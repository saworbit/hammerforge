extends GutTest

const HFPaintLayer = preload("res://addons/hammerforge/paint/hf_paint_layer.gd")
const HFPaintGrid = preload("res://addons/hammerforge/paint/hf_paint_grid.gd")

var layer: HFPaintLayer


func before_each():
	layer = HFPaintLayer.new()
	layer.grid = HFPaintGrid.new()
	layer.chunk_size = 8
	add_child(layer)


func after_each():
	layer.queue_free()
	layer = null


# ===========================================================================
# Cell bit storage
# ===========================================================================


func test_set_get_cell():
	layer.set_cell(Vector2i(3, 5), true)
	assert_true(layer.get_cell(Vector2i(3, 5)), "Cell should be filled")


func test_cell_default_empty():
	assert_false(layer.get_cell(Vector2i(0, 0)), "Cell should default to empty")


func test_clear_cell():
	layer.set_cell(Vector2i(3, 5), true)
	layer.set_cell(Vector2i(3, 5), false)
	assert_false(layer.get_cell(Vector2i(3, 5)), "Cell should be cleared")


func test_multiple_cells():
	layer.set_cell(Vector2i(0, 0), true)
	layer.set_cell(Vector2i(7, 7), true)
	layer.set_cell(Vector2i(3, 4), true)
	assert_true(layer.get_cell(Vector2i(0, 0)))
	assert_true(layer.get_cell(Vector2i(7, 7)))
	assert_true(layer.get_cell(Vector2i(3, 4)))
	assert_false(layer.get_cell(Vector2i(1, 1)), "Untouched cell should be empty")


func test_negative_cell_coords():
	layer.set_cell(Vector2i(-5, -3), true)
	assert_true(layer.get_cell(Vector2i(-5, -3)), "Negative coords should work")


func test_large_cell_coords():
	layer.set_cell(Vector2i(100, 200), true)
	assert_true(layer.get_cell(Vector2i(100, 200)), "Large coords should work")


# ===========================================================================
# Chunk management
# ===========================================================================


func test_chunk_created_on_set():
	layer.set_cell(Vector2i(0, 0), true)
	var ids = layer.get_chunk_ids()
	assert_eq(ids.size(), 1, "One chunk should be created")
	assert_eq(ids[0], Vector2i(0, 0), "Chunk at origin")


func test_different_chunks_for_distant_cells():
	layer.set_cell(Vector2i(0, 0), true)  # chunk (0,0)
	layer.set_cell(Vector2i(16, 16), true)  # chunk (2,2) with chunk_size=8
	var ids = layer.get_chunk_ids()
	assert_eq(ids.size(), 2, "Two chunks for distant cells")


func test_has_chunk():
	layer.set_cell(Vector2i(0, 0), true)
	assert_true(layer.has_chunk(Vector2i(0, 0)))
	assert_false(layer.has_chunk(Vector2i(5, 5)))


func test_remove_chunk():
	layer.set_cell(Vector2i(0, 0), true)
	var removed = layer.remove_chunk(Vector2i(0, 0))
	assert_true(removed, "Should return true when chunk removed")
	assert_false(layer.has_chunk(Vector2i(0, 0)), "Chunk should be gone")


func test_remove_nonexistent_chunk():
	var removed = layer.remove_chunk(Vector2i(99, 99))
	assert_false(removed, "Should return false for nonexistent chunk")


func test_clear_chunks():
	layer.set_cell(Vector2i(0, 0), true)
	layer.set_cell(Vector2i(16, 16), true)
	layer.clear_chunks()
	assert_eq(layer.get_chunk_ids().size(), 0, "All chunks should be cleared")


# ===========================================================================
# Material IDs
# ===========================================================================


func test_set_get_material():
	layer.set_cell(Vector2i(3, 3), true)
	layer.set_cell_material(Vector2i(3, 3), 5)
	assert_eq(layer.get_cell_material(Vector2i(3, 3)), 5, "Material ID should persist")


func test_default_material_is_zero():
	layer.set_cell(Vector2i(0, 0), true)
	assert_eq(layer.get_cell_material(Vector2i(0, 0)), 0, "Default material should be 0")


func test_material_clamps_to_255():
	layer.set_cell(Vector2i(0, 0), true)
	layer.set_cell_material(Vector2i(0, 0), 300)
	assert_eq(layer.get_cell_material(Vector2i(0, 0)), 255, "Material should clamp to 255")


func test_material_nonexistent_chunk_returns_zero():
	assert_eq(layer.get_cell_material(Vector2i(99, 99)), 0, "Nonexistent chunk material = 0")


# ===========================================================================
# Blend weights
# ===========================================================================


