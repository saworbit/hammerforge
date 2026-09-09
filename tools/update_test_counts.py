#!/usr/bin/env python3
"""Keep the published test totals in step with what the suite actually reports.

Five documents quote the size of the test suite. Every pull request that adds a
test invalidates all five at once, and a number nobody re-measured is worse than
no number at all -- CONTRIBUTING.md asks for totals from a successful full CI
run, with the date they were measured.

So CI measures them and this writes them down.

    python tools/update_test_counts.py --gut-log gut.log --write
    python tools/update_test_counts.py --gut-log gut.log --check

--check changes nothing and exits 1 when a document disagrees with the log,
naming the ones that do.
"""

from __future__ import annotations

import argparse
import datetime
import re
import sys

MONTHS = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
]

NUMBER_WORDS = {
    0: "no",
    1: "one",
    2: "two",
    3: "three",
    4: "four",
    5: "five",
    6: "six",
    7: "seven",
    8: "eight",
    9: "nine",
    10: "ten",
}


def today() -> str:
    now = datetime.datetime.now(datetime.timezone.utc)
    return "%s %d, %d" % (MONTHS[now.month - 1], now.day, now.year)


def word(n: int) -> str:
    """Small counts read better spelled out, which is how the docs write them."""
    return NUMBER_WORDS.get(n, str(n))


def grouped(n: int) -> str:
    return "{:,}".format(n)


