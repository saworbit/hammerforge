@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Where a surface paint stroke lands on the face the mapper clicked.
##
## The path is three steps: `pick_face_from_ray()` returns the face and the UV
## under the cursor, `HFPaintSystem.paint_surface_at()` clamps that UV to 0..1,
## and `SurfacePaint.paint_at_uv()` turns it into a pixel in the layer's weight
## image. This drives all three with a ray aimed at a known spot on a known
## face, and then reads the image back to see which texels moved.
##
## The UV a face carries is the projected one, and `_project_uvs_for_vertices()`
## projects world coordinates -- a 128 unit wall spans 128 in U, not 1.

const FaceSelector = preload("res://addons/hammerforge/face_selector.gd")


func id() -> String:
	return "surface-paint"


func summary() -> String:
	return "where a surface paint stroke lands against where the cursor was"


func run() -> void:
	await _where_the_stroke_lands()
	await _what_a_stroke_costs()


## The pixels above zero in a weight image, as a bounding box in texels.
func _painted_bounds(image: Image) -> Dictionary:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).r > 0.01:
				count += 1
				lo.x = mini(lo.x, x)
				lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x)
				hi.y = maxi(hi.y, y)
	return {"count": count, "from": lo, "to": hi}


func _where_the_stroke_lands() -> void:
	var root: Node3D = await fresh_root("PaintLevel")
	var b = box(root, Vector3(128, 64, 32))
	await frame()

	# A ray at the +Z face, three quarters of the way along it and above centre:
	# the cursor is plainly not in a corner.
	var target := Vector3(40.0, 20.0, 16.0)
	var hit: Dictionary = root.brush_system.pick_face_from_ray(
		target + Vector3(0, 0, 200), Vector3(0, 0, -1)
	)
	if hit.is_empty():
		flag("the face picker missed a face the ray passes through", target)
		return
	note("picked face index", hit.get("face_idx", -1))
	note("hit position", hit.get("position", Vector3.ZERO))
	note("UV the picker reports", hit.get("uv", Vector2.ZERO))

	var face_idx := int(hit.get("face_idx", 0))
	var face = b.faces[face_idx]
	root.add_surface_paint_layer(str(b.get_meta("brush_id", "")), face_idx)
	await frame()
	var uv: Vector2 = hit.get("uv", Vector2.ZERO)
	# The two lines HFPaintSystem.paint_surface_at() runs before painting. The
	# painted albedo is sampled through the face's own UVs, repeating, so the
	# texel under the cursor is the one the fractional part points at.
	var mapped := _tile_uv(uv)
	note("UV after the mapping paint_surface_at applies", mapped)
	root.surface_paint.paint_at_uv(face, 0, mapped, 0.1, 1.0)
	await frame()

	var layer = face.paint_layers[0] if face.paint_layers.size() > 0 else null
	if layer == null or layer.weight_image == null:
		flag("no weight image after a stroke", "paint_at_uv made no layer to paint into")
		return
	var image: Image = layer.weight_image
	var bounds: Dictionary = _painted_bounds(image)
	note("weight image size", image.get_size())
	note("texels the stroke moved", bounds["count"])
	note("painted region, in texels", "%s .. %s" % [bounds["from"], bounds["to"]])
	var expected := Vector2i(int(mapped.x * image.get_width()), int(mapped.y * image.get_height()))
	note("texel the mapped UV points at", expected)
	if bounds["count"] <= 0:
		flag("a stroke moved no texels at all", "paint_at_uv painted nothing")

	# Second stroke, at the far end of the same face and deliberately not a whole
	# number of tiles away: the texture repeats every world unit, so two points an
	# exact multiple apart are the same point in it. If the cursor position is
	# being thrown away, these two land in the same texels anyway.
	var far_target := Vector3(-40.25, -20.5, 16.0)
	var far_hit: Dictionary = root.brush_system.pick_face_from_ray(
		far_target + Vector3(0, 0, 200), Vector3(0, 0, -1)
	)
	var far_uv: Vector2 = far_hit.get("uv", Vector2.ZERO)
	var far_mapped := _tile_uv(far_uv)
	note("UV at the far end of the same face", far_uv)
	note("the same after the mapping", far_mapped)
	if far_mapped.is_equal_approx(mapped):
		flag(
			"two clicks %.2f apart map to the same UV" % far_target.distance_to(target),
			(
				"paint_surface_at() is discarding the position the picker reported."
				+ (
					" Both came back as %s, so every stroke on this face paints the same texels."
					% far_mapped
				)
			)
		)

	var far_face = b.faces[int(far_hit.get("face_idx", face_idx))]
	root.add_surface_paint_layer(
		str(b.get_meta("brush_id", "")), int(far_hit.get("face_idx", face_idx))
	)
	await frame()
	var far_layer = far_face.paint_layers[0] if far_face.paint_layers.size() > 0 else null
	if far_layer == null or far_layer.weight_image == null:
		return
	# Paint the far stroke into a fresh layer and compare where it landed.
	far_layer.weight_image.fill(Color(0, 0, 0, 1))
	root.surface_paint.paint_at_uv(far_face, 0, far_mapped, 0.1, 1.0)
	await frame()
	var far_bounds: Dictionary = _painted_bounds(far_layer.weight_image)
	note("the far stroke landed in", "%s .. %s" % [far_bounds["from"], far_bounds["to"]])
	if far_bounds["from"] == bounds["from"] and far_bounds["to"] == bounds["to"]:
		flag(
			"two strokes at opposite ends of a face moved the same texels",
			"the cursor position is not reaching the weight image"
		)


## The mapping paint_surface_at() applies: the fractional part, which is what the
## renderer samples the painted albedo with.
func _tile_uv(uv: Vector2) -> Vector2:
	return Vector2(uv.x - floor(uv.x), uv.y - floor(uv.y))


func _what_a_stroke_costs() -> void:
	var root: Node3D = await fresh_root("PaintCostLevel")
	var b = box(root, Vector3(128, 64, 32))
	await frame()
	root.add_surface_paint_layer(str(b.get_meta("brush_id", "")), 4)
	await frame()
	var face = b.faces[4]
	if face.paint_layers.is_empty():
		note("no layer to paint into", "skipping the cost half")
		return
	var started := Time.get_ticks_usec()
	for _i in 10:
		root.surface_paint.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.5, 1.0)
	var per_sample := float(Time.get_ticks_usec() - started) / 10000.0
	note("ms per paint sample at the dock's largest radius", per_sample)
	# The square scan measured about 52 ms a sample on the machine this was
	# written on and the per-row spans brought it to about 17. The threshold is
	# set well clear of both, because it is a wall-clock number on whatever
	# machine runs it: what it catches is a return to scanning the bounding
	# square, not a slow afternoon.
	if per_sample > 30.0:
		flag(
			"one paint sample at the dock's largest radius costs %.1f ms" % per_sample,
			(
				"paint_at_uv() is meant to walk each row's own span. A cost in this range"
				+ " means it is back to the (2r+1)^2 bounding square, and"
				+ " HFPaintSystem.handle_paint_input() calls it on every mouse-motion event"
				+ " while the button is held."
			)
		)
	var rebuild_started := Time.get_ticks_usec()
	for _i in 10:
		b.rebuild_preview()
	note(
		"ms per rebuild_preview, which paint_surface_at also runs per sample",
		float(Time.get_ticks_usec() - rebuild_started) / 10000.0
	)
