@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Rotate, flip and reset-rotation, driven the way the transform commands drive
## them: always through `LevelRoot`'s five-argument delegates, because those are
## the signatures undo replays.
##
## The shapes this looks for are round trips (four 90-degree rotations, or two
## flips across the same plane, must land exactly where they started) and
## winding after a mirror (a negative-determinant basis inverts face winding
## invisibly until the bake).

const FaceData = preload("res://addons/hammerforge/face_data.gd")

const AXIS_X := 0
const AXIS_Y := 1
const AXIS_Z := 2


func id() -> String:
	return "transform"


func summary() -> String:
	return "rotate/flip/reset round trips, mirror winding, pivots and nonsense angles"


func run() -> void:
	await _rotation_round_trip()
	await _flip_round_trip()
	await _mirror_winding()
	await _pivot_arithmetic()
	await _reset_rotation_keeps_scale()
	await _texture_lock_world_direction()
	await _nonsense_inputs()


func _ids(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		out.append(str(n.get_meta("brush_id", "")))
	return out


## Four quarter turns is the identity. Anything else is drift a mapper pays for
## by nudging the brush back by hand every time they rotate it.
func _rotation_round_trip() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 32, 16), Vector3(100, 0, -40))
	var ids := _ids([b])
	var before := HFVibe.describe_brushes(root)
	for _i in range(4):
		root.rotate_managed_nodes(ids, [], AXIS_Y, 90.0, Vector3.ZERO)
	await frame()
	var after := HFVibe.describe_brushes(root)
	note("four 90 deg yaw about origin", "%s -> %s" % [b.global_position, b.global_position])
	diff_levels(
		{"brushes": before}, {"brushes": after}, "four 90 deg yaw rotations", {"brushes": 334}
	)

	# And the same about the brush's own centre, which is the pivot the dock
	# uses by default.
	var c = box(root, Vector3(48, 48, 48), Vector3(-200, 16, 0))
	var cid := _ids([c])
	var pivot: Vector3 = root.resolve_transform_pivot(cid, [])
	var start: Vector3 = c.global_position
	for _i in range(4):
		root.rotate_managed_nodes(cid, [], AXIS_X, 90.0, pivot)
	await frame()
	if not c.global_position.is_equal_approx(start):
		flag(
			"four pitch rotations about the selection pivot move the brush",
			"%s -> %s" % [start, c.global_position]
		)
	else:
		note("four 90 deg pitch about selection pivot", "position held at %s" % start)


## Mirroring twice across the same plane is the identity too.
func _flip_round_trip() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(96, 24, 48), Vector3(64, 0, 0))
	var ids := _ids([b])
	b.faces[0].material_idx = 3
	b.faces[1].material_idx = 7
	var before := HFVibe.describe_brushes(root)
	root.flip_managed_nodes(ids, [], AXIS_X, Vector3.ZERO)
	await frame()
	root.flip_managed_nodes(ids, [], AXIS_X, Vector3.ZERO)
	await frame()
	var after := HFVibe.describe_brushes(root)
	diff_levels({"brushes": before}, {"brushes": after}, "two flips across the same plane")


## A mirror has a negative determinant, and every face that survives it comes
## back wound the other way unless something re-winds them.
func _mirror_winding() -> void:
	var root: Node3D = await fresh_root()
	for shape in range(0, 6):
		var info := {"shape": shape, "size": Vector3(64, 64, 64), "center": Vector3.ZERO}
		if shape != 0:
			info["sides"] = 8
		var b = root.create_brush_from_info(info)
		if b == null:
			note("shape %d" % shape, "create_brush_from_info returned null")
			continue
		var before_inward := HFVibe.inward_face_count(b)
		root.flip_managed_nodes(_ids([b]), [], AXIS_Z, Vector3.ZERO)
		await frame()
		var after_inward := HFVibe.inward_face_count(b)
		var det: float = b.global_transform.basis.determinant()
		note(
			"shape %d flipped" % shape,
			"inward %d -> %d, basis determinant %.3f" % [before_inward, after_inward, det]
		)
		if after_inward > before_inward:
			flag(
				"flipping shape %d leaves %d inward faces" % [shape, after_inward],
				"was %d before the flip; determinant %.3f" % [before_inward, det]
			)
		if det < 0.0:
			flag(
				"flipping shape %d leaves a negative-determinant basis" % shape,
				"determinant %.3f -- every face renders and bakes inside out from here" % det
			)
		root.delete_brush(b)
		await frame()


