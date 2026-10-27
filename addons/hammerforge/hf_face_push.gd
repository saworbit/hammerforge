@tool
extends RefCounted
## Move one face of a brush along its own normal, any brush, box or not (#1712).
##
## Box brushes have resize handles. A brush that has been clipped, carved, vertex
## edited, merged or drawn with Polygon or Path is CUSTOM and has none, and a
## sloped face never had one, so after the first clip a brush could only change
## by a vertex edit or a typed number. Here a face's plane moves and the brush is
## rebuilt from its planes, so its neighbours lengthen or shorten to meet it and
## the brush stays convex. A box stays a box, with its handles, by growing or
## shrinking along the face's axis.
##
## A distance that would turn the brush inside out, flatten it, or squeeze a face
## out of it is refused; `farthest()` finds the last one that holds.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
const HFConvexClip = preload("hf_convex_clip.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The thinnest a brush may end up along the face's normal, in metres.
const MIN_THICKNESS := 0.01
## Two planes this close in angle and place are one plane.
const SAME_PLANE_DOT := 0.9999
const SAME_PLANE_GAP := 0.001
## How many halvings `farthest()` makes looking for the last distance that holds.
const SEARCH_STEPS := 16


## Move face `face_idx` of `brush` out along its normal by `distance`, or in for a
## negative one, and say how, without touching the brush: `{ok, reason}`, and for
## one that holds either `{box: true, size, position}` or `{box: false, faces}`
## with the faces in the brush's own space.
static func pushed(brush: DraftBrush, face_idx: int, distance: float) -> Dictionary:
	if brush == null or not is_instance_valid(brush):
		return _refused("the brush is gone")
	if face_idx < 0 or face_idx >= brush.faces.size() or brush.faces[face_idx] == null:
		return _refused("the brush has no such face")
	if not is_finite(distance):
		return _refused("that distance is not a number")
	var face: FaceData = brush.faces[face_idx]
	var plane := HFConvexClip.face_plane(face)
	if plane.normal.length_squared() < 0.5:
		return _refused("the face has no area")
	var axis := _box_axis(brush, plane.normal)
	if axis >= 0:
		return _pushed_box(brush, axis, plane.normal, distance)
	return _pushed_planes(brush, face_idx, distance)


## The largest move towards `distance`, from 0, that `pushed()` lets through.
static func farthest(brush: DraftBrush, face_idx: int, distance: float) -> float:
	if bool(pushed(brush, face_idx, distance).get("ok", false)):
		return distance
	var good := 0.0
	var bad := distance
	for _i in SEARCH_STEPS:
		var middle := (good + bad) * 0.5
		if bool(pushed(brush, face_idx, middle).get("ok", false)):
			good = middle
		else:
			bad = middle
	return good


## Put what `pushed()` worked out on the brush.
static func apply(brush: DraftBrush, result: Dictionary) -> void:
	if brush == null or not bool(result.get("ok", false)):
		return
	if bool(result.get("box", false)):
		brush.size = result["size"]
		brush.global_position = result["position"]
		return
	var faces: Array[FaceData] = []
	for face in result["faces"]:
		faces.append(face)
	if brush.shape != DraftBrush.BrushShape.CUSTOM:
		brush.shape = DraftBrush.BrushShape.CUSTOM
	brush.faces = faces
	brush.size = DraftBrush._vertex_bounds(faces).size
	brush.geometry_dirty = false
	brush.rebuild_preview()


## The brush as it stands, for `restore()`: its shape and faces, and its place.
static func state_of(brush: DraftBrush) -> Dictionary:
	return {"geometry": brush.geometry_state(), "transform": brush.global_transform}


static func restore(brush: DraftBrush, state: Dictionary) -> void:
	if brush == null or not is_instance_valid(brush) or state.is_empty():
		return
	brush.apply_geometry_state(state["geometry"])
	brush.global_transform = state["transform"]
	brush.rebuild_preview()


## Where a drag of `raw` along `normal` lands: on a whole grid step along the
## normal, or where one of the face's corners `corners` lands on a grid plane,
## whichever is nearer. The second is what puts a sloped face down cleanly.
static func snapped_distance(
	raw: float, corners: PackedVector3Array, normal: Vector3, grid: float
) -> float:
	if grid <= 0.0:
		return raw
	var best := snappedf(raw, grid)
	for corner in corners:
		for axis in 3:
			if absf(normal[axis]) < 0.05:
				continue
			var lands := corner[axis] + normal[axis] * raw
			var candidate := (snappedf(lands, grid) - corner[axis]) / normal[axis]
			if absf(candidate - raw) < absf(best - raw):
				best = candidate
	return best


## The faces of `others` that lie in the world plane of `brush`'s face
## `face_idx`, facing the same way, as `[brush, face_idx]` pairs: the faces that
## move with it, as a wall of three brushes gets thicker as one.
static func coplanar_faces(brush: DraftBrush, face_idx: int, others: Array) -> Array:
	var out: Array = []
	var plane := world_plane(brush, face_idx)
	if plane.normal.length_squared() < 0.5:
		return out
	for other in others:
		if not (other is DraftBrush) or other == brush or not is_instance_valid(other):
			continue
		for i in (other as DraftBrush).faces.size():
			var theirs := world_plane(other, i)
			if (
				theirs.normal.dot(plane.normal) > SAME_PLANE_DOT
				and absf(theirs.d - plane.d) < SAME_PLANE_GAP
			):
				out.append([other, i])
				break
	return out


## The world plane of a face, its normal pointing out of the brush.
static func world_plane(brush: DraftBrush, face_idx: int) -> Plane:
	if face_idx < 0 or face_idx >= brush.faces.size() or brush.faces[face_idx] == null:
		return Plane()
	var local := HFConvexClip.face_plane(brush.faces[face_idx])
	if local.normal.length_squared() < 0.5:
		return Plane()
	var xform := brush.global_transform
	var normal := (xform.basis.inverse().transposed() * local.normal).normalized()
	var point := xform * (local.normal * local.d)
	return Plane(normal, normal.dot(point))


## The face's corners in world space.
static func world_corners(brush: DraftBrush, face_idx: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if face_idx < 0 or face_idx >= brush.faces.size() or brush.faces[face_idx] == null:
		return out
	for corner in (brush.faces[face_idx] as FaceData).local_verts:
		out.append(brush.global_transform * corner)
	return out


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## The local axis a box brush's face lies across, or -1 for a brush that is not a
## box, or a face that is not one of its six.
static func _box_axis(brush: DraftBrush, normal: Vector3) -> int:
	if brush.shape != DraftBrush.BrushShape.BOX or brush.faces.size() != 6:
		return -1
	for axis in 3:
		if absf(absf(normal[axis]) - 1.0) < 0.0001:
			return axis
	return -1


static func _pushed_box(
	brush: DraftBrush, axis: int, normal: Vector3, distance: float
) -> Dictionary:
	var world_step := (brush.global_transform.basis * normal).length()
	if world_step <= 0.0:
		return _refused("the brush is flattened")
	var local_distance := distance / world_step
	var size: Vector3 = brush.size
	size[axis] += local_distance
	if size[axis] < MIN_THICKNESS:
		return _refused("the brush would turn inside out")
	var position: Vector3 = (
		brush.global_position + brush.global_transform.basis * (normal * local_distance * 0.5)
	)
	return {"ok": true, "box": true, "size": size, "position": position}


## Rebuild the brush from its planes with the one moved, cut out of a box round
## everything they could bound, and hand each face the look of the face whose
## plane it lies on.
static func _pushed_planes(brush: DraftBrush, face_idx: int, distance: float) -> Dictionary:
	var faces: Array = brush.faces
	var planes: Array = []
	var corners := PackedVector3Array()
	for face in faces:
		if face == null:
			return _refused("the brush has a face missing")
		planes.append(HFConvexClip.face_plane(face))
		corners.append_array((face as FaceData).local_verts)
	var basis := brush.global_transform.basis
	if is_zero_approx(basis.determinant()):
		return _refused("the brush is flattened")
	# The distance is in metres in the level and the planes are the brush's own,
	# so a brush the gizmo scaled moved its face by the scale times it (#1998).
	# Measured across the plane, as the box path divides by its world step.
	var across: Vector3 = basis.inverse().transposed() * (planes[face_idx] as Plane).normal
	var local_distance := distance * across.length()
	planes[face_idx] = HFConvexClip.offset_plane(planes[face_idx], local_distance)
	var bounds := AABB(corners[0], Vector3.ZERO)
	for corner in corners:
		bounds = bounds.expand(corner)
	var reach := maxf(bounds.size.length(), 1.0) + absf(local_distance) * 2.0
	var outer := _box_faces(bounds.get_center(), reach)
	var cut := HFConvexClip.progressive_remainder(outer, planes)
	var built: Array = cut["remainder"]
	if not bool(cut["separated"]) or built.is_empty():
		return _refused("the brush would turn inside out")
	var origins := {}
	var used := {}
	for piece in built:
		var on := HFConvexClip.face_plane(piece)
		var source := -1
		for i in planes.size():
			var plane: Plane = planes[i]
			if (
				on.normal.dot(plane.normal) > SAME_PLANE_DOT
				and absf(on.d - plane.d) < SAME_PLANE_GAP
			):
				source = i
				break
		if source < 0:
			return _refused("the brush would open")
		origins[piece] = faces[source]
		used[source] = true
	if used.size() != faces.size() or built.size() != faces.size():
		return _refused("a face would be squeezed out of the brush")
	var interior := HFConvexClip.interior_point(built)
	if not HFConvexClip.is_convex_solid(built, interior):
		return _refused("the brush would not be one convex solid")
	var thickness := _thickness_along(built, (planes[face_idx] as Plane).normal)
	if thickness < MIN_THICKNESS:
		return _refused("the brush would be flattened")
	for piece in built:
		(piece as FaceData).copy_appearance_from(origins[piece])
	HFConvexClip.carry_onto_union(built, origins)
	var ordered: Array = []
	for i in faces.size():
		for piece in built:
			if origins[piece] == faces[i]:
				ordered.append(piece)
	return {"ok": true, "box": false, "faces": ordered}


static func _thickness_along(faces: Array, normal: Vector3) -> float:
	var low := INF
	var high := -INF
	for face in faces:
		for corner in (face as FaceData).local_verts:
			var along := normal.dot(corner)
			low = minf(low, along)
			high = maxf(high, along)
	return high - low


## The six faces of a cube `reach` across round `centre`, wound outward.
static func _box_faces(centre: Vector3, reach: float) -> Array:
	var h := reach
	var c := [
		centre + Vector3(-h, -h, -h),
		centre + Vector3(h, -h, -h),
		centre + Vector3(h, h, -h),
		centre + Vector3(-h, h, -h),
		centre + Vector3(-h, -h, h),
		centre + Vector3(h, -h, h),
		centre + Vector3(h, h, h),
		centre + Vector3(-h, h, h),
	]
	var rings := [
		[c[0], c[3], c[2], c[1]],
		[c[4], c[5], c[6], c[7]],
		[c[0], c[1], c[5], c[4]],
		[c[3], c[7], c[6], c[2]],
		[c[0], c[4], c[7], c[3]],
		[c[1], c[2], c[6], c[5]],
	]
	var out: Array = []
	for ring in rings:
		var face := FaceData.new()
		face.local_verts = PackedVector3Array(ring)
		face.ensure_geometry()
		out.append(face)
	return HFConvexClip.orient_faces_outward(out, centre)
