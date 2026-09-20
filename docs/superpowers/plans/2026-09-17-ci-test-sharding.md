# CI Test Sharding Implementation Plan

> **Shipped in 0.3.2 (#648). Do not implement this again.** `tools/shard_tests.py`, the four-leg `unit-test-shard` matrix and the aggregate job named `GUT Unit Tests` are in the tree and run on every push. Every step below is ticked. This file is kept as the record of why the split is shaped the way it is, not as work to pick up.

**Goal:** Cut CI wall clock from 6m24s to about 2m15s by running the GUT suite as four parallel shards, without changing what is covered.

**Architecture:** The `unit-tests` job splits into a four-leg `unit-test-shard` matrix plus an aggregate job that keeps the name `GUT Unit Tests`. A new `tools/shard_tests.py` computes each leg's slice of the 222 test scripts; `tools/update_test_counts.py` learns to sum the four shard logs and to refuse totals that do not account for every script.

**Tech Stack:** GitHub Actions, Python 3 (stdlib only), GUT 9.6.0 command-line runner, Godot 4.7-stable headless.

**Design document:** `docs/superpowers/specs/2026-09-17-ci-test-sharding-design.md`

## Global Constraints

- Python in `tools/` is linted by ruff with `line-length = 88`, `target-version = "py312"`, and `include = ["tools/*.py"]`. That glob reaches into subdirectories: ruff matches it with globset, where `*` crosses `/` unless `literal_separator` is set, and ruff does not set it. So `tools/vibe/run_vibe.py` is linted too. Nothing needs to be a direct child of `tools/`.
- ruff's selected rules are `E4`, `E7`, `E9`, `F`, `I`, `B`, `SIM`, `RUF`. `UP` (pyupgrade) is deliberately absent — do **not** rewrite `"%s" % x` into f-strings; the existing scripts use `%` formatting and that is the house style.
- `ruff format --check tools/` runs in CI. Format new code with `ruff format` before committing.
- Every tool in `tools/` that can fail a build carries a `--selftest` that proves the detector still detects. New guards follow that pattern.
- All GitHub Actions are pinned by full commit SHA with a `# vN` comment. `actionlint` and `zizmor` run over `.github/workflows/` on every push and will reject an unpinned action.
- Shards are numbered **from 1**, matching the workflow matrix. The file at sorted position `index` belongs to the shard where `index % of == shard - 1`.
- The aggregate job's name must be exactly `GUT Unit Tests`. It is a required status check on the `main` ruleset; any other spelling blocks every open pull request.
- Godot on CI is `4.7-stable`; locally it is `C:\Godot\godot.cmd`, invoked from the Bash tool as `cmd //c "C:\Godot\godot.cmd ..."`.
- Commit messages: short plain subject, body only when it adds something. No attribution lines.
- **Do not write these files with a shell heredoc.** In this environment a quoted heredoc still interprets backslash escapes, so `"\n".join(...)` arrives as a literal newline and `r"\s+"` arrives as `s+`. Both files in this plan are full of both. Use an editor/Write tool. This was hit while verifying the plan, not guessed at.

## File Structure

| File | Responsibility |
| --- | --- |
| `tools/shard_tests.py` (create) | Owns the split: which test scripts belong to which shard, and how many there are. Nothing else knows the rule. |
| `tools/update_test_counts.py` (modify) | Gains multi-log summing and a coverage assertion. Keeps sole ownership of the five published totals. |
| `.github/workflows/ci.yml` (modify) | Replaces the `unit-tests` job with a shard matrix plus an aggregate that keeps the required-check name. |
| `docs/superpowers/specs/2026-09-17-ci-test-sharding-design.md` (modify) | Filename correction only. |
| `CHANGELOG.md` (modify) | One `### Changed` entry. |
| `DEVELOPMENT.md` (modify) | Records why `-gconfig=` is load-bearing. The plan first named `docs/patterns_and_gotchas.md`, which does not exist here. |

---

### Task 1: The splitter

**Files:**
- Create: `tools/shard_tests.py`
- Modify: `.github/workflows/ci.yml` (add one step to the `static-checks` job)
- Modify: `docs/superpowers/specs/2026-09-17-ci-test-sharding-design.md` (rename references)

**Interfaces:**
- Produces: `test_scripts(tests_dir: str = "tests") -> list[str]` returning sorted `res://tests/NAME.gd` paths; `shard(paths: list[str], number: int, of: int) -> list[str]` (1-indexed, raises `ValueError` out of range); CLI `--shard N --of M`, `--count`, `--selftest`.
- Consumes: nothing.

**Note on the filename.** The design document calls this `tools/test_shard.py`. Use `tools/shard_tests.py` instead: every other script in `tools/` is verb-first (`check_placement_order.py`, `update_test_counts.py`, `build_release_tree.py`), and a `test_*.py` in a repository where `test_*.gd` means "a test" invites someone to read it as one. Step 6 corrects the design document to match.

- [x] **Step 1: Write the selftest cases as the whole script's test**

There is no pytest in this repository. The house pattern is that a tool which can fail a build carries `--selftest`, and that selftest is what CI runs. So the selftest is written first, and it is the failing test.

Create `tools/shard_tests.py` containing **only** the docstring and the selftest, so it fails for the right reason:

```python
#!/usr/bin/env python3
"""Split the GUT suite into shards CI can run in parallel.

The suite is 360 seconds of a 384 second CI run, and the other two jobs are done
inside 73. So the wait is the suite. The suite is 222 scripts with a median
runtime of 0.99s and no hotspot to fix -- which is exactly what makes it worth
dividing rather than optimising. Four shards come out at 89, 89, 95 and 88
seconds.

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


if __name__ == "__main__":
    sys.exit(selftest())
```

- [x] **Step 2: Run it to verify it fails**

Run: `python tools/shard_tests.py`

Expected: `NameError: name 'shard' is not defined`. That is the failure we want — the selftest is exercising a function that does not exist yet.

- [x] **Step 3: Write the minimal implementation**

Insert these two functions **above** `selftest()`:

```python
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
```

- [x] **Step 4: Run the selftest to verify it passes**

Run: `python tools/shard_tests.py`

Expected: `selftest: the split covers the suite exactly once at 1 to 8 shards`, exit 0.

- [x] **Step 5: Add the command line and check it against the real suite**

Replace the `if __name__ == "__main__":` block with a `main()` and the guard:

```python
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
```

Verify against the real suite:

```bash
python tools/shard_tests.py --count
python tools/shard_tests.py --selftest
for n in 1 2 3 4; do
  python tools/shard_tests.py --shard $n --of 4 | tr ',' '\n' | wc -l
done
```

Expected: `222`; the selftest line; then `56`, `56`, `55`, `55` summing to 222.

- [x] **Step 6: Correct the design document's filename**

In `docs/superpowers/specs/2026-09-17-ci-test-sharding-design.md`, replace every `tools/test_shard.py` with `tools/shard_tests.py` (there are three: the heading `### tools/test_shard.py`, the shard command block, and the coverage assertion bullet).

- [x] **Step 7: Run the selftest in CI**

In `.github/workflows/ci.yml`, in the `static-checks` job, add this step immediately after the `Check the CI wait grades the right commit` step:

```yaml
      # The suite is run in four shards and the totals are published from what
      # they report together. A splitter that quietly drops a file gives a green
      # run with less in it, so the split is checked before it is trusted.
      - name: Check the test split still covers the suite
        run: python3 tools/shard_tests.py --selftest
```

- [x] **Step 8: Lint, format and commit**

```bash
ruff check tools/
ruff format tools/
ruff format --check tools/
git add tools/shard_tests.py .github/workflows/ci.yml docs/superpowers/specs/2026-09-17-ci-test-sharding-design.md
git commit -m "Add the test-suite splitter"
```

---

### Task 2: Summing the shard totals

**Files:**
- Modify: `tools/update_test_counts.py`

**Interfaces:**
- Consumes: `tools/shard_tests.py --count` (Task 1), via the `--expect-scripts` value CI passes.
- Produces: `parse_gut_text(text: str, source: str = "<text>") -> dict`; `add_counts(per_shard: list[dict]) -> dict`; `sum_gut_logs(paths: list[str]) -> dict`; `selftest() -> int`. CLI: `--gut-log` becomes repeatable, `--expect-scripts N` and `--selftest` are added.
- The counts dict keys are unchanged: `scripts`, `tests`, `passing`, `asserts`, `risky`, `failing`.

- [x] **Step 1: Write the failing selftest**

Add this to `tools/update_test_counts.py`, immediately above `def main() -> int:`:

```python
# The keys that are simply added together across shards. Every one of them is a
# count of things that happened, so four shards summing to the whole suite is
# the same arithmetic in each case.
SUMMED = ("scripts", "tests", "passing", "asserts", "risky", "failing")


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
```

- [x] **Step 2: Run it to verify it fails**

Run: `python tools/update_test_counts.py --selftest`

Expected: `error: unrecognized arguments: --selftest`. The argument does not exist yet, and neither do `parse_gut_text` or `add_counts`.

- [x] **Step 3: Split the parser so it can be tested without files**

Replace the existing `parse_gut_log` function entirely with these three:

```python
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
        raise SystemExit("update_test_counts: cannot read %s: %s" % (path, problem)) from problem
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
```

Move the `SUMMED` tuple from Step 1's block up to sit directly above `parse_gut_text`, so it is defined before its first use. Delete it from where Step 1 placed it.

- [x] **Step 4: Run the selftest to verify it passes, before the flag exists**

The `--selftest` flag is not added until Step 5, so call the function directly:

```bash
python -c "import sys; sys.path.insert(0,'tools'); import update_test_counts as u; sys.exit(u.selftest())"
```

Expected: `selftest: shard totals add up and a truncated log is refused`, exit 0.

- [x] **Step 5: Wire up the command line**

In `main()`, replace the `--gut-log` argument with these three:

```python
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
```

`--gut-log` loses `required=True`, because `--selftest` takes no logs. Make `--write`/`--check` not required for the same reason: change the mutually exclusive group to `parser.add_mutually_exclusive_group()` and validate below.

Then, at the top of `main()` after `args = parser.parse_args()`:

```python
    if args.selftest:
        return selftest()

    if not args.gut_log:
        parser.error("--gut-log is required unless --selftest is given")
    if not (args.write or args.check):
        parser.error("give --write or --check")
```

And replace `counts = parse_gut_log(args.gut_log)` with:

```python
    counts = sum_gut_logs(args.gut_log)
    if args.expect_scripts is not None and counts["scripts"] != args.expect_scripts:
        raise SystemExit(
            "update_test_counts: the logs account for %d scripts, not %d. A shard "
            "ran fewer scripts than it was given, and publishing this total would "
            "record a smaller suite as measured fact."
            % (counts["scripts"], args.expect_scripts)
        )
```

- [x] **Step 6: Run the selftest through the flag**

Run: `python tools/update_test_counts.py --selftest`

Expected: `selftest: shard totals add up and a truncated log is refused`, exit 0.

- [x] **Step 7: Check the old single-log call still works**

The drift check on `main` and any local use pass one log. Confirm nothing regressed:

```bash
python tools/update_test_counts.py --gut-log <path-to-a-full-gut.log> --check
```

Expected: either `Test counts are current (...)` or a list of stale documents — not a traceback, and not an argparse error.

If no full log is to hand, make one:

```bash
printf 'Totals\n------\nScripts             222\nTests              4093\nPassing Tests      4086\nRisky/Pending         7\nAsserts           19729\n' > /tmp/fake.log
python tools/update_test_counts.py --gut-log /tmp/fake.log --check
```

Expected: `Test counts are current (4,093 tests across 222 scripts, 4,086 passing, 19,729 assertions).`

- [x] **Step 8: Add the selftest to CI, lint, format and commit**

In `.github/workflows/ci.yml`, in `static-checks`, add after the step Task 1 added:

```yaml
      # The five published totals are now added up from four shard logs rather
      # than read from one. That addition is where a wrong number would come
      # from, so it is checked here.
      - name: Check the shard totals still add up
        run: python3 tools/update_test_counts.py --selftest
```

```bash
ruff check tools/
ruff format tools/
ruff format --check tools/
git add tools/update_test_counts.py .github/workflows/ci.yml
git commit -m "Sum the published test counts across shard logs"
```

---

### Task 3: The shard matrix and the aggregate job

**Files:**
- Modify: `.github/workflows/ci.yml:96-204` (replace the whole `unit-tests` job)

**Interfaces:**
- Consumes: `tools/shard_tests.py --shard N --of M` and `--count` (Task 1); `tools/update_test_counts.py --gut-log ... --expect-scripts N` (Task 2).
- Produces: a job named `unit-test-shard` (matrix legs `unit-test-shard (1..4)`) and a job named exactly `GUT Unit Tests`.

- [x] **Step 1: Replace the `unit-tests` job with the shard matrix**

Delete the entire existing `unit-tests:` job and put this in its place:

```yaml
  unit-test-shard:
    name: GUT Shard ${{ matrix.shard }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
    strategy:
      # Every shard's result is wanted, not just the first failure. Stopping at
      # shard 2 hides whatever shard 3 would have said, and then the rerun finds
      # it -- which is the slow way round.
      fail-fast: false
      matrix:
        shard: [1, 2, 3, 4]
    env:
      GODOT_VERSION: "4.7-stable"
      SHARDS: "4"
    steps:
      # Read-only, and no credentials left behind: nothing in a shard writes.
      # The counts commit and its deploy key live in the aggregate job below,
      # which runs none of the test code.
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
        with:
          persist-credentials: false

      - name: Download Godot
        run: |
          wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O godot.zip
          unzip -q godot.zip
          mv "Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot
          chmod +x /usr/local/bin/godot

      - name: Import project
        run: godot --headless --import --path . 2>&1

      - name: Run this shard of the suite
        env:
          SHARD: ${{ matrix.shard }}
        run: |
          set -o pipefail
          # -gconfig= is load-bearing, and deleting it does not fail anything.
          # gut_config.gd applies `dirs` and then `tests` one after the other,
          # so with .gutconfig.json still in play each shard would collect all
          # 222 scripts on top of its own slice: four green runs of the whole
          # suite, four times the work, and nothing anywhere saying so.
          godot --headless -s res://addons/gut/gut_cmdln.gd --path . \
            -gconfig= -gexit -glog=1 \
            -gtest="$(python3 tools/shard_tests.py --shard "$SHARD" --of "$SHARDS")" \
            2>&1 | tee "gut-shard-${SHARD}.log"

      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: gut-shard-${{ matrix.shard }}
          path: gut-shard-${{ matrix.shard }}.log
          # Long enough to read after a failure, short enough not to accumulate.
          retention-days: 3
```

- [x] **Step 2: Add the aggregate job**

Immediately after the shard job, add:

```yaml
  # Named exactly "GUT Unit Tests" because that is what the main ruleset requires.
  # The shard legs above report under their own names and are not required
  # checks; this job speaks for all four.
  unit-tests:
    name: GUT Unit Tests
    runs-on: ubuntu-latest
    needs: unit-test-shard
    # Runs even when a shard failed, so this reports a red X. Without always()
    # it would be *skipped* instead, and a skipped required check never reports
    # at all -- the pull request would sit waiting on it for good.
    if: always()
    permissions:
      contents: read
    env:
      SHARDS: "4"
      OWN_PR: ${{ github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository }}
    steps:
      - name: Fail if any shard failed
        if: needs.unit-test-shard.result != 'success'
        env:
          RESULT: ${{ needs.unit-test-shard.result }}
        run: |
          echo "::error::a GUT shard did not pass ($RESULT)"
          exit 1

      # Same checkout as the old unit-tests job: the head branch and the deploy
      # key on this repository's own pull requests, so the counts commit can
      # land on that branch and start a run of its own.
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7 # zizmor: ignore[artipacked]
        with:
          ref: ${{ env.OWN_PR == 'true' && github.event.pull_request.head.ref || '' }}
          ssh-key: ${{ env.OWN_PR == 'true' && secrets.HF_COUNTS_DEPLOY_KEY || '' }}

      - uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
        with:
          pattern: gut-shard-*
          merge-multiple: true
          path: shard-logs

      - name: Check every shard reported
        run: |
          found=$(find shard-logs -name 'gut-shard-*.log' | wc -l)
          if [ "$found" -ne "$SHARDS" ]; then
            echo "::error::expected $SHARDS shard logs, found $found"
            exit 1
          fi

      # The five documents that quote the size of the suite go stale on any pull
      # request that adds a test. CI has just measured the suite -- in four
      # pieces -- so CI writes the numbers down. --expect-scripts is what stops
      # a shard that ran short from publishing a smaller suite as fact.
      - name: Update published test counts
        if: env.OWN_PR == 'true'
        run: |
          python3 tools/update_test_counts.py --gut-log shard-logs/gut-shard-*.log \
            --expect-scripts "$(python3 tools/shard_tests.py --count)" --write

      - name: Commit the counts to this pull request
        if: env.OWN_PR == 'true'
        env:
          BRANCH: ${{ github.event.pull_request.head.ref }}
        run: |
          # Scoped to exactly the documents update_test_counts.py rewrites.
          DOCS=(README.md docs/features.md DEVELOPMENT.md HammerForge_SPEC.md ROADMAP.md)
          if git diff --quiet -- "${DOCS[@]}"; then
            echo "Counts already current, nothing to commit."
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -- "${DOCS[@]}"
          git commit -m "Update published test counts"
          # Deliberately no [skip ci]: this push must start a run, so the new
          # head commit carries the checks the branch ruleset requires. It
          # cannot loop, because that run measures the same suite, finds the
          # numbers already written, and pushes nothing.
          git push origin "HEAD:${BRANCH}"

      # Two pull requests that each add tests can each write a number that was
      # correct when it was measured, and main ends up between them. The next
      # pull request that touches the suite writes the true figure, since the
      # script writes what it measured rather than a delta -- so this reports
      # rather than fails.
      - name: Report drift in main's published counts
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          if ! python3 tools/update_test_counts.py --gut-log shard-logs/gut-shard-*.log \
            --expect-scripts "$(python3 tools/shard_tests.py --count)" --check; then
            echo "::warning::Published test counts on main are stale. The next pull request that changes the suite will correct them."
          fi
```

- [x] **Step 3: Lint the workflow before pushing it**

`actionlint` and `zizmor` both run in CI, but a broken workflow is exactly the thing you want caught before it is the workflow deciding whether things are broken:

```bash
curl -fsSL -o /tmp/actionlint.tar.gz \
  "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz"
tar -xzf /tmp/actionlint.tar.gz -C /tmp actionlint
/tmp/actionlint -color
```

Expected: no output, exit 0.

On Windows without a Linux shell, skip this and rely on Step 5's push — but read the YAML once for indentation first.

- [x] **Step 4: Prove a shard command actually runs locally**

Do not take the `-gconfig=` behaviour on trust. Run one shard's worth of two scripts:

```bash
cmd //c "C:\Godot\godot.cmd --headless -s res://addons/gut/gut_cmdln.gd --path . -gconfig= -gexit -glog=1 -gtest=res://tests/test_array_limits.gd,res://tests/test_bevel.gd"
```

Expected: a summary block reading `Scripts 2` and `Tests 44`, exit 0. If `Scripts` reads 222, `-gconfig=` is not taking effect and the shards would each run the whole suite.

Then check for an orphan, because headless Godot survives and keeps the project locked:

```bash
powershell -Command "Get-Process -Name godot* -ErrorAction SilentlyContinue | Select-Object Id,StartTime"
```

Expected: nothing.

- [x] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "Run the GUT suite in four shards"
```

---

### Task 4: Land it

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `docs/patterns_and_gotchas.md`

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: nothing code depends on.

- [x] **Step 1: File the issue**

CHANGELOG entries in this repository carry an issue number. File one first so the entry can reference it:

```bash
gh issue create \
  --title "CI runs the whole GUT suite in one job, and that is the whole wait" \
  --body "A CI run is 6m24s at the median. The GUT job is 386s of it and the other two finish inside 73s, so 94% of the critical path is one job running 222 test scripts in series. Median script runtime is 0.99s with no hotspot, so the suite divides cleanly: four shards measure 89/89/95/88s. Design: docs/superpowers/specs/2026-09-17-ci-test-sharding-design.md"
```

Note the number it returns; call it `#NNN` below.

- [x] **Step 2: Write the CHANGELOG entry**

Add to the `### Changed` section under `## [Unreleased]`, matching the density of the entries around it:

```markdown
- **The test suite runs in four shards** (#NNN). A CI run was 6 minutes 24
  seconds, and 94% of that was one job: the GUT suite took 386 seconds while
  the two lint jobs finished inside 73. Per-script timings say there was nothing
  to optimise -- 222 scripts, median runtime 0.99s, 112 of them under a second,
  and the slowest single file 21s -- which is exactly the shape that divides
  instead. `tools/shard_tests.py` splits the scripts round-robin over their
  sorted names, four legs of a matrix run 56/56/55/55 of them in 89/89/95/88
  seconds, and an aggregate job adds the four logs back together. Coverage is
  unchanged: the same 222 scripts and 4,093 tests run, and the aggregate refuses
  to publish a total unless the logs account for every script, because a shard
  that ran short would otherwise write a smaller suite into all five documents
  as measured fact. Path filtering was measured and rejected instead: 53 of the
  last 60 commits touch both `addons/` and `tests/`, and all three job names are
  required checks, so a filtered job reports `skipped` and leaves the pull
  request unmergeable for good.
```

- [x] **Step 3: Record the `-gconfig=` trap**

Add to `docs/patterns_and_gotchas.md`, in whatever section covers test infrastructure:

```markdown
- `-gtest` does not narrow a GUT run on its own. `gut_config.gd` applies `dirs`
  and then `tests` one after the other, so with `.gutconfig.json` in play
  `-gtest` *adds* to the 222 scripts already collected from `res://tests/`.
  `-gconfig=` disables the config file and is what makes `-gtest` mean what it
  says. CI's shard command depends on it, and dropping it fails nothing: every
  shard just runs the whole suite, green and four times slower.
```

- [x] **Step 4: Commit and push the branch**

```bash
git add CHANGELOG.md docs/patterns_and_gotchas.md
git commit -m "Note the sharding change and the -gconfig trap"
git push -u origin ci/shard-the-test-suite
```

- [x] **Step 5: Open the pull request and check the required check name before merging**

```bash
gh pr create --fill
```

Then, and this is the step that matters most in the whole plan:

```bash
gh pr checks --watch
```

Confirm a check named exactly **`GUT Unit Tests`** appears and reports. If it does not — if the only entries are `GUT Shard 1..4` — the required check will never be satisfied and **every open pull request blocks**, not just this one. Fix the job's `name:` and push again before doing anything else.

- [x] **Step 6: Verify the totals and the timing**

```bash
gh run list --workflow=ci.yml --limit 3 --json databaseId,conclusion,createdAt,updatedAt
```

Check two things:

1. The run's wall clock is around 2m15s, not 6m24s.
2. The aggregate's summed totals read **222 scripts, 4,093 tests, 19,729 asserts** — the same numbers the single-job run reported on 17 September 2026. A different script count means the split dropped or duplicated something and `--expect-scripts` should have caught it; investigate before merging rather than adjusting the expectation.

- [x] **Step 7: Merge, with nothing else in flight**

```bash
gh pr list --state open
```

Expected: only this pull request. This rewires the job that gates every merge; if something else is open when the required-check name is wrong, it blocks too. Merge only when this is the sole open pull request.

---

## Self-Review

**Spec coverage.** Every section of the design document maps to a task: job structure and the aggregate's name (Task 3 Steps 1-2); the shard command and why `-gconfig=` is load-bearing (Task 3 Step 1, verified Step 4, recorded Task 4 Step 3); `tools/shard_tests.py` and its selftest (Task 1); the coverage assertion (Task 2 Step 5, `--expect-scripts`, plus the shard-log count check in Task 3 Step 2); summing the counts (Task 2); aggregate failure handling with `if: always()` (Task 3 Step 2); the deploy key moving to the aggregate (Task 3 Steps 1-2); "how to land it" (Task 4 Steps 5-7).

**Two deliberate deviations from the spec**, both noted at the point they occur: the script is `tools/shard_tests.py` rather than `tools/test_shard.py` (Task 1 corrects the spec to match), and `update_test_counts.py` gains its own `--selftest`, which the spec did not call for but the repository's own rule about guards does.

**Naming consistency.** `test_scripts`, `shard`, `selftest`, `parse_gut_text`, `parse_gut_log`, `add_counts`, `sum_gut_logs`, `SUMMED`, `TESTS_DIR`, `RES_PREFIX`, `--shard`, `--of`, `--count`, `--selftest`, `--gut-log`, `--expect-scripts`, `SHARDS`, `OWN_PR`, `unit-test-shard`, `unit-tests` / `GUT Unit Tests` — each is spelled the same way everywhere it appears.

**One ordering hazard worth stating plainly.** Task 2 Step 1 writes `SUMMED` above `main()`; Step 3 moves it above `parse_gut_text`. If the steps are done out of order, `parse_gut_text` will not see it. Step 3 says so explicitly.
