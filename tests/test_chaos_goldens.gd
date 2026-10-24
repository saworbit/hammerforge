extends "res://tests/support/chaos_seed_case.gd"
## The recorded chaos lines and how they are accepted (#1643).

const SCRATCH := "user://hf_test_chaos_goldens.json"


func after_each() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _line(brushes: int, volume: float) -> Dictionary:
	return {"brushes": brushes, "volume": volume, "bounds": [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]}


func test_a_seed_run_twice_ends_on_the_same_line():
	for scenario in ["chaos.gd", "chaos_systems.gd"]:
		var path: String = "res://tools/vibe/scenarios/" + scenario
		var first := await run_seed(path, 5)
		var second := await run_seed(path, 5)
		assert_false((first["outcome"] as Dictionary).is_empty(), "%s has an outcome" % scenario)
		assert_eq(
			HFChaosGoldens.rounded(second["outcome"]),
			HFChaosGoldens.rounded(first["outcome"]),
			"%s seed 5 twice" % scenario
		)


func test_every_seed_has_a_recorded_line():
	var goldens := HFChaosGoldens.new()
	assert_eq(int(goldens.data.get("steps", 0)), STEPS, "recorded at the steps the seeds run")
	for scenario in HFChaosGoldens.SCENARIOS:
		var missing: Array = []
		for seed_value in 48:
			if goldens.recorded(scenario, seed_value).is_empty():
				missing.append(seed_value)
		assert_eq(missing, [], "%s seeds with no line" % scenario)


func test_a_blank_reason_records_nothing():
	var goldens := HFChaosGoldens.new(SCRATCH)
	assert_false(goldens.bless("chaos", 0, _line(3, 10.0), "  "))
	assert_false(FileAccess.file_exists(SCRATCH), "nothing written")


func test_a_reason_rewrites_only_the_seeds_that_moved_and_says_why():
	var goldens := HFChaosGoldens.new(SCRATCH)
	goldens.bless("chaos", 0, _line(3, 10.0), "first", "2026-10-01")
	goldens.bless("chaos", 1, _line(4, 20.0), "first", "2026-10-01")
	goldens = HFChaosGoldens.new(SCRATCH)
	assert_false(
		goldens.bless("chaos", 0, _line(3, 10.0000001), "second", "2026-10-02"),
		"a seed that did not move is left alone"
	)
	assert_true(goldens.bless("chaos", 1, _line(5, 20.0), "second", "2026-10-02"))
	var again := HFChaosGoldens.new(SCRATCH)
	assert_eq(int(again.recorded("chaos", 0)["brushes"]), 3)
	assert_eq(int(again.recorded("chaos", 1)["brushes"]), 5)
	var notes: Array = again.data["notes"]
	assert_eq(notes.size(), 2, "one note a reason")
	assert_eq(str(notes[1]["reason"]), "second")
	assert_eq(JSON.stringify(notes[1]["seeds"]), '{"chaos":[1]}', "names only the seed that moved")
	var text := FileAccess.get_file_as_string(SCRATCH)
	assert_false(
		text.contains("3.0") or text.contains("5.0"), "counts are written as whole numbers"
	)


func test_a_count_must_match_and_a_volume_may_wobble():
	var was := _line(3, 1000.0)
	assert_eq(HFChaosGoldens.differences(was, _line(3, 1000.05)), [], "within a ten thousandth")
	var moved := HFChaosGoldens.differences(was, _line(4, 1000.5))
	assert_eq(moved.size(), 2)
	assert_string_contains(moved[0], "brushes 3 -> 4")
	assert_string_contains(moved[1], "volume")
	var bounds := _line(3, 1000.0)
	bounds["bounds"] = [0.0, 0.0, 0.0, 1.0, 1.0, 1.5]
	assert_eq(HFChaosGoldens.differences(was, bounds).size(), 1, "the bounds moved")
