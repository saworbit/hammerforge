@tool
extends RefCounted
## Where Hidden faces belong and where they do not (#1719): the faces of a
## selection that lie flat against a solid brush, for Hide Faces Against Solids,
## and the Hidden faces with open space in front of them, for Validate.
##
## A face lies against another when the two are on one plane, facing each other,
## and the other covers all of it. The other brush then fills the space in front
## of the face, so nobody can see it from anywhere. A face only partly covered,
## or covered by two faces between them, is left alone: hiding it could hide the
## part somebody sees.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const HFBrushEntity = preload("hf_brush_entity.gd")
const HFConvexClip = preload("hf_convex_clip.gd")
const HFHiddenFaces = preload("hf_hidden_faces.gd")
@warning_ignore_restore("shadowed_global_identifier")

## How far apart two planes may be and still be one, in metres.
const SAME_PLANE := 0.001
## How close to opposite two faces' normals have to be to face each other.
const FACING := -0.9999
## How much of a face may stick out past the face it lies on and still count as
## covered, in square metres: rounding, not a sliver anybody sees.
const UNCOVERED := 0.0001
## How far in front of a Hidden face Validate looks for a brush, in metres.
const REACH := 0.05
## The brush entities that draw like world brushes. A mover is left out: what is
## behind a door shows when it opens.
const DRAWN_CLASSES := ["func_detail", "func_wall"]


## The faces of `brushes` lying flat against a solid brush, brush key -> face
## indices, the shape `LevelRoot.face_selection` has. Faces already Hidden are
## left out.
static func against_solids(root: Node, brushes: Array) -> Dictionary:
	var solids := solid_brushes(root)
	var out: Dictionary = {}
	for brush in brushes:
		if not is_solid(root, brush):
			continue
		var bounds := _world_bounds(brush).grow(SAME_PLANE * 2.0)
		var others: Array = []
		for other in solids:
			if other != brush and bounds.intersects(_world_bounds(other)):
				others.append(other)
		if others.is_empty():
			continue
		var found: Array = []
		for i in brush.faces.size():
			var face = brush.faces[i]
			if face == null or face.is_hidden() or face.local_verts.size() < 3:
				continue
			if _covered(_world_face(brush, face), others):
				found.append(i)
		if not found.is_empty():
			out[_key_of(brush)] = found
	return out


## The Hidden faces with no brush right in front of them, each `[brush, face
## index]`: a hint that one may be seen.
static func facing_open_space(root: Node) -> Array:
	var solids := solid_brushes(root)
	var out: Array = []
	for brush in _all_brushes(root):
		for i in brush.faces.size():
			var face = brush.faces[i]
			if face == null or not face.is_hidden() or face.local_verts.size() < 3:
				continue
			var placed := _world_face(brush, face)
			var ahead: Vector3 = _centre(placed["points"]) + placed["normal"] * REACH
			var filled := false
			for other in solids:
				if other != brush and _holds(other, ahead):
					filled = true
					break
			if not filled:
				out.append([brush, i])
	return out


## The brushes a face can lie against unseen: solids, drawn and not a cut.
static func solid_brushes(root: Node) -> Array:
	var out: Array = []
	for brush in _all_brushes(root):
		if is_solid(root, brush):
			out.append(brush)
	return out


static func is_solid(root: Node, brush: Variant) -> bool:
	if not (brush is DraftBrush) or not is_instance_valid(brush):
		return false
	var draft := brush as DraftBrush
	if draft.operation != CSGShape3D.OPERATION_UNION:
		return false
	if root.draft_brushes_node == null or draft.get_parent() != root.draft_brushes_node:
		return false
	var entity_class := HFBrushEntity.entity_class(draft)
	return entity_class == "" or DRAWN_CLASSES.has(entity_class)


static func _all_brushes(root: Node) -> Array:
	var out: Array = []
	if root == null or root.draft_brushes_node == null:
		return out
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush and not child.is_queued_for_deletion():
			out.append(child)
	return out


static func _key_of(brush: DraftBrush) -> String:
	return brush.brush_id if brush.brush_id != "" else str(brush.get_instance_id())


## A face in the level: its corners, its outward normal and its plane's distance
## from the origin.
static func _world_face(brush: DraftBrush, face: Object) -> Dictionary:
	var place := brush.global_transform
	var points := PackedVector3Array()
	for corner in face.local_verts:
		points.append(place * corner)
	var normal: Vector3 = face.normal_through(place.basis)
	return {"points": points, "normal": normal, "d": normal.dot(points[0])}


static func _covered(placed: Dictionary, others: Array) -> bool:
	var area := HFHiddenFaces.polygon_area(Basis.IDENTITY, placed["points"])
	if area <= UNCOVERED:
		return false
	for other in others:
		for face in other.faces:
			if face == null or face.local_verts.size() < 3:
				continue
			var against := _world_face(other, face)
			if (placed["normal"] as Vector3).dot(against["normal"]) > FACING:
				continue
			if absf(float(against["d"]) + float(placed["d"])) > SAME_PLANE:
				continue
			var inside := _clipped_to(placed["points"], against)
			if area - HFHiddenFaces.polygon_area(Basis.IDENTITY, inside) <= UNCOVERED:
				return true
	return false


## The part of `points` inside the face `against`, both on one plane.
static func _clipped_to(points: PackedVector3Array, against: Dictionary) -> PackedVector3Array:
	var corners: PackedVector3Array = against["points"]
	var normal: Vector3 = against["normal"]
	var middle := _centre(corners)
	var kept := points
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		var across := (b - a).cross(normal)
		if across.length_squared() < 1e-12:
			continue
		across = across.normalized()
		if across.dot(middle - a) < 0.0:
			across = -across
		var clipped: Dictionary = HFConvexClip.clip_polygon(
			kept, PackedVector2Array(), Plane(across, a), true, SAME_PLANE * 0.01
		)
		kept = clipped["verts"]
		if kept.size() < 3:
			return PackedVector3Array()
	return kept


## Whether `point` is inside the convex brush `brush`.
static func _holds(brush: DraftBrush, point: Vector3) -> bool:
	var any := false
	for face in brush.faces:
		if face == null or face.local_verts.size() < 3:
			continue
		var placed := _world_face(brush, face)
		if (placed["normal"] as Vector3).dot(point) - float(placed["d"]) > 0.0:
			return false
		any = true
	return any


static func _centre(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	return sum / float(maxi(points.size(), 1))


static func _world_bounds(brush: DraftBrush) -> AABB:
	var place := brush.global_transform
	var bounds := AABB()
	var first := true
	for face in brush.faces:
		if face == null:
			continue
		for corner in face.local_verts:
			var point: Vector3 = place * corner
			if first:
				bounds = AABB(point, Vector3.ZERO)
				first = false
			else:
				bounds = bounds.expand(point)
	return bounds
