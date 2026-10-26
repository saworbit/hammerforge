@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Align to Edge, Fit Repeats, Fit Strip, and the slide and turn keys, measured
## off the UVs each face actually shows.
##
## Each of these claims an exact result: after Align to Edge the texture's V is
## constant along the chosen edge and a repeat starts on it; after Fit Repeats the
## face shows exactly the repeats asked for; a turn key turns about the middle of
## the face, so the texture there stays put. So every check reads `shown_uvs()`
## (what the face draws) rather than the face's scale, offset and rotation, and
## puts each command on the faces a mapper reaches for it on: a wall turned with
## Texture Lock on, a sheared wall, a clipped diagonal, a tiny face, a face with a
## stretched texture.

const HFUVMultiType = preload("res://addons/hammerforge/hf_uv_multi.gd")
const FaceDataType = preload("res://addons/hammerforge/face_data.gd")


func id() -> String:
	return "texture-fit"


func summary() -> String:
	return "Align to Edge, Fit Repeats, Fit Strip, slide and turn, read off the shown UVs"


func expected_issues() -> Array[int]:
	return [1993]


func run() -> void:
	await _align_to_edge()
	await _fit()
	await _turn_and_slide()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func _facing(brush: Node, normal: Vector3) -> int:
	var best := -1
	var best_dot := 0.9
	for i in brush.faces.size():
		var d: float = brush.faces[i].normal_through(brush.global_transform.basis).dot(normal)
		if d > best_dot:
			best_dot = d
			best = i
	return best


func _pick(root: Node3D, brush: Node, face_idx: int) -> void:
	root.face_selection = {_bid(brush): [face_idx]}


func _middle(face) -> Vector3:
	var m := Vector3.ZERO
	for c in face.local_verts:
		m += c
	return m / float(face.local_verts.size())


func _uv_at(face, local_point: Vector3) -> Vector2:
	return face.shown_uvs_at(PackedVector3Array([local_point]))[0]


## The face's shown UV bounds.
func _bounds(face) -> Rect2:
	var uvs: PackedVector2Array = face.shown_uvs()
	var rect := Rect2(uvs[0], Vector2.ZERO)
	for uv in uvs:
		rect = rect.expand(uv)
	return rect


# ---------------------------------------------------------------------------
# Align to Edge
# ---------------------------------------------------------------------------


## Build one face to align, by `kind`. Returns [root, brush, face_idx, label].
func _build(kind: String) -> Array:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(4, 2, 1), Vector3(0, 1, 0))
	var bid := _bid(b)
	match kind:
		"box front":
			pass
		"wall turned 23 on Y with Texture Lock":
			root.texture_lock = true
			root.rotate_managed_nodes([bid], [], 1, 23.0, b.global_position)
		"wall sheared with Texture Lock":
			root.texture_lock = true
			root.shear_managed_nodes([bid], [], 0, 1, 0.4, 0.0)
		"ramp sheared Y over X with Texture Lock":
			root.texture_lock = true
			root.shear_managed_nodes([bid], [], 1, 0, 0.5, -2.0)
		"wall sheared without Texture Lock":
			root.texture_lock = false
			root.shear_managed_nodes([bid], [], 0, 1, 0.4, 0.0)
		"stretched texture (2, 0.5) turned 0.3":
			var f := _facing(b, Vector3.BACK)
			root.set_face_uv_params(bid, f, Vector2(2, 0.5), Vector2(0.1, 0.2), 0.3)
		"tiny 0.1 m face":
			var tiny = box(root, Vector3(0.1, 0.1, 1), Vector3(3, 0.05, 0))
			b = tiny
		"clipped diagonal wall":
			var n := Vector3(1, 0.3, 1).normalized()
			root.clip_brushes_keeping([bid], Plane(n, n.dot(Vector3(1, 1, 0))), 2)
			b = root.draft_brushes_node.get_child(0)
			var cap := _facing(b, n)
			return [root, b, cap, kind]
	var brush = root.find_brush_by_id(_bid(b))
	return [root, brush, _facing(brush, Vector3.BACK), kind]


