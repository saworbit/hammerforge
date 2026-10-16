@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Several cordons at once.
##
## `cordon` asks what one cordon keeps out of a bake. Since #966 a level holds a
## list of them, each with a name and its own Bake switch, and a partial bake
## takes every brush that touches any cordon that is on. That is a union over
## boxes, and a union has edges a single box does not: two boxes that overlap,
## one inside another, one with no volume, one switched off beside one switched
## on, a brush lying across an edge, a box with nothing in it.
##
## Each case is measured off the baked meshes and the baked collision shapes
## separately, by attributing every baked triangle to the brush it sits in,
## rather than by trusting a count the bake reports. The list then goes through
## everything that carries it -- the `.hflevel`, a state round trip, the undo
## snapshot, `bake_dirty()` -- and through the exports that take the bake, and
## the checks a playtest runs (the spawn check, the navmesh) are asked whether
## they look at the same area the bake did.

const DockScene = preload("res://addons/hammerforge/dock.tscn")

const PREFIX := "user://cordons-many"
## Where Export Game Scene writes: beside the level's own scene, so the level
## claims a scene under `.godot`, which git ignores, and the file is removed.
const GAME_SCENE_SOURCE := "res://.godot/cordons-many_probe.tscn"
const GAME_SCENE_OUT := "res://.godot/cordons-many_probe_game.tscn"

## Four 2-unit boxes, far enough apart that a 4-unit cordon round one cannot
## reach another.
const SPOTS := {
	"A": Vector3(0, 0, 0),
	"B": Vector3(20, 0, 0),
	"C": Vector3(40, 0, 0),
	"D": Vector3(60, 0, 0),
}


## A dock whose toasts are kept, so what it tells the mapper can be read.
class ToastDock:
	extends "res://addons/hammerforge/dock.gd"

	var toasts: Array = []

	func show_toast(message: String, level: int = 0) -> void:
		toasts.append([level, message])


var _written: Array[String] = []


func id() -> String:
	return "cordons-many"


func summary() -> String:
	return "several cordons at once: overlap, nesting, disabled ones, saves, undo and partial bakes"


func run() -> void:
	await _the_union_cases()
	await _a_brush_across_a_cordon_edge()
	await _a_brush_flush_with_a_cordon_face()
	await _a_cut_outside_the_cordon()
	await _a_cordon_with_nothing_in_it()
	await _through_the_hflevel()
	await _through_state_and_the_undo_snapshot()
	await _through_bake_dirty()
	await _through_the_exports()
	await _what_the_spawn_check_sees()
	await _what_the_navmesh_and_validate_see()
	_cleanup()


func _cleanup() -> void:
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func physics_frame() -> void:
	await _tree.physics_frame


func _around(centre: Vector3, half: float = 2.0) -> AABB:
	return AABB(centre - Vector3.ONE * half, Vector3.ONE * half * 2.0)


## The level every union case starts from: one box at each spot.
func _four_boxes(root: Node3D) -> void:
	for spot in SPOTS:
		box(root, Vector3(2, 2, 2), SPOTS[spot])


# ---------------------------------------------------------------------------
# Measuring the bake
# ---------------------------------------------------------------------------


## Every baked triangle under `node`, in level space, as its three corners.
##
## The transform is carried down by hand rather than read off `global_transform`,
## so the same walk measures the baked container, a scene loaded back off disk
## and a glTF scene that was never added to the tree.
func _triangles(node: Node, xform: Transform3D, out: Dictionary) -> Dictionary:
	var here := xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var verts = arrays[Mesh.ARRAY_VERTEX]
			if not (verts is PackedVector3Array):
				continue
			var idx = arrays[Mesh.ARRAY_INDEX]
			var order := PackedInt32Array()
			if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
				order = idx
			else:
				for i in range((verts as PackedVector3Array).size()):
					order.append(i)
			for t in range(0, order.size() - 2, 3):
				out["mesh"].append(
					[here * verts[order[t]], here * verts[order[t + 1]], here * verts[order[t + 2]]]
				)
	if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
		var shape: Shape3D = (node as CollisionShape3D).shape
		if shape is ConcavePolygonShape3D:
			var faces: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
			for t in range(0, faces.size() - 2, 3):
				out["collision"].append([here * faces[t], here * faces[t + 1], here * faces[t + 2]])
		elif shape is ConvexPolygonShape3D:
			# A hull has points, not triangles: each point stands in for one.
			for p in (shape as ConvexPolygonShape3D).points:
				out["collision"].append([here * p, here * p, here * p])
		elif shape is BoxShape3D:
			var h: Vector3 = (shape as BoxShape3D).size * 0.5
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var p: Vector3 = here * Vector3(h.x * sx, h.y * sy, h.z * sz)
						out["collision"].append([p, p, p])
	for child in node.get_children():
		_triangles(child, here, out)
	return out


