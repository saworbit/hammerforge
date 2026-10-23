extends GutTest

## A failing chaos run cut down to the steps that matter (#1644).

const ChaosShrink = preload("res://tools/vibe/chaos_shrink.gd")
const Regressions = preload("res://tests/test_chaos_regressions.gd")

const SCRATCH := "user://hf_test_chaos_shrink"


## The chaos scenario with a break planted in it: `plant_b` after `plant_a`
## breaks the level, whatever else happened in between.
class Planted:
	extends "res://tools/vibe/scenarios/chaos.gd"

	var _armed := false
	var _broken := false

	func _begin() -> void:
		super._begin()
		_armed = false
		_broken = false

	func perform(root: Node3D, data: Dictionary) -> void:
		match str(data.get("op", "")):
			"plant_a":
				_armed = true
			"plant_b":
				_broken = _broken or _armed
			_:
				super.perform(root, data)

	## No structures, so the level stays small and the replays quick.
	func draw(rng: RandomNumberGenerator, op: String, count: int) -> Dictionary:
		var data := super.draw(rng, op, count)
		if op == "generate":
			return {"op": "none"}
		return data

	func step_problems(root: Node3D) -> Array:
		var problems := super.step_problems(root)
		if _broken:
			problems.append(
				"planted break with %d brushes" % root.draft_brushes_node.get_child_count()
			)
		return problems


func after_each() -> void:
	var folder := ProjectSettings.globalize_path(SCRATCH)
	if DirAccess.dir_exists_absolute(folder):
		for file_name in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(file_name))
		DirAccess.remove_absolute(folder)


## The planted run, made once for the tests that use it.
static var _planted: Array = []


## 150 ordinary steps from a seed, with `plant_a` at 40 and `plant_b` last.
func _planted_run() -> Array:
	if not _planted.is_empty():
		return _planted.duplicate(true)
	var source := Planted.new(get_tree())
	source.seed_value = 7
	source.steps = 149
	await source.run()
	await _drop_new_roots()
	var list: Array = source.taken.duplicate()
	list.insert(40, {"op": "plant_a"})
	list.append({"op": "plant_b"})
	_planted = list
	return list.duplicate(true)


func _levels() -> int:
	return get_tree().root.get_children().filter(func(child): return child is LevelRoot).size()


func _drop_new_roots() -> void:
	for child in get_tree().root.get_children():
		if child is LevelRoot:
			get_tree().root.remove_child(child)
			child.queue_free()
	await get_tree().process_frame


func test_numbers_are_masked_when_problems_are_compared():
	assert_eq(
		ChaosShrink.masked("brush 4986821_100 has 4 open edges"), "brush N_N has N open edges"
	)
	assert_eq(ChaosShrink.masked("size 2.5 on 7"), "size N on N")


func test_a_planted_break_at_step_150_shrinks_to_its_two_steps():
	var list := await _planted_run()
	var scenario := Planted.new(get_tree())
	var found: Dictionary = await scenario.replay(list)
	assert_eq(int(found.get("step", -1)), 150, "the whole run breaks at step 150")
	var shrinker = ChaosShrink.new(scenario, 120000)
	var shrunk: Array = await shrinker.shrink(list, str(found["problem"]), int(found["step"]))
	assert_lte(shrunk.size(), 5, "five steps or fewer")
	var ops := shrunk.map(func(step): return step["op"])
	assert_true(ops.has("plant_a") and ops.has("plant_b"), "the two that matter stay: %s" % [ops])
	assert_lt(ops.find("plant_a"), ops.find("plant_b"), "in their order")
	assert_false(shrinker.capped)


func test_a_shrunk_case_fails_on_its_own_from_a_fresh_level():
	var list := await _planted_run()
	var scenario := Planted.new(get_tree())
	var found: Dictionary = await scenario.replay(list)
	var shrinker = ChaosShrink.new(scenario, 120000)
	var shrunk: Array = await shrinker.shrink(list, str(found["problem"]), int(found["step"]))
	var path := ChaosShrink.record(7, 150, str(found["problem"]), shrunk, false, SCRATCH)
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(path)), OK, "the file reads")
	var levels_before := _levels()
	var again: Dictionary = await Planted.new(get_tree()).replay(json.data["steps"])
	assert_eq(_levels(), levels_before, "the replay drops the level it made")
	assert_false(again.is_empty(), "it still breaks")
	assert_eq(ChaosShrink.masked(str(again.get("problem", ""))), json.data["problem"])


func test_the_shrink_stops_at_its_time_cap_and_still_writes_what_it_has():
	var list := await _planted_run()
	var scenario := Planted.new(get_tree())
	var found: Dictionary = await scenario.replay(list)
	var shrinker = ChaosShrink.new(scenario, 0)
	var shrunk: Array = await shrinker.shrink(list, str(found["problem"]), int(found["step"]))
	assert_true(shrinker.capped, "stopped at the cap")
	assert_eq(shrunk.size(), list.size(), "with the list it had")
	var path := ChaosShrink.record(7, 150, str(found["problem"]), shrunk, true, SCRATCH)
	assert_true(FileAccess.file_exists(path))
	assert_string_contains(FileAccess.get_file_as_string(path), '"capped": true')


func test_the_regression_runner_reads_a_case_and_names_what_broke():
	var path := ChaosShrink.record(
		1,
		1,
		"brush N has N open edges",
		[{"op": "create", "shape": 0, "size": [8, 8, 8], "center": [0, 0, 0], "sides": 4}],
		false,
		SCRATCH
	)
	assert_eq(Regressions.cases(SCRATCH), PackedStringArray([path]))
	var runner = Regressions.new()
	add_child_autofree(runner)
	assert_eq(await runner.replay_case(path), [], "a case with nothing broken passes")
