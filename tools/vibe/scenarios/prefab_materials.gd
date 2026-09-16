@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a prefab remembers about how it was textured.
##
## A prefab is the unit of reuse: build a doorframe once, drop it in every level.
## Faces carry a `material_idx` into the level's palette, and a `.hfprefab`
## records the infos. The question is what those indices mean once the prefab is
## somewhere else.


func id() -> String:
	return "prefab-materials"


func summary() -> String:
	return "whether a prefab carries the materials it was built with, or just slot numbers"


func _mat(name: String, colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = colour
	return m


func _shipped(pattern: String, colour: String) -> Material:
	var p := (
		"res://addons/hammerforge/textures/prototypes/materials/proto_%s_%s.tres"
		% [pattern, colour]
	)
	return load(p) if ResourceLoader.exists(p) else null


func run() -> void:
	await _a_prefab_in_another_level()
	await _the_file_itself()


func _face_mats(root: Node3D) -> Array:
	var out: Array = []
	for b in root.draft_brushes_node.get_children():
		var row: Array = []
		for f in b.faces:
			row.append(f.material_idx)
		out.append(row)
	return out


func _palette_names(root: Node3D) -> Array:
	var out: Array = []
	for m in root.get_materials():
		out.append(
			(
				"null"
				if m == null
				else str(m.resource_name if m.resource_name != "" else m.resource_path.get_file())
			)
		)
	return out


## Build and save a prefab in a level with one palette, place it in a level with
## a different one.
func _a_prefab_in_another_level() -> void:
	var source: Node3D = await fresh_root("SourceLevel")
	source.set_materials(
		[
			_shipped("brick", "red"),
			_shipped("checker", "blue"),
			_shipped("stripes_diagonal", "green")
		]
	)
	note("source palette", _palette_names(source))
	var b = box(source, Vector3(128, 128, 32))
	await frame()
	for i in b.faces.size():
		b.faces[i].material_idx = 1  # the blue checker, slot 1
	note("source face slots", _face_mats(source))

	var path := "user://vibe_prefab_mats.hfprefab"
	var prefab = HFPrefab.capture_from_selection(source.brush_system, source.entity_system, [b], [])
	prefab.prefab_name = "doorframe"
	note("save_to_file returned", prefab.save_to_file(path))
	note("prefab file bytes", HFVibe.file_size(path))
	var text := FileAccess.get_file_as_string(path)
	note("prefab file mentions a material path", text.find("proto_") >= 0)
	note("prefab file mentions 'material'", text.find("material") >= 0)

	# A different level, whose palette holds different materials in those slots.
	var other: Node3D = await fresh_root("OtherLevel")
	other.set_materials([_shipped("dots", "yellow"), _shipped("hex", "purple")])
	note("other palette", _palette_names(other))
	var loaded = HFPrefab.load_from_file(path)
	if loaded == null:
		flag("a prefab just written will not load back")
		return
	var placed: Dictionary = loaded.instantiate(
		other.brush_system, other.entity_system, other, Vector3.ZERO
	)
	await frame()
	note("instantiate placed", placed.get("brush_ids", []).size())
	note("brushes in the other level", other.draft_brushes_node.get_child_count())
	note("face slots after placing", _face_mats(other))
	var slots := _face_mats(other)
	var resolved: Array = []
	for row in slots:
		for idx in row:
			var i := int(idx)
			var mats: Array = other.get_materials()
			resolved.append(
				(
					"slot %d -> %s"
					% [
						i,
						(
							"out of range"
							if i < 0 or i >= mats.size()
							else (
								"null" if mats[i] == null else str(mats[i].resource_path.get_file())
							)
						)
					]
				)
			)
			break
		break
	note("what slot 1 means in the other level", resolved)
	if text.find("proto_") < 0:
		known(
			621,
			"a .hfprefab records material slot numbers and no materials",
			(
				"the doorframe was built entirely out of slot 1, which was "
				+ "proto_checker_blue in the level it came from. The file carries no "
				+ "material path at all, so placing it in a level whose slot 1 is "
				+ "proto_hex_purple textures it purple, and placing it in a level with a "
				+ "two-slot palette and a face pointing at slot 4 leaves that face "
				+ "untextured. HFPrefab.to_dict() writes brush_infos and entity_infos and "
				+ "nothing else"
			)
		)


## What a prefab file is, as text.
func _the_file_itself() -> void:
	var root: Node3D = await fresh_root()
	root.set_materials([_shipped("brick", "red")])
	var b = box(root, Vector3(64, 64, 64))
	await frame()
	for f in b.faces:
		f.material_idx = 0
		f.uv_scale = Vector2(2.0, 0.5)
		f.uv_offset = Vector2(8, 16)
	var path := "user://vibe_prefab_plain.hfprefab"
	var prefab2 = HFPrefab.capture_from_selection(root.brush_system, root.entity_system, [b], [])
	prefab2.prefab_name = "plain"
	prefab2.save_to_file(path)
	var text := FileAccess.get_file_as_string(path)
	note("prefab file size", text.length())
	note(
		"keys at the top level",
		JSON.parse_string(text).keys() if JSON.parse_string(text) is Dictionary else "unparsed"
	)
	note("carries uv_scale", text.find("uv_scale") >= 0)
	note("carries material_idx", text.find("material_idx") >= 0)
	note(
		"what that means",
		"the UV settings travel with the prefab and the material they were tuned " + "for does not"
	)
