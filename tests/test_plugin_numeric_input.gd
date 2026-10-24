extends GutTest
## Boundary coverage for extracted numeric draw/extrude input.

const HFPluginNumericInput = preload("res://addons/hammerforge/plugin_numeric_input.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")


class FakeInputState:
	extends RefCounted

	var dragging := false
	var extruding := false
	var drag_base := false
	var drag_height_mode := false
	var drag_origin := Vector3.ZERO
	var drag_end := Vector3.ZERO
	var drag_height := 0.0
	var numeric_override := -1.0
	var typed_lock_x := true
	var typed_lock_z := true
	var typed_heading := Vector3.ZERO

	func has_numeric_override() -> bool:
		return numeric_override > 0.0

	func clear_numeric_override() -> void:
		numeric_override = -1.0
		typed_lock_x = true
		typed_lock_z = true
		typed_heading = Vector3.ZERO

	func is_dragging() -> bool:
		return dragging

	func is_extruding() -> bool:
		return extruding

	func is_drag_base() -> bool:
		return drag_base

	func is_drag_height() -> bool:
		return drag_height_mode

	func advance_to_height(_mouse_pos: Vector2) -> void:
		drag_base = false
		drag_height_mode = true


class FakeRoot:
	extends Node

	var input_state := FakeInputState.new()
	var update_count := 0
	var extrude_result: Dictionary = {}
	var drag_result: Dictionary = {}
	var extrude_height := 0.0
	var height_at_end := -1.0

	func update_drag(_camera: Camera3D, _mouse_pos: Vector2) -> void:
		update_count += 1

	func set_extrude_height(height: float) -> void:
		extrude_height = height

	func end_extrude_info() -> Dictionary:
		height_at_end = extrude_height
		return extrude_result

	func end_drag_info(_camera: Camera3D, _mouse_pos: Vector2, _size: Vector3) -> Dictionary:
		return drag_result


class FakeDock:
	extends RefCounted

	var toasts: Array = []

	func get_brush_size() -> Vector3:
		return Vector3.ONE

	func show_toast(message: String, _level: int = 0) -> void:
		toasts.append(message)


class FakePlugin:
	extends RefCounted

	var numeric_buffer := ""
	var last_3d_camera: Camera3D = null
	var last_3d_mouse_pos := Vector2.ZERO
	var dock := FakeDock.new()
	var hud_updates := 0
	var committed_info: Dictionary = {}

	func _update_hud_context() -> void:
		hud_updates += 1

	func _commit_brush_placement(_root: Node, info: Dictionary) -> void:
		committed_info = info


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func test_null_inputs_pass_through() -> void:
	assert_eq(HFPluginNumericInput.handle(null, null, null), EditorPlugin.AFTER_GUI_INPUT_PASS)


func test_inactive_input_passes_without_changing_buffer() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	plugin.numeric_buffer = "4"
	assert_eq(
		HFPluginNumericInput.handle(plugin, _key(KEY_2), root), EditorPlugin.AFTER_GUI_INPUT_PASS
	)
	assert_eq(plugin.numeric_buffer, "4")
	root.free()


func test_digits_and_decimal_update_the_active_preview() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	assert_eq(
		HFPluginNumericInput.handle(plugin, _key(KEY_1), root), EditorPlugin.AFTER_GUI_INPUT_STOP
	)
	HFPluginNumericInput.handle(plugin, _key(KEY_PERIOD), root)
	HFPluginNumericInput.handle(plugin, _key(KEY_PERIOD), root)
	HFPluginNumericInput.handle(plugin, _key(KEY_5), root)
	assert_eq(plugin.numeric_buffer, "1.5")
	assert_eq(root.input_state.drag_end, Vector3(1.5, 0.0, 1.5))
	assert_eq(root.update_count, 3)
	assert_eq(plugin.hud_updates, 3)
	root.free()


