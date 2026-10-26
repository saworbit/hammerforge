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
## Two solids whose shadows along a move share no more than this each way pass
## each other.
const SHADOW_HAIR := 0.001
## A face whose normal is this near square to a move runs along it.
const ALONG_FACE := 0.0001


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


## Which way each face points, by its winding: 1 away from the solid's middle,
## -1 into it, and 0 for a face too small or too central to say (#1869).
##
## A face wound the wrong way points into its brush. It is culled seen from
## outside and bakes facing into the solid, so it looks like any missing face.
## A displaced face is measured on the face under the displacement, which is
## what its corners are.
static func face_directions(faces: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(faces.size())
	var centre := vertex_centre(faces)
	for index in faces.size():
		var points := ring(faces[index])
		if points.size() < 3:
			continue
		var a: Vector3 = points[0]
		var normal: Vector3 = (points[2] - a).cross(points[1] - a)
		if normal.length() < 0.000001:
			continue
		var corner_sum := Vector3.ZERO
		for point in points:
			corner_sum += point
		var to_face: Vector3 = corner_sum / float(points.size()) - centre
		if to_face.length() < 0.000001:
			continue
		out[index] = 1 if normal.normalized().dot(to_face.normalized()) > 0.0 else -1
	return out


## The index of each face that points into its solid.
static func inward_faces(faces: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var directions := face_directions(faces)
	for index in directions.size():
		if directions[index] < 0:
			out.append(index)
	return out


## The share of the faces it can measure that point away from the solid's
## middle: 1 when every face does, and -1 when it can measure none.
static func outward_ratio(faces: Array) -> float:
	var outward := 0
	var counted := 0
	for direction in face_directions(faces):
		if direction != 0:
			counted += 1
			if direction > 0:
				outward += 1
	return float(outward) / float(counted) if counted > 0 else -1.0


## Every corner of the solid lies on or behind every face's plane, each plane
## turned to face away from the solid's middle, so a face wound the wrong way
## does not make a convex solid read as bent.
static func is_convex(faces: Array, tolerance := 0.01) -> bool:
	var centre := vertex_centre(faces)
	for face in faces:
		var points := ring(face)
		if points.size() < 3:
			continue
		var a: Vector3 = points[0]
		var normal: Vector3 = (points[2] - a).cross(points[1] - a)
		if normal.length() < 0.000001:
			continue
		normal = normal.normalized()
		if normal.dot(centre - a) > 0.0:
			normal = -normal
		var d := normal.dot(a)
		for other in faces:
			for point in ring(other):
				if normal.dot(point) - d > tolerance:
					return false
	return true


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


## How far convex solid `a` can move along `direction` before it meets convex
## solid `b` (#1964, #1966): the least, over the lines along `direction` through
## both, of the room between the end of `a` that leads and the end of `b` that
## faces it. Less than 0 when they overlap on a line, by how far `a` is into `b`
## there. INF when nothing of `b` is ahead of `a`, and when they pass each other,
## which they do when their shadows along `direction` share no more than a hair,
## so a box beside a wall's face is not stopped by the top of the wall.
##
## The least is on a line through a corner of either, or through a place where
## an edge of one crosses an edge of the other seen along the move, so those are
## the lines measured. A line on which `b` is wholly behind `a` does not count.
static func gap_along(a_faces: Array, b_faces: Array, direction: Vector3) -> float:
	var along := direction.normalized()
	if along == Vector3.ZERO:
		return INF
	var side := along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.UP).normalized()
	var other := along.cross(side)
	var a_corners := _corners(a_faces)
	var b_corners := _corners(b_faces)
	var a_shadow := _shadow(a_corners, side, other)
	var b_shadow := _shadow(b_corners, side, other)
	if not _shadows_overlap(a_shadow, b_shadow):
		return INF
	var lines := PackedVector3Array(a_corners)
	lines.append_array(b_corners)
	var b_edges: Array = []
	for edge in _segments(b_faces):
		b_edges.append(_shadow(PackedVector3Array(edge), side, other))
	for edge in _segments(a_faces):
		var from := _shadow(PackedVector3Array(edge), side, other)
		for flat in b_edges:
			var crossing: Variant = Geometry2D.segment_intersects_segment(
				from[0], from[1], flat[0], flat[1]
			)
			if crossing is Vector2:
				lines.append(side * crossing.x + other * crossing.y)
	var a_planes := _outward_planes(a_faces)
	var b_planes := _outward_planes(b_faces)
	var best := INF
	for point in lines:
		var a_span := _span_along(a_planes, point, along)
		var b_span := _span_along(b_planes, point, along)
		if a_span.x > a_span.y + TOUCH or b_span.x > b_span.y + TOUCH:
			continue
		if b_span.y > a_span.x + TOUCH:
			best = minf(best, b_span.x - a_span.y)
	return best


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


## Each corner once.
static func _corners(faces: Array) -> PackedVector3Array:
	var seen := {}
	for face in faces:
		for point in ring(face):
			seen[point] = true
	return PackedVector3Array(seen.keys())


## `points` seen along a move, on the plane across it that `side` and `other` span.
static func _shadow(
	points: PackedVector3Array, side: Vector3, other: Vector3
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(Vector2(side.dot(point), other.dot(point)))
	return out


## Whether two shadows share more than a hair. Each outline is drawn in by
## `SHADOW_HAIR` first, so two that only meet along an edge or at a corner do not.
static func _shadows_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var a_hull := Geometry2D.convex_hull(a)
	var b_hull := Geometry2D.convex_hull(b)
	if a_hull.size() < 3 or b_hull.size() < 3:
		return false
	var a_inner := Geometry2D.offset_polygon(a_hull, -SHADOW_HAIR)
	var b_inner := Geometry2D.offset_polygon(b_hull, -SHADOW_HAIR)
	for a_part in a_inner:
		for b_part in b_inner:
			if not Geometry2D.intersect_polygons(a_part, b_part).is_empty():
				return true
	return false


## Each face's plane, turned to face away from the solid's middle.
static func _outward_planes(faces: Array) -> Array[Plane]:
	var centre := vertex_centre(faces)
	var out: Array[Plane] = []
	for face in faces:
		var normal := face_normal(face)
		if normal == Vector3.ZERO:
			continue
		var plane := Plane(normal, face_centre(face))
		out.append(-plane if plane.distance_to(centre) > 0.0 else plane)
	return out


## The stretch of the line through `point` along `along` that is inside every
## plane, as distances along it from `point`: (in, out), with in past out when
## the line misses. A face the line runs along keeps it when the line is within
## `TOUCH` of it, so a line down a box's side is in the box.
static func _span_along(planes: Array[Plane], point: Vector3, along: Vector3) -> Vector2:
	var enter := -INF
	var leave := INF
	for plane in planes:
		var height := plane.distance_to(point)
		var rate := plane.normal.dot(along)
		if absf(rate) < ALONG_FACE:
			if height > TOUCH:
				return Vector2(INF, -INF)
			continue
		if rate > 0.0:
			leave = minf(leave, -height / rate)
		else:
			enter = maxf(enter, -height / rate)
	return Vector2(enter, leave)
