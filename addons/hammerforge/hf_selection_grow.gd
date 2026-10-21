@tool
extends RefCounted

## What Grow Selection and Shrink Selection reach (#1433): the faces that share
## an edge with the selected ones, and the brushes whose solids touch the
## selected ones.
##
## Two faces are neighbours when an edge of one lies along an edge of the other
## for some length, in world space. That is one test for two faces of one brush,
## which share their corners, and for faces of two brushes laid side by side,
## whose edges need only overlap. Faces that meet at a single corner are not
## neighbours, so a grow spreads along rows and columns, not diagonals.
##
## Two brushes touch when no plane separates them. Their world boxes are the
## cheap first pass, the one Merge makes, but a box is only an upper bound: a
## brush turned 45 degrees fills half its box. So a pair whose boxes meet goes
## on to the separating axis test over both brushes' face normals and the cross
## products of their edge directions, which for two convex solids says exactly
## whether a plane fits between them. A brush is convex by construction, so this
## is the whole answer, not an estimate.
##
## A brush that cannot be seen is never reached: hiding geometry to work on what
## is behind it is what a visgroup is for, as the Selection Filters say.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
@warning_ignore_restore("shadowed_global_identifier")

## How far apart two edges or two solids may be and still meet, in metres. The
## distance Merge allows two brushes it calls touching.
const CONTACT_EPSILON := 0.001
## Two world normals at least this close (under a degree apart) face one way.
const SAME_PLANE_DOT := 0.9999
## The widest Max angle, which lets every neighbour through.
const DEFAULT_MAX_ANGLE := 180.0
## Two directions closer than this are one axis for the separating test.
const _PARALLEL_DOT := 0.999999


## Every brush a grow may add: one the level owns and the mapper can see. The
## brush being drawn is not one yet.
static func reachable_brushes(root: Node) -> Array:
	var out: Array = []
	if root == null or not root.has_method("_iter_pick_nodes"):
		return out
	var preview = root.get("preview_brush")
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush) or node == preview:
			continue
		if not root.is_brush_node(node) or not (node as DraftBrush).is_visible_in_tree():
			continue
		out.append(node)
	return out


# ---------------------------------------------------------------------------
# Faces
# ---------------------------------------------------------------------------


## Walk the edges of the selected faces once. Returns `added`, the faces Grow
## adds, keyed as `face_selection` is with sorted indices, and `border`, the
## selected faces Shrink drops, as `{key: {index: true}}`.
##
## A neighbour counts when it is not selected, sits on a reachable brush and
## passes the options against the face it borders: with `same_plane` it lies in
## that face's plane, facing the same way, and otherwise its normal is within
## `max_angle` degrees of that face's. A selected face is on the border when it
## has such a neighbour, so Shrink takes back the ring a Grow just added.
static func walk_faces(
	root: Node, face_selection: Dictionary, same_plane: bool, max_angle: float
) -> Dictionary:
	var added: Dictionary = {}
	var border: Dictionary = {}
	var result := {"added": added, "border": border}
	if root == null:
		return result
	var cache: Dictionary = {}
	var candidates := reachable_brushes(root)
	var picked: Dictionary = {}
	for key in face_selection:
		picked[str(key)] = {}
		for index in face_selection[key]:
			picked[str(key)][int(index)] = true
	var found: Dictionary = {}
	for key in face_selection:
		var brush: DraftBrush = root._find_brush_by_key(str(key))
		if brush == null:
			continue
		var faces: Array = _world_faces(brush, cache)
		# A face's neighbours are near its brush, so the level is swept once a
		# brush rather than once a face.
		var nearby: Array = []
		for other in candidates:
			if _bounds_of(other, cache).intersects(_bounds_of(brush, cache)):
				nearby.append(other)
		for index in face_selection[key]:
			var face_index := int(index)
			if face_index < 0 or face_index >= faces.size() or faces[face_index] == null:
				continue
			var face: Dictionary = faces[face_index]
			var reach: AABB = face["bounds"]
			for other in nearby:
				if not _bounds_of(other, cache).intersects(reach):
					continue
				var other_faces: Array = _world_faces(other, cache)
				var other_key := str(HFBrushSystem.face_key(other))
				for j in other_faces.size():
					var neighbour = other_faces[j]
					if neighbour == null or (other == brush and j == face_index):
						continue
					if (picked.get(other_key, {}) as Dictionary).has(j):
						continue
					if not (neighbour["bounds"] as AABB).intersects(reach):
						continue
					if not _passes(face, neighbour, same_plane, max_angle):
						continue
					if not share_an_edge(face["corners"], neighbour["corners"]):
						continue
					if not found.has(other_key):
						found[other_key] = {}
					found[other_key][j] = true
					if not border.has(str(key)):
						border[str(key)] = {}
					border[str(key)][face_index] = true
	for other_key in found:
		var indices: Array = (found[other_key] as Dictionary).keys()
		indices.sort()
		added[other_key] = indices
	return result


