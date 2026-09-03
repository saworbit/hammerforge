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
