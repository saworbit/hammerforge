@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether a texture runs across a wall built out of more than one brush.
##
## Nobody builds a room out of one brush. A wall is three or four brushes in a
## row, a floor is a grid of them, and the thing a mapper notices first is
## whether the texture carries on across the seam or restarts at every brush
## edge. In every editor in this lineage it carries on, because a face's texture
## coordinates come from the face's position in the world.
##
## `FaceData._project_uvs_for_vertices()` is handed `local_verts`. This asks what
## that means at the seam: for brushes created side by side, for the same brush
## moved into place, for a brush duplicated along a row, and for the wall after
## it has been through a save.

const FaceData = preload("res://addons/hammerforge/face_data.gd")


func id() -> String:
	return "texture-continuity"


func summary() -> String:
	return "whether a texture runs across a wall built from several brushes"


func run() -> void:
	await _drawn_side_by_side()
	await _drawn_against_moved()
	await _which_way_the_checkbox_goes()
	await _a_duplicated_row()
	await _across_a_save()


## Where face `idx` of `brush` samples the texture, in UV units.
func _uv_rect(brush, idx: int) -> Rect2:
	var face = brush.faces[idx]
	var uvs: PackedVector2Array = face._project_uvs_for_vertices(face.local_verts)
	if uvs.is_empty():
		return Rect2()
	var lo := uvs[0]
	var hi := uvs[0]
	for uv in uvs:
		lo = lo.min(uv)
		hi = hi.max(uv)
	return Rect2(lo, hi - lo)


func _r(rect: Rect2) -> String:
	return "u[%.2f..%.2f]" % [rect.position.x, rect.position.x + rect.size.x]


## The face of a box that looks along -Z, so three boxes in a row along X are
## three panels of one wall and their U ranges should butt up against each other.
func _front_face(brush) -> int:
	var best := 0
	var best_dot := -INF
	for i in brush.faces.size():
		var d: float = brush.faces[i].normal.normalized().dot(Vector3.BACK)
		if d > best_dot:
			best_dot = d
			best = i
	return best


func _drawn_side_by_side() -> void:
	note("-- three 128-wide panels drawn in a row along X --")
	var root: Node3D = await fresh_root()
	var rects: Array[Rect2] = []
	for i in 3:
		var b = box(root, Vector3(128, 128, 16), Vector3(i * 128, 0, 0))
		await frame()
		var idx := _front_face(b)
		var rect := _uv_rect(b, idx)
		rects.append(rect)
		note("panel at x=%s, world u should start at %s" % [i * 128, i * 128 - 64], _r(rect))
	var all_same := true
	for r in rects:
		if not r.is_equal_approx(rects[0]):
			all_same = false
	if all_same:
		known(
			652,
			"three panels drawn side by side all sample the same texture coordinates",
			(
				(
					"every panel's front face maps to %s, so the texture restarts at each "
					+ "brush edge instead of running along the wall -- "
					+ "`_project_uvs_for_vertices()` reads `local_verts`, and a brush's "
					+ "local vertices do not know where the brush is"
				)
				% _r(rects[0])
			)
		)
	else:
		note("panels differ, checking they butt up")
		for i in range(1, rects.size()):
			var gap: float = rects[i].position.x - (rects[i - 1].position.x + rects[i - 1].size.x)
			if absf(gap) > 0.01:
				flag("a seam between panel %s and %s" % [i - 1, i], "%s UV units of gap" % gap)


## The same wall built the other way a mapper builds it: draw a panel, then
## move copies into place. `adjust_uvs_for_transform()` compensates `uv_offset`
## when a brush moves, so these two routes to the same wall can disagree.
func _drawn_against_moved() -> void:
	note("-- drawn at x=128 against drawn at 0 and moved to x=128 --")
	var root: Node3D = await fresh_root()
	var drawn = box(root, Vector3(128, 128, 16), Vector3(128, 0, 0))
	await frame()
	var moved = box(root, Vector3(128, 128, 16), Vector3.ZERO)
	await frame()
	root.nudge_brushes_by_id([moved.brush_id], Vector3(128, 0, 0))
	await frame()
	var a := _uv_rect(drawn, _front_face(drawn))
	var b := _uv_rect(moved, _front_face(moved))
	note("drawn at x=128", _r(a))
	note("drawn at 0, nudged +128", _r(b))
	note("both now at", "%s and %s" % [drawn.global_position, moved.global_position])
	if not a.is_equal_approx(b):
		known(
			653,
			"two brushes in the same place with the same size have different UVs",
			(
				(
					"drawing a panel where it goes gives %s; drawing it at the origin and "
					+ "moving it there gives %s. The texture on a wall then depends on how "
					+ "the mapper got the brush there, and no surface says which one happened"
				)
				% [_r(a), _r(b)]
			)
		)


