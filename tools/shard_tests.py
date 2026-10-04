#!/usr/bin/env python3
"""Split the GUT suite into shards CI can run in parallel.

The suite was 360 seconds of a 384 second CI run, and the other two jobs were
done inside 73 -- so the wait was the suite. It divides well: 222 scripts,
median runtime 0.99s, and no hotspot to fix instead of dividing, save one
21s file that sets the floor no split can beat. Measured after sharding, the
four shard jobs ran 1m53s to 2m07s and the whole CI run finished in 2m21s,
against 6m33s for the equivalent single-job run.

    python tools/shard_tests.py --shard 1 --of 4   # the paths for shard 1
    python tools/shard_tests.py --count            # how many scripts exist

Shards are numbered from 1 to match the workflow matrix. Each script goes to
the shard with the least measured time so far, longest first, from the
per-script seconds in tests/.durations.json. A script with no time yet counts
as the median and is placed after the timed ones, so it moves nothing else.
The split used to be round-robin over the sorted filenames, so adding one test
file moved every later file to another shard, the slowest shard changed from
run to run, and the shards were 30 to 77 seconds apart (#920).

The table goes stale slowly and harmlessly: a stale time only makes the shards
a little less even. Refresh it from the JUnit files CI uploads beside each
shard log:

    python tools/shard_tests.py --durations-from shard-logs/*/gut-shard-*.xml
    python tools/shard_tests.py --failures shard-logs/gut-shard-*.xml

--selftest checks the split still covers the suite exactly once, because a
splitter that quietly drops a file produces a green run with less in it, and a
smaller number that nobody re-measured is the failure this repository already
has a test for.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import xml.etree.ElementTree as ElementTree

TESTS_DIR = "tests"
RES_PREFIX = "res://tests/"
DURATIONS = os.path.join(TESTS_DIR, ".durations.json")


def test_scripts(tests_dir: str = TESTS_DIR) -> list[str]:
    """Every GUT test script, sorted, as engine paths."""
    names = [
        name
        for name in os.listdir(tests_dir)
        if name.startswith("test_") and name.endswith(".gd")
    ]
    return [RES_PREFIX + name for name in sorted(names)]


def load_durations(path: str = DURATIONS) -> dict[str, float]:
    """Seconds per script file name. Empty when there is no table yet."""
    try:
        with open(path, encoding="utf-8") as handle:
            table = json.load(handle)
    except FileNotFoundError:
        return {}
    return {str(name): float(seconds) for name, seconds in table.items()}


def split(paths: list[str], of: int, durations: dict[str, float]) -> list[list[str]]:
    """All `of` shards: longest first, each onto the least loaded shard.

    Scripts with no time yet go on after the timed ones, in name order, each
    weighing the median. So a new test file moves no other script, and the
    split only changes when the table is refreshed. Ties go to the lower shard,
    so all four shard jobs work out the same split on their own. With no times
    at all this deals the scripts out in turn, as the old split did.
    """
    if of < 1:
        raise ValueError("there must be at least one shard, got %d" % of)
    known = [
        durations[name] for name in map(os.path.basename, paths) if name in durations
    ]
    fallback = statistics.median(known) if known else 1.0

    def weight(path: str) -> float:
        return durations.get(os.path.basename(path), fallback)

    shards: list[list[str]] = [[] for _ in range(of)]
    loads = [0.0] * of
    timed = sorted(
        (p for p in paths if os.path.basename(p) in durations),
        key=lambda p: (-weight(p), p),
    )
    untimed = sorted(p for p in paths if os.path.basename(p) not in durations)
    for path in timed + untimed:
        target = min(range(of), key=lambda i: (loads[i], i))
        shards[target].append(path)
        loads[target] += weight(path)
    return [sorted(one) for one in shards]


def shard(
    paths: list[str], number: int, of: int, durations: dict[str, float] | None = None
) -> list[str]:
    """The slice of `paths` belonging to shard `number` of `of`, counting from 1."""
    if of < 1:
        raise ValueError("there must be at least one shard, got %d" % of)
    if not 1 <= number <= of:
        raise ValueError("shard %d is outside 1..%d" % (number, of))
    return split(paths, of, durations or {})[number - 1]


def read_junit(paths: list[str]) -> list[ElementTree.Element]:
    """The <testsuite> elements of GUT's JUnit files, one per script."""
    suites = []
    for path in paths:
        try:
            suites.extend(ElementTree.parse(path).getroot().iter("testsuite"))
        except (OSError, ElementTree.ParseError) as problem:
            print("shard_tests: skipping %s: %s" % (path, problem), file=sys.stderr)
    return suites


def durations_from_junit(paths: list[str]) -> dict[str, float]:
    """Seconds per script file name, as GUT measured them."""
    table = {}
    for suite in read_junit(paths):
        name = os.path.basename(suite.get("name", ""))
        if name:
            table[name] = round(float(suite.get("time", 0) or 0), 2)
    return dict(sorted(table.items()))


def failures_from_junit(paths: list[str]) -> list[str]:
    """`script: test` for every failing test, so a red run says which."""
    out = []
    for suite in read_junit(paths):
        for case in suite.iter("testcase"):
            if case.find("failure") is not None:
                out.append("%s: %s" % (suite.get("name", "?"), case.get("name", "?")))
    return out


