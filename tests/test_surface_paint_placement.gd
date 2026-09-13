extends GutTest

## Where a surface paint stroke lands, and how much it costs to put it there.
##
## A face's UVs are the projection of its world coordinates, so a 128-unit wall
## spans 128 in U rather than 1. The painted albedo becomes the material's
## `albedo_texture` and is sampled through those same UVs, repeating, so the
## texel under the cursor is the one the fractional part of the UV points at.
## Clamping to 0..1 instead threw the position away.

const SurfacePaintScript = preload("res://addons/hammerforge/surface_paint.gd")

const IMAGE_SIZE := Vector2i(256, 256)


func _painter() -> Node:
	var painter = SurfacePaintScript.new()
	painter.default_layer_size = IMAGE_SIZE
	add_child_autoqfree(painter)
	return painter


func _face() -> FaceData:
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(
		[
			Vector3(-64, -32, 16),
			Vector3(64, -32, 16),
			Vector3(64, 32, 16),
			Vector3(-64, 32, 16),
		]
	)
	return face


## Every texel the stroke moved, as a count and a bounding box.
func _painted(face: FaceData) -> Dictionary:
	var layer = face.paint_layers[0]
	var image: Image = layer.weight_image
	var count := 0
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).r > 0.0:
				count += 1
				lo.x = mini(lo.x, x)
				lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x)
				hi.y = maxi(hi.y, y)
	return {"count": count, "from": lo, "to": hi, "image": image}


# ---------------------------------------------------------------------------
# Where it lands (#464)
# ---------------------------------------------------------------------------


func test_a_stroke_lands_on_the_texel_the_uv_points_at() -> void:
	var painter := _painter()
	var face := _face()
	painter.paint_at_uv(face, 0, Vector2(0.75, 0.5), 0.05, 1.0)
	var result := _painted(face)
	assert_gt(result["count"], 0, "the stroke must move some texels")
	var centre := Vector2i(
		(result["from"].x + result["to"].x) / 2, (result["from"].y + result["to"].y) / 2
	)
	assert_almost_eq(centre.x, 192, 2, "0.75 of 256 is texel 192, not a corner")
	assert_almost_eq(centre.y, 128, 2, "0.5 of 256 is texel 128, not a corner")


func test_two_strokes_at_different_places_move_different_texels() -> void:
	var painter := _painter()
	var near := _face()
	var far := _face()
	# The UVs a 128-unit face reports at two points that are not a whole number
	# of tiles apart. Before the fix both clamped to a corner and painted the
	# same texels, whatever the cursor had been pointing at.
	painter.paint_at_uv(near, 0, Vector2(40.0, 20.0) - Vector2(40.0, 20.0).floor(), 0.05, 1.0)
	painter.paint_at_uv(far, 0, Vector2(-40.25, -20.5) - Vector2(-40.25, -20.5).floor(), 0.05, 1.0)
	var a := _painted(near)
	var b := _painted(far)
	assert_gt(a["count"], 0)
	assert_gt(b["count"], 0)
	assert_ne(
		[a["from"], a["to"]],
		[b["from"], b["to"]],
		"two clicks at different points on a face must not paint the same texels"
	)


func test_paint_surface_at_maps_the_uv_instead_of_clamping_it() -> void:
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_paint_system.gd"
	)
	var start := source.find("func paint_surface_at")
	var body := source.substr(start, source.find("\nfunc ", start + 10) - start)
	assert_false(
		body.contains("uv.x = clamp(uv.x, 0.0, 1.0)"),
		"clamping the UV discards the cursor position on any face larger than one unit"
	)
	assert_true(body.contains("floor(uv.x)"), "it must map through the wrap the renderer uses")


func test_a_stroke_on_the_seam_wraps_instead_of_being_cut_in_half() -> void:
	var painter := _painter()
	var face := _face()
	painter.paint_at_uv(face, 0, Vector2(0.0, 0.5), 0.05, 1.0)
	var image: Image = _painted(face)["image"]
	var painted_left := false
	var painted_right := false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).r > 0.0:
			painted_left = true
		if image.get_pixel(image.get_width() - 1, y).r > 0.0:
			painted_right = true
	assert_true(painted_left, "a stroke at the seam paints this side of it")
	assert_true(painted_right, "and wraps to the other, because the texture it sits in repeats")


func test_a_radius_past_half_the_image_cannot_wrap_onto_itself() -> void:
	var painter := _painter()
	var face := _face()
	# radius_uv 1.0 asks for a brush wider than the tile. Honouring it literally
	# would paint the far side of the wrap twice in one sample.
	painter.paint_at_uv(face, 0, Vector2(0.5, 0.5), 1.0, 0.5)
	var image: Image = _painted(face)["image"]
	# The centre gets the full strength once. A brush that wrapped onto itself
	# would have added the edge of the circle on top of it.
	assert_almost_eq(
		image.get_pixel(128, 128).r, 0.5, 0.01, "the centre is painted once, at full strength"
	)


# ---------------------------------------------------------------------------
# What it costs (#465)
# ---------------------------------------------------------------------------


func test_a_stroke_touches_the_circle_and_not_its_bounding_square() -> void:
	var painter := _painter()
	var face := _face()
	var radius_uv := 0.25
	painter.paint_at_uv(face, 0, Vector2(0.5, 0.5), radius_uv, 1.0)
	var result := _painted(face)
	var radius_px := radius_uv * float(IMAGE_SIZE.x)
	var circle := PI * radius_px * radius_px
	var square := (2.0 * radius_px + 1.0) * (2.0 * radius_px + 1.0)
	# A wall-clock assertion would be a different number on every machine. The
	# thing that made this expensive is structural: it walked the bounding square
	# and threw away the corners, which are about a fifth of it, one texel at a
	# time.
	assert_lt(
		float(result["count"]),
		square * 0.85,
		"a round brush must not be walking its bounding square"
	)
	assert_almost_eq(
		float(result["count"]) / circle,
		1.0,
		0.05,
		"the texels it touches are the ones inside the circle"
	)