def parse_gut_log(path: str) -> dict:
    """Pull the totals out of GUT's own summary block."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    required = {
        "scripts": r"^Scripts\s+(\d+)\s*$",
        "tests": r"^Tests\s+(\d+)\s*$",
        "passing": r"^Passing Tests\s+(\d+)\s*$",
        "asserts": r"^Asserts\s+(\d+)\s*$",
    }
    counts = {}
    for key, pattern in required.items():
        found = re.findall(pattern, text, re.MULTILINE)
        if not found:
            raise SystemExit(
                "update_test_counts: no '%s' total in %s. This reads GUT's own "
                "summary block, so the log has to be the full test output."
                % (key, path)
            )
        counts[key] = int(found[-1])
    # Absent from the summary when there are none of them.
    for key, pattern in [
        ("risky", r"^Risky/Pending\s+(\d+)\s*$"),
        ("failing", r"^Failing Tests\s+(\d+)\s*$"),
    ]:
        found = re.findall(pattern, text, re.MULTILINE)
        counts[key] = int(found[-1]) if found else 0
    return counts


DATE_PATTERN = r"(?P<date>[A-Z][a-z]+ \d{1,2}, \d{4})"


def rewrites(c: dict) -> list:
    """One (path, pattern, template) per number this owns.

    Patterns are anchored on the prose around the number rather than on the
    number itself, so a reworded sentence fails loudly here instead of silently
    leaving a stale figure behind. Where a sentence carries a verification date,
    the pattern captures it as `date` and the template leaves `{date}` unfilled,
    so the caller decides whether this rewrite is worth restamping.
    """
    common = {
        "tests": grouped(c["tests"]),
        "scripts": grouped(c["scripts"]),
        "passing": grouped(c["passing"]),
        "asserts": grouped(c["asserts"]),
        "risky": word(c["risky"]),
    }
    return [
        (
            "README.md",
            r'Tests-\d+%20passing-brightgreen" alt="\d+ tests passing"',
            # Plain digits, not grouped: this is a URL path segment.
            'Tests-{p}%20passing-brightgreen" alt="{p} tests passing"'.format(
                p=c["passing"]
            ),
        ),
        (
            "docs/features.md",
            r"The verified Godot 4\.7 suite on "
            + DATE_PATTERN
            + r" contains \*\*[\d,]+ tests across "
            r"[\d,]+ scripts\*\*: \*\*[\d,]+ passing tests\*\*, \w+ intentional "
            r"no-assert safety tests, and \*\*[\d,]+ assertions\*\*\.",
            (
                "The verified Godot 4.7 suite on {date} contains **{tests} tests "
                "across {scripts} scripts**: **{passing} passing tests**, {risky} "
                "intentional no-assert safety tests, and **{asserts} assertions**."
            ).format(date="{date}", **common),
        ),
        (
            "DEVELOPMENT.md",
            r"- \*\*GUT unit \+ integration tests\*\* -- [\d,]+ tests across [\d,]+ "
            r"test scripts \([\d,]+ passing plus \w+ intentional no-assert safety "
            r"tests; [\d,]+ assertions; verified in CI on "
            + DATE_PATTERN
            + r"; runs Godot headless\)",
            (
                "- **GUT unit + integration tests** -- {tests} tests across "
                "{scripts} test scripts ({passing} passing plus {risky} intentional "
                "no-assert safety tests; {asserts} assertions; verified in CI on "
                "{date}; runs Godot headless)"
            ).format(date="{date}", **common),
        ),
        (
            "HammerForge_SPEC.md",
            r"Full suite \(verified in CI on "
            + DATE_PATTERN
            + r"\): \*\*[\d,]+ tests\*\* across \*\*[\d,]+ "
            r"scripts\*\* \(\*\*[\d,]+ passing\*\* plus \w+ intentional no-assert "
            r"safety tests; \*\*[\d,]+ assertions\*\*\)\.",
            (
                "Full suite (verified in CI on {date}): **{tests} tests** across "
                "**{scripts} scripts** (**{passing} passing** plus {risky} "
                "intentional no-assert safety tests; **{asserts} assertions**)."
            ).format(date="{date}", **common),
        ),
        (
            "ROADMAP.md",
            r"The current suite covers [\d,]+ tests across [\d,]+ scripts,",
            "The current suite covers {tests} tests across {scripts} scripts,".format(
                **common
            ),
        ),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gut-log", required=True, help="file holding GUT's output")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="rewrite the documents")
    mode.add_argument(
        "--check", action="store_true", help="report drift, change nothing"
    )
    parser.add_argument(
        "--date",
        default=today(),
        help="verification date to write (default: today UTC)",
    )
    args = parser.parse_args()

    counts = parse_gut_log(args.gut_log)
    if counts["failing"]:
        raise SystemExit(
            "update_test_counts: %d failing tests in the log. A total is only worth "
            "publishing from a green run." % counts["failing"]
        )

    summary = "%s tests across %s scripts, %s passing, %s assertions" % (
        grouped(counts["tests"]),
        grouped(counts["scripts"]),
        grouped(counts["passing"]),
        grouped(counts["asserts"]),
    )

    stale = []
    for path, pattern, template in rewrites(counts):
        with open(path, encoding="utf-8") as handle:
            original = handle.read()
        found = re.search(pattern, original)
        if found is None:
            raise SystemExit(
                "update_test_counts: nothing matched in %s. The sentence this owns "
                "was reworded or removed; update its pattern in "
                "tools/update_test_counts.py." % path
            )
        # Hold the date the file already carries and see whether anything else
        # differs. A date is a record of when the numbers were measured, so
        # restamping one that has not moved would commit a change saying nothing.
        carried = found.groupdict().get("date") or args.date
        if found.group(0) == template.format(date=carried):
            continue
        stale.append(path)
        if args.write:
            replacement = template.format(date=args.date)
            updated = original[: found.start()] + replacement + original[found.end() :]
            with open(path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(updated)

    if args.check:
        if stale:
            print("Out of date (%s):" % summary)
            for path in stale:
                print("  %s" % path)
            print("Run: python tools/update_test_counts.py --gut-log <log> --write")
            return 1
        print("Test counts are current (%s)." % summary)
        return 0

    if stale:
        print("Updated to %s:" % summary)
        for path in stale:
            print("  %s" % path)
    else:
        print("Test counts already current (%s)." % summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
