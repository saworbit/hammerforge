@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Where does a door go when it opens?
##
## `runtime-entities` settles that a baked `func_door` moves at all. This asks
## where to. `HFDoorRuntime` slides the holder the bake makes for a door along
## a compass `angle`, by the door's extent along that direction, at `speed`, and
## closes it `wait` seconds after it gets there. Each of those is a convention
## a mapper brings from somewhere: the Quake family's `angle` (with -1 for up and
## -2 for down), a door turned with the wall it sits in, a double door built as
## two leaves under one name, a Quake `.map` imported with its doors in it, a
## player standing in the doorway as it shuts.
##
## Every case is run the way a game runs it: baked, exported with
## `export_game_scene()`, the level root taken out of the tree, and the scene
## loaded back and instanced. What is measured is where the door's mesh and its
## collision actually are once the slide has finished, not what the script says
## it set.

const DoorRuntime = preload("res://addons/hammerforge/hf_door_runtime.gd")
const MapIOScript = preload("res://addons/hammerforge/map_io.gd")

## A door leaf a player fits through: 0.2 thick in X, 2.2 high, 1.6 wide in Z.
const LEAF := Vector3(0.2, 2.2, 1.6)

var _written: Array[String] = []
var _scenes: Array[Node] = []


func id() -> String:
	return "door-motion"


func summary() -> String:
	return "where a door goes when it opens: turned brushes, angles, lips, and what is in the way"


func run() -> void:
	await _angle_conventions()
	await _turned_doors()
	await _two_leaf_door()
	await _a_door_crossing_a_map_file()
	await _speed_edges()
	await _wait_edges()
	await _interrupted_motion()
	await _closing_on_a_body()
	await _door_basic()
	await _cleanup()


# ---------------------------------------------------------------------------
# Scaffolding
# ---------------------------------------------------------------------------


## Bake, export as a game scene, drop the editing root, and instance the scene
## the way a game loads it. The editing root is gone before the scene comes in,
## so there is only ever one dispatcher and one set of collision in the tree.
func _ship(root: Node3D, tag: String) -> Node3D:
	await root.bake(false, false)
	await frame()
	var path := "user://door-motion_%s.tscn" % tag
	var ok: bool = root.export_game_scene(path)
	_written.append(path)
	await drop_root(root)
	if not ok:
		flag("export_game_scene refused the level for case '%s'" % tag)
		return null
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if not (packed is PackedScene):
		flag("the exported game scene for '%s' did not load back" % tag)
		return null
	var scene := (packed as PackedScene).instantiate() as Node3D
	_tree.get_root().add_child(scene)
	_scenes.append(scene)
	await frame()
	await frame()
	return scene


func _unship(scene: Node) -> void:
	if is_instance_valid(scene):
		_scenes.erase(scene)
		var parent := scene.get_parent()
		if parent:
			parent.remove_child(scene)
		scene.queue_free()
	await frame()


func _find(node: Node, pred: Callable, out: Array) -> Array:
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		_find(c, pred, out)
	return out


func _movers(scene: Node) -> Array:
	return _find(scene, func(n: Node) -> bool: return n.get_script() == DoorRuntime, [])


## Wait for a door's slide to finish, on real frames, with a cap.
func _settle(door: Node, cap_seconds: float = 6.0) -> float:
	var start := Time.get_ticks_msec()
	while true:
		var tween = door.get("_tween")
		if tween == null or not (tween as Tween).is_valid() or not (tween as Tween).is_running():
			break
		if Time.get_ticks_msec() - start > int(cap_seconds * 1000.0):
			break
		await frame()
	await frame()
	return (Time.get_ticks_msec() - start) / 1000.0


func _seconds(s: float) -> void:
	await _tree.create_timer(s).timeout


