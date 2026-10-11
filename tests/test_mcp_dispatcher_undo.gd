extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_undo and hf_redo take back only the agent's own steps, and refuse after
## anything else touched the level, even something that was then undone. And
## hf_create_starter, which is one step of its own.


func _foreign_step(name := "Human edit") -> void:
	var marker := Node.new()
	add_child_autoqfree(marker)
	undo.scene_history.create_action(name)
	undo.scene_history.add_do_property(marker, "name", "after")
	undo.scene_history.add_undo_property(marker, "name", "before")
	undo.scene_history.commit_action()


func test_place_undo_redo():
	var level := make_level()
	var id := await place_box()
	var undone := await call_tool("hf_undo")
	assert_true(undone["ok"], str(undone))
	assert_eq(undone["result"]["undone"], "MCP: place brush")
	assert_eq(brushes(level).size(), 0)
	var redone := await call_tool("hf_redo")
	assert_true(redone["ok"], str(redone))
	assert_eq(redone["result"]["redone"], "MCP: place brush")
	assert_not_null(brush_node(level, id))


func test_two_steps_then_two_undos():
	var level := make_level()
	await place_box([0, 1, 0])
	await place_box([6, 1, 0])
	assert_true((await call_tool("hf_undo"))["ok"])
	assert_eq(brushes(level).size(), 1)
	assert_true((await call_tool("hf_undo"))["ok"])
	assert_eq(brushes(level).size(), 0)


func test_a_human_step_on_top_conflicts():
	var level := make_level()
	await place_box()
	_foreign_step()
	var r := await call_tool("hf_undo")
	assert_refused(r, "undo_conflict")
	assert_eq(r["error"]["details"]["top_action"], "Human edit")
	assert_eq(brushes(level).size(), 1, "nothing undone")


func test_a_human_step_that_was_undone_still_conflicts():
	var level := make_level()
	await place_box()
	_foreign_step()
	undo.scene_history.undo()
	var r := await call_tool("hf_undo")
	assert_refused(r, "undo_conflict")
	assert_ne(
		int(r["error"]["details"]["revision"]), int(r["error"]["details"]["last_agent_revision"])
	)
	assert_eq(brushes(level).size(), 1)


func test_nothing_to_undo_or_redo():
	make_level()
	assert_refused(await call_tool("hf_undo"), "nothing_to_undo")
	assert_refused(await call_tool("hf_redo"), "nothing_to_redo")


func test_undo_before_any_agent_step_conflicts():
	make_level()
	_foreign_step()
	assert_refused(await call_tool("hf_undo"), "undo_conflict")


func test_redo_after_a_human_step_cleared_the_stack():
	make_level()
	await place_box()
	await call_tool("hf_undo")
	_foreign_step()
	assert_refused(await call_tool("hf_redo"), "nothing_to_redo")


func test_redo_of_a_human_step_conflicts():
	make_level()
	await place_box()
	_foreign_step()
	undo.scene_history.undo()
	var r := await call_tool("hf_redo")
	assert_refused(r, "redo_conflict")


# --- hf_create_starter -----------------------------------------------------


func test_create_starter_needs_a_scene():
	assert_refused(await call_tool("hf_create_starter"), "no_edited_scene")


func test_create_starter_refuses_a_scene_with_a_level():
	make_level()
	assert_refused(await call_tool("hf_create_starter"), "level_exists")


func test_create_starter_is_one_step_and_moves_the_target():
	var scene := make_scene()
	var before := await call_tool("hf_get_status")
	var r := await call_tool("hf_create_starter", {}, {"expect_target": before["target_id"]})
	assert_true(r["ok"], str(r))
	assert_ne(r["target_id"], before["target_id"], "the client follows onto the new level")
	assert_eq(r["result"]["target"]["target_id"], r["target_id"])
	assert_eq(undo.scene_history.get_history_count(), 1)
	assert_eq(undo.scene_history.get_current_action_name(), "MCP: create starter")
	assert_eq(host.history, ["MCP: create starter"])
	var level: LevelRoot = host.level_root_in(scene)
	assert_not_null(level)
	assert_not_null(level.spawn_system.get_active_spawn())
	var placed := await call_tool(
		"hf_place_brush",
		{"size": [2, 2, 2], "position": [0, 1, 0]},
		{"expect_target": r["target_id"]}
	)
	assert_true(placed["ok"], "work goes on in the new level: %s" % str(placed))


func test_create_starter_then_undo_takes_the_level_away():
	var scene := make_scene()
	await call_tool("hf_create_starter")
	var undone := await call_tool("hf_undo")
	assert_true(undone["ok"], str(undone))
	assert_null(host.level_root_in(scene))
	var redone := await call_tool("hf_redo")
	assert_true(redone["ok"], str(redone))
	assert_not_null(host.level_root_in(scene))