## The dock's Texture Lock checkbox is on by default and says "Keep texture
## alignment while moving". Which of the two alignments it keeps is the question:
## the texture's place on the brush, or the texture's place in the world. A UV
## built from `local_verts` is already stuck to the brush, so the compensation
## the checkbox switches on is what unsticks it.
func _which_way_the_checkbox_goes() -> void:
	note("-- moving a brush with the checkbox on, and with it off --")
	var results := {}
	for locked in [true, false]:
		var root: Node3D = await fresh_root()
		root.texture_lock = locked
		var b = box(root, Vector3(128, 128, 16), Vector3.ZERO)
		await frame()
		var before := _uv_rect(b, _front_face(b))
		root.nudge_brushes_by_id([b.brush_id], Vector3(256, 0, 0))
		await frame()
		var after := _uv_rect(b, _front_face(b))
		var stayed_on_the_brush := before.is_equal_approx(after)
		results[locked] = stayed_on_the_brush
		note(
			(
				"texture_lock=%s: %s -> %s, texture %s"
				% [
					locked,
					_r(before),
					_r(after),
					"stayed on the brush" if stayed_on_the_brush else "slid across the brush"
				]
			)
		)
	if results.get(true) == false and results.get(false) == true:
		known(
			653,
			"Texture Lock on is the setting that lets the texture slide off the brush",
			(
				"with Texture Lock ticked, moving a brush 256 units changes the UVs of "
				+ "its own vertices, so the texture slides across the face; unticked, the "
				+ "texture stays put on the brush. The checkbox says 'Keep texture "
				+ "alignment while moving' and is on by default"
			)
		)


## Array/duplicate is the fastest way to build a repeating wall. What the copies
## sample decides whether the run looks like one surface.
func _a_duplicated_row() -> void:
	note("-- a 4-copy linear array along X --")
	var root: Node3D = await fresh_root()
	var src = box(root, Vector3(128, 128, 16), Vector3.ZERO)
	await frame()
	var result = root.create_duplicate_array(
		PackedStringArray([src.brush_id]), 4, Vector3(128, 0, 0)
	)
	await frame()
	note("array result", result)
	var brushes: Array = []
	_collect(root, root, brushes)
	note("brushes after the array", brushes.size())
	var seen := {}
	for b in brushes:
		var rect := _uv_rect(b, _front_face(b))
		seen[_r(rect)] = int(seen.get(_r(rect), 0)) + 1
		note("copy at %s" % b.global_position, _r(rect))
	if seen.size() == 1 and brushes.size() > 1:
		known(
			652,
			"every copy in an array samples the same texture coordinates",
			(
				(
					"%s brushes spread over %s units all map to %s, so an arrayed wall "
					+ "shows the same patch of texture repeated rather than a continuous run"
				)
				% [brushes.size(), 3 * 128, seen.keys()[0]]
			)
		)


## Whatever the UVs are, they must be the same after a save and load, or the
## wall re-textures itself the next time the level is opened.
func _across_a_save() -> void:
	note("-- the same wall through a .hflevel --")
	var root: Node3D = await fresh_root()
	var before: Array[String] = []
	for i in 3:
		var b = box(root, Vector3(128, 128, 16), Vector3(i * 128, 0, 0))
		await frame()
		before.append(_r(_uv_rect(b, _front_face(b))))
	var path := "user://vibe_texture_continuity.hflevel"
	root.hflevel_autosave_path = path
	root.save_hflevel(path)
	if not await HFVibe.settle_save(_tree, root):
		flag("the save never finished")
		return
	root.clear_brushes()
	await frame()
	root.load_hflevel(path)
	await frame()
	var brushes: Array = []
	_collect(root, root, brushes)
	brushes.sort_custom(func(x, y): return x.global_position.x < y.global_position.x)
	var after: Array[String] = []
	for b in brushes:
		after.append(_r(_uv_rect(b, _front_face(b))))
	note("before the save", before)
	note("after the load", after)
	if before != after:
		flag("a wall's UVs change across a .hflevel round trip", "%s -> %s" % [before, after])


func _collect(root: Node3D, node: Node, out: Array) -> void:
	for child in node.get_children():
		if root.is_brush_node(child):
			out.append(child)
		_collect(root, child, out)
