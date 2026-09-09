extends GutTest

## Floor paint inference was assigned to every level's paint tool, where it
## classified each stroke on mouse release and then called a cleanup pass that
## changes no cells. These tests hold it out of the live stroke path until there
## is a cleanup pass worth running.

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


func test_the_cleanup_pass_still_changes_nothing():
	# The reason it is not wired in. A lone island and a one cell hole are what
	# denoise and hole fill were described as handling.
	var layer := HFPaintLayer.new()
	layer.grid = HFPaintGrid.new()
	layer.chunk_size = 8
	add_child_autoqfree(layer)
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(6, 6)]:
		layer.set_cell(cell, true)
	layer.consume_dirty_chunks()
	var engine := HFInferenceEngine.new()
	var chunks: Array[Vector2i] = [Vector2i.ZERO]
	engine.apply_cleanup(layer, chunks, &"room", HFInferenceEngine.InferenceSettings.new())
	assert_true(layer.get_cell(Vector2i(6, 6)), "The lone island is still there")
	assert_false(layer.get_cell(Vector2i(1, 1)), "and the hole is still a hole")
	assert_eq(layer.consume_dirty_chunks(), [] as Array[Vector2i], "Nothing was touched")


func test_intent_classification_still_answers():
	# The half that works. Kept because it is the input a cleanup pass needs.
	var engine := HFInferenceEngine.new()
	var stroke := HFStroke.new()
	stroke.tool = HFStroke.Tool.ERASE
	assert_eq(engine.infer_intent(stroke), &"erase")
