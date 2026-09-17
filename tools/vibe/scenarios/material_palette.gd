@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a level costs after pressing "Add Prototype Textures" once.
##
## The button is the first thing a mapper presses -- a fresh level has an empty
## palette and nothing to texture with -- and it adds 150 materials in one go.
## `materials` confirms the remap on removal is correct and `material-browser`
## covers the filters; neither asks what a 150-slot palette costs the level it
## is in, or what it takes to get back out of.
##
## Everything here is measured against the same level with a hand-picked palette
## of three, which is what a real map uses.

const PROTOTYPE_COUNT := 150


func id() -> String:
	return "material-palette"


func summary() -> String:
	return "what the 150-material prototype palette costs a level, and the way back out"


func run() -> void:
	await _what_it_costs()
	await _getting_back_to_three()
	await _what_a_second_press_does()
	await _slots_nothing_uses()


func _build(root: Node3D) -> void:
	# A small room: floor, ceiling, four walls, at the project's scale.
	var solid = box(root, Vector3(8, 3, 8), Vector3(0, 1.5, 0))
	await frame()
	root.hollow_brush_by_id(solid.brush_id, 0.25)
	await frame()


func _save_size(root: Node3D, path: String) -> int:
	root.hflevel_autosave_path = path
	root.save_hflevel(path)
	await HFVibe.settle_save(_tree, root)
	return HFVibe.file_size(path)


func _what_it_costs() -> void:
	note("-- one room, palette of 3, against the same room after the button --")
	var lean: Node3D = await fresh_root("Lean")
	lean.auto_spawn_player = false
	await _build(lean)
	# Three slots, hand-picked, which is what a greybox actually uses.
	var picked: Array = []
	var all_protos = lean.get_material_manager()
	lean.add_prototype_materials()
	var full_palette: Array = lean.get_materials()
	for i in [41, 51, 101]:
		if i < full_palette.size():
			picked.append(full_palette[i])
	lean.set_materials(picked)
	await frame()
	note("lean palette", lean.get_material_names())
	var lean_bytes: int = await _save_size(lean, "user://vibe_palette_lean.hflevel")
	note("lean .hflevel", "%s bytes" % lean_bytes)
	var _unused = all_protos

	var loaded: Node3D = await fresh_root("Loaded")
	loaded.auto_spawn_player = false
	await _build(loaded)
	var started := Time.get_ticks_msec()
	var added = loaded.add_prototype_materials()
	var add_ms := Time.get_ticks_msec() - started
	await frame()
	note("materials added by the button", added)
	note("time the button took", "%s ms" % add_ms)
	note("palette size", loaded.get_materials().size())
	var loaded_bytes: int = await _save_size(loaded, "user://vibe_palette_full.hflevel")
	note("full .hflevel", "%s bytes" % loaded_bytes)
	note("what the palette costs the file", "%s bytes" % (loaded_bytes - lean_bytes))
	if loaded_bytes > lean_bytes * 3:
		flag(
			"the prototype palette is most of a greybox level's file",
			(
				"the same six-brush room is %s bytes with three materials and %s bytes "
				+ "after pressing Add Prototype Textures -- %sx -- and 147 of the 150 "
				+ "slots are unused by any face"
			) % [lean_bytes, loaded_bytes, snappedf(float(loaded_bytes) / float(lean_bytes), 0.1)]
		)

	# And what it costs an undo, which snapshots the palette by value.
	var snap_started := Time.get_ticks_msec()
	var snapshot: Dictionary = loaded.capture_state()
	var snap_ms := Time.get_ticks_msec() - snap_started
	note("capture_state() with 150 materials", "%s ms" % snap_ms)
	note("materials carried in the snapshot", (snapshot.get("materials", []) as Array).size())
	var lean_snap: Dictionary = lean.capture_state()
	note("materials carried in the lean snapshot", (lean_snap.get("materials", []) as Array).size())


