@tool
extends RefCounted
class_name HFConvexClip

## Splitting a convex solid, described by its faces, along an arbitrary plane.
##
## This is the geometry behind Clip and Carve. It is deliberately free of the
## scene: it takes `FaceData` and a `Plane` in the same space and returns
## `FaceData`, so both callers — and their tests — can work without a LevelRoot.
##
## Two conventions matter throughout.
##
## **Winding is clockwise as seen from outside.** `FaceData.triangulate()` fans
## straight off `local_verts`, and Godot reads front faces as clockwise, so the
## vertex order *is* the geometry's outward direction. The mathematically natural
## ordering of a coplanar ring is counter-clockwise about its normal, so anything
## built here rather than carried through has to be reversed. `sort_coplanar_cw()`
## names that in its signature so no caller has to rediscover it.
##
## **Front is the side the plane normal points to.** `split()` names its halves
## after the plane, not after the caller's intent.

const FaceData = preload("face_data.gd")

## Points closer than this to the plane count as lying on it. Brush coordinates
## run in the tens to thousands, so a thousandth of a unit is far below anything
## a user can author and far above float noise.
const DEFAULT_EPSILON := 0.001

## A side needs at least this many faces to bound a volume: four, as a
## tetrahedron does. Fewer means the plane grazed the solid and the "piece" is a
## sliver, not a brush.
const MIN_SOLID_FACES := 4


## World axis for an index: 0 = X, 1 = Y, anything else = Z.
static func axis_normal(axis_index: int) -> Vector3:
	match axis_index:
		0:
			return Vector3.RIGHT
		1:
			return Vector3.UP
		_:
			return Vector3.BACK


## The plane a face lies in, in the face's own space.
static func face_plane(face: FaceData) -> Plane:
	if face == null or face.local_verts.size() < 3:
		return Plane()
	var normal := _face_normal(face)
	if normal.length_squared() < 0.5:
		return Plane()
	return Plane(normal, normal.dot(face.local_verts[0]))


## Every bounding plane of a convex solid, taken into another space.
##
## Carve needs the carver's own faces as planes in the target's frame, and its
## face normals point outward, so a point in front of one of these planes is
## outside the carver.
static func face_planes_in_space(faces: Array, into: Transform3D) -> Array:
	var planes: Array = []
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null or data.local_verts.size() < 3:
			continue
		var local := face_plane(data)
		if local.normal.length_squared() < 0.5:
			continue
		planes.append(into * local)
	return planes


## Split a convex face set by a plane expressed in the same space.
##
## Returns `{"front": Array, "back": Array, "cut": PackedVector3Array}`. A side
## comes back empty when the plane misses the solid, or when what it would carve
## off is too thin to be a solid — which is how callers tell "nothing to do" from
## a real cut without measuring anything themselves.
static func split(faces: Array, plane: Plane, epsilon: float = DEFAULT_EPSILON) -> Dictionary:
	var empty := {"front": [], "back": [], "cut": PackedVector3Array()}
	if faces.is_empty():
		return empty

	var front: Array = []
	var back: Array = []
	var cut_points := PackedVector3Array()
	var saw_front := false
	var saw_back := false

	for face in faces:
		var source: FaceData = face as FaceData
		if source == null or source.local_verts.size() < 3:
			continue
		var verts: PackedVector3Array = source.local_verts
		var uvs: PackedVector2Array = source.custom_uvs
		var has_uvs := uvs.size() == verts.size()

		var above := 0
		var below := 0
		for vertex in verts:
			var distance := plane.distance_to(vertex)
			if distance > epsilon:
				above += 1
			elif distance < -epsilon:
				below += 1
		if above > 0:
			saw_front = true
		if below > 0:
			saw_back = true

		if below == 0:
			# Entirely in front, or lying on the plane.
			front.append(_face_like(source, verts, uvs if has_uvs else PackedVector2Array()))
			continue
		if above == 0:
			back.append(_face_like(source, verts, uvs if has_uvs else PackedVector2Array()))
			continue

		var front_part := clip_polygon(verts, uvs, plane, true, epsilon)
		var back_part := clip_polygon(verts, uvs, plane, false, epsilon)
		var front_verts: PackedVector3Array = front_part["verts"]
		var back_verts: PackedVector3Array = back_part["verts"]
		if front_verts.size() >= 3:
			front.append(_face_like(source, front_verts, front_part["uvs"]))
		if back_verts.size() >= 3:
			back.append(_face_like(source, back_verts, back_part["uvs"]))
		cut_points.append_array(_crossing_points(verts, plane, epsilon))

	if not saw_front or not saw_back:
		# The plane never separated anything, so the solid belongs to one side.
		if saw_back:
			return {"front": [], "back": _duplicate_faces(faces), "cut": PackedVector3Array()}
		return {"front": _duplicate_faces(faces), "back": [], "cut": PackedVector3Array()}

	var ring := cap_polygon(cut_points, -plane.normal, epsilon)
	if ring.size() >= 3:
		var template: FaceData = _nearest_face(faces, -plane.normal)
		# The two caps are the same ring seen from opposite sides, so one is the
		# reverse of the other. Front looks back down the plane normal; back looks
		# along it.
		front.append(_cap_face(template, ring, -plane.normal))
		var reversed_ring := PackedVector3Array()
		for i in range(ring.size() - 1, -1, -1):
			reversed_ring.append(ring[i])
		back.append(_cap_face(_nearest_face(faces, plane.normal), reversed_ring, plane.normal))

	if front.size() < MIN_SOLID_FACES:
		front = []
	if back.size() < MIN_SOLID_FACES:
		back = []
	return {"front": front, "back": back, "cut": cut_points}


