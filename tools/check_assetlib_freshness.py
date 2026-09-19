#!/usr/bin/env python3
"""Notice when the Asset Library entry stops matching the release branch.

    python tools/check_assetlib_freshness.py
    python tools/check_assetlib_freshness.py --selftest

Releasing ends with a step nothing can do for us: pasting the new commit hash
into the Asset Library entry by hand. `release.yml` prints that hash to the job
summary, which is the right place to put it and the wrong place to rely on it. A
job summary is read once, in the minutes after a release, and never again.

When the entry stops matching, the failure is silent from every angle. The entry
looks fine, the download works, and it quietly hands out an old plugin. 0.3.2
shipped and the library went on serving the 0.3.0 tree, which is only visible by
clicking through and reading a version number on a web page nobody is looking at.

The queue is part of the answer
-------------------------------
An edit does not take effect when you submit it. It goes into a moderation queue
and a Godot moderator accepts it, so there is a window, possibly a long one,
where the paste has happened and the entry still serves the old commit. Comparing
the entry against the branch alone cannot tell that apart from a forgotten paste,
and would tell you to paste something you already pasted, which only adds a
second record to the queue.

So a divergence is only worth reporting once the pending edits have been read.
`GET /asset/edit?asset=<id>` lists them without authentication, and
`GET /asset/edit/<edit_id>` carries the `download_commit` each one would set.

That does mean an edit stuck in the queue forever reads as fine here. It is
reported with the time it has been waiting, but it does not fail: how fast a
volunteer moderator gets to it is not something a maintainer can act on, and
failing on it weekly is the kind of red that trains people to ignore red.
A rejected edit is the opposite and does fail, because that one needs doing
again and carries the reason why.

Why it does not just do the paste
---------------------------------
It could, nearly. The Asset Library has `POST /asset/{id}`, documented in
https://github.com/godotengine/godot-asset-library/blob/master/API.md. Two
things make it the wrong trade. The token comes from `POST /login`, which takes
a username and password and nothing else, so automating this means the
godotengine.org account password living in Actions secrets for the sake of a
once-a-release convenience. And the edit lands in the same moderation queue, so
it does not even remove the human. Recorded here because "there is no API" is
the obvious wrong answer and this is the second time it has been looked up.

Also worth not investigating a third time: the entry's **View files** button
points at the repository root, which shows `main`. That is not what installs
(the download is the `release` branch archive) but it looks alarming if you
click it expecting to see what ships. The Asset Library takes one repository URL
and uses it for browse, issues and download alike, so there is no field to aim
that button somewhere else, and pointing the whole entry at `/tree/release`
would fix browse and break issues. Left alone on purpose.
"""

from __future__ import annotations

import argparse
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from typing import NamedTuple

# https://godotengine.org/asset-library/asset/5449
ASSET_ID = 5449
API_ROOT = "https://godotengine.org/asset-library/api"
ENTRY_URL = f"{API_ROOT}/asset/{ASSET_ID}"
EDIT_URL = "https://godotengine.org/asset-library/asset/edit"

# The branch the Asset Library downloads, by commit hash. Never merged either
# way; see the header of .github/workflows/release.yml.
RELEASE_BRANCH = "release"

# How long a divergence is allowed to be normal. A release and its paste happen
# in the same sitting, so three days is generous rather than tight, and it is
# the whole of the false-alarm class this check would otherwise have.
GRACE_DAYS = 3

# A long queue is fine; an unbounded number of detail fetches is not.
MAX_EDITS_READ = 10

TIMEOUT_SECONDS = 30

# godotengine.org having a bad morning is not the entry being stale, but a
# check that shrugs at every failure is the silence it exists to break. So:
# retry the transient ones, then say so and fail.
RETRIES = 3
RETRY_WAIT_SECONDS = 5


class CheckError(Exception):
    """Something upstream was missing or the wrong shape."""


