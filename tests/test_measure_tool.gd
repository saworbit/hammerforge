extends GutTest

const HFMeasureToolScript = preload("res://addons/hammerforge/hf_measure_tool.gd")

var tool: HFMeasureTool


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


func test_hud_lines_with_measurement():
	tool._pending_point = Vector3(0, 0, 0)
	tool._has_pending = true
	tool._finish_ruler(Vector3(10, 0, 0))
	var lines: PackedStringArray = tool.get_shortcut_hud_lines()
	var joined := "\n".join(lines)
	assert_true(joined.contains("10.0"), "Should show distance")
	assert_true(joined.contains("Rulers: 1"), "Should show ruler count")
