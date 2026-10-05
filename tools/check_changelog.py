#!/usr/bin/env python3
"""Keep CHANGELOG.md to one dated line per change, grouped by week.

    python tools/check_changelog.py
    python tools/check_changelog.py --summary
    python tools/check_changelog.py --selftest

By October 2026 the changelog was 7,933 lines of paragraphs. The 0.3.2 section
alone held 371 entries under about 25 repeated headings, because every merge
appended its own block, and nothing below a release heading said when a change
went in. It was rewritten as one line per change, newest first, grouped by
release and then by week, and the old text moved word for word to changelog/.
This keeps it that way.

What it holds the file to:

  * `# Changelog` first, an `## At a glance` table, then the releases newest
    first: `## [Unreleased]` and then `## [X.Y.Z] - YYYY-MM-DD`.
  * Inside a release, `### Week of 28 Sep 2026` headings, each a Monday,
    newest first. Anything before the first week is free text: the highlights
    and the link to the full notes.
  * Inside a week, `#### Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`,
    `Security`, `Behind the scenes`, in that order and at most once each.
  * Under those, nothing but entries, one source line each:
    `- **4 Oct** What changed. (issue [#927](...), PR [#934](...))`.
    The date sits inside its week and inside its release: after the release
    before it, and not after its own. Newest first. At most 200 characters as
    they read, with each link counted by its label. The last bracket holds
    links to this repository's issues, pull requests or commits, and each
    label names the number or hash its link goes to.
  * Every relative link resolves, and the At a glance row of every released
    version says what `--summary` counts. Unreleased work has no row: counts
    that every open pull request had to edit would make any two of them
    conflict, which is why #933 stopped committing the test totals.

`--summary` prints the table, with a live row for the unreleased work. Paste
the released rows at release time. `--selftest` breaks a known-good changelog
once per rule and fails if any break goes unreported.
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CHANGELOG = REPO / "CHANGELOG.md"
REPO_URL = "https://github.com/saworbit/hammerforge/"

CATEGORIES = (
    "Added",
    "Changed",
    "Deprecated",
    "Removed",
    "Fixed",
    "Security",
    "Behind the scenes",
)
# Deprecated and Security are rare enough to live in the total only.
GLANCE_COLUMNS = ("Added", "Changed", "Removed", "Fixed", "Behind the scenes")
GLANCE_HEADER = (
    "| Release | Released | Work dates | " + " | ".join(GLANCE_COLUMNS) + " | Total |"
)
MAX_VISIBLE = 200
MONTHS = (
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
)
MONTH = "|".join(MONTHS)

RELEASE_RE = re.compile(r"^## \[([^\]]+)\](.*)$")
VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
RELEASE_DATE_RE = re.compile(r"^ - (\d{4}-\d{2}-\d{2})$")
WEEK_RE = re.compile(rf"^### Week of (\d{{1,2}}) ({MONTH}) (\d{{4}})$")
ENTRY_RE = re.compile(rf"^- \*\*(\d{{1,2}}) ({MONTH})\*\* (\S.*)$")
REFS_RE = re.compile(r" \(((?:issues?|PRs?|commits?) \[.*)\)$")
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
REPO_LINK_RE = re.compile(
    re.escape(REPO_URL) + r"(issues|pull|commit)/([0-9a-f]+|\d+)$"
)


@dataclass
class Entry:
    day: dt.date
    line: int


@dataclass
class Week:
    monday: dt.date
    line: int
    counts: dict[str, int] = field(default_factory=dict)
    entries: list[Entry] = field(default_factory=list)
    headings: dict[str, int] = field(default_factory=dict)


@dataclass
class Release:
    name: str
    released: dt.date | None
    line: int
    weeks: list[Week] = field(default_factory=list)


def short(day: dt.date) -> str:
    return f"{day.day} {MONTHS[day.month - 1]} {day.year}"


def visible(text: str) -> str:
    """The entry as it reads: links by their label, no bold markers."""
    return LINK_RE.sub(lambda m: m.group(1), text).replace("**", "")


def check_refs(refs: str) -> list[str]:
    links = LINK_RE.findall(refs)
    if not links:
        return ["the last bracket holds no link"]
    problems = []
    for label, url in links:
        found = REPO_LINK_RE.match(url)
        if not found:
            problems.append(f"{url} is not an issue, PR or commit of this repository")
            continue
        kind, ref = found.groups()
        if kind == "commit":
            matches = len(label) >= 7 and ref.startswith(label)
        else:
            matches = label == f"#{ref}"
        if not matches:
            problems.append(f"the label {label} does not match its link {url}")
    return problems


def entry_date(day: int, month: str, week: Week) -> dt.date | None:
    """The entry's date, taking its year from the week it sits in."""
    month_no = MONTHS.index(month) + 1
    year = week.monday.year + (1 if month_no < week.monday.month else 0)
    try:
        return dt.date(year, month_no, day)
    except ValueError:
        return None


