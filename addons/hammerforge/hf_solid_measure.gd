@tool
extends RefCounted
## Sizes, gaps and angles of convex solids, measured from their faces (#1649).
##
## A solid here is its faces, each a ring of points wound clockwise seen from
## outside, as a brush's faces are. The bridge's `hf_measure` answers through
## this in world space, and the tests' `solid_checks.gd` asks it a solid's middle
## and bounds, so both measure one way.
##
## A face is given as a `PackedVector3Array` or as anything with `local_verts`,
## such as a brush's `FaceData`, read as it stands.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFVertexWeld = preload("hf_vertex_weld.gd")
@warning_ignore_restore("shadowed_global_identifier")

## Below this two solids touch: a gap of 0.
const TOUCH := 0.0001
## Edge directions paired for the overlap test, past which only face normals are
## tried. A 64 sided cylinder against another is 4,225 pairs.
const MAX_EDGE_PAIRS := 4096


static func ring(face: Variant) -> PackedVector3Array:
	if face is PackedVector3Array:
		return face
	return face.local_verts if face != null else PackedVector3Array()


## Each face of `brush` as a ring of world points.
static func world_faces(brush: Node3D) -> Array:
	var xform := brush.global_transform
	var faces: Array = []
	for face in brush.get("faces"):
		if face == null:
			continue
		if face.has_method("ensure_geometry"):
			face.ensure_geometry()
		var points := PackedVector3Array()
		for point in ring(face):
			points.append(xform * point)
		if points.size() >= 3:
			faces.append(points)
	return faces


## The middle of the points, each counted once a face it is on.
static func vertex_centre(faces: Array) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for face in faces:
		for point in ring(face):
			total += point
			count += 1
	return total / float(count) if count > 0 else Vector3.ZERO


static func bounds(faces: Array) -> AABB:
	var box := AABB()
	var seeded := false
	for face in faces:
		for point in ring(face):
			if seeded:
				box = box.expand(point)
			else:
				box = AABB(point, Vector3.ZERO)
				seeded = true
	return box


## The volume a closed solid holds, by the signed volumes of the tetrahedra its
## faces make with the origin. Winding either way gives the same size.
static func volume(faces: Array) -> float:
	var total := 0.0
	for face in faces:
		var points := ring(face)
		for i in range(1, points.size() - 1):
			total += points[0].dot(points[i].cross(points[i + 1]))
	return absf(total) / 6.0


static func face_area(face: Variant) -> float:
	var points := ring(face)
	var sum := Vector3.ZERO
	for i in range(1, points.size() - 1):
		sum += (points[i] - points[0]).cross(points[i + 1] - points[0])
	return sum.length() * 0.5


static func face_centre(face: Variant) -> Vector3:
	var points := ring(face)
	var total := Vector3.ZERO
	for point in points:
		total += point
	return total / float(points.size()) if not points.is_empty() else Vector3.ZERO


## The way a face looks, out of the solid: its points run clockwise seen from
## there. The largest cross product of the fan, so a sliver corner cannot tip it.
static func face_normal(face: Variant) -> Vector3:
	var points := ring(face)
	var sum := Vector3.ZERO
	for i in range(1, points.size() - 1):
		sum += (points[i + 1] - points[0]).cross(points[i] - points[0])
	return sum.normalized() if sum.length_squared() > 0.0 else Vector3.ZERO


## How many edges of a solid's faces are used by anything but exactly two faces:
## 0 for a closed solid (#1769).
##
## Corners within `weld` of each other are one corner, chained as
## `HFVertexWeld.cluster()` chains them, so float noise from a turn or an import
## does not open a seam. A corner that lies on the straight line between its two
## neighbours is left out first: a clip can leave one on a face's edge that the
## face beside it does not have, and the edge is still shared.
static func open_edge_count(faces: Array, weld: float = 0.001) -> int:
	var rings: Array = []
	var points := PackedVector3Array()
	for face in faces:
		var corners := _without_straight_corners(ring(face), weld)
		rings.append(corners)
		points.append_array(corners)
	var id_of := PackedInt32Array()
	id_of.resize(points.size())
	for i in points.size():
		id_of[i] = i
	for group in HFVertexWeld.cluster(points, weld):
		for i in group:
			id_of[i] = group[0]
	var counts: Dictionary = {}
	var at := 0
	for corners in rings:
		var n: int = corners.size()
		for i in n:
			var a := id_of[at + i]
			var b := id_of[at + (i + 1) % n]
			if a != b:
				var key := Vector2i(mini(a, b), maxi(a, b))
				counts[key] = int(counts.get(key, 0)) + 1
		at += n
	var open := 0
	for key in counts:
		if counts[key] != 2:
			open += 1
	return open


## `points` without the corners that sit on the line between their neighbours.
static func _without_straight_corners(
	points: PackedVector3Array, weld: float
) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := points.size()
	for i in n:
		var before := points[(i - 1 + n) % n]
		var here := points[i]
		var after := points[(i + 1) % n]
		var span := after - before
		if span.length() > weld:
			var off_line := (here - before).cross(span).length() / span.length()
			if off_line <= weld and (here - before).dot(after - here) > 0.0:
				continue
		out.append(here)
	return out


## The smallest gap between two convex solids: the distance between them when
## apart, 0 when they touch, and minus how deep they go into each other when they
## overlap, which is how far the shorter way out is.
static func solid_gap(a_faces: Array, b_faces: Array) -> float:
	var overlap := _deepest_separation(a_faces, b_faces)
	if overlap <= TOUCH:
		return overlap if overlap < -TOUCH else 0.0
	return _distance_apart(a_faces, b_faces)