## Rotating about a distant pivot is an orbit: the distance to the pivot is what
## must not move.
func _pivot_arithmetic() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(32, 32, 32), Vector3(256, 0, 0))
	var ids := _ids([b])
	var pivot := Vector3.ZERO
	var r0: float = b.global_position.distance_to(pivot)
	root.rotate_managed_nodes(ids, [], AXIS_Y, 37.5, pivot)
	await frame()
	var r1: float = b.global_position.distance_to(pivot)
	note("orbit radius about origin", "%.4f -> %.4f" % [r0, r1])
	if absf(r1 - r0) > 0.001:
		flag("rotating about a pivot changes the orbit radius", "%.4f -> %.4f" % [r0, r1])
	if HFVibe.inward_face_count(b) > 0:
		flag(
			"a 37.5 degree rotation leaves inward faces",
			"%d faces wound inward" % HFVibe.inward_face_count(b)
		)


## `reset_rotation` documents that it keeps the scale Godot's gizmo wrote, so
## drive it the way the gizmo does -- set `rotation` and `scale` on the node.
func _reset_rotation_keeps_scale() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 64, 64))
	var ids := _ids([b])
	b.position = Vector3(10, 0, 0)
	b.rotation = Vector3(0.3, 0.6, 0.1)
	b.scale = Vector3(2.0, 0.5, 1.5)
	await frame()
	root.reset_managed_rotation(ids)
	await frame()
	var scale: Vector3 = b.global_transform.basis.get_scale()
	var euler: Vector3 = b.global_transform.basis.get_euler()
	note("after reset_rotation", "scale %s euler %s pos %s" % [scale, euler, b.global_position])
	if not scale.is_equal_approx(Vector3(2.0, 0.5, 1.5)):
		flag("reset_rotation changed the scale", "expected (2, 0.5, 1.5), got %s" % scale)
	if euler.length() > 0.001:
		flag("reset_rotation left a rotation behind", "euler %s" % euler)


## What texture lock does to a face under a yaw, against what #355 settled it
## should do: a face whose projection plane the turn keeps holds its world
## texture direction, and a face the turn swings out from under its projection
## carries its texture round with it, upright.
##
## The projection decides which of the two a face is, so the faces are given the
## Box UV projection the dock's re-project button applies -- a face left on the
## PLANAR_Z default is neither, and that is #463 rather than this.
func _texture_lock_world_direction() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(128, 64, 32))
	var ids := _ids([b])
	note("texture lock enabled", root.transform_system._texture_lock_enabled())

	# First, the brush exactly as the Draw tool makes it.
	var default_locked: bool = b.faces[2].adjust_uvs_for_rotation(
		Basis(Vector3.UP, deg_to_rad(90.0))
	)
	note("a default (PLANAR_Z) top face is compensated under a yaw", default_locked)
	if not default_locked:
		known(
			463,
			"texture lock declines every face of a brush nobody has re-projected",
			(
				"FaceData.uv_projection defaults to PLANAR_Z on all six faces, and"
				+ " adjust_uvs_for_rotation() refuses any face whose projection plane the turn"
				+ " takes away -- which under a yaw is every face of a default box. Texture"
				+ " lock therefore does nothing at all until the mapper re-projects."
			)
		)

	for face in b.faces:
		face.uv_projection = FaceData.UVProjection.BOX_UV
		face.custom_uvs = PackedVector2Array()
	b.rebuild_preview()
	await frame()

	var before: Array = []
	var normals: Array = []
	for i in range(b.faces.size()):
		before.append(_u_direction(b, i))
		normals.append((b.global_transform.basis * b.faces[i].normal).normalized())
	root.rotate_managed_nodes(ids, [], AXIS_Y, 90.0, Vector3.ZERO)
	await frame()
	var turn := Basis(Vector3.UP, deg_to_rad(90.0))
	for i in range(b.faces.size()):
		var n0: Vector3 = before[i]
		var n1: Vector3 = _u_direction(b, i)
		if n0 == Vector3.ZERO or n1 == Vector3.ZERO:
			note("face %d" % i, "no measurable U direction (before %s after %s)" % [n0, n1])
			continue
		var normal: Vector3 = normals[i]
		var turns_in_its_own_plane: bool = absf(normal.dot(Vector3.UP)) > 0.9
		var locked: bool = n1.dot(n0) > 0.999
		var carried: bool = n1.dot((turn * n0).normalized()) > 0.999
		note(
			"face %d (world normal %s)" % [i, normal.snapped(Vector3.ONE * 0.01)],
			"locked %s, carried %s" % [locked, carried]
		)
		if turns_in_its_own_plane and not locked:
			flag(
				"a yaw moves the texture on face %d, which turns in its own plane" % i,
				(
					(
						"world normal %s: the projection plane is the one the turn keeps, so the"
						+ " compensation should hold the texture where it was. U went from %s to %s."
					)
					% [normal.snapped(Vector3.ONE * 0.01), n0, n1]
				)
			)
		elif not turns_in_its_own_plane and not carried:
			flag(
				"a yaw tips the texture on face %d" % i,
				(
					(
						"world normal %s: the wall swings round, so its texture should go with it"
						+ " upright. U went from %s to %s, and carrying it would be %s."
					)
					% [normal.snapped(Vector3.ONE * 0.01), n0, n1, (turn * n0).normalized()]
				)
			)