def parse(text: str) -> tuple[list[Release], list[str]]:
    """Read the releases, and report every line that breaks the layout."""
    releases: list[Release] = []
    problems: list[str] = []
    lines = text.split("\n")
    if not lines or lines[0] != "# Changelog":
        problems.append("line 1: the file must open with `# Changelog`")

    release: Release | None = None
    week: Week | None = None
    category: str | None = None
    last_entry: Entry | None = None

    for number, line in enumerate(lines, 1):
        where = f"line {number}"
        if number == 1:
            continue
        if line.startswith("## "):
            week, category, last_entry = None, None, None
            found = RELEASE_RE.match(line)
            if not found:
                if line == "## At a glance" and not releases:
                    continue
                problems.append(f"{where}: `{line}` is not a release heading")
                release = None
                continue
            release = read_release(found, number, releases, problems)
            if release is not None:
                releases.append(release)
            continue

        if line.startswith("### "):
            category, last_entry = None, None
            week = read_week(line, number, release, problems)
            continue

        if line.startswith("#### "):
            last_entry = None
            category = read_category(line, number, week, category, problems)
            continue

        if line.startswith("#"):
            problems.append(f"{where}: `{line}` is not a heading this file uses")
            continue

        if week is None or not line.strip():
            continue

        # Inside a week, everything that is not a heading is an entry.
        if category is None:
            problems.append(f"{where}: put this under an `#### Added`-style heading")
            continue
        found = ENTRY_RE.match(line)
        if not found:
            problems.append(
                f"{where}: under a week, every line is one entry,"
                " `- **4 Oct** What changed. (PR [#N](...))`; the detail goes in"
                " the pull request description"
            )
            continue
        entry = read_entry(found, number, week, problems)
        if entry is None:
            continue
        if last_entry is not None and entry.day > last_entry.day:
            problems.append(f"{where}: entries run newest first in each list")
        last_entry = entry
        week.entries.append(entry)
        week.counts[category] = week.counts.get(category, 0) + 1

    for release in releases:
        for week in release.weeks:
            if not week.entries:
                problems.append(f"line {week.line}: this week has no entries")
            for name, line in week.headings.items():
                if week.entries and not week.counts[name]:
                    problems.append(f"line {line}: `{name}` has no entries")
    return releases, problems


def read_release(
    found: re.Match[str], number: int, releases: list[Release], problems: list[str]
) -> Release | None:
    name, rest = found.groups()
    where = f"line {number}"
    if name == "Unreleased":
        if releases:
            problems.append(f"{where}: `[Unreleased]` comes first, and only once")
        if rest:
            problems.append(f"{where}: `[Unreleased]` takes no date")
        return Release(name, None, number)
    version = VERSION_RE.match(name)
    dated = RELEASE_DATE_RE.match(rest)
    if not version or not dated:
        problems.append(f"{where}: a release reads `## [X.Y.Z] - YYYY-MM-DD`")
        return None
    try:
        released = dt.date.fromisoformat(dated.group(1))
    except ValueError:
        problems.append(f"{where}: {dated.group(1)} is not a date")
        return None
    previous = next((r for r in reversed(releases) if r.released), None)
    if previous is not None:
        if version_key(name) >= version_key(previous.name):
            problems.append(f"{where}: releases run newest first")
        elif released > previous.released:
            problems.append(f"{where}: released after {previous.name}, listed below it")
    return Release(name, released, number)


def version_key(name: str) -> tuple[int, ...]:
    return tuple(int(part) for part in name.split("."))


def read_week(
    line: str, number: int, release: Release | None, problems: list[str]
) -> Week | None:
    where = f"line {number}"
    found = WEEK_RE.match(line)
    if release is None:
        problems.append(f"{where}: a week heading belongs inside a release")
        return None
    if not found:
        problems.append(f"{where}: a week heading reads `### Week of 28 Sep 2026`")
        return None
    day, month, year = found.groups()
    try:
        monday = dt.date(int(year), MONTHS.index(month) + 1, int(day))
    except ValueError:
        problems.append(f"{where}: {day} {month} {year} is not a date")
        return None
    if monday.weekday() != 0:
        problems.append(
            f"{where}: a week starts on a Monday, and {short(monday)} is not one"
        )
    if release.weeks and monday >= release.weeks[-1].monday:
        problems.append(f"{where}: weeks run newest first")
    week = Week(monday, number)
    release.weeks.append(week)
    return week