## Clip one convex planar polygon, keeping the front or the back half.
##
## Sutherland-Hodgman in three dimensions. UVs ride along and are interpolated at
## each crossing by the edge parameter, so a cut face keeps its texture alignment
## instead of being re-projected.
static func clip_polygon(
	verts: PackedVector3Array,
	uvs: PackedVector2Array,
	plane: Plane,
	keep_front: bool,
	epsilon: float = DEFAULT_EPSILON
) -> Dictionary:
	var out_verts := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var count := verts.size()
	if count < 3:
		return {"verts": out_verts, "uvs": out_uvs}
	var has_uvs := uvs.size() == count
	var sign := 1.0 if keep_front else -1.0

	for i in count:
		var next_index := (i + 1) % count
		var current: Vector3 = verts[i]
		var next: Vector3 = verts[next_index]
		var current_distance := plane.distance_to(current) * sign
		var next_distance := plane.distance_to(next) * sign
		# Three-way classification, not a two-way inside test. A vertex sitting on
		# the plane is kept once and generates no crossing; testing only for
		# "inside" would emit it and then emit an intersection at the same point,
		# leaving a zero-length edge that stops the piece being a closed solid.
		var current_on := absf(current_distance) <= epsilon
		var next_on := absf(next_distance) <= epsilon

		if current_on or current_distance > 0.0:
			out_verts.append(current)
			if has_uvs:
				out_uvs.append(uvs[i])
		if current_on or next_on:
			continue
		if (current_distance > 0.0) == (next_distance > 0.0):
			continue
		var span := current_distance - next_distance
		if absf(span) < 0.000001:
			continue
		var t: float = clampf(current_distance / span, 0.0, 1.0)
		out_verts.append(current.lerp(next, t))
		if has_uvs:
			out_uvs.append(uvs[i].lerp(uvs[next_index], t))

	return {"verts": out_verts, "uvs": out_uvs if has_uvs else PackedVector2Array()}


## Order coplanar points into a ring wound clockwise as seen from `outward_normal`.
##
## Sorting by angle about the centroid gives counter-clockwise about the normal
## by the right-hand rule, so the result is reversed. That reversal is the whole
## reason this function exists rather than being written inline at its two call
## sites: clockwise-from-outside is what the rest of the codebase means by a face.
static func sort_coplanar_cw(
	verts: PackedVector3Array, outward_normal: Vector3
) -> PackedVector3Array:
	var count := verts.size()
	if count < 3:
		return verts
	var normal := outward_normal.normalized()
	if normal.length_squared() < 0.5:
		return verts
	var centroid := Vector3.ZERO
	for vertex in verts:
		centroid += vertex
	centroid /= float(count)
	var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var u := normal.cross(reference).normalized()
	var v := normal.cross(u)
	var order: Array = []
	for i in count:
		var relative: Vector3 = verts[i] - centroid
		order.append({"index": i, "angle": atan2(relative.dot(v), relative.dot(u))})
	order.sort_custom(func(a, b): return a["angle"] < b["angle"])
	var sorted := PackedVector3Array()
	for i in range(order.size() - 1, -1, -1):
		sorted.append(verts[order[i]["index"]])
	return sorted


## Build the cut surface from the crossing points, deduplicated and ordered.
static func cap_polygon(
	cut_points: PackedVector3Array, outward_normal: Vector3, epsilon: float = DEFAULT_EPSILON
) -> PackedVector3Array:
	var unique := PackedVector3Array()
	var seen := {}
	for point in cut_points:
		var key := _quantize(point, epsilon)
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(point)
	if unique.size() < 3:
		return PackedVector3Array()
	return sort_coplanar_cw(unique, outward_normal)


## Describe a face set as an axis-aligned box, or return an empty dictionary.
##
## A piece that is still a box should be emitted as one rather than as CUSTOM:
## a CUSTOM brush loses its resize handles, and the commonest cut of all — a box
## split down one of its own axes — produces two boxes.
##
## Returns `{"size": Vector3, "center": Vector3}` when the faces form a six-sided
## box aligned to the frame they are expressed in.
static func is_axis_aligned_box(faces: Array, epsilon: float = DEFAULT_EPSILON) -> Dictionary:
	if faces.size() != 6:
		return {}
	var bounds := AABB()
	var seeded := false
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null or data.local_verts.size() != 4:
			return {}
		var normal := _face_normal(data)
		if not _is_axis_direction(normal, epsilon):
			return {}
		for vertex in data.local_verts:
			if seeded:
				bounds = bounds.expand(vertex)
			else:
				bounds = AABB(vertex, Vector3.ZERO)
				seeded = true
	if not seeded:
		return {}
	if bounds.size.x <= epsilon or bounds.size.y <= epsilon or bounds.size.z <= epsilon:
		return {}
	# Every vertex has to sit on the shell of those bounds, or the faces describe
	# something box-shaped only in outline.
	for face in faces:
		var data: FaceData = face as FaceData
		for vertex in data.local_verts:
			if not _on_box_shell(vertex, bounds, epsilon):
				return {}
	return {"size": bounds.size, "center": bounds.get_center()}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


