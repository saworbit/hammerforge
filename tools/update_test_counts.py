#!/usr/bin/env python3
"""Keep the published test totals in step with what the suite actually reports.

Five documents quote the size of the test suite, and a number nobody
re-measured is worse than no number at all. CONTRIBUTING.md asks for totals from
a successful full run, with the date they were measured.

They are a release snapshot. CI used to commit them to every pull request that
moved them, which started a second CI round and made any two open pull requests
that added tests conflict on all five files (#916). Now they are written once,
when a release is cut, from a full run's log:

    python tools/update_test_counts.py --gut-log gut.log --write
    python tools/update_test_counts.py --gut-log gut.log --check
    python tools/update_test_counts.py --gut-log shard-*.log --expect-scripts N --report

--check changes nothing and exits 1 when a document disagrees with the log,
naming the ones that do. --report reads no document at all: it prints the
totals and still refuses a log set that is short of scripts or has a failure in
it, which is what CI runs on every shard set.

    python tools/update_test_counts.py --gut-log shard-*.log --leaks

--leaks fails when a log ends with orphans or warnings in GUT's totals, and
names them. A node a test never freed landed green in #911, because nothing read
those two lines (#923). One warning is only reported: "Test script has N unfreed
children" depends on the order the scripts ran in, so it is printed as a CI
annotation rather than failed on.
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
SUMMED = (
    "scripts",
    "tests",
    "passing",
    "asserts",
    "risky",
    "failing",
    "warnings",
    "orphans",
)

ANSI = re.compile(r"\x1b\[[0-9;]*m")


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
        ("warnings", r"^Warnings\s+(\d+)\s*$"),
        ("orphans", r"^Orphans\s+(\d+)\s*$"),
    ]:
        found = re.findall(pattern, text, re.MULTILINE)
        counts[key] = int(found[-1]) if found else 0
    return counts


def read_log(path: str) -> str:
    """The log's text, or a one-line exit when it cannot be read."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError as problem:
        # A shard that never uploaded its log must say so in one line rather
        # than as a traceback, because this is the failure the totals depend on
        # noticing.
        raise SystemExit(
            "update_test_counts: cannot read %s: %s" % (path, problem)
        ) from problem


def parse_gut_log(path: str) -> dict:
    """GUT's totals from the log at `path`."""
    return parse_gut_text(read_log(path), path)


def leak_notes(text: str) -> list[str]:
    """What GUT said about each orphan and warning, with the script it was in.

    The orphan list GUT prints at the end of a run already names the script and
    the test. A warning is printed inside the script's own output, so it is
    paired here with the last script header above it.
    """
    notes = []
    script = ""
    in_orphans = False
    for raw in text.splitlines():
        line = ANSI.sub("", raw).rstrip()
        if re.match(r"^= \d+ Orphans", line):
            in_orphans = True
            continue
        if in_orphans:
            if line.startswith("= Run Summary"):
                in_orphans = False
            elif line and not line.startswith("="):
                notes.append(line)
            continue
        if re.match(r"^res://.*\.gd$", line):
            script = line
        elif "[WARNING]:" in line:
            notes.append(
                "%s: %s" % (script or "<no script>", line.split("]:", 1)[1].strip())
            )
    return notes


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
            # The At a Glance cell sat at 2,860 for months while a badge above it
            # was kept current, because nothing owned it.
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

    # Orphans and warnings are added up like the rest, and absent reads as none.
    leaky = add_counts(
        [
            parse_gut_text(_fixture(10, 20, 20, 40)),
            parse_gut_text(_fixture(10, 20, 20, 40) + "Warnings 1\nOrphans 2\n"),
        ]
    )
    check("summed warnings", leaky["warnings"], 1)
    check("summed orphans", leaky["orphans"], 2)

    # The notes name the script and the test, through GUT's colour codes.
    log = (
        "res://tests/test_a.gd\n"
        "\x1b[33m[WARNING]:  \x1b[0mTest script has 2 unfreed children.\n"
        "\x1b[33m= 1 Orphans\x1b[0m\n"
        "\x1b[33m=====\x1b[0m\n"
        "test_b.gd\n"
        "    - test_leaks\n"
        "\x1b[33m= Run Summary\x1b[0m\n"
        "Orphans 1\n"
    )
    check(
        "leak notes",
        leak_notes(log),
        [
            "res://tests/test_a.gd: Test script has 2 unfreed children.",
            "test_b.gd",
            "    - test_leaks",
        ],
    )

    # The order-dependent warning is reported and does not fail; an orphan or
    # any other warning does.
    unfreed = (
        "res://tests/test_a.gd\n"
        "[WARNING]:  Test script has 2 unfreed children.  Increase log level\n"
        + _fixture(1, 2, 2, 4)
        + "Warnings 1\n"
    )
    failed, lines = leak_verdict(unfreed, "a.log")
    check("an order-dependent warning does not fail", failed, False)
    check(
        "but it is annotated",
        lines[0].startswith("::warning::res://tests/test_a.gd"),
        True,
    )
    other = (
        "res://tests/test_b.gd\n[WARNING]:  Something else\n"
        + _fixture(1, 2, 2, 4)
        + "Warnings 1\n"
    )
    check("another warning fails", leak_verdict(other, "b.log")[0], True)
    check(
        "an orphan fails",
        leak_verdict(_fixture(1, 2, 2, 4) + "Orphans 1\n", "c.log")[0],
        True,
    )

    if failures:
        print("selftest: %d checks wrong" % failures)
        return 1
    print(
        "selftest: shard totals add up, a truncated log is refused, and orphans "
        "and warnings are counted and named"
    )
    return 0