def read_category(
    line: str, number: int, week: Week | None, current: str | None, problems: list[str]
) -> str | None:
    where = f"line {number}"
    name = line[5:]
    if week is None:
        problems.append(f"{where}: `{line}` belongs inside a week")
        return None
    if name not in CATEGORIES:
        problems.append(
            f"{where}: `{name}` is not a category; use one of " + ", ".join(CATEGORIES)
        )
        return None
    if name in week.counts:
        problems.append(f"{where}: `{name}` appears twice in this week")
    elif current is not None and CATEGORIES.index(name) < CATEGORIES.index(current):
        problems.append(
            f"{where}: `{name}` comes before `{current}`; the order is "
            + ", ".join(CATEGORIES)
        )
    week.counts.setdefault(name, 0)
    week.headings.setdefault(name, number)
    return name


def read_entry(
    found: re.Match[str], number: int, week: Week, problems: list[str]
) -> Entry | None:
    where = f"line {number}"
    day, month, body = found.groups()
    when = entry_date(int(day), month, week)
    if when is None:
        problems.append(f"{where}: {day} {month} is not a date")
        return None
    if not week.monday <= when <= week.monday + dt.timedelta(days=6):
        problems.append(f"{where}: {short(when)} is outside its week")
    length = len(visible(f"{day} {month} {body}"))
    if length > MAX_VISIBLE:
        problems.append(
            f"{where}: {length} characters as it reads, over {MAX_VISIBLE};"
            " say what changed and leave the how to the pull request"
        )
    refs = REFS_RE.search(body)
    if not refs:
        problems.append(
            f"{where}: end with a bracket of links, `(PR [#N](...))`,"
            " `(issue [#N](...), PR [#M](...))` or `(commit [abc1234](...))`"
        )
    else:
        problems.extend(f"{where}: {p}" for p in check_refs(refs.group(1)))
    return Entry(when, number)


def check_windows(releases: list[Release]) -> list[str]:
    """Each entry sits after the release below it and not after its own."""
    problems = []
    for index, release in enumerate(releases):
        older = next((r for r in releases[index + 1 :] if r.released), None)
        for week in release.weeks:
            for entry in week.entries:
                if release.released and entry.day > release.released:
                    problems.append(
                        f"line {entry.line}: dated after {release.name} was released"
                    )
                if older and older.released and entry.day < older.released:
                    problems.append(
                        f"line {entry.line}: dated before {older.name} was released;"
                        " it belongs to that release or an older one"
                    )
    return problems


def check_links(text: str, root: Path) -> list[str]:
    problems = []
    for number, line in enumerate(text.split("\n"), 1):
        for _, url in LINK_RE.findall(line):
            if re.match(r"^(https?:|mailto:|#)", url):
                continue
            if not (root / url.split("#")[0]).exists():
                problems.append(f"line {number}: {url} does not exist")
    return problems


def work_dates(first: dt.date, last: dt.date) -> str:
    if (first.year, first.month) == (last.year, last.month):
        return f"{first.day} to {short(last)}" if first != last else short(last)
    if first.year == last.year:
        return f"{first.day} {MONTHS[first.month - 1]} to {short(last)}"
    return f"{short(first)} to {short(last)}"


def summary_row(release: Release) -> str:
    counts: dict[str, int] = {}
    days = []
    for week in release.weeks:
        for name, count in week.counts.items():
            counts[name] = counts.get(name, 0) + count
        days.extend(entry.day for entry in week.entries)
    released = short(release.released) if release.released else "not yet"
    span = work_dates(min(days), max(days)) if days else "none"
    cells = [release.name, released, span]
    cells += [str(counts.get(name, 0)) for name in GLANCE_COLUMNS]
    cells.append(str(sum(counts.values())))
    return "| " + " | ".join(cells) + " |"