func _baked(root: Node3D) -> Dictionary:
	var out := {"mesh": [], "collision": []}
	if root.baked_container == null:
		return out
	return _triangles(root.baked_container, root.global_transform, out)


## How many triangles have their centre inside `box`.
func _count_in(tris: Array, box: AABB) -> int:
	var grown := box.grow(0.001)
	var n := 0
	for tri in tris:
		var centre: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		if grown.has_point(centre):
			n += 1
	return n


## Which of the four spots have baked triangles, and how many each.
func _which(tris: Array) -> Dictionary:
	var out := {}
	for spot in SPOTS:
		var n := _count_in(tris, _around(SPOTS[spot], 1.5))
		if n > 0:
			out[spot] = n
	return out


## The box every baked point spans.
func _extent(tris: Array) -> AABB:
	var have := false
	var box := AABB()
	for tri in tris:
		for p in tri:
			if have:
				box = box.expand(p)
			else:
				box = AABB(p, Vector3.ZERO)
				have = true
	return box


# ---------------------------------------------------------------------------
# The union
# ---------------------------------------------------------------------------


## Set up one named case on a level holding the four boxes.
func _setup(root: Node3D, label: String) -> void:
	root.cordon_enabled = true
	match label:
		"one cordon round A (the control)":
			root.set_cordon_region(0, _around(SPOTS["A"]))
		"two disjoint cordons, round A and round C":
			root.set_cordon_region(0, _around(SPOTS["A"]))
			root.set_cordon_region(1, _around(SPOTS["C"]))
		"two overlapping cordons, A..B and B..C":
			root.set_cordon_region(0, AABB(Vector3(-2, -2, -2), Vector3(24, 4, 4)))
			root.set_cordon_region(1, AABB(Vector3(18, -2, -2), Vector3(24, 4, 4)))
		"one cordon A..C with a second round B inside it":
			root.set_cordon_region(0, AABB(Vector3(-2, -2, -2), Vector3(44, 4, 4)))
			root.set_cordon_region(1, _around(SPOTS["B"]))
		"the second cordon given max-to-min round C":
			root.set_cordon_region(0, _around(SPOTS["A"]))
			root.set_cordon_region(1, AABB(SPOTS["C"] + Vector3.ONE * 2.0, -Vector3.ONE * 4.0))
		"an inverted extra cordon written to the property":
			root.set_cordon_region(0, _around(SPOTS["A"]))
			var extra: Array[AABB] = [AABB(SPOTS["C"] + Vector3.ONE * 2.0, -Vector3.ONE * 4.0)]
			root.cordon_extra_aabbs = extra
		"a zero-size cordon at D's centre":
			root.set_cordon_region(0, _around(SPOTS["A"]))
			root.set_cordon_region(1, AABB(SPOTS["D"], Vector3.ZERO))
		"a zero-size cordon in empty space":
			root.set_cordon_region(0, _around(SPOTS["A"]))
			root.set_cordon_region(1, AABB(Vector3(80, 0, 0), Vector3.ZERO))
		"round A on, round C switched off":
			root.set_cordon_region(0, _around(SPOTS["A"]))
			root.set_cordon_region(1, _around(SPOTS["C"]))
			root.set_cordon_active(1, false)
		"round A switched off, round C on":
			root.set_cordon_region(0, _around(SPOTS["A"]))
			root.set_cordon_region(1, _around(SPOTS["C"]))
			root.set_cordon_active(0, false)
		"both switched off":
			root.set_cordon_region(0, _around(SPOTS["A"]))
			root.set_cordon_region(1, _around(SPOTS["C"]))
			root.set_cordon_active(0, false)
			root.set_cordon_active(1, false)
		"two cordons set, Enable Cordon off":
			root.set_cordon_region(0, _around(SPOTS["A"]))
			root.set_cordon_region(1, _around(SPOTS["C"]))
			root.cordon_enabled = false