## `face_selection` with `added` put in after what it held, so the face picked
## first, the one the UV Editor shows, stays first.
static func with_faces(face_selection: Dictionary, added: Dictionary) -> Dictionary:
	var out: Dictionary = face_selection.duplicate(true)
	for key in added:
		var indices: Array = (out.get(key, []) as Array).duplicate()
		for index in added[key]:
			if not indices.has(index):
				indices.append(index)
		out[key] = indices
	return out


## `face_selection` with every face `border` names taken out, and a brush left
## with none taken out too.
static func without_faces(face_selection: Dictionary, border: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in face_selection:
		var dropped: Dictionary = border.get(str(key), {})
		var kept: Array = []
		for index in face_selection[key]:
			if not dropped.has(int(index)):
				kept.append(index)
		if not kept.is_empty():
			out[key] = kept
	return out


## How many faces a `{key: indices}` dictionary holds.
static func face_count(faces: Dictionary) -> int:
	var total := 0
	for key in faces:
		total += (faces[key] as Array).size()
	return total


## Whether two flat polygons, given by their world corners, have an edge in
## common: one edge of each on one line, overlapping for more than a contact.
static func share_an_edge(first: PackedVector3Array, second: PackedVector3Array) -> bool:
	var n := first.size()
	var m := second.size()
	for i in n:
		var a: Vector3 = first[i]
		var b: Vector3 = first[(i + 1) % n]
		for k in m:
			if edges_overlap(a, b, second[k], second[(k + 1) % m]):
				return true
	return false


## Whether segment `q0`-`q1` lies along segment `p0`-`p1` and the two overlap
## by more than `CONTACT_EPSILON`. Segments that only meet end to end, or cross,
## do not.
static func edges_overlap(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3) -> bool:
	var run := p1 - p0
	var length := run.length()
	if length <= CONTACT_EPSILON:
		return false
	var along := run / length
	var t0 := (q0 - p0).dot(along)
	var t1 := (q1 - p0).dot(along)
	if ((q0 - p0) - along * t0).length() > CONTACT_EPSILON:
		return false
	if ((q1 - p0) - along * t1).length() > CONTACT_EPSILON:
		return false
	return minf(length, maxf(t0, t1)) - maxf(0.0, minf(t0, t1)) > CONTACT_EPSILON


static func _passes(
	face: Dictionary, neighbour: Dictionary, same_plane: bool, max_angle: float
) -> bool:
	var normal: Vector3 = face["normal"]
	var dot := clampf(normal.dot(neighbour["normal"]), -1.0, 1.0)
	if same_plane:
		if dot < SAME_PLANE_DOT:
			return false
		var on_plane: Vector3 = (face["corners"] as PackedVector3Array)[0]
		for corner in neighbour["corners"]:
			if absf(normal.dot(corner - on_plane)) > CONTACT_EPSILON:
				return false
		return true
	# A thousandth of a degree of slack, so a turn of exactly Max angle is not
	# turned away by rounding in the normals.
	return rad_to_deg(acos(dot)) <= max_angle + 0.001


## A brush's faces in world space, by face index: each one's corners, normal
## and bounds grown by the contact distance, or null for a face too small to
## have an edge. Built once a brush per walk.
static func _world_faces(brush: DraftBrush, cache: Dictionary) -> Array:
	if cache.has(brush):
		return cache[brush]["faces"]
	var xform := brush.global_transform
	var faces: Array = []
	var bounds := AABB()
	var seeded := false
	for face in brush.get_faces():
		var data := face as FaceData
		if data == null or data.local_verts.size() < 3:
			faces.append(null)
			continue
		var corners := PackedVector3Array()
		var face_bounds := AABB(xform * data.local_verts[0], Vector3.ZERO)
		for vertex in data.local_verts:
			var point: Vector3 = xform * vertex
			corners.append(point)
			face_bounds = face_bounds.expand(point)
		bounds = bounds.merge(face_bounds) if seeded else face_bounds
		seeded = true
		(
			faces
			. append(
				{
					"corners": corners,
					"normal": data.normal_through(xform.basis),
					"bounds": face_bounds.grow(CONTACT_EPSILON),
				}
			)
		)
	cache[brush] = {"faces": faces, "bounds": bounds.grow(CONTACT_EPSILON)}
	return faces


static func _bounds_of(brush: DraftBrush, cache: Dictionary) -> AABB:
	_world_faces(brush, cache)
	return cache[brush]["bounds"]


# ---------------------------------------------------------------------------
# Brushes
# ---------------------------------------------------------------------------


## Walk the selected brushes once. Returns `added`, the reachable brushes not
## in `selection` whose solids touch or overlap a selected brush's, which Grow
## adds, and `border`, the selected brushes touching one of those, which Shrink
## drops. Both in the order the level holds them. Anything in `selection` that
## is not a brush is no part of either.
static func walk_brushes(root: Node, selection: Array) -> Dictionary:
	var added: Array = []
	var border: Array = []
	var result := {"added": added, "border": border}
	if root == null:
		return result
	var sources: Array = []
	for node in selection:
		if is_instance_valid(node) and node is DraftBrush and root.is_brush_node(node):
			sources.append(node)
	if sources.is_empty():
		return result
	var hulls: Dictionary = {}
	var touched: Dictionary = {}
	for other in reachable_brushes(root):
		if selection.has(other):
			continue
		var other_hull := _hull(other, hulls)
		for brush in sources:
			var hull := _hull(brush, hulls)
			if not (hull["bounds"] as AABB).intersects(other_hull["bounds"]):
				continue
			if not hulls_touch(hull, other_hull):
				continue
			if not added.has(other):
				added.append(other)
			touched[brush] = true
	for brush in sources:
		if touched.has(brush):
			border.append(brush)
	return result


## Whether two brushes' solids touch or overlap.
static func brushes_touch(first: DraftBrush, second: DraftBrush) -> bool:
	var a := hull_of(first)
	var b := hull_of(second)
	return (a["bounds"] as AABB).intersects(b["bounds"]) and hulls_touch(a, b)


## A brush as the separating test reads it: `points`, its world corners,
## `normals`, its face normals, `edges`, its edge directions, and `bounds`, its
## world box grown by the contact distance.
static func hull_of(brush: DraftBrush) -> Dictionary:
	return _hull(brush, {})


## The separating axis test for two convex solids. Each is `points`, its world
## corners, `normals`, its face normals, and `edges`, its edge directions. When
## no axis among the normals of both and the cross products of an edge of each
## puts a gap of more than `CONTACT_EPSILON` between them, they touch or overlap.
## The cross products catch two solids that pass each other edge to edge, which
## no face normal separates.
static func hulls_touch(first: Dictionary, second: Dictionary) -> bool:
	var a_points: PackedVector3Array = first["points"]
	var b_points: PackedVector3Array = second["points"]
	if a_points.is_empty() or b_points.is_empty():
		return false
	var axes: Array = (first["normals"] as Array) + (second["normals"] as Array)
	for a_edge in first["edges"]:
		for b_edge in second["edges"]:
			var axis: Vector3 = (a_edge as Vector3).cross(b_edge)
			if axis.length_squared() > 0.000001:
				axes.append(axis.normalized())
	for axis in axes:
		if _gap_along(axis, a_points, b_points) > CONTACT_EPSILON:
			return false
	return true


static func _gap_along(
	axis: Vector3, a_points: PackedVector3Array, b_points: PackedVector3Array
) -> float:
	var a_min := INF
	var a_max := -INF
	for point in a_points:
		var d := axis.dot(point)
		a_min = minf(a_min, d)
		a_max = maxf(a_max, d)
	var b_min := INF
	var b_max := -INF
	for point in b_points:
		var d := axis.dot(point)
		b_min = minf(b_min, d)
		b_max = maxf(b_max, d)
	return maxf(b_min - a_max, a_min - b_max)


## A brush as the separating test reads it, with its world box grown by the
## contact distance for the first pass. Built once a brush per walk.
static func _hull(brush: DraftBrush, cache: Dictionary) -> Dictionary:
	if cache.has(brush):
		return cache[brush]
	var xform := brush.global_transform
	var points := PackedVector3Array()
	var normals: Array = []
	var edges: Array = []
	for face in brush.get_faces():
		var data := face as FaceData
		if data == null or data.local_verts.is_empty():
			continue
		var corners := PackedVector3Array()
		for vertex in data.local_verts:
			corners.append(xform * vertex)
		points.append_array(corners)
		_add_direction(normals, data.normal_through(xform.basis))
		for i in corners.size():
			_add_direction(edges, corners[(i + 1) % corners.size()] - corners[i])
	var bounds := AABB()
	if not points.is_empty():
		bounds = AABB(points[0], Vector3.ZERO)
		for point in points:
			bounds = bounds.expand(point)
	var hull := {
		"points": points,
		"normals": normals,
		"edges": edges,
		"bounds": bounds.grow(CONTACT_EPSILON),
	}
	cache[brush] = hull
	return hull


## Add a direction to a list of axes, unless it is too short to have one or a
## direction already there runs along it either way.
static func _add_direction(axes: Array, direction: Vector3) -> void:
	if direction.length_squared() < 0.0000000001:
		return
	var unit := direction.normalized()
	for axis in axes:
		if absf((axis as Vector3).dot(unit)) > _PARALLEL_DOT:
			return
	axes.append(unit)