def check_glance(text: str, releases: list[Release]) -> list[str]:
    lines = text.split("\n")
    if "## At a glance" not in lines:
        return ["the `## At a glance` section is missing"]
    start = lines.index("## At a glance")
    rows = {}
    for line in lines[start + 1 :]:
        if line.startswith("## "):
            break
        if line.startswith("| ") and not line.startswith(("| Release ", "|--")):
            rows[line.split("|")[1].strip()] = line
    problems = []
    for release in releases:
        if release.released is None:
            continue
        want = summary_row(release)
        have = rows.pop(release.name, None)
        if have != want:
            problems.append(
                f"At a glance: the {release.name} row should read {want}"
                " (python tools/check_changelog.py --summary)"
            )
    for name in rows:
        problems.append(f"At a glance: {name} is not a released version below")
    return problems


def check(text: str, root: Path) -> list[str]:
    """One line per problem. Empty means the changelog is in shape."""
    releases, problems = parse(text)
    problems += check_windows(releases)
    problems += check_links(text, root)
    problems += check_glance(text, releases)
    return problems


def summary(text: str) -> str:
    releases, _ = parse(text)
    rows = [GLANCE_HEADER, "|" + "---|" * (len(GLANCE_COLUMNS) + 4)]
    rows += [summary_row(release) for release in releases]
    return "\n".join(rows)


# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------

PR = REPO_URL + "pull/"
ISSUE = REPO_URL + "issues/"

CLEAN = f"""# Changelog

How to read this file.

## At a glance

{GLANCE_HEADER}
|---|---|---|---|---|---|---|---|---|
| 0.2.0 | 5 Oct 2026 | 30 Sep to 5 Oct 2026 | 1 | 0 | 0 | 1 | 0 | 2 |
| 0.1.0 | 26 Sep 2026 | 22 to 26 Sep 2026 | 0 | 0 | 0 | 2 | 1 | 3 |

## [Unreleased]

**Highlights**

- Something people will notice.

### Week of 5 Oct 2026

#### Fixed

- **6 Oct** A thing works again. (PR [#12]({PR}12))

## [0.2.0] - 2026-10-05

**Highlights**

- A new tool.

Full notes: [changelog/0.2.0.md](changelog/0.2.0.md)

### Week of 5 Oct 2026

#### Added

- **5 Oct** A new tool. (issue [#10]({ISSUE}10), PR [#11]({PR}11))

### Week of 28 Sep 2026

#### Fixed

- **30 Sep** A fix. (commit [abc1234]({REPO_URL}commit/abc1234def))

## [0.1.0] - 2026-09-26

### Week of 21 Sep 2026

#### Fixed

- **26 Sep** The second fix. (PR [#3]({PR}3))
- **22 Sep** The first fix. (PR [#2]({PR}2))

#### Behind the scenes

- **22 Sep** A test. (PR [#2]({PR}2))
"""

FIRST_FIX = f"- **22 Sep** The first fix. (PR [#2]({PR}2))"
SECOND_FIX = f"- **26 Sep** The second fix. (PR [#3]({PR}3))"

