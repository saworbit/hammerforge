extends "res://tests/mcp/mcp_dispatcher_case.gd"

## Cordons over the bridge (#1300): hf_get_cordons lists them, hf_set_cordon adds
## or changes one and hf_remove_cordon takes one out. Each change is one undo step
## that holds the cordons, which no level state does, so a refused batch and an
## undone one put them back too, and the dock is told every time.


func _set_cordon(params: Dictionary) -> Dictionary:
	return await call_tool("hf_set_cordon", params)


## The cordons and the undo history, for "a refusal changed nothing".
func _cordon_snapshot(level: LevelRoot) -> Dictionary:
	return {
		"cordons": level.capture_cordons(),
		"steps": undo.scene_history.get_history_count(),
	}


## A level with three named cordons, the middle one switched off.
func _three_cordons() -> LevelRoot:
	var level := make_level()
	level.set_cordon_region(0, AABB(Vector3(0, 0, 0), Vector3(2, 2, 2)))
	level.set_cordon_region(1, AABB(Vector3(10, 0, 0), Vector3(2, 2, 2)))
	level.set_cordon_region(2, AABB(Vector3(20, 0, 0), Vector3(2, 2, 2)))
	level.set_cordon_name(0, "A")
	level.set_cordon_name(1, "B")
	level.set_cordon_name(2, "C")
	level.set_cordon_active(1, false)
	return level


func _names(answer: Dictionary) -> Array:
	var out: Array = []
	for cordon in answer["cordons"]:
		out.append(cordon["name"])
	return out


# --- hf_get_cordons ----------------------------------------------------------


func test_a_new_level_lists_its_one_cordon_off():
	make_level()
	var r := await call_tool("hf_get_cordons")
	assert_true(r["ok"], str(r))
	var got: Dictionary = r["result"]
	assert_false(got["enabled"])
	assert_false(got["partial_bake"], "cordons off, so a bake takes the whole level")
	assert_eq(got["cordons"].size(), 1)
	assert_eq_deep(
		got["cordons"][0],
		{
			"index": 0,
			"name": "Cordon 1",
			"min": [-128.0, -128.0, -128.0],
			"max": [128.0, 128.0, 128.0],
			"active": true,
		}
	)
	assert_eq(undo.scene_history.get_history_count(), 0, "a read records nothing")


func test_get_cordons_reads_names_switches_and_corners():
	var level := _three_cordons()
	# Given corners the wrong way round, the level stores the box right way out.
	level.set_cordon_region(2, AABB(Vector3(22, 2, 2), Vector3(-2, -2, -2)))
	var r := await call_tool("hf_get_cordons")
	assert_eq(_names(r["result"]), ["A", "B", "C"])
	assert_false(r["result"]["cordons"][1]["active"])
	assert_eq(r["result"]["cordons"][2]["min"], [20.0, 0.0, 0.0])
	assert_eq(r["result"]["cordons"][2]["max"], [22.0, 2.0, 2.0])


# --- hf_set_cordon: adding ---------------------------------------------------


func test_a_cordon_added_round_brushes_switches_cordons_on():
	var level := make_level()
	var id := await place_box([10, 1, 0], [4, 2, 4])
	var r := await _set_cordon({"brush_ids": [id]})
	assert_true(r["ok"], str(r))
	var got: Dictionary = r["result"]
	assert_true(got["added"])
	assert_eq(got["cordons"].size(), 2)
	# The box round the brush grown by a unit, as Add Cordon from Selection makes.
	assert_eq_deep(
		got["cordon"],
		{
			"index": 1,
			"name": "Cordon 2",
			"min": [7.0, -1.0, -3.0],
			"max": [13.0, 3.0, 3.0],
			"active": true
		}
	)
	assert_true(got["enabled"], "a cordon given a place switches cordons on")
	assert_true(got["partial_bake"])
	assert_true(level.cordon_enabled)
	assert_eq(level.get_all_cordon_regions().size(), 2)
	assert_eq(undo.scene_history.get_current_action_name(), "MCP: set cordon")


func test_a_cordon_added_at_bounds_takes_its_corners_either_way_round():
	var level := make_level()
	var r := await _set_cordon({"bounds": {"min": [4, 3, 2], "max": [-4, -1, -2]}})
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["cordon"]["min"], [-4.0, -1.0, -2.0])
	assert_eq(r["result"]["cordon"]["max"], [4.0, 3.0, 2.0])
	assert_true(r["result"]["cordon"]["active"])
	assert_true(level.cordon_enabled, "bounds switch cordons on as brushes do")
	assert_eq(level.get_all_cordon_regions()[1], AABB(Vector3(-4, -1, -2), Vector3(8, 4, 4)))


func test_what_is_given_beside_a_place_wins():
	var level := make_level()
	var r := await _set_cordon(
		{
			"bounds": {"min": [0, 0, 0], "max": [2, 2, 2]},
			"name": "Atrium",
			"active": false,
			"enabled": false,
		}
	)
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["cordon"]["name"], "Atrium")
	assert_false(r["result"]["cordon"]["active"])
	assert_false(level.cordon_enabled)
	assert_eq(undo.scene_history.get_history_count(), 1, "all of it one step")


