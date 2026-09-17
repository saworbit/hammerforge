@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Putting a model in a level, which is half of building one.
##
## Brushes make the shell. Everything else in a shipped game -- crates, lamps,
## foliage, the door leaf that is a model and not a box -- arrives as a
## `PackedScene` somebody else authored. The shipped entity library has a class
## for exactly that: `prop_static`, "A model placed in the level. Set Scene to
## the mesh or scene to show."
##
## This scenario does what that sentence says and then looks for the model.


func id() -> String:
	return "props-and-models"


func summary() -> String:
	return "what happens to a prop_static's Scene property, in the editor, the bake and the export"


const PROP_PATH := "res://.vibe_prop_crate.tscn"

var _written: Array[String] = []


func run() -> void:
	_make_a_prop_scene()
	await _place_one_and_look_for_it()
	await _through_the_bake_and_the_playtest()
	await _what_else_can_carry_a_model()
	_cleanup()


## A crate, saved to disk, exactly as an artist would hand one over.
func _make_a_prop_scene() -> void:
	var crate := Node3D.new()
	crate.name = "Crate"
	var mi := MeshInstance3D.new()
	mi.name = "CrateMesh"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.8, 0.8)
	mi.mesh = bm
	crate.add_child(mi)
	mi.owner = crate
	var packed := PackedScene.new()
	var err := packed.pack(crate)
	if err != OK:
		note("could not pack the test prop", err)
		return
	ResourceSaver.save(packed, PROP_PATH)
	_written.append(PROP_PATH)
	crate.free()
	note("a crate scene written to", PROP_PATH)
	note("it loads back", ResourceLoader.exists(PROP_PATH))


func _find(node: Node, pred: Callable, out: Array) -> Array:
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		_find(c, pred, out)
	return out


func _mesh_nodes(root: Node) -> Array:
	return (
		_find(root, func(n: Node) -> bool: return n is MeshInstance3D, [])
		. map(func(n: Node) -> String: return n.name)
	)


func _place_one_and_look_for_it() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	var prop = (
		root
		. _restore_entity_from_info(
			{
				"entity_type": "prop_static",
				"entity_class": "prop_static",
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)),
				"properties": {"scene": PROP_PATH},
				"name": "crate_1",
				"entity_name": "crate_1",
			}
		)
	)
	if prop == null:
		flag("prop_static could not be placed at all")
		return
	await frame()
	note("the prop node", "%s (%s)" % [prop.name, prop.get_class()])
	note("its stored properties", prop.get_meta("entity_properties", {}))
	note(
		"children it has",
		prop.get_children().map(func(c: Node) -> String: return "%s (%s)" % [c.name, c.get_class()])
	)
	var meshes := _mesh_nodes(prop)
	note("MeshInstance3D nodes under the prop", meshes)
	# The question the description answers "yes" to.
	var loaded_crate := _find(prop, func(n: Node) -> bool: return str(n.name).contains("Crate"), [])
	if loaded_crate.is_empty():
		flag(
			"setting a prop_static's Scene property loads nothing",
			(
				"prop_static's own description is 'A model placed in the level. Set Scene to "
				+ "the mesh or scene to show.' The property is stored and nothing in the addon "
				+ "ever calls load() or instantiate() on it, so the mapper places a prop, types "
				+ "a path, and the level stays empty with no error anywhere. Nothing that "
				+ "places a model in a level works."
			)
		)


func _through_the_bake_and_the_playtest() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	(
		root
		. _restore_entity_from_info(
			{
				"entity_type": "prop_static",
				"entity_class": "prop_static",
				"transform": Transform3D(Basis.IDENTITY, Vector3(2, 0.4, 0)),
				"properties": {"scene": PROP_PATH},
				"name": "crate_1",
				"entity_name": "crate_1",
			}
		)
	)
	await frame()
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	note("meshes in the baked container", _mesh_nodes(container) if container else "no container")

	var scene_path := "user://vibe_props_playtest.tscn"
	var ok = root.export_playtest_scene(scene_path)
	note("export_playtest_scene", ok)
	var packed: PackedScene = load(scene_path) if ResourceLoader.exists(scene_path) else null
	if packed == null:
		note("no playtest scene on disk to read back", true)
		return
	var inst := packed.instantiate()
	note(
		"the playtest scene's tree",
		(
			_find(inst, func(_n: Node) -> bool: return true, [])
			. map(func(n: Node) -> String: return "%s (%s)" % [n.name, n.get_class()])
		)
	)
	var crates := _find(inst, func(n: Node) -> bool: return str(n.name).contains("Crate"), [])
	note("crate meshes in the exported playtest", crates.size())
	inst.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scene_path))


## Everything else in the plugin that could carry a model, checked so the report
## says what a mapper's options actually are rather than only what does not work.
func _what_else_can_carry_a_model() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var with_scene: Array = []
	var f := FileAccess.open("res://addons/hammerforge/entities.json", FileAccess.READ)
	if f:
		var defs: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if defs is Dictionary:
			for key in defs:
				for prop in defs[key].get("properties", []):
					var pname := str(prop.get("name", ""))
					if pname in ["scene", "model", "mesh", "path"]:
						with_scene.append("%s.%s" % [key, pname])
	note("entity properties that name an asset path", with_scene)
	await _what_the_scatter_picker_accepts()


func _cleanup() -> void:
	for p in _written:
		var abs := ProjectSettings.globalize_path(p)
		DirAccess.remove_absolute(abs)
		var uid := abs + ".uid"
		if FileAccess.file_exists(p + ".uid"):
			DirAccess.remove_absolute(uid)
	note("cleaned up", _written)


## The scatter brush is the other way a model reaches a level. Its file dialog
## and the code behind it disagree about what a model is.
func _what_the_scatter_picker_accepts() -> void:
	var src := FileAccess.open("res://addons/hammerforge/dock_paint_handler.gd", FileAccess.READ)
	var text := src.get_as_text() if src else ""
	if src:
		src.close()
	var filter_line := ""
	var at := text.find("add_filter(")
	if at >= 0:
		var close := text.find(")", at)
		filter_line = text.substr(at, max(close - at + 1, 0))
	note("what the scatter Pick Mesh dialog offers", filter_line)
	note(
		"what build_scatter_settings keeps",
		"`if res is Mesh: s.mesh = res` (dock_paint_handler.gd)"
	)

	# What each offered extension actually loads as. A .glb or .gltf is imported
	# by Godot as a PackedScene, never as a Mesh.
	var scene_res: Resource = load(PROP_PATH) if ResourceLoader.exists(PROP_PATH) else null
	note("a scene resource `is Mesh`", scene_res is Mesh)
	note("a scene resource `is PackedScene`", scene_res is PackedScene)
	var mesh_res := BoxMesh.new()
	note("a Mesh resource `is Mesh`", mesh_res is Mesh)
	if filter_line.contains("glb") or filter_line.contains("gltf"):
		flag(
			"the scatter mesh picker offers .glb and .gltf and then discards them",
			(
				"The dialog filter is `*.tres,*.res,*.obj,*.glb,*.gltf`, so a mapper picking "
				+ "the crate an artist handed over picks a .glb. Godot imports .glb and .gltf "
				+ "as PackedScene, and `build_scatter_settings()` keeps the resource only `if "
				+ "res is Mesh`, so the pick is silently dropped: the button's label changes to "
				+ "the filename, `s.mesh` stays null, and scattering places nothing. Either the "
				+ "filter should not offer scene formats, or the loader should pull the first "
				+ "MeshInstance3D out of the instantiated scene."
			)
		)
