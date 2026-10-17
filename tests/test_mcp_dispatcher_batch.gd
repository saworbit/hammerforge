extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_batch: several changes as one undo step, all or nothing. A later op can
## name a brush an earlier op made as "$N.brush_id".


## A level whose brush creation makes the brush and then reports failure, the
## way an apply can change the level before it fails.
class BrushThenFailLevel:
	extends LevelRoot

	func create_brush_from_info(info: Dictionary) -> Node:
		super.create_brush_from_info(info)
		return null


func _place(x: float) -> Dictionary:
	return {"tool": "hf_place_brush", "params": {"size": [2, 2, 2], "position": [x, 1, 0]}}


func test_a_batch_is_one_step_and_undoes_in_one():
	var level := make_level()
	var ops := [
		_place(0),
		_place(4),
		_place(8),
		{
			"tool": "hf_transform_brush",
			"params": {"brush_id": "$0.brush_id", "position": [0, 5, 0]}
		},
	]
	var r := await call_tool("hf_batch", {"ops": ops})
	assert_true(r["ok"], str(r))
	var results: Array = r["result"]["results"]
	assert_eq(results.size(), 4)
	assert_eq(brushes(level).size(), 3)
	var moved_id: String = results[0]["result"]["brush"]["brush_id"]
	assert_eq(
		brush_node(level, moved_id).global_position,
		Vector3(0, 5, 0),
		"the reference reached op 0's brush"
	)
	assert_eq(undo.scene_history.get_history_count(), 1)
	assert_eq(undo.scene_history.get_current_action_name(), "MCP: batch (4 ops)")
	var undone := await call_tool("hf_undo")
	assert_true(undone["ok"], str(undone))
	assert_eq(brushes(level).size(), 0, "one undo takes the whole batch back")


func test_a_failure_part_way_leaves_the_level_as_it_was():
	var level := make_level()
	await place_box([20, 1, 0])
	var before := snapshot(level)
	var ops := [
		_place(0),
		_place(4),
		{"tool": "hf_delete_brush", "params": {"brush_id": "no_such_brush"}},
		_place(8),
	]
	var r := await call_tool("hf_batch", {"ops": ops})
	assert_refused(r, "batch_failed")
	assert_eq(int(r["error"]["details"]["index"]), 2)
	assert_eq(r["error"]["details"]["error"]["code"], "brush_not_found")
	assert_true(r["error"]["details"]["rolled_back"])
	assert_eq_deep(snapshot(level), before)


func test_bad_references_are_refused():
	var level := make_level()
	var before := snapshot(level)
	var forward := [
		{
			"tool": "hf_transform_brush",
			"params": {"brush_id": "$1.brush_id", "position": [0, 0, 0]}
		},
		_place(0),
	]
	var r := await call_tool("hf_batch", {"ops": forward})
	assert_refused(r, "batch_failed", "a forward reference")
	assert_eq(r["error"]["details"]["error"]["code"], "invalid_argument")
	var no_brush := [
		_place(0),
		{"tool": "hf_delete_brush", "params": {"brush_id": "$0.brush_id"}},
		{
			"tool": "hf_transform_brush",
			"params": {"brush_id": "$1.brush_id", "position": [0, 0, 0]}
		},
	]
	var r2 := await call_tool("hf_batch", {"ops": no_brush})
	assert_refused(r2, "batch_failed", "a delete makes no brush")
	assert_eq(int(r2["error"]["details"]["index"]), 2)
	assert_eq_deep(snapshot(level), before)


func test_the_op_list_is_checked_before_anything_runs():
	var level := make_level()
	var before := snapshot(level)
	assert_refused(await call_tool("hf_batch", {"ops": []}), "invalid_argument", "empty")
	var too_many: Array = []
	for i in 101:
		too_many.append(_place(i * 3))
	assert_refused(await call_tool("hf_batch", {"ops": too_many}), "invalid_argument", "101")
	assert_refused(
		await call_tool("hf_batch", {"ops": [_place(0), {"tool": "hf_undo", "params": {}}]}),
		"invalid_argument",
		"undo inside"
	)
	assert_refused(
		await call_tool("hf_batch", {"ops": [{"tool": "hf_place_brush", "params": [1]}]}),
		"invalid_argument",
		"params not an object"
	)
	assert_eq_deep(snapshot(level), before)


