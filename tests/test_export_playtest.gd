extends GutTest

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")

var root: Node3D


func before_each():
	root = LevelRootScript.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.grid_snap = 1.0
	add_child(root)


func after_each():
	root.free()
	root = null


func test_bake_wire_io_defaults_on():
	assert_true(root.bake_wire_io, "Test Level / regular bake should wire I/O by default")


func test_runtime_level_root_skips_editor_only_systems():
	var runtime_script := GDScript.new()
	runtime_script.source_code = """
extends "res://addons/hammerforge/level_root.gd"
func _should_initialize_editor_systems() -> bool:
	return false
"""
	assert_eq(runtime_script.reload(), OK)
	var runtime_root = runtime_script.new()
	runtime_root.auto_spawn_player = false
	add_child(runtime_root)
	assert_not_null(runtime_root.brush_system, "runtime baking keeps brush lookup")
	assert_not_null(runtime_root.entity_system, "runtime baking keeps entity lookup")
	assert_not_null(runtime_root.bake_system, "runtime baking stays available")
	assert_not_null(runtime_root.file_system, "runtime reload support stays available")
	for property_name in [
		"grid_system",
		"drag_system",
		"validation_system",
		"snap_system",
		"vertex_system",
		"io_visualizer",
		"prefab_overlay",
	]:
		assert_null(runtime_root.get(property_name), "%s stays unloaded at runtime" % property_name)
	runtime_root.free()


func test_runtime_brush_creation_survives_missing_grid_system():
	# HFBrushSystem stays alive at runtime and calls back into _record_last_brush,
	# which used to dereference the unloaded grid_system.
	var runtime_script := GDScript.new()
	runtime_script.source_code = """
extends "res://addons/hammerforge/level_root.gd"
func _should_initialize_editor_systems() -> bool:
	return false
"""
	assert_eq(runtime_script.reload(), OK)
	var runtime_root = runtime_script.new()
	runtime_root.auto_spawn_player = false
	runtime_root.commit_freeze = false
	add_child(runtime_root)
	assert_null(runtime_root.grid_system, "grid_system stays unloaded at runtime")

	var brush = runtime_root.brush_system.create_brush_from_info(
		{"shape": 0, "size": Vector3.ONE, "center": Vector3.ZERO}
	)
	assert_not_null(brush, "Runtime brush creation should succeed without a grid")

	# The other two grid delegates take the same unguarded shape, so pin them too.
	runtime_root.update_editor_grid(null, Vector2.ZERO)
	runtime_root._refresh_grid_plane()
	runtime_root.free()


func test_editor_only_systems_are_loaded_on_demand():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/level_root.gd")
	for path in [
		"systems/hf_grid_system.gd",
		"systems/hf_drag_system.gd",
		"systems/hf_io_visualizer.gd",
		"systems/hf_vertex_system.gd",
		"systems/hf_carve_preview.gd",
		"ui/hf_prefab_overlay.gd",
	]:
		assert_false(source.contains('preload("%s")' % path), "%s is not preloaded" % path)
		assert_true(source.contains('load("res://addons/hammerforge/%s")' % path))


func test_export_playtest_scene_empty_level():
	var path := "user://test_playtest_export.tscn"
	var success: bool = root.export_playtest_scene(path)
	assert_true(success, "Should succeed even with empty level")
	# Verify file was created
	assert_true(FileAccess.file_exists(path), "Exported file should exist")
	# Cleanup
	DirAccess.remove_absolute(path)


func test_export_playtest_scene_includes_light():
	var path := "user://test_playtest_light.tscn"
	root.export_playtest_scene(path)
	# Load and verify it has a light
	var packed: PackedScene = ResourceLoader.load(path)
	if packed:
		var scene: Node = packed.instantiate()
		var has_light := false
		for child in scene.get_children():
			if child is DirectionalLight3D:
				has_light = true
				break
		assert_true(has_light, "Should have a default light")
		scene.free()
	DirAccess.remove_absolute(path)


func test_export_playtest_scene_includes_environment():
	var path := "user://test_playtest_env.tscn"
	root.export_playtest_scene(path)
	var packed: PackedScene = ResourceLoader.load(path)
	if packed:
		var scene: Node = packed.instantiate()
		var has_env := false
		for child in scene.get_children():
			if child is WorldEnvironment:
				has_env = true
				break
		assert_true(has_env, "Should have a WorldEnvironment")
		scene.free()
	DirAccess.remove_absolute(path)