## The world AABB of a door's mesh and of its collision, from the nodes the
## bake put under the holder.
func _door_boxes(door: Node3D) -> Dictionary:
	var mesh_box := AABB()
	var col_box := AABB()
	var have_mesh := false
	var have_col := false
	for mi in _find(door, func(n: Node) -> bool: return n is MeshInstance3D, []):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		mesh_box = b if not have_mesh else mesh_box.merge(b)
		have_mesh = true
	for cs in _find(door, func(n: Node) -> bool: return n is CollisionShape3D, []):
		var shape: Shape3D = (cs as CollisionShape3D).shape
		if shape == null:
			continue
		var b2: AABB = (cs as CollisionShape3D).global_transform * shape.get_debug_mesh().get_aabb()
		col_box = b2 if not have_col else col_box.merge(b2)
		have_col = true
	return {"mesh": mesh_box, "col": col_box, "has_mesh": have_mesh, "has_col": have_col}


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


## One func_door leaf, its properties set the way the Entity panel sets them, and
## optionally turned about Y the way the Build tab turns a brush. Returns the
## shipped scene, its door, and what the brush held before it was baked.
func _one_door(tag: String, props: Dictionary, yaw: float = 0.0) -> Dictionary:
	var root: Node3D = await fresh_root()
	var b = box(root, LEAF, Vector3(0, LEAF.y * 0.5, 0))
	await frame()
	root.tie_brushes_to_entity([str(b.brush_id)], "func_door", "gate")
	for k in props:
		root.set_entity_property(b, k, props[k])
	if yaw != 0.0:
		root.rotate_managed_nodes([str(b.brush_id)], [], 1, yaw, b.global_position)
	var held: Dictionary = (b.get_meta("brush_entity_data", {}) as Dictionary).duplicate()
	var basis: Basis = b.global_transform.basis
	var scene := await _ship(root, tag)
	var doors: Array = _movers(scene) if scene else []
	return {
		"scene": scene,
		"door": doors[0] if doors.size() > 0 else null,
		"doors": doors,
		"held": held,
		"basis": basis
	}


## Open a door and measure what moved, and by how much, once it has stopped.
func _open_and_measure(door: Node3D) -> Dictionary:
	var before := _door_boxes(door)
	var origin := door.global_position
	door.call("open")
	var took := await _settle(door)
	var after := _door_boxes(door)
	var travel: Vector3 = door.global_position - origin
	return {
		"travel": travel,
		"mesh_moved": after["mesh"].get_center() - before["mesh"].get_center(),
		"col_moved": after["col"].get_center() - before["col"].get_center(),
		"seconds": took,
		"before": before,
		"after": after,
	}


# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------


