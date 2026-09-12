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
	# The two lines HFPaintSystem.paint_surface_at() runs before painting.
	var clamped := Vector2(clampf(uv.x, 0.0, 1.0), clampf(uv.y, 0.0, 1.0))
	note("UV after the clamp paint_surface_at applies", clamped)
	root.surface_paint.paint_at_uv(face, 0, clamped, 0.1, 1.0)
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
	var expected := Vector2i(
		int(clamped.x * image.get_width()), int(clamped.y * image.get_height())
	)
	note("texel the clamped UV points at", expected)

	if not is_equal_approx(uv.x, clamped.x) or not is_equal_approx(uv.y, clamped.y):
		known(
			464,
			"a surface paint stroke always lands in one corner of the face",
			(
				(
					"pick_face_from_ray() reports the face's own UV, and a face's UVs are the"
					+ " projection of its world coordinates -- this hit at %s came back as UV %s."
					+ " paint_surface_at() then clamps that to 0..1, so every stroke anywhere on a"
					+ " face larger than one unit lands at the same clamped corner (%s here) no"
					+ " matter where the cursor was. The stroke moved %d texels, all inside %s..%s"
					+ " of a %s image."
				)
				% [
					hit.get("position", Vector3.ZERO),
					uv,
					clamped,
					int(bounds["count"]),
					bounds["from"],
					bounds["to"],
					image.get_size(),
				]
			)
		)

	# Second stroke, at the opposite end of the same face. If the clamp is
	# collapsing them, both land in the same texels.
	var far_target := Vector3(-40.0, -20.0, 16.0)
	var far_hit: Dictionary = root.brush_system.pick_face_from_ray(
		far_target + Vector3(0, 0, 200), Vector3(0, 0, -1)
	)
	var far_uv: Vector2 = far_hit.get("uv", Vector2.ZERO)
	var far_clamped := Vector2(clampf(far_uv.x, 0.0, 1.0), clampf(far_uv.y, 0.0, 1.0))
	note("UV at the far end of the same face", far_uv)
	note("the same after the clamp", far_clamped)
	if far_clamped == clamped and far_target != target:
		note(
			"two clicks %s apart clamp to the same UV" % far_target.distance_to(target), far_clamped
		)


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
	if per_sample > 10.0:
		known(
			465,
			"one paint sample at the dock's largest radius costs %.1f ms" % per_sample,
			(
				"paint_at_uv() scans a square of (2r+1)^2 texels with get_pixel/set_pixel, and"
				+ " HFPaintSystem.handle_paint_input() calls it on every mouse-motion event"
				+ " while the button is held. At the top of the dock's 0.01..0.5 radius range"
				+ " that is a 257x257 pass over a 256x256 image on the main thread, per sample."
			)
		)
	var rebuild_started := Time.get_ticks_usec()
	for _i in 10:
		b.rebuild_preview()
	note(
		"ms per rebuild_preview, which paint_surface_at also runs per sample",
		float(Time.get_ticks_usec() - rebuild_started) / 10000.0
	)
