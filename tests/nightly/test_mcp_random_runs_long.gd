extends "res://tests/mcp/mcp_random_run_case.gd"
## Random runs through the bridge at the nightly's length (#1646): 100 seeds of
## 80 calls, each undone all the way back to the starting level, redone all the
## way forward and made again on a fresh level. A failing seed writes its calls
## under `user://hf_random_runs`.
##
## Nightly only: `.github/workflows/nightly.yml` runs this folder. The pull
## request form is `tests/test_mcp_random_runs.gd`, 16 seeds of 40.

const SEEDS := 100
const CALLS := 80
## Seeds apart from the pull request's, so the night covers new runs.
const FIRST_SEED := 1001


func test_long_random_runs_undo_back_to_where_they_started(
	seed_value = use_parameters(range(FIRST_SEED, FIRST_SEED + SEEDS))
):
	var report := await run_seed(seed_value, CALLS)
	for failure in report["failures"]:
		print("random run seed %d: %s" % [seed_value, failure])
	assert_eq(report["failures"], [], "seed %d (calls in %s)" % [seed_value, FAILED_RUNS])
