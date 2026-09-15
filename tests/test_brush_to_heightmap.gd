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


func _track_result_layer(result) -> void:
	if result == null or result.layer == null:
		return
	if result.layer.get_parent() == null:
		add_child_autoqfree(result.layer)


# ===========================================================================
# ConvertSettings defaults
# ===========================================================================


func test_default_settings():
	var s := HFBrushToHeightmapScript.ConvertSettings.new()
	assert_eq(s.cell_size, 1.0)
	assert_eq(s.margin_cells, 2)
	assert_eq(s.remove_sources, false)
	assert_null(s.source_root)
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
	_track_result_layer(result)
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
	_track_result_layer(result)
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


func test_convert_skips_subtractive_brushes():
	var add := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	var sub := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	sub.operation = CSGShape3D.OPERATION_SUBTRACTION
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	var result := converter.convert([add, sub], settings)
	_track_result_layer(result)
	assert_eq(result.error, "")
	assert_eq(result.brush_count, 1)


func test_convert_subtract_only_errors():
	var sub := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	sub.operation = CSGShape3D.OPERATION_SUBTRACTION
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	var result := converter.convert([sub], settings)
	assert_ne(result.error, "")
	assert_null(result.layer)


func test_convert_uses_mesh_bounds_including_displacement_height():
	var brush := _make_brush(Vector3(0, 0, 0), Vector3(2, 2, 2))
	brush._ensure_mesh_instance()
	var box := BoxMesh.new()
	box.size = Vector3(2, 20, 2)
	brush.mesh_instance.mesh = box
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.cell_size = 1.0
	settings.height_scale = 10.0
	var result := converter.convert([brush], settings)
	_track_result_layer(result)
	assert_eq(result.error, "")
	assert_true(result.cell_max.y - result.cell_min.y >= 2)
	var aabb: AABB = converter._get_brush_aabb(brush)
	assert_gt(aabb.size.y, 10.0, "Mesh AABB should include the taller displacement mesh")


func test_convert_multiple_brushes():
	var b1 := _make_brush(Vector3(2, 1, 2), Vector3(2, 2, 2))
	var b2 := _make_brush(Vector3(6, 3, 6), Vector3(2, 6, 2))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	var result := converter.convert([b1, b2], settings)
	_track_result_layer(result)
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
	_track_result_layer(result)
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
	_track_result_layer(result)
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
	_track_result_layer(result)
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
	_track_result_layer(result)
	assert_not_null(result.layer.grid, "New layer should have a grid")
	assert_eq(result.layer.grid.cell_size, settings.cell_size)


func test_new_layer_display_name():
	var brush := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	var converter := HFBrushToHeightmapScript.new()
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	var result := converter.convert([brush], settings)
	_track_result_layer(result)
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
	_track_result_layer(result)
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


# ===========================================================================
# The grid has a ceiling (#512)
# ===========================================================================


## The cell size comes from the level's grid snap, which is set for an unrelated
## reason and has no bearing on how big a heightmap the editor can hold. The
## cost is quadratic, so a fine snap over a large selection allocated hundreds of
## megabytes on the main thread with no progress and no way to stop.
func test_a_selection_too_large_for_the_cell_size_widens_the_cell_size():
	var brush := _make_brush(Vector3.ZERO, Vector3(4096, 32, 4096))
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.cell_size = 0.25

	var result = HFBrushToHeightmapScript.new().convert([brush], settings)
	_track_result_layer(result)

	assert_eq(result.error, "", "the operation stays useful rather than being refused")
	assert_lte(result.heightmap.get_width(), 2048, "width is inside the cap")
	assert_lte(result.heightmap.get_height(), 2048, "height is inside the cap")
	assert_gt(result.cell_size_used, 0.25, "it had to widen to fit")
	assert_ne(result.notice, "", "and it says which cell size it used")


func test_a_selection_that_fits_keeps_the_cell_size_it_was_given():
	var brush := _make_brush(Vector3.ZERO, Vector3(64, 32, 64))
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.cell_size = 4.0

	var result = HFBrushToHeightmapScript.new().convert([brush], settings)
	_track_result_layer(result)

	assert_eq(result.cell_size_used, 4.0, "nothing to widen")
	assert_eq(result.notice, "", "and nothing to say about it")


# ===========================================================================
# remove_sources does what it says (#511)
# ===========================================================================


class RemovalRoot:
	extends Node

	var deleted: Array = []

	func delete_brush(brush: Node, _free: bool = true) -> void:
		deleted.append(brush)


func test_remove_sources_takes_the_rasterised_brushes_out_of_the_level():
	var level := RemovalRoot.new()
	add_child_autoqfree(level)
	var brush := _make_brush(Vector3.ZERO, Vector3(64, 32, 64))
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.cell_size = 4.0
	settings.remove_sources = true
	settings.source_root = level

	var result = HFBrushToHeightmapScript.new().convert([brush], settings)
	_track_result_layer(result)

	assert_eq(level.deleted, [brush], "the geometry is in the level once, not twice")
	assert_eq(result.removed_sources, 1)


func test_remove_sources_leaves_the_brushes_when_it_is_not_asked_for():
	var level := RemovalRoot.new()
	add_child_autoqfree(level)
	var brush := _make_brush(Vector3.ZERO, Vector3(64, 32, 64))
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.cell_size = 4.0
	settings.source_root = level

	var result = HFBrushToHeightmapScript.new().convert([brush], settings)
	_track_result_layer(result)

	assert_eq(level.deleted, [], "the default is to keep them")
	assert_eq(result.removed_sources, 0)


## A brush it never read is not a source it can claim to have converted.
func test_remove_sources_keeps_a_subtractive_brush():
	var level := RemovalRoot.new()
	add_child_autoqfree(level)
	var additive := _make_brush(Vector3.ZERO, Vector3(64, 32, 64))
	var cutter := _make_brush(Vector3(200, 0, 0), Vector3(32, 32, 32))
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.cell_size = 4.0
	settings.remove_sources = true
	settings.source_root = level

	var result = HFBrushToHeightmapScript.new().convert([additive, cutter], settings)
	_track_result_layer(result)

	assert_eq(level.deleted, [additive])
	assert_eq(result.removed_sources, 1)


func test_remove_sources_without_a_root_keeps_the_brushes():
	var brush := _make_brush(Vector3.ZERO, Vector3(64, 32, 64))
	var settings := HFBrushToHeightmapScript.ConvertSettings.new()
	settings.cell_size = 4.0
	settings.remove_sources = true

	var result = HFBrushToHeightmapScript.new().convert([brush], settings)
	_track_result_layer(result)

	assert_eq(result.removed_sources, 0, "a brush has to go out through the brush system")
	assert_true(is_instance_valid(brush))
