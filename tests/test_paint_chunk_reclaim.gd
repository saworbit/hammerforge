extends GutTest

## Erasing paint should give the memory back. A chunk whose last bit clears holds
## nothing but zeros, and holding it costs memory the Test tab reports and weight
## in every .hflevel save and every undo snapshot, permanently, for paint the
## user removed.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot
var layer: HFPaintLayer


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	layer = root.paint_layers.get_active_layer()


func _fill(size: int, filled: bool) -> void:
	for x in range(size):
		for z in range(size):
			layer.set_cell(Vector2i(x, z), filled)


# -- Reclamation --------------------------------------------------------------


func test_erasing_every_cell_gives_the_chunks_back():
	_fill(40, true)
	var chunks_when_painted := layer.get_chunk_ids().size()
	assert_gt(chunks_when_painted, 1, "40 by 40 cells should span more than one chunk")

	_fill(40, false)

	assert_eq(layer.get_chunk_ids().size(), 0, "Every chunk should be gone")


func test_paint_memory_goes_back_down():
	_fill(40, true)
	var painted_bytes := root.get_paint_memory_bytes()
	assert_gt(painted_bytes, 0, "Painting should cost something")

	_fill(40, false)

	assert_eq(root.get_paint_memory_bytes(), 0, "Erasing should give it back")


func test_a_chunk_with_one_cell_left_is_kept():
	_fill(8, true)
	assert_eq(layer.get_chunk_ids().size(), 1, "8 by 8 cells fit in one chunk")

	for x in range(8):
		for z in range(8):
			if x == 0 and z == 0:
				continue
			layer.set_cell(Vector2i(x, z), false)

	assert_eq(layer.get_chunk_ids().size(), 1, "One filled cell still needs its chunk")
	assert_true(layer.get_cell(Vector2i(0, 0)), "and that cell should still be painted")


func test_a_chunk_can_be_repainted_after_it_was_dropped():
	_fill(8, true)
	_fill(8, false)
	assert_eq(layer.get_chunk_ids().size(), 0, "The chunk should have gone")

	layer.set_cell(Vector2i(2, 3), true)

	assert_eq(layer.get_chunk_ids().size(), 1, "and come back when painted again")
	assert_true(layer.get_cell(Vector2i(2, 3)), "with the cell set")


func test_erasing_a_cell_that_was_not_painted_changes_nothing():
	layer.set_cell(Vector2i(5, 5), false)

	assert_eq(layer.get_chunk_ids().size(), 0, "Erasing nothing should not leave a chunk behind")


# -- Nothing empty reaches a save or a snapshot -------------------------------


func test_an_erased_area_is_not_serialized():
	_fill(40, true)
	_fill(40, false)

	var captured: Array = root.state_system.capture_paint_layers(true)

	for entry in captured:
		assert_eq(entry["chunks"], [], "An erased layer should serialize no chunks")


func test_a_painted_area_is_still_serialized():
	_fill(8, true)

	var captured: Array = root.state_system.capture_paint_layers(true)

	assert_eq(captured[0]["chunks"].size(), 1, "A painted chunk should still be written")


func test_paint_survives_a_capture_and_restore():
	_fill(8, true)
	var snapshot = root.capture_state(true)
	_fill(8, false)

	root.restore_state(snapshot)

	var restored = root.paint_layers.get_active_layer()
	assert_true(restored.get_cell(Vector2i(3, 3)), "The painted cell should come back")
	assert_eq(restored.get_chunk_ids().size(), 1, "with its chunk")


# -- The live bit count is right after a wholesale write ----------------------


func test_setting_a_chunk_s_bits_wholesale_recounts_them():
	_fill(8, true)
	var cid: Vector2i = layer.get_chunk_ids()[0]
	var bits := layer.get_chunk_bits(cid)

	layer.set_chunk_bits(cid, bits)

	assert_false(layer.is_chunk_empty(cid), "A chunk loaded with set bits is not empty")
	layer.set_cell(Vector2i(0, 0), false)
	assert_eq(layer.get_chunk_ids().size(), 1, "and clearing one cell does not drop it")


func test_a_chunk_loaded_with_no_bits_reads_as_empty():
	_fill(8, true)
	var cid: Vector2i = layer.get_chunk_ids()[0]
	var blank := PackedByteArray()
	blank.resize(layer.get_chunk_bits(cid).size())

	layer.set_chunk_bits(cid, blank)

	assert_true(layer.is_chunk_empty(cid), "No bits set means empty")
