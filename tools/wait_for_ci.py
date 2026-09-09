#!/usr/bin/env python3
"""Wait for a pull request's CI run, keyed to the commit rather than the branch.

Waiting on a branch is the obvious thing and it is wrong three ways, all of
which happened while landing #265 to #270:

  - `gh run list --branch X` returns the newest run on that branch, which is
    often the *previous* one. Merging on that answer merges a commit nothing
    graded. It reported success on a superseded run once and was caught by
    luck.
  - `git rev-parse HEAD` is not the pull request's head. The local checkout
    drifts -- `gh pr merge` can leave you on main -- and then the wait grades
    main's tip and reports green for a branch it never looked at.
  - Polling until no check is `pending` treats "the workflows have not been
    created yet" as "everything passed", because zero pending is also what an
    empty list looks like.

The fourth is the worst, because it looks like a pass: ci.yml pushes a counts
commit to the pull request when the published test totals move, so the head can
change *during* the wait. A commit that was green a moment ago is then no longer
what would merge. This one is not hypothetical -- it happened on #271 while this
script was watching it, and the log reads:

    #271 head b267dc2
    #271 head moved b267dc2 -> f2ae5fa, waiting on the new commit
    #271 CI failed on f2ae5fa

f2ae5fa was CI's own "Update published test counts". A branch-keyed wait would
have graded b267dc2 and called it green. This re-reads the head every poll and
starts over on the new commit rather than reporting on the old one.

    python tools/wait_for_ci.py 270
    python tools/wait_for_ci.py 270 --workflow CI --timeout 1800

Exits 0 only when the named workflow concluded successfully on the commit that
is still the pull request's head. Exits 1 on failure, timeout, or a missing
`gh`.

--selftest exercises the run-picking and verdict logic against fixtures,
including a run carrying the wrong commit, because a guard that cannot fail is
not a guard.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time

# The workflow whose conclusion decides whether the branch may merge. The others
# on a pull request here are Labeler and a Dependabot auto-merge that skips.
DEFAULT_WORKFLOW = "CI"

# Long enough for a full Godot suite run plus queueing, short enough that a
# wedged run does not hold a session open indefinitely.
DEFAULT_TIMEOUT_SECONDS = 2700

POLL_SECONDS = 30


class GhError(RuntimeError):
    """`gh` is missing, unauthenticated, or answered with something unusable."""


def _gh(args: list[str]) -> str:
    try:
        done = subprocess.run(
            ["gh", *args],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError as exc:
        raise GhError("gh is not on PATH") from exc
    if done.returncode != 0:
        raise GhError("gh %s failed: %s" % (" ".join(args), done.stderr.strip()))
    return done.stdout


def _gh_json(args: list[str]):
    raw = _gh(args)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise GhError("gh %s did not return JSON" % " ".join(args)) from exc


def head_sha(pr: int) -> str:
    """The pull request's head commit, as GitHub currently has it.

    Deliberately not `git rev-parse HEAD`: the local checkout is not the
    authority on what a pull request would merge, and frequently is not even on
    the branch.
    """
    data = _gh_json(["pr", "view", str(pr), "--json", "headRefOid"])
    sha = str(data.get("headRefOid", ""))
    if len(sha) != 40:
        raise GhError("pull request %d has no usable head commit" % pr)
    return sha


def runs_for(sha: str) -> list[dict]:
    """Workflow runs GitHub associates with one commit.

    `--commit` wants the full forty characters. An abbreviated one matches
    nothing and returns an empty list, which is indistinguishable from "no run
    yet" -- so callers must pass what `head_sha()` gave them.
    """
    return _gh_json(
        [
            "run",
            "list",
            "--commit",
            sha,
            "--limit",
            "20",
            "--json",
            "workflowName,headSha,status,conclusion,databaseId",
        ]
    )


def select_run(runs: list[dict], sha: str, workflow: str) -> dict | None:
    """The named workflow's run on this exact commit, or None.

    The commit is checked again here rather than trusted from the query. A run
    reported against another commit is somebody else's answer.
    """
    for run in runs:
        if run.get("workflowName") != workflow:
            continue
        if str(run.get("headSha", "")) != sha:
            continue
        return run
    return None


def verdict(run: dict | None) -> str:
    """One of "waiting", "success" or "failure".

    A missing run is "waiting", never "success": before the workflow exists
    there is no evidence either way, and reading an absent run as a pass is the
    bug that let an ungraded commit look ready to merge.
    """
    if run is None:
        return "waiting"
    if run.get("status") != "completed":
        return "waiting"
    return "success" if run.get("conclusion") == "success" else "failure"


def wait(
    pr: int,
    workflow: str = DEFAULT_WORKFLOW,
    timeout: int = DEFAULT_TIMEOUT_SECONDS,
    poll: int = POLL_SECONDS,
    sleeper=time.sleep,
    clock=time.monotonic,
    resolve_head=head_sha,
    fetch_runs=runs_for,
) -> int:
    deadline = clock() + timeout
    sha = resolve_head(pr)
    print("#%d head %s" % (pr, sha[:7]), flush=True)

    while True:
        current = resolve_head(pr)
        if current != sha:
            # ci.yml commits the published test counts to the branch, so this is
            # ordinary rather than alarming. The old commit's result is now
            # about something that will not merge.
            print(
                "#%d head moved %s -> %s, waiting on the new commit"
                % (pr, sha[:7], current[:7]),
                flush=True,
            )
            sha = current

        state = verdict(select_run(fetch_runs(sha), sha, workflow))
        if state == "success":
            # Read the head once more before answering. A counts commit landing
            # between the fetch above and this line would otherwise be reported
            # green on the strength of the commit it replaced.
            settled = resolve_head(pr)
            if settled != sha:
                print(
                    "#%d head moved to %s as it passed, regrading" % (pr, settled[:7]),
                    flush=True,
                )
                sha = settled
                sleeper(poll)
                continue
            print("#%d %s passed on %s" % (pr, workflow, sha[:7]), flush=True)
            return 0
        if state == "failure":
            print("#%d %s failed on %s" % (pr, workflow, sha[:7]), flush=True)
            return 1

        if clock() >= deadline:
            print(
                "#%d %s did not finish on %s within %ds"
                % (pr, workflow, sha[:7], timeout),
                flush=True,
            )
            return 1
        sleeper(poll)


# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------

_SHA = "a" * 40
_OTHER = "b" * 40


def _selftest() -> int:
    failures: list[str] = []
    ran = 0

    def check(name: str, got, want) -> None:
        nonlocal ran
        ran += 1
        if got != want:
            failures.append("%s: got %r, wanted %r" % (name, got, want))

    done = {
        "workflowName": "CI",
        "headSha": _SHA,
        "status": "completed",
        "conclusion": "success",
    }
    check("picks the run on this commit", select_run([done], _SHA, "CI"), done)

    # The failure that merged nothing but nearly did: a green run belonging to
    # some other commit on the same branch.
    stale = dict(done, headSha=_OTHER)
    check("refuses another commit's run", select_run([stale], _SHA, "CI"), None)
    check(
        "refuses another commit's run",
        verdict(select_run([stale], _SHA, "CI")),
        "waiting",
    )

    other = dict(done, workflowName="Labeler")
    check("refuses another workflow", select_run([other], _SHA, "CI"), None)

    # Zero runs is "not yet", which is the distinction the pending-count check
    # collapsed.
    check("no runs is waiting", verdict(select_run([], _SHA, "CI")), "waiting")
    check(
        "queued is waiting",
        verdict({"status": "queued", "conclusion": None}),
        "waiting",
    )
    check(
        "in progress is waiting",
        verdict({"status": "in_progress", "conclusion": None}),
        "waiting",
    )
    check("success is success", verdict(done), "success")
    check(
        "failure is failure",
        verdict(dict(done, conclusion="failure")),
        "failure",
    )
    check(
        "cancelled is failure",
        verdict(dict(done, conclusion="cancelled")),
        "failure",
    )

    # The whole loop, against a head that moves under it the way ci.yml's counts
    # commit moves one. The green run on the commit it started from must not be
    # the answer.
    moved = dict(done, headSha=_OTHER)
    graded: list[str] = []

    def _record(sha: str) -> list[dict]:
        graded.append(sha)
        return [moved] if sha == _OTHER else [done]

    heads = [_SHA, _OTHER]
    check(
        "a moved head is graded on the new commit",
        wait(
            1,
            poll=0,
            sleeper=lambda _: None,
            clock=lambda: 0.0,
            resolve_head=lambda _pr: heads.pop(0) if heads else _OTHER,
            fetch_runs=_record,
        ),
        0,
    )
    check("the new commit is the one graded", graded, [_OTHER])

    # Green on the commit it started from, but the head moved while that answer
    # was in flight. Reporting the old commit's pass here is the failure mode
    # this whole script exists to refuse.
    late: list[str] = []

    def _late_head(_pr: int) -> str:
        late.append("read")
        # First two reads say A, so the loop grades A and finds it green. The
        # confirming read says B.
        return _SHA if len(late) <= 2 else _OTHER

    check(
        "a pass on a superseded commit is not reported",
        wait(
            1,
            poll=0,
            sleeper=lambda _: None,
            clock=lambda: 0.0,
            resolve_head=_late_head,
            fetch_runs=lambda sha: [done] if sha == _SHA else [moved],
        ),
        0,
    )
    check("it went on to grade the newer commit", len(late) > 3, True)

    # A run that never completes must time out rather than report either way.
    ticks = [0.0, 0.0, 99.0]
    check(
        "an unfinished run times out",
        wait(
            1,
            timeout=1,
            poll=0,
            sleeper=lambda _: None,
            clock=lambda: ticks.pop(0) if ticks else 99.0,
            resolve_head=lambda _pr: _SHA,
            fetch_runs=lambda _sha: [],
        ),
        1,
    )

    if failures:
        for line in failures:
            print("selftest: %s" % line, file=sys.stderr)
        return 1
    print("selftest: %d checks passed" % ran)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("pr", nargs="?", type=int, help="pull request number")
    parser.add_argument("--workflow", default=DEFAULT_WORKFLOW)
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_SECONDS)
    parser.add_argument("--poll", type=int, default=POLL_SECONDS)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)

    if args.selftest:
        return _selftest()
    if args.pr is None:
        parser.error("a pull request number is required")

    try:
        return wait(args.pr, args.workflow, args.timeout, args.poll)
    except GhError as exc:
        print("wait_for_ci: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