func _the_union_cases() -> void:
	var cases := {
		"one cordon round A (the control)": ["A"],
		"two disjoint cordons, round A and round C": ["A", "C"],
		"two overlapping cordons, A..B and B..C": ["A", "B", "C"],
		"one cordon A..C with a second round B inside it": ["A", "B", "C"],
		"the second cordon given max-to-min round C": ["A", "C"],
		"an inverted extra cordon written to the property": ["A", "C"],
		# A point inside a brush touches it, by AABB.intersects().
		"a zero-size cordon at D's centre": ["A", "D"],
		"a zero-size cordon in empty space": ["A"],
		"round A on, round C switched off": ["A"],
		"round A switched off, round C on": ["C"],
		# The guide: with every cordon's Bake unchecked, the entire map bakes.
		"both switched off": ["A", "B", "C", "D"],
		"two cordons set, Enable Cordon off": ["A", "B", "C", "D"],
	}
	var single_box_tris := -1
	for label in cases:
		var root: Node3D = await fresh_root("Cordons")
		_four_boxes(root)
		await frame()
		_setup(root, label)
		await frame()
		var ok: bool = await root.bake()
		await frame()
		var baked := _baked(root)
		var mesh := _which(baked["mesh"])
		var collision := _which(baked["collision"])
		var dry: Dictionary = root.bake_dry_run()
		note(
			"case: %s" % label,
			(
				"bake %s; cordons %s on %s; mesh triangles per brush %s; collision per brush %s; dry run draft %s"
				% [
					ok,
					root.get_all_cordon_regions(),
					[root.is_cordon_active(0), root.is_cordon_active(1)],
					mesh,
					collision,
					dry.get("draft", "?"),
				]
			)
		)
		var expected: Array = cases[label]
		var got_mesh: Array = mesh.keys()
		var got_collision: Array = collision.keys()
		got_mesh.sort()
		got_collision.sort()
		if got_mesh != expected:
			flag(
				"cordons '%s' baked the wrong brushes" % label,
				"expected meshes at %s, the bake put them at %s" % [expected, got_mesh]
			)
		if got_collision != got_mesh:
			flag(
				(
					"cordons '%s': the baked collision and the baked meshes cover different brushes"
					% label
				),
				"meshes at %s, collision at %s" % [got_mesh, got_collision]
			)
		if int(dry.get("draft", -1)) != got_mesh.size():
			flag(
				"cordons '%s': the dry run does not count what the bake took" % label,
				"dry run says %s, the bake took %d" % [dry.get("draft"), got_mesh.size()]
			)
		# A brush in two cordons is still one brush: no doubled geometry.
		for spot in mesh:
			if single_box_tris < 0:
				single_box_tris = int(mesh[spot])
			elif int(mesh[spot]) != single_box_tris:
				flag(
					(
						"cordons '%s': brush %s baked %d triangles, a lone box bakes %d"
						% [label, spot, mesh[spot], single_box_tris]
					),
					"a brush inside two cordons at once should bake once"
				)
		await drop_root(root)


## A 10-unit plank with a cordon over its first two units. The guide says the
## bake takes every brush that touches a cordon, so the whole plank is expected
## and the bake is not a clip. Written down so nobody files it as one.
func _a_brush_across_a_cordon_edge() -> void:
	var root: Node3D = await fresh_root("Straddle")
	box(root, Vector3(10, 2, 2), Vector3(104, 0, 0))
	await frame()
	root.cordon_enabled = true
	root.set_cordon_region(0, _around(Vector3(100, 0, 0)))
	await frame()
	await root.bake()
	await frame()
	var baked := _baked(root)
	note(
		"a plank 99..109 with a cordon 98..102",
		(
			"baked mesh spans %s, collision spans %s: the whole brush, as the guide says (no clipping)"
			% [_extent(baked["mesh"]), _extent(baked["collision"])]
		)
	)
	await drop_root(root)


## A brush whose face lies exactly on a cordon's face. `_brush_in_cordon()` asks
## `AABB.intersects()`, which is strict: two boxes that only share a face do not
## intersect. The guide says a brush that *touches* a cordon is baked.
func _a_brush_flush_with_a_cordon_face() -> void:
	var gaps := {"flush (cordon ends on the brush's face)": 0.0, "overlapping by 0.01": 0.01}
	var results := {}
	for label in gaps:
		var root: Node3D = await fresh_root("Flush")
		# A floor slab with its top at y = 0, the way a room is built. A whole unit
		# thick, so its top is 0 exactly and not 0 give or take a float.
		box(root, Vector3(6, 1, 6), Vector3(140, -0.5, 0))
		# A wall standing on it.
		box(root, Vector3(0.2, 3, 6), Vector3(143.1, 1.5, 0))
		await frame()
		root.cordon_enabled = true
		# The room's air, typed from the floor's top to head height: y 0..3, the
		# numbers a mapper reads off the grid.
		var lift: float = gaps[label]
		root.set_cordon_region(
			0, AABB(Vector3(137, 0.0 - lift, -3), Vector3(6.1 + lift, 3.0 + lift, 6))
		)
		await frame()
		await root.bake()
		await frame()
		var baked := _baked(root)
		var floor_tris := _count_in(
			baked["mesh"], AABB(Vector3(137, -1.05, -3), Vector3(6, 1.1, 6))
		)
		var wall_tris := _count_in(baked["mesh"], AABB(Vector3(143, 0.05, -3), Vector3(0.2, 3, 6)))
		var floor_collision := _count_in(
			baked["collision"], AABB(Vector3(137, -1.05, -3), Vector3(6, 1.1, 6))
		)
		results[label] = [floor_tris, floor_collision, wall_tris]
		note(
			"cordon over a room's air, %s" % label,
			(
				"cordon %s; floor slab: %d mesh / %d collision triangles; wall: %d mesh triangles"
				% [root.cordon_aabb, floor_tris, floor_collision, wall_tris]
			)
		)
		await drop_root(root)
	var flush: Array = results["flush (cordon ends on the brush's face)"]
	var overlap: Array = results["overlapping by 0.01"]
	if int(flush[0]) == 0 and int(overlap[0]) > 0:
		known(
			1206,
			"a brush whose face lies on a cordon's face is left out of the bake",
			(
				(
					"a 6x1x6 floor with its top at y=0 and a cordon typed from y=0 to y=3 over"
					+ " the room: the floor bakes %d mesh and %d collision triangles (the wall"
					+ " inside the cordon bakes %d); move the cordon's bottom down 0.01 and the"
					+ " floor bakes %d. `HFBakeSystem._brush_in_cordon()` asks"
					+ " `region.intersects(bounds)`, and Godot's AABB.intersects() is strict, so"
					+ " two boxes that share a face do not intersect. The guide says 'Only brushes"
					+ " that touch a cordon that is on are included'. A cordon typed on the grid"
					+ " round a room's air drops the floor and the ceiling it sits on, and the"
					+ " partial bake has nothing to stand on. Set from Selection grows by a unit,"
					+ " so only typed or spun bounds meet it."
				)
				% [flush[0], flush[1], flush[2], overlap[0]]
			)
		)


