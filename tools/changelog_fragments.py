#!/usr/bin/env python3
"""Keep each pull request's changelog lines in a file of its own.

    python tools/changelog_fragments.py --check
    python tools/changelog_fragments.py --preview
    python tools/changelog_fragments.py --compile
    python tools/changelog_fragments.py --require origin/main
    python tools/changelog_fragments.py --selftest

Every pull request used to add its line at the top of the same list in
CHANGELOG.md, under this week. Any two open pull requests then conflicted on
those lines, so a batch landed one at a time, each merging main back in and
waiting for CI again (#917). Git's `merge=union` driver is no way out: GitHub's
merge button and its mergeability check ignore .gitattributes merge drivers.

So a pull request adds a fragment instead, `changelog.d/<slug>.<kind>.md`, and
leaves CHANGELOG.md alone. The kind is added, changed, deprecated, removed,
fixed, security or behind (Behind the scenes). Each line of the file is one
entry, `- What changed.`, with an optional bracket of the issues it closes at
the end. It has no date and no pull request link, because neither is known
until it merges.

`--compile` runs later, on a branch cut from main, and finds the commit that
added each fragment. Pull requests land as squash commits whose subject ends
`(#N)`, which gives the pull request. The commit's author date, in its own
timezone, gives the day: the changelog dates a change by the local day it
merged, and GitHub writes the committer date in UTC, which is a day early for a
morning merge in Sydney. Compile writes each line into its week and category
under `## [Unreleased]`, newest first, and deletes the fragments. It refuses a
fragment that is not committed or whose commit names no pull request, and it
writes nothing that `check_changelog.py` would reject.

`--preview` prints the `[Unreleased]` section compile would write, without
writing anything. A fragment that has not merged yet is dated today and linked
to `PR #?`, which compile would refuse.

`--check` is what CI runs. It holds every fragment to what compile can turn
into a line `check_changelog.py` accepts, the 200 character limit included,
counted with the longest date and a 4 digit pull request.

`--require BASE` is what CI runs on a pull request. A change to the addon or
the server used to pass with no fragment at all, and was missing from the
changelog until someone noticed (#1297). This fails when the changes since BASE
touch `addons/hammerforge/` or `hammerforge_mcp/src/` and add no fragment; the
`no-changelog` label on the pull request waives it for a refactor or a
test-only change. Docs, tests and tooling are never asked. Only an added
fragment counts. A deleted or edited one used to count too, so a change that
only touched someone else's fragment passed with no line of its own (#1487).
The one change that deletes fragments and brings none is a compile, which
writes CHANGELOG.md in the same change, and that is not asked.

`--selftest` breaks a good fragment once per rule, compiles fragments in a
throwaway repository, and asks for a fragment where it should.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from unittest import mock

import check_changelog as cl

REPO = cl.REPO
FOLDER = cl.FRAGMENTS.name
README = "README.md"
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*\.([a-z]+)\.md$")
DATED_RE = re.compile(rf"^\*\*\d{{1,2}} ({cl.MONTH})\*\*")
PULL_RE = re.compile(r"\bPRs? [\[#]|/pull/\d")
SUBJECT_PR_RE = re.compile(r"\(#(\d+)\)$")
# The longest a line can read once compiled: a two digit day, and a pull
# request number as long as the ones being opened now.
LONGEST_DAY = dt.date(2026, 9, 28)
LONGEST_PR = 9999
UNKNOWN_PR = "PR #?"
ONE_ENTRY = (
    "each line is one entry, `- What changed.`; the detail goes in the pull"
    " request description"
)


@dataclass
class Fragment:
    rel: str
    path: Path
    category: str
    entries: list[str]


@dataclass
class Placed:
    """A fragment with the day it merged and the pull request that merged it."""

    fragment: Fragment
    day: dt.date
    pr: str
    order: float


def pr_link(number: int) -> str:
    return f"PR [#{number}]({cl.REPO_URL}pull/{number})"


def entry_line(text: str, day: dt.date, pr: str) -> str:
    """The changelog line a fragment's entry becomes."""
    # Into the closing bracket of issues if there is one, or a bracket of its own.
    body = f"{text[:-1]}, {pr})" if cl.REFS_RE.search(text) else f"{text} ({pr})"
    return f"- **{day.day} {cl.MONTHS[day.month - 1]}** {body}"


