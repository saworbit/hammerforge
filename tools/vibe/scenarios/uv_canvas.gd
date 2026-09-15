@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The UV editor in the Paint tab, against the UVs a real face carries.
##
## `UVEditor` draws a face's `custom_uvs` by multiplying each one by the
## control's size, and turns a drag back into a UV by dividing by it. Both of
## those only make sense if a UV is a number between 0 and 1.
##
## A HammerForge UV is not. `_project_uvs_for_vertices()` reads world
## coordinates straight out of the face -- `Vector2(v.x, v.y)` for a planar Z
## face -- so a 64-unit box has UVs spanning 64. The question is where that puts
## the points the editor draws, whether any of them can be clicked, and what one
## drag does to the face.

const UVEditorScene = preload("res://addons/hammerforge/uv_editor.tscn")
const FaceDataType = preload("res://addons/hammerforge/face_data.gd")

## The size the Paint tab gives the editor. Anything of this order has the same
## answer; the ratio is what matters, not the exact number.
const CANVAS := Vector2(240, 240)


func id() -> String:
	return "uv-canvas"


func summary() -> String:
	return "where the UV editor draws a real face's UVs, and what dragging one does"


func run() -> void:
	await _where_the_points_land()
	await _what_a_drag_does()
	await _after_the_dock_reprojects()


func _editor() -> Control:
	var ed = UVEditorScene.instantiate()
	_tree.get_root().add_child(ed)
	ed.size = CANVAS
	await frame()
	return ed


## The UV bounding box of a face, in UV units.
func _uv_bounds(face: Variant) -> Rect2:
	var uvs: PackedVector2Array = face.custom_uvs
	if uvs.is_empty():
		return Rect2()
	var lo := uvs[0]
	var hi := uvs[0]
	for uv in uvs:
		lo = Vector2(minf(lo.x, uv.x), minf(lo.y, uv.y))
		hi = Vector2(maxf(hi.x, uv.x), maxf(hi.y, uv.y))
	return Rect2(lo, hi - lo)


## Every drawn point, and how many of them are inside the control.
func _where_the_points_land() -> void:
	var root: Node3D = await fresh_root("UVCanvas")
	var ed: Control = await _editor()
	for size in [Vector3(64, 64, 64), Vector3(8, 8, 8), Vector3(512, 512, 512)]:
		var b = box(root, size, Vector3(size.x * 4.0, 0, 0))
		await frame()
		var face = b.faces[0]
		ed.set_face(face)
		var bounds := _uv_bounds(face)
		note(
			"%s brush, face 0 UV bounds" % str(size.x),
			"position %s size %s" % [bounds.position, bounds.size]
		)
		var inside := 0
		var drawn: Array = []
		for uv in face.custom_uvs:
			var screen: Vector2 = ed._uv_to_screen(uv)
			drawn.append(screen)
			if (
				screen.x >= 0.0
				and screen.x <= CANVAS.x
				and screen.y >= 0.0
				and screen.y <= CANVAS.y
			):
				inside += 1
		note(
			"%s brush, points inside the %dx%d canvas" % [str(size.x), CANVAS.x, CANVAS.y],
			"%d of %d, first at %s" % [inside, face.custom_uvs.size(), drawn[0] if drawn else "-"]
		)
		if inside == 0 and not face.custom_uvs.is_empty():
			# Nothing drawn inside the control also means nothing clickable:
			# _find_nearest_uv_index() only accepts a hit within point_radius.
			var reachable := 0
			for x in range(0, int(CANVAS.x), 8):
				for y in range(0, int(CANVAS.y), 8):
					if ed._find_nearest_uv_index(Vector2(x, y)) >= 0:
						reachable += 1
			known(
				506,
				(
					"the UV editor draws a %s brush's face entirely outside its own canvas"
					% str(size.x)
				),
				(
					(
						"UVs span %.0f because a projected UV is a world coordinate,"
						% maxf(bounds.size.x, bounds.size.y)
					)
					+ " and _uv_to_screen() multiplies by the control size as though it were 0..1;"
					+ " %d of %d sampled positions can select a point" % [reachable, 900]
				)
			)
	ed.queue_free()


## One drag, and what the face keeps of its UV layout.
func _what_a_drag_does() -> void:
	var root: Node3D = await fresh_root("UVDrag")
	var ed: Control = await _editor()
	var b = box(root, Vector3(64, 64, 64))
	await frame()
	var face = b.faces[0]
	ed.set_face(face)
	var before: PackedVector2Array = face.custom_uvs.duplicate()
	var before_bounds := _uv_bounds(face)
	note("before the drag, UV bounds", "%s size %s" % [before_bounds.position, before_bounds.size])

	# The drag path: press picks an index, motion writes the clamped UV.
	# Pick index 0 directly, because nothing on the canvas can reach it.
	ed._drag_index = 0
	var motion := InputEventMouseMotion.new()
	motion.position = CANVAS * 0.5
	ed._gui_input(motion)
	ed._drag_index = -1

	var after_bounds := _uv_bounds(face)
	note("after one drag, UV bounds", "%s size %s" % [after_bounds.position, after_bounds.size])
	note("vertex 0 UV", "%s -> %s" % [before[0], face.custom_uvs[0]])
	var moved: float = before[0].distance_to(face.custom_uvs[0])
	if moved > maxf(before_bounds.size.x, before_bounds.size.y) * 0.25:
		known(
			506,
			"dragging a UV point moves it by the whole face rather than by the cursor",
			(
				(
					"the cursor was put at the middle of the canvas and the vertex moved %.1f UV units,"
					% moved
				)
				+ (
					" because _screen_to_uv() clamps to 0..1 and this face's UVs span %.0f"
					% maxf(before_bounds.size.x, before_bounds.size.y)
				)
			)
		)
	ed.queue_free()


## The dock's own UV controls clear `custom_uvs` and re-project, so the numbers
## the editor is showing may not be the ones the face renders with. Whether the
## editor is told.
func _after_the_dock_reprojects() -> void:
	var root: Node3D = await fresh_root("UVReproject")
	var ed: Control = await _editor()
	var b = box(root, Vector3(64, 64, 64))
	await frame()
	var face = b.faces[0]
	ed.set_face(face)
	var shown: PackedVector2Array = face.custom_uvs.duplicate()
	var brush_id := str(b.get_meta("brush_id", ""))
	root.set_face_uv_params(brush_id, 0, Vector2(4.0, 4.0), Vector2(0.5, 0.5), 0.0)
	await frame()
	var face_now = b.faces[0]
	note("UVs the editor was handed", shown[0] if shown.size() > 0 else "-")
	note(
		"UVs the face holds after Set UV Params",
		face_now.custom_uvs[0] if face_now.custom_uvs.size() > 0 else "-"
	)
	if face_now == face and shown.size() > 0 and face_now.custom_uvs.size() > 0:
		if not shown[0].is_equal_approx(face_now.custom_uvs[0]):
			note(
				"the editor holds the same FaceData, so a redraw shows the new UVs", "no stale copy"
			)
	ed.queue_free()
