extends GutTest
## The Draw hover preview (#1400) and Draw on Face (#1401) through the real
## plugin: what a move, a click, a tool change, the switch, L and the palette do,
## and that undo and redo bring a face draw back turned as it was drawn.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFDragSystemType = preload("res://addons/hammerforge/systems/hf_drag_system.gd")
const HFConsoleControlsType = preload("res://addons/hammerforge/ui/hf_console_controls.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const POLYGON_TOOL := 102
const PAINT_LINE := 3
## The middle of the rig's viewport, where the camera looks at the origin.
const AIM := Vector2(400, 300)

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _level() -> Node:
	var level = await rig.make_level()
	rig.plugin.dock._apply_grid_snap(1.0)
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	return level


func _leave(level: Node) -> void:
	var dock = rig.plugin.dock
	if dock.is_draw_on_face_enabled():
		dock.draw_on_face_btn.button_pressed = false
	dock.draw_hover_preview.button_pressed = true
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await rig.leave_level(level)


func _move(at: Vector2, buttons := 0) -> int:
	return rig.forward(PluginRig.motion(at, buttons))


func _left(pressed: bool, at: Vector2) -> int:
	return rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, pressed, at))


func _at(world: Vector3) -> Vector2:
	return rig.camera.unproject_position(world)


func _brushes(level: Node) -> Array:
	return level.draft_brushes_node.get_children()


# ---------------------------------------------------------------------------
# The hover preview
# ---------------------------------------------------------------------------


func test_draw_shows_the_preview_and_a_still_pointer_picks_nothing_new():
	assert_not_null(rig.plugin, rig.error())
	var level = await _level()
	_move(AIM)
	assert_true(level.draw_hover.is_showing(), "Draw idle shows where a draw lands")
	var shown: Dictionary = level.draw_hover.shown
	_move(AIM)
	assert_same(level.draw_hover.shown, shown, "the same pointer and view pick nothing new")
	_move(AIM + Vector2(40, 0))
	assert_not_same(level.draw_hover.shown, shown, "a pointer that moved picks again")
	await _leave(level)


func test_the_click_starts_where_the_preview_said_and_takes_it_down():
	var level = await _level()
	rig.box(level, "table", Vector3(0, 1, 0), Vector3(8, 2, 8))
	var aim := _at(Vector3(0.3, 2, 0.3))
	_move(aim)
	var shown: Dictionary = level.draw_hover.shown
	assert_eq(int(shown.get("kind", -1)), HFDragSystemType.StartKind.RAISED, "on the table")
	assert_eq(_left(true, aim), STOP, "the draw starts")
	assert_false(level.draw_hover.is_showing(), "starting a drag takes the preview down")
	assert_eq(level.input_state.drag_origin, shown["point"], "where the preview said")
	_move(aim + Vector2(30, 10), MOUSE_BUTTON_MASK_LEFT)
	assert_false(level.draw_hover.is_showing(), "and it stays down through the drag")
	rig.forward(PluginRig.key(KEY_ESCAPE))
	_left(false, aim)
	await _leave(level)


func test_changing_tool_takes_the_preview_down():
	var level = await _level()
	_move(AIM)
	assert_true(level.draw_hover.is_showing())
	rig.plugin._hotkey_palette.action_invoked.emit("tool_select")
	assert_false(level.draw_hover.is_showing(), "Select has no draw to preview")
	_move(AIM + Vector2(20, 0))
	assert_false(level.draw_hover.is_showing(), "nor does a move in it")
	await _leave(level)


func test_the_switch_turns_the_preview_off_and_is_kept():
	var level = await _level()
	var prefs = rig.plugin._user_prefs
	assert_true(bool(prefs.get_pref("draw_hover_preview", false)), "on by default")
	assert_true(rig.plugin.dock.draw_hover_preview.button_pressed, "and the switch says so")
	_move(AIM)
	assert_true(level.draw_hover.is_showing())
	rig.plugin.dock.draw_hover_preview.button_pressed = false
	assert_false(level.draw_hover.is_showing(), "off takes it down at once")
	assert_false(bool(prefs.get_pref("draw_hover_preview", true)), "and is kept as a preference")
	_move(AIM + Vector2(20, 0))
	assert_false(level.draw_hover.is_showing(), "a move brings nothing back")
	await _leave(level)


func test_the_console_lists_the_switch_in_its_viewport_group():
	var found := {}
	for group in HFConsoleControlsType.GROUPS:
		for spec in group["rows"]:
			if str(spec.get("pref", "")) == "draw_hover_preview":
				found = {"group": group["title"], "dock": spec.get("dock", "")}
	assert_eq(found.get("group", ""), "Viewport")
	assert_eq(found.get("dock", ""), "draw_hover_preview", "written through the dock's switch")


