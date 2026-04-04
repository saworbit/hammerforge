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
