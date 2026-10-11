extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_batch: several changes as one undo step, all or nothing. A later op can
## name a brush an earlier op made as "$N.brush_id".


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
