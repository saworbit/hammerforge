@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Ctrl+S, close Godot, open the scene again.
##
## This is how a level actually persists. The `.hflevel` is a second copy that
## Save Level writes (#646, #650); the `.tscn` is what Godot loads when the
## mapper double-clicks the scene, and it is written by `PackedScene.pack()`
## over whatever HammerForge gave an `owner` to.
##
## `scene-weight` measures what that costs in bytes and `examples-integrity`
## checks the shipped examples build. Neither packs a level and opens it again.
## So: build a level with one of everything, pack it, instantiate it, and ask
## the reopened level the same questions as the original.
##
## `_get_editor_owner()` reads `tree.edited_scene_root`, which is null headless,
## so the owners the editor would assign are assigned here before packing --
## otherwise the scenario measures the harness.

const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")


func id() -> String:
	return "scene-reopen"


func summary() -> String:
	return "what a level is after being packed into its .tscn and opened again"


func run() -> void:
	await _pack_and_open()
	await _a_hidden_visgroup_across_a_save()
	await _every_other_registry()
	await _open_it_twice()


## A level with one of everything a mapper would have after an evening.
func _furnish(root: Node3D) -> void:
	root.auto_spawn_player = false
	var solid = box(root, Vector3(8, 3, 8), Vector3(0, 1.5, 0))
	await frame()
	root.hollow_brush_by_id(solid.brush_id, 0.25)
	await frame()
	box(root, Vector3(2, 0.25, 4), Vector3(0, 0.5, 6))
	await frame()

	root.add_prototype_materials()
	var ids: Array = []
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			ids.append(str(child.get("brush_id")))
	root.assign_material_to_whole_brushes(41, ids)

	# A face with hand-set UV parameters, so texturing has something to lose.
	root.set_face_uv_params(str(ids[0]), 0, Vector2(2, 2), Vector2(0.25, 0.5), deg_to_rad(30.0))

	root.create_visgroup("shell")
	var nodes: Array = []
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			nodes.append(child)
	root.add_selection_to_visgroup("shell", nodes)
	root.group_selection("shell_group", nodes.slice(0, 3))

	var lamp := DraftEntity.new()
	lamp.entity_type = "light_point"
	lamp.entity_class = "light_point"
	lamp.name = "lamp"
	root.add_entity(lamp)
	await frame()
	lamp.global_position = Vector3(0, 2.5, 0)
	var door := DraftEntity.new()
	door.entity_type = "door_basic"
	door.entity_class = "door_basic"
	door.name = "gate"
	root.add_entity(door)
	await frame()
	root.add_entity_output(lamp, "TurnOn", "gate", "Open", "", 0.0, false)

	root.cordon_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 8, 16))
	root.cordon_enabled = true
	root.grid_snap = 0.25
	root.texture_lock = false
	root.bake_chunk_size = 4.0
	root.hflevel_autosave_path = "user://vibe_scene_reopen.hflevel"
	await frame()


## The owners `_get_editor_owner()` would assign in the editor. Without them
## `pack()` writes an empty scene and every finding below would be the harness.
func _own(root: Node3D) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


