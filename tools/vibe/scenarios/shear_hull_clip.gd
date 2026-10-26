@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Shear, Hull and the Clip tool, and a face pushed along its normal: the four
## commands that rebuild a brush's corners rather than move the brush.
##
## Each one hands the bake a new set of faces, so the questions are the ones the
## cut operations get: is what comes out a closed convex solid, are its corners
## where the operation says they go (measured here, not read off the report),
## does a shear keep the volume it had, and does a state round trip put the
## level back exactly. Then the edges a mapper reaches by accident: points on one
## line, the same point twice, two points, a hull far from the origin, a push
## that would turn a brush inside out.

const HFConvexClipType = preload("res://addons/hammerforge/hf_convex_clip.gd")
const HFHullType = preload("res://addons/hammerforge/hf_hull.gd")
const HFHullToolType = preload("res://addons/hammerforge/hf_hull_tool.gd")
const HFClipToolType = preload("res://addons/hammerforge/hf_clip_tool.gd")
const HFFacePushType = preload("res://addons/hammerforge/hf_face_push.gd")
const HFTransformSystemType = preload("res://addons/hammerforge/systems/hf_transform_system.gd")


func id() -> String:
	return "shear-hull-clip"


func summary() -> String:
	return "shear, hull, the Clip tool and face push: closed, convex, measured, undone"


func expected_issues() -> Array[int]:
	return [1998, 1999]


func run() -> void:
	await _shear()
	await _hull_of_brushes()
	await _hull_of_points()
	await _clip_tool()
	await _face_push()
	await _shared_corners()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## Every distinct corner of a brush in the world, sorted, snapped to a millimetre.
func _corners(brush: Node3D) -> Array:
	var out: Array = []
	for face in brush.faces:
		for corner in face.local_verts:
			var point: Vector3 = (brush.global_transform * corner).snapped(Vector3.ONE * 0.001)
			if not out.has(point):
				out.append(point)
	out.sort()
	return out


func _volume(brush: Node3D) -> float:
	return HFVibe.solid_volume(brush.faces) * absf(brush.global_transform.basis.determinant())


func _convex(brush: Node3D) -> bool:
	return HFConvexClipType.is_convex_solid(
		brush.faces, HFConvexClipType.interior_point(brush.faces)
	)


## What is wrong with each brush on the level as a solid, by the harness's own
## count and by convexity.
func _solid_problems(root: Node3D) -> Array:
	var out: Array = HFVibe.check_solids(root, {})
	for b in root.draft_brushes_node.get_children():
		if not _convex(b):
			out.append("brush %s is not convex" % _bid(b))
	return out


func _same_points(a: Array, b: Array, tolerance: float = 0.002) -> bool:
	if a.size() != b.size():
		return false
	for p in a:
		var found := false
		for q in b:
			if (p as Vector3).distance_to(q) <= tolerance:
				found = true
				break
		if not found:
			return false
	return true


# ---------------------------------------------------------------------------
# Shear
# ---------------------------------------------------------------------------


