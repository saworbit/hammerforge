@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Structures and the cuts that join or wrap brushes, measured after the late
## October work on them.
##
## A new structure with nothing selected stands on the floor (#1827): each type at
## its defaults is lifted by `stand_height()` and its lowest solid corner read off
## the pieces. A path builds trim beside its stairs or railings (#1849): each
## combination, straight and smooth, built into a level, every piece a closed
## solid and no point of a trim strip inside a tread, a rail or the path. Carve
## and Hull make only closed brushes (#1845): a tilted cutter and turned brushes,
## near the origin and 3 km out, the carved volume against the box less what the
## cutter takes, and the hull of two turned boxes against the 4 x 1 x 1 box it
## is. Merge keeps the sculpts of displaced faces (#1909), "a power finer so every
## old grid point is still a point of it": every old grid point of the joined
## tops looked up on the merged surface, for two halves and for the joins that
## are not two halves.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func id() -> String:
	return "structure-paths"


func summary() -> String:
	return "structures on the floor, trim beside stairs and rails, carve and hull closed, merged sculpts"


func expected_issues() -> Array[int]:
	return [1971, 1972]


func run() -> void:
	await _stand_heights()
	await _trim_with_extras()
	await _carve_measured()
	await _hull_far_and_turned()
	await _merge_sculpts()


func _bid(n: Node) -> String:
	return str(n.get_meta("brush_id", ""))


func _brushes_since(root: Node3D, before: Array) -> Array:
	var out: Array = []
	for b in root._iter_managed_brush_nodes():
		if not before.has(b):
			out.append(b)
	return out


# ---------------------------------------------------------------------------
# On the floor
# ---------------------------------------------------------------------------


func _stand_heights() -> void:
	var root: Node3D = await fresh_root()
	var x := 0.0
	for type in HFGeneratorSystem.known_types():
		var s: Dictionary = HFGeneratorSystem.default_settings(type)
		var lift := HFGeneratorSystem.stand_height(type, s)
		var before: Array = root._iter_managed_brush_nodes()
		var made = root.create_generator(type, s, Transform3D(Basis.IDENTITY, Vector3(x, lift, 0)))
		var lowest := INF
		for b in _brushes_since(root, before):
			if b.operation == CSGShape3D.OPERATION_SUBTRACTION:
				continue
			for f in b.faces:
				for v in f.local_verts:
					lowest = minf(lowest, (b.global_transform * v).y)
		note(type, "%s, lifted %.3f, lowest solid corner %.4f" % [made.ok, lift, lowest])
		if not made.ok or absf(lowest) > 0.001:
			flag("A new %s does not stand on the floor" % type, "lowest solid corner %.4f" % lowest)
		x += 30.0
	await drop_root(root)


# ---------------------------------------------------------------------------
# Trim beside stairs and railings
# ---------------------------------------------------------------------------


## Whether `point` is behind every face of `brush` by more than `margin`.
func _inside(brush: Node, point: Vector3, margin: float) -> bool:
	var local: Vector3 = brush.global_transform.affine_inverse() * point
	var centre := Vector3.ZERO
	var n := 0
	for f in brush.faces:
		for v in f.local_verts:
			centre += v
			n += 1
	centre /= maxf(1.0, n)
	for f in brush.faces:
		if f.local_verts.size() < 3:
			continue
		var normal: Vector3 = f.normal.normalized()
		if normal.dot(f.local_verts[0] - centre) < 0.0:
			normal = -normal
		if normal.dot(local - f.local_verts[0]) > -margin:
			return false
	return true


## The middle of `brush` and a point nine tenths of the way to each corner.
func _samples(brush: Node) -> Array:
	var centre := Vector3.ZERO
	var corners: Array = []
	for f in brush.faces:
		for v in f.local_verts:
			var w: Vector3 = brush.global_transform * v
			corners.append(w)
			centre += w
	centre /= maxf(1.0, corners.size())
	var out: Array = [centre]
	for c in corners:
		out.append(centre.lerp(c, 0.9))
	return out