## Every angle the property can hold that means something somewhere, square to
## the world. The definition offers one float, "Move Angle (deg)", and the script
## says 0 is +X turning towards -Z, the Quake family's way round, with -1 and -2
## for up and down (#1210). A `lip` is the other Quake door key -- how much of the
## door is left showing -- and the definition does not offer one.
func _angle_conventions() -> void:
	var rows: Array = []
	var vertical: Dictionary = {}
	for a in [0.0, 90.0, 180.0, 270.0, 45.0, -1.0, -2.0]:
		var made := await _one_door("angle_%d" % int(a), {"angle": a})
		var door: Node3D = made["door"]
		if door == null:
			flag("a func_door with angle %s baked no door holder" % a)
			await _unship(made["scene"])
			continue
		var m := await _open_and_measure(door)
		var travel: Vector3 = m["travel"]
		var dir := travel.normalized() if travel.length() > 0.0001 else Vector3.ZERO
		rows.append(
			(
				"angle %s: travel %s (%.3f m), unit %s, mesh moved %s, collision moved %s, %.2fs"
				% [
					a,
					_v(travel),
					travel.length(),
					_v(dir),
					_v(m["mesh_moved"]),
					_v(m["col_moved"]),
					m["seconds"]
				]
			)
		)
		if not (m["mesh_moved"] as Vector3).is_equal_approx(m["col_moved"]):
			flag(
				"a door's mesh and collision moved by different amounts at angle %s" % a,
				"mesh %s, collision %s" % [_v(m["mesh_moved"]), _v(m["col_moved"])]
			)
		if a < 0.0:
			vertical[a] = {"dir": dir, "travel": travel.length()}
		await _unship(made["scene"])
	note("a 0.2 x 2.2 x 1.6 func_door, square to the world, opened at each angle", rows)

	var up: Dictionary = vertical.get(-1.0, {})
	var down: Dictionary = vertical.get(-2.0, {})
	if not up.is_empty() and not down.is_empty():
		var lifts := (up["dir"] as Vector3).is_equal_approx(Vector3.UP)
		var lowers := (down["dir"] as Vector3).is_equal_approx(Vector3.DOWN)
		var by_height := absf(float(up["travel"]) - LEAF.y) < 0.01
		by_height = by_height and absf(float(down["travel"]) - LEAF.y) < 0.01
		note(
			"angle -1 and -2, the Quake family's up and down",
			(
				"-1 moved %s by %.3f m, -2 moved %s by %.3f m, against a door %.1f m high"
				% [_v(up["dir"]), up["travel"], _v(down["dir"]), down["travel"], LEAF.y]
			)
		)
		if not (lifts and lowers and by_height):
			flag(
				"a func_door at angle -1 or -2 does not lift or lower by its height (#1210)",
				(
					"-1 moved %s by %.3f m and -2 moved %s by %.3f m"
					% [_v(up["dir"]), up["travel"], _v(down["dir"]), down["travel"]]
				)
			)

	# The lip key, set the only way one gets onto a brush entity besides an import.
	var lipped := await _one_door("lip", {"lip": 0.5})
	if lipped["door"]:
		var m2 := await _open_and_measure(lipped["door"])
		note(
			"a func_door given lip 0.5 (not a declared property)",
			"held %s; travel %.3f m" % [lipped["held"], (m2["travel"] as Vector3).length()]
		)
	await _unship(lipped["scene"])


## The same door turned 30 and 90 degrees about Y, as a doorway turned with the
## wall it sits in. Two questions: which way does it slide now, and does turning
## a brush entity turn its `angle` the way turning a point entity does? It did not,
## and a door turned 90 degrees slid out of its wall by its own thickness (#1210).
func _turned_doors() -> void:
	for yaw in [30.0, 90.0]:
		var made := await _one_door("yaw_%d" % int(yaw), {}, yaw)
		var door: Node3D = made["door"]
		if door == null:
			await _unship(made["scene"])
			continue
		var own_axis: Vector3 = ((made["basis"] as Basis) * Vector3(0, 0, 1)).normalized()
		var m := await _open_and_measure(door)
		var travel: Vector3 = m["travel"]
		var along := travel.dot(own_axis)
		var across := (travel - own_axis * along).length()
		note(
			"func_door turned %s degrees, angle left alone" % yaw,
			(
				"angle the brush holds after the turn: %s; its own width axis %s; travel %s: %.3f m along its own width, %.3f m across it"
				% [
					made["held"].get("angle", "(default 90)"),
					_v(own_axis),
					_v(travel),
					along,
					across
				]
			)
		)
		if absf(absf(along) - LEAF.z) > 0.01 or across > 0.01:
			flag(
				(
					"a func_door turned %s degrees does not slide along its own width by its width (#1210)"
					% yaw
				),
				(
					"travel %s: %.3f m along its own %.1f m width, %.3f m across it; the brush holds angle %s"
					% [_v(travel), along, LEAF.z, across, made["held"].get("angle", "(default 90)")]
				)
			)
		await _unship(made["scene"])

	# A point entity with an angle, turned the same way, for comparison.
	var root: Node3D = await fresh_root()
	var spawn = root._restore_entity_from_info(
		{
			"entity_type": "player_start",
			"transform": Transform3D(Basis.IDENTITY, Vector3(3, 0, 0)),
			"properties": {"angle": 0.0},
			"name": "spawn"
		}
	)
	await frame()
	root.rotate_managed_nodes([], [root.get_path_to(spawn)], 1, 90.0, spawn.global_position)
	note("a player_start's angle after the same 90 degree turn", spawn.entity_data.get("angle"))
	await drop_root(root)