def selftest() -> int:
    paths = ["res://tests/test_%03d.gd" % i for i in range(222)]
    failures = 0

    for of in range(1, 9):
        shards = [shard(paths, n, of) for n in range(1, of + 1)]
        seen = [path for one in shards for path in one]
        if sorted(seen) != paths:
            print("selftest: %d shards do not cover the suite exactly once" % of)
            failures += 1
        if len(seen) != len(set(seen)):
            print("selftest: %d shards run some script twice" % of)
            failures += 1
        if any(not one for one in shards):
            print("selftest: %d shards left one of them empty" % of)
            failures += 1
        spread = max(len(one) for one in shards) - min(len(one) for one in shards)
        if spread > 1:
            print("selftest: %d shards differ by %d scripts" % (of, spread))
            failures += 1

    # Timed: every script still runs exactly once, and greedy packing keeps the
    # shards within one script's time of each other, which round-robin did not.
    times = {"test_%03d.gd" % i: 0.2 + (i * 37 % 11) * 0.7 for i in range(222)}
    times["test_007.gd"] = 13.0
    for of in range(1, 9):
        shards = [shard(paths, n, of, times) for n in range(1, of + 1)]
        seen = [path for one in shards for path in one]
        if sorted(seen) != paths or len(seen) != len(set(seen)):
            print("selftest: %d timed shards do not cover the suite exactly once" % of)
            failures += 1
        loads = [sum(times[os.path.basename(p)] for p in one) for one in shards]
        if max(loads) - min(loads) > max(times.values()):
            print(
                "selftest: %d timed shards are %.1fs apart"
                % (of, max(loads) - min(loads))
            )
            failures += 1

    # A script with no time yet weighs the median, and a new one does not move
    # every other script: the four shards here are the same bar the new file.
    before = [shard(paths, n, 4, times) for n in range(1, 5)]
    after = [
        shard([*paths, "res://tests/test_zzz.gd"], n, 4, times) for n in range(1, 5)
    ]
    moved = sum(
        1
        for one, two in zip(before, after, strict=True)
        for path in one
        if path not in two
    )
    if moved:
        print("selftest: adding one untimed script moved %d others" % moved)
        failures += 1

    # GUT's JUnit file reads back into the table and the failure list.
    junit = (
        '<?xml version="1.0" encoding="UTF-8"?>\n<testsuites name="GutTests">\n'
        '<testsuite name="tests/test_a.gd" tests="2" failures="1" time="1.2345">\n'
        '<testcase name="test_ok" status="pass" time="1.0"></testcase>\n'
        '<testcase name="test_bad" status="fail" time="0.2345">'
        '<failure message="failed"><![CDATA[expected 1]]></failure></testcase>\n'
        "</testsuite>\n</testsuites>"
    )
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        xml_path = os.path.join(tmp, "shard.xml")
        with open(xml_path, "w", encoding="utf-8") as handle:
            handle.write(junit)
        if durations_from_junit([xml_path]) != {"test_a.gd": 1.23}:
            print("selftest: the JUnit times did not read back")
            failures += 1
        if failures_from_junit([xml_path]) != ["tests/test_a.gd: test_bad"]:
            print("selftest: the failing test was not named")
            failures += 1

    for number, of in [(0, 4), (5, 4), (-1, 4)]:
        try:
            shard(paths, number, of)
        except ValueError:
            continue
        print("selftest: shard %d of %d should have been refused" % (number, of))
        failures += 1

    if failures:
        print("selftest: %d checks wrong" % failures)
        return 1
    print(
        "selftest: the split covers the suite exactly once at 1 to 8 shards, timed"
        " shards stay within one script of each other, and JUnit files read back"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--shard", type=int, help="which shard to print, from 1")
    parser.add_argument("--of", type=int, help="how many shards there are")
    parser.add_argument(
        "--count", action="store_true", help="print how many test scripts exist"
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check the split still covers the suite exactly once",
    )
    parser.add_argument(
        "--tests-dir", default=TESTS_DIR, help="where the test scripts live"
    )
    parser.add_argument(
        "--durations-from",
        nargs="+",
        metavar="XML",
        help="rewrite tests/.durations.json from GUT's JUnit files",
    )
    parser.add_argument(
        "--failures",
        nargs="*",
        metavar="XML",
        help="print the failing tests named in GUT's JUnit files",
    )
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    if args.durations_from:
        table = durations_from_junit(args.durations_from)
        if not table:
            raise SystemExit("shard_tests: no script times in those files")
        with open(DURATIONS, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(table, handle, indent=1, sort_keys=True)
            handle.write("\n")
        print("Wrote %d script times to %s." % (len(table), DURATIONS))
        return 0

    if args.failures is not None:
        for line in failures_from_junit(args.failures):
            print("- %s" % line)
        return 0

    if args.count:
        print(len(test_scripts(args.tests_dir)))
        return 0

    if args.shard is None or args.of is None:
        parser.error("give --shard and --of, or --count, or --selftest")

    try:
        chosen = shard(
            test_scripts(args.tests_dir), args.shard, args.of, load_durations()
        )
    except ValueError as problem:
        raise SystemExit("shard_tests: %s" % problem) from problem
    print(",".join(chosen))
    return 0


if __name__ == "__main__":
    sys.exit(main())