# GUT counts the nodes still under a test script when the script ends. A node a
# test queued for freeing is normally gone by then, but when GUT resumed that
# test from a frame that ran long, the timer it waits on fires before the frame
# frees anything, and the node is counted. Whether that happens depends on which
# script ran before, so failing on it turned main red on a test nobody had
# touched as soon as the shard order changed (#923, #940).
ORDER_DEPENDENT_WARNING = "unfreed children"


def leak_verdict(text: str, source: str) -> tuple[bool, list[str]]:
    """Whether a log should fail the run, and the lines that say why.

    Orphans fail it, and so does every warning except the order-dependent one,
    which comes back as a CI annotation instead.
    """
    counts = parse_gut_text(text, source)
    notes = leak_notes(text)
    order_dependent = [note for note in notes if ORDER_DEPENDENT_WARNING in note]
    lines = ["::warning::%s" % note for note in order_dependent]
    warnings = counts["warnings"] - len(order_dependent)
    if not (counts["orphans"] or warnings > 0):
        return False, lines
    lines.append("%s: %d orphans, %d warnings" % (source, counts["orphans"], warnings))
    lines.extend("  %s" % note for note in notes if note not in order_dependent)
    return True, lines


def check_leaks(paths: list[str]) -> int:
    """Print what each log left behind; 1 when any of them fails the run."""
    dirty = 0
    for path in paths:
        failed, lines = leak_verdict(read_log(path), path)
        for line in lines:
            print(line)
        dirty += failed
    if dirty:
        print(
            "\nA test left a node behind or GUT warned about one. Free what a test "
            "makes with autofree() or add_child_autofree(). A queued free from a "
            "script's last test can still be counted, so prefer the immediate one "
            "there."
        )
        return 1
    print("No orphans, and no warnings that fail the run, in %d logs." % len(paths))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
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
    mode.add_argument(
        "--report",
        action="store_true",
        help="print the totals and read no document; the guards still apply",
    )
    mode.add_argument(
        "--leaks",
        action="store_true",
        help="fail when GUT reports orphans or warnings at the end of a log",
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
    if not (args.write or args.check or args.report or args.leaks):
        parser.error("give --write, --check, --report or --leaks")

    if args.leaks:
        return check_leaks(args.gut_log)

    counts = sum_gut_logs(args.gut_log)
    if args.expect_scripts is not None and counts["scripts"] != args.expect_scripts:
        raise SystemExit(
            "update_test_counts: the logs account for %d scripts, not %d. The "
            "shards and the split disagree on the size of the suite, and "
            "publishing this total would record the wrong one as measured fact."
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

    if args.report:
        print("Measured %s." % summary)
        return 0

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