## A floor across the cordon edge with a hole cut in the half outside it. The
## floor is taken whole; the cutter, wholly outside, is not taken at all.
func _a_cut_outside_the_cordon() -> void:
	var holes := {}
	for cordoned in [false, true]:
		# Each case somewhere else in space, so a ray in the second cannot meet
		# collision the first left behind.
		var at := Vector3(0, 0, 50) if cordoned else Vector3.ZERO
		var root: Node3D = await fresh_root("CutOutside")
		box(root, Vector3(10, 0.2, 4), Vector3(204, -0.1, 0) + at)
		var cutter = (
			root
			. create_brush_from_info(
				{
					"shape": 0,
					"size": Vector3(2, 1, 2),
					"center": Vector3(206, -0.1, 0) + at,
					"operation": CSGShape3D.OPERATION_SUBTRACTION,
				}
			)
		)
		await frame()
		root.cordon_enabled = cordoned
		root.set_cordon_region(0, _around(Vector3(200, 0, 0) + at))
		await frame()
		await root.bake()
		await frame()
		await physics_frame()
		await physics_frame()
		var baked := _baked(root)
		# The hole's two edges at x = 205 and x = 207: a floor with the hole cut
		# has corners there, one without has none between x = 199 and 209.
		var edge_points := 0
		for tri in baked["mesh"]:
			for p in tri:
				if absf(p.x - 205.0) < 0.01 or absf(p.x - 207.0) < 0.01:
					edge_points += 1
		# And a ray straight down the middle of the hole, on every layer.
		var ray := PhysicsRayQueryParameters3D.create(
			Vector3(206, 2, 0) + at, Vector3(206, -5, 0) + at
		)
		ray.collision_mask = 0xFFFFFFFF
		var hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(ray)
		var hit_at: Variant = hit.get("position", null)
		holes[cordoned] = [edge_points, hit_at]
		note(
			(
				"a floor 199..209 cut at 205..207, cordon %s"
				% ("over 198..202" if cordoned else "off")
			),
			(
				"cutter %s; baked mesh corners on the hole's edges: %d; a ray down the hole's middle hits %s; floor spans %s"
				% [
					"in the bake" if root.bake_system.brush_bakes(cutter) else "left out",
					edge_points,
					hit_at if hit_at != null else "nothing",
					_extent(baked["mesh"]),
				]
			)
		)
		await drop_root(root)
	var uncut: Array = holes[false]
	var cut: Array = holes[true]
	if int(uncut[0]) > 0 and uncut[1] == null and int(cut[0]) == 0 and cut[1] != null:
		known(
			1206,
			"a brush the cordon takes whole is baked without the cuts made in it outside the cordon",
			(
				(
					"a 10-unit floor slab x 199..209 with a cutter at x 205..207. With the cordon"
					+ " off the bake has %d mesh corners on the hole's edges and a ray down the"
					+ " hole's middle falls through. With a cordon over x 198..202 the slab still"
					+ " bakes whole, since it touches the cordon, but the cutter does not touch"
					+ " it, so `brush_bakes()` leaves it out and the slab comes back solid: %d"
					+ " corners on the hole's edges, and the ray lands on baked collision at %s."
					+ " The partial bake shows, and lets the player walk on, a floor where the"
					+ " level has a pit. The fix is to take every cutter that meets a brush the"
					+ " cordon took."
				)
				% [uncut[0], cut[0], cut[1]]
			)
		)


