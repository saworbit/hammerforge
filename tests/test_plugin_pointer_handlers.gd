extends GutTest
## Focused coverage for extracted plugin paint and pointer handlers.

const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const HFPluginPaintInput = preload("res://addons/hammerforge/plugin_paint_input.gd")


func test_displacement_start_is_null_safe() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	assert_false(HFPluginPaintInput.should_start_displacement(null, press, null))


func test_polygon_margin_accepts_inside_and_rejects_distant_points() -> void:
	var vertices := PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, -1)]
	)
	assert_true(HFPluginPaintInput.point_near_polygon_3d(Vector3.ZERO, vertices, Vector3.UP, 0.0))
	assert_false(
		HFPluginPaintInput.point_near_polygon_3d(Vector3(4, 0, 0), vertices, Vector3.UP, 0.0)
	)


func test_plugin_pointer_callbacks_are_thin_delegates() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for call in [
		"HFPluginPaintInput.should_start_displacement",
		"HFPluginPaintInput.handle_displacement",
		"HFPluginPaintInput.commit_displacement_undo",
		"HFPluginPaintInput.do_displacement_stroke",
		"HFPluginPaintInput.point_near_polygon_3d",
		"HFPluginPaintInput.handle_paint",
		"HFPluginPointerTools.handle_extrude",
		"HFPluginPointerTools.handle_draw",
		"HFPluginPointerTools.handle_motion",
		"HFPluginPointerTools.update_prefab_hover",
	]:
		assert_true(source.contains(call), "%s must be delegated" % call)


func test_dispatcher_keeps_paint_and_pointer_calls_in_the_same_order() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_viewport_input.gd")
	var displacement := source.find("plugin._handle_disp_paint_input")
	var paint := source.find("plugin._handle_paint_input")
	var draw := source.find("plugin._handle_draw_mouse")
	var motion := source.find("plugin._handle_mouse_motion")
	assert_gte(displacement, 0)
	assert_gt(paint, displacement)
	assert_gt(draw, paint)
	assert_gt(motion, draw)
