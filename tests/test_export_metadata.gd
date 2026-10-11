extends GutTest

## An exported game scene can carry metadata on its root. The MCP bridge writes
## the bake id and the revision it baked into the scene it hands to Didi, so the
## runtime test can check it loaded the bake it was told about.

const PATH := "user://hf_export_metadata_test.tscn"

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _exported_root() -> Node:
	var packed := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert_not_null(packed, "the scene was written")
	return autofree(packed.instantiate()) if packed else null


func test_metadata_rides_on_the_scene_root():
	var meta := {"bake_id": "b-1", "source_revision": 7, "target_id": "1:2:3"}
	assert_true(root.export_game_scene(PATH, meta))
	var scene := _exported_root()
	assert_true(scene.has_meta("hammerforge_bake"))
	assert_eq(scene.get_meta("hammerforge_bake"), meta)


func test_no_metadata_leaves_the_root_plain():
	assert_true(root.export_game_scene(PATH))
	assert_false(_exported_root().has_meta("hammerforge_bake"))