func test_backspace_updates_preview_and_consumes_key() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	plugin.numeric_buffer = "12"
	assert_eq(
		HFPluginNumericInput.handle(plugin, _key(KEY_BACKSPACE), root),
		EditorPlugin.AFTER_GUI_INPUT_STOP
	)
	assert_eq(plugin.numeric_buffer, "1")
	assert_eq(root.input_state.drag_end, Vector3(1.0, 0.0, 1.0))
	root.free()


func test_enter_commits_numeric_extrusion() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.extruding = true
	root.extrude_result = {"brush_id": "extruded"}
	plugin.numeric_buffer = "3.25"
	assert_eq(
		HFPluginNumericInput.handle(plugin, _key(KEY_ENTER), root),
		EditorPlugin.AFTER_GUI_INPUT_STOP
	)
	# The Extrude's own depth, set before it builds the brush. Enter used to put
	# the number in the Draw's height, which the Extrude never reads (#1560).
	assert_eq(root.height_at_end, 3.25, "the extrusion is built at the typed depth")
	assert_eq(root.input_state.drag_height, 0.0, "and the Draw's height is left alone")
	assert_eq(plugin.numeric_buffer, "")
	assert_eq(plugin.committed_info, root.extrude_result)
	assert_eq(plugin.hud_updates, 1)
	root.free()


## Tab in a draw's base moves on to the next value, width to depth to height
## (#1693), and with all three typed it places the brush. It used to apply the one
## number as a square base, so the depth could never be typed apart.
func test_tab_moves_a_base_entry_on_to_its_next_value() -> void:
	var plugin := FakePlugin.new()
	var root := _base_drag()
	root.drag_result = {"placed": true, "info": {"brush_id": "drawn"}}
	plugin.numeric_buffer = "4"
	assert_eq(
		HFPluginNumericInput.handle(plugin, _key(KEY_TAB), root), EditorPlugin.AFTER_GUI_INPUT_STOP
	)
	assert_eq(plugin.numeric_buffer, "4,", "Tab is a comma in the base")
	assert_true(root.input_state.drag_base, "and the base is still being set")
	assert_eq(root.input_state.drag_end.x, 4.0, "the width holds")
	_type(plugin, root, [KEY_3, KEY_TAB, KEY_2])
	assert_eq(plugin.numeric_buffer, "4,3,2")
	assert_eq(root.input_state.drag_end, Vector3(4.0, 0.0, 3.0))
	assert_eq(root.input_state.drag_height, 2.0)
	HFPluginNumericInput.handle(plugin, _key(KEY_TAB), root)
	assert_eq(plugin.committed_info, {"brush_id": "drawn"}, "Tab on the height places it")
	assert_eq(plugin.numeric_buffer, "")
	root.free()


func _base_drag(end := Vector3.ZERO) -> FakeRoot:
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	root.input_state.drag_end = end
	return root


func _type(plugin: FakePlugin, root: FakeRoot, keys: Array) -> void:
	for keycode in keys:
		HFPluginNumericInput.handle(plugin, _key(keycode), root)


func test_width_and_depth_are_typed_apart() -> void:
	var plugin := FakePlugin.new()
	var root := _base_drag()
	_type(plugin, root, [KEY_6, KEY_COMMA, KEY_4])
	assert_eq(plugin.numeric_buffer, "6,4")
	assert_eq(root.input_state.drag_end, Vector3(6.0, 0.0, 4.0), "6 wide and 4 deep")
	assert_true(root.input_state.has_numeric_override(), "the mouse leaves it alone")
	_type(plugin, root, [KEY_ENTER])
	assert_true(root.input_state.drag_height_mode, "Enter goes on to the height")
	assert_eq(root.input_state.drag_end, Vector3(6.0, 0.0, 4.0))
	assert_eq(plugin.committed_info, {}, "with nothing placed yet")
	assert_eq(plugin.numeric_buffer, "")
	root.free()


