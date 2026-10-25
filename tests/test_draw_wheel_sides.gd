extends GutTest

## Ctrl+wheel steps Sides in Draw (#1891). The shortcut row promised
## Ctrl+Scroll since the HUD came in, and nothing read the wheel. A notch now
## steps the Sides box by one for a shape that has Sides, with Draw idle or
## partway through a draw, and a draw under way is made with the new count. The
## plain wheel, Alt+wheel, and Ctrl+wheel on a shape with no Sides go on to Godot.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")

const BrushShape = LevelRootScript.BrushShape
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _drawing_level(shape: int, sides: int) -> Node:
	var level = await rig.make_level()
	var dock = rig.plugin.dock
	dock.tool_draw.button_pressed = true
	dock._set_active_shape(shape)
	if dock._shape_requires_sides(shape):
		dock.sides_spin.value = sides
	return level


static func _wheel(up: bool, ctrl := true, alt := false, pressed := true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.position = Vector2(400, 300)
	return event


## One notch: the press and the release, as the wheel sends them. The plugin's
## answer to the press.
func _notch(up: bool, ctrl := true, alt := false) -> int:
	var answer := rig.forward(_wheel(up, ctrl, alt))
	assert_eq(
		rig.forward(_wheel(up, ctrl, alt, false)), answer, "the release goes where the press went"
	)
	return answer


## A draw started by a press in the viewport, as the plugin starts one, carried
## to the height stage of a 2 by 3 by 2 brush on the origin.
func _start_draw_to_height(level) -> void:
	var at := rig.camera.unproject_position(Vector3.ZERO)
	rig.forward(PluginRig.motion(at))
	assert_eq(
		rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, at)), STOP, "the press starts a draw"
	)
	level.input_state.drag_origin = Vector3(-1, 0, -1)
	level.input_state.drag_end = Vector3(1, 0, 1)
	level.input_state.advance_to_height(at)
	level.input_state.drag_height = 3.0
	assert_true(level.input_state.is_drag_height(), "the draw is at its height stage")


func _finish_draw(level) -> Node:
	var before: Array = level._iter_managed_brush_nodes()
	var result: Dictionary = level.end_drag_info(
		rig.camera, rig.camera.unproject_position(Vector3.ZERO), Vector3(2, 3, 2)
	)
	assert_true(result.get("placed", false), "the draw places a brush")
	rig.plugin._commit_brush_placement(level, result["info"])
	for brush in level._iter_managed_brush_nodes():
		if not before.has(brush):
			return brush
	return null


func _hud_text() -> String:
	rig.plugin._update_hud_context()
	return rig.plugin.hud.tooltip_text


func test_ctrl_wheel_up_mid_draw_makes_the_cylinder_with_one_more_side():
	var level = await _drawing_level(BrushShape.CYLINDER, 8)
	_start_draw_to_height(level)
	assert_eq(_notch(true), STOP, "Ctrl+wheel during a cylinder draw is HammerForge's")
	assert_eq(rig.plugin.dock.get_sides(), 9, "the Sides box follows")
	assert_eq(level.preview_brush.sides, 9, "the preview rebuilds with the new count at once")
	var brush = _finish_draw(level)
	assert_not_null(brush)
	assert_eq(brush.sides, 9, "the brush is made with one more side than the box had")
	await rig.leave_level(level)


func test_ctrl_wheel_steps_sides_with_draw_idle_and_down_as_well():
	var level = await _drawing_level(BrushShape.CYLINDER, 12)
	assert_eq(_notch(false), STOP, "idle Draw takes it for a round shape")
	assert_eq(rig.plugin.dock.get_sides(), 11, "a notch down is one fewer")
	await rig.leave_level(level)


func test_box_draw_and_plain_or_alt_wheel_go_on_to_godot():
	var level = await _drawing_level(BrushShape.BOX, 8)
	_start_draw_to_height(level)
	assert_eq(_notch(true), PASS, "a box has no Sides, so Ctrl+wheel is Godot's")
	level.cancel_drag()
	await rig.leave_level(level)

	level = await _drawing_level(BrushShape.CYLINDER, 8)
	_start_draw_to_height(level)
	assert_eq(_notch(true, false), PASS, "the plain wheel is Godot's during a draw")
	assert_eq(_notch(true, true, true), PASS, "and so is Ctrl+Alt+wheel")
	assert_eq(_notch(true, false, true), PASS, "and Alt+wheel")
	assert_eq(rig.plugin.dock.get_sides(), 8, "none of them changed Sides")
	level.cancel_drag()
	await rig.leave_level(level)


func test_ctrl_wheel_outside_draw_goes_on_to_godot():
	var level = await _drawing_level(BrushShape.CYLINDER, 8)
	rig.plugin.dock.tool_select.button_pressed = true
	assert_eq(_notch(true), PASS, "Select keeps the wheel Godot's")
	assert_eq(rig.plugin.dock.get_sides(), 8)
	await rig.leave_level(level)


func test_sides_stop_at_the_ends_of_the_box_range():
	var level = await _drawing_level(BrushShape.CYLINDER, 64)
	_notch(true)
	assert_eq(rig.plugin.dock.get_sides(), 64, "a step up at 64 stays at 64")
	await rig.leave_level(level)

	level = await _drawing_level(BrushShape.PYRAMID, 3)
	_notch(false)
	assert_eq(rig.plugin.dock.get_sides(), 3, "a step down at 3 stays at 3")
	await rig.leave_level(level)

	level = await _drawing_level(BrushShape.CYLINDER, 5)
	_notch(false)
	assert_eq(rig.plugin.dock.get_sides(), 5, "a round shape stops at the least it is built with")
	await rig.leave_level(level)


func test_hud_names_the_count_for_a_cylinder_and_has_no_wheel_line_for_a_box():
	var level = await _drawing_level(BrushShape.BOX, 8)
	assert_false(_hud_text().contains("Scroll"), "no wheel line for a box")
	rig.plugin.dock._set_active_shape(BrushShape.CYLINDER)
	rig.plugin.dock.sides_spin.value = 12
	assert_true(_hud_text().contains("Ctrl+Scroll: Sides (12)"), "the count, for a cylinder")
	_notch(true)
	assert_true(_hud_text().contains("Ctrl+Scroll: Sides (13)"), "and it follows a notch")
	_start_draw_to_height(level)
	assert_true(_hud_text().contains("Ctrl+Scroll: Sides (13)"), "the height stage names it too")
	level.cancel_drag()
	await rig.leave_level(level)
