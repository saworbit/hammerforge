extends "res://tests/support/plugin_sweep_case.gd"
## A bake applies the pending cuts, moving them in among the brushes, and nothing
## recorded that: after Bake or Quick Play, Ctrl+Z could not bring a cut back to
## pending, and Quick Play's redo brought back the spawn it made and not the cuts
## the bake applied (#1353). The dock's bakes now record the apply first, as a
## step of their own when there was anything to apply; undo puts the cuts back
## and leaves the bake standing, as it does with any step before a bake.


## The level as undo has to put it back, one entry per key of `capture_state()`,
## less the bake's product and the id counter, as the undo sweep compares it.
func _level(root: Node) -> Dictionary:
	var out := {}
	var state: Dictionary = root.capture_state(false)
	state.erase("id_counter")
	state.erase("baked_present")
	state.erase("bake_preview_mode")
	for key in state:
		out[key] = var_to_str(state[key])
	return out


func test_undo_after_bake_puts_the_cut_back_to_pending():
	await _bring_up(true)
	var root = await _enter_state("pending_cut")
	var undo = plugin.stand_in_undo
	undo.clear()
	var before := _level(root)
	plugin.dock._on_bake()
	await get_tree().process_frame
	await _settle(root)
	assert_eq(root.pending_node.get_child_count(), 0, "the bake applied the cut")
	assert_not_null(root.baked_container, "and baked")
	var after := _level(root)
	assert_eq(undo.step_count(), 1, "the apply is a step of its own")
	assert_eq(undo.scene_history.get_current_action_name(), "Apply Pending Cuts")
	undo.press_undo()
	await get_tree().process_frame
	assert_eq(root.pending_node.get_child_count(), 1, "undo put the cut back to pending")
	assert_eq(_level(root), before, "with the level as it was before the bake")
	undo.press_redo()
	await get_tree().process_frame
	assert_eq(_level(root), after, "redo applied it again")
	undo.clear()
	await _leave_level(root)
	await _take_down()


func test_a_bake_with_nothing_pending_leaves_no_step():
	await _bring_up(true)
	var root = await _enter_state("box_selected")
	var undo = plugin.stand_in_undo
	undo.clear()
	plugin.dock._on_bake()
	await get_tree().process_frame
	await _settle(root)
	assert_not_null(root.baked_container, "baked")
	assert_eq(undo.step_count(), 0, "a bake is no step, and there was nothing to apply")
	await _leave_level(root)
	await _take_down()


func test_the_apply_button_with_nothing_pending_leaves_no_step():
	await _bring_up(true)
	var root = await _enter_state("box_selected")
	var undo = plugin.stand_in_undo
	undo.clear()
	plugin.dock._on_apply_cuts()
	assert_eq(undo.step_count(), 0, "the Apply button has the same no-op rule as a bake")
	await _leave_level(root)
	await _take_down()


func test_the_apply_button_records_the_same_step_as_a_bake():
	await _bring_up(true)
	var root = await _enter_state("pending_cut")
	var undo = plugin.stand_in_undo
	undo.clear()
	var before := _level(root)
	plugin.dock._on_apply_cuts()
	assert_eq(undo.step_count(), 1)
	assert_eq(undo.scene_history.get_current_action_name(), "Apply Pending Cuts")
	assert_eq(root.pending_node.get_child_count(), 0)
	var after := _level(root)
	undo.press_undo()
	await get_tree().process_frame
	assert_eq(_level(root), before)
	undo.press_redo()
	await get_tree().process_frame
	assert_eq(_level(root), after)
	undo.clear()
	await _leave_level(root)
	await _take_down()


func test_quick_play_redo_brings_back_the_spawn_and_the_applied_cut():
	await _bring_up(true)
	var root = await _enter_state("pending_cut")
	var undo = plugin.stand_in_undo
	undo.clear()
	var before := _level(root)
	plugin.dock._on_quick_play()
	await get_tree().process_frame
	await _settle(root)
	assert_eq(root.pending_node.get_child_count(), 0, "Quick Play's bake applied the cut")
	assert_not_null(root.spawn_system.get_active_spawn(), "and it made a spawn")
	var after := _level(root)
	assert_eq(undo.step_count(), 2, "the spawn and the apply are a step each")
	undo.press_undo()
	undo.press_undo()
	await get_tree().process_frame
	assert_eq(_level(root), before, "undo took back both")
	assert_null(root.spawn_system.get_active_spawn(), "the spawn included")
	undo.press_redo()
	undo.press_redo()
	await get_tree().process_frame
	assert_eq(_level(root), after, "redo brought back the spawn and the applied cut")
	undo.clear()
	await _leave_level(root)
	await _take_down()
