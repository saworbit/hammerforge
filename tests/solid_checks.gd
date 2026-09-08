extends RefCounted

## Shared measurements for "is this actually a convex solid?".
##
## Not a test script — the suite collects `test_*.gd`, and this is preloaded by
## the generator tests that all need the same four questions answered: is it
## closed, does every face point away from the inside, how big is it, and where
## is its middle.
##
## Winding is measured rather than assumed everywhere in this codebase, because a
## solid that bakes inside out looks perfectly correct in the editor and is
## invisible until it is baked.


static func centroid(faces: Array) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for face in faces:
		for v in face.local_verts:
			total += v
			count += 1
	return total / float(count) if count > 0 else Vector3.ZERO


static func key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 100.0), roundi(point.y * 100.0), roundi(point.z * 100.0)]


## Edges used by anything other than exactly two faces. Zero means closed.
static func open_edge_count(faces: Array) -> int:
	var counts := {}
	for face in faces:
		var verts: PackedVector3Array = face.local_verts
		var n := verts.size()
		for i in n:
			var a := key(verts[i])
			var b := key(verts[(i + 1) % n])
			var edge: String = a + "|" + b if a < b else b + "|" + a
			counts[edge] = int(counts.get(edge, 0)) + 1
	var open := 0
	for edge in counts:
		if counts[edge] != 2:
			open += 1
	return open


## The fraction of faces whose clockwise-from-outside normal actually points away
## from the solid's own middle. One means every face; anything less bakes wrong.
static func outward_ratio(faces: Array) -> float:
	if faces.is_empty():
		return -1.0
	var centre := centroid(faces)
	var outward := 0
	var counted := 0
	for face in faces:
		var verts: PackedVector3Array = face.local_verts
		if verts.size() < 3:
			continue
		var a: Vector3 = verts[0]
		var normal: Vector3 = (verts[2] - a).cross(verts[1] - a)
		if normal.length() < 0.000001:
			continue
		var face_centre := Vector3.ZERO
		for v in verts:
			face_centre += v
		face_centre /= float(verts.size())
		var to_face: Vector3 = face_centre - centre
		if to_face.length() < 0.000001:
			continue
		counted += 1
		if normal.normalized().dot(to_face.normalized()) > 0.0:
			outward += 1
	return float(outward) / float(counted) if counted > 0 else -1.0


## Every vertex of the solid lies on or behind every one of its face planes.
## A solid that fails this is not convex, and every brush here has to be.
static func is_convex(faces: Array, tolerance := 0.01) -> bool:
	var centre := centroid(faces)
	for face in faces:
		var verts: PackedVector3Array = face.local_verts
		if verts.size() < 3:
			continue
		var a: Vector3 = verts[0]
		var normal: Vector3 = (verts[2] - a).cross(verts[1] - a)
		if normal.length() < 0.000001:
			continue
		normal = normal.normalized()
		if normal.dot(centre - a) > 0.0:
			normal = -normal
		var d := normal.dot(a)
		for other in faces:
			for v in other.local_verts:
				if normal.dot(v) - d > tolerance:
					return false
	return true


static func bounds(faces: Array) -> AABB:
	var box := AABB()
	var seeded := false
	for face in faces:
		for v in face.local_verts:
			if seeded:
				box = box.expand(v)
			else:
				box = AABB(v, Vector3.ZERO)
				seeded = true
	return box


## The bounds of every piece of a structure together.
static func structure_bounds(pieces: Array) -> AABB:
	var box := AABB()
	var seeded := false
	for piece in pieces:
		for face in piece:
			for v in face.local_verts:
				if seeded:
					box = box.expand(v)
				else:
					box = AABB(v, Vector3.ZERO)
					seeded = true
	return box


## Assert-friendly one-liner: what is wrong with this solid, or "" if nothing is.
static func describe_problem(faces: Array) -> String:
	if faces.size() < 4:
		return "only %d faces; a solid needs at least four" % faces.size()
	if open_edge_count(faces) != 0:
		return "%d open edges" % open_edge_count(faces)
	if not is_convex(faces):
		return "not convex"
	var ratio := outward_ratio(faces)
	if ratio < 0.9999:
		return "only %.0f%% of faces point outward" % (ratio * 100.0)
	return ""