func _align_to_edge() -> void:
	note("-- Align to Edge --")
	var kinds := [
		"box front",
		"wall turned 23 on Y with Texture Lock",
		"wall sheared with Texture Lock",
		"ramp sheared Y over X with Texture Lock",
		"wall sheared without Texture Lock",
		"stretched texture (2, 0.5) turned 0.3",
		"tiny 0.1 m face",
		"clipped diagonal wall",
	]
	for kind in kinds:
		var built: Array = await _build(kind)
		var root: Node3D = built[0]
		var brush = built[1]
		var fi: int = built[2]
		if fi < 0:
			note(kind, "no front face found")
			await drop_root(root)
			continue
		var face = brush.faces[fi]
		var had_layout: bool = face.has_uv_layout()
		_pick(root, brush, fi)
		var bad_edges: Array = []
		var count: int = face.local_verts.size()
		for step in count:
			var turned: int = root.align_selected_faces_to_edge()
			face = root.find_brush_by_id(_bid(brush)).faces[fi]
			var edge: int = root.brush_system._aligned_edges.get(face.get_instance_id(), -1)
			if turned != 1 or edge < 0:
				bad_edges.append("step %d: turned %d" % [step, turned])
				continue
			var uvs: PackedVector2Array = face.shown_uvs()
			var a: Vector2 = uvs[edge]
			var b: Vector2 = uvs[(edge + 1) % count]
			var mid := _uv_at(face, _middle(face))
			var problems: Array = []
			if absf(a.y - b.y) > 0.001:
				problems.append("V runs %.4f -> %.4f along the edge" % [a.y, b.y])
			if absf(a.y - roundf(a.y)) > 0.001:
				problems.append("V at the edge is %.4f, not a whole repeat" % a.y)
			if mid.y >= a.y:
				problems.append("the texture's top faces away from the middle")
			if not problems.is_empty():
				bad_edges.append("edge %d: %s" % [edge, ", ".join(problems)])
		note(
			"Align to Edge round every edge of a %s" % kind,
			(
				"%d edges, custom layout %s, %s"
				% [count, had_layout, "all aligned" if bad_edges.is_empty() else str(bad_edges)]
			)
		)
		if not bad_edges.is_empty():
			known(
				1993,
				"Align to Edge does not lay the texture along the edge of a %s" % kind,
				(
					"%s (the face %s a hand layout)"
					% [str(bad_edges).substr(0, 500), "has" if had_layout else "has no"]
				)
			)
		await drop_root(root)


# ---------------------------------------------------------------------------
# Fit Repeats and Fit Strip
# ---------------------------------------------------------------------------


func _fit() -> void:
	note("-- Fit Repeats and Fit Strip --")
	for kind in [
		"box front",
		"wall sheared with Texture Lock",
		"stretched texture (2, 0.5) turned 0.3",
		"tiny 0.1 m face"
	]:
		var built: Array = await _build(kind)
		var root: Node3D = built[0]
		var brush = built[1]
		var fi: int = built[2]
		_pick(root, brush, fi)
		var fitted: int = root.fit_selected_faces_repeats(3, 2)
		var face = root.find_brush_by_id(_bid(brush)).faces[fi]
		var r := _bounds(face)
		note(
			"Fit Repeats 3 x 2 on a %s" % kind,
			(
				"fitted %d, shows U %.4f..%.4f, V %.4f..%.4f"
				% [fitted, r.position.x, r.end.x, r.position.y, r.end.y]
			)
		)
		if (
			fitted != 1
			or r.position.distance_to(Vector2.ZERO) > 0.001
			or r.end.distance_to(Vector2(3, 2)) > 0.001
		):
			flag("Fit Repeats 3 x 2 on a %s does not show 3 x 2" % kind, str(r))
		var strip: int = root.fit_selected_faces_strip(2, 5)
		face = root.find_brush_by_id(_bid(brush)).faces[fi]
		r = _bounds(face)
		note(
			"Fit Strip 2 of 5 on a %s" % kind,
			(
				"fitted %d, shows U %.4f..%.4f, V %.4f..%.4f"
				% [strip, r.position.x, r.end.x, r.position.y, r.end.y]
			)
		)
		if (
			strip != 1
			or r.position.distance_to(Vector2(0, 0.2)) > 0.001
			or r.end.distance_to(Vector2(1, 0.4)) > 0.001
		):
			flag("Fit Strip 2 of 5 on a %s does not show the second fifth" % kind, str(r))
		await drop_root(root)
	# Out of range: nothing should change and nothing should be counted.
	var root2: Node3D = await fresh_root()
	var b2 = box(root2, Vector3(4, 2, 1), Vector3(0, 1, 0))
	var f2 := _facing(b2, Vector3.BACK)
	_pick(root2, b2, f2)
	var before_dict: Dictionary = b2.faces[f2].to_dict()
	var odd := {
		"repeats 0 x 0": func(): return root2.fit_selected_faces_repeats(0, 0),
		"repeats -2 x 1": func(): return root2.fit_selected_faces_repeats(-2, 1),
		"strip 0 of 4": func(): return root2.fit_selected_faces_strip(0, 4),
		"strip 5 of 4": func(): return root2.fit_selected_faces_strip(5, 4),
		"strip 1 of 0": func(): return root2.fit_selected_faces_strip(1, 0),
	}
	for label in odd:
		var n: int = (odd[label] as Callable).call()
		var r := _bounds(root2.find_brush_by_id(_bid(b2)).faces[f2])
		note("Fit %s" % label, "fitted %d, shows %s" % [n, r])
	var after_dict: Dictionary = root2.find_brush_by_id(_bid(b2)).faces[f2].to_dict()
	# Not a finding: a count of 0 or less on one axis means "keep the aspect", so
	# -2 x 1 is 1 down with U following, the one of these that changes the face.
	note(
		"the out-of-range fits changed the face",
		HFVibe.canonical(before_dict) != HFVibe.canonical(after_dict)
	)
	await drop_root(root2)