## Two leaves tied under one name, side by side across a 3.2 m doorway: the
## guide's "a door of several leaves". Opened through the dispatcher, from a
## trigger, as a game opens it.
func _two_leaf_door() -> void:
	var root: Node3D = await fresh_root()
	var left = box(root, LEAF, Vector3(0, LEAF.y * 0.5, -LEAF.z * 0.5))
	var right = box(root, LEAF, Vector3(0, LEAF.y * 0.5, LEAF.z * 0.5))
	var plate = box(root, Vector3(1, 1, 1), Vector3(4, 0.5, 0))
	await frame()
	root.tie_brushes_to_entity([str(left.brush_id), str(right.brush_id)], "func_door", "pair")
	root.tie_brushes_to_entity([str(plate.brush_id)], "trigger_once", "plate")
	root.add_entity_output(plate, "OnStartTouch", "pair", "Open")
	# Can one leaf be given its own direction through the panel's setter?
	root.set_entity_property(left, "angle", 270.0)
	note(
		"after setting angle 270 on the left leaf",
		(
			"left holds %s, right holds %s"
			% [
				left.get_meta("brush_entity_data", {}).get("angle"),
				right.get_meta("brush_entity_data", {}).get("angle")
			]
		)
	)
	root.set_entity_property(left, "angle", 90.0)
	var scene := await _ship(root, "two_leaf")
	if scene == null:
		return
	var doors: Array = _movers(scene)
	note("door holders baked for two leaves under one name", doors.size())
	var dispatcher: Node = scene.get_node_or_null("HFIODispatcher")
	if dispatcher == null or doors.size() != 2:
		flag("the two-leaf door did not bake into two holders and a dispatcher", doors.size())
		await _unship(scene)
		return
	var origins: Array = doors.map(func(d: Node3D) -> Vector3: return d.global_position)
	dispatcher.call("fire", "plate", "OnStartTouch", "")
	for d in doors:
		await _settle(d)
	var spans: Array = []
	for d in doors:
		var cb: AABB = _door_boxes(d)["col"]
		spans.append(Vector2(cb.position.z, cb.end.z))
	# How much of the doorway, z in [-1.6, 1.6], is still covered by a leaf.
	var lo := -LEAF.z
	var hi := LEAF.z
	var covered := 0.0
	var pieces: Array = []
	for s in spans:
		var a := clampf((s as Vector2).x, lo, hi)
		var b := clampf((s as Vector2).y, lo, hi)
		if b > a:
			pieces.append(Vector2(a, b))
	pieces.sort_custom(func(p, q): return p.x < q.x)
	var cursor := lo
	for p in pieces:
		var a2: float = maxf(p.x, cursor)
		if p.y > a2:
			covered += p.y - a2
			cursor = p.y
	var moved: Array = []
	for i in doors.size():
		moved.append(_v((doors[i] as Node3D).global_position - (origins[i] as Vector3)))
	note("each leaf's travel", moved)
	note(
		"each leaf's collision z-span after Open",
		spans.map(func(s): return "%.2f..%.2f" % [s.x, s.y])
	)
	note("doorway still covered after Open", "%.2f of %.2f m" % [covered, hi - lo])
	if covered > 0.01:
		flag(
			"a two-leaf func_door does not clear its doorway (#1217)",
			(
				(
					"Two 1.6 m leaves tied under one name across a 3.2 m doorway, opened through "
					+ "the dispatcher: each slid %s, and %.2f m of the 3.2 m doorway is still shut. "
					+ "Every leaf of one door should travel the whole door's extent along its angle, "
					+ "as a Quake-family func_door of several brushes does."
				)
				% [", ".join(moved), covered]
			)
		)
	await _unship(scene)