func _shear() -> void:
	note("-- shear --")
	var cases := [
		["box", {"shape": 0, "size": Vector3(2, 3, 0.5), "center": Vector3(1, 1.5, 0)}, 0.0],
		[
			"cylinder of 12",
			{"shape": 1, "size": Vector3(2, 3, 2), "center": Vector3(0, 1.5, 0), "sides": 12},
			0.0
		],
		["wedge", {"shape": 4, "size": Vector3(2, 2, 2), "center": Vector3(0, 1, 0)}, 0.0],
		[
			"box turned 30 on Y",
			{"shape": 0, "size": Vector3(2, 3, 1), "center": Vector3(0, 1.5, 0)},
			30.0
		],
	]
	for case in cases:
		var root: Node3D = await fresh_root()
		var b = root.create_brush_from_info(case[1])
		if float(case[2]) != 0.0:
			root.rotate_managed_nodes([_bid(b)], [], 1, float(case[2]), b.global_position)
		var bid := _bid(b)
		var before_corners := _corners(b)
		var before_volume := _volume(b)
		var state: Dictionary = root.capture_state()
		var before_level := HFVibe.describe_level(root)
		var amount := 0.5
		var pivot := 0.0
		var report: Dictionary = root.shear_managed_nodes([bid], [], 0, 1, amount, pivot)
		await frame()
		var after_b = root.find_brush_by_id(bid)
		if after_b == null:
			flag("shear of a %s lost the brush" % case[0])
			await drop_root(root)
			continue
		# Every corner p goes to p + X * amount * (p.y - pivot), measured here.
		var expected: Array = []
		for p in before_corners:
			var q: Vector3 = p + Vector3.RIGHT * amount * ((p as Vector3).y - pivot)
			expected.append(q.snapped(Vector3.ONE * 0.001))
		var got := _corners(after_b)
		var after_volume := _volume(after_b)
		note(
			"shear a %s along X over Y by 0.5" % case[0],
			(
				"changed %d, corners %d, volume %.4f -> %.4f, convex %s"
				% [
					int(report.get("changed", 0)),
					got.size(),
					before_volume,
					after_volume,
					_convex(after_b)
				]
			)
		)
		if not _same_points(got, expected):
			flag(
				"a sheared %s's corners are not where the shear puts them" % case[0],
				"expected %s, got %s" % [str(expected).substr(0, 300), str(got).substr(0, 300)]
			)
		if absf(after_volume - before_volume) > before_volume * 0.001:
			flag(
				"shearing a %s changed its volume" % case[0],
				"%.4f before, %.4f after" % [before_volume, after_volume]
			)
		for problem in _solid_problems(root):
			flag("shear of a %s left a bad solid" % case[0], problem)
		root.restore_state(state)
		await frame()
		var back = root.find_brush_by_id(bid)
		var back_corners := _corners(back) if back else []
		if not _same_points(back_corners, before_corners):
			flag(
				(
					"restoring the state before a shear of a %s does not put its corners back"
					% case[0]
				),
				str(back_corners).substr(0, 300)
			)
		diff_levels(
			before_level, HFVibe.describe_level(root), "shear of a %s then restore" % case[0]
		)
		await drop_root(root)

	# Out of range: each should change nothing and say so through the report.
	var root2: Node3D = await fresh_root()
	var b2 = box(root2, Vector3(2, 2, 2), Vector3(0, 1, 0))
	var bid2 := _bid(b2)
	var sig := HFVibe.signature(root2)
	var bad := {
		"along == over": [1, 1, 0.5, 0.0],
		"axis 3": [3, 1, 0.5, 0.0],
		"axis -1": [0, -1, 0.5, 0.0],
		"amount NAN": [0, 1, NAN, 0.0],
		"amount INF": [0, 1, INF, 0.0],
		"pivot NAN": [0, 1, 0.5, NAN],
	}
	for label in bad:
		var args: Array = bad[label]
		var report: Dictionary = root2.shear_managed_nodes(
			[bid2], [], args[0], args[1], args[2], args[3]
		)
		var same := HFVibe.signature(root2) == sig
		note(
			"shear with %s" % label,
			"changed %d, level unchanged %s" % [int(report.get("changed", 0)), same]
		)
		if not same:
			flag("a shear with %s changed the level" % label, HFVibe.signature(root2))
			sig = HFVibe.signature(root2)
	# Shear and shear back: the brush it started as.
	var start := _corners(root2.find_brush_by_id(bid2))
	root2.shear_managed_nodes([bid2], [], 2, 1, 0.75, 0.0)
	root2.shear_managed_nodes([bid2], [], 2, 1, -0.75, 0.0)
	var round_trip := _corners(root2.find_brush_by_id(bid2))
	note("shear 0.75 then -0.75 on Z over Y", "corners back: %s" % _same_points(start, round_trip))
	if not _same_points(start, round_trip):
		flag("a shear and its opposite do not give the brush back", str(round_trip))
	await drop_root(root2)


