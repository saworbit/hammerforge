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
##
## The middle and the bounds are the addon's own measures, the ones the bridge's
## hf_measure answers with (#1649), so a test and an agent measure alike.

const HFSolidMeasure = preload("res://addons/hammerforge/hf_solid_measure.gd")


static func centroid(faces: Array) -> Vector3:
	return HFSolidMeasure.vertex_centre(faces)


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
## Validate asks the same question of every brush (#1869).
static func outward_ratio(faces: Array) -> float:
	return HFSolidMeasure.outward_ratio(faces)


## Every vertex of the solid lies on or behind every one of its face planes.
## A solid that fails this is not convex, and every brush here has to be.
static func is_convex(faces: Array, tolerance := 0.01) -> bool:
	return HFSolidMeasure.is_convex(faces, tolerance)


static func bounds(faces: Array) -> AABB:
	return HFSolidMeasure.bounds(faces)


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