func test_a_minus_turns_its_side_the_other_way() -> void:
	var plugin := FakePlugin.new()
	var root := _base_drag(Vector3(2, 0, 2))
	plugin.numeric_buffer = "-6"
	_type(plugin, root, [KEY_COMMA, KEY_4])
	assert_eq(plugin.numeric_buffer, "-6,4")
	assert_eq(root.input_state.drag_end, Vector3(-6.0, 0.0, 4.0), "the width goes back")
	root.free()
	var heading_back := _base_drag(Vector3(-2, 0, -2))
	plugin.numeric_buffer = ""
	_type(plugin, heading_back, [KEY_6, KEY_COMMA, KEY_KP_SUBTRACT, KEY_4])
	assert_eq(heading_back.input_state.drag_end, Vector3(-6.0, 0.0, 4.0), "against the drag")
	heading_back.free()
	var square := _base_drag(Vector3(2, 0, -2))
	plugin.numeric_buffer = ""
	_type(plugin, square, [KEY_MINUS, KEY_3])
	assert_eq(square.input_state.drag_end, Vector3(-3.0, 0.0, 3.0), "one number flips both")
	square.free()


func test_three_values_place_the_brush_with_no_height_click() -> void:
	var plugin := FakePlugin.new()
	var root := _base_drag()
	root.drag_result = {"placed": true, "info": {"brush_id": "drawn"}}
	_type(plugin, root, [KEY_6, KEY_COMMA, KEY_4, KEY_COMMA, KEY_3, KEY_ENTER])
	assert_eq(plugin.committed_info, {"brush_id": "drawn"})
	assert_eq(root.input_state.drag_height, 3.0)
	assert_eq(root.input_state.drag_end, Vector3(6.0, 0.0, 4.0))
	root.free()


func test_a_width_alone_leaves_the_depth_to_the_mouse() -> void:
	var plugin := FakePlugin.new()
	var root := _base_drag(Vector3(2, 0, 5))
	plugin.numeric_buffer = "6"
	_type(plugin, root, [KEY_COMMA])
	assert_eq(root.input_state.drag_end, Vector3(6.0, 0.0, 5.0), "the depth is the drag's")
	assert_true(root.input_state.typed_lock_x)
	assert_false(root.input_state.typed_lock_z, "the drag system lets the mouse set it")
	_type(plugin, root, [KEY_BACKSPACE])
	assert_eq(plugin.numeric_buffer, "6")
	assert_true(root.input_state.typed_lock_z, "one number is a square again")
	assert_eq(root.input_state.drag_end, Vector3(6.0, 0.0, 6.0))
	root.free()


func test_a_third_comma_and_a_ctrl_minus_are_not_typed() -> void:
	var plugin := FakePlugin.new()
	var root := _base_drag()
	plugin.numeric_buffer = "6,4,3"
	assert_eq(
		HFPluginNumericInput.handle(plugin, _key(KEY_COMMA), root),
		EditorPlugin.AFTER_GUI_INPUT_PASS
	)
	assert_eq(plugin.numeric_buffer, "6,4,3")
	plugin.numeric_buffer = ""
	var ctrl_minus := _key(KEY_MINUS)
	ctrl_minus.ctrl_pressed = true
	assert_eq(
		HFPluginNumericInput.handle(plugin, ctrl_minus, root),
		EditorPlugin.AFTER_GUI_INPUT_PASS,
		"Ctrl and minus is the grid's"
	)
	assert_eq(plugin.numeric_buffer, "")
	root.free()


func test_a_comma_in_the_height_stage_is_not_typed() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_height_mode = true
	plugin.numeric_buffer = "4"
	_type(plugin, root, [KEY_COMMA, KEY_MINUS])
	assert_eq(plugin.numeric_buffer, "4", "a height is one number")
	root.free()


