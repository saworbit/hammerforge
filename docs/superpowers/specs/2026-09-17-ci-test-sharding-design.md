# CI Test Sharding — Cut the Wait Without Cutting Coverage

Design document. 17 September 2026.

## Problem

A CI run takes 6 minutes 24 seconds at the median, and almost all of it is one
job waiting on one thing.

Three jobs run in parallel on every push and every pull request:

| Job | Duration | Share of the critical path |
| --- | --- | --- |
| Workflow & Tooling Lint | 12s | — |
| GDScript Lint & Format | 73s | — |
| GUT Unit Tests | 386s | **94%** |

Inside the test job, the Godot download is 2 seconds and the import is 14. The
suite itself is 360. Everything that is not the test suite is already free.

That latency is not paid once. Across the last 100 runs — 11 hours of one sweep
day — there were 83 pull-request runs across 17 branches: **4.9 pushes per pull
request**, two branches at 11 apiece. Every push pays the full 6 minutes, and
because the stacked-pull-request workflow merges serially, CI latency *is* the
critical path through a sweep. The queue either drains or it backs up.

## What the measurement rules out

The obvious answers were measured first, and none of them survive.

**Path filters buy nothing.** Of the last 60 commits, 53 touch both
`addons/` and `tests/`. Around five are docs-only or tools-only. Worse, all
three job names are required status checks on the `main` ruleset, and a
path-filtered job reports `skipped` — which never satisfies a required check, so
the pull request becomes permanently unmergeable. That is real machinery, and a
shim job to work around it, for an 8% hit rate on jobs costing 12 and 73 seconds.

**Caching `.godot/` buys 14 seconds and risks a silent failure.** A stale
`global_script_class_cache.cfg` does not announce itself: the suite reports a
*lower script count* and a cascade of unrelated "Nonexistent function" errors.
Trading that for 14 seconds of a 111-second path is not a trade.

**Fail-fast on lint stops being worth building.** Today a lint failure at 1:13
lets the 6-minute test job burn to completion, because GitHub does not cancel
sibling jobs. After sharding it wastes 111 seconds instead of 366, against a 94%
pass rate (3 failures in 100 runs — two caught by lint, one by the suite).
Making the shards `needs: static-checks` would serialise 73s + 111s and make the
common case *slower*.

**A two-tier suite does not fit the workflow.** Fast subset per push, full suite
before merge — but pull requests here are merged minutes after they are opened,
so the full tier fires almost every time anyway. The complexity is paid; the
wait is not saved.

**Changed-file test selection is the one most likely to hide a defect.**
GDScript offers no import graph to derive the mapping from, so it is
hand-maintained and silently wrong the first time a file is renamed. The vibe
sweep notes record defects turning up outside the area that was touched. This is
exactly the approach that would stop finding them.

## What the measurement points at

Per-script timings pulled from a real run: 222 scripts, median **0.99s**, 112 of
them under a second, the slowest a single 21.2s file
(`test_brush_to_heightmap.gd`). The top 25 scripts are 47% of the suite. There is
no pathological hotspot to fix — which is precisely what makes the suite shard
cleanly.

Round-robin over the sorted filename list, four ways, against the measured
durations:

| | shard 1 | shard 2 | shard 3 | shard 4 |
| --- | --- | --- | --- | --- |
| Time | 89s | 89s | 95s | 88s |
| Scripts | 56 | 56 | 55 | 55 |

With per-shard download and import overhead, the slowest shard lands at about
**111 seconds against 377 today**. The aggregate job is not free and is not
parallel: it waits on all four shards, then checks out, downloads the logs and
sums them, which is another 20 to 30 seconds on the end. Call the whole run
**about 2 minutes 15**.

Four is where the curve flattens. Going from two shards to four saves 89
seconds; four to six saves 17, because that one 21-second file sets the floor.
Beating the floor requires a committed timing manifest, which goes stale the
moment someone adds a slow test and then hands out an unbalanced split without
saying so. Four shards also means four legs that can flake rather than six.

## Scope

1. Split the `unit-tests` job into a four-way shard matrix and an aggregate job.
2. Add `tools/shard_tests.py` to compute the split, with a selftest.
3. Teach `update_test_counts.py` to sum across several shard logs.
4. Assert that the shards together covered every test script.

Coverage does not change. The same 222 scripts and 4,093 tests run.

## Design

### Job structure

`unit-tests` becomes two jobs:

**`unit-test-shard`** — a 1..4 matrix. Each leg takes a plain read-only
checkout, downloads Godot, imports the project, runs its slice, and uploads
`gut-shard-N.log` as an artifact. These legs report as `unit-test-shard (1)`
through `(4)` and are *not* required checks.

**`unit-tests`** — keeps the job name `GUT Unit Tests` exactly, so the ruleset's
required checks need no edit at all. It declares `needs: unit-test-shard`,
downloads the four logs, verifies coverage, sums the counts, and then does the
existing write / commit / drift-report work unchanged.