# (name, text to find, what to put there, a phrase the report must contain)
CASES = (
    ("a misnamed title", "# Changelog\n", "# Change log\n", "# Changelog"),
    (
        "an unknown second-level heading",
        "## [0.1.0]",
        "## Notes\n\n## [0.1.0]",
        "not a release heading",
    ),
    ("releases out of order", "## [0.1.0]", "## [0.3.0]", "newest first"),
    ("a release with no date", "## [0.2.0] - 2026-10-05", "## [0.2.0]", "X.Y.Z"),
    (
        "a release dated after the one above it",
        "## [0.1.0] - 2026-09-26",
        "## [0.1.0] - 2026-10-06",
        "released after 0.2.0",
    ),
    ("Unreleased twice", "## [0.1.0] - 2026-09-26", "## [Unreleased]", "only once"),
    ("a week that is not a Monday", "Week of 28 Sep", "Week of 29 Sep", "Monday"),
    (
        "weeks out of order",
        "### Week of 21 Sep 2026",
        f"### Week of 14 Sep 2026\n\n#### Fixed\n\n- **15 Sep** Old. (PR [#1]({PR}1))"
        "\n\n### Week of 21 Sep 2026",
        "weeks run newest first",
    ),
    ("an unknown category", "#### Added", "#### Bugfixes", "not a category"),
    (
        "categories out of order",
        "#### Behind the scenes",
        "#### Added",
        "comes before",
    ),
    (
        "a category twice in a week",
        "#### Behind the scenes",
        "#### Fixed",
        "appears twice",
    ),
    (
        "a category with no entries",
        "### Week of 28 Sep 2026\n",
        "### Week of 28 Sep 2026\n\n#### Removed\n",
        "`Removed` has no entries",
    ),
    (
        "a week with no entries",
        "### Week of 28 Sep 2026",
        "### Week of 28 Sep 2026\n\n### Week of 28 Sep 2026",
        "no entries",
    ),
    ("an entry outside its week", "**30 Sep**", "**27 Sep**", "outside its week"),
    ("a date that does not exist", "**30 Sep**", "**31 Sep**", "not a date"),
    (
        "an entry dated after its release",
        SECOND_FIX,
        SECOND_FIX.replace("26 Sep", "27 Sep"),
        "after 0.1.0 was released",
    ),
    (
        "an entry dated before the release below",
        "### Week of 5 Oct 2026\n\n#### Fixed\n\n- **6 Oct**",
        "### Week of 28 Sep 2026\n\n#### Fixed\n\n- **1 Oct**",
        "before 0.2.0 was released",
    ),
    (
        "entries out of order",
        f"{SECOND_FIX}\n{FIRST_FIX}",
        f"{FIRST_FIX}\n{SECOND_FIX}",
        "entries run newest first",
    ),
    (
        "an entry wrapped onto a second line",
        FIRST_FIX,
        FIRST_FIX + "\n  and how it was done.",
        "every line is one entry",
    ),
    (
        "a paragraph under a week",
        FIRST_FIX,
        FIRST_FIX + "\n\nWhy this was hard to find.",
        "every line is one entry",
    ),
    (
        "an entry before any category",
        "### Week of 28 Sep 2026\n",
        f"### Week of 28 Sep 2026\n\n- **29 Sep** Stray. (PR [#4]({PR}4))\n",
        "under an",
    ),
    (
        "an entry too long to read at a glance",
        "The first fix.",
        "The first fix, " + "and then some more detail " * 8 + ".",
        "characters as it reads",
    ),
    ("an entry with no link", f" (PR [#3]({PR}3))", "", "end with a bracket"),
    (
        "a link to another repository",
        f"[#3]({PR}3)",
        "[#3](https://github.com/elsewhere/repo/pull/3)",
        "not an issue, PR or commit of this repository",
    ),
    ("a label that names another PR", f"[#3]({PR}3)", f"[#3]({PR}4)", "label #3"),
    (
        "a broken relative link",
        "(changelog/0.2.0.md)",
        "(changelog/0.2.9.md)",
        "does not exist",
    ),
    (
        "a stale At a glance row",
        "| 1 | 0 | 0 | 1 | 0 | 2 |",
        "| 1 | 0 | 0 | 4 | 0 | 5 |",
        "the 0.2.0 row",
    ),
    (
        "a missing At a glance row",
        "| 0.1.0 | 26 Sep 2026 | 22 to 26 Sep 2026 | 0 | 0 | 0 | 2 | 1 | 3 |\n",
        "",
        "the 0.1.0 row",
    ),
    (
        "an At a glance row for nothing",
        "| 0.1.0 | 26 Sep",
        "| 0.0.9 | 1 Jan 2026 | none | 0 | 0 | 0 | 0 | 0 | 0 |\n| 0.1.0 | 26 Sep",
        "0.0.9 is not a released version",
    ),
)


def selftest() -> int:
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "changelog").mkdir()
        (root / "changelog" / "0.2.0.md").write_text("notes\n", encoding="utf-8")

        clean = check(CLEAN, root)
        if clean:
            print("selftest: the clean changelog was rejected:")
            for problem in clean:
                print(f"  {problem}")
            failures += 1

        for name, old, new, phrase in CASES:
            if old not in CLEAN:
                print(f"selftest: {name}: the fixture has no {old!r} to replace")
                failures += 1
                continue
            problems = check(CLEAN.replace(old, new, 1), root)
            if not any(phrase in problem for problem in problems):
                print(f"selftest: {name} went unreported as {phrase!r}; got {problems}")
                failures += 1

    total = len(CASES) + 1
    if failures:
        print(f"selftest: {failures} of {total} cases wrong")
        return 1
    print(f"selftest: {total} cases correct")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("changelog", nargs="?", type=Path, default=CHANGELOG)
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check the guard still catches each way the format can break",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="print the At a glance table, with a live row for unreleased work",
    )
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    text = args.changelog.read_text(encoding="utf-8")
    if args.summary:
        print(summary(text))
        return 0

    problems = check(text, args.changelog.parent)
    for problem in problems:
        print(f"{args.changelog.name}: {problem}")
    if problems:
        print("CONTRIBUTING.md, Changelog Entries, says how to write one.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