func _trim_with_extras() -> void:
	var names := ["None", "Stairs", "Railings"]
	for smooth in [false, true]:
		for extra in [
			HFPathTool.PathExtra.NONE, HFPathTool.PathExtra.STAIRS, HFPathTool.PathExtra.RAILING
		]:
			for trim_flip in [false, true]:
				await _trim_case(smooth, extra, trim_flip, names[extra])


## One path that climbs 2 m and turns twice, built as Enter builds it: the path's
## own pieces, then the extras, the trim among them.
func _trim_case(smooth: bool, extra: int, trim_flip: bool, extra_name: String) -> void:
	var root: Node3D = await fresh_root()
	var tool = HFPathTool.new()
	tool.root = root
	tool.set_setting("path_width", 2.0)
	tool.set_setting("path_extra", extra)
	tool.set_setting("path_add_trim", true)
	tool.set_setting("trim_flip", trim_flip)
	if smooth:
		tool.set_setting("path_curve", HFPathTool.CurveMode.SMOOTH)
	tool._waypoints = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(16, 2, 0), Vector3(28, 2, 10), Vector3(44, 2, 12)]
	)
	var label := (
		"%s path, %s and trim%s"
		% ["smooth" if smooth else "straight", extra_name, ", trim flipped" if trim_flip else ""]
	)
	var refusal: String = tool._refusal()
	if refusal != "":
		flag("A path with trim beside %s is refused" % extra_name, refusal)
		await drop_root(root)
		return
	var width: float = tool.get_setting("path_width")
	var height: float = tool.get_setting("path_height")
	var custom: int = LevelRootType.BrushShape.CUSTOM
	var trim_infos: Array = tool._build_trim(width, "g", custom)
	var own: Array = []
	var others: Array = []
	var trim: Array = []
	for info in tool._band_pieces(tool._band_for(width), height, width, "g"):
		own.append(root.create_brush_from_info(info))
	for info in tool._extras(width, height, "g", custom):
		var is_trim := trim_infos.any(func(t): return t.get("center") == info.get("center"))
		var made = root.create_brush_from_info(info)
		(trim if is_trim else others).append(made)
	var problems := HFVibe.check_solids(root)
	var in_extras := 0
	var in_path := 0
	for t in trim:
		for point in _samples(t):
			for o in others:
				if _inside(o, point, 0.001):
					in_extras += 1
			for o in own:
				if _inside(o, point, 0.001):
					in_path += 1
	note(
		label,
		(
			"%d path pieces, %d extras, %d trim; trim points inside an extra %d, inside the path %d; %d not closed"
			% [own.size(), others.size(), trim.size(), in_extras, in_path, problems.size()]
		)
	)
	if trim.is_empty() or in_extras > 0 or in_path > 0 or not problems.is_empty():
		flag(
			"Trim built beside %s overlaps it or is not closed" % extra_name,
			(
				"%s: %d trim, %d in an extra, %d in the path, %s"
				% [label, trim.size(), in_extras, in_path, problems]
			)
		)
	await drop_root(root)


# ---------------------------------------------------------------------------
# Carve, measured
# ---------------------------------------------------------------------------


## A 4 x 2 x 4 box carved by a 12-sided cylinder 1 across tilted 20 degrees through
## it, and by a 1 x 3 x 1 box with both turned 45. The tilted cylinder crosses the
## box top to bottom, so it takes its section times 2 / cos 20.
func _carve_measured() -> void:
	for at in [Vector3.ZERO, Vector3(3000.3, 0, -1980.7)]:
		var root: Node3D = await fresh_root()
		var host = box(root, Vector3(4, 2, 4), at + Vector3(0, 1, 0))
		var centre: Vector3 = at + Vector3(0.3, 1, -0.4)
		var cylinder = root.create_brush_from_info(
			{"shape": 1, "size": Vector3(1, 6, 1), "center": centre, "sides": 12}
		)
		var section := HFVibe.solid_volume(cylinder.faces) / 6.0
		var cylinder_id := _bid(cylinder)
		root.rotate_managed_nodes([cylinder_id], [], 0, 20.0, centre)
		var made = root.carve_with_brush(cylinder_id)
		await frame()
		var expected := 32.0 - section * 2.0 / cos(deg_to_rad(20.0))
		_carve_result(root, cylinder_id, made, expected, "a tilted cylinder at %s" % at)
		await drop_root(root)

		root = await fresh_root()
		host = box(root, Vector3(4, 2, 4), at + Vector3(0, 1, 0))
		var cutter = box(root, Vector3(1, 3, 1), at + Vector3(0.7, 1, 0.2))
		var cutter_id := _bid(cutter)
		root.rotate_managed_nodes([_bid(host), cutter_id], [], 1, 45.0, at)
		made = root.carve_with_brush(cutter_id)
		await frame()
		_carve_result(root, cutter_id, made, 30.0, "a box, both turned 45, at %s" % at)
		await drop_root(root)