class PendingEdit(NamedTuple):
    """An unaccepted edit that would set the entry to `commit`."""

    edit_id: str
    status: str
    commit: str
    waiting_days: int
    reason: str


def _get_json(url: str, headers: dict[str, str] | None = None) -> dict:
    """Fetch and decode, retrying the failures that are worth retrying.

    A 5xx or a dropped connection on one Monday morning says nothing about the
    entry, and failing the run for it would be noise. A 4xx does say something:
    the entry has moved or gone, and no amount of waiting fixes that.
    """
    request = urllib.request.Request(url, headers=headers or {})
    request.add_header("User-Agent", "hammerforge-assetlib-freshness")
    last: CheckError | None = None
    for attempt in range(RETRIES):
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                return json.load(response)
        except urllib.error.HTTPError as err:
            if err.code < 500:
                raise CheckError(f"{url} returned HTTP {err.code}") from err
            last = CheckError(f"{url} returned HTTP {err.code}")
        except urllib.error.URLError as err:
            last = CheckError(f"{url} could not be reached: {err.reason}")
        except json.JSONDecodeError as err:
            raise CheckError(f"{url} did not return JSON") from err
        if attempt < RETRIES - 1:
            time.sleep(RETRY_WAIT_SECONDS)
    raise last or CheckError(f"{url} could not be read")


def is_sha(value: str) -> bool:
    return len(value) == 40 and all(c in "0123456789abcdef" for c in value.lower())


def parse_entry(payload: dict) -> tuple[str, str]:
    """The commit the library serves, and the version it calls it.

    Separated from the fetch so the shape can be checked without the network,
    and because an entry that answers with no commit at all is its own failure
    rather than a divergence.
    """
    commit = str(payload.get("download_commit") or "").strip()
    version = str(payload.get("version_string") or "").strip()
    if not commit:
        raise CheckError("the entry has no download_commit")
    if not is_sha(commit):
        raise CheckError(f"the entry's download_commit is not a sha: {commit!r}")
    return commit.lower(), version or "an unnamed version"


def verdict(
    entry_commit: str,
    entry_version: str,
    head_sha: str,
    head_subject: str,
    age_days: int,
    edit: PendingEdit | None,
) -> tuple[str, list[str]]:
    """current, submitted, rejected, pending or stale, and why."""
    head = head_sha.lower()
    if entry_commit.lower() == head:
        return "current", [
            f"The Asset Library is serving {entry_version}, "
            f"which is {head_sha[:7]}, the head of `{RELEASE_BRANCH}`."
        ]

    disagree = [
        f"The Asset Library entry and the `{RELEASE_BRANCH}` branch disagree.",
        "",
        f"    entry {ASSET_ID}   {entry_version} at {entry_commit[:7]}",
        f"    {RELEASE_BRANCH:<12} {head_subject} at {head_sha[:7]}, "
        f"pushed {_days(age_days)} ago",
    ]
    paste = ["", f"Paste {head_sha} into the Download Commit field at {EDIT_URL}"]

    if edit is not None and edit.commit.lower() == head:
        if edit.status == "rejected":
            said = f": {edit.reason}" if edit.reason else "."
            return "rejected", [
                *disagree,
                "",
                f"Edit {edit.edit_id} would have fixed this and was rejected{said}",
                *paste[1:],
            ]
        return "submitted", [
            *disagree,
            "",
            f"Nothing to do. Edit {edit.edit_id} is already in the queue with the "
            f"right commit, waiting {_days(edit.waiting_days)} for a moderator.",
        ]

    if age_days < GRACE_DAYS:
        return "pending", [
            *disagree,
            *paste,
            "",
            f"Not failing yet: a release younger than {GRACE_DAYS} days has not "
            "had a fair chance to be pasted.",
        ]
    return "stale", [*disagree, *paste]


def _days(count: int) -> str:
    return f"{count} day{'' if count == 1 else 's'}"