## A copy of `source` carrying new geometry and everything else unchanged.
static func _face_like(
	source: FaceData, verts: PackedVector3Array, uvs: PackedVector2Array
) -> FaceData:
	var face := FaceData.new()
	face.material_idx = source.material_idx
	face.uv_projection = source.uv_projection
	face.uv_scale = source.uv_scale
	face.uv_offset = source.uv_offset
	face.uv_rotation = source.uv_rotation
	face.local_verts = verts
	face.custom_uvs = uvs if uvs.size() == verts.size() else PackedVector2Array()
	face.ensure_geometry()
	return face


static func _cap_face(
	template: FaceData, ring: PackedVector3Array, outward_normal: Vector3
) -> FaceData:
	var face := FaceData.new()
	if template != null:
		face.material_idx = template.material_idx
		face.uv_projection = template.uv_projection
		face.uv_scale = template.uv_scale
		face.uv_offset = template.uv_offset
		face.uv_rotation = template.uv_rotation
	face.local_verts = ring
	face.normal = outward_normal.normalized()
	face.ensure_geometry()
	return face


static func _duplicate_faces(faces: Array) -> Array:
	var out: Array = []
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null or data.local_verts.size() < 3:
			continue
		out.append(_face_like(data, data.local_verts, data.custom_uvs))
	return out


## The face whose outward normal is most like `direction`. A cut surface has no
## texture of its own, so it borrows from the face it most resembles.
static func _nearest_face(faces: Array, direction: Vector3) -> FaceData:
	var best: FaceData = null
	var best_dot := -2.0
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null or data.local_verts.size() < 3:
			continue
		var alignment := _face_normal(data).dot(direction.normalized())
		if alignment > best_dot:
			best_dot = alignment
			best = data
	return best


static func _crossing_points(
	verts: PackedVector3Array, plane: Plane, epsilon: float
) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count := verts.size()
	for i in count:
		var current: Vector3 = verts[i]
		var next: Vector3 = verts[(i + 1) % count]
		var current_distance := plane.distance_to(current)
		var next_distance := plane.distance_to(next)
		if absf(current_distance) <= epsilon:
			out.append(current)
			continue
		if (current_distance > 0.0) == (next_distance > 0.0):
			continue
		if absf(next_distance) <= epsilon:
			continue
		var span := current_distance - next_distance
		if absf(span) < 0.000001:
			continue
		out.append(current.lerp(next, clampf(current_distance / span, 0.0, 1.0)))
	return out


## The face's outward normal, recomputed from its winding rather than trusted.
##
## `FaceData.normal` is a stored field and a caller may not have refreshed it;
## the vertex order is the authority. Same cross-product convention as
## `FaceData._compute_normal()`.
static func _face_normal(face: FaceData) -> Vector3:
	var verts := face.local_verts
	if verts.size() < 3:
		return face.normal
	var a: Vector3 = verts[0]
	for i in range(1, verts.size() - 1):
		var normal := (verts[i + 1] - a).cross(verts[i] - a)
		if normal.length_squared() > 0.000001:
			return normal.normalized()
	return face.normal


static func _is_axis_direction(direction: Vector3, epsilon: float) -> bool:
	var tolerance := maxf(0.999, 1.0 - epsilon)
	return (
		absf(direction.dot(Vector3.RIGHT)) >= tolerance
		or absf(direction.dot(Vector3.UP)) >= tolerance
		or absf(direction.dot(Vector3.BACK)) >= tolerance
	)


static func _on_box_shell(point: Vector3, bounds: AABB, epsilon: float) -> bool:
	var low := bounds.position
	var high := bounds.position + bounds.size
	if point.x < low.x - epsilon or point.x > high.x + epsilon:
		return false
	if point.y < low.y - epsilon or point.y > high.y + epsilon:
		return false
	if point.z < low.z - epsilon or point.z > high.z + epsilon:
		return false
	return (
		absf(point.x - low.x) <= epsilon
		or absf(point.x - high.x) <= epsilon
		or absf(point.y - low.y) <= epsilon
		or absf(point.y - high.y) <= epsilon
		or absf(point.z - low.z) <= epsilon
		or absf(point.z - high.z) <= epsilon
	)


static func _quantize(point: Vector3, epsilon: float) -> String:
	var step := maxf(epsilon, 0.000001)
	return "%d,%d,%d" % [roundi(point.x / step), roundi(point.y / step), roundi(point.z / step)]