def check_entry(line: str) -> list[str]:
    """Why one line of a fragment would not compile to an accepted entry."""
    text = line[2:]
    if not line.startswith("- ") or not text.strip() or text != text.lstrip():
        return [ONE_ENTRY]
    problems = []
    if DATED_RE.match(text):
        problems.append("leave the date out; compile adds the day it merged")
    if PULL_RE.search(text):
        problems.append(
            "leave the pull request out; compile adds the one that merged this"
        )
    refs = cl.REFS_RE.search(text)
    head = text[: refs.start()] if refs else text
    if cl.LINK_RE.search(head):
        problems.append("links go in the bracket at the end, `(issue [#N](...))`")
    if refs:
        problems += check_bracket(refs.group(1))
    line = entry_line(text, LONGEST_DAY, pr_link(LONGEST_PR))
    found = cl.ENTRY_RE.match(line)
    if found is None:
        problems.append(f"this would not compile to a changelog line: {line}")
        return problems
    length = len(cl.visible(" ".join(found.groups())))
    if length > cl.MAX_VISIBLE:
        problems.append(
            f"{length} characters as it will read with its date and a 4 digit"
            f" pull request, over {cl.MAX_VISIBLE}; say what changed and leave"
            " the how to the pull request"
        )
    return problems


def check_bracket(refs: str) -> list[str]:
    """The closing bracket names issues of this repository, and nothing else."""
    word = refs.split(" ", 1)[0]
    links = cl.LINK_RE.findall(refs)
    if word.startswith("PR") or any("/pull/" in url for _, url in links):
        return []  # check_entry has already said to leave the PR out
    if word.startswith("commit"):
        return ["the bracket names issues only; compile adds the pull request"]
    problems = []
    for label, url in links:
        found = cl.REPO_LINK_RE.match(url)
        if not found or found.group(1) != "issues":
            problems.append(f"{url} is not an issue of this repository")
        elif label != f"#{found.group(2)}":
            problems.append(f"the label {label} does not match its link {url}")
    want = "issue" if len(links) == 1 else "issues"
    shape = f"{want} " + ", ".join(f"[{label}]({url})" for label, url in links)
    if refs != shape:
        problems.append(
            "one issue reads `(issue [#N](...))` and more read"
            " `(issues [#N](...), [#M](...))`"
        )
    return problems


# A change under these asks for a fragment: the addon is what ships, and the
# server is what an agent runs. Everything else (docs, tests, tooling, the
# dev-only capture plugin) is Behind the scenes at most, and not asked for one.
ASKED = ("addons/hammerforge/", "hammerforge_mcp/src/")
WAIVER = "no-changelog"
CHANGELOG = "CHANGELOG.md"


def is_fragment(path: str) -> bool:
    folder, _, name = path.rpartition("/")
    return folder == FOLDER and name != README and NAME_RE.match(name) is not None


def compiles(changed: dict[str, str]) -> bool:
    """Whether these changes are a compile: the changelog written, fragments gone.

    Compile deletes every fragment it writes in, and the release pull request
    carries it, so a change with deleted fragments and CHANGELOG.md is the one
    that may bring none.
    """
    fragments = [status for path, status in changed.items() if is_fragment(path)]
    return (
        CHANGELOG in changed
        and bool(fragments)
        and all(status == "D" for status in fragments)
    )


def fragment_missing(changed: dict[str, str]) -> str | None:
    """Why these changes need a fragment they do not bring, or None.

    changed maps each path to its git status letter: A added, M edited,
    D deleted, R renamed onto that path. Only an added fragment is a line of
    the change's own.
    """
    asked = sorted(path for path in changed if path.startswith(ASKED))
    brought = any(
        status == "A" and is_fragment(path) for path, status in changed.items()
    )
    if not asked or brought or compiles(changed):
        return None
    shown = ", ".join(asked[:3]) + (", ..." if len(asked) > 3 else "")
    return (
        f"This changes {shown} and adds no fragment under {FOLDER}/. Add one, or"
        f" put the {WAIVER} label on the pull request for a refactor or a"
        " test-only change."
    )


