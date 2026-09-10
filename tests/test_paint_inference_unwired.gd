extends GutTest

## Floor paint inference is a real cleanup pass now, but remains opt-in. These
## tests hold the default-off contract while the wave-2 suite covers each edit.

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFInferenceEngine = preload("res://addons/hammerforge/paint/hf_inference_engine.gd")
const HFStroke = preload("res://addons/hammerforge/paint/hf_stroke.gd")
const HFPaintLayer = preload("res://addons/hammerforge/paint/hf_paint_layer.gd")
const HFPaintGrid = preload("res://addons/hammerforge/paint/hf_paint_grid.gd")

var root: Node3D


func before_each():
	root = LevelRootScript.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	add_child(root)


func after_each():
	root.free()
	root = null


func test_a_level_does_not_wire_an_inference_engine_into_its_paint_tool():
	assert_not_null(root.paint_tool, "The level still builds a paint tool")
	assert_null(root.paint_tool.inference, "and it is not handed an inference engine")


func test_the_stroke_path_still_has_the_hook():
	# Assigning an engine is what turns it on, so the hook has to survive.
	assert_true(
		"inference" in root.paint_tool, "The paint tool still takes an engine if one is given"
	)


func test_the_cleanup_pass_is_bounded_to_one_cell_topology():
	var layer := HFPaintLayer.new()
	layer.grid = HFPaintGrid.new()
	layer.chunk_size = 8
	add_child_autoqfree(layer)
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(6, 6)]:
		layer.set_cell(cell, true)
	layer.consume_dirty_chunks()
	var engine := HFInferenceEngine.new()
	var chunks: Array[Vector2i] = [Vector2i.ZERO]
	engine.apply_cleanup(layer, chunks, &"room", HFInferenceEngine.InferenceSettings.new())
	assert_false(layer.get_cell(Vector2i(6, 6)), "The one-cell island is denoised")
	assert_true(layer.get_cell(Vector2i(0, 0)), "A connected run remains")
	assert_true(layer.get_cell(Vector2i(1, 0)), "Cleanup does not rewrite user intent")


func test_intent_classification_still_answers():
	# The half that works. Kept because it is the input a cleanup pass needs.
	var engine := HFInferenceEngine.new()
	var stroke := HFStroke.new()
	stroke.tool = HFStroke.Tool.ERASE
	assert_eq(engine.infer_intent(stroke), &"erase")
