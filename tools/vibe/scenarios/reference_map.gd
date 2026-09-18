@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The committed reference map, loaded from disk and taken through the chain.
##
## `examples-integrity` covers the five shipped examples, and they are small and
## each about one feature. This covers the one level in the repo that has the
## whole feature set in it at once: a shell with a doorway cut through it, fifteen
## materials, UVs anchored to world space across the floor to wall join, three
## tied brush entities wired to each other, a visgroup per wing, a spawn the
## validator approves, and the bake options a shipped level uses (#710).
##
## What makes it worth a scenario of its own is that the file is **committed**.
## `round-trip` and `persistence` both save a level and load it straight back, so
## they read a file the build that wrote it produced. Neither would notice a
## format change that stops last release's file from loading, because neither has
## last release's file. This one does.
##
## Rebuild it with:
##
##     godot --headless -s res://tools/build_reference_map.gd --path .
##
## The numbers below are what that build produces. When a deliberate change to
## the map moves them, rebuild and update them together. When they move on their
## own, the loader lost something.

const MAP_PATH := "res://addons/hammerforge/data/reference_map.hflevel"

const WANT_BRUSHES := 119
const WANT_ENTITIES := 6
const WANT_VISGROUPS := ["west_wing", "east_wing", "corridor"]
const WANT_TIED := 3
const WANT_IO := 3
const WANT_MATERIAL_SLOTS := 15
const WANT_UV_ANCHORED := 216


func id() -> String:
	return "reference-map"


func summary() -> String:
	return "the committed reference map, loaded from disk, validated, baked and exported"


func run() -> void:
	var root: Node3D = await fresh_root("Reference")
	if not FileAccess.file_exists(MAP_PATH):
		flag(
			"the reference map is missing",
			(
				(
					"%s is not in the tree. Rebuild it with tools/build_reference_map.gd, "
					+ "or this scenario is checking nothing."
				)
				% MAP_PATH
			)
		)
		return
	note("file bytes", _file_size(MAP_PATH))
	await _load_it(root)
	await _what_came_back(root)
	await _validate(root)
	await _bake(root)
	await _export(root)
	await _cost(root)


func _load_it(root: Node3D) -> void:
	note("-- load the committed file --")
	var started := Time.get_ticks_usec()
	var ok: bool = root.load_hflevel(MAP_PATH)
	note("load_hflevel returned", ok)
	note("load took", "%.1f ms" % (float(Time.get_ticks_usec() - started) / 1000.0))
	await frame()
	if not ok:
		flag(
			"the committed reference map no longer loads",
			(
				"nothing else in the repo reads a level file this build did not write, so "
				+ "this is the only thing that would have caught it"
			)
		)


## Every record the builder put in, counted on the way back out.
##
## Each of these is a thing `example_levels.json` cannot express, which is the
## reason the map exists. A count that drops is a record the save or the load
## stopped carrying.
func _what_came_back(root: Node3D) -> void:
	note("-- what survived the round trip --")
	var brushes := _brushes(root)
	note("brushes", brushes.size())
	if brushes.size() != WANT_BRUSHES:
		flag("brush count moved", "%d, expected %d" % [brushes.size(), WANT_BRUSHES])

	note("entities", root.get_entity_count())
	if root.get_entity_count() != WANT_ENTITIES:
		flag("entity count moved", "%d, expected %d" % [root.get_entity_count(), WANT_ENTITIES])

	var names := Array(root.get_visgroup_names())
	note("visgroups", names)
	for wanted in WANT_VISGROUPS:
		if not names.has(wanted):
			flag("a visgroup did not survive the round trip", wanted)

	var tied := 0
	var io := 0
	var slots: Dictionary = {}
	var anchored := 0
	for b in brushes:
		if str(b.get_meta("brush_entity_class", "")) != "":
			tied += 1
		io += (b.get_meta("entity_io_outputs", []) as Array).size()
		for f in b.faces:
			slots[int(f.material_idx)] = true
			if not f.uv_scale.is_equal_approx(Vector2.ONE) or f.uv_offset != Vector2.ZERO:
				anchored += 1
	if root.entities_node:
		for e in root.entities_node.get_children():
			io += (e.get_meta("entity_io_outputs", []) as Array).size()

	note("tied brushes", tied)
	if tied != WANT_TIED:
		flag("a tie did not survive the round trip", "%d, expected %d" % [tied, WANT_TIED])
	note("io connections", io)
	if io != WANT_IO:
		flag("a wire did not survive the round trip", "%d, expected %d" % [io, WANT_IO])
	note("distinct material slots", slots.keys().size())
	if slots.keys().size() != WANT_MATERIAL_SLOTS:
		flag(
			"the map came back with a different palette",
			"%d slots in use, expected %d" % [slots.keys().size(), WANT_MATERIAL_SLOTS]
		)
	note("faces with a non default UV transform", anchored)
	if anchored != WANT_UV_ANCHORED:
		flag(
			"the UV alignment did not survive the round trip",
			"%d faces, expected %d" % [anchored, WANT_UV_ANCHORED]
		)

	# The bake options travel in the file's settings half rather than its state,
	# so a level that loads its geometry and not its options bakes differently
	# from the one that was saved and nothing says so.
	note("bake_navmesh", root.bake_navmesh)
	note("bake_generate_occluders", root.bake_generate_occluders)
	note("bake_use_face_materials", root.bake_use_face_materials)
	for pair in [
		["bake_navmesh", root.bake_navmesh],
		["bake_generate_occluders", root.bake_generate_occluders],
		["bake_use_face_materials", root.bake_use_face_materials]
	]:
		if not bool(pair[1]):
			flag("a bake option the map was saved with came back off", pair[0])

	var inward := 0
	for b in brushes:
		inward += HFVibe.inward_face_count(b)
	note("inward facing faces", inward)
	if inward > 0:
		flag("the reference map loaded with faces pointing the wrong way", inward)