func test_set_get_blend():
	layer.set_cell(Vector2i(2, 2), true)
	layer.set_cell_blend(Vector2i(2, 2), 0.75)
	var blend = layer.get_cell_blend(Vector2i(2, 2))
	assert_almost_eq(blend, 0.75, 0.01, "Blend weight should be ~0.75")


func test_blend_default_is_zero():
	layer.set_cell(Vector2i(0, 0), true)
	assert_almost_eq(layer.get_cell_blend(Vector2i(0, 0)), 0.0, 0.01, "Default blend = 0")


func test_blend_slot_2():
	layer.set_cell(Vector2i(1, 1), true)
	layer.set_cell_blend_slot(Vector2i(1, 1), 2, 0.5)
	var val = layer.get_cell_blend_slot(Vector2i(1, 1), 2)
	assert_almost_eq(val, 0.5, 0.02, "Slot 2 blend weight should be ~0.5")


func test_blend_slot_3():
	layer.set_cell(Vector2i(1, 1), true)
	layer.set_cell_blend_slot(Vector2i(1, 1), 3, 0.9)
	var val = layer.get_cell_blend_slot(Vector2i(1, 1), 3)
	assert_almost_eq(val, 0.9, 0.02, "Slot 3 blend weight should be ~0.9")


func test_blend_slot_1_delegates_to_blend():
	layer.set_cell(Vector2i(1, 1), true)
	layer.set_cell_blend_slot(Vector2i(1, 1), 1, 0.6)
	var val = layer.get_cell_blend(Vector2i(1, 1))
	assert_almost_eq(val, 0.6, 0.02, "Slot 1 should delegate to blend_weights")


func test_blend_invalid_slot_returns_zero():
	layer.set_cell(Vector2i(0, 0), true)
	assert_almost_eq(layer.get_cell_blend_slot(Vector2i(0, 0), 0), 0.0, 0.01, "Slot 0 = 0")
	assert_almost_eq(layer.get_cell_blend_slot(Vector2i(0, 0), 4), 0.0, 0.01, "Slot 4 = 0")


func test_blend_nonexistent_chunk_returns_zero():
	assert_almost_eq(layer.get_cell_blend(Vector2i(99, 99)), 0.0, 0.01, "No chunk = 0")


# ===========================================================================
# Dirty chunk tracking
# ===========================================================================


func test_dirty_chunks_tracked():
	layer.set_cell(Vector2i(0, 0), true)
	var dirty = layer.consume_dirty_chunks()
	assert_true(dirty.size() > 0, "Should have dirty chunks after set_cell")


func test_consume_dirty_clears():
	layer.set_cell(Vector2i(0, 0), true)
	layer.consume_dirty_chunks()
	var dirty2 = layer.consume_dirty_chunks()
	assert_eq(dirty2.size(), 0, "Dirty chunks should be cleared after consume")


# ===========================================================================
# Chunk bits raw access
# ===========================================================================


func test_set_get_chunk_bits():
	layer.set_cell(Vector2i(0, 0), true)
	var bits = layer.get_chunk_bits(Vector2i(0, 0))
	assert_true(bits.size() > 0, "Should get chunk bits")
	# Bit 0 should be set (cell 0,0 in local coords)
	assert_true((bits[0] & 1) != 0, "First bit should be set")


func test_get_chunk_bits_nonexistent():
	var bits = layer.get_chunk_bits(Vector2i(99, 99))
	assert_eq(bits.size(), 0, "Nonexistent chunk should return empty")


# ===========================================================================
# Heightmap
# ===========================================================================


func test_has_heightmap_default_false():
	assert_false(layer.has_heightmap(), "Default layer has no heightmap")


func test_has_heightmap_with_image():
	layer.heightmap = Image.create(64, 64, false, Image.FORMAT_RF)
	assert_true(layer.has_heightmap(), "Layer with image has heightmap")


func test_get_height_at_no_heightmap():
	var h = layer.get_height_at(Vector2i(0, 0))
	assert_almost_eq(h, 0.0, 0.001, "No heightmap should return 0")


func test_get_height_at_with_heightmap():
	var img = Image.create(4, 4, false, Image.FORMAT_RF)
	img.fill(Color(0.5, 0, 0, 1))  # RF format: r = 0.5
	layer.heightmap = img
	layer.height_scale = 10.0
	var h = layer.get_height_at(Vector2i(0, 0))
	assert_almost_eq(h, 5.0, 0.1, "Height should be 0.5 * 10.0 = 5.0")


# ===========================================================================
# Memory bytes
# ===========================================================================


func test_memory_bytes_increases():
	var before = layer.get_memory_bytes()
	layer.set_cell(Vector2i(0, 0), true)
	var after = layer.get_memory_bytes()
	assert_true(after > before, "Memory should increase after adding a cell")
