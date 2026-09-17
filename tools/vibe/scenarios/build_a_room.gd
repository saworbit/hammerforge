@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## One map, built the way the user guide says to build one, start to finish.
##
## Every other scenario takes a slice. This one takes the whole sequence a
## mapper does on a first evening with the tool and reports what it finds at
## each step, because some of what goes wrong only goes wrong in sequence:
##
##   1. hollow a box into a room
##   2. clip a doorway out of one wall
##   3. build a corridor and a second room on the other side
##   4. texture the walls, floor and ceiling from the palette
##   5. put a light and a player spawn in
##   6. group the first room so it can be moved as one
##   7. validate
##   8. bake
##   9. export the playtest scene
##
## Nothing here is an edge case. Anything flagged is something a mapper meets
## on the way to their first playable room.

const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

## A room at the scale the project settled on in #625: the player is 1.6 units
## high, the grid snaps at 0.5 and a drawn brush is 2 units. An 8x3x8 room with
## 0.25 walls is a room you can stand in two of.
const ROOM := Vector3(8, 3, 8)
const WALL := 0.25


func id() -> String:
	return "build-a-room"


func summary() -> String:
	return "one map built end to end: hollow, doorway, corridor, texture, light, bake, playtest"


func run() -> void:
	var root: Node3D = await fresh_root("Map")
	root.hflevel_autosave_path = "user://vibe_build_a_room.hflevel"
	await _step_1_hollow_a_room(root)
	await _step_2_a_doorway(root)
	await _step_3_a_corridor(root)
	await _step_4_texture_it(root)
	await _step_5_light_and_spawn(root)
	await _step_6_group_the_room(root)
	await _step_7_validate(root)
	await _step_8_bake(root)
	await _step_9_playtest(root)


var _room_ids: Array = []


func _step_1_hollow_a_room(root: Node3D) -> void:
	note("-- 1. hollow a 512 box into a room --")
	var solid = box(root, ROOM, Vector3(0, ROOM.y * 0.5, 0))
	await frame()
	var can = root.can_hollow_brush(solid.brush_id, WALL)
	note("can_hollow says", "%s %s" % [can.ok, can.user_text()])
	var result = root.hollow_brush_by_id(solid.brush_id, WALL)
	await frame()
	note("hollow says", "%s %s" % [result.ok, result.user_text()])
	var brushes := _brushes(root)
	_room_ids = brushes.map(func(b): return str(b.brush_id))
	note("walls produced", brushes.size())
	if brushes.size() != 6:
		flag("hollowing a box does not give six walls", brushes.size())
	var inward := 0
	for b in brushes:
		inward += HFVibe.inward_face_count(b)
	note("inward-facing faces across the shell", inward)
	if inward > 0:
		flag("a hollowed room has faces pointing the wrong way", "%s of them" % inward)
	# A room you can stand in: the inner void should be ROOM - 2*WALL.
	var inner := _inner_void(brushes)
	note("inner void", inner)
	var want := ROOM - Vector3(WALL, WALL, WALL) * 2.0
	if not inner.is_equal_approx(want):
		flag("the room's inside is not size minus two walls", "%s, wanted %s" % [inner, want])


func _step_2_a_doorway(root: Node3D) -> void:
	note("-- 2. cut a 1.2x2 doorway through the -Z wall --")
	var before := _brushes(root).size()
	var cutter = box(root, Vector3(1.2, 2.0, WALL * 4.0), Vector3(0, 1.0, -ROOM.z * 0.5))
	await frame()
	var carve = root.carve_with_brush(cutter.brush_id)
	await frame()
	note("carve says", "%s %s" % [carve.ok, carve.user_text()])
	var after := _brushes(root)
	note("brushes: %s -> %s" % [before, after.size()])
	if not carve.ok:
		flag("carving a doorway out of a hollowed room fails", carve.user_text())
		return
	# The hole has to be a hole. Sample the middle of the doorway and ask
	# whether any brush still fills it.
	var doorway_centre := Vector3(0, 1.0, -ROOM.z * 0.5)
	var filled := _brush_containing(after, doorway_centre)
	note("a brush still occupies the doorway centre", filled != "")
	if filled != "":
		flag("the doorway is still solid after the carve", "brush %s covers it" % filled)
	var broken := 0
	for b in after:
		if not root.vertex_system.validate_convexity(b):
			broken += 1
	note("non-convex brushes after the carve", broken)
	if broken > 0:
		flag("carving a doorway leaves non-convex brushes", "%s of %s" % [broken, after.size()])


