@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## A door made of brushes, the way this lineage makes one.
##
## `entities` covers point entities -- a light, a spawn -- and their naming,
## duplication and wiring. A **brush** entity is the other half and a different
## thing: geometry tied to a class, so a set of brushes becomes a door, a
## platform, a trigger volume. `tie_brushes_to_entity()` is the operation, the
## Objects tab is the surface, and the `.map` exporter writes them as their own
## entity blocks.
##
## The workflow here is the one from any Quake-family tutorial: draw the door,
## tie it to a class, name it, wire a trigger to it, save, reload, export, and
## export the playtest scene. Each step asks what the door still is.

const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")


func id() -> String:
	return "brush-entities"


func summary() -> String:
	return "brushes tied to an entity class: naming, wiring, saving and what the exports make of them"


func run() -> void:
	await _tie_and_name()
	await _through_a_save()
	await _through_the_exports()
	await _what_the_level_counts()


func _door(root: Node3D) -> Array:
	var leaves: Array = []
	for i in 2:
		leaves.append(box(root, Vector3(0.6, 2, 0.15), Vector3(-0.3 + i * 0.6, 1, 0)))
		await frame()
	return leaves


func _tie_and_name() -> void:
	note("-- two brushes tied to door_basic --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var leaves: Array = await _door(root)
	var ids: Array = leaves.map(func(b): return str(b.brush_id))
	root.tie_brushes_to_entity(ids, "door_basic")
	await frame()
	for b in leaves:
		note("leaf class", b.get_meta("brush_entity_class", ""))
	var tied := 0
	for b in leaves:
		if str(b.get_meta("brush_entity_class", "")) == "door_basic":
			tied += 1
	if tied != 2:
		flag("tie_brushes_to_entity left a brush untied", "%s of 2" % tied)

	# A brush entity needs a name for anything to be able to target it. Where
	# does that name live, and what surface sets it?
	note("entity_count (point entities)", root.get_entity_count())
	note("names the level answers to", root.find_entities_by_name("gate").size())
	var name_meta := []
	for b in leaves:
		name_meta.append(b.get_meta("entity_name", null))
	note("the name meta on the leaves", name_meta)

	var dock_source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var entity_handler := FileAccess.get_file_as_string(
		"res://addons/hammerforge/dock_entity_handler.gd"
	)
	# `find_entities_by_name()` and the `.map` exporter both read an `entity_name`
	# meta off a brush, so the mechanism is there. The question is which surface
	# writes it.
	var writers: Array[String] = []
	for path in [
		"res://addons/hammerforge/dock.gd",
		"res://addons/hammerforge/dock_brush_handler.gd",
		"res://addons/hammerforge/dock_entity_handler.gd",
		"res://addons/hammerforge/systems/hf_brush_system.gd",
		"res://addons/hammerforge/systems/hf_entity_system.gd",
	]:
		if FileAccess.get_file_as_string(path).find('set_meta("entity_name"') >= 0:
			writers.append(path.get_file())
	note("files that set an entity_name meta", writers)
	note(
		"the dock's Tie to Entity arguments",
		"a class from brush_entity_class_opt and nothing else (dock_brush_handler.gd:1526)"
	)
	var unused_ref = [dock_source, entity_handler]

	# Can a wire reach it? `add_entity_output` wants a source Node.
	var lamp := DraftEntity.new()
	lamp.entity_type = "light_point"
	lamp.entity_class = "light_point"
	lamp.name = "switch"
	root.add_entity(lamp)
	await frame()
	root.add_entity_output(lamp, "TurnOn", "gate", "Open", "", 0.0, false)
	await frame()
	var wires: Array = root.get_all_entity_connections()
	note("wires in the level", wires.size())
	note("summary for 'gate'", root.get_connection_summary("gate"))
	var dangling: Array = []
	for w in wires:
		if root.find_entities_by_name(str((w as Dictionary).get("target_name", ""))).is_empty():
			dangling.append(str((w as Dictionary).get("target_name", "")))
	note("wire targets the level cannot resolve", dangling)
	if not dangling.is_empty():
		known(
			668,
			"a brush entity cannot be given a name, so nothing can be wired to it",
			(
				(
					"`find_entities_by_name()` checks brush entities for an `entity_name` "
					+ "meta and the `.map` exporter writes one, so the mechanism is complete "
					+ "except for a surface that sets it: the dock's Tie to Entity takes a "
					+ "class from a dropdown and no name, and the only code that ever writes "
					+ "the meta onto a brush is the `.map` *import* path. A wire to %s "
					+ "therefore cannot resolve, and #620's dangling-wire check reports it "
					+ "as broken"
				)
				% str(dangling)
			)
		)


func _through_a_save() -> void:
	note("-- the door through a .hflevel --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var leaves: Array = await _door(root)
	var ids: Array = leaves.map(func(b): return str(b.brush_id))
	root.tie_brushes_to_entity(ids, "door_basic")
	await frame()
	var before := HFVibe.describe_brushes(root)
	var path := "user://vibe_brush_entities.hflevel"
	root.hflevel_autosave_path = path
	root.save_hflevel(path)
	if not await HFVibe.settle_save(_tree, root):
		flag("the save never finished")
		return
	root.clear_brushes()
	await frame()
	root.load_hflevel(path)
	await frame()
	var after := HFVibe.describe_brushes(root)
	note("brushes before %s, after %s" % [before.size(), after.size()])
	var classes: Array = []
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			classes.append(str(child.get_meta("brush_entity_class", "")))
	note("classes after the load", classes)
	if classes.count("door_basic") != 2:
		flag(
			"a .hflevel round trip does not bring the brush entity class back",
			"expected two door_basic, got %s" % str(classes)
		)
	if HFVibe.canonical(before) != HFVibe.canonical(after):
		flag("the tied brushes changed across a .hflevel round trip")


func _through_the_exports() -> void:
	note("-- the door through .map and through the playtest scene --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	box(root, Vector3(8, 0.25, 8), Vector3(0, -0.125, 0))
	await frame()
	var leaves: Array = await _door(root)
	var ids: Array = leaves.map(func(b): return str(b.brush_id))
	root.tie_brushes_to_entity(ids, "door_basic")
	await frame()

	var map_path := "user://vibe_brush_entities.map"
	root.export_map(map_path, "valve220")
	await frame()
	var text := FileAccess.get_file_as_string(map_path)
	note(".map bytes", text.length())
	note(".map names door_basic", text.find("door_basic") >= 0)
	var blocks := text.count('"classname"')
	note("classname lines in the .map", blocks)
	if text.find("door_basic") < 0:
		flag("a brush entity does not reach the .map export", "%s bytes written" % text.length())
	# One worldspawn plus one door_basic holding both leaves.
	var door_blocks := text.count('"classname" "door_basic"')
	note("door_basic blocks in the .map", door_blocks)
	if door_blocks > 1:
		known(
			668,
			"two brushes tied to one entity are exported as two entities",
			(
				(
					"the .map holds %s separate `door_basic` blocks, one brush each. "
					+ "`export_map()` appends an `entity_brush_blocks` entry per node "
					+ "(map_io.gd:222) and then writes one block per entry, so a door with "
					+ "two leaves compiles as two doors that move independently and are "
					+ "targeted separately. Grouping the blocks by class and name is what "
					+ "makes it one entity"
				)
				% door_blocks
			)
		)

	var scene_path := "user://vibe_brush_entities_playtest.tscn"
	var ok = root.export_playtest_scene(scene_path)
	note("export_playtest_scene", ok)
	if not ok:
		flag("a level with a brush entity will not export a playtest scene")
		return
	var packed = load(scene_path)
	var inst = packed.instantiate()
	_tree.get_root().add_child(inst)
	await frame()
	var counts := {}
	var named: Array[String] = []
	_tally(inst, counts, named)
	note("playtest scene node classes", counts)
	note("nodes whose name mentions the door", named)
	if named.is_empty():
		known(
			668,
			"the door is not a thing in the playtest scene",
			(
				"the two leaves are tied to door_basic and the exported scene has no "
				+ "node that groups them or names the class, so nothing at run time can "
				+ "open the door: `_playtest_node_for_entity()` runs over "
				+ "`entities_node` and a brush entity is not in it. The .map export does "
				+ "write the block, so the two exporters disagree about what a brush "
				+ "entity is"
			)
		)
	inst.get_parent().remove_child(inst)
	inst.queue_free()


## The counts a mapper reads off the status board, against what is in the level.
func _what_the_level_counts() -> void:
	note("-- what the level's own counters say about a brush entity --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var leaves: Array = await _door(root)
	var ids: Array = leaves.map(func(b): return str(b.brush_id))
	root.tie_brushes_to_entity(ids, "door_basic")
	await frame()
	note("get_live_brush_count()", root.get_live_brush_count())
	note("get_entity_count()", root.get_entity_count())
	note("get_level_health()", root.get_level_health())
	note("validate_level()", root.validate_level())
	note("get_all_entity_connections()", root.get_all_entity_connections().size())
	root.untie_brushes_from_entity(ids)
	await frame()
	var still: Array = []
	for b in leaves:
		still.append(str(b.get_meta("brush_entity_class", "")))
	note("classes after untie", still)
	if still.count("") != 2:
		flag("untie left a class behind", str(still))


func _tally(node: Node, counts: Dictionary, named: Array[String]) -> void:
	for child in node.get_children():
		var cls := child.get_class()
		counts[cls] = int(counts.get(cls, 0)) + 1
		var n := str(child.name).to_lower()
		if n.find("door") >= 0 or n.find("gate") >= 0:
			named.append(str(child.name))
		_tally(child, counts, named)