func test_export_playtest_scene_includes_player():
	var path := "user://test_playtest_player.tscn"
	assert_true(root.export_playtest_scene(path))
	var packed: PackedScene = ResourceLoader.load(path)
	assert_not_null(packed)
	var scene: Node = packed.instantiate()
	add_child_autoqfree(scene)
	var player: Node = scene.get_node_or_null("PlaytestPlayer")
	assert_not_null(player, "Exported scene needs a PlaytestPlayer")
	if player == null:
		return
	assert_true(player is CharacterBody3D)
	assert_not_null(player.get_script(), "PlaytestPlayer needs PlaytestFPS")
	var camera: Node = scene.find_child("MainCamera", true, false)
	assert_not_null(camera, "PlaytestPlayer should create a camera at runtime")


func test_export_playtest_scene_keeps_nested_baked_geometry():
	var baked := Node3D.new()
	baked.name = "BakedGeometry"
	root.add_child(baked)
	root.baked_container = baked
	var chunk := Node3D.new()
	chunk.name = "BakedChunk_0"
	baked.add_child(chunk)
	var mesh := MeshInstance3D.new()
	mesh.name = "NestedMesh"
	mesh.mesh = BoxMesh.new()
	chunk.add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "Collision"
	chunk.add_child(body)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = BoxShape3D.new()
	body.add_child(col)
	var path := "user://test_playtest_nested_geo.tscn"
	assert_true(root.export_playtest_scene(path))
	var packed: PackedScene = ResourceLoader.load(path)
	assert_not_null(packed)
	var scene: Node = packed.instantiate()
	assert_not_null(scene.find_child("NestedMesh", true, false), "Nested mesh must survive pack")
	assert_not_null(scene.find_child("Shape", true, false), "Nested collision must survive pack")
	scene.free()
	DirAccess.remove_absolute(path)


func test_export_playtest_scene_preserves_source_world_transforms():
	root.position = Vector3(100, 0, 0)
	root.rotation_degrees = Vector3(0, 30, 0)
	root.scale = Vector3(1.5, 1.5, 1.5)
	var baked := Node3D.new()
	baked.name = "BakedGeometry"
	baked.position = Vector3(10, 0, 0)
	baked.rotation_degrees = Vector3(0, 15, 0)
	root.add_child(baked)
	root.baked_container = baked
	var chunk := Node3D.new()
	chunk.name = "MovedChunk"
	chunk.position = Vector3(1, 0, 0)
	baked.add_child(chunk)
	var mesh := MeshInstance3D.new()
	mesh.name = "MovedMesh"
	mesh.position = Vector3(2, 0, 0)
	mesh.scale = Vector3(2, 1, 1)
	mesh.mesh = BoxMesh.new()
	chunk.add_child(mesh)
	var entity := Node3D.new()
	entity.name = "MovedEntity"
	entity.position = Vector3(3, 0, 0)
	root.entities_node.position = Vector3(20, 0, 0)
	root.entities_node.add_child(entity)
	var expected_mesh_transform := mesh.global_transform
	var expected_entity_transform := entity.global_transform
	var path := "user://test_playtest_transforms.tscn"
	assert_true(root.export_playtest_scene(path))
	var packed: PackedScene = ResourceLoader.load(path)
	assert_not_null(packed)
	var scene: Node = packed.instantiate()
	add_child_autoqfree(scene)
	var exported_mesh := scene.find_child("MovedMesh", true, false) as Node3D
	var exported_entity := scene.find_child("MovedEntity", true, false) as Node3D
	assert_not_null(exported_mesh)
	assert_not_null(exported_entity)
	if exported_mesh and exported_entity:
		assert_true(exported_mesh.global_transform.is_equal_approx(expected_mesh_transform))
		assert_true(exported_entity.global_transform.is_equal_approx(expected_entity_transform))
	DirAccess.remove_absolute(path)


func test_export_playtest_scene_wires_nested_brush_io():
	var baked := Node3D.new()
	baked.name = "BakedGeometry"
	root.add_child(baked)
	root.baked_container = baked
	var holder := Node3D.new()
	holder.name = "Nonstructural"
	baked.add_child(holder)
	var trigger := Area3D.new()
	trigger.name = "Trigger_0"
	trigger.set_meta(
		"entity_io_outputs",
		[{"output_name": "OnTrigger", "target_name": "door", "input_name": "Open"}]
	)
	holder.add_child(trigger)
	var path := "user://test_playtest_nested_io.tscn"
	assert_true(root.export_playtest_scene(path))
	var packed: PackedScene = ResourceLoader.load(path)
	assert_not_null(packed)
	var scene: Node = packed.instantiate()
	var dispatcher: Node = scene.find_child("HFIODispatcher", true, false)
	assert_not_null(dispatcher, "Nested trigger I/O should attach HFIORuntime")
	scene.free()
	DirAccess.remove_absolute(path)


