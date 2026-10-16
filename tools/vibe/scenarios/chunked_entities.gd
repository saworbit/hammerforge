@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether a chunked bake builds the same doors, triggers and detail as an
## unchunked one.
##
## `bake-chunking` asks whether a level ever reaches the chunked bake, and
## `streamed-world-bake` whether a chunked bake covers the world. Neither looks
## at brush entities, which the chunk collector skips as non-structural
## (`collect_chunk_brushes()`) and something else has to add back. This bakes
## one small level twice, chunk size 0 and chunk size 4, with and without a
## painted face (which picks the face path over the CSG path), and compares
## what the container holds by class and by name.

const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")


func id() -> String:
	return "chunked-entities"


func summary() -> String:
	return "whether a chunked bake builds the doors, triggers and detail an unchunked bake does"


func run() -> void:
	for painted in [false, true]:
		var plain := await _bake(0.0, painted)
		var chunked := await _bake(4.0, painted)
		var path := "face path" if painted else "CSG path"
		note("%s, unchunked" % path, plain)
		note("%s, chunk size 4" % path, chunked)
		if not bool(chunked["is chunked"]):
			note("%s: chunk size 4 did not chunk this level, so the comparison says nothing" % path)
		for key in plain:
			if key == "is chunked":
				continue
			if HFVibe.canonical(plain[key]) != HFVibe.canonical(chunked.get(key)):
				flag(
					"a chunked bake (%s) changes %s" % [path, key],
					"unchunked %s, chunked %s" % [plain[key], chunked.get(key)]
				)


func _bake(chunk: float, painted: bool) -> Dictionary:
	var root: Node3D = await fresh_root()
	var floor_brush = box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	box(root, Vector3(12, 3, 0.3), Vector3(0, 1.5, -6))
	box(root, Vector3(12, 3, 0.3), Vector3(0, 1.5, 6))
	var door = box(root, Vector3(1.2, 2.2, 0.2), Vector3(-3, 1.1, 0))
	root.tie_brushes_to_entity([str(door.get_meta("brush_id", ""))], "func_door", "gate")
	var trig = box(root, Vector3(2, 2, 2), Vector3(3, 1, 3))
	root.tie_brushes_to_entity([str(trig.get_meta("brush_id", ""))], "trigger_once", "zone")
	root.add_entity_output(trig, "OnTrigger", "gate", "Open")
	for i in 3:
		var crate = box(root, Vector3(0.8, 0.8, 0.8), Vector3(4, 0.4, -3 + i * 1.5))
		root.tie_brushes_to_entity([str(crate.get_meta("brush_id", ""))], "func_detail")
	var wall = box(root, Vector3(1, 2, 1), Vector3(-4, 1, 4))
	root.tie_brushes_to_entity([str(wall.get_meta("brush_id", ""))], "func_wall", "barrier")
	if painted:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.3, 0.2)
		root.apply_material_to_brush_by_id(str(floor_brush.get_meta("brush_id", "")), mat)
	root.bake_chunk_size = chunk
	await root.bake(false, false)
	await frame()
	var out := _contents(root)
	await drop_root(root)
	return out


func _contents(root: Node3D) -> Dictionary:
	var container := root.get_node_or_null("BakedGeometry")
	var by_class := {}
	var names := []
	var areas := 0
	var bodies := 0
	var chunks := 0
	if container:
		for n in container.find_children("*", "", true, false):
			if str(n.name).begins_with("BakedChunk_"):
				chunks += 1
			var cls := HFBrushEntity.entity_class(n)
			if cls != "" and n is MeshInstance3D:
				by_class[cls] = int(by_class.get(cls, 0)) + 1
			if n.has_meta("entity_name") and n is Area3D:
				areas += 1
			if n is StaticBody3D and HFBrushEntity.entity_class(n) != "":
				bodies += 1
			var en := str(n.get_meta("entity_name", ""))
			if en != "" and not names.has(en):
				names.append(en)
	names.sort()
	return {
		"entity meshes by class": by_class,
		"named entities": names,
		"trigger areas": areas,
		"entity bodies": bodies,
		"is chunked": chunks > 0,
	}
