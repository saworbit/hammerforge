extends GutTest
## Behavioural coverage for the three paint hot paths converted to packed buffers:
## `SurfacePaint.paint_at_uv`, `FaceData.get_painted_albedo` and
## `HFPaintTool._apply_terrain_brush` (issue #39).
##
## None of these had direct coverage before, which is how `paint_at_uv` shipped a
## Godot 3 `Image.lock()` call that aborts the function on Godot 4.

const FaceData = preload("res://addons/hammerforge/face_data.gd")
const SurfacePaint = preload("res://addons/hammerforge/surface_paint.gd")
const HFPaintTool = preload("res://addons/hammerforge/paint/hf_paint_tool.gd")
const HFPaintLayer = preload("res://addons/hammerforge/paint/hf_paint_layer.gd")
const HFStroke = preload("res://addons/hammerforge/paint/hf_stroke.gd")

# ===========================================================================
# SurfacePaint.paint_at_uv
# ===========================================================================


func _make_surface_paint() -> SurfacePaint:
	var sp = SurfacePaint.new()
	sp.default_layer_size = Vector2i(32, 32)
	return autofree(sp)


func test_paint_at_uv_writes_weight_into_the_layer():
	# Regression: the previous implementation called Image.lock(), which does not
	# exist in Godot 4, so every surface paint stroke aborted before writing.
	var sp = _make_surface_paint()
	var face = FaceData.new()
	sp.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.25, 1.0)
	assert_eq(face.paint_layers.size(), 1, "layer 0 was created")
	var img: Image = face.paint_layers[0].weight_image
	assert_not_null(img, "weight image exists")
	assert_almost_eq(img.get_pixel(16, 16).r, 1.0, 0.02, "centre texel painted to full weight")


func test_paint_at_uv_falls_off_towards_the_brush_edge():
	var sp = _make_surface_paint()
	var face = FaceData.new()
	sp.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.25, 1.0)
	var img: Image = face.paint_layers[0].weight_image
	var centre := img.get_pixel(16, 16).r
	var midway := img.get_pixel(20, 16).r
	var outside := img.get_pixel(31, 16).r
	assert_gt(centre, midway, "centre is stronger than midway")
	assert_gt(midway, outside, "midway is stronger than outside the radius")
	assert_almost_eq(outside, 0.0, 0.001, "texels beyond the radius are untouched")


func test_paint_at_uv_accumulates_across_strokes():
	var sp = _make_surface_paint()
	var face = FaceData.new()
	sp.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.25, 0.4)
	var first: float = face.paint_layers[0].weight_image.get_pixel(16, 16).r
	sp.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.25, 0.4)
	var second: float = face.paint_layers[0].weight_image.get_pixel(16, 16).r
	assert_gt(second, first, "a second pass adds more weight")


func test_paint_at_uv_erases_with_negative_strength():
	var sp = _make_surface_paint()
	var face = FaceData.new()
	sp.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.25, 1.0)
	sp.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.25, -1.0)
	var img: Image = face.paint_layers[0].weight_image
	assert_almost_eq(img.get_pixel(16, 16).r, 0.0, 0.02, "negative strength erases the weight")


func test_paint_at_uv_clamps_at_the_image_edges():
	var sp = _make_surface_paint()
	var face = FaceData.new()
	sp.paint_at_uv(face, 0, Vector2(0.0, 0.0), 0.25, 1.0)
	var img: Image = face.paint_layers[0].weight_image
	assert_gt(img.get_pixel(0, 0).r, 0.5, "corner texel painted without going out of bounds")


func test_paint_at_uv_handles_a_non_rgba8_weight_image():
	var sp = _make_surface_paint()
	var face = FaceData.new()
	var layer = FaceData.PaintLayer.new()
	layer.weight_image = Image.create(32, 32, false, Image.FORMAT_RGB8)
	layer.weight_image.fill(Color(0, 0, 0))
	face.paint_layers.append(layer)
	sp.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.25, 1.0)
	var img: Image = face.paint_layers[0].weight_image
	assert_almost_eq(img.get_pixel(16, 16).r, 1.0, 0.02, "centre texel painted on an RGB8 layer")


