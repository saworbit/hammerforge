@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## An outdoor level, built end to end.
##
## `build-a-room` walks a mapper's first evening indoors: hollow a room, carve a
## doorway, texture it, light it, bake, playtest. An outdoor level is a different
## set of tools and nothing in the sweep runs them in sequence — terrain from a
## noise heightmap, three ground textures painted onto it, a building placed on
## top of it, foliage scattered over it, a spawn on the ground, a bake, and the
## playtest.
##
## Every step here is one a mapper does. The question at each one is whether the
## step after it can still see what the step before it made.


func id() -> String:
	return "build-outdoors"


func summary() -> String:
	return "a whole outdoor level: terrain, ground textures, a building, foliage, bake, playtest"


const PROTO := "res://addons/hammerforge/icon.png"


func run() -> void:
	await _the_evening()


func _walk(node: Node, out: Array) -> Array:
	out.append(node)
	for c in node.get_children():
		_walk(c, out)
	return out


func _classes(node: Node) -> Dictionary:
	var counts: Dictionary = {}
	for n in _walk(node, []):
		counts[n.get_class()] = int(counts.get(n.get_class(), 0)) + 1
	return counts


func _the_evening() -> void:
	var root: Node3D = await fresh_root()

	# --- 1. Ground. A noise heightmap is how an outdoor level starts.
	var t := Time.get_ticks_msec()
	root.generate_heightmap_noise({})
	await frame()
	note("noise terrain generated", "%d ms" % (Time.get_ticks_msec() - t))
	note("paint memory", "%d bytes" % root.get_paint_memory_bytes())
	var layer = root.paint_layers.get_active_layer() if root.paint_layers else null
	if layer == null:
		flag("generate_heightmap_noise left no active paint layer")
		return
	note("the layer it made", "%s, height_scale %s" % [layer.display_name, layer.height_scale])

	# A terrain a person can walk over rather than a moon.
	root.set_heightmap_scale(4.0)
	await frame()
	note("height scale set to 4 units", layer.height_scale)

	# --- 2. Ground textures. Three slots is what the blend shader offers.
	for slot in [1, 2, 3]:
		root.set_terrain_slot_texture(slot, PROTO)
	await frame()
	note("terrain slot paths", layer.terrain_slot_paths)
	var filled := 0
	for p in layer.terrain_slot_paths:
		if str(p) != "":
			filled += 1
	if filled == 0:
		flag(
			"set_terrain_slot_texture stored nothing",
			"three slots set to an existing texture and all three read back empty"
		)

	# --- 2b. The ground has to be painted before there is anything for the
	# heightmap to displace. A noise heightmap on its own is a height field over
	# cells nobody has claimed.
	var painted := 0
	for y in range(-16, 16):
		for x in range(-16, 16):
			layer.set_cell(Vector2i(x, y), true)
			painted += 1
	await frame()
	note("ground cells painted", painted)

	# --- 3. The terrain has to become geometry before anything can stand on it.
	if root.paint_system and root.paint_system.has_method("regenerate_paint_layers"):
		t = Time.get_ticks_msec()
		root.paint_system.regenerate_paint_layers()
		for _i in 8:
			await frame()
		note("regenerate_paint_layers", "%d ms" % (Time.get_ticks_msec() - t))
	# The generated terrain lives under the reconciler's own holders, not under
	# `generated_floors` -- `generated_floors` is the container the *brush* paint
	# path uses, and a heightmap layer never touches it.
	# Three holders, not one. `floors_root` is where the *brush* paint path puts
	# flat floor rects; a heightmap layer builds displaced chunks into
	# `heightmap_floors_root` instead, and the skirt walls go to `walls_root`.
	# Looking in only the first of the three reads as "the terrain built nothing".
	var rec = root.paint_tool.reconciler if root.paint_tool else null
	var holders: Dictionary = {}
	if rec:
		holders["floors_root"] = rec.floors_root
		holders["heightmap_floors_root"] = rec.heightmap_floors_root
		holders["walls_root"] = rec.walls_root
	var terrain_meshes := 0
	var terrain_names: Array = []
	for key in holders:
		var holder = holders[key]
		if holder == null or not is_instance_valid(holder):
			note("holder '%s'" % key, "absent")
			continue
		var here := 0
		for n in _walk(holder, []):
			if n is MeshInstance3D and n.mesh:
				here += 1
				terrain_names.append(n.name)
		note("holder '%s'" % key, "%d MeshInstance3D" % here)
		terrain_meshes += here
	note("terrain MeshInstance3D nodes across all three holders", terrain_meshes)
	note("their names", terrain_names.slice(0, 4))
	var gid_nodes: Array = []
	for n in _walk(root, []):
		if n.has_meta("hf_gid"):
			gid_nodes.append("%s (%s)" % [n.name, n.get_class()])
	note("nodes carrying hf_gid anywhere in the level", gid_nodes.size())
	if terrain_meshes == 0:
		flag(
			"a painted, heightmapped ground produces no terrain mesh",
			(
				(
					"%d cells painted on the active layer, a noise heightmap over them, and "
					+ "regenerate_paint_layers() built nothing to walk on"
				)
				% painted
			)
		)

	# --- 4. A building on top of it. Brushes and terrain in one level.
	for spec in [
		[Vector3(8, 0.3, 8), Vector3(0, 4.0, 0)],
		[Vector3(8, 3, 0.3), Vector3(0, 5.5, -4)],
		[Vector3(8, 3, 0.3), Vector3(0, 5.5, 4)],
		[Vector3(0.3, 3, 8), Vector3(-4, 5.5, 0)],
		[Vector3(0.3, 3, 8), Vector3(4, 5.5, 0)],
	]:
		box(root, spec[0], spec[1])
	await frame()
	note("brushes placed on the terrain", root.brush_system.get_live_brush_count())

	# --- 5. A spawn, and whether the validator likes it over terrain.
	if root.has_method("create_default_spawn"):
		root.create_default_spawn()
		await frame()
	var spawn: Node3D = null
	if root.entities_node:
		for c in root.entities_node.get_children():
			if str(c.get_meta("entity_type", c.get_meta("entity_class", ""))) == "player_start":
				spawn = c
	note("a spawn exists", spawn != null)

	# --- 6. Validate before baking, which is the habit the dock encourages.
	t = Time.get_ticks_msec()
	var report: Dictionary = root.validate_level()
	note("validate_level", "%d ms, %s" % [Time.get_ticks_msec() - t, report])

	# --- 7. Bake.
	t = Time.get_ticks_msec()
	var baked: bool = await root.bake(false, false)
	await frame()
	note("bake", "%s in %d ms" % [baked, Time.get_ticks_msec() - t])
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		flag("an outdoor level with terrain and brushes baked nothing")
		return
	note("baked container", _classes(container))
	var baked_terrain: Array = []
	for n in _walk(container, []):
		if str(n.name).begins_with("HMFloor") or str(n.name).contains("hf_floor"):
			baked_terrain.append(n.name)
	var has_terrain := not baked_terrain.is_empty()
	note("terrain nodes in the baked container", baked_terrain.size())
	note("named", baked_terrain.slice(0, 3))
	if not has_terrain:
		flag(
			"the terrain is not in the baked container",
			(
				"the heightmap layer builds its own meshes under generated_floors, and the "
				+ "bake produced only brush-sized geometry -- so a baked outdoor level is the "
				+ "building with no ground under it"
			)
		)

	# --- 8. Does the player land on the ground?
	if spawn:
		var validation: Dictionary = root.spawn_system.validate_spawn(spawn, 0)
		note("spawn validation severity", validation.get("severity", 0))
		note("spawn validation issues", validation.get("issues", PackedStringArray()))

	# --- 9. Ship it.
	var scene_path := "user://vibe_outdoors.tscn"
	var ok = root.export_playtest_scene(scene_path)
	note("export_playtest_scene", ok)
	if ResourceLoader.exists(scene_path):
		var packed: PackedScene = load(scene_path)
		var inst := packed.instantiate()
		note("the playtest scene", _classes(inst))
		var names: Array = _walk(inst, []).map(func(n: Node) -> String: return n.name)
		note("its node names", names)
		var scene_terrain: Array = []
		for n in _walk(inst, []):
			if str(n.name).begins_with("HMFloor") or str(n.name).contains("hf_floor"):
				scene_terrain.append(n.name)
		var terrain_in_scene := not scene_terrain.is_empty()
		note("terrain nodes in the playtest scene", scene_terrain.size())
		if not terrain_in_scene:
			flag(
				"the exported playtest scene has no terrain in it",
				(
					"export_playtest_scene() copies the children of `baked_container` and of "
					+ "`entities_node`, and the terrain lives under `generated_floors`, which is "
					+ "neither -- so the level a mapper presses Play on is the building floating "
					+ "over nothing"
				)
			)
		inst.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(scene_path))

	# --- 10. And the round trip, because an evening ends with Ctrl+S.
	var path := "user://vibe_outdoors.hflevel"
	root.save_hflevel(path)
	var settled: bool = await HFVibe.settle_save(_tree, root, 4000)
	note("save settled", "%s, %d bytes" % [settled, HFVibe.file_size(path)])
	var bytes := HFVibe.file_size(path)
	root.load_hflevel(path)
	await frame()
	note("brushes after the reload", root.brush_system.get_live_brush_count())
	var reloaded = root.paint_layers.get_active_layer() if root.paint_layers else null
	note("the terrain layer after the reload", reloaded.display_name if reloaded else null)
	note("its slot textures after the reload", reloaded.terrain_slot_paths if reloaded else null)
	note("paint memory after the reload", "%d bytes" % root.get_paint_memory_bytes())
	if bytes > 0 and reloaded == null:
		flag("the terrain layer did not survive the .hflevel", "saved %d bytes" % bytes)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
