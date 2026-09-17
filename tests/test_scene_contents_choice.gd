extends GutTest

## What the `.tscn` keeps of a level, as against what the `.hflevel` keeps (#624).
##
## HammerForge gives an `owner` to almost everything it makes, so Godot's own
## Ctrl+S writes the brushes and the geometry baked from them into the scene file,
## and Save Level writes a third copy beside it. A 100 brush level measured 261 KB
## of `.tscn` against 4 KB of `.hflevel`, and a bake added another 149 KB that is
## entirely derivable from the brushes already in the file.
##
## Ownership is the whole mechanism: a node with an owner is written to the scene
## and a node without one is not, so these tests assert `owner` rather than
## measuring a file.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	# `_get_editor_owner()` reads `edited_scene_root`, which is null headless, and
	# falls back to `get_owner()`. Without one, every owner here is null and the
	# assertions below pass whatever the setting does.
	root.owner = self
	return root


func _box(root: LevelRoot, at := Vector3.ZERO) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(2, 2, 2),
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


func _a_baked_container(root: LevelRoot) -> Node3D:
	var container := Node3D.new()
	container.name = "BakedGeometry"
	var mesh := MeshInstance3D.new()
	mesh.name = "BakedMesh_0"
	container.add_child(mesh)
	root.add_child(container)
	return container


# ===========================================================================
# The default is what HammerForge has always done
# ===========================================================================


func test_a_level_keeps_its_brushes_and_its_bake_unless_asked_otherwise():
	var root := _fresh_root()
	assert_eq(
		root.scene_contents,
		LevelRootType.SceneContents.BRUSHES_AND_BAKE,
		"the default is the behaviour that needs no other file"
	)
	assert_true(root.scene_keeps_brushes(), "the scene is the whole level on its own")
	assert_true(root.scene_keeps_bake(), "including geometry that runs without the plugin")


# ===========================================================================
# Brushes only: the scene stays the size of its sources
# ===========================================================================


func test_brushes_only_leaves_the_baked_geometry_out_of_the_scene():
	var root := _fresh_root()
	root.scene_contents = LevelRootType.SceneContents.BRUSHES_ONLY
	var container := _a_baked_container(root)

	root._assign_owner_recursive(container)

	assert_null(container.owner, "the bake is not written to the .tscn")
	assert_null(container.get_child(0).owner, "nor is anything under it")
	assert_true(root.scene_keeps_brushes(), "but the brushes still are")


func test_brushes_only_still_owns_a_brush():
	var root := _fresh_root()
	root.scene_contents = LevelRootType.SceneContents.BRUSHES_ONLY
	var brush := _box(root)
	assert_eq(root._get_editor_owner(), brush.owner, "a brush is still the scene's")


# ===========================================================================
# Bake only: the lightest scene, and the one that needs the other file
# ===========================================================================


func test_bake_only_leaves_the_brushes_out_of_the_scene():
	var root := _fresh_root()
	root.hflevel_autosave_path = "user://hf_scene_contents_%d.hflevel" % Time.get_ticks_usec()
	root.scene_contents = LevelRootType.SceneContents.BAKE_ONLY

	var brush := _box(root)

	assert_false(root.scene_keeps_brushes(), "the brushes live in the .hflevel")
	assert_null(brush.owner, "so the brush is not written to the .tscn")
	assert_true(root.scene_keeps_bake(), "while the geometry is")


func test_bake_only_is_refused_when_there_is_nowhere_to_put_the_brushes():
	# The one way this setting can lose work. A level with no .hflevel path that
	# stopped owning its brushes would be dropping its only copy of them.
	var root := _fresh_root()
	root.hflevel_autosave_path = ""
	root.scene_contents = LevelRootType.SceneContents.BAKE_ONLY

	var brush := _box(root)

	assert_true(root.scene_keeps_brushes(), "the scene keeps them regardless")
	assert_eq(root._get_editor_owner(), brush.owner, "so the brush is still written")
	assert_true(
		root.scene_contents_description().contains("no .hflevel path"),
		"and the setting says why it is not doing what it was set to"
	)