func test_a_brush_placed_earlier_in_a_batch_can_be_cordoned():
	var level := make_level()
	var ops := [
		{"tool": "hf_place_brush", "params": {"size": [4, 2, 4], "position": [30, 1, 0]}},
		{"tool": "hf_set_cordon", "params": {"brush_ids": ["$0.brush_id"], "name": "Far room"}},
	]
	var r := await call_tool("hf_batch", {"ops": ops})
	assert_true(r["ok"], str(r))
	var cordon: Dictionary = r["result"]["results"][1]["result"]["cordon"]
	assert_eq(cordon["name"], "Far room")
	assert_eq(cordon["min"], [27.0, -1.0, -3.0])
	assert_eq(cordon["max"], [33.0, 3.0, 3.0])
	assert_eq(level.get_all_cordon_regions().size(), 2)
	assert_eq(undo.scene_history.get_history_count(), 1)


# --- hf_set_cordon: changing one ---------------------------------------------


func test_a_cordon_is_named_and_switched_by_index():
	var level := _three_cordons()
	var r := await _set_cordon({"index": 2, "name": "  Vault  ", "active": false})
	assert_true(r["ok"], str(r))
	assert_false(r["result"]["added"])
	assert_eq(r["result"]["cordon"]["name"], "Vault", "trimmed, as the dock trims it")
	assert_false(level.is_cordon_active(2))
	assert_false(level.cordon_enabled, "naming and switching one leaves cordons as they were")
	var renamed := await _set_cordon({"index": 2, "name": ""})
	assert_eq(renamed["result"]["cordon"]["name"], "Cordon 3", "an empty name goes back")


func test_a_cordon_moved_by_index_keeps_its_name():
	var level := _three_cordons()
	var r := await _set_cordon({"index": 1, "bounds": {"min": [50, 0, 0], "max": [60, 4, 10]}})
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["cordon"]["name"], "B")
	assert_true(r["result"]["cordon"]["active"], "a cordon given a place is switched on")
	assert_eq(level.get_all_cordon_regions()[1], AABB(Vector3(50, 0, 0), Vector3(10, 4, 10)))
	assert_eq(level.get_all_cordon_regions().size(), 3)


func test_enabled_alone_switches_every_cordon():
	var level := _three_cordons()
	var on := await _set_cordon({"enabled": true})
	assert_true(on["ok"], str(on))
	assert_true(level.cordon_enabled)
	assert_null(on["result"]["cordon"], "no one cordon was named")
	assert_true(on["result"]["partial_bake"])
	var off := await _set_cordon({"enabled": false})
	assert_false(level.cordon_enabled)
	assert_false(off["result"]["partial_bake"])
	assert_false(level.is_cordon_active(1), "each keeps its own switch")


func test_partial_bake_is_off_while_every_cordon_is_switched_off():
	var level := make_level()
	var r := await _set_cordon({"index": 0, "active": false, "enabled": true})
	assert_true(r["result"]["enabled"])
	assert_false(r["result"]["partial_bake"], "nothing switched on, so the whole level bakes")
	assert_eq(level.get_cordon_regions().size(), 0)


# --- hf_remove_cordon ----------------------------------------------------------


func test_removing_one_moves_the_later_ones_up_with_their_names_and_switches():
	var level := _three_cordons()
	var r := await call_tool("hf_remove_cordon", {"index": 0})
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["removed"]["name"], "A")
	assert_eq(_names(r["result"]), ["B", "C"])
	assert_false(r["result"]["cordons"][0]["active"], "B's switch went with it")
	assert_true(level.is_cordon_active(1))
	assert_eq(level.get_all_cordon_regions()[0], AABB(Vector3(10, 0, 0), Vector3(2, 2, 2)))
	assert_eq(undo.scene_history.get_current_action_name(), "MCP: remove cordon")


func test_the_last_cordon_cannot_go():
	var level := make_level()
	var before := _cordon_snapshot(level)
	var r := await call_tool("hf_remove_cordon", {"index": 0})
	assert_refused(r, "operation_failed")
	assert_string_contains(r["error"]["message"], "active false")
	assert_eq_deep(_cordon_snapshot(level), before)


# --- Refusals ------------------------------------------------------------------


