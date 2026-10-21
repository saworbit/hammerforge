extends GutTest

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _with_prior_action():
	var level = await rig.make_level()
	var box = rig.box(level, "prior", Vector3.ZERO)
	rig.select([box])
	rig.plugin._on_hotkey_palette_action("duplicate")
	assert_eq(level.brush_system.get_cached_brush_count(), 2)
	return level


func _start_draw(level, height_stage: bool):
	assert_true(level.begin_drag(rig.camera, Vector2(600, 400), 0, Vector3.ONE, 0))
	if height_stage:
		level.input_state.advance_to_height(Vector2(600, 400))
	rig.plugin.numeric_buffer = "12"
	assert_not_null(level.preview_brush)


func _check_cancel(height_stage: bool, global_shortcut: bool):
	var level = await _with_prior_action()
	_start_draw(level, height_stage)
	var history = rig.undo().scene_history
	var version: int = history.get_version()
	var handled: bool
	if global_shortcut:
		handled = rig.press_shortcut(PluginRig.key(KEY_Z, true))
	else:
		handled = rig.forward(PluginRig.key(KEY_Z, true)) == STOP
	# Emulate Godot handling an unclaimed undo key.
	if not handled:
		rig.undo().press_undo()
	assert_true(handled, "Undo cancels only the preview")
	assert_true(level.input_state.is_idle())
	assert_null(level.preview_brush)
	assert_eq(rig.plugin.numeric_buffer, "")
	assert_eq(history.get_version(), version, "Cancelling leaves history untouched")
	assert_eq(level.brush_system.get_cached_brush_count(), 2, "The previous brush stays")
	assert_false(rig.press_shortcut(PluginRig.key(KEY_Z, true)), "Idle undo belongs to Godot")
	rig.undo().press_undo()
	assert_eq(level.brush_system.get_cached_brush_count(), 1, "The next undo reaches history")
	await rig.leave_level(level)


func test_viewport_undo_cancels_base_and_height():
	await _check_cancel(false, false)
	await _check_cancel(true, false)


func test_global_undo_cancels_base_and_height():
	await _check_cancel(false, true)
	await _check_cancel(true, true)


func test_redo_is_not_claimed_as_draw_cancel():
	var level = await _with_prior_action()
	_start_draw(level, false)
	assert_false(rig.press_shortcut(PluginRig.key(KEY_Z, true, true)))
	assert_true(level.input_state.is_dragging())
	await rig.leave_level(level)


func test_undo_cancels_a_live_extrusion_without_touching_history():
	var level = await _with_prior_action()
	var brush = level.find_brush_by_id("prior")
	var face_index := 0
	for i in brush.faces.size():
		if brush.faces[i].normal.dot(Vector3.UP) > 0.99:
			face_index = i
			break
	var face_center := Vector3.ZERO
	for vertex in brush.faces[face_index].local_verts:
		face_center += brush.global_transform * vertex
	face_center /= brush.faces[face_index].local_verts.size()
	assert_true(level.begin_extrude(rig.camera, rig.camera.unproject_position(face_center), 1))
	var version: int = rig.undo().scene_history.get_version()
	assert_true(rig.press_shortcut(PluginRig.key(KEY_Z, true)))
	assert_true(level.input_state.is_idle())
	assert_false(level.extrude_tool.active)
	assert_null(level.extrude_tool._preview_brush)
	assert_eq(rig.undo().scene_history.get_version(), version)
	await rig.leave_level(level)


func test_text_focus_keeps_undo_while_a_draw_is_active():
	var level = await _with_prior_action()
	_start_draw(level, false)
	var field := LineEdit.new()
	rig.viewport.add_child(field)
	field.grab_focus()
	assert_eq(rig.viewport.gui_get_focus_owner(), field)
	var version: int = rig.undo().scene_history.get_version()
	rig.press_shortcut(PluginRig.key(KEY_Z, true))
	assert_eq(rig.undo().scene_history.get_version(), version)
	assert_true(level.input_state.is_dragging())
	field.free()
	await rig.leave_level(level)