def _age_days(stamp: str) -> int:
    """Whole days between an Asset Library timestamp and now, never negative."""
    when = datetime.strptime(stamp.strip(), "%Y-%m-%d %H:%M:%S").replace(
        tzinfo=timezone.utc
    )
    return max((datetime.now(timezone.utc) - when).days, 0)


def _pending_edit(head_sha: str) -> PendingEdit | None:
    """The unsettled edit that would set the entry to `head_sha`, if there is one."""
    query = urllib.parse.urlencode({"asset": ASSET_ID})
    listing = _get_json(f"{API_ROOT}/asset/edit?{query}").get("result") or []
    for record in listing[:MAX_EDITS_READ]:
        status = str(record.get("status") or "").strip().lower()
        # Accepted means the entry already moved, so it cannot be the reason the
        # entry has not. Everything else is carried through, including a status
        # this does not know about: verdict() treats an unknown one as still in
        # flight rather than shouting about a state nobody has looked at, and
        # rejected is carried precisely so it can be shouted about.
        if status == "accepted":
            continue
        edit_id = str(record.get("edit_id") or "").strip()
        if not edit_id:
            continue
        detail = _get_json(f"{API_ROOT}/asset/edit/{edit_id}")
        commit = str(detail.get("download_commit") or "").strip().lower()
        if commit != head_sha.lower():
            continue
        try:
            waiting = _age_days(str(record.get("submit_date") or ""))
        except ValueError:
            waiting = 0
        return PendingEdit(
            edit_id=edit_id,
            status=status,
            commit=commit,
            waiting_days=waiting,
            reason=str(detail.get("reason") or "").strip(),
        )
    return None


def _release_head(repo: str) -> tuple[str, str, int]:
    """Sha, subject and age in days of the head of the release branch."""
    headers = {"Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN", "")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    payload = _get_json(
        f"https://api.github.com/repos/{repo}/commits/{RELEASE_BRANCH}", headers
    )
    sha = str(payload.get("sha") or "").strip()
    if not sha:
        raise CheckError(f"no sha for {repo}@{RELEASE_BRANCH}")
    commit = payload.get("commit") or {}
    # release.yml commits the tree as "HammerForge <version>", which makes the
    # message legible without a second call for plugin.cfg. A different subject
    # still reads fine, it just stops naming the version.
    subject = str(commit.get("message") or "").split("\n")[0].strip() or "a release"
    when = str((commit.get("committer") or {}).get("date") or "").strip()
    if not when:
        raise CheckError(f"no commit date for {repo}@{RELEASE_BRANCH}")
    pushed = datetime.fromisoformat(when.replace("Z", "+00:00"))
    return sha, subject, max((datetime.now(timezone.utc) - pushed).days, 0)


SHA_A = "395a272b30bb0d38aaba631d46271317946bea88"
SHA_B = "1dc1afee478191b992488497400dfeb83e65ebfa"


def _edit(status: str, commit: str, waiting: int = 1, reason: str = "") -> PendingEdit:
    return PendingEdit("24358", status, commit, waiting, reason)