## A door with angle 90 going out through `.map` with this project's own axis
## conversion, and what the same key means on the other side. The file is Z-up;
## `MapIO.from_map_axes()` says how its directions come into Godot.
func _a_door_crossing_a_map_file() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, LEAF, Vector3(0, LEAF.y * 0.5, 0))
	await frame()
	root.tie_brushes_to_entity([str(b.brush_id)], "func_door", "gate")
	root.set_entity_property(b, "angle", 90.0)
	var map_path := "user://door-motion_door.map"
	_written.append(map_path)
	var err: int = root.export_map(map_path)
	note("export_map with the defaults (quake, metres to units, axes converted)", error_string(err))
	var text := FileAccess.get_file_as_string(map_path)
	var angle_line := ""
	var axis_line := ""
	for line in text.split("\n"):
		if line.contains('"angle"'):
			angle_line = line.strip_edges()
		if line.contains("_hf_axis_convention"):
			axis_line = line.strip_edges()
	note("the door's angle in the file", angle_line)
	note("the axis convention the file records", axis_line)
	await drop_root(root)

	# What angle 90 means in that file's frame, brought into Godot by this
	# project's own conversion: Quake's angle 90 is +Y, north.
	var quake_dir := Vector3(cos(deg_to_rad(90.0)), sin(deg_to_rad(90.0)), 0.0)
	var file_means: Vector3 = MapIOScript.from_map_axes(quake_dir)
	note("Quake-family angle 90 (file +Y), through MapIO.from_map_axes()", _v(file_means))

	# Import it back and run it.
	var back: Node3D = await fresh_root()
	var err_in: int = back.import_map(map_path)
	note("import_map of the same file", error_string(err_in))
	var doors_back: Array = []
	for d in back.draft_brushes_node.get_children():
		if str(d.get_meta("brush_entity_class", "")) == "func_door":
			doors_back.append(d)
	if doors_back.is_empty():
		flag("the func_door did not come back from its own .map export")
		await drop_root(back)
		return
	note(
		"angle the imported door holds",
		doors_back[0].get_meta("brush_entity_data", {}).get("angle")
	)
	var scene := await _ship(back, "map_door")
	var movers: Array = _movers(scene) if scene else []
	if movers.is_empty():
		await _unship(scene)
		return
	var m := await _open_and_measure(movers[0])
	var dir: Vector3 = (m["travel"] as Vector3).normalized()
	note("the imported door, opened here", "%s, unit %s" % [_v(m["travel"]), _v(dir)])
	if dir.dot(file_means) < 0.99:
		flag(
			"a func_door crossing a .map does not open the way the file's angle means (#1210)",
			(
				(
					"The .map export writes %s into a file that records %s; in that Z-up file angle "
					+ "90 is +Y (north), which MapIO.from_map_axes() brings in as Godot %s, and the "
					+ "door read back opens %s."
				)
				% [angle_line, axis_line, _v(file_means), _v(dir)]
			)
		)
	await _unship(scene)


## Speed at 0, below 0, and slow. The definition gives no range.
func _speed_edges() -> void:
	var rows: Array = []
	for s in [0.0, -2.0, 0.5]:
		var made := await _one_door(
			"speed_%s" % str(s).replace("-", "m").replace(".", "_"), {"speed": s}
		)
		var door: Node3D = made["door"]
		if door == null:
			await _unship(made["scene"])
			continue
		var origin := door.global_position
		door.call("open")
		await _seconds(1.0)
		var moved := (door.global_position - origin).length()
		rows.append(
			"speed %s: %.3f m in 1 s of game time (full travel is %.1f m)" % [s, moved, LEAF.z]
		)
		await _unship(made["scene"])
	note("how far a door gets in one second", rows)
	note(
		"what speed 0 and below means",
		(
			"_move_to() divides by maxf(speed, 0.01) (hf_door_runtime.gd:222), so 0 and every "
			+ "negative speed are one centimetre a second: 160 s to open a 1.6 m door, and the "
			+ "wait only starts once it arrives. In the Quake family 0 means the default (100 "
			+ "units/s). Not flagged: it is a value a mapper has to type, the definition has no "
			+ "range to stop it, and Validate could say so."
		)
	)