func test_a_batch_replays_by_operation_id():
	var level := make_level()
	var params := {"ops": [_place(0), _place(4)]}
	await call_tool("hf_batch", params, {"operation_id": "batch-1"})
	var again := await call_tool("hf_batch", params, {"operation_id": "batch-1"})
	assert_true(again["replayed"])
	assert_eq(brushes(level).size(), 2)


func test_a_first_op_that_changes_the_level_and_fails_is_taken_back():
	var level := BrushThenFailLevel.new()
	make_scene(level)
	var before := snapshot(level)
	var r := await call_tool("hf_batch", {"ops": [_place(0), _place(4)]})
	assert_refused(r, "batch_failed")
	assert_eq(int(r["error"]["details"]["index"]), 0)
	assert_true(r["error"]["details"]["rolled_back"])
	assert_eq(brushes(level).size(), 0, "the brush op 0 made before it failed is gone")
	assert_eq_deep(snapshot(level), before)


func test_a_first_op_refused_by_its_check_needs_no_rollback():
	var level := make_level()
	var before := snapshot(level)
	var ops := [{"tool": "hf_delete_brush", "params": {"brush_id": "no_such_brush"}}]
	var r := await call_tool("hf_batch", {"ops": ops})
	assert_refused(r, "batch_failed")
	assert_false(r["error"]["details"]["rolled_back"], "nothing ran, so nothing to take back")
	assert_eq_deep(snapshot(level), before)


# --- Palette commands in a batch ------------------------------------------


func _command(command: String, brush_ids: Array, args := {}) -> Dictionary:
	return {
		"tool": "hf_run_command",
		"params": {"command": command, "brush_ids": brush_ids, "params": args},
	}


func test_a_command_takes_the_brushes_earlier_ops_made():
	var level := make_level()
	var ops := [
		_place(0),
		_place(2),
		_command("merge", ["$0.brush_id", "$1.brush_id"]),
		_command("hollow", ["$2.brush_id"], {"thickness": 0.25}),
	]
	var r := await call_tool("hf_batch", {"ops": ops})
	assert_true(r["ok"], str(r))
	assert_eq(undo.scene_history.get_current_action_name(), "MCP: batch (4 ops)")
	var merged: String = r["result"]["results"][2]["result"]["brush"]["brush_id"]
	assert_eq(r["result"]["results"][3]["result"]["removed"], [merged], "the merge was hollowed")
	assert_eq(brushes(level).size(), 6, "into six walls")
	await call_tool("hf_undo")
	assert_eq(brushes(level).size(), 0, "one undo takes the whole batch back")


func test_a_command_refused_late_in_a_batch_keeps_nothing():
	var level := make_level()
	var before := snapshot(level)
	var ops := [
		_place(0),
		_command("hollow", ["$0.brush_id"], {"thickness": 0.25}),
		_command("clip", ["nope"]),
	]
	var r := await call_tool("hf_batch", {"ops": ops})
	assert_refused(r, "batch_failed")
	assert_eq(r["error"]["details"]["index"], 2)
	assert_eq(r["error"]["details"]["error"]["code"], "brush_not_found")
	assert_eq(snapshot(level), before, "the box and its walls are gone, and no step")


func test_an_unknown_command_in_a_batch_is_refused_at_its_index():
	var level := make_level()
	var before := snapshot(level)
	var r := await call_tool("hf_batch", {"ops": [_place(0), _command("nope", [])]})
	assert_refused(r, "batch_failed")
	assert_eq(r["error"]["details"]["index"], 1)
	assert_eq(r["error"]["details"]["error"]["code"], "unknown_command")
	assert_eq(snapshot(level), before)