# (name, entry commit, head sha, age in days, pending edit, expected state)
CASES = [
    ("matching commits are current", SHA_A, SHA_A, 0, None, "current"),
    ("matching stays current when old", SHA_A, SHA_A, 400, None, "current"),
    ("case does not decide it", SHA_A.upper(), SHA_A, 0, None, "current"),
    ("a fresh divergence is pending", SHA_A, SHA_B, 0, None, "pending"),
    ("the last day of grace is pending", SHA_A, SHA_B, GRACE_DAYS - 1, None, "pending"),
    ("the day grace runs out is stale", SHA_A, SHA_B, GRACE_DAYS, None, "stale"),
    ("a long divergence is stale", SHA_A, SHA_B, 13, None, "stale"),
    # The state this was actually in when it was written: pasted, queued, and
    # indistinguishable from a forgotten paste by the entry alone.
    (
        "a queued edit is not a forgotten paste",
        SHA_A,
        SHA_B,
        13,
        _edit("new", SHA_B),
        "submitted",
    ),
    (
        "an unknown status counts as queued",
        SHA_A,
        SHA_B,
        13,
        _edit("in_review", SHA_B),
        "submitted",
    ),
    (
        "a rejected edit needs doing again",
        SHA_A,
        SHA_B,
        13,
        _edit("rejected", SHA_B, reason="bad icon"),
        "rejected",
    ),
    # A queued edit that sets some other commit says nothing about this one.
    (
        "a queued edit for another commit does not count",
        SHA_A,
        SHA_B,
        13,
        _edit("new", SHA_A),
        "stale",
    ),
    (
        "a queued edit does not rescue a fresh divergence into silence",
        SHA_A,
        SHA_B,
        0,
        _edit("new", SHA_A),
        "pending",
    ),
]

# (name, payload, expected commit, or None when it should be refused)
ENTRY_CASES = [
    ("a normal entry", {"download_commit": SHA_A, "version_string": "0.3.0"}, SHA_A),
    ("upper case is accepted", {"download_commit": SHA_A.upper()}, SHA_A),
    ("no commit at all", {"version_string": "0.3.0"}, None),
    ("a null commit", {"download_commit": None}, None),
    ("an empty commit", {"download_commit": "   "}, None),
    ("a branch name is not a sha", {"download_commit": RELEASE_BRANCH}, None),
    ("a short sha is not a sha", {"download_commit": SHA_A[:7]}, None),
    ("not hex", {"download_commit": "z" * 40}, None),
]


def selftest() -> int:
    failures = 0
    for name, entry_commit, head_sha, age_days, edit, expected in CASES:
        state, lines = verdict(
            entry_commit, "0.0.0", head_sha, "HammerForge 0.0.0", age_days, edit
        )
        if state != expected:
            print(f"selftest: {name} should be {expected}, got {state}")
            failures += 1
        elif not lines:
            print(f"selftest: {name} returned no explanation")
            failures += 1

    for name, payload, expected in ENTRY_CASES:
        try:
            got: str | None = parse_entry(payload)[0]
        except CheckError:
            got = None
        if got != expected:
            print(f"selftest: {name} should be {expected}, got {got}")
            failures += 1

    total = len(CASES) + len(ENTRY_CASES)
    if failures:
        print(f"selftest: {failures} of {total} cases wrong")
        return 1
    print(f"selftest: {total} cases correct")
    return 0


def _report(lines: list[str]) -> None:
    body = "\n".join(lines)
    print(body)
    summary = os.environ.get("GITHUB_STEP_SUMMARY", "")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"### Asset Library\n\n{body}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Asset Library freshness check")
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check the detector still catches each way this goes wrong",
    )
    args = parser.parse_args()
    if args.selftest:
        return selftest()

    repo = os.environ.get("GITHUB_REPOSITORY", "saworbit/hammerforge")
    try:
        entry_commit, entry_version = parse_entry(_get_json(ENTRY_URL))
        head_sha, head_subject, age_days = _release_head(repo)
        edit = None
        if entry_commit != head_sha.lower():
            edit = _pending_edit(head_sha)
    except CheckError as err:
        # Already retried, so this is not a blip. A check that cannot reach what
        # it checks and reports success is the exact failure this exists to
        # catch, one level up: green forever while nobody is looking.
        print(f"::error::could not compare the Asset Library entry: {err}")
        return 1

    state, lines = verdict(
        entry_commit, entry_version, head_sha, head_subject, age_days, edit
    )
    _report(lines)
    if state == "stale":
        print(f"::error::the Asset Library entry has been stale for {_days(age_days)}")
        return 1
    if state == "rejected":
        print("::error::the Asset Library edit that would fix this was rejected")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