## World-space direction of increasing U across one face, or zero when the face
## is degenerate. Read off the face's own triangulated UVs, not from anything
## the UV code claims about itself.
func _u_direction(brush: Node3D, face_idx: int) -> Vector3:
	var tri: Dictionary = brush.faces[face_idx].triangulate()
	var verts: PackedVector3Array = tri["verts"]
	var uvs: PackedVector2Array = tri["uvs"]
	if verts.size() < 3 or uvs.size() != verts.size():
		return Vector3.ZERO
	var basis: Basis = brush.global_transform.basis
	var v0: Vector3 = basis * verts[0]
	var e1: Vector3 = basis * verts[1] - v0
	var e2: Vector3 = basis * verts[2] - v0
	var n: Vector3 = e1.cross(e2)
	if n.length() < 0.0001:
		return Vector3.ZERO
	# g . e1 = du1, g . e2 = du2, g . n = 0.
	var m := Basis(Vector3(e1.x, e2.x, n.x), Vector3(e1.y, e2.y, n.y), Vector3(e1.z, e2.z, n.z))
	if absf(m.determinant()) < 0.000001:
		return Vector3.ZERO
	var g: Vector3 = m.inverse() * Vector3(uvs[1].x - uvs[0].x, uvs[2].x - uvs[0].x, 0.0)
	return g.normalized() if g.length() > 0.0 else Vector3.ZERO


## Numbers no dock would send, which undo replay and a script can both send.
func _nonsense_inputs() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 64, 64))
	var ids := _ids([b])
	var cases := [
		["NAN angle", func(): root.rotate_managed_nodes(ids, [], AXIS_Y, NAN, Vector3.ZERO)],
		["INF angle", func(): root.rotate_managed_nodes(ids, [], AXIS_Y, INF, Vector3.ZERO)],
		["NAN pivot", func(): root.rotate_managed_nodes(ids, [], AXIS_Y, 45.0, Vector3(NAN, 0, 0))],
		["INF flip pivot", func(): root.flip_managed_nodes(ids, [], AXIS_X, Vector3(INF, 0, 0))],
		["axis index 9", func(): root.rotate_managed_nodes(ids, [], 9, 45.0, Vector3.ZERO)],
		["axis index -1", func(): root.flip_managed_nodes(ids, [], -1, Vector3.ZERO)],
	]
	for case in cases:
		var label: String = case[0]
		var before: Transform3D = b.global_transform
		(case[1] as Callable).call()
		await frame()
		var xf: Transform3D = b.global_transform
		var finite: bool = (
			xf.origin.is_finite() and xf.basis.determinant() == xf.basis.determinant()
		)
		note(label, "pos %s det %s" % [xf.origin, xf.basis.determinant()])
		if not finite:
			known(
				335,
				"%s leaves the brush with a non-finite transform" % label,
				"origin %s, determinant %s" % [xf.origin, xf.basis.determinant()]
			)
			# Put it back so the next case starts from something sane.
			b.global_transform = before
			await frame()
		for problem in HFVibe.check_invariants(root):
			known(335, "%s broke an invariant" % label, problem)