func test_a_typed_zero_side_is_refused() -> void:
	var plugin := FakePlugin.new()
	var root := _base_drag(Vector3(2, 0, 2))
	_type(plugin, root, [KEY_6, KEY_COMMA, KEY_0])
	assert_eq(plugin.dock.toasts, [], "nothing is said on the way to 0.5")
	_type(plugin, root, [KEY_ENTER])
	assert_true(root.input_state.drag_base, "the base is still being set")
	assert_eq(plugin.dock.toasts, ["Type a size greater than 0"], "Enter says why")
	root.free()


func test_enter_commits_numeric_draw_height() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_height_mode = true
	root.drag_result = {"placed": true, "info": {"brush_id": "drawn"}}
	plugin.numeric_buffer = "2.5"
	assert_eq(
		HFPluginNumericInput.handle(plugin, _key(KEY_ENTER), root),
		EditorPlugin.AFTER_GUI_INPUT_STOP
	)
	assert_eq(root.input_state.drag_height, 2.5)
	assert_eq(plugin.numeric_buffer, "")
	assert_eq(plugin.committed_info, root.drag_result.info)
	assert_eq(plugin.hud_updates, 1)
	root.free()


## Numbers typed over the viewport during a Draw drag reach the module through
## the plugin: 8 Enter sets an 8 by 8 base, 4 Enter a height of 4, and the brush
## is placed at that size.
func test_plugin_callbacks_are_thin_numeric_delegates() -> void:
	var rig := PluginRig.new()
	await rig.bring_up(self)
	assert_not_null(rig.plugin, rig.error())
	var level = await rig.make_level()
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	var grid: float = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(1.0)
	var aim := Vector2(400, 300)
	var stop := EditorPlugin.AFTER_GUI_INPUT_STOP
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, aim)), stop, "the drag began")
	assert_eq(rig.forward(PluginRig.key(KEY_8)), stop, "a digit is taken")
	assert_eq(rig.plugin.numeric_buffer, "8", "into the buffer")
	assert_true(rig.plugin.dock._mode_label.text.ends_with("[8]"), "which the banner shows")
	rig.forward(PluginRig.key(KEY_ENTER))
	assert_true(level.input_state.is_drag_height(), "Enter sets the base and moves to height")
	rig.forward(PluginRig.key(KEY_4))
	rig.forward(PluginRig.key(KEY_ENTER))
	# The drag's preview brush goes at the end of the frame.
	await rig.frame()
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "the brush was placed")
	if level.draft_brushes_node.get_child_count() == 1:
		var placed = level.draft_brushes_node.get_child(0)
		assert_eq(placed.size, Vector3(8, 4, 8), "at the typed size")
	rig.plugin.dock._apply_grid_snap(grid)
	await rig.leave_level(level)
	await rig.take_down()


func test_plugin_gd_does_not_parse_the_buffer_itself() -> void:
	# A grep on purpose. The drag above proves plugin.gd hands numeric input on;
	# this keeps a second parser of the buffer out of plugin.gd, which a typed
	# size that comes out right cannot show (#609).
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_false(
		source.contains("numeric_buffer.is_valid_float()"), "and does not parse the buffer itself"
	)


func test_keypad_digits_and_decimal_fill_the_buffer() -> void:
	# KEY_KP_ENTER was already accepted, so before this the keypad could end a
	# gesture at whatever size the mouse was at without a digit ever landing.
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	assert_eq(
		HFPluginNumericInput.handle(plugin, _key(KEY_KP_1), root),
		EditorPlugin.AFTER_GUI_INPUT_STOP,
		"A keypad digit should be consumed, not passed on"
	)
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_2), root)
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_PERIOD), root)
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_5), root)
	assert_eq(plugin.numeric_buffer, "12.5", "The keypad should type the same as the top row")
	assert_eq(root.input_state.drag_end, Vector3(12.5, 0.0, 12.5), "and drive the same preview")
	root.free()


func test_keypad_zero_is_a_digit_not_a_pass_through() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_1), root)
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_0), root)
	assert_eq(plugin.numeric_buffer, "10", "KEY_KP_0 sits at the far end of the range")
	root.free()