# ---------------------------------------------------------------------------
# Hull of brushes
# ---------------------------------------------------------------------------


func _hull_of_brushes() -> void:
	note("-- hull of selection --")
	var root: Node3D = await fresh_root()
	var a = box(root, Vector3(1, 1, 1), Vector3(0, 0.5, 0))
	var c = box(root, Vector3(2, 0.5, 2), Vector3(3, 0.25, 1))
	var all_corners: Array = _corners(a) + _corners(c)
	var state: Dictionary = root.capture_state()
	var before_level := HFVibe.describe_level(root)
	var result = root.hull_brushes_by_ids([_bid(a), _bid(c)])
	await frame()
	var live: Array = root.draft_brushes_node.get_children()
	note("hull of two boxes apart", "%s, %d brushes after" % [result.ok, live.size()])
	if result.ok and live.size() == 1:
		var hull: Node3D = live[0]
		# Every corner of either source lies inside or on the hull.
		var outside := 0
		var interior := HFConvexClipType.interior_point(hull.faces)
		var planes: Array = HFConvexClipType.outward_planes(hull.faces, interior)
		var into: Transform3D = hull.global_transform.affine_inverse()
		for p in all_corners:
			for plane: Plane in planes:
				if plane.distance_to(into * p) > 0.002:
					outside += 1
					break
		note("source corners outside the hull", outside)
		if outside > 0:
			flag("Hull of Selection leaves %d source corners outside the hull" % outside)
		for problem in _solid_problems(root):
			flag("Hull of Selection made a bad solid", problem)
	root.restore_state(state)
	await frame()
	diff_levels(before_level, HFVibe.describe_level(root), "hull then restore")
	await drop_root(root)


# ---------------------------------------------------------------------------
# Hull of points
# ---------------------------------------------------------------------------


