extends GutTest

const HFMeasureToolScript = preload("res://addons/hammerforge/hf_measure_tool.gd")

var tool: HFMeasureTool


class MeasureInputSpy:
	extends HFMeasureTool

	var snap_calls := 0
	var regular_left_calls := 0

	func _handle_snap_reference(_camera: Camera3D, _mouse_pos: Vector2) -> int:
		snap_calls += 1
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	func _handle_left_click(
		_event: InputEventMouseButton, _camera: Camera3D, _mouse_pos: Vector2
	) -> int:
		regular_left_calls += 1
		return EditorPlugin.AFTER_GUI_INPUT_STOP


class SnapRoot:
	extends Node3D

	var snap_calls := 0

	func _snap_point(point: Vector3, _exclude_ids: Array = []) -> Vector3:
		snap_calls += 1
		return point.snapped(Vector3(4, 4, 4))


func before_each():
	tool = HFMeasureToolScript.new()


func after_each():
	tool = null


func test_tool_name():
	assert_eq(tool.tool_name(), "Measure")


func test_tool_id():
	assert_eq(tool.tool_id(), 100)


func test_tool_shortcut():
	assert_eq(tool.tool_shortcut_key(), KEY_M)


func test_snap_hit_uses_level_root_snap_settings():
	var root := SnapRoot.new()
	tool.root = root
	assert_eq(tool._snap_hit(Vector3(3, 7, 9)), Vector3(4, 8, 8))
	assert_eq(root.snap_calls, 1)
	root.free()


func test_initial_state_empty():
	assert_eq(tool._measurements.size(), 0)
	assert_false(tool._has_pending)
	assert_false(tool._align_active)


func test_ruler_colors_array():
	assert_true(tool.RULER_COLORS.size() >= 6, "Should have at least 6 ruler colors")


func test_max_rulers_constant():
	assert_eq(tool.MAX_RULERS, 20)


func test_ruler_color_cycles():
	var c0: Color = tool._ruler_color(0)
	var c6: Color = tool._ruler_color(6)
	# Index 6 wraps to index 0
	assert_eq(c0, c6, "Colors should cycle")


func test_point_line_distance_on_line():
	var dist: float = tool._point_line_distance(
		Vector3(0.5, 0, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)
	)
	assert_almost_eq(dist, 0.0, 0.001)


func test_point_line_distance_off_line():
	var dist: float = tool._point_line_distance(
		Vector3(0.5, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)
	)
	assert_almost_eq(dist, 1.0, 0.001)


func test_point_line_distance_beyond_segment():
	var dist: float = tool._point_line_distance(
		Vector3(2, 0, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)
	)
	assert_almost_eq(dist, 1.0, 0.001)


func test_point_line_distance_degenerate():
	# Same point for both line endpoints
	var dist: float = tool._point_line_distance(
		Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0)
	)
	assert_almost_eq(dist, 1.0, 0.001)


func test_finish_ruler_adds_measurement():
	tool._pending_point = Vector3(0, 0, 0)
	tool._has_pending = true
	tool._finish_ruler(Vector3(10, 0, 0))
	assert_eq(tool._measurements.size(), 1)
	assert_false(tool._has_pending)
	assert_eq(tool._measurements[0]["a"], Vector3(0, 0, 0))
	assert_eq(tool._measurements[0]["b"], Vector3(10, 0, 0))


func test_finish_ruler_caps_at_max():
	tool._has_pending = true
	tool._pending_point = Vector3.ZERO
	for i in range(25):
		tool._pending_point = Vector3(float(i), 0, 0)
		tool._has_pending = true
		tool._finish_ruler(Vector3(float(i + 1), 0, 0))
	assert_eq(tool._measurements.size(), tool.MAX_RULERS)


func test_remove_last_ruler():
	tool._pending_point = Vector3(0, 0, 0)
	tool._has_pending = true
	tool._finish_ruler(Vector3(1, 0, 0))
	tool._pending_point = Vector3(1, 0, 0)
	tool._has_pending = true
	tool._finish_ruler(Vector3(2, 0, 0))
	assert_eq(tool._measurements.size(), 2)
	tool._remove_last_ruler()
	assert_eq(tool._measurements.size(), 1)


func test_clear_all():
	tool._pending_point = Vector3(0, 0, 0)
	tool._has_pending = true
	tool._finish_ruler(Vector3(1, 0, 0))
	tool._clear_all()
	assert_eq(tool._measurements.size(), 0)
	assert_false(tool._has_pending)
	assert_false(tool._align_active)


