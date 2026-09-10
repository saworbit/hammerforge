extends GutTest
## Wave-2 Floor Paint generative actions and bounded cleanup contracts.

const HFAutoConnector = preload("res://addons/hammerforge/paint/hf_auto_connector.gd")
const HFConnectorTool = preload("res://addons/hammerforge/paint/hf_connector_tool.gd")
const HFGeometrySynth = preload("res://addons/hammerforge/paint/hf_geometry_synth.gd")
const HFInferenceEngine = preload("res://addons/hammerforge/paint/hf_inference_engine.gd")
const HFPaintLayerManager = preload("res://addons/hammerforge/paint/hf_paint_layer_manager.gd")
const HFPaintTool = preload("res://addons/hammerforge/paint/hf_paint_tool.gd")
const HFStroke = preload("res://addons/hammerforge/paint/hf_stroke.gd")
const HFPluginOverlays = preload("res://addons/hammerforge/plugin_overlays.gd")

var manager: HFPaintLayerManager
var layer
var tool: HFPaintTool


func before_each() -> void:
	manager = HFPaintLayerManager.new()
	manager.chunk_size = 8
	add_child_autoqfree(manager)
	layer = manager.create_layer(&"floor", 0.0)
	tool = HFPaintTool.new()
	tool.layer_manager = manager
	add_child_autoqfree(tool)


func after_each() -> void:
	manager = null
	layer = null
	tool = null


func test_wall_height_gesture_is_scoped_to_the_last_painted_footprint() -> void:
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(8, 8)]:
		layer.set_cell(cell, true)
	tool._last_committed_cells = {Vector2i(0, 0): true, Vector2i(1, 0): true}

	assert_true(tool.begin_height_gesture(100.0))
	tool.update_height_gesture(76.0)
	assert_eq(tool.confirm_height_gesture(), 2)
	assert_almost_eq(layer.get_wall_height(Vector2i(0, 0), 3.0), 4.0, 0.001)
	assert_almost_eq(layer.get_wall_height(Vector2i(1, 0), 3.0), 4.0, 0.001)
	assert_almost_eq(layer.get_wall_height(Vector2i(8, 8), 3.0), 3.0, 0.001)


func test_cancelled_height_gesture_restores_cell_heights_and_preview() -> void:
	layer.set_cell(Vector2i(2, 3), true)
	layer.set_wall_height(Vector2i(2, 3), 2.5)
	tool._last_committed_cells = {Vector2i(2, 3): true}
	assert_true(tool.begin_height_gesture(100.0))
	tool.update_height_gesture(52.0)
	assert_true(tool.is_height_gesture_active())

	assert_true(tool.cancel_pending_action())
	assert_false(tool.is_height_gesture_active())
	assert_almost_eq(layer.get_wall_height(Vector2i(2, 3), 3.0), 2.5, 0.001)
	assert_true(tool.get_preview_cells().is_empty())


func test_height_gesture_does_not_apply_a_footprint_to_a_different_layer() -> void:
	layer.set_cell(Vector2i(2, 3), true)
	tool._last_committed_cells = {Vector2i(2, 3): true}
	tool._last_committed_layer_index = 0
	manager.create_layer(&"upper", 3.0)
	manager.set_active_layer(1)

	assert_false(tool.begin_height_gesture(100.0))


func test_geometry_synth_keeps_distinct_wall_heights() -> void:
	layer.set_cell(Vector2i(0, 0), true)
	layer.set_cell(Vector2i(1, 0), true)
	layer.set_wall_height(Vector2i(0, 0), 2.0)
	layer.set_wall_height(Vector2i(1, 0), 4.0)
	var synth := HFGeometrySynth.new()
	var settings := HFGeometrySynth.SynthSettings.new()
	var model = synth.build_for_chunks(layer, [Vector2i.ZERO], settings)
	var heights: Dictionary = {}
	for wall in model.walls:
		heights[wall.height] = true
	assert_true(heights.has(2.0))
	assert_true(heights.has(4.0))


func test_mirror_x_and_z_expand_one_stamp_in_the_same_action() -> void:
	tool.mirror_x_enabled = true
	tool.mirror_z_enabled = true
	tool._active_stroke = HFStroke.new()
	tool._painting = true
	tool._stamp_cell(Vector2i(1, 2))

	for expected in [Vector2i(1, 2), Vector2i(-2, 2), Vector2i(1, -3), Vector2i(-2, -3)]:
		assert_true(layer.get_cell(expected), "Missing mirrored cell %s" % expected)
	assert_eq(tool._stroke_cells.size(), 4)


func test_room_stamp_reuses_the_last_rect_size() -> void:
	tool._last_rect_size = Vector2i(3, 2)
	tool._hover_cell = Vector2i(5, 6)

	assert_eq(tool.stamp_room_from_last_rect(), 6)
	for y in range(6, 8):
		for x in range(5, 8):
			assert_true(layer.get_cell(Vector2i(x, y)))
	assert_eq(tool.get_last_committed_cell_count(), 6)


func test_connector_candidates_are_limited_to_the_touched_footprint() -> void:
	manager.clear_layers()
	var low = manager.create_layer(&"low", 0.0)
	var high = manager.create_layer(&"high", 3.0)
	low.set_cell(Vector2i(0, 0), true)
	high.set_cell(Vector2i(1, 0), true)
	low.set_cell(Vector2i(20, 20), true)
	high.set_cell(Vector2i(21, 20), true)
	var touched := {Vector2i(0, 0): true}
	var defs: Array = HFAutoConnector.new().call("defs_for_touched_cells", manager, 0, touched)

	assert_eq(defs.size(), 1)
	assert_eq(defs[0].from_cell, Vector2i(0, 0))
	assert_eq(defs[0].to_cell, Vector2i(1, 0))