func _hull_of_points() -> void:
	note("-- the Hull tool's points --")
	var cube := PackedVector3Array()
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				cube.append(Vector3(x, y, z))
	var cases := {
		"two points": PackedVector3Array([Vector3.ZERO, Vector3.ONE]),
		"three points": PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP]),
		"four on a line":
		PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2, Vector3.RIGHT * 3]),
		"six on a plane":
		PackedVector3Array(
			[
				Vector3.ZERO,
				Vector3.RIGHT,
				Vector3.BACK,
				Vector3(1, 0, 1),
				Vector3(2, 0, 0.5),
				Vector3(0.5, 0, 2)
			]
		),
		"a tetrahedron, one point twice":
		PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3.UP]),
		"a tetrahedron, one point 0.0005 off another":
		PackedVector3Array(
			[Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.0005, 1, 0)]
		),
	}
	for label in cases:
		var hull: Dictionary = HFHullType.of(cases[label])
		var line := "ok" if hull["ok"] else "refused: %s" % hull.get("reason", "")
		if hull["ok"]:
			line += ", %d faces" % (hull["faces"] as Array).size()
		note(label, line)
	# Far from the origin: the Hull tool hands world points straight in.
	for offset in [0.0, 100.0, 1000.0, 4000.0, 16000.0]:
		var moved := PackedVector3Array()
		for p in cube:
			moved.append(p * 2.0 + Vector3(offset, 0, offset))
		moved.append(Vector3(offset + 1.0, 1.0, offset + 1.0))  # one inside
		var hull: Dictionary = HFHullType.of(moved)
		var line := "refused: %s" % hull.get("reason", "") if not hull["ok"] else ""
		if hull["ok"]:
			var faces: Array = hull["faces"]
			# Measured about the cube's own corner: a volume summed about the origin
			# 16 km away loses everything to float32 cancellation, not to the hull.
			var local_faces: Array = []
			for f in faces:
				var copy = f.duplicate()
				var verts := PackedVector3Array()
				for v in f.local_verts:
					verts.append(v - Vector3(offset, 0, offset))
				copy.local_verts = verts
				local_faces.append(copy)
			line = (
				"%d faces, %d open edges, volume %.3f"
				% [faces.size(), HFVibe.open_edge_count(faces), HFVibe.solid_volume(local_faces)]
			)
		note("a 2 m cube of points %d m out" % int(offset), line)
		if not hull["ok"] or (hull["faces"] as Array).size() != 6:
			flag(
				"the hull of a 2 m cube's corners %d m from the origin is not a cube" % int(offset),
				line
			)
	# Through the tool's own brush builder, into a level, and back out of a save.
	var root: Node3D = await fresh_root()
	var points := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 0, 2), Vector3(2, 0, 2), Vector3(1, 2, 1)]
	)
	var hull: Dictionary = HFHullType.of(points)
	if hull["ok"]:
		var info := HFHullToolType.brush_info(hull["faces"])
		var brush = root.create_brush_from_info(info)
		await frame()
		note(
			"a pyramid from five points",
			"%d faces, volume %.3f" % [brush.faces.size(), _volume(brush)]
		)
		if absf(_volume(brush) - 8.0 / 3.0) > 0.01:
			flag(
				"the Hull tool's pyramid is not the volume of the pyramid",
				"%.4f against 2.6667" % _volume(brush)
			)
		var want: Array = []
		for p in points:
			want.append(p.snapped(Vector3.ONE * 0.001))
		if not _same_points(_corners(brush), want):
			flag("the Hull tool's brush is not on the points clicked", str(_corners(brush)))
		for problem in _solid_problems(root):
			flag("the Hull tool made a bad solid", problem)
	# The cost of a hull of round brushes, which is what a column wrap is.
	for sides in [16, 32, 64]:
		var r: Node3D = await fresh_root()
		var c1 = r.create_brush_from_info(
			{"shape": 1, "size": Vector3(1, 3, 1), "center": Vector3(0, 1.5, 0), "sides": sides}
		)
		var c2 = r.create_brush_from_info(
			{"shape": 1, "size": Vector3(2, 0.5, 2), "center": Vector3(0, 0.25, 3), "sides": sides}
		)
		var t0 := Time.get_ticks_msec()
		var check = r.can_hull_brushes([_bid(c1), _bid(c2)])
		var t1 := Time.get_ticks_msec()
		note(
			"Hull check of two %d-sided cylinders" % sides,
			(
				"%s in %d ms, %d corners (the check, the preview, the check at OK and the command each work it out)"
				% [check.ok, t1 - t0, _corners(c1).size() + _corners(c2).size()]
			)
		)
		await drop_root(r)
	var rs: Node3D = await fresh_root()
	var s1 = rs.create_brush_from_info(
		{"shape": 2, "size": Vector3(2, 2, 2), "center": Vector3(0, 1, 0)}
	)
	var s2 = rs.create_brush_from_info(
		{"shape": 2, "size": Vector3(2, 2, 2), "center": Vector3(4, 1, 0)}
	)
	var ts := Time.get_ticks_msec()
	var sphere_check = rs.can_hull_brushes([_bid(s1), _bid(s2)])
	var sphere_ms := Time.get_ticks_msec() - ts
	note(
		"Hull check of two default spheres",
		"%s in %d ms, %d corners" % [sphere_check.ok, sphere_ms, _corners(s1).size() * 2]
	)
	# Where the time goes: the engine's hull finder, or the face search after it.
	var pts := PackedVector3Array()
	for p in _corners(s1) + _corners(s2):
		pts.append(p)
	var t_a := Time.get_ticks_msec()
	var hull_corners: PackedVector3Array = HFHullType._corners(HFHullType.unique_points(pts))
	var t_b := Time.get_ticks_msec()
	var hull_faces: Array = HFHullType._faces(hull_corners)
	var t_c := Time.get_ticks_msec()
	note(
		"HFHull on those corners",
		(
			"engine hull finder %d ms for %d corners, the face search %d ms for %d faces"
			% [t_b - t_a, hull_corners.size(), t_c - t_b, hull_faces.size()]
		)
	)
	if sphere_ms > 2000:
		known(
			1999,
			(
				"Hull of Selection on two default spheres takes %.1f s, and a press works it out four times"
				% (sphere_ms / 1000.0)
			),
			(
				"can_hull before the dialog, the preview, can_hull again at OK, then the hull: "
				+ "HFHull._faces tries every triple of corners against every face found, O(n^4)"
			)
		)
	await drop_root(rs)
	await drop_root(root)