## `wait` at 0, -1 and a small positive value. The script says zero or less
## stays open; Quake's -1 stays open and its 0 closes at once.
func _wait_edges() -> void:
	var rows: Array = []
	for w in [0.4, 0.0, -1.0]:
		var made := await _one_door(
			"wait_%s" % str(w).replace("-", "m").replace(".", "_"), {"wait": w}
		)
		var door: Node3D = made["door"]
		if door == null:
			await _unship(made["scene"])
			continue
		var origin := door.global_position
		door.call("open")
		await _settle(door)
		var at_open := (door.global_position - origin).length()
		# Long enough for a 0.4 s wait and the 0.8 s slide back, with room.
		await _seconds(2.0)
		var later := (door.global_position - origin).length()
		rows.append(
			(
				"wait %s: %.3f m open on arrival, %.3f m open 2 s later, is_open %s"
				% [w, at_open, later, door.call("is_open")]
			)
		)
		if w > 0.0 and later > 0.05:
			flag(
				"a door with wait %s did not close itself" % w,
				"%.3f m open 2 s after arriving" % later
			)
		await _unship(made["scene"])
	note("wait at its edges (guide: zero or less stays open)", rows)


## Inputs arriving while the door is still moving.
func _interrupted_motion() -> void:
	var rows: Array = []

	# Open while opening: the second Open is ignored, the slide carries on.
	var made := await _one_door("reopen", {"wait": 0.0})
	var door: Node3D = made["door"]
	if door:
		var origin := door.global_position
		var opened := [0]
		door.connect("opened", func() -> void: opened[0] += 1)
		door.call("open")
		await _seconds(0.3)
		door.call("open")
		await _settle(door)
		rows.append(
			(
				"Open, Open at 0.3 s: ends %.3f m out, opened emitted %d time(s)"
				% [(door.global_position - origin).length(), opened[0]]
			)
		)
	await _unship(made["scene"])

	# Close while opening: it turns round and stays shut.
	made = await _one_door("close_mid", {"wait": 0.3})
	door = made["door"]
	if door:
		var origin2 := door.global_position
		door.call("open")
		await _seconds(0.3)
		var mid := (door.global_position - origin2).length()
		door.call("close")
		await _settle(door)
		await _seconds(1.5)
		rows.append(
			(
				"Open, Close at %.2f m out: %.3f m out 1.5 s after it shut, is_open %s"
				% [mid, (door.global_position - origin2).length(), door.call("is_open")]
			)
		)
		if (door.global_position - origin2).length() > 0.05:
			flag(
				"a door closed while opening opened itself again",
				_v(door.global_position - origin2)
			)
	await _unship(made["scene"])

	# Toggle while opening closes it.
	made = await _one_door("toggle_mid", {"wait": 0.0})
	door = made["door"]
	if door:
		var origin3 := door.global_position
		door.call("toggle")
		await _seconds(0.3)
		door.call("toggle")
		await _settle(door)
		rows.append(
			(
				"Toggle, Toggle at 0.3 s: %.3f m out, is_open %s"
				% [(door.global_position - origin3).length(), door.call("is_open")]
			)
		)
	await _unship(made["scene"])

	# A stale self-close: open, arrive (wait 1.0 arms), close, reopen before the
	# first timer runs out. The first timer must not shut the second opening.
	made = await _one_door("stale_timer", {"wait": 1.0})
	door = made["door"]
	if door:
		var origin4 := door.global_position
		door.call("open")
		await _settle(door)
		var arrived := Time.get_ticks_msec()
		await _seconds(0.3)
		door.call("close")
		await _seconds(0.2)
		door.call("open")
		await _settle(door)
		# Past the first timer's 1.0 s, short of the second's.
		while Time.get_ticks_msec() - arrived < 1300:
			await frame()
		var out := (door.global_position - origin4).length()
		(
			rows
			. append(
				(
					"Open, arrive, Close at +0.3 s, Open at +0.5 s: %.3f m out at +1.3 s (first timer was due at +1.0 s)"
					% out
				)
			)
		)
		if out < LEAF.z - 0.05:
			flag(
				"a door's first self-close timer shut it after it was reopened", "%.3f m out" % out
			)
	await _unship(made["scene"])
	note("inputs that arrive mid-slide", rows)


