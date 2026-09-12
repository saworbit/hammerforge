@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Vertex and edge editing: moving vertices, splitting edges, merging vertices
## and clipping back to convex.
##
## This is the one part of the editor where the user hands geometry directly to
## the brush, with nothing between the input and the face data. Every other
## operation builds its faces from parameters that were checked on the way in.
## Here a delta goes straight onto a vertex position and the only thing standing
## between that and the bake is `validate_convexity()`, so the questions are
## what that check actually rejects, and what the level looks like after an
## operation it let through.


func id() -> String:
	return "vertex"


func summary() -> String:
	return "vertex moves, edge splits, merges and the convexity check that gates them"


func run() -> void:
	await _a_move_that_bends_a_face()
	await _a_move_that_dents_the_solid()
	await _a_non_finite_move()
	await _merging_every_vertex_of_a_box()
	await _splitting_an_edge()
	await _clip_to_convex_on_a_healthy_brush()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## Volume of a brush's own faces, by the divergence theorem. Independent of
## anything the brush or the vertex system reports about itself.
func _volume(brush: Node3D) -> float:
	var total := 0.0
	for face in brush.faces:
		if face == null:
			continue
		var tri: Dictionary = face.triangulate()
		var verts: PackedVector3Array = tri["verts"]
		var i := 0
		while i + 2 < verts.size():
			total += verts[i].dot(verts[i + 1].cross(verts[i + 2])) / 6.0
			i += 3
	return absf(total)


## The largest distance any of a face's own vertices sits off the plane through
## its first three. A brush face is a plane by definition -- the bake, the .map
## export and every clip treat it as one -- so anything non-zero here is a face
## that no longer means what its consumers assume.
func _worst_non_planarity(brush: Node3D) -> float:
	var worst := 0.0
	for face in brush.faces:
		if face == null or face.local_verts.size() < 4:
			continue
		var fv: PackedVector3Array = face.local_verts
		var n: Vector3 = (fv[1] - fv[0]).cross(fv[2] - fv[0])
		if n.length() < 0.0001:
			continue
		n = n.normalized()
		for v in fv:
			worst = maxf(worst, absf(n.dot(v - fv[0])))
	return worst


func _any_non_finite(brush: Node3D) -> bool:
	for face in brush.faces:
		if face == null:
			continue
		for v in face.local_verts:
			if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
				return true
	return false


## Dragging one corner of a box bends the faces that meet at it, because a quad
## with one corner moved is no longer a plane. Whichever way it goes, the brush
## the mapper is left with has to be a convex solid made of planes: pulled away
## from the solid the bent faces are cut into triangles and the move stands,
## pushed into it there is no split that stays convex and the move goes back.
func _a_move_that_bends_a_face() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	var vs = root.vertex_system
	var before := _volume(b)
	var faces_before: int = b.faces.size()

	vs.select_vertex(_bid(b), 0)
	var ok: bool = vs.move_vertices(Vector3(0, -256, 0))
	var after := _volume(b)
	var bow := _worst_non_planarity(b)
	note(
		"pulling one corner 256 away from the solid",
		(
			"accepted: %s, volume %.0f -> %.0f, faces %d -> %d"
			% [ok, before, after, faces_before, b.faces.size()]
		)
	)
	note("worst face non-planarity after the move", "%.2f units" % bow)
	if bow > 0.02:
		flag(
			"a vertex move left a face bent",
			(
				"one corner of a 64 box pulled 256 units: accepted %s, worst face sits %.1f units off its own plane"
				% [ok, bow]
			)
		)
	elif ok and b.faces.size() <= faces_before:
		flag(
			"a bent face was accepted without being split",
			"faces %d -> %d" % [faces_before, b.faces.size()]
		)
	elif ok:
		note(
			"split and kept", "faces %d -> %d, volume %.0f" % [faces_before, b.faces.size(), after]
		)
	elif absf(after - before) > 0.5:
		flag(
			"a refused vertex move did not restore the brush",
			"volume %.0f before, %.0f after the refusal" % [before, after]
		)
	else:
		note("refused and restored", "volume back to %.0f" % after)


## The other direction. A corner pushed into the solid dents it, and no
## triangulation of the bent faces gets that back to convex.
func _a_move_that_dents_the_solid() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	var vs = root.vertex_system
	var before := _volume(b)
	var faces_before: int = b.faces.size()

	# Vertex 0 of a box is the (+x, -y, +z) corner, so this heads for the middle.
	vs.select_vertex(_bid(b), 0)
	var ok: bool = vs.move_vertices(Vector3(-16, 16, -16))
	var after := _volume(b)
	note(
		"pushing one corner 16 into the solid",
		"accepted: %s, volume %.0f -> %.0f" % [ok, before, after]
	)
	if ok:
		flag("a dent was accepted", "volume %.0f -> %.0f" % [before, after])
	elif absf(after - before) > 0.5 or b.faces.size() != faces_before:
		flag(
			"a refused vertex move did not restore the brush",
			"volume %.0f -> %.0f, faces %d -> %d" % [before, after, faces_before, b.faces.size()]
		)
	else:
		note("refused and restored", "volume back to %.0f, faces %d" % [after, faces_before])