## A cordon round empty space, alone, after a bake of the whole level.
func _a_cordon_with_nothing_in_it() -> void:
	var root: Node3D = await fresh_root("EmptyCordon")
	_four_boxes(root)
	await frame()
	var messages: Array = []
	root.connect("user_message", func(text: String, level: int): messages.append([level, text]))
	await root.bake()
	await frame()
	var before := _which(_baked(root)["mesh"])
	root.cordon_enabled = true
	root.set_cordon_region(0, _around(Vector3(300, 0, 0)))
	messages.clear()
	await frame()
	var ok: bool = await root.bake()
	await frame()
	var after := _baked(root)
	var dry: Dictionary = root.bake_dry_run()
	note(
		"a cordon round empty space after a full bake (it bakes what it was asked to: nothing; #377 was the inverted-box form, where the box was not what the mapper drew)",
		(
			"before %s; the bake returned %s, status %s, and left %d mesh triangles; dry run draft %s; messages %s"
			% [
				before,
				ok,
				root.get_last_bake_status(),
				after["mesh"].size(),
				dry.get("draft", "?"),
				messages,
			]
		)
	)
	await drop_root(root)


# ---------------------------------------------------------------------------
# What carries the list
# ---------------------------------------------------------------------------


## Three cordons, one named with odd characters, one off and one given inverted.
func _three_cordons(root: Node3D) -> void:
	root.cordon_enabled = true
	root.set_cordon_region(0, _around(SPOTS["A"]))
	root.set_cordon_region(1, _around(SPOTS["C"]))
	root.set_cordon_region(2, AABB(SPOTS["D"] + Vector3.ONE * 2.0, -Vector3.ONE * 4.0))
	root.set_cordon_name(0, "Arena")
	root.set_cordon_name(2, 'Vault "7" / ü,{x}')
	root.set_cordon_active(1, false)


func _through_the_hflevel() -> void:
	var path := PREFIX + "_level.hflevel"
	_written.append(path)
	var root: Node3D = await fresh_root("SaveCordons")
	_four_boxes(root)
	await frame()
	_three_cordons(root)
	var before: Dictionary = root.capture_cordons()
	note("cordons saved", before)
	root.save_hflevel(path, true)
	await HFVibe.settle_save(_tree, root)
	await drop_root(root)

	var loaded: Node3D = await fresh_root("LoadCordons")
	var ok: bool = loaded.load_hflevel(path)
	await frame()
	var after: Dictionary = loaded.capture_cordons()
	note("cordons after .hflevel load (load returned %s)" % ok, after)
	if HFVibe.canonical(before) != HFVibe.canonical(after):
		flag(
			"the cordon list does not survive a .hflevel save and load",
			"saved %s, loaded %s" % [HFVibe.canonical(before), HFVibe.canonical(after)]
		)
	await loaded.bake()
	await frame()
	var baked := _which(_baked(loaded)["mesh"])
	note("the loaded level bakes", baked)
	if baked.keys() != ["A", "D"]:
		flag(
			"a loaded level does not bake the cordons it was saved with",
			"expected A and D (C's cordon is off), baked %s" % [baked.keys()]
		)
	await drop_root(loaded)

	# The same file loaded over a level that already holds five cordons.
	var busy: Node3D = await fresh_root("BusyCordons")
	for i in range(5):
		busy.set_cordon_region(i, _around(Vector3(i * 10, 50, 0)))
		busy.set_cordon_name(i, "old %d" % i)
	busy.load_hflevel(path)
	await frame()
	var over: Dictionary = busy.capture_cordons()
	note("the same file loaded over a level holding five cordons", over)
	if HFVibe.canonical(over) != HFVibe.canonical(before):
		flag(
			"loading a .hflevel over a level keeps cordons the file does not hold",
			(
				"the file holds %s, the level now holds %s"
				% [HFVibe.canonical(before), HFVibe.canonical(over)]
			)
		)
	await drop_root(busy)


func _through_state_and_the_undo_snapshot() -> void:
	var root: Node3D = await fresh_root("StateCordons")
	_four_boxes(root)
	await frame()
	_three_cordons(root)
	var cordons: Dictionary = root.capture_cordons()

	# capture_state / restore_state: the cordons are settings, not state, so a
	# state action neither carries them nor puts them back (test_cordon_undo.gd).
	var state: Dictionary = root.state_system.capture_state(true)
	root.remove_cordon_region(1)
	root.set_cordon_name(0, "renamed")
	var changed: Dictionary = root.capture_cordons()
	root.state_system.restore_state(state)
	await frame()
	var after_restore: Dictionary = root.capture_cordons()
	note(
		"restore_state() after removing a cordon and renaming another",
		(
			"cordons %s the edit (by design: a state action does not carry settings)"
			% ("keep" if HFVibe.canonical(after_restore) == HFVibe.canonical(changed) else "lose")
		)
	)

	# The dock's undo goes through capture_cordons() / restore_cordons().
	root.restore_cordons(cordons)
	var snapshot: Dictionary = root.capture_cordons()
	root.remove_cordon_region(0)
	root.set_cordon_region(root.get_all_cordon_regions().size(), _around(SPOTS["B"]))
	root.set_cordon_active(0, false)
	root.restore_cordons(snapshot)
	var undone: Dictionary = root.capture_cordons()
	note("restore_cordons() after a remove, an add and a switch", undone)
	if HFVibe.canonical(undone) != HFVibe.canonical(snapshot):
		flag(
			"the undo snapshot does not put the cordon list back",
			"snapshot %s, after restore %s" % [HFVibe.canonical(snapshot), HFVibe.canonical(undone)]
		)
	await root.bake()
	await frame()
	var baked := _which(_baked(root)["mesh"])
	note("and the level then bakes", baked)
	if baked.keys() != ["A", "D"]:
		flag("after restore_cordons() the bake takes %s, expected A and D" % [baked.keys()])
	await drop_root(root)