def changed_since(root: Path, base: str) -> dict[str, str]:
    """Each path changed since the branch left base, with its status letter.

    From the merge base where the history is there, so a base that moved on
    is not counted against the branch. A pull request's merge commit checked
    out at depth 1 has no history to find one in, and there base's tip is the
    merge commit's own parent, which is the same thing. Untracked files count
    as added, so the check is useful before the commit too. A rename is found
    as one, so moving a fragment to a new name does not read as adding one.
    """
    found = subprocess.run(
        ["git", "merge-base", base, "HEAD"],
        cwd=root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    since = found.stdout.strip() if found.returncode == 0 else base
    committed = git(root, "diff", "--name-status", "--find-renames", since or base)
    changed: dict[str, str] = {}
    for line in committed.splitlines():
        fields = line.split("\t")
        if len(fields) >= 2:
            # A rename or copy lists the old path, then the new one.
            changed[fields[-1].strip()] = fields[0][:1]
    untracked = git(root, "ls-files", "--others", "--exclude-standard")
    for line in untracked.splitlines():
        if line.strip():
            changed[line.strip()] = "A"
    return changed


def require_fragment(root: Path, base: str) -> list[str]:
    problem = fragment_missing(changed_since(root, base))
    return [problem] if problem else []


def read_fragments(root: Path) -> tuple[list[Fragment], list[str]]:
    """Every fragment in changelog.d/, and every way one breaks the rules."""
    folder = root / FOLDER
    fragments: list[Fragment] = []
    problems: list[str] = []
    if not folder.is_dir():
        return fragments, problems
    for path in sorted(folder.iterdir()):
        rel = f"{FOLDER}/{path.name}"
        if path.name == README:
            continue
        if path.is_dir():
            problems.append(f"{rel}: {FOLDER}/ holds fragments, not folders")
            continue
        found = NAME_RE.match(path.name)
        if not found:
            problems.append(
                f"{rel}: name a fragment `<slug>.<kind>.md`, the slug in"
                " lowercase letters, digits and hyphens"
            )
            continue
        category = cl.FRAGMENT_KINDS.get(found.group(1))
        if category is None:
            problems.append(
                f"{rel}: `{found.group(1)}` is not a kind; use one of "
                + ", ".join(cl.FRAGMENT_KINDS)
            )
            continue
        try:
            text = path.read_bytes().decode("utf-8").replace("\r\n", "\n")
        except UnicodeDecodeError:
            problems.append(f"{rel}: save it as UTF-8")
            continue
        if text.startswith("﻿"):
            problems.append(f"{rel}: save it as UTF-8 without a byte order mark")
            text = text[1:]
        entries = []
        for number, line in enumerate(text.split("\n"), 1):
            if not line.strip():
                continue
            if line != line.rstrip():
                problems.append(f"{rel}:{number}: trailing whitespace")
                line = line.rstrip()
            problems += [f"{rel}:{number}: {p}" for p in check_entry(line)]
            entries.append(line[2:])
        if not entries:
            problems.append(f"{rel}: a fragment holds at least one `- ` line")
        fragments.append(Fragment(rel, path, category, entries))
    return fragments, problems


def git(root: Path, *args: str) -> str:
    done = subprocess.run(
        ["git", *args],
        cwd=root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if done.returncode:
        raise SystemExit(f"git {' '.join(args)} failed: {done.stderr.strip()}")
    return done.stdout


def place(
    root: Path, fragments: list[Fragment], strict: bool
) -> tuple[list[Placed], list[str]]:
    """Date each fragment and name its pull request, from the commit that added it.

    Strict is compile: a fragment that has not merged through a pull request is
    an error. Otherwise it is dated today and linked to PR #?.
    """
    changed = set(git(root, "diff", "--name-only", "HEAD", "--", FOLDER).split())
    placed, problems = [], []
    for fragment in fragments:
        added = ""
        if fragment.rel not in changed:
            added = git(
                root,
                "log",
                "-1",
                "--no-renames",
                "--diff-filter=A",
                "--format=%h%x1f%aI%x1f%s",
                "--",
                fragment.rel,
            ).strip()
        if not added:
            if strict:
                problems.append(
                    f"{fragment.rel}: commit it first; compile reads the day and"
                    " the pull request from the commit that added it"
                )
            placed.append(Placed(fragment, dt.date.today(), UNKNOWN_PR, 1e18))
            continue
        commit, iso, subject = added.split("\x1f", 2)
        merged = dt.datetime.fromisoformat(iso)
        number = SUBJECT_PR_RE.search(subject)
        if number is None:
            if strict:
                problems.append(
                    f"{fragment.rel}: added by {commit} `{subject}`, which names no"
                    " pull request; compile on a branch cut from main, after the"
                    " pull request is squash-merged"
                )
            placed.append(Placed(fragment, dt.date.today(), UNKNOWN_PR, 1e18))
            continue
        # The author date keeps the merger's timezone, so .date() is their day.
        pr = pr_link(int(number.group(1)))
        placed.append(Placed(fragment, merged.date(), pr, merged.timestamp()))
    return placed, problems


@dataclass
class WeekBlock:
    monday: dt.date
    lists: dict[str, list[str]] = field(default_factory=dict)


@dataclass
class Unreleased:
    """CHANGELOG.md cut around the `## [Unreleased]` weeks compile adds to."""

    above: list[str]
    preamble: list[str]
    weeks: list[WeekBlock]
    below: list[str]

    @classmethod
    def read(cls, text: str) -> Unreleased:
        # Only ever called on a changelog check_changelog.py accepts.
        lines = text.split("\n")
        start = lines.index("## [Unreleased]")
        end = next(
            (i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")),
            len(lines),
        )
        section = cls(lines[: start + 1], [], [], lines[end:])
        week, category = None, ""
        for line in lines[start + 1 : end]:
            if line.startswith("### "):
                day, month, year = cl.WEEK_RE.match(line).groups()
                monday = dt.date(int(year), cl.MONTHS.index(month) + 1, int(day))
                week = WeekBlock(monday)
                section.weeks.append(week)
            elif week is None:
                section.preamble.append(line)
            elif line.startswith("#### "):
                category = line[5:]
                week.lists[category] = []
            elif line.strip():
                week.lists[category].append(line)
        return section

    def add(self, category: str, day: dt.date, line: str) -> None:
        """Put a line in its week and category, above anything not newer."""
        monday = day - dt.timedelta(days=day.weekday())
        week = next((w for w in self.weeks if w.monday == monday), None)
        if week is None:
            week = WeekBlock(monday)
            at = next(
                (i for i, w in enumerate(self.weeks) if w.monday < monday),
                len(self.weeks),
            )
            self.weeks.insert(at, week)
        entries = week.lists.setdefault(category, [])
        at = next(
            (i for i, e in enumerate(entries) if self.day_of(e, week) <= day),
            len(entries),
        )
        entries.insert(at, line)

    @staticmethod
    def day_of(entry: str, week: WeekBlock) -> dt.date:
        day, month, _ = cl.ENTRY_RE.match(entry).groups()
        return cl.entry_date(int(day), month, cl.Week(week.monday, 0))

    def section(self) -> list[str]:
        """`## [Unreleased]` and everything under it, laid out as the file is."""
        out = [self.above[-1], ""]
        preamble = "\n".join(self.preamble).strip("\n")
        if preamble:
            out += [*preamble.split("\n"), ""]
        for week in self.weeks:
            out += [f"### Week of {cl.short(week.monday)}", ""]
            for name in cl.CATEGORIES:
                if name in week.lists:
                    out += [f"#### {name}", "", *week.lists[name], ""]
        return out

    def text(self) -> str:
        return "\n".join(self.above[:-1] + self.section() + self.below)


def compiled(root: Path, strict: bool) -> tuple[str, list[Placed], list[str]]:
    """CHANGELOG.md with every fragment written in, and what stops that."""
    fragments, problems = read_fragments(root)
    if problems:
        return "", [], problems
    text = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    broken = cl.check(text, root)
    if broken:
        return "", [], ["CHANGELOG.md fails check_changelog.py already:", *broken]
    if "## [Unreleased]" not in text.split("\n"):
        return "", [], ["CHANGELOG.md has no `## [Unreleased]` to compile into"]
    placed, problems = place(root, fragments, strict)
    if problems:
        return "", [], problems
    section = Unreleased.read(text)
    for item in sorted(placed, key=lambda p: (p.order, p.fragment.rel)):
        # Newer lines go on top, so a fragment's own lines go in bottom first.
        for entry in reversed(item.fragment.entries):
            line = entry_line(entry, item.day, item.pr)
            section.add(item.fragment.category, item.day, line)
    return section.text(), placed, []


def compile_fragments(root: Path) -> list[str]:
    """Write the fragments into CHANGELOG.md and delete them, or say why not."""
    text, placed, problems = compiled(root, strict=True)
    if problems:
        return problems
    after = cl.check(text, root)
    if after:
        return ["the compiled changelog fails check_changelog.py:", *after]
    (root / "CHANGELOG.md").write_text(text, encoding="utf-8", newline="\n")
    for item in placed:
        item.fragment.path.unlink()
    return []


def preview(root: Path) -> tuple[str, list[str]]:
    text, _, problems = compiled(root, strict=False)
    if problems:
        return "", problems
    return "\n".join(Unreleased.read(text).section()), []


# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------

ISSUE = cl.REPO_URL + "issues/"
PR = cl.REPO_URL + "pull/"
GOOD_NAME = "bake-connector.fixed.md"
GOOD = (
    "- Bake Changed builds a paint connector confirmed after the last bake;"
    f" it said nothing had changed. (issue [#1255]({ISSUE}1255))"
)
BRACKET = f"(issue [#1255]({ISSUE}1255))"
# 183 characters of text and its bracket read as exactly 200 once compiled.
FITS = "- " + "x" * 169 + f" {BRACKET}"

# (name, file name, contents, a phrase the report must contain)
CASES = (
    ("an uppercase name", "Bake.fixed.md", GOOD, "name a fragment"),
    ("a name with no kind", "bake-connector.md", GOOD, "name a fragment"),
    ("a file that is not Markdown", "bake.fixed.txt", GOOD, "name a fragment"),
    ("an unknown kind", "bake.bugfix.md", GOOD, "`bugfix` is not a kind"),
    ("a folder", "old/", "", "not folders"),
    ("an empty fragment", GOOD_NAME, "\n", "at least one"),
    ("a line with no dash", GOOD_NAME, GOOD[2:], "each line is one entry"),
    ("a wrapped line", GOOD_NAME, f"{GOOD}\n  and how.", "each line is one entry"),
    ("a dash and nothing else", GOOD_NAME, "-", "each line is one entry"),
    ("two spaces after the dash", GOOD_NAME, "- " + GOOD[1:], "each line is one entry"),
    ("trailing whitespace", GOOD_NAME, GOOD + " ", "trailing whitespace"),
    ("a byte order mark", GOOD_NAME, "﻿" + GOOD, "byte order mark"),
    ("not UTF-8", GOOD_NAME, b"- caf\xe9", "save it as UTF-8"),
    (
        "a date already in it",
        GOOD_NAME,
        GOOD.replace("- Bake", "- **17 Oct** Bake"),
        "leave the date out",
    ),
    (
        "a pull request in the bracket",
        GOOD_NAME,
        GOOD.replace("1255))", f"1255), PR [#1290]({PR}1290))"),
        "leave the pull request out",
    ),
    (
        "a bracket of only a pull request",
        GOOD_NAME,
        GOOD.replace(BRACKET, f"(PR [#1290]({PR}1290))"),
        "leave the pull request out",
    ),
    (
        "an issue in another repository",
        GOOD_NAME,
        GOOD.replace(ISSUE, "https://github.com/elsewhere/repo/issues/"),
        "not an issue of this repository",
    ),
    (
        "a label that names another issue",
        GOOD_NAME,
        GOOD.replace(f"{ISSUE}1255", f"{ISSUE}1256"),
        "label #1255 does not match",
    ),
    (
        "a link in the text",
        GOOD_NAME,
        GOOD.replace("the last bake", "the [last bake](docs/bake.md)"),
        "links go in the bracket",
    ),
    (
        "a commit in the bracket",
        GOOD_NAME,
        GOOD.replace(BRACKET, f"(commit [abc1234]({cl.REPO_URL}commit/abc1234))"),
        "names issues only",
    ),
    (
        "two issues under `issue`",
        GOOD_NAME,
        GOOD.replace("1255))", f"1255), [#1256]({ISSUE}1256))"),
        "more read",
    ),
    (
        "a line that fits until the date and pull request go in",
        GOOD_NAME,
        FITS.replace("x ", "xx "),
        "201 characters as it will read",
    ),
)


def write_fragment(folder: Path, name: str, contents: str | bytes) -> None:
    if name.endswith("/"):
        (folder / name).mkdir()
    elif isinstance(contents, bytes):
        (folder / name).write_bytes(contents)
    else:
        (folder / name).write_text(contents + "\n", encoding="utf-8", newline="\n")


def check_cases() -> int:
    """Break a good fragment once per rule."""
    failures = 0
    for name, file_name, contents, phrase in [
        ("a good fragment", GOOD_NAME, GOOD, ""),
        ("a line exactly at the limit", GOOD_NAME, FITS, ""),
        *CASES,
    ]:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / FOLDER
            folder.mkdir()
            write_fragment(folder, README, "# Not a fragment\n\n- Not an entry")
            write_fragment(folder, file_name, contents)
            _, problems = read_fragments(Path(tmp))
        if not phrase and problems:
            print(f"selftest: {name} was rejected: {problems}")
            failures += 1
        elif phrase and not any(phrase in problem for problem in problems):
            print(f"selftest: {name} went unreported as {phrase!r}; got {problems}")
            failures += 1
    return failures


GLANCE = (
    f"{cl.GLANCE_HEADER}\n|---|---|---|---|---|---|---|---|---|\n"
    "| 0.1.0 | 2 Oct 2026 | 2 Oct 2026 | 0 | 0 | 0 | 1 | 0 | 1 |"
)
RELEASED = f"""## [0.1.0] - 2026-10-02

### Week of 28 Sep 2026

#### Fixed

- **2 Oct** The first fix. (PR [#2]({PR}2))
"""
BEFORE = f"""# Changelog

## At a glance

{GLANCE}

## [Unreleased]

**Highlights so far**

- Something people will notice.

### Week of 5 Oct 2026

#### Fixed

- **6 Oct** A thing works again. (PR [#12]({PR}12))

{RELEASED}"""
AFTER = f"""# Changelog

## At a glance

{GLANCE}

## [Unreleased]

**Highlights so far**

- Something people will notice.

### Week of 12 Oct 2026

#### Fixed

- **12 Oct** A door opens again. (issue [#30]({ISSUE}30), PR [#31]({PR}31))

### Week of 5 Oct 2026

#### Added

- **7 Oct** Lights can start dark. (PR [#33]({PR}33))
- **7 Oct** The dock says which lights start dark. (PR [#33]({PR}33))

#### Fixed

- **6 Oct** The bake finishes, every time. (PR [#32]({PR}32))
- **6 Oct** A thing works again. (PR [#12]({PR}12))

{RELEASED}"""

# (file, contents, subject, author date, committer date). The door merged at
# 9am on Monday 12 Oct in Sydney, which is Sunday 11 Oct in UTC and the week
# before: dated by the committer date, it would land a week early.
LANDED = (
    (
        "door.fixed.md",
        f"- A door opens again. (issue [#30]({ISSUE}30))",
        "Open the door again (#31)",
        "2026-10-12T09:00:00+11:00",
        "2026-10-11T22:00:00+00:00",
    ),
    (
        "bake.fixed.md",
        "- The bake finishes.",
        "Finish the bake (#32)",
        "2026-10-06T20:00:00+11:00",
        "2026-10-06T09:00:00+00:00",
    ),
    (
        "lights.added.md",
        "- Lights can start dark.\n- The dock says which lights start dark.",
        "Let lights start dark (#33)",
        "2026-10-07T15:00:00+11:00",
        "2026-10-07T04:00:00+00:00",
    ),
    # A later pull request that rewords a fragment does not take it over.
    (
        "bake.fixed.md",
        "- The bake finishes, every time.",
        "Reword the bake line (#34)",
        "2026-10-13T10:00:00+11:00",
        "2026-10-12T23:00:00+00:00",
    ),
)


def hermetic(tmp: Path) -> dict[str, str]:
    """Nothing from the machine's git config: no hooks, signing or autocrlf."""
    empty = tmp / "gitconfig"
    empty.write_text("")
    return {
        "GIT_CONFIG_GLOBAL": str(empty),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "selftest",
        "GIT_AUTHOR_EMAIL": "selftest@example.invalid",
        "GIT_COMMITTER_NAME": "selftest",
        "GIT_COMMITTER_EMAIL": "selftest@example.invalid",
    }


def commit(root: Path, subject: str, author: str, committer: str) -> None:
    env = {"GIT_AUTHOR_DATE": author, "GIT_COMMITTER_DATE": committer}
    with mock.patch.dict(os.environ, env):
        git(root, "add", "-A")
        git(root, "commit", "-q", "-m", subject)


def compile_cases() -> int:
    """Compile three merged fragments in a throwaway repository."""
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "repo"
        folder = root / FOLDER
        folder.mkdir(parents=True)
        with mock.patch.dict(os.environ, hermetic(Path(tmp))):
            git(root, "init", "-q", "-b", "main")
            (root / "CHANGELOG.md").write_text(BEFORE, encoding="utf-8", newline="\n")
            write_fragment(folder, README, "# Fragments")
            broken = cl.check(BEFORE, root)
            if broken:
                print(f"selftest: the fixture changelog fails: {broken}")
                failures += 1
            commit(root, "Start", "2026-10-02T10:00:00+11:00", "2026-10-02T10:00:00Z")
            for name, contents, subject, author, committer in LANDED:
                write_fragment(folder, name, contents)
                commit(root, subject, author, committer)

            failures += refusals(root)

            problems = compile_fragments(root)
            text = (root / "CHANGELOG.md").read_text(encoding="utf-8")
            left = sorted(path.name for path in folder.iterdir())
        if problems or text != AFTER:
            print(f"selftest: compile wrote the wrong changelog: {problems}\n{text}")
            failures += 1
        if left != [README]:
            print(f"selftest: compile should leave only the README, left {left}")
            failures += 1
    return failures


def refusals(root: Path) -> int:
    """What compile must refuse, and refuse without writing anything."""
    failures = 0
    folder = root / FOLDER
    door = folder / LANDED[0][0]
    # (name, file, contents, subject and author date if committed, phrase)
    cases = (
        ("an uncommitted fragment", "late.fixed.md", "- Late.", "", "", "commit it"),
        ("an edited fragment", door.name, "- Edited.", "", "", "commit it first"),
        (
            "a fragment with no pull request",
            "pushed.fixed.md",
            "- Pushed.",
            "Push straight to main",
            "2026-10-13T10:00:00+11:00",
            "names no pull request",
        ),
        # Merged before 0.1.0 and never compiled in, so it would be dated before
        # the release below it. That is check_changelog.py's call, not ours.
        (
            "a fragment that missed its release",
            "missed.fixed.md",
            "- Missed.",
            "Miss the release (#29)",
            "2026-10-01T10:00:00+10:00",
            "before 0.1.0 was released",
        ),
    )
    for name, file_name, contents, subject, author, phrase in cases:
        write_fragment(folder, file_name, contents)
        if subject:
            commit(root, subject, author, "2026-10-13T10:00:00Z")
        problems = compile_fragments(root)
        if not any(phrase in problem for problem in problems):
            print(f"selftest: {name} went unreported as {phrase!r}; got {problems}")
            failures += 1
        if (root / "CHANGELOG.md").read_text(encoding="utf-8") != BEFORE:
            print(f"selftest: compile refused {name} but wrote the changelog")
            failures += 1
        if file_name == "late.fixed.md":
            # The one a preview exists for: not merged yet, so today and PR #?.
            today = dt.date.today()
            want = f"- **{today.day} {cl.MONTHS[today.month - 1]}** Late. (PR #?)"
            shown, problems = preview(root)
            if want not in shown.split("\n"):
                print(f"selftest: preview should show {want!r}; got {problems}")
                failures += 1
        if subject:
            git(root, "rm", "-q", f"{FOLDER}/{file_name}")
            commit(root, "Drop it", "2026-10-13T11:00:00+11:00", "2026-10-13T11:00:00Z")
        else:
            git(root, "checkout", "-q", "--", ".")
            git(root, "clean", "-q", "-f", "--", FOLDER)
    return failures


def round_trips() -> int:
    """Compiling nothing changes nothing, in the fixture and the real file."""
    failures = 0
    real = (REPO / "CHANGELOG.md").read_text(encoding="utf-8")
    for name, text in (("the fixture", BEFORE), ("CHANGELOG.md", real)):
        if Unreleased.read(text).text() != text:
            print(f"selftest: reading and writing {name} back changed it")
            failures += 1
    return failures


REQUIRE_CASES = (
    # (name, changed paths with their git status, whether a fragment is missing)
    ("an addon change with no fragment", {"addons/hammerforge/plugin.gd": "M"}, True),
    (
        "an addon change with a fragment",
        {"addons/hammerforge/plugin.gd": "M", "changelog.d/fix.fixed.md": "A"},
        False,
    ),
    (
        "an addon change that only touches the README",
        {"addons/hammerforge/plugin.gd": "M", "changelog.d/README.md": "M"},
        True,
    ),
    (
        "an addon change that deletes someone else's fragment",
        {"addons/hammerforge/plugin.cfg": "M", "changelog.d/1297.added.md": "D"},
        True,
    ),
    (
        "an addon change that edits someone else's fragment",
        {"addons/hammerforge/a.gd": "M", "changelog.d/old.fixed.md": "M"},
        True,
    ),
    (
        "an addon change that renames someone else's fragment",
        {"addons/hammerforge/a.gd": "M", "changelog.d/new.fixed.md": "R"},
        True,
    ),
    (
        "a compile, as the release carries it",
        {
            "addons/hammerforge/plugin.cfg": "M",
            "CHANGELOG.md": "M",
            "changelog.d/1297.added.md": "D",
            "changelog.d/old.fixed.md": "D",
        },
        False,
    ),
    (
        "the changelog edited by hand with a fragment edited, not compiled",
        {
            "addons/hammerforge/a.gd": "M",
            "CHANGELOG.md": "M",
            "changelog.d/old.fixed.md": "M",
        },
        True,
    ),
    (
        "a server change with no fragment",
        {"hammerforge_mcp/src/hammerforge_mcp/server.py": "M"},
        True,
    ),
    (
        "docs, tests and tooling",
        {
            "docs/a.md": "M",
            "tests/test_a.gd": "A",
            "tools/a.py": "M",
            "hammerforge_mcp/tests/test_a.py": "M",
            "addons/hf_docshot/hf_docshot.gd": "M",
        },
        False,
    ),
    ("nothing", {}, False),
)


def require_cases() -> int:
    """The rule on its own, then through git in a throwaway repository."""
    failures = 0
    for name, changed, missing in REQUIRE_CASES:
        problem = fragment_missing(changed)
        if bool(problem) != missing:
            print(
                f"selftest: {name} should {'' if missing else 'not '}be asked; got {problem}"
            )
            failures += 1
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "repo"
        (root / "addons" / "hammerforge").mkdir(parents=True)
        (root / FOLDER).mkdir()
        with mock.patch.dict(os.environ, hermetic(Path(tmp))):
            git(root, "init", "-q", "-b", "main")
            (root / "addons" / "hammerforge" / "a.gd").write_text("extends Node\n")
            write_fragment(root / FOLDER, README, "# Fragments")
            write_fragment(root / FOLDER, "old.fixed.md", "- Fixed before.")
            commit(root, "Start", "2026-10-02T10:00:00+11:00", "2026-10-02T10:00:00Z")
            git(root, "checkout", "-q", "-b", "topic")
            (root / "addons" / "hammerforge" / "a.gd").write_text("extends Node3D\n")
            commit(
                root,
                "Change the addon",
                "2026-10-03T10:00:00+11:00",
                "2026-10-03T10:00:00Z",
            )
            if not require_fragment(root, "main"):
                print("selftest: an addon commit with no fragment went unasked")
                failures += 1
            # Untracked counts: the check is useful before the commit too.
            write_fragment(root / FOLDER, "topic.fixed.md", "- Changed.")
            if require_fragment(root, "main"):
                print("selftest: an untracked fragment was not counted")
                failures += 1
            commit(
                root,
                "Add the fragment",
                "2026-10-03T11:00:00+11:00",
                "2026-10-03T11:00:00Z",
            )
            # main moving on with an addon change of its own is not this
            # branch's change: the diff runs from the merge base.
            git(root, "checkout", "-q", "main")
            (root / "addons" / "hammerforge" / "b.gd").write_text("extends Node\n")
            commit(
                root,
                "Change main (#2)",
                "2026-10-04T10:00:00+11:00",
                "2026-10-04T10:00:00Z",
            )
            git(root, "checkout", "-q", "-b", "docs-only", "topic~2")
            (root / "README.md").write_text("# Docs\n")
            commit(
                root, "Docs only", "2026-10-05T10:00:00+11:00", "2026-10-05T10:00:00Z"
            )
            problems = require_fragment(root, "main")
            if problems:
                print(
                    f"selftest: a docs-only branch was asked because main moved: {problems}"
                )
                failures += 1
            # Someone else's fragment, deleted, edited or renamed, is not a
            # line of this change's own (#1487).
            old_fragment = root / FOLDER / "old.fixed.md"
            for change in ("deleted", "edited", "renamed"):
                git(root, "checkout", "-q", "-b", f"{change}-fragment", "main")
                (root / "addons" / "hammerforge" / "a.gd").write_text(
                    "extends Node2D\n"
                )
                if change == "deleted":
                    old_fragment.unlink()
                elif change == "edited":
                    old_fragment.write_text("- Fixed before, said better.\n")
                else:
                    old_fragment.rename(old_fragment.with_name("moved.fixed.md"))
                commit(
                    root,
                    f"Change the addon, {change} fragment",
                    "2026-10-06T10:00:00+11:00",
                    "2026-10-06T10:00:00Z",
                )
                if not require_fragment(root, "main"):
                    print(f"selftest: the {change} fragment was counted as a new one")
                    failures += 1
            # A compile writes the changelog and deletes what it wrote in.
            git(root, "checkout", "-q", "-b", "compile", "main")
            (root / "addons" / "hammerforge" / "a.gd").write_text("extends Node2D\n")
            old_fragment.unlink()
            (root / "CHANGELOG.md").write_text("# Changelog\n")
            commit(root, "Compile", "2026-10-07T10:00:00+11:00", "2026-10-07T10:00:00Z")
            problems = require_fragment(root, "main")
            if problems:
                print(f"selftest: a compile was asked for a fragment: {problems}")
                failures += 1
    return failures


def selftest() -> int:
    failures = check_cases() + compile_cases() + round_trips() + require_cases()
    if failures:
        print(f"selftest: {failures} wrong answers")
        return 1
    print(
        f"selftest: {len(CASES) + 2} fragment cases correct; compile refuses what"
        " it should, previews, writes the right changelog, and changes nothing"
        f" when there is nothing to compile; {len(REQUIRE_CASES)} ask-for-one"
        " cases correct, through git too"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check", action="store_true", help="check every fragment (the default)"
    )
    mode.add_argument(
        "--preview",
        action="store_true",
        help="print [Unreleased] as compile would write it, and write nothing",
    )
    mode.add_argument(
        "--compile",
        action="store_true",
        help="write the fragments into CHANGELOG.md and delete them",
    )
    mode.add_argument(
        "--require",
        metavar="BASE",
        help="fail when the changes since BASE touch the addon or the server"
        " and bring no fragment",
    )
    mode.add_argument(
        "--selftest",
        action="store_true",
        help="check the guard still catches each way a fragment can break",
    )
    args = parser.parse_args()

    if args.selftest:
        return selftest()
    if args.require:
        problems = require_fragment(REPO, args.require)
        if not problems:
            print(f"The changes since {args.require} bring a fragment, or need none.")
            return 0
    elif args.preview:
        text, problems = preview(REPO)
        if not problems:
            print(text)
            return 0
    elif args.compile:
        problems = compile_fragments(REPO)
        if not problems:
            print("Compiled into CHANGELOG.md, and the fragments are deleted.")
            print("Commit both, and nothing else, in one pull request.")
            return 0
    else:
        fragments, problems = read_fragments(REPO)
        if not problems:
            lines = sum(len(fragment.entries) for fragment in fragments)
            print(f"{FOLDER}/: {len(fragments)} fragments, {lines} lines, all good.")
            return 0
    for problem in problems:
        print(problem)
    print(f"CONTRIBUTING.md, Changelog Entries, and {FOLDER}/{README} say how.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
