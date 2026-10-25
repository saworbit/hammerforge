@tool
extends RefCounted
## Sweep faces into a run of brushes along a bend (#1714).
##
## The faces the mapper picked are the cross section. A start frame stands on
## them, its Z the way they face, and an end frame says where the run ends: a
## straight run, a circular arc whose axis is worked out from the two frames, or
## an S bend between them. The path is cut into segments, and each cut carries
## the section, placed by that cut's frame: on an arc a cut is the radial plane
## through the axis, so the section turns with the bend and stays whole. Each
## piece is the convex hull of the section at its two cuts, so it is one convex
## brush, and two pieces share the section at the cut between them, face to face.
##
## A piece whose far section is not wholly ahead of its near cut folds back on
## itself, as a bend too tight for the section's width does, and is refused.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("face_data.gd")
const HFHull = preload("hf_hull.gd")
@warning_ignore_restore("shadowed_global_identifier")

enum Path { STRAIGHT, ARC, S_BEND }

const PATH_NAMES := ["Straight", "Arc", "S bend"]
## The most segments one sweep may cut, and the most times it may repeat.
const MAX_SEGMENTS := 64
const MAX_ITERATIONS := 32
## Closer to straight than this, in radians, an arc is a straight run.
const STRAIGHT_ENOUGH := 0.0001
## How far ahead of its near cut every corner of a piece's far section must be.
const AHEAD := 0.001


## The frame a sweep starts from on a section of corner rings in world space,
## all in one plane facing `normal`: its middle, Z along `normal`, and Y as near
## the world's up as the plane allows.
static func start_frame(rings: Array, normal: Vector3) -> Transform3D:
	var middle := Vector3.ZERO
	var count := 0
	for ring in rings:
		for corner in ring:
			middle += corner
			count += 1
	if count > 0:
		middle /= count
	var z := normal.normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Transform3D(Basis(x, y, z), middle)


## Where a sweep ends from `start`, as a dialog's typed values say: `length` along
## Z for a straight run; an arc of `angle` degrees and `radius` turning toward
## `toward` (a unit direction in the start frame's own X and Y); or an S bend
## `length` along and `offset` toward `toward`, facing as it began.
static func end_frame(
	start: Transform3D,
	path: int,
	length: float,
	angle: float,
	radius: float,
	offset: float,
	toward: Vector2
) -> Transform3D:
	var z := start.basis.z
	var side := (start.basis.x * toward.x + start.basis.y * toward.y).normalized()
	match path:
		Path.ARC:
			var axis := z.cross(side).normalized()
			var centre := start.origin + side * radius
			var turn := Basis(axis, deg_to_rad(angle))
			return Transform3D(turn * start.basis, centre + turn * (start.origin - centre))
		Path.S_BEND:
			return Transform3D(start.basis, start.origin + z * length + side * offset)
	return Transform3D(start.basis, start.origin + z * length)


## The frames at every cut from `start` to `end` along `path`, `segments` pieces'
## worth: segments + 1 frames, the first `start` and the last `end`.
static func frames(path: int, start: Transform3D, end: Transform3D, segments: int) -> Array:
	var count := clampi(segments, 1, MAX_SEGMENTS)
	var out: Array = []
	match path:
		Path.ARC:
			var arc := _arc(start, end)
			if arc.is_empty():
				return frames(Path.STRAIGHT, start, end, count)
			for k in count + 1:
				var t := float(k) / count
				var turn := Basis(arc["axis"], arc["angle"] * t)
				var origin: Vector3 = (
					arc["centre"]
					+ turn * (start.origin - arc["centre"])
					+ arc["axis"] * arc["rise"] * t
				)
				out.append(Transform3D(turn * start.basis, origin))
		Path.S_BEND:
			var reach := start.origin.distance_to(end.origin)
			var heading := start.basis.z
			var basis := start.basis
			for k in count + 1:
				var t := float(k) / count
				var tangent := _hermite_tangent(start, end, reach, t)
				if k > 0 and not tangent.is_zero_approx():
					# Turned the least that takes the last heading to this one, so the
					# section does not twist.
					basis = Basis(Quaternion(heading, tangent.normalized())) * basis
					heading = tangent.normalized()
				out.append(Transform3D(basis.orthonormalized(), _hermite(start, end, reach, t)))
			out[out.size() - 1] = end
		_:
			for k in count + 1:
				var t := float(k) / count
				out.append(start.interpolate_with(end, t))
	return out


## `{axis, angle, centre, rise}` of the turn about a line that takes `start` to
## `end`, `rise` how far along the axis it climbs on the way, or {} when the two
## face the same way.
static func _arc(start: Transform3D, end: Transform3D) -> Dictionary:
	var relative := (end.basis * start.basis.inverse()).orthonormalized()
	var quat := relative.get_rotation_quaternion()
	var angle := quat.get_angle()
	if angle > PI:
		angle -= TAU
	if absf(angle) < STRAIGHT_ENOUGH:
		return {}
	var axis := quat.get_axis().normalized()
	var move := end.origin - start.origin
	var rise := move.dot(axis)
	var across := move - axis * rise
	# The centre is where the start turns onto the end: (I - R) u = across, in the
	# plane square to the axis, with u from the start to the centre.
	var e1 := (start.basis.z - axis * start.basis.z.dot(axis)).normalized()
	if e1.is_zero_approx():
		e1 = axis.cross(Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT).normalized()
	var e2 := axis.cross(e1)
	var a := across.dot(e1)
	var b := across.dot(e2)
	var c := cos(angle)
	var s := sin(angle)
	var den := 2.0 - 2.0 * c
	var u1 := ((1.0 - c) * a - s * b) / den
	var u2 := (s * a + (1.0 - c) * b) / den
	return {"axis": axis, "angle": angle, "centre": start.origin + e1 * u1 + e2 * u2, "rise": rise}