func _through_bake_dirty() -> void:
	var root: Node3D = await fresh_root("DirtyCordons")
	_four_boxes(root)
	await frame()
	root.cordon_enabled = true
	root.set_cordon_region(0, _around(SPOTS["A"]))
	root.set_cordon_region(1, _around(SPOTS["C"]))
	await frame()
	var steps: Array = []
	var ok: bool = await root.bake_dirty()
	steps.append(["first bake_dirty", ok, _which(_baked(root)["mesh"]).keys(), ["A", "C"]])

	root.set_cordon_active(1, false)
	ok = await root.bake_dirty()
	steps.append(["C's cordon switched off", ok, _which(_baked(root)["mesh"]).keys(), ["A"]])

	var b_id := str(root.draft_brushes_node.get_child(1).get_meta("brush_id", ""))
	root.nudge_brushes_by_id([b_id], Vector3(0, 0, 0.5))
	ok = await root.bake_dirty()
	steps.append(
		["B, outside every cordon, nudged", ok, _which(_baked(root)["mesh"]).keys(), ["A"]]
	)

	root.set_cordon_name(0, "Arena")
	ok = await root.bake_dirty()
	(
		steps
		. append(
			[
				"a cordon renamed (status %s)" % root.get_last_bake_status(),
				ok,
				_which(_baked(root)["mesh"]).keys(),
				["A"],
			]
		)
	)

	root.set_cordon_region(1, _around(SPOTS["B"] + Vector3(0, 0, 0.5)))
	root.set_cordon_active(1, true)
	ok = await root.bake_dirty()
	steps.append(
		[
			"the second cordon moved onto B and on",
			ok,
			_which(_baked(root)["mesh"]).keys(),
			["A", "B"]
		]
	)

	for step in steps:
		var got: Array = step[2]
		got.sort()
		note("bake_dirty: %s" % step[0], "returned %s, baked %s" % [step[1], got])
		if got != step[3]:
			flag(
				"bake_dirty() after '%s' leaves the wrong brushes baked" % step[0],
				"expected %s, baked %s" % [step[3], got]
			)
	await drop_root(root)


# ---------------------------------------------------------------------------
# The exports
# ---------------------------------------------------------------------------


func _brushes_in_map(path: String) -> int:
	var text := FileAccess.get_file_as_string(path)
	var depth := 0
	var brushes := 0
	for line in text.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("{"):
			depth += 1
			if depth == 2:
				brushes += 1
		elif t.begins_with("}"):
			depth -= 1
	return brushes