# ===========================================================================
# An entity definition becomes the node it names (#598, #599)
# ===========================================================================


func _place(entity_class: String) -> DraftEntity:
	return root._create_entity_from_map({"classname": entity_class, "origin": Vector3.ZERO})


func _exported_tree(file_name: String) -> Node:
	var path := "user://%s" % file_name
	assert_true(root.export_playtest_scene(path), "the export has to succeed")
	var packed: PackedScene = ResourceLoader.load(path)
	DirAccess.remove_absolute(path)
	assert_not_null(packed, "the exported scene has to load back")
	return packed.instantiate() if packed else null


func test_a_light_entity_becomes_a_light():
	var lamp := _place("light_point")
	lamp.name = "lamp_1"
	var scene := _exported_tree("hf_playtest_light_entity.tscn")
	var found: OmniLight3D = null
	for child in scene.get_children():
		if child is OmniLight3D:
			found = child as OmniLight3D
	assert_not_null(found, "entities.json names OmniLight3D, so the playtest gets one")
	if found:
		assert_eq(found.name, StringName("lamp_1"), "and it keeps the name it was placed under")
	scene.free()


func test_a_placed_light_stops_the_fallback_sun_being_added():
	_place("light_point")
	var scene := _exported_tree("hf_playtest_no_fallback.tscn")
	var suns := 0
	for child in scene.get_children():
		if child is DirectionalLight3D:
			suns += 1
	assert_eq(suns, 0, "a level that lights itself does not need PlaytestSun")
	scene.free()


func test_a_lights_authored_properties_land_on_the_real_node():
	var lamp := _place("light_point")
	lamp.entity_data["range"] = 42.0
	lamp.entity_data["energy"] = 3.5
	lamp.entity_data["color"] = Color(1.0, 0.0, 0.0)
	var scene := _exported_tree("hf_playtest_light_props.tscn")
	var found: OmniLight3D = null
	for child in scene.get_children():
		if child is OmniLight3D:
			found = child as OmniLight3D
	assert_not_null(found)
	if found:
		# The names the level stores and the names the engine uses differ, which is
		# what `maps_to` in entities.json is for.
		assert_almost_eq(found.omni_range, 42.0, 0.001, "Range reaches omni_range")
		assert_almost_eq(found.light_energy, 3.5, 0.001, "Energy reaches light_energy")
		assert_almost_eq(found.light_color.r, 1.0, 0.01, "Colour reaches light_color")
	scene.free()


func test_a_marker_entity_is_still_exported_as_a_marker():
	var start := _place("player_start")
	start.name = "start"
	var scene := _exported_tree("hf_playtest_marker.tscn")
	var names: Array = []
	for child in scene.get_children():
		names.append(str(child.name))
	assert_true(names.has("start"), "a definition naming a plain Node3D ships the marker")
	scene.free()


func test_an_entity_definition_can_name_a_scene_to_instantiate():
	# #599: `scene` was parsed, serialized and never instantiated.
	var scene_path := "user://hf_test_entity_prop.tscn"
	var prop_root := MeshInstance3D.new()
	prop_root.name = "PropRoot"
	var packed_prop := PackedScene.new()
	assert_eq(packed_prop.pack(prop_root), OK)
	assert_eq(ResourceSaver.save(packed_prop, scene_path), OK)
	prop_root.free()

	root.entity_definitions["prop_test"] = {
		"classname": "prop_test",
		"scene": scene_path,
		"properties": [],
	}
	var placed := _place("prop_test")
	placed.name = "prop_1"
	var scene := _exported_tree("hf_playtest_scene_entity.tscn")
	var found := false
	for child in scene.get_children():
		if child is MeshInstance3D and str(child.name) == "prop_1":
			found = true
	assert_true(found, "the named scene is what the playtest should carry")
	scene.free()
	DirAccess.remove_absolute(scene_path)