# ---------------------------------------------------------------------------
# Turn and slide keys
# ---------------------------------------------------------------------------


func _turn_and_slide() -> void:
	note("-- turn and slide keys --")
	for kind in [
		"box front",
		"wall turned 23 on Y with Texture Lock",
		"wall sheared with Texture Lock",
		"ramp sheared Y over X with Texture Lock",
	]:
		var built: Array = await _build(kind)
		var root: Node3D = built[0]
		var brush = built[1]
		var fi: int = built[2]
		_pick(root, brush, fi)
		var face = brush.faces[fi]
		var middle := _middle(face)
		var at_middle := _uv_at(face, middle)
		var records := HFUVMultiType.picked(root)
		var turn: Dictionary = HFUVMultiType.turn_changes(records, 15.0)
		root.set_uv_params_on_faces(turn["changes"])
		face = root.find_brush_by_id(_bid(brush)).faces[fi]
		var after := _uv_at(face, middle)
		note(
			"turn 15 degrees on a %s" % kind,
			"the UV at the middle %s -> %s, layout %s" % [at_middle, after, face.has_uv_layout()]
		)
		if after.distance_to(at_middle) > 0.001:
			known(
				1993,
				"the turn key on a %s does not turn about the middle of the face" % kind,
				(
					"the texture at the middle moved %.4f UV (%s -> %s)"
					% [after.distance_to(at_middle), at_middle, after]
				)
			)
		# Slide 0.5 m to screen right, seen square on to the face.
		var normal: Vector3 = face.normal_through(brush.global_transform.basis).normalized()
		var up := Vector3.UP
		var right := up.cross(normal).normalized()
		var p_world: Vector3 = brush.global_transform * middle
		var before_uv := _uv_at(face, middle)
		records = HFUVMultiType.picked(root)
		var slide: Dictionary = HFUVMultiType.slide_changes(records, right, up, Vector2(1, 0), 0.5)
		root.set_uv_params_on_faces(slide["changes"])
		face = root.find_brush_by_id(_bid(brush)).faces[fi]
		# What was at the middle should now be 0.5 m along `right` on the face.
		var on_face := (right - normal * right.dot(normal)).normalized()
		var moved_local: Vector3 = (
			brush.global_transform.affine_inverse() * (p_world + on_face * 0.5)
		)
		var moved_uv := _uv_at(face, moved_local)
		note(
			"slide 0.5 m right on a %s" % kind,
			(
				"the texture from the middle is now %.4f UV from 0.5 m along"
				% moved_uv.distance_to(before_uv)
			)
		)
		if moved_uv.distance_to(before_uv) > 0.001:
			known(
				1993,
				"the slide key on a %s does not move the texture 0.5 m the way it points" % kind,
				"%s was at the middle, 0.5 m right now shows %s" % [before_uv, moved_uv]
			)
		await drop_root(root)
