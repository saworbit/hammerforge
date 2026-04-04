extends GutTest

const HFBrushToHeightmapScript = preload("res://addons/hammerforge/paint/hf_brush_to_heightmap.gd")
const HFPaintLayerScript = preload("res://addons/hammerforge/paint/hf_paint_layer.gd")
const HFPaintGridScript = preload("res://addons/hammerforge/paint/hf_paint_grid.gd")


# ===========================================================================
# Helper: create a brush node with position and size
# ===========================================================================


func _make_brush(pos: Vector3, sz: Vector3) -> DraftBrush:
	var b := DraftBrush.new()
	b.size = sz
	add_child_autoqfree(b)
	b.global_position = pos
	return b


# ===========================================================================
# ConvertSettings defaults
# ===========================================================================


func test_default_settings():
	var s := HFBrushToHeightmapScript.ConvertSettings.new()
	assert_eq(s.cell_size, 1.0)
	assert_eq(s.margin_cells, 2)
	assert_eq(s.remove_sources, false)
	assert_eq(s.height_scale, 10.0)
	assert_null(s.target_layer)


# ===========================================================================
# Empty input
# ===========================================================================


func test_convert_empty_array():
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	var result := converter.convert([], settings)
	assert_ne(result.error, "", "Should produce an error for empty input")
	assert_null(result.layer)


# ===========================================================================
# Single brush conversion
# ===========================================================================


func test_convert_single_brush():
	var brush := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.cell_size = 1.0
	settings.height_scale = 10.0
	var result := converter.convert([brush], settings)
	assert_eq(result.error, "")
	assert_not_null(result.layer)
	assert_not_null(result.heightmap)
	assert_eq(result.brush_count, 1)
	assert_true(result.cell_min.x <= result.cell_max.x)
	assert_true(result.cell_min.y <= result.cell_max.y)


func test_convert_produces_filled_cells():
	var brush := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.cell_size = 1.0
	var result := converter.convert([brush], settings)
	assert_eq(result.error, "")
	var filled := 0
	for cid in result.layer.get_chunk_ids():
		var chunk_size := result.layer.chunk_size
		var origin := Vector2i(cid.x * chunk_size, cid.y * chunk_size)
		for y in range(chunk_size):
			for x in range(chunk_size):
				if result.layer.get_cell(origin + Vector2i(x, y)):
					filled += 1
	assert_gt(filled, 0, "Should have filled cells from the brush footprint")


# ===========================================================================
# Multiple brush conversion
# ===========================================================================


func test_convert_multiple_brushes():
	var b1 := _make_brush(Vector3(2, 1, 2), Vector3(2, 2, 2))
	var b2 := _make_brush(Vector3(6, 3, 6), Vector3(2, 6, 2))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	var result := converter.convert([b1, b2], settings)
	assert_eq(result.error, "")
	assert_eq(result.brush_count, 2)
	assert_not_null(result.heightmap)


# ===========================================================================
# Height scale
# ===========================================================================


func test_height_scale_applied():
	var brush := _make_brush(Vector3(5, 5, 5), Vector3(2, 10, 2))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.height_scale = 20.0
	var result := converter.convert([brush], settings)
	assert_eq(result.error, "")
	assert_eq(result.layer.height_scale, 20.0)


# ===========================================================================
# ConvertResult fields
# ===========================================================================


func test_result_cell_bounds():
	var brush := _make_brush(Vector3(10, 1, 10), Vector3(6, 2, 6))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.margin_cells = 3
	var result := converter.convert([brush], settings)
	assert_eq(result.error, "")
	assert_lt(result.cell_min.x, 10, "Min X should be before brush center")
	assert_gt(result.cell_max.x, 10, "Max X should be after brush center")


# ===========================================================================
# Target layer reuse
# ===========================================================================


func test_target_layer_reuse():
	var layer := HFPaintLayerScript.new()
	layer.layer_id = &"existing"
	layer.grid = HFPaintGridScript.new()
	layer.grid.cell_size = 1.0
	add_child_autoqfree(layer)

	var brush := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.target_layer = layer
	var result := converter.convert([brush], settings)
	assert_eq(result.error, "")
	assert_eq(result.layer, layer, "Should reuse the target layer")
	assert_eq(result.layer.layer_id, &"existing")


# ===========================================================================
# Layer properties
# ===========================================================================


func test_new_layer_has_grid():
	var brush := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	var result := converter.convert([brush], settings)
	assert_not_null(result.layer.grid, "New layer should have a grid")
	assert_eq(result.layer.grid.cell_size, settings.cell_size)


func test_new_layer_display_name():
	var brush := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	var result := converter.convert([brush], settings)
	assert_eq(result.layer.display_name, "Converted Terrain")


# ===========================================================================
# Heightmap coordinate round-trip (posmod alignment)
# ===========================================================================


func test_height_roundtrip_nonzero_origin():
	# Place a brush far from origin so cell_min != (0,0)
	var brush := _make_brush(Vector3(50, 3, 50), Vector3(4, 6, 4))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.cell_size = 1.0
	settings.height_scale = 10.0
	settings.margin_cells = 1
	var result := converter.convert([brush], settings)
	assert_eq(result.error, "")
	# The layer should read back non-zero height for cells under the brush
	var layer := result.layer
	var center_cell := Vector2i(50, 50)
	var h := layer.get_height_at(center_cell)
	assert_gt(h, 0.0, "Height at brush center cell should be > 0 (got %f)" % h)
	# Also test a cell outside the brush footprint but inside the image
	var outside_cell := result.cell_min  # margin cell, no brush coverage
	var h_outside := layer.get_height_at(outside_cell)
	assert_eq(h_outside, 0.0, "Height outside brush should be 0")