func _step_3_a_corridor(root: Node3D) -> void:
	note("-- 3. a corridor out of the doorway, and a second room --")
	var before := _brushes(root).size()
	# Floor, ceiling and two side walls of a 1.2-wide corridor running -Z.
	var z := -ROOM.z * 0.5 - 4.0
	box(root, Vector3(1.2 + WALL * 2, WALL, 8), Vector3(0, 0, z))
	await frame()
	box(root, Vector3(1.2 + WALL * 2, WALL, 8), Vector3(0, 2.0, z))
	await frame()
	box(root, Vector3(WALL, 2.0, 8), Vector3(-0.6 - WALL * 0.5, 1.0, z))
	await frame()
	box(root, Vector3(WALL, 2.0, 8), Vector3(0.6 + WALL * 0.5, 1.0, z))
	await frame()
	var second = box(root, ROOM, Vector3(0, ROOM.y * 0.5, z - 4.0 - ROOM.z * 0.5))
	await frame()
	var hollow = root.hollow_brush_by_id(second.brush_id, WALL)
	await frame()
	note("second room hollow says", "%s %s" % [hollow.ok, hollow.user_text()])
	note("brushes: %s -> %s" % [before, _brushes(root).size()])
	var invariants := HFVibe.check_invariants(root)
	note("invariants after the corridor", invariants if invariants.size() > 0 else "all held")
	for line in invariants:
		flag("invariant broken while building the corridor", line)


func _step_4_texture_it(root: Node3D) -> void:
	note("-- 4. texture it from the palette --")
	var added = root.add_prototype_materials()
	note("prototype materials added", added)
	note("palette", root.get_material_names())
	if root.get_materials().is_empty():
		flag("a fresh level has no materials to texture with")
		return
	var brushes := _brushes(root)
	var ids: Array = brushes.map(func(b): return str(b.brush_id))
	var touched = root.assign_material_to_whole_brushes(1, ids)
	note("faces given slot 1", touched)
	if touched == 0:
		flag("assigning a material to every brush touched no faces")
	var wrong := 0
	for b in brushes:
		for f in b.faces:
			if int(f.material_idx) != 1:
				wrong += 1
	note("faces not on slot 1 afterwards", wrong)
	if wrong > 0:
		flag("assigning a material to every brush left faces behind", "%s faces" % wrong)
	var usable = root.is_usable_material_slot(1)
	note("is_usable_material_slot(1)", usable)


func _step_5_light_and_spawn(root: Node3D) -> void:
	note("-- 5. a light and a player spawn --")
	var defs: Dictionary = root.get_entity_definitions()
	note("entity classes available", defs.keys().size())
	var light_class := ""
	for key in defs.keys():
		if str(key).find("light") >= 0:
			light_class = str(key)
			break
	note("light class used", light_class)
	if light_class == "":
		flag("no light entity class in entities.json", defs.keys())
	else:
		var light := DraftEntity.new()
		light.entity_class = light_class
		light.name = "room_light"
		light.position = Vector3(0, 2.5, 0)
		root.add_entity(light)
		await frame()
		note("entities after adding a light", root.get_entity_count())
	if root.spawn_system:
		var existing = root.spawn_system.get_active_spawn()
		if not existing:
			root.spawn_system.create_default_spawn()
			await frame()
		var spawn = root.spawn_system.get_active_spawn()
		note("spawn node", spawn.name if spawn else "none")
		note("spawn position", spawn.global_position if spawn else "n/a")
		note("spawn validation", root.spawn_system.validate_spawn(spawn, 1))


func _step_6_group_the_room(root: Node3D) -> void:
	note("-- 6. group the first room so it moves as one --")
	var nodes: Array = []
	for b in _brushes(root):
		if str(b.brush_id) in _room_ids:
			nodes.append(b)
	note("room brushes still present", nodes.size())
	if nodes.is_empty():
		flag(
			"none of the original room's brushes survived the doorway carve",
			(
				"the ids captured after the hollow no longer resolve, so a mapper who "
				+ "selected the room before carving has lost the selection"
			)
		)
		return
	root.group_selection("first_room", nodes)
	var members: Array = root.get_group_members("first_room")
	note("group members", members.size())
	if members.size() != nodes.size():
		flag("grouping the room kept %s of %s brushes" % [members.size(), nodes.size()])
	root.create_visgroup("rooms")
	root.add_selection_to_visgroup("rooms", nodes)
	root.set_visgroup_visible("rooms", false)
	await frame()
	var hidden := 0
	for n in nodes:
		if not (n as Node3D).visible:
			hidden += 1
	note("brushes hidden by the visgroup", "%s of %s" % [hidden, nodes.size()])
	if hidden != nodes.size():
		flag("hiding a visgroup left brushes visible", "%s of %s hidden" % [hidden, nodes.size()])
	root.set_visgroup_visible("rooms", true)
	await frame()


func _step_7_validate(root: Node3D) -> void:
	note("-- 7. validate --")
	var report: Dictionary = root.validate_level()
	for key in report.keys():
		note("validate.%s" % key, report[key])
	var issues = report.get("issues", [])
	if issues is Array and issues.size() > 0:
		note("issues on a level built entirely through the documented path", issues.size())
		for entry in issues:
			note("  issue", entry)
	note("missing dependencies", root.check_missing_dependencies())
	note("health", root.get_level_health())