### The shard command

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd --path . \
  -gconfig= -gexit -glog=1 \
  -gtest="$(python3 tools/shard_tests.py --shard "$SHARD" --of 4)"
```

`-gconfig=` is load-bearing, and the workflow needs a comment saying so.
`gut_config.gd` applies `dirs` and then `tests` one after the other:

```gdscript
for i in range(opts.dirs.size()):
    gut.add_directory(opts.dirs[i], opts.prefix, opts.suffix)

for i in range(opts.tests.size()):
    gut.add_script(opts.tests[i])
```

They are additive, not a filter. That is the mechanism behind the recorded
gotcha that `-gtest` does not narrow the run when `.gutconfig.json` sets `dirs`.
Leave the config file in play and every shard collects all 222 scripts anyway:
still green, four times the work, and no signal that anything is wrong. Disabling
the config file is what makes `-gtest` mean what it says.

Verified against the real suite before writing this document: two named scripts
produced `Scripts 2` and `Tests 44`, and nothing else was collected.

### `tools/shard_tests.py`

Round-robin over the sorted filename list. Shards are numbered from 1 to match
the matrix, so the file at position `index` belongs to the shard where
`index % of == shard - 1`. No timing manifest to maintain, and nothing to drift.

- `--shard N --of M` prints the comma-separated `res://tests/...` paths
- `--count` prints the number of `test_*.gd` files
- `--selftest` proves the shards partition the set exactly: every file in exactly
  one shard, none dropped, none duplicated, for every M from 1 to 8

The selftest runs in `static-checks` beside the other guards, for the same reason
they are there — a splitter that cannot fail its own check is a splitter nobody
is checking.

### The coverage assertion

GUT's summary block prints `Scripts 222` — exactly the number of files on disk.
The aggregate job hard-fails when either:

- a shard log is missing, or
- the summed `Scripts` does not equal `tools/shard_tests.py --count`.

Without this, a shard that dies early yields a quietly smaller total, and CI
writes that smaller number into all five published documents as measured fact.
That is the failure `tests/test_suite_integrity.gd` already exists to prevent —
coverage disappearing behind a plausible number — one level up, where sharding
now makes it possible again.

### Summing the counts

`update_test_counts.py` gains a repeatable `--gut-log` and adds up `scripts`,
`tests`, `passing`, `asserts`, `risky` and `failing`. Its existing regexes work
unchanged on a shard log: the summary block format is identical, and the script
already treats `Risky/Pending` and `Failing Tests` as absent when zero.

Counts travel as artifacts rather than job outputs, because every leg of a matrix
writes the same output key and the last one to finish wins.

### Aggregate failure handling

The aggregate runs `if: always()`, and its first step fails explicitly when
`needs.unit-test-shard.result != 'success'`. Without `always()` the aggregate is
*skipped* when a shard fails, and a skipped required check leaves the pull
request showing "expected" indefinitely instead of a clear red X. The counts
steps stay gated on success.

### Where the deploy key goes

The counts commit moves to the aggregate job, and the `HF_COUNTS_DEPLOY_KEY`
checkout goes with it. The shards take ordinary read-only checkouts. This is a
small security improvement that falls out of the change rather than motivating
it: the key stops being present on the job that executes every line of test code,
and sits instead on a job that executes none of it.

## Expected result

| | Now | After |
| --- | --- | --- |
| Wall clock per run | 6m24s | ~2m15s |
| Scripts / tests run | 222 / 4,093 | 222 / 4,093 |
| Job-minutes per run | ~7.9 | ~9 |

Job-minutes go *up* by about one, buying three extra Godot downloads and imports.
The repository is public, so those minutes are free, and latency is what was
asked for.

## Risks

**`-gconfig=` gets dropped by a later edit.** The shards silently go back to
running the whole suite each: green, four times slower, no signal. Mitigated by a
comment at the call site and an entry in the patterns file.

**The aggregate job name drifts from `GUT Unit Tests`.** The required check then
never reports and *every* open pull request becomes unmergeable at once.
Recoverable only by editing the ruleset.

**A shard flakes.** One leg failing fails the aggregate, as it must. Four legs
carry more of this risk than one job did; six would carry more still, which is
part of why the shard count stops at four.

## Testing

- `tools/shard_tests.py --selftest` in `static-checks`, with the other guards.
- `ruff` and `gdformat` already cover `tools/`, so the new script is linted by
  the existing jobs.
- Before merging: compare the aggregate's summed totals against the last
  full-suite run. They must read 222 / 4,093 / 19,729 asserts.

## How to land it

As its own pull request, with nothing else in flight. This rewires the job that
gates every merge, and the failure mode of getting the required-check name wrong
is that every open pull request blocks simultaneously. Push the branch, confirm
on the pull request that a check named `GUT Unit Tests` appears and reports, and
only then merge.