func _through_the_exports() -> void:
	var root: Node3D = await fresh_root("ExportCordons")
	_four_boxes(root)
	await frame()
	root.cordon_enabled = true
	root.set_cordon_region(0, _around(SPOTS["A"]))
	root.set_cordon_region(1, _around(SPOTS["C"]))
	await frame()
	await root.bake()
	await frame()
	note("the bake the exports start from", _which(_baked(root)["mesh"]))

	var map_path := PREFIX + ".map"
	_written.append(map_path)
	var map_err: int = root.export_map(map_path, "valve220")
	note(
		".map export with two cordons on",
		(
			"error %d, %d brushes written of 4: the source level, not the bake (Hammer's own .map is the same)"
			% [map_err, _brushes_in_map(map_path)]
		)
	)

	var gltf_path := PREFIX + ".gltf"
	_written.append(gltf_path)
	# The glTF writer names its buffer after the file and the buffer's index.
	_written.append(PREFIX + ".bin")
	_written.append(PREFIX + "0.bin")
	var gltf_err: int = root.export_baked_gltf(gltf_path)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var read_err := doc.append_from_file(gltf_path, state)
	var gltf_spots := {}
	if gltf_err == OK and read_err == OK:
		var scene := doc.generate_scene(state)
		if scene:
			gltf_spots = _which(
				_triangles(scene, Transform3D.IDENTITY, {"mesh": [], "collision": []})["mesh"]
			)
			scene.free()
	note(
		"glTF export, read back",
		"write %d, read %d, geometry at %s: what was baked" % [gltf_err, read_err, gltf_spots]
	)
	if gltf_spots.keys() != ["A", "C"]:
		flag(
			"the glTF export does not hold what the cordoned bake held",
			"geometry at %s" % [gltf_spots]
		)

	var playtest_path := PREFIX + "_playtest.tscn"
	_written.append(playtest_path)
	var wrote: bool = root.export_playtest_scene(playtest_path)
	var playtest_spots := {}
	var packed = load(playtest_path) if wrote else null
	if packed is PackedScene:
		var inst: Node = (packed as PackedScene).instantiate()
		playtest_spots = _which(
			_triangles(inst, Transform3D.IDENTITY, {"mesh": [], "collision": []})["mesh"]
		)
		inst.free()
	note("playtest scene, loaded back", "written %s, geometry at %s" % [wrote, playtest_spots])

	# Export Game Scene, through the dock, the way a mapper ships.
	var dock = DockScene.instantiate()
	dock.set_script(ToastDock)
	dock.presets_dir = PREFIX + "_presets"
	_tree.get_root().add_child(dock)
	await frame()
	var prefs := HFUserPrefs.new()
	prefs.persistence_enabled = false
	dock.set_user_prefs(prefs)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	root.scene_file_path = GAME_SCENE_SOURCE
	_written.append(GAME_SCENE_OUT)
	await HFDockManageHandler.on_export_game_scene(dock)
	await frame()
	var game_spots := {}
	if FileAccess.file_exists(GAME_SCENE_OUT):
		var game = ResourceLoader.load(GAME_SCENE_OUT, "", ResourceLoader.CACHE_MODE_IGNORE)
		if game is PackedScene:
			var inst: Node = (game as PackedScene).instantiate()
			game_spots = _which(
				_triangles(inst, Transform3D.IDENTITY, {"mesh": [], "collision": []})["mesh"]
			)
			inst.free()
	var said_cordon := false
	for toast in dock.toasts:
		# The probe's own file name has "cordon" in it; read past the path.
		var said := str(toast[1]).replace(GAME_SCENE_OUT, "").to_lower()
		said_cordon = said_cordon or said.contains("cordon")
	note(
		"Export Game Scene with two cordons on",
		"the game scene holds geometry at %s; toasts %s" % [game_spots, dock.toasts]
	)
	if game_spots.size() < SPOTS.size() and not said_cordon:
		known(
			1205,
			"Export Game Scene ships only what the cordons hold, and says nothing about them",
			(
				(
					"four boxes A..D, cordons round A and C left on from iterating. Export Game"
					+ " Scene rebakes for the game (`_bake_game_scene()` calls"
					+ " `level_root.bake()`), and the bake honours the cordons, so the scene"
					+ " written holds geometry at %s only. The last toast is %s and no toast"
					+ " mentions a cordon. The guide calls the cordon a partial bake 'useful for"
					+ " iterating on part of a large map'; the game scene is the one bake that is"
					+ " never meant to be partial. The export already swaps the bake profile for"
					+ " its own bake and puts it back; it does nothing with the cordons, and its"
					+ " toast names the profile as if that were all that shaped the result."
				)
				% [game_spots.keys(), dock.toasts[-1] if not dock.toasts.is_empty() else "none"]
			)
		)
	dock.queue_free()
	await frame()
	await drop_root(root)


# ---------------------------------------------------------------------------
# The checks a playtest runs
# ---------------------------------------------------------------------------


