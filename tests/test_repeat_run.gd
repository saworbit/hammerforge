extends GutTest

## Repeat Run plays the commands, moves and turns made since the selection last
## changed by hand again, on what is selected now, as one undo step (#1735).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginRun = preload("res://addons/hammerforge/plugin_run.gd")
const HFPluginAdjustLast = preload("res://addons/hammerforge/plugin_adjust_last.gd")
const HFPluginCommandsScript = preload("res://addons/hammerforge/plugin_commands.gd")
const HFSelectionGestureScript = preload("res://addons/hammerforge/hf_selection_gesture.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func before_each():
	if rig.plugin:
		HFPluginRun.clear(rig.plugin)


func after_each():
	if rig.plugin:
		HFPluginAdjustLast.close(rig.plugin)


func _run(action: String) -> void:
	rig.plugin._on_hotkey_palette_action(action)


func _level() -> Node:
	var level = await rig.make_level()
	level.grid_snap = 1.0
	level.rotate_snap_degrees = 15.0
	rig.undo().clear()
	return level


func _select(nodes: Array) -> void:
	rig.select(nodes)
	await rig.frame()


func _selected() -> Array:
	return rig.plugin._current_selection_nodes()


func _brushes(level: Node) -> Array:
	return level._iter_managed_brush_nodes()


## A drag of the gizmo, as the Select tool's press sees one: the press begins on
## `node`, the gizmo moves it to `to`, and the release says what moved.
func _drag(node: Node3D, to: Transform3D) -> void:
	var gesture := HFSelectionGestureScript.new()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, false, [node])
	node.global_transform = to
	var result: Dictionary = gesture.finish(Vector2(60, 0), 4.0)
	assert_eq(
		int(result["decision"]),
		HFSelectionGestureScript.ReleaseDecision.NATIVE_GIZMO,
		"fixture: a gizmo drag"
	)
	rig.plugin._note_run_moved(result["moved"])


func _text() -> String:
	return HFPluginRun.run_text(rig.plugin)


func test_duplicate_move_up_and_turn_then_repeat_run_three_times_makes_a_turning_stair():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var first = rig.box(level, "step", Vector3(0, 1, 0), Vector3(4, 1, 2))
	await _select([first])
	_run("duplicate")
	var copy: Node3D = _selected()[0]
	assert_ne(copy, first, "fixture: the copy is the selection")
	_drag(copy, Transform3D(copy.global_basis, copy.global_position + Vector3(0, 3, 0)))
	rig.plugin._rotate_selected(level, 1)
	assert_eq(_text(), "Duplicate, Move +Y 3 m, Rotate CCW 15° Y", "what the run holds")
	for press in 3:
		_run("repeat_run")
		await rig.frame()
	var steps: Array = _brushes(level)
	steps.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	assert_eq(steps.size(), 5, "the first step and four more")
	for k in steps.size():
		var step: Node3D = steps[k]
		assert_almost_eq(step.global_position.y, 1.0 + 3.0 * k, 0.001, "each 3 m higher")
		assert_almost_eq(step.global_position.x, float(k), 0.001, "and a grid step along")
		assert_almost_eq(
			step.global_basis.get_euler().y, deg_to_rad(15.0 * k), 0.001, "and turned 15 more"
		)
	await rig.leave_level(level)


func test_each_press_is_one_undo_step_named_repeat_run():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 1, 0))
	await _select([a])
	_run("duplicate")
	rig.plugin._nudge_selected(level, Vector3.UP)
	var brushes: int = _brushes(level).size()
	var steps: int = rig.undo().step_count()
	_run("repeat_run")
	assert_eq(rig.undo().step_count(), steps + 1, "one step for the copy and its move")
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Repeat Run")
	assert_eq(_brushes(level).size(), brushes + 1, "a copy")
	rig.undo().press_undo()
	await rig.frame()
	assert_eq(_brushes(level).size(), brushes, "one Ctrl+Z takes it back")
	await rig.leave_level(level)


func test_a_selection_made_by_hand_takes_the_run_and_the_next_command_starts_a_new_one():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 1, 0))
	var b = rig.box(level, "b", Vector3(20, 1, 0))
	await _select([a])
	_run("duplicate")
	rig.plugin._nudge_selected(level, Vector3.UP)
	await _select([b])
	assert_eq(_text(), "Duplicate, Move +Y 1 m", "still the run, to play on what is selected now")
	_run("repeat_run")
	var copy: Node3D = _selected()[0]
	assert_ne(copy, b, "a copy of b")
	assert_almost_eq(copy.global_position, Vector3(21, 2, 0), Vector3.ONE * 0.001)
	assert_eq(_text(), "Duplicate, Move +Y 1 m", "and the run goes on from it")
	await _select([a])
	rig.plugin._nudge_selected(level, Vector3.RIGHT)
	assert_eq(_text(), "Move +X 1 m", "the next command starts a new run")
	await rig.leave_level(level)