func test_connector_definition_round_trips_for_undo_and_level_save() -> void:
	var original := HFConnectorTool.ConnectorDef.new()
	original.from_layer_index = 2
	original.to_layer_index = 4
	original.from_cell = Vector2i(-3, 7)
	original.to_cell = Vector2i(-2, 7)
	original.connector_type = HFConnectorTool.ConnectorType.STAIRS
	original.width_cells = 3
	original.stair_step_height = 0.2
	var restored: Variant = original.call("from_dict", original.call("to_dict"))

	assert_eq(restored.from_layer_index, 2)
	assert_eq(restored.to_layer_index, 4)
	assert_eq(restored.from_cell, Vector2i(-3, 7))
	assert_eq(restored.connector_type, HFConnectorTool.ConnectorType.STAIRS)
	assert_almost_eq(restored.stair_step_height, 0.2, 0.001)


func test_confirming_connector_ghost_commits_definition_and_clears_preview() -> void:
	var definition := HFConnectorTool.ConnectorDef.new()
	definition.from_layer_index = 0
	definition.to_layer_index = 1
	definition.from_cell = Vector2i.ZERO
	definition.to_cell = Vector2i(1, 0)
	tool._pending_connector_defs = [definition]

	assert_eq(tool.confirm_connector_ghosts(), 1)
	assert_eq(tool.connector_defs.size(), 1)
	assert_true(tool._pending_connector_defs.is_empty())
	var saved := tool.capture_connector_defs()
	tool.connector_defs.clear()
	tool.restore_connector_defs(saved)
	assert_eq(tool.connector_defs.size(), 1)
	assert_eq(tool.connector_defs[0].to_cell, Vector2i(1, 0))


func test_inference_denoises_only_a_one_cell_island() -> void:
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(6, 6)]:
		layer.set_cell(cell, true)
	layer.consume_dirty_chunks()
	HFInferenceEngine.new().apply_cleanup(
		layer, [Vector2i.ZERO], &"blob", HFInferenceEngine.InferenceSettings.new()
	)
	assert_true(layer.get_cell(Vector2i(0, 0)))
	assert_true(layer.get_cell(Vector2i(1, 0)))
	assert_false(layer.get_cell(Vector2i(6, 6)))


func test_inference_fills_one_cell_hole_and_bridges_one_cell_gap() -> void:
	for cell in [
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(4, 0),
		Vector2i(6, 0),
	]:
		layer.set_cell(cell, true)
	layer.consume_dirty_chunks()
	HFInferenceEngine.new().apply_cleanup(
		layer, [Vector2i.ZERO], &"room", HFInferenceEngine.InferenceSettings.new()
	)
	assert_true(layer.get_cell(Vector2i(0, 0)), "Four-neighbour one-cell hole is filled")
	assert_true(layer.get_cell(Vector2i(5, 0)), "Cardinal one-cell gap is bridged")
	assert_false(layer.get_cell(Vector2i(5, 1)), "Cleanup does not spread beyond topology")


func test_corridor_cleanup_widens_one_cell_run_by_one_cell() -> void:
	for x in range(3):
		layer.set_cell(Vector2i(x, 0), true)
	layer.consume_dirty_chunks()
	HFInferenceEngine.new().apply_cleanup(
		layer, [Vector2i.ZERO], &"corridor", HFInferenceEngine.InferenceSettings.new()
	)
	for x in range(3):
		assert_true(layer.get_cell(Vector2i(x, 1)))
	assert_false(layer.get_cell(Vector2i(1, 2)))


func test_inference_is_default_off_until_the_paint_toggle_wires_it() -> void:
	assert_null(tool.inference)


func test_floor_paint_still_contains_no_rmb_handler() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/paint/hf_paint_tool.gd")
	assert_false(source.contains("MOUSE_BUTTON_RIGHT"))


func test_paint_footprint_overlay_is_freed_synchronously() -> void:
	var fake_plugin := Node.new()
	fake_plugin.set_script(_overlay_plugin_script())
	add_child_autoqfree(fake_plugin)
	var fake_dock := RefCounted.new()
	fake_dock.set_script(_overlay_dock_script())
	fake_plugin.dock = fake_dock
	var fake_root := Node3D.new()
	fake_root.set_script(_overlay_root_script())
	add_child_autoqfree(fake_root)
	fake_root.paint_layers = manager
	fake_root.paint_tool = tool
	tool._painting = true
	tool._stroke_cells = {Vector2i.ZERO: true}

	HFPluginOverlays.update_paint_overlay(fake_plugin, fake_root)
	assert_not_null(fake_plugin._paint_overlay_mesh)
	assert_true(is_instance_valid(fake_plugin._paint_overlay_mesh))

	HFPluginOverlays.clear_paint_overlay(fake_plugin)
	assert_null(fake_plugin._paint_overlay_mesh)
	assert_true(fake_plugin._paint_connector_overlay_meshes.is_empty())


func _overlay_plugin_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node
var dock
var _paint_overlay_mesh: MeshInstance3D = null
var _paint_overlay_imesh: ImmediateMesh = null
var _paint_connector_overlay_meshes: Array[MeshInstance3D] = []
"""
	script.reload()
	return script


func _overlay_dock_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends RefCounted
func is_paint_mode_enabled() -> bool:
    return true
"""
	script.reload()
	return script


func _overlay_root_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node3D
var paint_layers
var paint_tool
"""
	script.reload()
	return script