static func _hermite(start: Transform3D, end: Transform3D, reach: float, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return (
		start.origin * (2.0 * t3 - 3.0 * t2 + 1.0)
		+ start.basis.z * reach * (t3 - 2.0 * t2 + t)
		+ end.origin * (-2.0 * t3 + 3.0 * t2)
		+ end.basis.z * reach * (t3 - t2)
	)


static func _hermite_tangent(
	start: Transform3D, end: Transform3D, reach: float, t: float
) -> Vector3:
	var t2 := t * t
	return (
		start.origin * (6.0 * t2 - 6.0 * t)
		+ start.basis.z * reach * (3.0 * t2 - 4.0 * t + 1.0)
		+ end.origin * (-6.0 * t2 + 6.0 * t)
		+ end.basis.z * reach * (3.0 * t2 - 2.0 * t)
	)


## The frames of `iterations` sweeps, each from where the last one ended: every
## cut but the joins between sweeps, which each sweep's first frame repeats.
static func repeated(frame_list: Array, iterations: int) -> Array:
	var out: Array = frame_list.duplicate()
	if frame_list.size() < 2:
		return out
	var start: Transform3D = frame_list[0]
	var end: Transform3D = frame_list[frame_list.size() - 1]
	var step := end * start.affine_inverse()
	var carry := Transform3D.IDENTITY
	for i in range(1, clampi(iterations, 1, MAX_ITERATIONS)):
		carry = step * carry
		for k in range(1, frame_list.size()):
			out.append(carry * (frame_list[k] as Transform3D))
	return out


## The pieces of sweeping `rings` (world corner rings, all in `start`'s plane)
## through `frame_list`: `{pieces, folded}`, each piece `{faces, edges, section,
## segment, ok}` with `faces` world FaceData, and `folded` how many fold back on
## themselves. A ring is placed at each frame as it sits in the first, scaled
## about the frame's middle from 1 at the first cut to `end_scale` at the last,
## along its own X and Y, so a run narrows or widens and two pieces still share
## the cut between them (#1899). `edges` says for each face the edge of its ring
## it ran along, or -1 for an end.
static func pieces(rings: Array, frame_list: Array, end_scale := Vector2.ONE) -> Dictionary:
	var out: Array = []
	var folded := 0
	if frame_list.size() < 2:
		return {"pieces": out, "folded": 0}
	var first: Transform3D = frame_list[0]
	var to_first := first.affine_inverse()
	var last := frame_list.size() - 1
	for section in rings.size():
		var local := PackedVector3Array()
		for corner in rings[section]:
			local.append(to_first * (corner as Vector3))
		for k in last:
			var near_frame: Transform3D = frame_list[k]
			var far_frame: Transform3D = frame_list[k + 1]
			var near := _placed(local, near_frame, Vector2.ONE.lerp(end_scale, float(k) / last))
			var far := _placed(local, far_frame, Vector2.ONE.lerp(end_scale, float(k + 1) / last))
			var ok := (
				_ahead(near, near_frame.basis.z, far) and _ahead(far, -far_frame.basis.z, near)
			)
			var faces: Array = []
			if ok:
				var hull := HFHull.of(near + far)
				ok = bool(hull.get("ok", false))
				if ok:
					faces = hull["faces"]
			if not ok:
				folded += 1
			(
				out
				. append(
					{
						"faces": faces,
						"edges": _edges_run_along(faces, near, far),
						"section": section,
						"segment": k,
						"ok": ok,
					}
				)
			)
	return {"pieces": out, "folded": folded}


## `local`, a ring in the first frame's space, placed at `frame` and scaled by
## `scale` along that frame's X and Y about its middle.
static func _placed(
	local: PackedVector3Array, frame: Transform3D, scale: Vector2
) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in local:
		out.append(frame * Vector3(point.x * scale.x, point.y * scale.y, point.z))
	return out


## For each of `faces`, the edge of the ring, from corner i to i + 1, whose two
## ends at the near cut and at the far cut all lie on it, or -1 for a face no edge
## ran along: the ends of the piece.
static func _edges_run_along(
	faces: Array, near: PackedVector3Array, far: PackedVector3Array
) -> PackedInt32Array:
	var out := PackedInt32Array()
	for face in faces:
		var plane := Plane((face as FaceData).normal, (face as FaceData).local_verts[0])
		var found := -1
		for i in near.size():
			var j := (i + 1) % near.size()
			var on_it := true
			for point in [near[i], near[j], far[i], far[j]]:
				on_it = on_it and absf(plane.distance_to(point)) <= AHEAD
			if on_it:
				found = i
				break
		out.append(found)
	return out


## Whether every point of `ahead` is on the side of `ring`'s plane that `facing`
## points to, by more than AHEAD.
static func _ahead(ring: PackedVector3Array, facing: Vector3, ahead: PackedVector3Array) -> bool:
	if ring.is_empty():
		return false
	var plane := Plane(facing.normalized(), ring[0])
	for point in ahead:
		if plane.distance_to(point) <= AHEAD:
			return false
	return true


## Give every face in `faces` the look of `source`: its material and how its
## texture is laid on.
static func take_look(faces: Array, source: FaceData) -> void:
	for face: FaceData in faces:
		face.material_idx = source.material_idx
		face.map_texture = source.map_texture
		face.uv_projection = source.uv_projection
		face.legacy_wall_axes = source.legacy_wall_axes
		face.uv_scale = source.uv_scale
		face.uv_offset = source.uv_offset
		face.uv_rotation = source.uv_rotation