func test_snap_ref_index_adjusts_on_rollover():
	# Fill to max
	for i in range(tool.MAX_RULERS):
		tool._pending_point = Vector3(float(i), 0, 0)
		tool._has_pending = true
		tool._finish_ruler(Vector3(float(i + 1), 0, 0))
	assert_eq(tool._measurements.size(), tool.MAX_RULERS)
	# Set snap ref to ruler at index 5
	tool._snap_ref_index = 5
	tool._align_active = true
	# Add one more ruler — triggers pop_front, shifting indices down by 1
	tool._pending_point = Vector3(100, 0, 0)
	tool._has_pending = true
	tool._finish_ruler(Vector3(101, 0, 0))
	assert_eq(tool._snap_ref_index, 4, "Snap ref index should decrement after rollover")
	assert_true(tool._align_active, "Align should stay active")


func test_snap_ref_cleared_when_evicted():
	# Fill to max
	for i in range(tool.MAX_RULERS):
		tool._pending_point = Vector3(float(i), 0, 0)
		tool._has_pending = true
		tool._finish_ruler(Vector3(float(i + 1), 0, 0))
	# Set snap ref to ruler at index 0 (the oldest, about to be evicted)
	tool._snap_ref_index = 0
	tool._align_active = true
	# Add one more — evicts index 0
	tool._pending_point = Vector3(200, 0, 0)
	tool._has_pending = true
	tool._finish_ruler(Vector3(201, 0, 0))
	assert_eq(tool._snap_ref_index, -1, "Snap ref should be cleared when evicted")
	assert_false(tool._align_active, "Align should be deactivated")


func test_hud_lines_empty():
	var lines: PackedStringArray = tool.get_shortcut_hud_lines()
	assert_true(lines.size() > 0)
	assert_true(lines[0].contains("Measure"))
	var joined := "\n".join(lines)
	assert_true(joined.contains("Ctrl+Click: Set snap ref"))
	assert_false(joined.contains("RMB: Set snap ref"))


func test_plain_rmb_is_reserved_for_native_camera_navigation():
	var root := Node3D.new()
	var camera := Camera3D.new()
	tool.root = root
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	assert_eq(
		tool.handle_input(event, camera, Vector2.ZERO),
		EditorPlugin.AFTER_GUI_INPUT_PASS,
		"Measure must never conditionally steal plain RMB near a ruler",
	)
	root.free()
	camera.free()


func test_ctrl_and_cmd_click_route_only_to_snap_reference():
	var spy := MeasureInputSpy.new()
	var root := Node3D.new()
	var camera := Camera3D.new()
	spy.root = root

	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	assert_eq(spy.handle_input(right, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	assert_eq(spy.snap_calls, 0)

	var ctrl_left := InputEventMouseButton.new()
	ctrl_left.button_index = MOUSE_BUTTON_LEFT
	ctrl_left.pressed = true
	ctrl_left.ctrl_pressed = true
	assert_eq(spy.handle_input(ctrl_left, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(spy.snap_calls, 1)
	assert_eq(spy.regular_left_calls, 0)

	var cmd_left := InputEventMouseButton.new()
	cmd_left.button_index = MOUSE_BUTTON_LEFT
	cmd_left.pressed = true
	cmd_left.meta_pressed = true
	assert_eq(spy.handle_input(cmd_left, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(spy.snap_calls, 2)
	assert_eq(spy.regular_left_calls, 0)

	var plain_left := InputEventMouseButton.new()
	plain_left.button_index = MOUSE_BUTTON_LEFT
	plain_left.pressed = true
	assert_eq(spy.handle_input(plain_left, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(spy.snap_calls, 2)
	assert_eq(spy.regular_left_calls, 1)
	root.free()
	camera.free()


func test_snap_reference_miss_is_consumed():
	var root := Node3D.new()
	var camera := Camera3D.new()
	tool.root = root
	assert_eq(
		tool._handle_snap_reference(camera, Vector2.ZERO),
		EditorPlugin.AFTER_GUI_INPUT_STOP,
		"A missed Ctrl+Click must not fall through into Draw or Select",
	)
	root.free()
	camera.free()


func test_hud_lines_with_measurement():
	tool._pending_point = Vector3(0, 0, 0)
	tool._has_pending = true
	tool._finish_ruler(Vector3(10, 0, 0))
	var lines: PackedStringArray = tool.get_shortcut_hud_lines()
	var joined := "\n".join(lines)
	assert_true(joined.contains("10.0"), "Should show distance")
	assert_true(joined.contains("Rulers: 1"), "Should show ruler count")
