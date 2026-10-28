@tool
extends RefCounted
## The convex hull of a set of points, as the faces of one brush (#1715).
##
## Merge makes the exact union and refuses brushes that do not touch, and a shape
## easier to describe as "everything between these" was built by vertex editing a
## box until it matched. Hull of Selection wraps the corners of brushes whether
## they touch or not, and the Hull tool wraps points clicked one at a time. The
## engine's own hull finder picks the corners, each put back on the point it came
## from, and the faces are the planes through them that every corner lies behind,
## wound clockwise from outside as every brush face is.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("face_data.gd")
const HFConvexClip = preload("hf_convex_clip.gd")
const HFSolidMeasure = preload("hf_solid_measure.gd")
@warning_ignore_restore("shadowed_global_identifier")

## How far a point may sit off a plane for the points to count as flat.
const ON_PLANE := 0.01
## How far a corner may sit off a face's plane and still be one of its corners.
## A face is flat, so this is a rounding error and no more. At ON_PLANE, a corner
## 0.008 off a long thin face's plane joined it, and the hull came out with faces
## that were not flat and overlapped, which is no closed solid (#1843).
const ON_FACE := 0.0001
## Points closer than this are one point.
const SAME_POINT := 0.001

const TOO_FEW := "Place at least 4 points, not all in one plane"
const FLAT := "The points lie in one plane, so they hold no solid"


## The hull of `points`: `{"ok": true, "faces": Array[FaceData], "corners":
## PackedVector3Array}`, the faces in the points' own space, or `{"ok": false,
## "reason": String}` for fewer than four points or points in one plane.
##
## `rounding` is how far the points may sit from where they were meant to be. A
## corner that far off a face is on it: a brush kilometres out is placed to a
## float's step there, which is more than `ON_FACE` (#1971).
static func of(points: PackedVector3Array, rounding := 0.0) -> Dictionary:
	var unique := unique_points(points)
	if unique.size() < 4:
		return {"ok": false, "reason": TOO_FEW}
	if is_flat(unique):
		return {"ok": false, "reason": FLAT}
	var corners := _corners(unique)
	var faces := _faces(corners, maxf(ON_FACE, rounding))
	if faces.size() < 4:
		return {"ok": false, "reason": FLAT}
	return {"ok": true, "faces": faces, "corners": corners}