## The mapper decides they only want three of them. What does the editor give
## them to do that with?
func _getting_back_to_three() -> void:
	note("-- removing 147 slots one at a time, which is the only way the dock offers --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	await _build(root)
	root.add_prototype_materials()
	await frame()
	# Texture the room out of the middle of the palette, so the removals below
	# have to remap.
	var ids: Array = []
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			ids.append(str(child.get("brush_id")))
	root.assign_material_to_whole_brushes(101, ids)
	await frame()
	note("faces on slot 101", _faces_on(root, 101))

	var dock_source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var bulk := (
		dock_source.find("remove_all_materials") >= 0
		or dock_source.find("clear_materials") >= 0
		or dock_source.find("remove_unused_materials") >= 0
	)
	note("a bulk remove exists in the dock", bulk)

	var started := Time.get_ticks_msec()
	var removals := 0
	# Remove everything above and below the one the room uses, the way the
	# dock's minus button does it: one index at a time, each with a full remap.
	while root.get_materials().size() > 1:
		var target := 0 if root.get_materials().size() > 1 else -1
		if target == _slot_of_first_face(root):
			target = 1
		root.remove_material_from_palette(target)
		removals += 1
		if removals > 200:
			break
	var ms := Time.get_ticks_msec() - started
	await frame()
	note("removals to get from 150 to 1", removals)
	note("time taken", "%s ms" % ms)
	note("palette now", root.get_material_names())
	note("faces still pointing somewhere real", _faces_with_material(root))
	if not bulk:
		flag(
			"there is no way to undo Add Prototype Textures except 149 presses",
			(
				"`remove_material_from_palette()` takes one index and walks every brush "
				+ "in the level remapping face indices each time; getting back to a "
				+ "hand-picked palette is %s of those, %s ms here on a six-brush room "
				+ "and quadratic in the level's size. The dock has no Remove Unused, no "
				+ "multi-select on the material list and no Clear Palette"
			) % [removals, ms]
		)


func _what_a_second_press_does() -> void:
	note("-- pressing the button twice --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var first = root.add_prototype_materials()
	var second = root.add_prototype_materials()
	note("first press added", first)
	note("second press added", second)
	note("palette size", root.get_materials().size())
	if root.get_materials().size() != PROTOTYPE_COUNT:
		flag(
			"pressing Add Prototype Textures twice does not leave 150 materials",
			"palette holds %s" % root.get_materials().size()
		)


## What the level knows about which slots are worth keeping.
func _slots_nothing_uses() -> void:
	note("-- what the level can already tell you about unused slots --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	await _build(root)
	root.add_prototype_materials()
	await frame()
	var ids: Array = []
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			ids.append(str(child.get("brush_id")))
	root.assign_material_to_whole_brushes(51, ids)
	await frame()
	var used := {}
	for child in root.draft_brushes_node.get_children():
		if not root.is_brush_node(child):
			continue
		for face in child.get("faces"):
			if face and int(face.material_idx) >= 0:
				used[int(face.material_idx)] = true
	note("slots any face uses", used.keys())
	note("slots in the palette", root.get_materials().size())
	note("slots nothing uses", root.get_materials().size() - used.keys().size())
	var mm = root.get_material_manager()
	note("MaterialManager methods", _methods(mm))
	var has_usage: bool = mm.has_method("get_usage_counts") or mm.has_method("get_material_usage")
	note("the manager can already count usage", has_usage)
	var report: Dictionary = root.validate_level()
	note("validate_level on a level with 149 dead slots", report)


func _faces_on(root: Node3D, slot: int) -> int:
	var n := 0
	for child in root.draft_brushes_node.get_children():
		if not root.is_brush_node(child):
			continue
		for face in child.get("faces"):
			if face and int(face.material_idx) == slot:
				n += 1
	return n


func _faces_with_material(root: Node3D) -> int:
	var n := 0
	for child in root.draft_brushes_node.get_children():
		if not root.is_brush_node(child):
			continue
		for face in child.get("faces"):
			if face and int(face.material_idx) >= 0:
				n += 1
	return n


func _slot_of_first_face(root: Node3D) -> int:
	for child in root.draft_brushes_node.get_children():
		if not root.is_brush_node(child):
			continue
		for face in child.get("faces"):
			if face and int(face.material_idx) >= 0:
				return int(face.material_idx)
	return -1


func _methods(obj: Object) -> Array:
	var out: Array = []
	for m in obj.get_method_list():
		var n := str(m.get("name", ""))
		if not n.begins_with("_"):
			out.append(n)
	return out
