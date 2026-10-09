extends GutTest

## The dock shows the level's settings after a load (#968).
##
## The dock read the settings into its controls only when it bound to a level.
## Load .hflevel applied the file's settings and left every control showing the
## level as it was before. A stale checkbox shows the wrong state; the cordon
## spins lost data, because one spin change wrote all six bounds back.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const CollationTests = preload("res://tests/test_undo_collation.gd")

## The cordon the open level has before the load.
const OLD_CORDON := AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
## The cordons the file brings.
const FILE_CORDON := AABB(Vector3(100, 100, 100), Vector3(8, 8, 8))
const FILE_EXTRA := AABB(Vector3(200, 100, 100), Vector3(8, 8, 8))

var root: LevelRoot
var dock: Node
var path := ""


func before_each():
	root = _level()
	root.bake_visible_only = false
	root.cordon_aabb = OLD_CORDON
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	path = "user://test_dock_settings_after_load_%d.hflevel" % Time.get_ticks_usec()
	_write_file()


func after_each():
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	dock = null
	root = null


func _level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


## A file whose settings differ from the open level's in every control checked.
func _write_file() -> void:
	var other := _level()
	other.bake_visible_only = true
	other.cordon_enabled = true
	other.cordon_aabb = FILE_CORDON
	var extra: Array[AABB] = [FILE_EXTRA]
	other.cordon_extra_aabbs = extra
	var bundle := {
		"version": HFLevelIO.FORMAT_VERSION,
		"saved_at": "now",
		"settings": other._capture_hflevel_settings(),
		"state": other.capture_state(),
	}
	HFLevelIO.save_to_path(path, HFLevelIO.encode_variant(bundle), false)


func _spins() -> AABB:
	var low := Vector3(dock.cordon_min_x.value, dock.cordon_min_y.value, dock.cordon_min_z.value)
	var high := Vector3(dock.cordon_max_x.value, dock.cordon_max_y.value, dock.cordon_max_z.value)
	return AABB(low, high - low)


func _assert_dock_shows_the_level(when: String) -> void:
	assert_eq(
		dock.bake_visible_only_check.button_pressed,
		root.bake_visible_only,
		"%s: Bake Visible Only shows the level's" % when
	)
	assert_eq(
		dock.cordon_enabled_check.button_pressed,
		root.cordon_enabled,
		"%s: Enable Cordon shows the level's" % when
	)
	assert_eq(
		dock.cordon_region_opt.item_count,
		root.get_cordon_regions().size(),
		"%s: the list holds the level's cordons" % when
	)
	assert_eq(_spins(), root.cordon_aabb, "%s: the spins show the level's cordon" % when)


func test_the_dock_shows_the_settings_the_file_brought():
	assert_eq(_spins(), OLD_CORDON, "fixture: the dock shows the open level's cordon")
	HFDockFileHandler.on_hflevel_load_selected(dock, path)
	assert_true(root.bake_visible_only, "fixture: the load set the file's settings")
	assert_eq(root.cordon_aabb, FILE_CORDON, "fixture: and its cordon")
	_assert_dock_shows_the_level("after the load")


func test_one_spin_after_a_load_moves_only_that_bound():
	HFDockFileHandler.on_hflevel_load_selected(dock, path)
	dock.cordon_max_y.value = 150.0
	var moved := FILE_CORDON
	moved.size.y = 50.0
	assert_eq(root.cordon_aabb, moved, "the other five bounds are the file's, not the old level's")
	assert_eq(root.get_cordon_regions().size(), 2, "and the file's second cordon is kept")


func test_the_dock_follows_the_undo_and_redo_of_a_load():
	var fake = CollationTests.FakeUndoRedo.new()
	# What the dock's Load .hflevel registers: the load, and the whole level
	# before it as the undo.
	HFUndoHelper.register_action(
		fake, root, "Load .hflevel", 0, "load_hflevel", [path], root.capture_full_state(), true
	)
	assert_eq(root.cordon_aabb, FILE_CORDON, "fixture: the step ran the load")
	_assert_dock_shows_the_level("after the load")

	fake.undo()
	assert_eq(root.cordon_aabb, OLD_CORDON, "fixture: undo put the old level back")
	assert_false(root.bake_visible_only, "fixture: and its settings")
	_assert_dock_shows_the_level("after the undo")

	fake.redo()
	assert_eq(root.cordon_aabb, FILE_CORDON, "fixture: redo loaded the file again")
	_assert_dock_shows_the_level("after the redo")