## The pieces left once the cutter, which Carve takes away, is set aside.
func _carve_result(root: Node3D, cutter_id: String, made, expected: float, label: String) -> void:
	var volume := 0.0
	var open := 0
	var inward := 0
	var pieces := 0
	for n in root._iter_managed_brush_nodes():
		if _bid(n) == cutter_id:
			continue
		pieces += 1
		volume += HFVibe.solid_volume(n.faces) * absf(n.global_basis.determinant())
		open += HFVibe.open_edge_count(n.faces)
		inward += HFVibe.inward_face_count(n)
	note(
		"carve by " + label,
		(
			"%s, %d pieces, volume %.4f (expected %.4f), %d open edges, %d turned in"
			% [made.ok, pieces, volume, expected, open, inward]
		)
	)
	if not made.ok or open > 0 or inward > 0 or absf(volume - expected) > 0.005:
		flag(
			"Carve leaves pieces that are not the box less the cutter: " + label,
			[volume, expected, open, inward]
		)


# ---------------------------------------------------------------------------
# Hull, far out and turned
# ---------------------------------------------------------------------------


## Two 1 x 1 x 1 boxes 3 apart, turned together about the first's foot: their hull
## is a 4 x 1 x 1 box, six faces, closed. Hull carries the second box's corners
## into the first's space through the two world transforms; 3 km out a float
## carries a few ten-thousandths of rounding, more than the hull's ON_FACE of
## 0.0001, and the faces it finds no longer close.
func _hull_far_and_turned() -> void:
	var broken: Array = []
	for c in [
		[Vector3(0.3, 0, -0.7), 45.0],
		[Vector3(3000.3, 0, -1980.7), 0.0],
		[Vector3(3000.3, 0, -1980.7), 45.0],
		[Vector3(3000.3, 0, -1980.7), 7.0],
		[Vector3(8000.3, 0, -5280.7), 30.0],
	]:
		var at: Vector3 = c[0]
		var root: Node3D = await fresh_root()
		var a = box(root, Vector3(1, 1, 1), at + Vector3(0, 0.5, 0))
		var b = box(root, Vector3(1, 1, 1), at + Vector3(3, 0.5, 0))
		if c[1] != 0.0:
			root.rotate_managed_nodes([_bid(a), _bid(b)], [], 1, c[1], at)
		# Where the hull reads the second box: carried into the first's space.
		var carried: Vector3 = (a.global_transform.affine_inverse() * b.global_transform).origin
		var drift := carried.distance_to(Vector3(3, 0, 0))
		var made = root.hull_brushes_by_ids([_bid(a), _bid(b)])
		var line := ""
		for n in root._iter_managed_brush_nodes():
			var open := HFVibe.open_edge_count(n.faces)
			var volume := HFVibe.solid_volume(n.faces)
			line = (
				"%d faces, %d open edges, %d turned in, volume %.4f"
				% [n.faces.size(), open, HFVibe.inward_face_count(n), volume]
			)
			if open > 0 or absf(volume - 4.0) > 0.01:
				broken.append("turned %d at %s: %s" % [c[1], at, line])
		note(
			"hull of two boxes turned %d at %s" % [c[1], at],
			"%s: %s; the second box read %.5f off where it is" % [made.user_text(), line, drift]
		)
		await drop_root(root)
	if not broken.is_empty():
		known(
			1971,
			"Hull makes a brush that is not closed when the brushes are turned and far out",
			broken
		)


