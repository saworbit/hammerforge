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


# The keys that are simply added together across shards. Every one of them is a
# count of things that happened, so four shards summing to the whole suite is
# the same arithmetic in each case.
SUMMED = ("scripts", "tests", "passing", "asserts", "risky", "failing")


def parse_gut_text(text: str, source: str = "<text>") -> dict:
    """Pull the totals out of GUT's own summary block."""
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
                % (key, source)
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


def parse_gut_log(path: str) -> dict:
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
    except OSError as problem:
        # A shard that never uploaded its log must say so in one line rather
        # than as a traceback, because this is the failure the totals depend on
        # noticing.
        raise SystemExit(
            "update_test_counts: cannot read %s: %s" % (path, problem)
        ) from problem
    return parse_gut_text(text, path)


def add_counts(per_shard: list[dict]) -> dict:
    """Add the shard totals together into one suite total."""
    totals = dict.fromkeys(SUMMED, 0)
    for counts in per_shard:
        for key in SUMMED:
            totals[key] += counts[key]
    return totals


def sum_gut_logs(paths: list[str]) -> dict:
    return add_counts([parse_gut_log(path) for path in paths])


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
            # The sixth number, in a file the tool already rewrites. The badge at
            # the top was kept current on every wave while the At a Glance cell
            # eighty lines below it sat at 2,860, because nothing owned it.
            "README.md",
            r"\*\*[\d,]+\+? unit \+ integration tests\*\* with CI on every push",
            "**{tests} unit + integration tests** with CI on every push".format(
                **common
            ),
        ),
        (
            "ROADMAP.md",
            r"The current suite covers [\d,]+ tests across [\d,]+ scripts,",
            "The current suite covers {tests} tests across {scripts} scripts,".format(
                **common
            ),
        ),
    ]


def _fixture(scripts, tests, passing, asserts, risky=None, failing=None) -> str:
    """A GUT summary block, shaped the way a shard writes one."""
    lines = [
        "Totals",
        "------",
        "Scripts          %d" % scripts,
        "Tests            %d" % tests,
        "Passing Tests    %d" % passing,
    ]
    # GUT leaves both of these out of the block entirely when they are zero,
    # which is the case the parser has to keep getting right.
    if risky is not None:
        lines.append("Risky/Pending    %d" % risky)
    if failing is not None:
        lines.append("Failing Tests    %d" % failing)
    lines.append("Asserts          %d" % asserts)
    return "\n".join(lines) + "\n"


def selftest() -> int:
    failures = 0

    def check(name, got, want):
        nonlocal failures
        if got != want:
            print("selftest: %s got %r, wanted %r" % (name, got, want))
            failures += 1

    # The real run, split the way CI splits it.
    shards = [
        parse_gut_text(_fixture(56, 1000, 1000, 5000)),
        parse_gut_text(_fixture(56, 1100, 1098, 5200, risky=2)),
        parse_gut_text(_fixture(55, 990, 990, 4800)),
        parse_gut_text(_fixture(55, 1003, 1003, 4729)),
    ]
    total = add_counts(shards)
    check("summed scripts", total["scripts"], 222)
    check("summed tests", total["tests"], 4093)
    check("summed passing", total["passing"], 4091)
    check("summed asserts", total["asserts"], 19729)
    check("summed risky", total["risky"], 2)
    check("absent risky reads as zero", total["failing"], 0)

    # A failing shard has to survive the addition. Publishing a total from a run
    # with failures in it is what the --write guard refuses, and it can only
    # refuse what the sum still carries.
    failed = add_counts([parse_gut_text(_fixture(55, 990, 989, 4800, failing=1))])
    check("a failing shard keeps its failure", failed["failing"], 1)

    # A shard that died before printing its summary is the dangerous case: the
    # other three still parse and the total is still plausible.
    try:
        parse_gut_text("Godot Engine v4.7.stable\nSegmentation fault\n", "shard-3.log")
    except SystemExit:
        pass
    else:
        print("selftest: a log with no summary block should have been refused")
        failures += 1

    if failures:
        print("selftest: %d checks wrong" % failures)
        return 1
    print("selftest: shard totals add up and a truncated log is refused")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--gut-log",
        action="extend",
        nargs="+",
        metavar="PATH",
        help="files holding GUT's output, one per shard; may be repeated",
    )
    parser.add_argument(
        "--expect-scripts",
        type=int,
        help=(
            "refuse the totals unless the logs together report this many "
            "scripts; CI passes tools/shard_tests.py --count"
        ),
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check the shard totals still add up",
    )
    mode = parser.add_mutually_exclusive_group()
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

    if args.selftest:
        return selftest()

    if not args.gut_log:
        parser.error("--gut-log is required unless --selftest is given")
    if not (args.write or args.check):
        parser.error("give --write or --check")

    counts = sum_gut_logs(args.gut_log)
    if args.expect_scripts is not None and counts["scripts"] != args.expect_scripts:
        raise SystemExit(
            "update_test_counts: the logs account for %d scripts, not %d. A shard "
            "ran fewer scripts than it was given, and publishing this total would "
            "record a smaller suite as measured fact."
            % (counts["scripts"], args.expect_scripts)
        )
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