func test_keypad_enter_commits_a_keypad_typed_value() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_1), root)
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_2), root)
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_8), root)

	var result := HFPluginNumericInput.handle(plugin, _key(KEY_KP_ENTER), root)

	assert_eq(result, EditorPlugin.AFTER_GUI_INPUT_STOP, "Keypad Enter still commits")
	assert_eq(root.input_state.drag_end, Vector3(128.0, 0.0, 128.0), "at the size that was typed")
	root.free()


func test_a_second_keypad_decimal_is_ignored() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_1), root)
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_PERIOD), root)
	HFPluginNumericInput.handle(plugin, _key(KEY_PERIOD), root)
	HFPluginNumericInput.handle(plugin, _key(KEY_KP_5), root)
	assert_eq(plugin.numeric_buffer, "1.5", "One decimal point, whichever key typed it")
	root.free()


# ===========================================================================
# A typed base keeps the direction the drag had (#517)
# ===========================================================================


func test_a_typed_base_keeps_a_negative_drag_in_its_own_quadrant() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	root.input_state.drag_end = Vector3(-64, 0, -64)
	plugin.numeric_buffer = "128"

	HFPluginNumericInput.apply_value(plugin, root)

	assert_eq(
		root.input_state.drag_end,
		Vector3(-128, 0, -128),
		"the brush belongs where the cursor is, not across the origin from it"
	)
	root.free()


func test_a_typed_base_keeps_a_mixed_quadrant() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	root.input_state.drag_end = Vector3(-10, 0, 10)
	plugin.numeric_buffer = "64"

	HFPluginNumericInput.update_preview(plugin, root)

	assert_eq(root.input_state.drag_end, Vector3(-64, 0, 64))
	root.free()


func test_a_typed_base_before_the_mouse_has_moved_goes_positive() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	plugin.numeric_buffer = "32"

	HFPluginNumericInput.update_preview(plugin, root)

	assert_eq(root.input_state.drag_end, Vector3(32, 0, 32), "no direction yet, so the default")
	root.free()


# ===========================================================================
# The typed value stands until the buffer empties (#516)
# ===========================================================================


func test_typing_sets_the_override_the_drag_system_reads() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true

	HFPluginNumericInput.handle(plugin, _key(KEY_1), root)

	assert_true(root.input_state.has_numeric_override(), "the mouse has to leave this field alone")
	assert_eq(root.input_state.numeric_override, 1.0)
	root.free()


func test_backspacing_the_buffer_away_gives_the_gesture_back_to_the_mouse() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	HFPluginNumericInput.handle(plugin, _key(KEY_1), root)

	HFPluginNumericInput.handle(plugin, _key(KEY_BACKSPACE), root)

	assert_eq(plugin.numeric_buffer, "")
	assert_false(root.input_state.has_numeric_override(), "nothing typed, nothing to hold")
	root.free()


## A typed 0 places nothing and leaves the Draw at its height stage for the mouse
## or another number, and says why rather than dropping the number in silence.
func test_a_typed_zero_is_refused_with_a_word_and_the_draw_goes_on() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_height_mode = true
	root.drag_result = {"placed": true, "info": {"brush_id": "drawn"}}
	plugin.numeric_buffer = "0"

	HFPluginNumericInput.apply_value(plugin, root)

	assert_eq(plugin.committed_info, {}, "nothing is placed")
	assert_true(root.input_state.drag_height_mode, "the draw is still setting its height")
	assert_eq(plugin.numeric_buffer, "")
	assert_eq(plugin.dock.toasts, ["Type a size greater than 0"])
	assert_eq(plugin.hud_updates, 1, "and the banner drops the number")
	root.free()


func test_committing_clears_the_override() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_height_mode = true
	plugin.numeric_buffer = "96"

	HFPluginNumericInput.apply_value(plugin, root)

	assert_false(root.input_state.has_numeric_override())
	root.free()