func test_a_refusal_changes_nothing_and_records_no_step():
	var level := _three_cordons()
	var id := await place_box()
	var flat := {"min": [0, 0, 0], "max": [4, 0, 4]}
	var cases := {
		"an index past the last": ["hf_set_cordon", {"index": 3, "name": "x"}, "invalid_argument"],
		"a negative index": ["hf_set_cordon", {"index": -1, "active": true}, "invalid_argument"],
		"a fractional index": ["hf_remove_cordon", {"index": 0.5}, "invalid_argument"],
		"no index to remove": ["hf_remove_cordon", {}, "invalid_argument"],
		"brushes and bounds":
		["hf_set_cordon", {"brush_ids": [id], "bounds": flat}, "invalid_argument"],
		"no brushes": ["hf_set_cordon", {"brush_ids": []}, "invalid_argument"],
		"an empty id": ["hf_set_cordon", {"brush_ids": [""]}, "invalid_argument"],
		"an unknown brush": ["hf_set_cordon", {"brush_ids": [id, "nope"]}, "brush_not_found"],
		"a box of no depth": ["hf_set_cordon", {"bounds": flat}, "invalid_argument"],
		"half a box": ["hf_set_cordon", {"bounds": {"min": [0, 0, 0]}}, "invalid_argument"],
		"a name for no cordon": ["hf_set_cordon", {"name": "x"}, "invalid_argument"],
		"nothing to change": ["hf_set_cordon", {"index": 1}, "invalid_argument"],
		"nothing at all": ["hf_set_cordon", {}, "invalid_argument"],
		"a switch that is not one":
		["hf_set_cordon", {"index": 0, "active": 1}, "invalid_argument"],
		"a name that is not text": ["hf_set_cordon", {"index": 0, "name": 7}, "invalid_argument"],
	}
	var before := _cordon_snapshot(level)
	for case_name in cases:
		var spec: Array = cases[case_name]
		assert_refused(await call_tool(spec[0], spec[1]), spec[2], case_name)
		assert_eq_deep(_cordon_snapshot(level), before)


func test_an_index_refusal_says_which_cordons_there_are():
	_three_cordons()
	var r := await _set_cordon({"index": 9, "name": "x"})
	assert_string_contains(r["error"]["message"], "from 0 to 2")
	assert_string_contains(r["error"]["message"], "leave it out to add one")


# --- Undo, rollback and the dock -----------------------------------------------


func test_undo_and_redo_put_the_cordons_back_and_leave_the_brushes():
	var level := make_level()
	var id := await place_box([10, 1, 0], [4, 2, 4])
	var before: Dictionary = level.capture_cordons()
	assert_true((await _set_cordon({"brush_ids": [id], "name": "Room"}))["ok"])
	var after: Dictionary = level.capture_cordons()
	var undone := await call_tool("hf_undo")
	assert_true(undone["ok"], str(undone))
	assert_eq(undone["result"]["undone"], "MCP: set cordon")
	assert_eq_deep(level.capture_cordons(), before)
	assert_not_null(brush_node(level, id), "a cordon step holds no brush")
	var redone := await call_tool("hf_redo")
	assert_true(redone["ok"], str(redone))
	assert_eq_deep(level.capture_cordons(), after)


func test_a_removed_cordon_comes_back_on_undo_with_its_name():
	var level := _three_cordons()
	var before: Dictionary = level.capture_cordons()
	await call_tool("hf_remove_cordon", {"index": 1})
	undo.scene_history.undo()
	assert_eq_deep(level.capture_cordons(), before)


func test_a_refused_batch_puts_the_cordons_back():
	var level := make_level()
	await place_box()
	var before := snapshot(level)
	var cordons_before: Dictionary = level.capture_cordons()
	var ops := [
		{"tool": "hf_set_cordon", "params": {"bounds": {"min": [0, 0, 0], "max": [2, 2, 2]}}},
		{"tool": "hf_set_cordon", "params": {"index": 0, "name": "Hall", "enabled": true}},
		{"tool": "hf_delete_brush", "params": {"brush_id": "nope"}},
	]
	var r := await call_tool("hf_batch", {"ops": ops})
	assert_refused(r, "batch_failed")
	assert_eq(int(r["error"]["details"]["index"]), 2)
	assert_true(r["error"]["details"]["rolled_back"])
	assert_eq_deep(level.capture_cordons(), cordons_before)
	assert_eq_deep(snapshot(level), before)


func test_an_undone_batch_takes_back_its_brushes_and_its_cordons():
	var level := make_level()
	var cordons_before: Dictionary = level.capture_cordons()
	var ops := [
		{"tool": "hf_place_brush", "params": {"size": [4, 2, 4], "position": [30, 1, 0]}},
		{"tool": "hf_set_cordon", "params": {"brush_ids": ["$0.brush_id"]}},
	]
	assert_true((await call_tool("hf_batch", {"ops": ops}))["ok"])
	var cordons_after: Dictionary = level.capture_cordons()
	assert_true((await call_tool("hf_undo"))["ok"])
	assert_eq(brushes(level).size(), 0)
	assert_eq_deep(level.capture_cordons(), cordons_before)
	assert_true((await call_tool("hf_redo"))["ok"])
	assert_eq(brushes(level).size(), 1)
	assert_eq_deep(level.capture_cordons(), cordons_after)


func test_every_cordon_change_tells_the_dock():
	var level := _three_cordons()
	watch_signals(level)
	await _set_cordon({"index": 0, "name": "Hall"})
	assert_signal_emit_count(level, "settings_applied", 1, "a set")
	await call_tool("hf_remove_cordon", {"index": 2})
	assert_signal_emit_count(level, "settings_applied", 2, "a remove")
	await call_tool("hf_undo")
	assert_signal_emit_count(level, "settings_applied", 3, "an undo")


func test_a_refusal_does_not_disturb_the_dock():
	var level := _three_cordons()
	watch_signals(level)
	await _set_cordon({"index": 7, "name": "x"})
	assert_signal_not_emitted(level, "settings_applied")
