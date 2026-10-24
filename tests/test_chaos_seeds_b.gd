extends "res://tests/support/chaos_seed_case.gd"
## Seeds 24 to 47 of `chaos`, the brush operations, each checked after every
## step and against its recorded line (#1643). The seeds are split over files so
## the CI shards can share them out.

const SCENARIO := "res://tools/vibe/scenarios/chaos.gd"


func test_seed(seed_value = use_parameters(range(24, 48))):
	await check_seed(SCENARIO, "chaos", seed_value)