# ---------------------------------------------------------------------------
# Clip tool
# ---------------------------------------------------------------------------


func _clip_tool() -> void:
	note("-- the Clip tool --")
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(4, 2, 2), Vector3(0, 1, 0))
	var tool = HFClipToolType.new()
	tool.root = root
	tool.selection_source = func(): return root.draft_brushes_node.get_children()
	# Points that make no plane.
	var no_plane := {
		"one point": [Vector3(0, 1, 0)],
		"two points the same": [Vector3(0, 1, 0), Vector3(0, 1, 0)],
		"two along the view axis": [Vector3(0, 0, 0), Vector3(0, 2, 0)],
		"three on a line": [Vector3(-1, 1, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)],
		"three, two the same": [Vector3(0, 1, -1), Vector3(0, 1, -1), Vector3(0, 2, 1)],
	}
	for label in no_plane:
		tool._reset()
		tool.set_view_axis(Vector3.UP)
		for p in no_plane[label]:
			tool.add_point(p)
		var sig := HFVibe.signature(root)
		var applied: bool = tool.apply()
		note("Clip tool with %s" % label, "plane %s, applied %s" % [tool.plane() != null, applied])
		if applied or HFVibe.signature(root) != sig:
			flag("the Clip tool cut with %s" % label, HFVibe.signature(root))
	tool._reset()
	await drop_root(root)

	# Keep front, back and both, on a box turned 30 degrees, measured by volume.
	for keep in [0, 1, 2]:
		var r: Node3D = await fresh_root()
		var t = r.create_brush_from_info(
			{"shape": 0, "size": Vector3(4, 2, 2), "center": Vector3(0, 1, 0)}
		)
		r.rotate_managed_nodes([_bid(t)], [], 1, 30.0, t.global_position)
		var whole := _volume(t)
		var state: Dictionary = r.capture_state()
		var before_level := HFVibe.describe_level(r)
		var clip = HFClipToolType.new()
		clip.root = r
		clip.selection_source = func(): return r.draft_brushes_node.get_children()
		clip.set_setting("keep", keep)
		clip.set_view_axis(Vector3.UP)
		clip.add_point(Vector3(0.5, 1, -3))
		clip.add_point(Vector3(0.5, 1, 3))
		var cut: Plane = clip.plane()
		var ok: bool = clip.apply()
		await frame()
		var pieces: Array = r.draft_brushes_node.get_children()
		var total := 0.0
		var wrong_side := 0
		for p in pieces:
			total += _volume(p)
			var side := 0.0
			for corner in _corners(p):
				side += cut.distance_to(corner)
			# A kept front piece sits on the normal's side, a back piece behind.
			if keep == 1 and side < -0.01:
				wrong_side += 1
			if keep == 2 and side > 0.01:
				wrong_side += 1
		note(
			"Clip tool keep %s on a turned box" % ["both", "front", "back"][keep],
			"applied %s, %d pieces, volume %.3f of %.3f" % [ok, pieces.size(), total, whole]
		)
		if keep == 0 and absf(total - whole) > whole * 0.002:
			flag(
				"a Clip keeping both pieces changed the volume",
				"%.4f against %.4f" % [total, whole]
			)
		if wrong_side > 0:
			flag("the Clip tool kept the wrong side", "keep %d, plane %s" % [keep, cut])
		for problem in _solid_problems(r):
			flag("the Clip tool made a bad solid", problem)
		r.restore_state(state)
		await frame()
		diff_levels(before_level, HFVibe.describe_level(r), "Clip tool then restore")
		clip._reset()
		await drop_root(r)


# ---------------------------------------------------------------------------
# Face push
# ---------------------------------------------------------------------------