## Two room floors. The cordon takes the first; the spawn stands on the second.
func _what_the_spawn_check_sees() -> void:
	var root: Node3D = await fresh_root("SpawnCordons")
	box(root, Vector3(6, 0.2, 6), Vector3(400, -0.1, 0))
	box(root, Vector3(6, 0.2, 6), Vector3(420, -0.1, 0))
	await frame()
	var spawn: Node3D = root.spawn_system.create_default_spawn()
	await root.bake()
	await frame()
	await physics_frame()
	await physics_frame()
	# Stand it where the validator wants it over the second floor.
	spawn.global_position = Vector3(420, 1.0, 0)
	var first: Dictionary = root.spawn_system.validate_spawn(spawn, 0)
	spawn.global_position = first.get("suggested_position", spawn.global_position)
	await physics_frame()
	var whole: Dictionary = root.spawn_system.validate_spawn(spawn, 0)
	note(
		"spawn at %s over the second floor, whole level baked" % spawn.global_position,
		"severity %s, issues %s" % [whole.get("severity"), whole.get("issues")]
	)

	root.cordon_enabled = true
	root.set_cordon_region(0, _around(Vector3(400, 0, 0), 4.0))
	await root.bake()
	await frame()
	await physics_frame()
	await physics_frame()
	var baked := _baked(root)
	var under_spawn := _count_in(
		baked["collision"], AABB(Vector3(417, -0.25, -3), Vector3(6, 0.3, 6))
	)
	var mask: int = root._layer_from_index(root.bake_collision_layer_index)
	var ray := PhysicsRayQueryParameters3D.create(
		spawn.global_position + Vector3.UP, spawn.global_position + Vector3.DOWN * 100.0
	)
	ray.collision_mask = 0xFFFFFFFF
	var hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(ray)
	var cordoned: Dictionary = root.spawn_system.validate_spawn(spawn, mask)
	note(
		"the same spawn after a bake with a cordon over the first floor only",
		(
			"baked collision triangles under the spawn: %d; a ray down on every layer hits %s; validate_spawn severity %s, issues %s, floor_hit %s"
			% [
				under_spawn,
				hit.get("collider", "nothing"),
				cordoned.get("severity"),
				cordoned.get("issues"),
				cordoned.get("floor_hit"),
			]
		)
	)
	if under_spawn == 0 and hit.is_empty() and int(cordoned.get("severity", 0)) < 2:
		known(
			1204,
			"the spawn check approves a spawn standing on a brush the cordon left out of the bake",
			(
				(
					"two 6x0.2x6 floors 20 apart, a cordon over the first, the spawn standing"
					+ " on the second. After the bake there are %d collision triangles under the"
					+ " spawn and a ray down on every layer hits nothing, so a player started"
					+ " there falls forever. validate_spawn() returns severity %s, issues %s,"
					+ " floor at %s. Since #1064 it also takes floors from the brushes themselves"
					+ " (`_brush_floor_under()` over `_brush_solids()`, which walks"
					+ " `root._iter_pick_nodes()` with no cordon or Bake Visible Only filter), so"
					+ " the brush the bake skipped is the floor it approves. Test Level and"
					+ " Export Playtest Build bake, ask this, and launch on anything under"
					+ " severity 2. The brush walk wants `bake_system.brush_bakes()` when it is"
					+ " standing in for the bake's collision."
				)
				% [
					under_spawn,
					cordoned.get("severity"),
					cordoned.get("issues"),
					cordoned.get("floor_hit"),
				]
			)
		)

	# The same walk with Bake Visible Only in place of the cordon: the second
	# floor hidden, so the bake leaves it out by the other scope setting.
	root.cordon_enabled = false
	root.bake_visible_only = true
	(root.draft_brushes_node.get_child(1) as Node3D).visible = false
	await root.bake()
	await frame()
	await physics_frame()
	await physics_frame()
	var hidden_under := _count_in(
		_baked(root)["collision"], AABB(Vector3(417, -0.25, -3), Vector3(6, 0.3, 6))
	)
	var hidden: Dictionary = root.spawn_system.validate_spawn(spawn, mask)
	note(
		"the same spawn with the second floor hidden and Bake Visible Only on (no cordon)",
		(
			"baked collision triangles under the spawn: %d; validate_spawn severity %s, issues %s"
			% [hidden_under, hidden.get("severity"), hidden.get("issues")]
		)
	)
	await drop_root(root)


func _what_the_navmesh_and_validate_see() -> void:
	var root: Node3D = await fresh_root("NavCordons")
	box(root, Vector3(6, 0.2, 6), Vector3(500, -0.1, 0))
	box(root, Vector3(6, 0.2, 6), Vector3(520, -0.1, 0))
	await frame()
	root.bake_navmesh = true
	root.cordon_enabled = true
	root.set_cordon_region(0, _around(Vector3(500, 0, 0), 4.0))
	await root.bake()
	await frame()
	var region := root.baked_container.get_node_or_null("BakedNavmesh") as NavigationRegion3D
	var span := "no navmesh"
	if region and region.navigation_mesh:
		var verts: PackedVector3Array = region.navigation_mesh.get_vertices()
		if not verts.is_empty():
			var nav_bounds := AABB(verts[0], Vector3.ZERO)
			for v in verts:
				nav_bounds = nav_bounds.expand(v)
			span = (
				"%d polygons spanning x %.1f..%.1f"
				% [
					region.navigation_mesh.get_polygon_count(),
					nav_bounds.position.x,
					nav_bounds.end.x
				]
			)
			if nav_bounds.end.x > 510.0:
				flag(
					"the navmesh reaches a floor the cordon left out",
					"navmesh spans %s with a cordon over x 496..504" % nav_bounds
				)
	note(
		"navmesh with a cordon over the first of two floors",
		"%s: it is parsed from the baked collision, so it follows the cordon" % span
	)
	var report: Dictionary = root.validate_level(false)
	var mentions := 0
	for issue in report.get("issues", []):
		if str(issue).to_lower().contains("cordon"):
			mentions += 1
	note(
		"validate_level() with the cordon on",
		(
			"%d issues, %d mentioning the cordon: it checks the whole source level, not the bake's area"
			% [report.get("issues", []).size(), mentions]
		)
	)
	await drop_root(root)
