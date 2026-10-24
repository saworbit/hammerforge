extends GutTest
## A draw's base typed as width, depth and height in one entry (#1693), on the
## real plugin and level. One number could only make a square base, so a 6 by 4
## room took a drag to size by eye. `6,` holds the width while the mouse sets the
## depth, `6,4,3` and Enter places the brush with no height click, and the size
## beside the cursor shows which value is being typed.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginHud = preload("res://addons/hammerforge/plugin_hud.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
## The middle of the rig's viewport, where the camera looks at the origin.
const AIM := Vector2(400, 300)

var rig := PluginRig.new()
var _grid_before := 0.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _level() -> Node:
	var level = await rig.make_level()
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(1.0)
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	return level


func _leave(level: Node) -> void:
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await rig.leave_level(level)
	rig.plugin.dock._apply_grid_snap(_grid_before)


func _left(pressed: bool, at: Vector2) -> int:
	return rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, pressed, at))


func _drag_to(at: Vector2) -> void:
	rig.forward(PluginRig.motion(at, MOUSE_BUTTON_MASK_LEFT))


func _keys(keys: Array) -> void:
	for keycode in keys:
		assert_eq(rig.forward(PluginRig.key(keycode)), STOP, "the key is typed")


func test_a_width_alone_holds_while_the_mouse_sets_the_depth():
	var level = await _level()
	var state = level.input_state
	_left(true, AIM)
	_drag_to(AIM + Vector2(60, 20))
	_keys([KEY_6, KEY_COMMA])
	var width: float = state.drag_end.x - state.drag_origin.x
	assert_eq(absf(width), 6.0, "the width is typed")
	var depth_before: float = state.drag_end.z
	_drag_to(AIM + Vector2(140, 110))
	assert_eq(state.drag_end.x - state.drag_origin.x, width, "and holds as the mouse moves")
	assert_ne(state.drag_end.z, depth_before, "while the depth follows the mouse")
	var label := HFPluginHud.cursor_size_text(rig.plugin, level)
	assert_string_starts_with(label, "W 6  D []", "the depth is the value being typed")
	_keys([KEY_4])
	var depth: float = state.drag_end.z - state.drag_origin.z
	assert_eq(absf(depth), 4.0, "then the depth is typed")
	_drag_to(AIM + Vector2(60, 20))
	assert_eq(state.drag_end.z - state.drag_origin.z, depth, "and holds too")
	assert_eq(state.drag_end.x - state.drag_origin.x, width)
	rig.forward(PluginRig.key(KEY_ESCAPE))
	_left(false, AIM + Vector2(60, 20))
	assert_eq(level.draft_brushes_node.get_child_count(), 0, "Escape placed nothing")
	await _leave(level)


func test_three_values_and_enter_place_the_brush_with_no_height_click():
	var level = await _level()
	_left(true, AIM)
	_drag_to(AIM + Vector2(60, 20))
	_keys([KEY_6, KEY_TAB, KEY_4, KEY_TAB, KEY_3])
	assert_eq(rig.plugin.numeric_buffer, "6,4,3", "Tab moves on as a comma does")
	assert_eq(HFPluginHud.cursor_size_text(rig.plugin, level), "W 6  D 4  H [3]")
	_keys([KEY_ENTER])
	assert_true(level.input_state.is_idle(), "the brush is placed at once")
	_left(false, AIM + Vector2(60, 20))
	assert_eq(level.draft_brushes_node.get_child_count(), 1)
	var brush = level.draft_brushes_node.get_child(0)
	assert_eq(brush.size, Vector3(6, 3, 4), "6 wide, 3 high and 4 deep")
	await _leave(level)


func test_one_number_is_still_a_square_base():
	var level = await _level()
	var state = level.input_state
	_left(true, AIM)
	_drag_to(AIM + Vector2(60, 20))
	_keys([KEY_5, KEY_ENTER])
	assert_true(state.is_drag_height(), "Enter goes on to the height")
	var delta: Vector3 = state.drag_end - state.drag_origin
	assert_eq(Vector2(absf(delta.x), absf(delta.z)), Vector2(5, 5), "5 by 5")
	rig.forward(PluginRig.key(KEY_ESCAPE))
	_left(false, AIM + Vector2(60, 20))
	await _leave(level)