func test_a_scene_path_that_does_not_exist_falls_back_to_the_marker():
	root.entity_definitions["prop_missing"] = {
		"classname": "prop_missing",
		"scene": "res://does/not/exist.tscn",
		"properties": [],
	}
	var placed := _place("prop_missing")
	placed.name = "prop_2"
	var scene := _exported_tree("hf_playtest_missing_scene.tscn")
	var names: Array = []
	for child in scene.get_children():
		names.append(str(child.name))
	assert_true(names.has("prop_2"), "a level still exports when a definition is wrong")
	scene.free()


func test_wiring_survives_being_rebuilt_as_a_real_node():
	var button := _place("light_point")
	button.set_meta("entity_name", "lamp_1")
	root.add_entity_output(button, "OnTrigger", "lamp_1", "TurnOn")
	var scene := _exported_tree("hf_playtest_light_io.tscn")
	var carried := false
	for child in scene.get_children():
		if child is OmniLight3D:
			carried = not child.get_meta("entity_io_outputs", []).is_empty()
	assert_true(carried, "the wiring hung on the marker has to move with it")
	scene.free()


# ===========================================================================
# A prop's model reaches the level (#690)
# ===========================================================================

const _CRATE_PATH := "user://hf_test_prop_crate.tscn"


func _write_crate_scene() -> void:
	var crate := Node3D.new()
	crate.name = "Crate"
	var mi := MeshInstance3D.new()
	mi.name = "CrateMesh"
	mi.mesh = BoxMesh.new()
	crate.add_child(mi)
	mi.owner = crate
	var packed := PackedScene.new()
	assert_eq(packed.pack(crate), OK)
	assert_eq(ResourceSaver.save(packed, _CRATE_PATH), OK)
	crate.free()


func _remove_crate_scene() -> void:
	if FileAccess.file_exists(_CRATE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_CRATE_PATH))


func _place_crate_prop() -> Node3D:
	return (
		root
		. _restore_entity_from_info(
			{
				"entity_type": "prop_static",
				"entity_class": "prop_static",
				"transform": Transform3D(Basis.IDENTITY, Vector3(2, 0.4, 0)),
				"properties": {"scene": _CRATE_PATH},
				"name": "crate_1",
				"entity_name": "crate_1",
			}
		)
	)


func _mesh_names(node: Node, out: Array) -> Array:
	if node is MeshInstance3D:
		out.append(str(node.name))
	for child in node.get_children():
		_mesh_names(child, out)
	return out


func test_a_prop_scene_is_instantiated_into_the_playtest_node():
	# prop_static is the documented way to put a model in a level, and its path was
	# stored, saved and exported as an empty marker with nothing said anywhere.
	_write_crate_scene()
	var prop: Node3D = _place_crate_prop()
	assert_not_null(prop, "the prop should have been placed")
	var built: Node3D = root._playtest_node_for_entity(prop)
	assert_not_null(built, "a prop naming a scene should build that scene")
	assert_eq(_mesh_names(built, []), ["CrateMesh"], "the model should be under the node")
	built.free()
	_remove_crate_scene()


func test_a_prop_with_no_scene_still_builds_its_marker():
	var prop: Node3D = (
		root
		. _restore_entity_from_info(
			{
				"entity_type": "prop_static",
				"entity_class": "prop_static",
				"transform": Transform3D.IDENTITY,
				"properties": {"scene": ""},
				"name": "crate_2",
			}
		)
	)
	assert_not_null(prop)
	var built: Node3D = root._playtest_node_for_entity(prop)
	if built:
		assert_eq(_mesh_names(built, []), [], "an unset path brings no model with it")
		built.free()


func test_an_instantiated_scene_survives_packing_once():
	# Owning the inside of an instantiated scene makes pack() write those nodes out
	# beside the instance too, so the saved scene holds the model twice.
	_write_crate_scene()
	var outer := Node3D.new()
	outer.name = "PackRoot"
	add_child_autoqfree(outer)
	var inst: Node3D = (load(_CRATE_PATH) as PackedScene).instantiate()
	inst.name = "crate_1"
	outer.add_child(inst)
	root._own_tree(inst, outer)
	var packed := PackedScene.new()
	assert_eq(packed.pack(outer), OK)
	var path := "user://hf_test_prop_outer.tscn"
	assert_eq(ResourceSaver.save(packed, path), OK)
	var back: Node = (load(path) as PackedScene).instantiate()
	assert_eq(_mesh_names(back, []), ["CrateMesh"], "one model in, one model out")
	back.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_remove_crate_scene()
