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

Shards are numbered from 1 to match the workflow matrix. The split is
round-robin over the sorted filenames rather than contiguous blocks: adjacent
filenames test adjacent subsystems and cost similar amounts, so interleaving
balances the shards without anyone maintaining a table of per-file timings that
would go stale the first time someone adds a slow test.

--selftest checks the split still covers the suite exactly once, because a
splitter that quietly drops a file produces a green run with less in it, and a
smaller number that nobody re-measured is the failure this repository already
has a test for.
"""

from __future__ import annotations

import argparse
import os
import sys

TESTS_DIR = "tests"
RES_PREFIX = "res://tests/"


def test_scripts(tests_dir: str = TESTS_DIR) -> list[str]:
    """Every GUT test script, sorted, as engine paths."""
    names = [
        name
        for name in os.listdir(tests_dir)
        if name.startswith("test_") and name.endswith(".gd")
    ]
    return [RES_PREFIX + name for name in sorted(names)]


def shard(paths: list[str], number: int, of: int) -> list[str]:
    """The slice of `paths` belonging to shard `number` of `of`, counting from 1."""
    if of < 1:
        raise ValueError("there must be at least one shard, got %d" % of)
    if not 1 <= number <= of:
        raise ValueError("shard %d is outside 1..%d" % (number, of))
    return paths[number - 1 :: of]


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
    print("selftest: the split covers the suite exactly once at 1 to 8 shards")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
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
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    if args.count:
        print(len(test_scripts(args.tests_dir)))
        return 0

    if args.shard is None or args.of is None:
        parser.error("give --shard and --of, or --count, or --selftest")

    try:
        chosen = shard(test_scripts(args.tests_dir), args.shard, args.of)
    except ValueError as problem:
        raise SystemExit("shard_tests: %s" % problem) from problem
    print(",".join(chosen))
    return 0


if __name__ == "__main__":
    sys.exit(main())