func test_paint_at_uv_creates_intermediate_layers():
	var sp = _make_surface_paint()
	var face = FaceData.new()
	sp.paint_at_uv(face, 2, Vector2(0.5, 0.5), 0.25, 1.0)
	assert_eq(face.paint_layers.size(), 3, "layers 0..2 exist")
	assert_gt(face.paint_layers[2].weight_image.get_pixel(16, 16).r, 0.5, "layer 2 painted")


func test_paint_at_uv_ignores_a_null_face():
	var sp = _make_surface_paint()
	sp.paint_at_uv(null, 0, Vector2(0.5, 0.5), 0.25, 1.0)
	pass_test("painting a null face is a no-op rather than a crash")


# ===========================================================================
# FaceData.get_painted_albedo
# ===========================================================================


func _solid_texture(color: Color, size: int = 16) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _weight_image(value: float, size: int = 16) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(value, 0, 0, 1))
	return img


func _add_layer(face: FaceData, color: Color, weight: float, mode: int, opacity := 1.0) -> void:
	var layer = FaceData.PaintLayer.new()
	layer.texture = _solid_texture(color)
	layer.weight_image = _weight_image(weight)
	layer.blend_mode = mode
	layer.opacity = opacity
	face.paint_layers.append(layer)


func test_get_painted_albedo_returns_null_without_layers():
	assert_null(FaceData.new().get_painted_albedo(), "no layers means no composite")


