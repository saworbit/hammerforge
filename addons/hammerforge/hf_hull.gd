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
@warning_ignore_restore("shadowed_global_identifier")

## How far a corner may sit off a face's plane and still be on it.
const ON_PLANE := 0.01
## Points closer than this are one point.
const SAME_POINT := 0.001

const TOO_FEW := "Place at least 4 points, not all in one plane"
const FLAT := "The points lie in one plane, so they hold no solid"


## The hull of `points`: `{"ok": true, "faces": Array[FaceData], "corners":
## PackedVector3Array}`, the faces in the points' own space, or `{"ok": false,
## "reason": String}` for fewer than four points or points in one plane.
static func of(points: PackedVector3Array) -> Dictionary:
	var unique := unique_points(points)
	if unique.size() < 4:
		return {"ok": false, "reason": TOO_FEW}
	if is_flat(unique):
		return {"ok": false, "reason": FLAT}
	var corners := _corners(unique)
	var faces := _faces(corners)
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


## One face for each plane through three of `corners` that has every corner on or
## behind it, holding every corner on it.
static func _faces(corners: PackedVector3Array) -> Array:
	var planes: Array[Plane] = []
	var faces: Array = []
	var count := corners.size()
	for i in count:
		for j in range(i + 1, count):
			for k in range(j + 1, count):
				var normal := (corners[j] - corners[i]).cross(corners[k] - corners[i])
				if normal.length_squared() < 1e-8:
					continue
				var plane := Plane(normal.normalized(), corners[i])
				if _known(planes, plane) or _known(planes, -plane):
					continue
				var side := _side(corners, plane)
				if side == 0:
					continue
				if side < 0:
					plane = -plane
				planes.append(plane)
				var on_it := PackedVector3Array()
				for corner in corners:
					if absf(plane.distance_to(corner)) <= ON_PLANE:
						on_it.append(corner)
				var face := FaceData.new()
				face.local_verts = HFConvexClip.sort_coplanar_cw(on_it, plane.normal)
				face.normal = plane.normal
				face.ensure_geometry()
				faces.append(face)
	return faces


## 1 when every corner is on or behind `plane`, -1 when every one is on or in
## front of it, 0 when they are on both sides.
static func _side(corners: PackedVector3Array, plane: Plane) -> int:
	var behind := true
	var ahead := true
	for corner in corners:
		var distance := plane.distance_to(corner)
		if distance > ON_PLANE:
			behind = false
		if distance < -ON_PLANE:
			ahead = false
		if not behind and not ahead:
			return 0
	return 1 if behind else -1


static func _known(planes: Array[Plane], plane: Plane) -> bool:
	for known in planes:
		if known.normal.dot(plane.normal) > 0.9999 and absf(known.d - plane.d) < ON_PLANE:
			return true
	return false