## `points` with any point within `SAME_POINT` of an earlier one left out.
static func unique_points(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in points:
		var seen := false
		for kept in out:
			if kept.distance_to(point) < SAME_POINT:
				seen = true
				break
		if not seen:
			out.append(point)
	return out


## Whether every one of `points` lies on one plane, or on one line.
static func is_flat(points: PackedVector3Array) -> bool:
	if points.size() < 4:
		return true
	var a: Vector3 = points[0]
	var far_index := 1
	for i in range(1, points.size()):
		if a.distance_to(points[i]) > a.distance_to(points[far_index]):
			far_index = i
	var b: Vector3 = points[far_index]
	var normal := Vector3.ZERO
	for point in points:
		var across := (b - a).cross(point - a)
		if across.length() > normal.length():
			normal = across
	if normal.length() < SAME_POINT:
		return true
	var plane := Plane(normal.normalized(), a)
	for point in points:
		if absf(plane.distance_to(point)) > ON_PLANE:
			return false
	return true


## The points of `points` on the hull. The engine's hull finder may move a corner
## by a rounding error, so each is put back on the point nearest it.
static func _corners(points: PackedVector3Array) -> PackedVector3Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var shape := mesh.create_convex_shape(true, false) as ConvexPolygonShape3D
	if shape == null or shape.points.size() < 4:
		return points
	var out := PackedVector3Array()
	for found in shape.points:
		var nearest: Vector3 = points[0]
		for point in points:
			if point.distance_squared_to(found) < nearest.distance_squared_to(found):
				nearest = point
		if not out.has(nearest):
			out.append(nearest)
	return out


## One face for each plane through three of `corners` that has every corner within
## `on_face` behind it, holding every corner within `on_face` of it. Three corners
## on a face already found are that face.
##
## Trying every three corners against every face found took seconds on two round
## brushes (#1999), so the faces are found by walking from one to the next. Where
## corners sit about `on_face` off one plane, the walk can leave a seam open that
## the search through every three closes, so that search still has the last word
## when the walk does not close.
static func _faces(corners: PackedVector3Array, on_face := ON_FACE) -> Array:
	var walked := _walk(corners, on_face)
	if HFSolidMeasure.open_edge_count(walked) == 0:
		return walked
	return _every_three(corners, on_face)


## The faces, found by walking: from one face, across each edge, to the corner the
## plane through that edge meets first as it turns out of the face. Each face
## takes its plane from the first three of its corners that make one, and the
## faces come in that order, as the search through every three made them.
static func _walk(corners: PackedVector3Array, on_face: float) -> Array:
	var start := _first_triple(corners, range(corners.size()), on_face)
	if start.is_empty():
		return []
	var walked: Array = []
	var planes: Array[Plane] = []
	var edges := {}
	var index_of := {}
	for i in corners.size():
		index_of[corners[i]] = i
	_add_face(corners, start, walked, planes, edges, index_of, on_face)
	var next := 0
	while next < walked.size():
		var from: Dictionary = walked[next]
		next += 1
		var ring: PackedInt32Array = from["ring"]
		var middle := Vector3.ZERO
		for i in ring:
			middle += corners[i]
		middle /= float(ring.size())
		for r in ring.size():
			var a := ring[r]
			var b := ring[(r + 1) % ring.size()]
			# The face across this edge is found, and holds it the other way round.
			if edges.has(Vector2i(b, a)):
				continue
			var c := _pivot(corners, from["plane"], middle, a, b, on_face)
			if c < 0:
				continue
			var normal := (corners[b] - corners[a]).cross(corners[c] - corners[a])
			var plane := Plane(normal.normalized(), corners[a])
			var side := _side(corners, plane, on_face)
			if side == 0:
				continue
			# Corners a rounding error off one plane can make another plane through
			# three of them leave the fourth off, so the face keeps every corner this
			# plane holds. When no three of them do, it is this plane, which holds
			# the edge it was found across.
			var on_it := _on_plane(corners, plane, on_face)
			var found := _first_triple(corners, on_it, on_face, true)
			if found.is_empty():
				var first := [a, b, c]
				first.sort()
				found = {
					"first": Vector3i(first[0], first[1], first[2]),
					"plane": plane if side > 0 else -plane,
				}
			_add_face(corners, found, walked, planes, edges, index_of, on_face)
	walked.sort_custom(func(one, other): return one["first"] < other["first"])
	var faces: Array = []
	for each in walked:
		faces.append(each["face"])
	return faces


## The faces, found by trying every three corners in order against every face
## found so far.
static func _every_three(corners: PackedVector3Array, on_face: float) -> Array:
	var planes: Array[Plane] = []
	var faces: Array = []
	var count := corners.size()
	for i in count:
		for j in range(i + 1, count):
			for k in range(j + 1, count):
				var normal := (corners[j] - corners[i]).cross(corners[k] - corners[i])
				if normal.length_squared() < 1e-8:
					continue
				if _on_a_face(planes, [corners[i], corners[j], corners[k]], on_face):
					continue
				var plane := Plane(normal.normalized(), corners[i])
				var side := _side(corners, plane, on_face)
				if side == 0:
					continue
				if side < 0:
					plane = -plane
				planes.append(plane)
				faces.append(_face_on(corners, plane, on_face))
	return faces


## The face on `plane`: every corner within `on_face` of it, wound clockwise from
## outside.
static func _face_on(corners: PackedVector3Array, plane: Plane, on_face: float) -> FaceData:
	var on_it := PackedVector3Array()
	for i in _on_plane(corners, plane, on_face):
		on_it.append(corners[i])
	var face := FaceData.new()
	face.local_verts = HFConvexClip.sort_coplanar_cw(on_it, plane.normal)
	face.normal = plane.normal
	face.ensure_geometry()
	return face


## The first three of the corners at `among`, in order, that a plane goes through
## with every corner on or behind it, and with all of `among` on it when
## `holding_all`: `{"first": Vector3i, "plane": Plane}`, the plane facing out, or
## empty when no three do.
static func _first_triple(
	corners: PackedVector3Array, among: Array, on_face: float, holding_all := false
) -> Dictionary:
	var count := among.size()
	for x in count:
		var i: int = among[x]
		for y in range(x + 1, count):
			var j: int = among[y]
			for z in range(y + 1, count):
				var k: int = among[z]
				var normal := (corners[j] - corners[i]).cross(corners[k] - corners[i])
				if normal.length_squared() < 1e-8:
					continue
				var plane := Plane(normal.normalized(), corners[i])
				if holding_all and _on_plane(corners, plane, on_face, among).size() < count:
					continue
				var side := _side(corners, plane, on_face)
				if side == 0:
					continue
				return {"first": Vector3i(i, j, k), "plane": plane if side > 0 else -plane}
	return {}


## The indices of the corners within `on_face` of `plane`, in order, of those at
## `among`, or of every corner when `among` is empty.
static func _on_plane(
	corners: PackedVector3Array, plane: Plane, on_face: float, among: Array = []
) -> Array:
	var out: Array = []
	for i in among if not among.is_empty() else range(corners.size()):
		if absf(plane.distance_to(corners[i])) <= on_face:
			out.append(i)
	return out


## Add the face on `found`'s plane to `walked`, unless its first three corners
## are on a face already there.
static func _add_face(
	corners: PackedVector3Array,
	found: Dictionary,
	walked: Array,
	planes: Array[Plane],
	edges: Dictionary,
	index_of: Dictionary,
	on_face: float
) -> void:
	var first: Vector3i = found["first"]
	if _on_a_face(planes, [corners[first.x], corners[first.y], corners[first.z]], on_face):
		return
	var plane: Plane = found["plane"]
	planes.append(plane)
	var face := _face_on(corners, plane, on_face)
	var ring := PackedInt32Array()
	for corner in face.local_verts:
		ring.append(int(index_of[corner]))
	for r in ring.size():
		edges[Vector2i(ring[r], ring[(r + 1) % ring.size()])] = true
	walked.append({"first": first, "plane": plane, "face": face, "ring": ring})


## The corner that a plane through corners `a` and `b`, turning about them out of
## `plane`, meets first, or -1. Every corner is on or behind the plane through
## the three, so it is the plane of the face across that edge.
static func _pivot(
	corners: PackedVector3Array, plane: Plane, inside: Vector3, a: int, b: int, on_face: float
) -> int:
	var from := corners[a]
	var along := corners[b] - from
	var best := -1
	var best_normal := Vector3.ZERO
	for q in corners.size():
		var corner := corners[q]
		if absf(plane.distance_to(corner)) <= on_face:
			continue
		var normal := along.cross(corner - from)
		if normal.length_squared() < 1e-8:
			continue
		if best >= 0 and best_normal.dot(corner - from) <= 0.0:
			continue
		if normal.dot(inside - from) > 0.0:
			normal = -normal
		best = q
		best_normal = normal
	return best


## 1 when every corner is on or behind `plane`, -1 when every one is on or in
## front of it, 0 when they are on both sides. A corner within `on_face` of it is
## on it.
static func _side(corners: PackedVector3Array, plane: Plane, on_face := ON_FACE) -> int:
	var behind := true
	var ahead := true
	for corner in corners:
		var distance := plane.distance_to(corner)
		if distance > on_face:
			behind = false
		if distance < -on_face:
			ahead = false
		if not behind and not ahead:
			return 0
	return 1 if behind else -1


## Whether every one of `points` lies within `on_face` of one of `planes`.
## Comparing a new plane's normal and distance with each known one let two faces a
## fraction of a degree apart count as one, which left a hole where the second
## should have been.
static func _on_a_face(planes: Array[Plane], points: Array, on_face := ON_FACE) -> bool:
	for known in planes:
		var all_on := true
		for point in points:
			if absf(known.distance_to(point)) > on_face:
				all_on = false
				break
		if all_on:
			return true
	return false