## A player standing in the doorway as the door shuts on them. The door is a
## StaticBody3D under a Node3D the script tweens, so it is moved by teleport
## every frame. The body is the playtest player's capsule, and it runs
## move_and_slide() every physics frame the way the playtest controller does.
func _closing_on_a_body() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	# The jamb the door shuts against, on its -Z side.
	box(root, Vector3(0.2, LEAF.y, 2.0), Vector3(0, LEAF.y * 0.5, -LEAF.z * 0.5 - 1.0))
	var b = box(root, LEAF, Vector3(0, LEAF.y * 0.5, 0))
	await frame()
	root.tie_brushes_to_entity([str(b.brush_id)], "func_door", "gate")
	root.set_entity_property(b, "wait", 0.0)
	# +Z, away from the jamb, so it shuts back against it with the player between.
	root.set_entity_property(b, "angle", 270.0)
	var scene := await _ship(root, "body")
	var doors: Array = _movers(scene) if scene else []
	if doors.is_empty():
		await _unship(scene)
		return
	var door: Node3D = doors[0]
	door.call("open")
	await _settle(door)

	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	cs.shape = cap
	body.add_child(cs)
	_tree.get_root().add_child(body)
	_scenes.append(body)
	body.global_position = Vector3(0, 0.82, -0.4)
	for _i in 10:
		await _tree.physics_frame
		body.velocity = Vector3(0, -1, 0)
		body.move_and_slide()
	var stood := body.global_position
	door.call("close")
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2000:
		await _tree.physics_frame
		body.velocity = Vector3(0, -1, 0)
		body.move_and_slide()
	var col: AABB = _door_boxes(door)["col"]
	var p := body.global_position
	# Capsule against the closed door's box, in the horizontal plane.
	var nearest := Vector2(
		clampf(p.x, col.position.x, col.end.x), clampf(p.z, col.position.z, col.end.z)
	)
	var gap := Vector2(p.x, p.z).distance_to(nearest)
	var inside := gap < cap.radius - 0.01
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = cs.global_transform
	q.exclude = [body.get_rid()]
	var hits: Array = body.get_world_3d().direct_space_state.intersect_shape(q, 8)
	var hit_names: Array = hits.map(
		func(h: Dictionary) -> String: return str((h["collider"] as Node).name)
	)
	note("player capsule before the door shut", _v(stood))
	note("player capsule 2 s after Close", _v(p))
	note("closed door's collision box", "%s .. %s" % [_v(col.position), _v(col.end)])
	note("is_open after Close", door.call("is_open"))
	note(
		"the capsule's overlap with the closed door",
		"%.3f m (radius %.2f)" % [maxf(0.0, cap.radius - gap), cap.radius]
	)
	note("what the capsule intersects now", hit_names)
	if not inside:
		note(
			"a door shutting on a player",
			(
				(
					"not flagged: the door does not stop or go back for what is in the way, and "
					+ "the capsule was shoved %.3f m sideways out of the door's thickness by "
					+ "move_and_slide()'s recovery, onto one side of the doorway, rather than being "
					+ "left inside it. The door is a StaticBody3D under a tweened Node3D, which "
					+ "Godot recommends AnimatableBody3D for; that is a design note, not a defect "
					+ "this run can show."
				)
				% absf(p.x - stood.x)
			)
		)
	if inside:
		flag(
			"a func_door shuts through a player standing in the doorway",
			(
				(
					"The playtest player's capsule (r 0.35, h 1.6) stood at %s in the doorway, "
					+ "running move_and_slide() every physics frame. Close was not refused, the door "
					+ "did not stop or go back, and 2 s later the capsule is at %s with %.3f m of "
					+ "it inside the closed door's collision (%s), intersecting %s. The door is a "
					+ "StaticBody3D whose parent Node3D is tweened (hf_door_runtime.gd:226-227, "
					+ '`_tween.tween_property(self, "position", target, duration)`), so the body '
					+ "is teleported each frame and carries no velocity; a CharacterBody3D's "
					+ "recovery cannot push the player out ahead of it once the jamb is behind "
					+ "them. Nothing in the script checks what is in the way (Quake doors go back "
					+ "when blocked; Godot's own answer for a moving collider is AnimatableBody3D). "
					+ "In a game the player is stuck in the door or pops out on whichever side "
					+ "recovery picks."
				)
				% [
					_v(stood),
					_v(p),
					cap.radius - gap,
					"%s..%s" % [_v(col.position), _v(col.end)],
					hit_names
				]
			)
		)
	_scenes.erase(body)
	body.queue_free()
	await _unship(scene)