## A point's gap to a solid: the distance to it from outside, and minus the
## distance to its nearest face from inside.
static func point_gap(point: Vector3, faces: Array) -> float:
	var inside := true
	var nearest_plane := INF
	for face in faces:
		var points := ring(face)
		var height := face_normal(face).dot(point - points[0])
		if height > TOUCH:
			inside = false
			break
		nearest_plane = minf(nearest_plane, -height)
	if inside:
		return -nearest_plane if nearest_plane > TOUCH else 0.0
	var best := INF
	for face in faces:
		best = minf(best, point_face_distance(point, face))
	return best


## The gap between two faces as flat polygons: 0 when they meet or cross.
static func face_gap(a: Variant, b: Variant) -> float:
	for pair in [[a, b], [b, a]]:
		var edges := ring(pair[0])
		for i in edges.size():
			if _segment_meets_face(edges[i], edges[(i + 1) % edges.size()], pair[1]):
				return 0.0
	var gap := _distance_apart([a], [b])
	return gap if gap > TOUCH else 0.0


## How far apart two solids are along the axis that keeps them furthest apart,
## of their face normals and the crossings of their edges: the separation when
## positive, and minus the shallowest way out when they overlap.
static func _deepest_separation(a_faces: Array, b_faces: Array) -> float:
	var a_points := _points(a_faces)
	var b_points := _points(b_faces)
	var axes: Array[Vector3] = []
	for face in a_faces + b_faces:
		var normal := face_normal(face)
		if normal != Vector3.ZERO:
			axes.append(normal)
	var a_edges := _edge_directions(a_faces)
	var b_edges := _edge_directions(b_faces)
	if a_edges.size() * b_edges.size() <= MAX_EDGE_PAIRS:
		for u in a_edges:
			for v in b_edges:
				var axis := u.cross(v)
				if axis.length_squared() > 0.000001:
					axes.append(axis.normalized())
	var best := -INF
	for axis in axes:
		var a_span := _span(a_points, axis)
		var b_span := _span(b_points, axis)
		best = maxf(best, maxf(b_span.x - a_span.y, a_span.x - b_span.y))
	return best


## The distance between two solids known to be apart: the nearest of each corner
## to the other's faces and of each edge to the other's edges.
static func _distance_apart(a_faces: Array, b_faces: Array) -> float:
	var best := INF
	for pair in [[a_faces, b_faces], [b_faces, a_faces]]:
		for point in _points(pair[0]):
			for face in pair[1]:
				best = minf(best, point_face_distance(point, face))
	var a_segments := _segments(a_faces)
	var b_segments := _segments(b_faces)
	for s in a_segments:
		for t in b_segments:
			var closest := Geometry3D.get_closest_points_between_segments(s[0], s[1], t[0], t[1])
			best = minf(best, closest[0].distance_to(closest[1]))
	return best


static func point_face_distance(point: Vector3, face: Variant) -> float:
	var points := ring(face)
	var normal := face_normal(face)
	var height := normal.dot(point - points[0])
	if normal != Vector3.ZERO and _inside(point - normal * height, points, normal):
		return absf(height)
	var best := INF
	for i in points.size():
		var on_edge := Geometry3D.get_closest_point_to_segment(
			point, points[i], points[(i + 1) % points.size()]
		)
		best = minf(best, point.distance_to(on_edge))
	return best


## Whether `point`, on the face's plane, is inside the face or on its edge.
static func _inside(point: Vector3, points: PackedVector3Array, normal: Vector3) -> bool:
	var first_side := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var side := normal.dot((b - a).cross(point - a))
		if absf(side) <= TOUCH:
			continue
		if first_side == 0.0:
			first_side = signf(side)
		elif signf(side) != first_side:
			return false
	return true


static func _segment_meets_face(from: Vector3, to: Vector3, face: Variant) -> bool:
	var points := ring(face)
	var normal := face_normal(face)
	if normal == Vector3.ZERO:
		return false
	var a := normal.dot(from - points[0])
	var b := normal.dot(to - points[0])
	if a * b > 0.0 and absf(a) > TOUCH and absf(b) > TOUCH:
		return false
	if absf(a - b) <= TOUCH:
		# In the face's plane: meeting it is the edges crossing, which the
		# distance between edges finds.
		return false
	var hit := from + (to - from) * (a / (a - b))
	return _inside(hit, points, normal)


static func _points(faces: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for face in faces:
		out.append_array(ring(face))
	return out


## Each edge once, as [from, to].
static func _segments(faces: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for face in faces:
		var points := ring(face)
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			var key := _edge_key(a, b)
			if not seen.has(key):
				seen[key] = true
				out.append([a, b])
	return out


## The directions the solid's edges run in, each once whichever way it is walked.
static func _edge_directions(faces: Array) -> Array[Vector3]:
	var seen: Dictionary = {}
	var out: Array[Vector3] = []
	for segment in _segments(faces):
		var direction: Vector3 = (segment[1] - segment[0]).normalized()
		if direction == Vector3.ZERO:
			continue
		# One way round: the first component that is not nothing points up.
		for component in [direction.x, direction.y, direction.z]:
			if absf(component) > TOUCH:
				if component < 0.0:
					direction = -direction
				break
		var key := str(direction.snappedf(0.0001))
		if not seen.has(key):
			seen[key] = true
			out.append(direction)
	return out


static func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := str(a.snappedf(0.0001))
	var kb := str(b.snappedf(0.0001))
	return ka + "|" + kb if ka < kb else kb + "|" + ka


## The least and most `points` reach along `axis`, as (min, max).
static func _span(points: PackedVector3Array, axis: Vector3) -> Vector2:
	var low := INF
	var high := -INF
	for point in points:
		var along := axis.dot(point)
		low = minf(low, along)
		high = maxf(high, along)
	return Vector2(low, high)