# ===========================================================================
# Changing the setting reaches what is already there
# ===========================================================================


func test_changing_the_setting_re_owns_the_level_that_is_already_built():
	# Otherwise the setting would only describe what gets built after it, and the
	# next Ctrl+S would write something the setting does not say.
	var root := _fresh_root()
	var brush := _box(root)
	var container := _a_baked_container(root)
	root.baked_container = container
	root._assign_owner_recursive(container)
	assert_not_null(container.owner, "the bake starts owned")

	root.scene_contents = LevelRootType.SceneContents.BRUSHES_ONLY

	assert_null(container.owner, "the bake already in the level stopped being written")
	assert_eq(root._get_editor_owner(), brush.owner, "and the brush still is")


func test_going_back_to_the_default_re_owns_the_bake():
	var root := _fresh_root()
	var container := _a_baked_container(root)
	root.baked_container = container
	root.scene_contents = LevelRootType.SceneContents.BRUSHES_ONLY
	root._assign_owner_recursive(container)
	assert_null(container.owner)

	root.scene_contents = LevelRootType.SceneContents.BRUSHES_AND_BAKE

	assert_not_null(container.owner, "the bake is written again")


# ===========================================================================
# The setting travels with the level
# ===========================================================================


func test_the_setting_is_captured_and_restored_with_the_level():
	var root := _fresh_root()
	root.scene_contents = LevelRootType.SceneContents.BRUSHES_ONLY
	var settings: Dictionary = root._capture_hflevel_settings()
	assert_eq(
		int(settings.get("scene_contents", -1)),
		LevelRootType.SceneContents.BRUSHES_ONLY,
		"a .hflevel records what the scene was keeping"
	)

	var other := _fresh_root()
	other._apply_hflevel_settings(settings)
	assert_eq(
		other.scene_contents,
		LevelRootType.SceneContents.BRUSHES_ONLY,
		"and a level loaded from it keeps the same arrangement"
	)


func test_an_out_of_range_setting_from_a_file_lands_on_a_mode_that_exists():
	# `.hflevel` is JSON, hand editable, and written by older builds.
	var root := _fresh_root()
	root._apply_hflevel_settings({"scene_contents": 99})
	assert_lt(int(root.scene_contents), LevelRootType.SceneContents.size(), "clamped to a mode")
	root._apply_hflevel_settings({"scene_contents": -5})
	assert_gte(int(root.scene_contents), 0, "and not below one either")


# ===========================================================================
# Saying it once, when the two files disagree (#646)
# ===========================================================================


func test_a_level_offers_its_freshness_report_once_per_open():
	var root := _fresh_root()

	var first: Dictionary = root.take_hflevel_freshness_report()
	assert_true(first.has("stale"), "the first ask gets the report")

	assert_eq(
		root.take_hflevel_freshness_report(),
		{},
		"the dock rebinds on every scene tab switch, and it is the same level each time"
	)


func test_asking_for_the_report_directly_is_not_latched():
	var root := _fresh_root()

	root.take_hflevel_freshness_report()
	assert_true(
		root.check_hflevel_freshness().has("stale"),
		"the latch is the dock's once-per-open, not an answer the level stops giving"
	)


func test_a_level_resolves_the_scene_that_holds_it_through_its_owners():
	var scene_root := Node3D.new()
	scene_root.scene_file_path = "user://hf_owner_chain_test.tscn"
	add_child_autoqfree(scene_root)
	var level := LevelRootType.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	scene_root.add_child(level)
	level.owner = scene_root

	assert_eq(
		level.scene_source_path(),
		"user://hf_owner_chain_test.tscn",
		"the topmost unowned node is the scene a level belongs to, whichever tab is in front"
	)


func test_a_level_that_is_its_own_scene_resolves_to_itself():
	var level := LevelRootType.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	level.scene_file_path = "user://hf_own_scene_test.tscn"

	assert_eq(level.scene_source_path(), "user://hf_own_scene_test.tscn")


func test_a_level_that_was_never_saved_has_no_scene_path():
	assert_eq(_fresh_root().scene_source_path(), "", "nothing to be out of step with")