func _pack(root: Node3D, path: String) -> PackedScene:
	_own(root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		flag("PackedScene.pack() failed", err)
		return null
	ResourceSaver.save(packed, path)
	return load(path)


func _describe(root: Node3D) -> Dictionary:
	var d := HFVibe.describe_level(root)
	d["visgroups"] = root.get_visgroup_names()
	d["group_members"] = root.get_group_members("shell_group").size()
	d["materials"] = root.get_materials().size()
	d["grid_snap"] = root.grid_snap
	d["texture_lock"] = root.texture_lock
	d["cordon_enabled"] = root.cordon_enabled
	d["cordon_aabb"] = root.cordon_aabb
	d["bake_chunk_size"] = root.bake_chunk_size
	d["hflevel_path"] = root.hflevel_autosave_path
	# The live source node is an object reference; two instantiations of the same
	# scene hold different ones and that is not a finding.
	var wires: Array = []
	for c in root.get_all_entity_connections():
		var copy: Dictionary = (c as Dictionary).duplicate()
		copy.erase("source")
		wires.append(copy)
	d["connections"] = wires
	d["brush_count"] = root.get_live_brush_count()
	d["entity_count"] = root.get_entity_count()
	return d


func _pack_and_open() -> void:
	note("-- a furnished level, packed and opened again --")
	var root: Node3D = await fresh_root("Map")
	await _furnish(root)
	var before := _describe(root)
	note("before: brushes %s, entities %s" % [before["brush_count"], before["entity_count"]])
	note("before: visgroups %s, group %s" % [before["visgroups"], before["group_members"]])
	note("before: connections", before["connections"])

	var path := "user://vibe_scene_reopen.tscn"
	var packed := _pack(root, path)
	if packed == null:
		return
	note("packed .tscn", "%s bytes" % HFVibe.file_size(path))

	# The original goes, the way closing the scene does.
	root.get_parent().remove_child(root)
	root.queue_free()
	await frame()
	await frame()

	var reopened: Node3D = packed.instantiate()
	_tree.get_root().add_child(reopened)
	await frame()
	await frame()
	if reopened.get("brush_system") == null:
		flag("a reopened level has no subsystems", "brush_system is null after two frames")
		return
	var after := _describe(reopened)
	note("after: brushes %s, entities %s" % [after["brush_count"], after["entity_count"]])
	note("after: visgroups %s, group %s" % [after["visgroups"], after["group_members"]])
	note("after: connections", after["connections"])

	diff_levels(before, after, "packing the level into its .tscn and opening it")

	# The things the level-wide diff does not reach.
	for key in [
		"visgroups",
		"group_members",
		"materials",
		"grid_snap",
		"texture_lock",
		"cordon_enabled",
		"cordon_aabb",
		"bake_chunk_size",
		"hflevel_path",
		"connections",
		"brush_count",
		"entity_count",
	]:
		if HFVibe.canonical(before[key]) != HFVibe.canonical(after[key]):
			flag(
				"reopening the scene changed '%s'" % key,
				"%s -> %s" % [HFVibe.canonical(before[key]), HFVibe.canonical(after[key])]
			)

	# And whether the reopened level is still editable, which is the point of it.
	var fresh_brush = box(reopened, Vector3(1, 1, 1), Vector3(0, 6, 0))
	await frame()
	note("a brush drawn in the reopened level", fresh_brush != null)
	if fresh_brush == null:
		flag("a reopened level cannot draw a brush")
	else:
		note("its id", fresh_brush.brush_id)
		var clash := 0
		for child in reopened.draft_brushes_node.get_children():
			if reopened.is_brush_node(child) and str(child.get("brush_id")) == str(
				fresh_brush.brush_id
			):
				clash += 1
		if clash > 1:
			flag(
				"a brush drawn in a reopened level gets an id another brush already has",
				"%s brushes answer to %s" % [clash, fresh_brush.brush_id]
			)
	var invariants := HFVibe.check_invariants(reopened)
	note("invariants in the reopened level", invariants if invariants.size() > 0 else "all held")
	for line in invariants:
		flag("invariant broken in a reopened level", line)


## Visgroups are one registry on one RefCounted subsystem. There are several
## more, and `pack()` treats them all the same way, so each is asked the same
## question: build one, save the scene, open it, is it still there?
func _every_other_registry() -> void:
	note("-- every registry that lives on a subsystem rather than a node --")
	var root: Node3D = await fresh_root("Registries")
	root.auto_spawn_player = false

	# A generator: the structure library's editable output.
	var gen = root.create_generator("stairs", {}, Transform3D(Basis(), Vector3(0, 0, -8)))
	await frame()
	# An array: a source brush plus a duplicator record holding its copies.
	var src = box(root, Vector3(1, 1, 1), Vector3.ZERO)
	await frame()
	root.create_duplicate_array(PackedStringArray([str(src.brush_id)]), 3, Vector3(2, 0, 0))
	await frame()
	# A hollow: six walls plus the record that lets the thickness be changed later.
	var shell = box(root, Vector3(4, 3, 4), Vector3(0, 1.5, 8))
	await frame()
	root.hollow_brush_by_id(shell.brush_id, 0.25)
	await frame()
	# A paint layer, and a surface paint layer on a face.
	root.add_paint_layer()
	root.rename_paint_layer(0, "ground")
	root.add_surface_paint_layer(str(src.brush_id), 0)
	await frame()

	var before := _registries(root)
	note("before the save", before)
	if int(before["generators"]) == 0:
		note("no generator was built, so that column is not a result", gen)

	var path := "user://vibe_scene_reopen_registries.tscn"
	var packed := _pack(root, path)
	if packed == null:
		return
	root.get_parent().remove_child(root)
	root.queue_free()
	await frame()
	var reopened: Node3D = packed.instantiate()
	_tree.get_root().add_child(reopened)
	await frame()
	await frame()
	var after := _registries(reopened)
	note("after the reopen", after)
	note("brushes before %s, after %s" % [before["brushes"], after["brushes"]])

	for key in before.keys():
		if key == "brushes":
			continue
		if int(before[key]) > 0 and int(after[key]) == 0:
			flag(
				"saving the scene loses the %s registry" % key,
				(
					"%s before the save, %s after, while the brushes it describes are "
					+ "still there (%s of them). The record lives on a RefCounted "
					+ "subsystem and `PackedScene.pack()` writes nodes"
				) % [before[key], after[key], after["brushes"]]
			)
		elif int(before[key]) != int(after[key]):
			flag(
				"the %s registry does not come back the same size" % key,
				"%s -> %s" % [before[key], after[key]]
			)


func _registries(root: Node3D) -> Dictionary:
	var generators := 0
	var duplicators := 0
	var hollows := 0
	var surface_layers := 0
	if root.generator_system:
		generators = root.generator_count()
	for child in root.draft_brushes_node.get_children():
		if not root.is_brush_node(child):
			continue
		var bid := str(child.get("brush_id"))
		if root.duplicator_for_selection([bid]) != null:
			duplicators += 1
		if root.hollow_for_selection([bid]) != null:
			hollows += 1
		var layers = child.get("faces")
		if layers is Array:
			for face in layers:
				if face and face.paint_layers is Array:
					surface_layers += (face.paint_layers as Array).size()
	return {
		"generators": generators,
		"brushes_in_an_array": duplicators,
		"brushes_in_a_hollow": hollows,
		"paint_layers": root.get_paint_layer_names().size(),
		"surface_paint_layers": surface_layers,
		"prefab_instances": (
			root.prefab_system.get_all_instances().size() if root.prefab_system else 0
		),
		"brushes": root.get_live_brush_count(),
	}


## Two scenes made from the same PackedScene, which is what an instanced level
## or a second tab on the same file is.
## The registry lives on the subsystem and the membership lives on the node, so
## a reopened scene has members of a visgroup that is not in the list. If the
## visgroup was hidden when the scene was saved, its brushes come back hidden
## with nothing in the dock to unhide them.
func _a_hidden_visgroup_across_a_save() -> void:
	note("-- hide a visgroup, save the scene, open it again --")
	var root: Node3D = await fresh_root("Hidden")
	root.auto_spawn_player = false
	var keep = box(root, Vector3(2, 2, 2), Vector3.ZERO)
	await frame()
	var hide_me = box(root, Vector3(2, 2, 2), Vector3(4, 0, 0))
	await frame()
	root.create_visgroup("detail")
	root.add_selection_to_visgroup("detail", [hide_me])
	root.set_visgroup_visible("detail", false)
	await frame()
	note("before the save: visgroups %s" % str(root.get_visgroup_names()))
	note("before the save: the hidden brush is visible", hide_me.visible)
	note("the membership meta on the node", hide_me.get_meta("visgroups", null))

	var path := "user://vibe_scene_reopen_hidden.tscn"
	var packed := _pack(root, path)
	if packed == null:
		return
	root.get_parent().remove_child(root)
	root.queue_free()
	await frame()
	var reopened: Node3D = packed.instantiate()
	_tree.get_root().add_child(reopened)
	await frame()
	await frame()

	var hidden_now := 0
	var memberships: Array = []
	for child in reopened.draft_brushes_node.get_children():
		if not reopened.is_brush_node(child):
			continue
		if not (child as Node3D).visible:
			hidden_now += 1
		memberships.append(child.get_meta("visgroups", null))
	note("after the reopen: visgroups in the registry", reopened.get_visgroup_names())
	note("after the reopen: membership still on the nodes", memberships)
	note("after the reopen: brushes that are invisible", hidden_now)
	if reopened.get_visgroup_names().size() == 0 and hidden_now > 0:
		flag(
			"a hidden visgroup comes back with its brushes still hidden and no way to show them",
			(
				"the membership is node metadata and survives the .tscn; the registry is "
				+ "a plain `var visgroups` on HFVisgroupSystem and does not, so the "
				+ "reopened level has %s invisible brush(es) that still claim to be in "
				+ "'detail' and a visgroup list with nothing in it. Nothing in the dock "
				+ "can unhide them and Validate says nothing"
			) % hidden_now
		)
	var report: Dictionary = reopened.validate_level()
	note("validate_level on the reopened level", report)
	var _unused = keep


func _open_it_twice() -> void:
	note("-- the same .tscn opened twice at once --")
	var path := "user://vibe_scene_reopen.tscn"
	var packed = load(path)
	if packed == null:
		note("no packed scene from the previous section", path)
		return
	var a: Node3D = packed.instantiate()
	_tree.get_root().add_child(a)
	await frame()
	var b: Node3D = packed.instantiate()
	_tree.get_root().add_child(b)
	await frame()
	await frame()
	note("A brushes %s, B brushes %s" % [a.get_live_brush_count(), b.get_live_brush_count()])
	var a_ids: Array = []
	var b_ids: Array = []
	for child in a.draft_brushes_node.get_children():
		if a.is_brush_node(child):
			a_ids.append(str(child.get("brush_id")))
	for child in b.draft_brushes_node.get_children():
		if b.is_brush_node(child):
			b_ids.append(str(child.get("brush_id")))
	note("A ids", a_ids.slice(0, 4))
	note("B ids", b_ids.slice(0, 4))
	note("the two share every id", a_ids == b_ids)
	note("A autosave path", a.hflevel_autosave_path)
	note("B autosave path", b.hflevel_autosave_path)
	# Both save to the same file, both hold the same ids: whichever writes last
	# wins, and a prefab instance record taken from one resolves inside the other.
	if a_ids == b_ids and str(a.hflevel_autosave_path) == str(b.hflevel_autosave_path):
		note(
			"two copies of one scene are indistinguishable",
			"same ids, same autosave path -- see the second level case in #655"
		)
