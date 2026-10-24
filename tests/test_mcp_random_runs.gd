extends "res://tests/mcp/mcp_random_run_case.gd"
## Random runs through the bridge on every PR (#1646): 16 seeds of 40 calls each,
## undone all the way back to the starting level, redone all the way forward, and
## made again on a fresh level. The nightly run has 100 seeds of 80
## (`tests/nightly/test_mcp_random_runs_long.gd`).

const SEEDS := 16
const CALLS := 40


func test_a_random_run_undoes_back_to_where_it_started(
	seed_value = use_parameters(range(1, SEEDS + 1))
):
	var report := await run_seed(seed_value, CALLS)
	for failure in report["failures"]:
		print("random run seed %d: %s" % [seed_value, failure])
	assert_eq(report["failures"], [], "seed %d (calls in %s)" % [seed_value, FAILED_RUNS])
	assert_gt(
		int(report["steps"]), CALLS / 2, "seed %d made most of its calls into steps" % seed_value
	)