func _step_8_bake(root: Node3D) -> void:
	note("-- 8. bake --")
	var dry: Dictionary = root.bake_dry_run()
	note("bake_dry_run", dry)
	var estimate: Dictionary = root.estimate_bake_time()
	note("estimate_bake_time", estimate)
	var started := Time.get_ticks_msec()
	# The mask the dock's Bake button passes, not the API default of 0: a bake
	# with no mask is correctly collisionless and measuring that measures the
	# scenario.
	var ok = await root.bake(true, false, 1)
	var elapsed := Time.get_ticks_msec() - started
	note("bake returned", ok)
	note("bake took", "%s ms (reported %s ms)" % [elapsed, root.get_last_bake_duration_ms()])
	note("bake status", root.get_last_bake_status())
	note("chunks", root.get_bake_chunk_count())
	var baked := _baked_meshes(root)
	note("baked MeshInstance3D nodes", baked.size())
	var tris := 0
	var surfaces := 0
	for m in baked:
		if m.mesh:
			surfaces += m.mesh.get_surface_count()
			for s in m.mesh.get_surface_count():
				tris += m.mesh.surface_get_array_len(s) / 3
	note("baked surfaces", surfaces)
	note("baked triangles (approx)", tris)
	if baked.is_empty():
		flag("a room, a corridor and a second room bake to no geometry")
	var collision := _collision_shapes(root)
	note("collision shapes in the bake", collision)
	note("bake_collision_mode", root.bake_collision_mode)
	if collision == 0:
		flag(
			"the bake produced no collision, so a playtest walks through walls",
			"bake_collision_mode is %s and the mask passed was 1" % root.bake_collision_mode
		)


func _step_9_playtest(root: Node3D) -> void:
	note("-- 9. export the playtest scene --")
	var path := "user://vibe_build_a_room_playtest.tscn"
	var ok = root.export_playtest_scene(path)
	note("export_playtest_scene", ok)
	if not ok:
		flag("exporting the playtest scene failed on a level built through the guide")
		return
	note("playtest scene bytes", HFVibe.file_size(path))
	var packed = load(path)
	if packed == null:
		flag("the exported playtest scene will not load back")
		return
	var inst = packed.instantiate()
	_tree.get_root().add_child(inst)
	await frame()
	var counts := {}
	_tally(inst, counts)
	note("playtest scene contents", counts)
	if int(counts.get("MeshInstance3D", 0)) == 0:
		flag("the playtest scene has no geometry in it")
	if int(counts.get("CharacterBody3D", 0)) == 0 and int(counts.get("CollisionShape3D", 0)) == 0:
		flag("the playtest scene has neither a player nor any collision", counts)
	inst.get_parent().remove_child(inst)
	inst.queue_free()


# --- helpers ---------------------------------------------------------------


func _brushes(root: Node3D) -> Array:
	var out: Array = []
	_collect(root, root, out)
	return out


func _collect(root: Node3D, node: Node, out: Array) -> void:
	for child in node.get_children():
		if root.is_brush_node(child):
			out.append(child)
		_collect(root, child, out)


func _brush_containing(brushes: Array, point: Vector3) -> String:
	for b in brushes:
		var extent: Vector3 = HFVibe.local_extent(b)
		var aabb := AABB((b as Node3D).global_position - extent * 0.5, extent)
		if aabb.has_point(point):
			return str(b.brush_id)
	return ""


## The empty box the six walls of a hollow surround.
func _inner_void(walls: Array) -> Vector3:
	if walls.is_empty():
		return Vector3.ZERO
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var inner_lo := -lo
	var inner_hi := lo
	for w in walls:
		var extent: Vector3 = HFVibe.local_extent(w)
		var c: Vector3 = (w as Node3D).global_position
		lo = lo.min(c - extent * 0.5)
		hi = hi.max(c + extent * 0.5)
	# The void is the outer box less the thinnest wall on each side, which for a
	# uniform hollow is the outer box less two wall thicknesses.
	var thinnest := INF
	for w in walls:
		var extent: Vector3 = HFVibe.local_extent(w)
		thinnest = minf(thinnest, minf(extent.x, minf(extent.y, extent.z)))
	var unused_ref = [inner_lo, inner_hi]
	return (hi - lo) - Vector3(thinnest, thinnest, thinnest) * 2.0


func _baked_meshes(root: Node3D) -> Array:
	var out: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if child is MeshInstance3D and not root.is_brush_node(child):
				out.append(child)
			stack.append(child)
	return out


## Counted with a loop rather than a closure: a GDScript lambda captures by
## value, so `_walk(root, func(node): n += 1)` increments a copy and always
## reports zero -- which reads exactly like a bake that produced no collision.
func _collision_shapes(root: Node3D) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if child is CollisionShape3D:
				n += 1
			stack.append(child)
	return n


func _tally(node: Node, counts: Dictionary) -> void:
	for child in node.get_children():
		var cls := child.get_class()
		counts[cls] = int(counts.get(cls, 0)) + 1
		_tally(child, counts)