## The recurring seam. Every comparison against NaN is false, so a check written
## as "reject when the vertex is in front of the plane" cannot reject one.
func _a_non_finite_move() -> void:
	for delta in [
		Vector3(NAN, 0, 0),
		Vector3(0, INF, 0),
		Vector3(-INF, NAN, INF),
	]:
		var root: Node3D = await fresh_root()
		var b := box(root, Vector3(64, 64, 64))
		var vs = root.vertex_system
		vs.select_vertex(_bid(b), 0)
		var ok: bool = vs.move_vertices(delta)
		var poisoned := _any_non_finite(b)
		note("move by %s" % delta, "accepted: %s, non-finite verts: %s" % [ok, poisoned])
		if poisoned:
			known(
				365,
				"a non-finite vertex move is accepted and reaches the face data",
				"delta %s, move_vertices returned %s, brush volume %s" % [delta, ok, _volume(b)]
			)


## Selecting every vertex of a box and merging collapses the whole solid onto
## its centre. Every face degenerates. What is left in the level afterwards is
## the question.
func _merging_every_vertex_of_a_box() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	var vs = root.vertex_system
	var verts: PackedVector3Array = vs.get_brush_vertices(b)
	var all := PackedInt32Array()
	for i in range(verts.size()):
		all.append(i)

	var before := _volume(b)
	var ok: bool = vs.merge_vertices(_bid(b), all)
	await frame()
	var faces_left: int = b.faces.size() if is_instance_valid(b) else -1
	var after: float = _volume(b) if is_instance_valid(b) else 0.0
	note(
		"merging all %d vertices of a box" % verts.size(),
		"accepted: %s, faces %d, volume %.0f -> %.0f" % [ok, faces_left, before, after]
	)
	if ok and faces_left == 0:
		known(
			366,
			"merging every vertex leaves a live brush with no faces",
			(
				"%d brushes still in the level, the collapsed one has 0 faces and 0 volume"
				% root.brush_system.get_live_brush_count()
			)
		)
	for problem in HFVibe.check_invariants(root):
		flag("after merging every vertex: %s" % problem)


## A split puts a vertex on the midpoint of an edge. The solid should be the
## same shape with one more vertex on it -- same volume, still convex.
func _splitting_an_edge() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	var vs = root.vertex_system
	var before := _volume(b)
	var before_count: int = vs.get_brush_vertices(b).size()

	var edges: Array = vs.get_brush_edges(b)
	if edges.is_empty():
		note("no edges reported for a box", "skipping the split")
		return
	var edge: Array = (
		edges[0] if edges[0] is Array else [edges[0].get("a", 0), edges[0].get("b", 1)]
	)
	var ok: bool = vs.split_edge(_bid(b), edge)
	var after := _volume(b)
	var after_count: int = vs.get_brush_vertices(b).size()
	note(
		"splitting one edge of a box",
		(
			"accepted: %s, vertices %d -> %d, volume %.0f -> %.0f"
			% [ok, before_count, after_count, before, after]
		)
	)
	if ok and absf(after - before) > 0.5:
		flag(
			"splitting an edge changed the brush's volume",
			"%.2f -> %.2f, a midpoint lies on the surface and should move nothing" % [before, after]
		)
	note("worst face non-planarity after the split", "%.4f units" % _worst_non_planarity(b))
	# A midpoint inserted at position 0 or 1 lands between the first three
	# vertices, which is exactly the triple `_compute_normal()` measures. Three
	# collinear points give a zero cross, and the fallback is `Vector3.UP`.
	var collinear := 0
	for face in b.faces:
		if face == null or face.local_verts.size() < 3:
			continue
		var fv: PackedVector3Array = face.local_verts
		var cross: Vector3 = (fv[2] - fv[0]).normalized().cross((fv[1] - fv[0]).normalized())
		if cross.length() <= 0.0001:
			collinear += 1
			known(
				367,
				"split_edge leaves a face whose first three vertices are collinear",
				(
					"_compute_normal() measures only local_verts[0..2], gets a zero cross and falls back to Vector3.UP -- this face now reports normal %s"
					% face.normal
				)
			)
	note("faces with a collinear opening triple after one split", collinear)
	if ok and not vs.validate_convexity(b):
		known(
			367,
			"the brush's own validate_convexity() rejects a brush right after split_edge()",
			(
				"the midpoint lies exactly on the hull, so the shape did not change -- volume %.0f -> %.0f -- yet the check that gates every later vertex move now says no"
				% [before, after]
			)
		)
	if ok:
		var inward := HFVibe.inward_face_count(b)
		if inward > 0:
			flag("edge split left %d inward-facing faces" % inward)


## `clip_to_convex` is the repair tool. On a brush that is already convex it
## should be a no-op and say so.
func _clip_to_convex_on_a_healthy_brush() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	var before := _volume(b)
	var changed: bool = root.clip_brush_to_convex(_bid(b))
	var after := _volume(b)
	note(
		"clip_to_convex on an untouched box",
		"changed: %s, volume %.0f -> %.0f" % [changed, before, after]
	)
	if changed:
		flag("clip_to_convex reports it modified a brush that was already convex")
	if absf(after - before) > 0.5:
		flag("clip_to_convex changed a convex brush", "%.0f -> %.0f" % [before, after])