func _face_push() -> void:
	note("-- face push --")
	var root: Node3D = await fresh_root()
	var w = root.create_brush_from_info(
		{"shape": 4, "size": Vector3(2, 2, 2), "center": Vector3(0, 1, 0)}
	)
	# Each face out 0.5 and in 0.5, each judged by where its plane went.
	for i in w.faces.size():
		for distance in [0.5, -0.5]:
			var state := HFFacePushType.state_of(w)
			var plane_before := HFFacePushType.world_plane(w, i)
			var result := HFFacePushType.pushed(w, i, distance)
			if not result["ok"]:
				note("push wedge face %d by %.1f" % [i, distance], "refused: %s" % result["reason"])
				continue
			HFFacePushType.apply(w, result)
			var plane_after := HFFacePushType.world_plane(w, i)
			var moved := plane_after.d - plane_before.d
			if (
				absf(moved - distance) > 0.001
				or plane_after.normal.dot(plane_before.normal) < 0.9999
			):
				flag(
					"pushing wedge face %d by %.1f moved its plane %.4f" % [i, distance, moved],
					"normal %s -> %s" % [plane_before.normal, plane_after.normal]
				)
			for problem in _solid_problems(root):
				flag("pushing wedge face %d by %.1f left a bad solid" % [i, distance], problem)
			HFFacePushType.restore(w, state)
	# A custom brush the gizmo stretched: a push is asked in metres in the world.
	var c = root.create_brush_from_info(
		{"shape": 4, "size": Vector3(2, 2, 2), "center": Vector3(5, 1, 0)}
	)
	c.scale = Vector3(1.5, 1.5, 1.5)
	var face_idx := -1
	for i in c.faces.size():
		if HFFacePushType.world_plane(c, i).normal.dot(Vector3.UP) < -0.99:
			face_idx = i
	if face_idx >= 0:
		var before_plane := HFFacePushType.world_plane(c, face_idx)
		var res := HFFacePushType.pushed(c, face_idx, 1.0)
		var moved := 0.0
		if res["ok"]:
			HFFacePushType.apply(c, res)
			moved = HFFacePushType.world_plane(c, face_idx).d - before_plane.d
		note("push the bottom of a wedge scaled 1.5x by 1 m", "its plane moved %.3f m" % moved)
		# The drag's snap: it picks the distance that puts a corner on a grid
		# line, which lands there only if the push moves the face that far.
		var corners := HFFacePushType.world_corners(c, face_idx)
		var normal: Vector3 = HFFacePushType.world_plane(c, face_idx).normal
		var snapped_d := HFFacePushType.snapped_distance(-0.3, corners, normal, 0.5)
		var res2 := HFFacePushType.pushed(c, face_idx, snapped_d)
		var y := NAN
		if res2["ok"]:
			HFFacePushType.apply(c, res2)
			y = HFFacePushType.world_corners(c, face_idx)[0].y
		note(
			"a snapped drag of -0.3 on grid 0.5, same brush",
			"snapped to %.3f, the face's corners land at y = %.3f" % [snapped_d, y]
		)
		# A box under the same scale, for comparison: `_pushed_box()` divides by it.
		var bx = box(root, Vector3(2, 2, 2), Vector3(10, 1, 0))
		bx.scale = Vector3(1.5, 1.5, 1.5)
		var bottom := -1
		for i in bx.faces.size():
			if HFFacePushType.world_plane(bx, i).normal.dot(Vector3.UP) < -0.99:
				bottom = i
		var box_before := HFFacePushType.world_plane(bx, bottom)
		HFFacePushType.apply(bx, HFFacePushType.pushed(bx, bottom, 1.0))
		var box_moved: float = HFFacePushType.world_plane(bx, bottom).d - box_before.d
		note("push the bottom of a box scaled 1.5x by 1 m", "its plane moved %.3f m" % box_moved)
		if absf(moved - 1.0) > 0.01 or absf(y - snappedf(y, 0.5)) > 0.001:
			known(
				1998,
				"a face push on a gizmo-scaled custom brush moves the face by the scale times the distance",
				(
					(
						"scale 1.5: asked 1 m, moved %.3f m; a drag snapped to %.3f puts the face at y = %.3f, "
						+ "off grid 0.5. A box under the same scale moves %.3f m"
					)
					% [moved, snapped_d, y, box_moved]
				)
			)
	await drop_root(root)