func test_a_refused_step_takes_back_the_steps_before_it_and_names_itself():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 2, 0), Vector3(4, 4, 4))
	var small = rig.box(level, "small", Vector3(30, 1, 0), Vector3(0.6, 0.6, 0.6))
	var thickness: float = rig.plugin.dock.hollow_thickness.value
	rig.plugin.dock.hollow_thickness.value = 0.5
	await _select([a])
	_run("duplicate")
	_run("hollow")
	assert_eq(await rig.accept_dialogs(), 1, "Hollow asks")
	assert_eq(_text(), "Duplicate, Hollow (0.5 m)")
	var brushes: int = _brushes(level).size()
	var steps: int = rig.undo().step_count()
	await _select([small])
	rig.clear_toasts()
	_run("repeat_run")
	await rig.frame()
	assert_eq(_brushes(level).size(), brushes, "the copy taken back too")
	assert_eq(rig.undo().step_count(), steps, "and no step")
	var said: Array = rig.toasts().filter(func(t): return t.begins_with("Repeat Run stopped"))
	assert_eq(said.size(), 1, "it says so")
	if said.size() == 1:
		assert_string_contains(said[0], "at step 2 of 2, Hollow (0.5 m): ")
	var kept: Array = _selected()
	assert_eq(kept.size(), 1, "the brush it was played on is still selected")
	if kept.size() == 1:
		assert_eq(str(kept[0].brush_id), "small")
	rig.plugin.dock.hollow_thickness.value = thickness
	await rig.leave_level(level)


func test_the_palette_shows_what_the_run_holds():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 1, 0))
	await _select([a])
	var palette = rig.plugin._hotkey_palette
	palette.update_state(HFPluginCommandsScript.build_command_state(rig.plugin, level, 0))
	assert_true(palette._entry_of("repeat_run")["button"].disabled, "nothing to play yet")
	_run("duplicate")
	rig.plugin._nudge_selected(level, Vector3.UP)
	palette.update_state(HFPluginCommandsScript.build_command_state(rig.plugin, level, 0))
	palette._on_search_changed("")
	var top: Array = []
	for child in palette._list.get_children():
		if child.visible:
			top.append(child.text)
		if top.size() == 2:
			break
	assert_eq(top, ["Repeat: Duplicate", "Repeat Run: Duplicate, Move +Y 1 m"])
	assert_false(palette._entry_of("repeat_run")["button"].disabled)
	await rig.leave_level(level)


func test_a_change_the_run_cannot_play_ends_it():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 1, 0))
	await _select([a])
	_run("duplicate")
	_run("flip_selection")
	assert_eq(_text(), "", "a Flip the run cannot play ends it")
	rig.plugin._nudge_selected(level, Vector3.UP)
	assert_eq(_text(), "Move +Y 1 m", "and the next one starts after it")
	await rig.leave_level(level)


func test_an_undo_takes_its_step_out_of_the_run():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 1, 0))
	await _select([a])
	_run("duplicate")
	rig.plugin._nudge_selected(level, Vector3.UP)
	rig.undo().press_undo()
	await rig.frame()
	assert_eq(_text(), "Duplicate")
	await rig.leave_level(level)


func test_held_moves_add_up_and_adjust_last_changes_the_run_s_step():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 1, 0))
	await _select([a])
	for press in 3:
		rig.plugin._nudge_selected(level, Vector3.UP)
	assert_eq(_text(), "Move +Y 3 m", "three presses, one move")
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "offset", Vector3(0, 0, 2)))
	assert_eq(_text(), "Move +Z 2 m", "the move Adjust Last made")
	await rig.leave_level(level)


func test_clear_run_empties_it():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 1, 0))
	await _select([a])
	_run("duplicate")
	_run("clear_run")
	assert_eq(_text(), "")
	var brushes: int = _brushes(level).size()
	rig.clear_toasts()
	_run("repeat_run")
	assert_eq(rig.toasts(), ["Nothing to repeat: run commands on a selection first"])
	assert_eq(_brushes(level).size(), brushes, "and nothing runs")
	await rig.leave_level(level)


func test_a_drag_is_kept_as_a_turn_about_a_world_axis_and_a_move():
	var before := Transform3D(Basis.IDENTITY, Vector3(1, 0, 0))
	var turn := Basis(Vector3.UP, deg_to_rad(30.0))
	var after := Transform3D(turn, Vector3(1, 2, 0))
	assert_eq(
		HFPluginRun.move_steps([[after, before]]),
		[["rotate_ccw", {"angle": 30.0, "axis": "y"}], ["nudge", {"offset": Vector3(0, 2, 0)}]]
	)
	var back := Transform3D(Basis(Vector3.UP, deg_to_rad(-45.0)), Vector3(1, 0, 0))
	assert_eq(
		HFPluginRun.move_steps([[back, before]]),
		[["rotate_cw", {"angle": -45.0, "axis": "y"}]],
		"the other way is a clockwise turn"
	)
	var two := [
		[
			Transform3D(turn, turn * Vector3(-2, 0, 0)),
			Transform3D(Basis.IDENTITY, Vector3(-2, 0, 0))
		],
		[Transform3D(turn, turn * Vector3(2, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(2, 0, 0))],
	]
	assert_eq(
		HFPluginRun.move_steps(two),
		[["rotate_ccw", {"angle": 30.0, "axis": "y"}]],
		"two turned about the middle between them"
	)
	var scaled := Transform3D(Basis.IDENTITY.scaled(Vector3(2, 1, 1)), Vector3(1, 0, 0))
	assert_eq(HFPluginRun.move_steps([[scaled, before]]), [], "a scale cannot be said")
	var tilted := Transform3D(Basis(Vector3(1, 1, 0).normalized(), 0.5), Vector3(1, 0, 0))
	assert_eq(HFPluginRun.move_steps([[tilted, before]]), [], "nor a turn about a tilted axis")


func test_what_the_run_can_hold():
	for id in [
		"duplicate",
		"nudge",
		"rotate_ccw",
		"hollow",
		"clip",
		"carve",
		"merge",
		"move_to_floor",
		"snap_to_grid"
	]:
		assert_true(HFPluginRun.playable(id), id)
	for id in ["flip_selection", "delete", "paste", "justify_fit", "duplicate_array"]:
		assert_false(HFPluginRun.playable(id), id)