func test_get_painted_albedo_full_weight_overlay_replaces_the_base():
	var face = FaceData.new()
	_add_layer(face, Color(0.2, 0.4, 0.6, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	var out := face.get_painted_albedo()
	assert_not_null(out, "composite produced")
	var px := out.get_pixel(8, 8)
	assert_almost_eq(px.r, 0.2, 0.01, "red replaced by the layer texture")
	assert_almost_eq(px.g, 0.4, 0.01, "green replaced by the layer texture")
	assert_almost_eq(px.b, 0.6, 0.01, "blue replaced by the layer texture")


func test_get_painted_albedo_zero_weight_keeps_the_white_base():
	var face = FaceData.new()
	_add_layer(face, Color(0.0, 0.0, 0.0, 1.0), 0.0, FaceData.PaintBlend.OVERLAY)
	var px := face.get_painted_albedo().get_pixel(8, 8)
	assert_almost_eq(px.r, 1.0, 0.01, "unpainted texels stay white")


func test_get_painted_albedo_half_weight_blends_halfway():
	var face = FaceData.new()
	_add_layer(face, Color(0.0, 0.0, 0.0, 1.0), 0.5, FaceData.PaintBlend.OVERLAY)
	var px := face.get_painted_albedo().get_pixel(8, 8)
	assert_almost_eq(px.r, 0.5, 0.02, "half weight lands halfway between white and black")


func test_get_painted_albedo_opacity_scales_the_weight():
	var face = FaceData.new()
	_add_layer(face, Color(0.0, 0.0, 0.0, 1.0), 1.0, FaceData.PaintBlend.OVERLAY, 0.25)
	var px := face.get_painted_albedo().get_pixel(8, 8)
	assert_almost_eq(px.r, 0.75, 0.02, "opacity 0.25 leaves 75% of the white base")


func test_get_painted_albedo_multiply_darkens():
	var face = FaceData.new()
	_add_layer(face, Color(0.5, 0.5, 0.5, 1.0), 1.0, FaceData.PaintBlend.MULTIPLY)
	var px := face.get_painted_albedo().get_pixel(8, 8)
	assert_almost_eq(px.r, 0.5, 0.01, "multiply against a white base yields the texture")


func test_get_painted_albedo_add_saturates():
	var face = FaceData.new()
	_add_layer(face, Color(0.5, 0.5, 0.5, 1.0), 1.0, FaceData.PaintBlend.ADD)
	var px := face.get_painted_albedo().get_pixel(8, 8)
	assert_almost_eq(px.r, 1.0, 0.01, "adding to a white base clamps at 1.0")


func test_get_painted_albedo_stacks_layers_in_order():
	var face = FaceData.new()
	_add_layer(face, Color(1.0, 0.0, 0.0, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	_add_layer(face, Color(0.0, 0.0, 1.0, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	var px := face.get_painted_albedo().get_pixel(8, 8)
	assert_almost_eq(px.b, 1.0, 0.01, "the last full-weight layer wins")
	assert_almost_eq(px.r, 0.0, 0.01, "the earlier layer is fully covered")


func test_get_painted_albedo_skips_zero_opacity_layers():
	var face = FaceData.new()
	_add_layer(face, Color(0.0, 0.0, 0.0, 1.0), 1.0, FaceData.PaintBlend.OVERLAY, 0.0)
	var px := face.get_painted_albedo().get_pixel(8, 8)
	assert_almost_eq(px.r, 1.0, 0.01, "a zero-opacity layer contributes nothing")


func test_get_painted_albedo_handles_a_compressed_source_texture():
	# get_image() on a non-RGBA8 texture used to be indexed directly; the packed
	# path duplicates and converts so the texture's own image is never mutated.
	var src := Image.create(16, 16, false, Image.FORMAT_RGB8)
	src.fill(Color(0.25, 0.5, 0.75))
	var tex := ImageTexture.create_from_image(src)
	var face = FaceData.new()
	var layer = FaceData.PaintLayer.new()
	layer.texture = tex
	layer.weight_image = _weight_image(1.0)
	face.paint_layers.append(layer)
	var px := face.get_painted_albedo().get_pixel(8, 8)
	assert_almost_eq(px.g, 0.5, 0.02, "RGB8 source composited correctly")
	assert_eq(tex.get_image().get_format(), Image.FORMAT_RGB8, "source texture left untouched")


func test_get_painted_albedo_respects_max_size():
	var face = FaceData.new()
	var layer = FaceData.PaintLayer.new()
	layer.texture = _solid_texture(Color(0, 0, 0, 1), 64)
	layer.weight_image = _weight_image(1.0, 64)
	face.paint_layers.append(layer)
	var out := face.get_painted_albedo(16)
	assert_eq(out.get_width(), 16, "composite downscaled to max_size")
	assert_eq(out.get_height(), 16, "composite downscaled to max_size")


func test_get_painted_albedo_sizes_to_the_weight_image_not_the_texture():
	# When a layer has a weight image, that image alone sets the composite size —
	# the texture is resampled to match, even when it is larger.
	var face = FaceData.new()
	var layer = FaceData.PaintLayer.new()
	layer.texture = _solid_texture(Color(0, 0, 0, 1), 32)
	layer.weight_image = _weight_image(1.0, 8)
	face.paint_layers.append(layer)
	var out := face.get_painted_albedo()
	assert_eq(out.get_width(), 8, "composite sized from the weight image")
	assert_almost_eq(out.get_pixel(4, 4).r, 0.0, 0.02, "the downscaled texture still paints")


func test_get_painted_albedo_sizes_from_the_texture_without_a_weight_image():
	var face = FaceData.new()
	var layer = FaceData.PaintLayer.new()
	layer.texture = _solid_texture(Color(0, 0, 0, 1), 32)
	face.paint_layers.append(layer)
	var out := face.get_painted_albedo()
	assert_eq(out.get_width(), 32, "composite sized from the texture")
	assert_not_null(layer.weight_image, "a default weight image was created for the layer")


# ===========================================================================
# HFPaintTool._apply_terrain_brush
# ===========================================================================


func _make_sculpt_layer(size: int = 32, fill: float = 0.5) -> HFPaintLayer:
	var layer = autofree(HFPaintLayer.new())
	layer.chunk_size = 16
	layer.heightmap = Image.create(size, size, false, Image.FORMAT_RF)
	layer.heightmap.fill(Color(fill, 0, 0))
	return layer


func _make_tool() -> HFPaintTool:
	var t = autofree(HFPaintTool.new())
	t.sculpt_radius = 4.0
	t.sculpt_strength = 20.0
	t.sculpt_falloff = 0.5
	return t


func test_sculpt_raise_lifts_the_centre_most():
	var t = _make_tool()
	var layer = _make_sculpt_layer()
	t.tool = HFStroke.Tool.SCULPT_RAISE
	t._apply_terrain_brush(layer, Vector2i(16, 16))
	var centre: float = layer.heightmap.get_pixel(16, 16).r
	var edge: float = layer.heightmap.get_pixel(19, 16).r
	assert_gt(centre, 0.5, "centre raised above the flat base")
	assert_gt(centre, edge, "falloff means the centre rises more than the edge")
	assert_almost_eq(
		layer.heightmap.get_pixel(0, 0).r, 0.5, 0.0001, "outside the brush is untouched"
	)


func test_sculpt_lower_drops_the_centre_most():
	var t = _make_tool()
	var layer = _make_sculpt_layer()
	t.tool = HFStroke.Tool.SCULPT_LOWER
	t._apply_terrain_brush(layer, Vector2i(16, 16))
	assert_lt(layer.heightmap.get_pixel(16, 16).r, 0.5, "centre lowered below the flat base")


func test_sculpt_clamps_to_the_unit_range():
	var t = _make_tool()
	t.sculpt_strength = 500.0
	var layer = _make_sculpt_layer(32, 0.9)
	t.tool = HFStroke.Tool.SCULPT_RAISE
	t._apply_terrain_brush(layer, Vector2i(16, 16))
	assert_almost_eq(layer.heightmap.get_pixel(16, 16).r, 1.0, 0.0001, "height clamps at 1.0")


func test_sculpt_smooth_pulls_a_spike_towards_its_neighbours():
	var t = _make_tool()
	var layer = _make_sculpt_layer()
	layer.heightmap.set_pixel(16, 16, Color(1.0, 1.0, 1.0))
	t.tool = HFStroke.Tool.SCULPT_SMOOTH
	t._apply_terrain_brush(layer, Vector2i(16, 16))
	var after: float = layer.heightmap.get_pixel(16, 16).r
	assert_lt(after, 1.0, "the spike was pulled down")
	assert_gt(after, 0.5, "smoothing does not overshoot past the neighbourhood")


func test_sculpt_flatten_pulls_towards_the_captured_height():
	var t = _make_tool()
	var layer = _make_sculpt_layer()
	# Ramp so the brush footprint has varying heights around the captured centre.
	for y in range(32):
		for x in range(32):
			layer.heightmap.set_pixel(x, y, Color(float(x) / 32.0, 0, 0))
	t.tool = HFStroke.Tool.SCULPT_FLATTEN
	var before: float = layer.heightmap.get_pixel(19, 16).r
	t._apply_terrain_brush(layer, Vector2i(16, 16))
	var captured := 16.0 / 32.0
	var after: float = layer.heightmap.get_pixel(19, 16).r
	assert_lt(
		absf(after - captured), absf(before - captured), "texel moved towards the centre height"
	)


func test_sculpt_wraps_across_the_heightmap_edges():
	var t = _make_tool()
	var layer = _make_sculpt_layer()
	t.tool = HFStroke.Tool.SCULPT_RAISE
	t._apply_terrain_brush(layer, Vector2i(0, 0))
	assert_gt(layer.heightmap.get_pixel(31, 31).r, 0.5, "the brush wraps to the opposite corner")


func test_sculpt_marks_the_touched_chunks_dirty():
	var t = _make_tool()
	var layer = _make_sculpt_layer()
	layer.grid = HFPaintGrid.new()
	t.tool = HFStroke.Tool.SCULPT_RAISE
	t._apply_terrain_brush(layer, Vector2i(16, 16))
	assert_gt(layer.consume_dirty_chunks().size(), 0, "affected chunks were flagged for rebuild")


func test_sculpt_marks_no_chunks_without_a_grid():
	var t = _make_tool()
	var layer = _make_sculpt_layer()
	t.tool = HFStroke.Tool.SCULPT_RAISE
	t._apply_terrain_brush(layer, Vector2i(16, 16))
	assert_eq(layer.consume_dirty_chunks().size(), 0, "a grid-less layer flags nothing")


func test_sculpt_handles_a_non_rf_heightmap():
	var t = _make_tool()
	var layer = _make_sculpt_layer()
	layer.heightmap = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	layer.heightmap.fill(Color(0.5, 0.5, 0.5, 1.0))
	t.tool = HFStroke.Tool.SCULPT_RAISE
	t._apply_terrain_brush(layer, Vector2i(16, 16))
	assert_gt(layer.heightmap.get_pixel(16, 16).r, 0.5, "sculpt applies to a non-RF heightmap")


func test_sculpt_ignores_a_layer_without_a_heightmap():
	var t = _make_tool()
	var layer = autofree(HFPaintLayer.new())
	t.tool = HFStroke.Tool.SCULPT_RAISE
	t._apply_terrain_brush(layer, Vector2i(16, 16))
	pass_test("sculpting a heightmap-less layer is a no-op rather than a crash")


# ===========================================================================
# Composite cache
# ===========================================================================


func test_composite_cache_returns_the_same_image_when_nothing_changed():
	var face = FaceData.new()
	_add_layer(face, Color(0.2, 0.4, 0.6, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	var first := face.get_painted_albedo()
	assert_eq(face.get_painted_albedo(), first, "a second call reuses the cached composite")


func test_composite_cache_rebuilds_after_painting():
	var sp = _make_surface_paint()
	var face = FaceData.new()
	_add_layer(face, Color(0.0, 0.0, 0.0, 1.0), 0.0, FaceData.PaintBlend.OVERLAY)
	var before := face.get_painted_albedo()
	assert_almost_eq(before.get_pixel(8, 8).r, 1.0, 0.01, "nothing painted yet")
	sp.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.9, 1.0)
	var after := face.get_painted_albedo()
	assert_ne(after, before, "painting invalidates the cached composite")
	assert_lt(after.get_pixel(8, 8).r, 0.5, "the new composite shows the stroke")


func test_composite_cache_rebuilds_after_an_opacity_change():
	var face = FaceData.new()
	_add_layer(face, Color(0.0, 0.0, 0.0, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	var before := face.get_painted_albedo()
	face.paint_layers[0].opacity = 0.25
	var after := face.get_painted_albedo()
	assert_ne(after, before, "opacity is part of the cache key")
	assert_almost_eq(after.get_pixel(8, 8).r, 0.75, 0.02, "the new opacity is applied")


func test_composite_cache_rebuilds_after_a_blend_mode_change():
	var face = FaceData.new()
	_add_layer(face, Color(0.5, 0.5, 0.5, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	var before := face.get_painted_albedo()
	face.paint_layers[0].blend_mode = FaceData.PaintBlend.ADD
	var after := face.get_painted_albedo()
	assert_ne(after, before, "blend mode is part of the cache key")
	assert_almost_eq(after.get_pixel(8, 8).r, 1.0, 0.01, "ADD saturates against the white base")


func test_composite_cache_rebuilds_after_a_texture_swap():
	var face = FaceData.new()
	_add_layer(face, Color(1.0, 0.0, 0.0, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	var before := face.get_painted_albedo()
	face.paint_layers[0].texture = _solid_texture(Color(0.0, 0.0, 1.0, 1.0))
	var after := face.get_painted_albedo()
	assert_ne(after, before, "the texture identity is part of the cache key")
	assert_almost_eq(after.get_pixel(8, 8).b, 1.0, 0.01, "the swapped texture is composited")


func test_composite_cache_rebuilds_after_a_layer_is_added():
	var face = FaceData.new()
	_add_layer(face, Color(1.0, 0.0, 0.0, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	var before := face.get_painted_albedo()
	_add_layer(face, Color(0.0, 1.0, 0.0, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	var after := face.get_painted_albedo()
	assert_ne(after, before, "the layer count is part of the cache key")
	assert_almost_eq(after.get_pixel(8, 8).g, 1.0, 0.01, "the added layer is composited")


func test_composite_cache_is_keyed_by_max_size():
	var face = FaceData.new()
	_add_layer(face, Color(0.0, 0.0, 0.0, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	var full := face.get_painted_albedo(16)
	var small := face.get_painted_albedo(8)
	assert_eq(full.get_width(), 16, "first request honoured max_size 16")
	assert_eq(small.get_width(), 8, "a different max_size is not served from cache")


func test_invalidate_painted_albedo_forces_a_rebuild():
	var face = FaceData.new()
	_add_layer(face, Color(0.2, 0.4, 0.6, 1.0), 1.0, FaceData.PaintBlend.OVERLAY)
	var before := face.get_painted_albedo()
	face.invalidate_painted_albedo()
	var after := face.get_painted_albedo()
	assert_ne(after, before, "explicit invalidation drops the cached image")
	assert_almost_eq(after.get_pixel(8, 8).r, 0.2, 0.01, "the rebuild produces the same result")