func _validate(root: Node3D) -> void:
	note("-- validate and invariants --")
	var report: Dictionary = root.validate_level()
	var issues = report.get("issues", [])
	note("validate issues", issues.size())
	for entry in issues:
		note("  issue", entry)
	if issues is Array and issues.size() > 0:
		flag("the reference map does not validate clean", issues)
	note("missing dependencies", root.check_missing_dependencies())
	note("health", root.get_level_health())
	var broken := HFVibe.check_invariants(root)
	note("invariants", broken if broken.size() > 0 else "all held")
	for line in broken:
		flag("invariant broken on the reference map", line)


func _bake(root: Node3D) -> void:
	note("-- bake with the options the file carries --")
	var started := Time.get_ticks_msec()
	var ok = await root.bake(true, false, 1)
	note("bake returned", ok)
	note("bake took", "%d ms" % (Time.get_ticks_msec() - started))
	note("bake status", root.get_last_bake_status())
	if not ok:
		flag("the reference map does not bake", root.get_last_bake_status())
		return
	await frame()
	var meshes := 0
	var navmesh := 0
	var occluders := 0
	for node in _descendants(root.baked_container):
		if node is MeshInstance3D:
			meshes += 1
		elif node is NavigationRegion3D:
			navmesh += 1
		elif node is OccluderInstance3D:
			occluders += 1
	note("baked meshes", meshes)
	note("navigation regions", navmesh)
	note("occluders", occluders)
	if meshes == 0:
		flag("baking the reference map produced no meshes")
	if navmesh == 0:
		flag(
			"the map asks for a navmesh and the bake made none",
			"bake_navmesh is %s" % root.bake_navmesh
		)
	if occluders == 0:
		flag(
			"the map asks for occluders and the bake made none",
			"bake_generate_occluders is %s" % root.bake_generate_occluders
		)


func _export(root: Node3D) -> void:
	note("-- export the playtest scene --")
	var path := "user://vibe_reference_map.tscn"
	var ok: bool = root.export_playtest_scene(path)
	note("export_playtest_scene returned", ok)
	if not ok:
		flag("the reference map does not export")
		return
	note("exported bytes", _file_size(path))
	var packed = load(path)
	if packed == null:
		flag("the exported reference scene does not load back")
		return
	var instance = packed.instantiate()
	note("exported root", instance.name)
	note("exported children", _descendants(instance).size())
	instance.free()


## What the map costs, on a real level rather than a grid of boxes.
##
## `level-scale` prices the curve on synthetic geometry. These are the numbers
## for a level with cut geometry, fifteen materials and per face UVs in it, which
## is the shape the curve is meant to predict.
func _cost(root: Node3D) -> void:
	note("-- what a real map costs --")
	var t := Time.get_ticks_usec()
	var state: Dictionary = root.capture_state()
	note("capture_state", "%.1f ms" % (float(Time.get_ticks_usec() - t) / 1000.0))
	note("snapshot", "%.1f KB" % (float(var_to_bytes(state).size()) / 1024.0))
	t = Time.get_ticks_usec()
	root.restore_state(state)
	note("restore_state", "%.1f ms" % (float(Time.get_ticks_usec() - t) / 1000.0))
	await frame()
	t = Time.get_ticks_usec()
	var report: Dictionary = root.validate_level()
	note("validate_level", "%.1f ms" % (float(Time.get_ticks_usec() - t) / 1000.0))
	note("validate still clean", (report.get("issues", []) as Array).is_empty())


func _brushes(root: Node3D) -> Array:
	var out: Array = []
	if not root.draft_brushes_node:
		return out
	for child in root.draft_brushes_node.get_children():
		if child.get("brush_id") != null:
			out.append(child)
	return out


func _descendants(node: Node) -> Array:
	var out: Array = []
	if not node or not is_instance_valid(node):
		return out
	for child in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return -1
	var size := f.get_length()
	f.close()
	return size
