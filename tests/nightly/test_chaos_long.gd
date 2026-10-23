extends "res://tests/support/chaos_seed_case.gd"

## The chaos scenarios at 300 steps over more seeds than a pull request runs
## (#1643). Each step's checks still fail a seed and name the step and the
## operation; there is no recorded line at this length, so where a run ends is
## not compared.
##
## Nightly only: `.github/workflows/nightly.yml` runs this folder, and the suite
## every pull request runs does not look in it. The pull request form is the
## `test_chaos_*seeds*.gd` scripts, at 60 steps against `tests/goldens/chaos.json`.

const LONG_STEPS := 300


func _long(scenario_path: String, scenario: String, seed_value: int) -> void:
	var run := await run_seed(scenario_path, seed_value, LONG_STEPS)
	for line in run["flags"]:
		fail_test("%s seed %d at %d steps: %s" % [scenario, seed_value, LONG_STEPS, line])
	assert_false(
		(run["outcome"] as Dictionary).is_empty(), "%s seed %d ran" % [scenario, seed_value]
	)


func test_chaos(seed_value = use_parameters(range(0, 64))):
	await _long("res://tools/vibe/scenarios/chaos.gd", "chaos", seed_value)


func test_chaos_io(seed_value = use_parameters(range(0, 48))):
	await _long("res://tools/vibe/scenarios/chaos_io.gd", "chaos-io", seed_value)


func test_chaos_systems(seed_value = use_parameters(range(0, 96))):
	await _long("res://tools/vibe/scenarios/chaos_systems.gd", "chaos-systems", seed_value)
