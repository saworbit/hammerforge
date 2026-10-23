extends "res://tests/support/chaos_seed_case.gd"
## Seeds 16 to 31 of `chaos-io`, edits with save, state and .map round trips,
## each checked after every step and against its recorded line (#1643). The
## seeds are split over files so the CI shards can share them out.

const SCENARIO := "res://tools/vibe/scenarios/chaos_io.gd"


func test_seed(seed_value = use_parameters(range(16, 32))):
	await check_seed(SCENARIO, "chaos-io", seed_value)
