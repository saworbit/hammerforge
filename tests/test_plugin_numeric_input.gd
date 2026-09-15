extends GutTest
## Boundary coverage for extracted numeric draw/extrude input.

const HFPluginNumericInput = preload("res://addons/hammerforge/plugin_numeric_input.gd")


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

	func has_numeric_override() -> bool:
		return numeric_override > 0.0

	func clear_numeric_override() -> void:
		numeric_override = -1.0

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
	var grid_snap := 1.0
	var update_count := 0
	var extrude_result: Dictionary = {}
	var drag_result: Dictionary = {}

	func update_drag(_camera: Camera3D, _mouse_pos: Vector2) -> void:
		update_count += 1

	func end_extrude_info() -> Dictionary:
		return extrude_result

	func end_drag_info(_camera: Camera3D, _mouse_pos: Vector2, _size: Vector3) -> Dictionary:
		return drag_result


class FakeDock:
	extends RefCounted

	func get_brush_size() -> Vector3:
		return Vector3.ONE


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
	assert_eq(root.input_state.drag_height, 3.25)
	assert_eq(plugin.numeric_buffer, "")
	assert_eq(plugin.committed_info, root.extrude_result)
	assert_eq(plugin.hud_updates, 1)
	root.free()


func test_tab_applies_base_dimension_and_advances_to_height() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_base = true
	plugin.numeric_buffer = "4"
	assert_eq(
		HFPluginNumericInput.handle(plugin, _key(KEY_TAB), root), EditorPlugin.AFTER_GUI_INPUT_STOP
	)
	assert_eq(plugin.numeric_buffer, "")
	assert_false(root.input_state.drag_base)
	assert_true(root.input_state.drag_height_mode)
	assert_eq(root.input_state.drag_end, Vector3(4.0, 0.0, 4.0))
	assert_eq(root.update_count, 1)
	assert_eq(plugin.hud_updates, 1)
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


func test_plugin_callbacks_are_thin_numeric_delegates() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for call in [
		"HFPluginNumericInput.handle",
		"HFPluginNumericInput.update_preview",
		"HFPluginNumericInput.apply_value",
	]:
		assert_true(source.contains(call), "%s must be delegated" % call)


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


func test_committing_clears_the_override() -> void:
	var plugin := FakePlugin.new()
	var root := FakeRoot.new()
	root.input_state.dragging = true
	root.input_state.drag_height_mode = true
	plugin.numeric_buffer = "96"

	HFPluginNumericInput.apply_value(plugin, root)

	assert_false(root.input_state.has_numeric_override())
	root.free()
