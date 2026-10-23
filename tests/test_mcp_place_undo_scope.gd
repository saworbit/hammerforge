extends "res://tests/mcp/mcp_dispatcher_case.gd"

## A placement over the bridge records what it made, not the whole level, so each
## placement costs the same however big the level is (#1786).


func test_undoing_a_placement_takes_out_only_what_it_made():
	var level := make_level()
	var other_id := await place_box([10, 1, 0])
	var placed_id := await place_box([0, 1, 0])
	# A change no step records. A whole level undo of the placement would put the
	# other brush back where it was; a scoped one leaves it alone.
	brush_node(level, other_id).global_position = Vector3(10, 1, 7)
	undo.scene_history.undo()
	assert_null(level.find_brush_by_id(placed_id), "the placed brush is gone")
	assert_eq(
		brush_node(level, other_id).global_position, Vector3(10, 1, 7), "the other is untouched"
	)
	undo.scene_history.redo()
	var again = level.find_brush_by_id(placed_id)
	assert_not_null(again, "redo makes it again under its id")
	if again:
		assert_eq((again as Node3D).global_position, Vector3(0, 1, 0))


func test_an_entity_placement_is_undone_and_redone_alone():
	var level := make_level()
	var answer := await call_tool(
		"hf_place_entity", {"entity_class": "light_point", "position": [0, 2, 0]}
	)
	assert_true(answer.get("ok", false), str(answer).left(200))
	var path := str(answer["result"]["entity"]["entity"])
	var lamp: Node = level.get_node(NodePath(path))
	lamp.entity_data["energy"] = 3.0
	undo.scene_history.undo()
	await get_tree().process_frame
	assert_null(level.get_node_or_null(NodePath(path)), "the lamp is gone")
	undo.scene_history.redo()
	var again: Node = level.get_node_or_null(NodePath(path))
	assert_not_null(again, "redo makes it again at its path")
	if again:
		assert_eq(str(again.entity_class), "light_point")


func test_a_cut_still_undoes_through_the_level():
	var level := make_level()
	await place_box([0, 1, 0])
	var answer := await call_tool(
		"hf_place_brush", {"size": [1, 1, 1], "position": [0, 1, 0], "operation": "subtract"}
	)
	assert_true(answer.get("ok", false), str(answer).left(200))
	var count := brushes(level).size()
	undo.scene_history.undo()
	assert_eq(brushes(level).size(), count - 1, "the cut is taken back")


func test_the_agent_s_own_undo_takes_back_a_placement():
	var level := make_level()
	var placed_id := await place_box([0, 1, 0])
	var undone := await call_tool("hf_undo")
	assert_true(undone.get("ok", false), str(undone).left(200))
	assert_null(level.find_brush_by_id(placed_id))
