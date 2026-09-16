extends GutTest

## A single click on the paint grid is a stroke of one cell. These pin the two
## places that treated it as something else.

var layer: HFPaintLayer


func before_each() -> void:
	layer = HFPaintLayer.new()
	layer.grid = HFPaintGrid.new()
	layer.chunk_size = 8
	add_child_autoqfree(layer)


func test_cleanup_leaves_a_one_cell_stroke_alone() -> void:
	var cell := Vector2i(5, 5)
	layer.set_cell(cell, true)
	var chunks: Array[Vector2i] = [layer._cell_to_chunk(cell)]
	layer.consume_dirty_chunks()
	HFInferenceEngine.new().apply_cleanup(
		layer, chunks, &"blob", HFInferenceEngine.InferenceSettings.new(), {cell: true}
	)
	assert_true(layer.get_cell(cell), "One click paints one cell, cleanup or no cleanup")


func test_cleanup_still_denoises_a_stray_cell_in_a_larger_stroke() -> void:
	var stroke := {Vector2i(0, 0): true, Vector2i(1, 0): true, Vector2i(6, 6): true}
	for cell: Vector2i in stroke:
		layer.set_cell(cell, true)
	var chunks: Array[Vector2i] = [Vector2i.ZERO]
	layer.consume_dirty_chunks()
	HFInferenceEngine.new().apply_cleanup(
		layer, chunks, &"blob", HFInferenceEngine.InferenceSettings.new(), stroke
	)
	assert_true(layer.get_cell(Vector2i(0, 0)), "The connected run stays")
	assert_false(layer.get_cell(Vector2i(6, 6)), "and a stray cell is still removed")


func test_a_one_cell_dab_is_not_a_closed_room() -> void:
	var stroke := HFStroke.new()
	stroke.add_cell(Vector2i(4, 4), 0.0)
	stroke.analyse()
	assert_false(stroke.is_closed, "One cell encloses nothing")
	assert_eq(HFInferenceEngine.new().infer_intent(stroke), &"blob")


func test_a_loop_of_three_cells_is_still_closed() -> void:
	var stroke := HFStroke.new()
	stroke.add_cell(Vector2i(0, 0), 0.0)
	stroke.add_cell(Vector2i(1, 0), 0.1)
	stroke.add_cell(Vector2i(0, 1), 0.2)
	stroke.analyse()
	assert_true(stroke.is_closed, "First and last a cell apart, with cells enough to close")
	assert_eq(HFInferenceEngine.new().infer_intent(stroke), &"room")
