@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The material library: `save_library()` and `load_library()` on
## `MaterialManager`, against what a mapper can actually reach.
##
## The User Guide has a "Material Library" section that describes **Save** and
## **Load** as two things the palette does, and `docs/features.md` lists
## "Material library persistence" as a feature. Both of those describe an API
## that exists. What is measured here is whether it can be reached from the
## editor, and what a round trip through it keeps.

const PrototypeTextures = preload("res://addons/hammerforge/hf_prototype_textures.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")


func id() -> String:
	return "material-library"


func summary() -> String:
	return "whether the documented Save/Load material library can be reached, and what it keeps"


func run() -> void:
	await _is_there_a_way_in()
	await _round_trip_runtime_materials()
	await _round_trip_prototype_materials()


## Every control the Materials section builds, against the two the guide names.
func _is_there_a_way_in() -> void:
	var root: Node3D = await fresh_root("MaterialLibraryDock")
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	await frame()

	var buttons: Array = []
	_collect_buttons(dock, buttons)
	var labels: Array = []
	for b in buttons:
		var text := str(b.text).strip_edges()
		if text != "":
			labels.append(text)
	var library_controls: Array = []
	for text in labels:
		var lowered: String = str(text).to_lower()
		if "librar" in lowered:
			library_controls.append(text)
	note("buttons on the dock", labels.size())
	note("buttons mentioning a library", library_controls)

	# The palette API the guide documents.
	var mm = root.material_manager
	note("MaterialManager has save_library", mm.has_method("save_library"))
	note("MaterialManager has load_library", mm.has_method("load_library"))

	if library_controls.is_empty() and mm.has_method("save_library"):
		known(
			498,
			"the documented Save/Load material library has no control anywhere in the dock",
			(
				"docs/HammerForge_UserGuide.md has a 'Material Library' section describing"
				+ " Save and Load, and docs/features.md lists 'Material library persistence"
				+ " -- save/load palettes as JSON'. MaterialManager.save_library() and"
				+ " load_library() are called by nothing in addons/hammerforge; the Materials"
				+ " section builds Add, Remove, Refresh Prototypes and Assign and nothing else"
			)
		)
	dock.queue_free()


func _collect_buttons(node: Node, out: Array) -> void:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_collect_buttons(child, out)


## A palette of materials made in memory, saved and loaded back.
##
## `save_library()` writes each slot's `resource_path` and nothing else, so a
## material that was never written to disk is saved as an empty string.
func _round_trip_runtime_materials() -> void:
	var root: Node3D = await fresh_root("MaterialLibraryRuntime")
	var mats: Array = []
	for i in range(4):
		var m := StandardMaterial3D.new()
		m.resource_name = "runtime_%d" % i
		m.albedo_color = Color(float(i) / 4.0, 0.5, 0.5)
		mats.append(m)
	root.set_materials(mats)
	var mm = root.material_manager
	note("palette before saving", mm.materials.size())

	var path := "user://vibe_material_library_runtime.json"
	var rc: int = mm.save_library(path)
	note("save_library returned", rc)
	note("the file it wrote", FileAccess.get_file_as_string(path))

	var loaded: bool = mm.load_library(path)
	note("load_library returned", loaded)
	note("palette after loading", mm.materials.size())
	note("empty slots after loading", mm.get_missing_count())
	if loaded and mm.get_missing_count() == mm.materials.size() and mm.materials.size() > 0:
		known(
			515,
			(
				"saving a palette of materials that were made in the editor produces a library"
				+ " that restores nothing"
			),
			(
				"save_library() records each slot's resource_path, and a material added"
				+ (
					" through the Materials tab's Add button has none, so all %d slots are"
					% mm.materials.size()
				)
				+ " written as empty strings and come back null. It returns OK and says nothing"
			)
		)


## The same round trip over the 150 shipped prototypes, which do have paths.
func _round_trip_prototype_materials() -> void:
	var root: Node3D = await fresh_root("MaterialLibraryProto")
	var mm = root.material_manager
	var added: int = PrototypeTextures.load_all_into(mm)
	note("prototype materials loaded into the palette", added)
	if added == 0:
		note("no prototype .tres files on this checkout", "skipping the round trip")
		return
	var path := "user://vibe_material_library_proto.json"
	mm.save_library(path)
	var before: int = mm.materials.size()
	var loaded: bool = mm.load_library(path)
	note("load_library returned", loaded)
	note("palette size", "%d -> %d" % [before, mm.materials.size()])
	note("empty slots after loading", mm.get_missing_count())
	if mm.get_missing_count() > 0:
		flag(
			"a library saved from the shipped prototype palette does not load back whole",
			"%d of %d slots are empty" % [mm.get_missing_count(), mm.materials.size()]
		)