# ---------------------------------------------------------------------------
# Many corners at once
# ---------------------------------------------------------------------------


func _corner_at(root: Node3D, brush: Node3D, world: Vector3) -> int:
	var verts: PackedVector3Array = root.vertex_system.get_brush_vertices(brush)
	for i in verts.size():
		if (brush.global_transform * verts[i]).distance_to(world) < 0.001:
			return i
	return -1


func _shared_corners() -> void:
	note("-- many corners at once --")
	var root: Node3D = await fresh_root()
	# Four floor tiles meeting at the origin, one of them turned a quarter.
	var tiles: Array = []
	for at in [
		Vector3(-1, 0.25, -1), Vector3(1, 0.25, -1), Vector3(-1, 0.25, 1), Vector3(1, 0.25, 1)
	]:
		tiles.append(box(root, Vector3(2, 0.5, 2), at))
	root.rotate_managed_nodes([_bid(tiles[3])], [], 1, 90.0, tiles[3].global_position)
	await frame()
	var vs = root.vertex_system
	vs.set_selection(tiles)
	var shared_at := Vector3(0, 0.5, 0)
	var first := _corner_at(root, tiles[0], shared_at)
	var count: int = vs.select_shared_corner(_bid(tiles[0]), first)
	var state: Dictionary = root.capture_state()
	var before_level := HFVibe.describe_level(root)
	var snaps: Dictionary = vs.transform_selected(
		Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), "Move rejected"
	)
	var raised := 0
	for t in tiles:
		if _corner_at(root, t, Vector3(0, 1, 0)) >= 0:
			raised += 1
	note(
		"raise the corner four tiles share, one tile turned 90",
		(
			"%d picked, moved %s, %d tiles have the corner at y = 1"
			% [count, not snaps.is_empty(), raised]
		)
	)
	if count == 4 and not snaps.is_empty() and raised != 4:
		flag("a shared corner raised on four tiles left a crack", "%d of 4 tiles moved it" % raised)
	for problem in _solid_problems(root):
		flag("raising a shared corner left a bad solid", problem)
	root.restore_state(state)
	await frame()
	diff_levels(before_level, HFVibe.describe_level(root), "a shared corner move then restore")
	await drop_root(root)

	# Two boxes side by side: the corner they share pushed down into both. One
	# refusal should leave both as they were.
	var r2: Node3D = await fresh_root()
	var left = box(r2, Vector3(2, 2, 2), Vector3(-1, 1, 0))
	var right = box(r2, Vector3(2, 2, 2), Vector3(1, 1, 0))
	var vs2 = r2.vertex_system
	vs2.set_selection([left, right])
	var c := _corner_at(r2, left, Vector3(0, 2, 1))
	vs2.select_shared_corner(_bid(left), c)
	var corners_before: Array = _corners(left) + _corners(right)
	var moved: Dictionary = vs2.transform_selected(
		Transform3D(Basis.IDENTITY, Vector3(-0.8, -0.8, -0.8)), "Move rejected"
	)
	var corners_after: Array = (
		_corners(r2.find_brush_by_id(_bid(left))) + _corners(r2.find_brush_by_id(_bid(right)))
	)
	var same := _same_points(corners_before, corners_after)
	note(
		"push the corner two boxes share into the left one (a dent there)",
		"moved %s, both as they were %s" % [not moved.is_empty(), same]
	)
	if moved.is_empty() and not same:
		flag(
			"a refused move of a shared corner left one brush changed",
			str(corners_after).substr(0, 300)
		)
	for problem in _solid_problems(r2):
		flag("a shared corner move left a bad solid", problem)
	await drop_root(r2)