func test_polygon_shows_where_its_first_point_lands_until_it_is_placed():
	var level = await _level()
	rig.box(level, "table", Vector3(0, 1, 0), Vector3(8, 2, 8))
	rig.plugin._activate_external_tool(POLYGON_TOOL, level)
	var polygon = rig.plugin._tool_registry.get_active_tool()
	assert_eq(polygon.tool_id(), POLYGON_TOOL)
	var aim := _at(Vector3(1.3, 2, -0.6))
	_move(aim)
	assert_true(level.draw_hover.is_showing(), "before the first point")
	var point: Vector3 = level.draw_hover.shown["point"]
	_left(true, aim)
	_left(false, aim)
	assert_eq(polygon._polygon_points.size(), 1, "the click placed the first point")
	assert_eq(polygon._polygon_points[0], point, "where the preview said")
	assert_false(level.draw_hover.is_showing(), "and the preview went with it")
	_move(aim + Vector2(30, 0))
	assert_false(level.draw_hover.is_showing(), "it does not come back for the next point")
	rig.forward(PluginRig.key(KEY_ESCAPE))
	rig.plugin._deactivate_external_tool()
	await _leave(level)


# ---------------------------------------------------------------------------
# Draw on Face: L, the palette and the dock
# ---------------------------------------------------------------------------


func test_l_and_the_palette_toggle_draw_on_face():
	var level = await _level()
	var dock = rig.plugin.dock
	assert_false(dock.is_draw_on_face_enabled(), "off to start")
	assert_eq(rig.forward(PluginRig.key_for("toggle_draw_on_face")), STOP, "L is taken")
	assert_true(dock.is_draw_on_face_enabled(), "L turns it on")
	assert_true(dock.draw_on_face_btn.button_pressed, "the button says so")
	rig.plugin._hotkey_palette.action_invoked.emit("toggle_draw_on_face")
	assert_false(dock.is_draw_on_face_enabled(), "the palette turns it off")
	await _leave(level)


func test_l_in_paint_mode_is_still_the_line_tool():
	var level = await _level()
	var dock = rig.plugin.dock
	rig.plugin._toggle_paint_mode()
	assert_true(dock.is_paint_mode_enabled())
	rig.forward(PluginRig.key_for("toggle_draw_on_face"))
	assert_false(dock.is_draw_on_face_enabled(), "Paint keeps L")
	assert_eq(dock.get_paint_tool_id(), PAINT_LINE, "for its Line tool")
	rig.plugin._toggle_paint_mode()
	await _leave(level)


func test_a_face_draw_is_undone_and_redone_with_its_turn():
	var level = await _level()
	var dock = rig.plugin.dock
	dock.toggle_draw_on_face()
	var wall = rig.box(level, "wall", Vector3(0, 2, 0), Vector3(8, 4, 2))
	var from := _at(Vector3(-1.2, 1.2, 1))
	var to := _at(Vector3(1.8, 3.2, 1))
	_move(from)
	assert_eq(
		int(level.draw_hover.shown.get("kind", -1)),
		HFDragSystemType.StartKind.FACE,
		"the wall shows the face look"
	)
	assert_eq(_left(true, from), STOP, "the draw starts on the wall")
	_move(to, MOUSE_BUTTON_MASK_LEFT)
	_left(false, to)
	var pulled := to - Vector2(0, 30)
	_move(pulled)
	_left(true, pulled)
	_left(false, pulled)
	var made: Array = []
	for brush in _brushes(level):
		if brush != wall:
			made.append(brush)
	assert_eq(made.size(), 1, "the draw made one brush")
	if made.size() != 1:
		await _leave(level)
		return
	var drawn: Transform3D = made[0].global_transform
	var drawn_id := str(made[0].brush_id)
	assert_almost_eq(drawn.basis.y, Vector3.BACK, Vector3.ONE * 0.0001, "it stands out of the wall")
	assert_gt(drawn.basis.determinant(), 0.0)
	assert_true(rig.undo().press_undo(), "the step undoes")
	assert_null(level.find_brush_by_id(drawn_id), "undo takes it away")
	assert_true(rig.undo().press_redo(), "and redoes")
	var back = level.find_brush_by_id(drawn_id)
	assert_not_null(back, "redo puts it back")
	if back:
		assert_true(back.global_transform.is_equal_approx(drawn), "turned as it was drawn")
	await _leave(level)