# ---------------------------------------------------------------------------
# Merge and sculpts
# ---------------------------------------------------------------------------


## The corners of the triangles `brush`'s up-facing faces draw, in the level.
func _top_points(brush: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	for face in brush.faces:
		if face.normal.y < 0.9:
			continue
		for vertex in face.triangulate().get("verts", PackedVector3Array()):
			out.append(brush.global_transform * vertex)
	return out


## The height of the surface `tris` (corners three at a time) above (x, z), or NAN.
func _height_at(tris: PackedVector3Array, x: float, z: float) -> float:
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var v0 := Vector2(b.x - a.x, b.z - a.z)
		var v1 := Vector2(c.x - a.x, c.z - a.z)
		var v2 := Vector2(x - a.x, z - a.z)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-9:
			continue
		var s := (v2.x * v1.y - v1.x * v2.y) / den
		var t := (v0.x * v2.y - v2.x * v0.y) / den
		if s >= -1e-5 and t >= -1e-5 and s + t <= 1.00001:
			return a.y + s * (b.y - a.y) + t * (c.y - a.y)
	return NAN


## Boxes 1 tall and 4 deep in a row along X, each top sculpted at its power with
## a pattern between 0 and 0.5, sewn, then merged.
func _merge_sculpts() -> void:
	var moved: Array = []
	for c in [
		["two halves at power 2", [4.0, 4.0], [2, 2]],
		["two halves at powers 2 and 3", [4.0, 4.0], [2, 3]],
		["three in a row at power 2", [4.0, 4.0, 4.0], [2, 2, 2]],
		["a 4 and a 2 at power 2", [4.0, 2.0], [2, 2]],
		["two halves at power 4", [4.0, 4.0], [4, 4]],
	]:
		var root: Node3D = await fresh_root()
		var x := 0.0
		var ids: Array = []
		for k in (c[1] as Array).size():
			var w: float = c[1][k]
			var b = root.create_brush_from_info(
				{"size": Vector3(w, 1, 4), "center": Vector3(x + w * 0.5, 0.5, 0)}
			)
			x += w
			ids.append(_bid(b))
			for index in b.faces.size():
				if b.faces[index].normal.y < 0.9:
					continue
				root.create_displacement(_bid(b), index, int(c[2][k]))
				var d = b.faces[index].displacement
				for row in d.get_dim():
					for col in d.get_dim():
						d.set_distance(row, col, 0.05 * float((row * 7 + col * 3 + k * 5) % 11))
				root.set_displacement_sew_group(_bid(b), index, 1)
		root.sew_all_displacements()
		var originals := PackedVector3Array()
		for n in root._iter_managed_brush_nodes():
			originals.append_array(_top_points(n))
		var made = root.merge_brushes_by_ids(ids)
		await frame()
		var merged: Array = root._iter_managed_brush_nodes()
		if not made.ok or merged.size() != 1:
			note(c[0], "not merged: %s, %d brushes" % [made.user_text(), merged.size()])
			await drop_root(root)
			continue
		var tris := _top_points(merged[0])
		var worst := 0.0
		var off := 0
		for p in originals:
			var h := _height_at(tris, p.x, p.z)
			if is_nan(h):
				continue
			if absf(h - p.y) > 0.001:
				off += 1
			worst = maxf(worst, absf(h - p.y))
		var power := -1
		for f in merged[0].faces:
			if f.normal.y > 0.9 and f.displacement != null:
				power = f.displacement.power
		note(
			c[0],
			(
				"%s; merged at power %d, %d of %d old grid corners off the surface, worst by %.4f"
				% [made.user_text(), power, off, originals.size(), worst]
			)
		)
		if off > 0:
			moved.append(
				(
					"%s: power %d, %d of %d moved, worst %.3f"
					% [c[0], power, off, originals.size(), worst]
				)
			)
		await drop_root(root)
	if not moved.is_empty():
		known(
			1972,
			"Merge lays a sculpt over a grid too coarse for the faces it joins, and moves its relief without a word",
			moved
		)