## `door_basic`, both ways a mapper can place one: as a point entity (the
## palette offers it) and tied to a brush.
func _door_basic() -> void:
	var root: Node3D = await fresh_root()
	var placed = (
		root
		. _restore_entity_from_info(
			{
				"entity_type": "door_basic",
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 1, 3)),
				"properties": {},
				"name": "pdoor",
				"entity_name": "pdoor",
			}
		)
	)
	var plate = box(root, Vector3(1, 1, 1), Vector3(4, 0.5, 0))
	var bdoor = box(root, LEAF, Vector3(-3, LEAF.y * 0.5, 0))
	await frame()
	root.tie_brushes_to_entity([str(plate.brush_id)], "trigger_once", "plate")
	root.tie_brushes_to_entity([str(bdoor.brush_id)], "door_basic", "bdoor")
	root.add_entity_output(plate, "OnStartTouch", "pdoor", "Open")
	root.add_entity_output(plate, "OnStartTouch", "bdoor", "Open")
	note("door_basic placed as a point entity", placed != null)
	var scene := await _ship(root, "door_basic")
	if scene == null:
		return
	var point: Node3D = null
	for n in _find(
		scene, func(n: Node) -> bool: return str(n.get_meta("entity_name", "")) == "pdoor", []
	):
		point = n
	var movers: Array = _movers(scene)
	var bmover: Node3D = movers[0] if movers.size() > 0 else null
	if point:
		var meshes := _find(point, func(n: Node) -> bool: return n is VisualInstance3D, []).size()
		var bodies := _find(point, func(n: Node) -> bool: return n is CollisionObject3D, []).size()
		note(
			"the point door_basic in the game scene",
			(
				"%s (%s), script %s, %d visual and %d collision node(s) under it"
				% [
					point.name,
					point.get_class(),
					point.get_script().resource_path.get_file() if point.get_script() else "none",
					meshes,
					bodies
				]
			)
		)
	var p0: Vector3 = point.global_position if point else Vector3.ZERO
	var b0: Vector3 = bmover.global_position if bmover else Vector3.ZERO
	var dispatcher: Node = scene.get_node_or_null("HFIODispatcher")
	if dispatcher:
		dispatcher.call("fire", "plate", "OnStartTouch", "")
	if bmover:
		await _settle(bmover)
	await frame()
	if point:
		note("the point door_basic after Open", "moved %s" % _v(point.global_position - p0))
	if bmover:
		note(
			"door_basic tied to a brush after Open",
			(
				"moved %s (speed %s, wait %s, angle %s: door_basic declares speed and locked only)"
				% [
					_v(bmover.global_position - b0),
					bmover.get("speed"),
					bmover.get("wait"),
					bmover.get("angle")
				]
			)
		)
	note(
		"why a point door_basic is not flagged",
		(
			"it ships as its editor marker: a Node3D with no mesh, no collision and no script "
			+ "that answers Open, because its class is Node3D and _playtest_node_for_entity() "
			+ "returns null for that. #682 kept it for old levels and named func_door the one "
			+ "to use; the guide's 'A door that moves' is about brushes tied to it."
		)
	)
	await _unship(scene)


func _cleanup() -> void:
	for s in _scenes.duplicate():
		if is_instance_valid(s):
			await _unship(s)
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	note("files written and removed", _written.size())
