extends GutTest

## Brush presets live in the project, not in the addon folder (#930).
##
## The upgrade steps replace `addons/hammerforge` outright, which is right for the
## plugin's own files and deleted every saved preset with them.

const DockType = preload("res://addons/hammerforge/dock.gd")

const _SCRATCH := "user://test_presets_930"
const _LEGACY := _SCRATCH + "/addons/hammerforge/presets"
const _TARGET := _SCRATCH + "/hammerforge_presets"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(_LEGACY)


func after_each() -> void:
	_remove_tree(_SCRATCH)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir_name in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(dir_name))
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write(path: String, text: String = '[gd_resource type="Resource" format=3]\n') -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_presets_are_saved_outside_the_addon_folder():
	# Not added to the tree: _ready() builds the whole dock and this needs none of it.
	var dock := DockType.new()
	autofree(dock)
	assert_false(dock.presets_dir.begins_with("res://addons/"), dock.presets_dir)


func test_presets_saved_in_the_addon_folder_move_out_once():
	_write(_LEGACY.path_join("preset_1.tres"), "one")
	_write(_LEGACY.path_join("wide_wall.tres"), "two")

	assert_eq(DockType.migrate_legacy_presets(_LEGACY, _TARGET), 2)

	assert_eq(FileAccess.get_file_as_string(_TARGET.path_join("preset_1.tres")), "one")
	assert_eq(FileAccess.get_file_as_string(_TARGET.path_join("wide_wall.tres")), "two")
	assert_false(DirAccess.dir_exists_absolute(_LEGACY), "the emptied old folder is gone")


func test_a_project_that_has_moved_is_left_alone():
	DirAccess.make_dir_recursive_absolute(_TARGET)
	_write(_LEGACY.path_join("late.tres"))

	assert_eq(DockType.migrate_legacy_presets(_LEGACY, _TARGET), 0)

	assert_true(FileAccess.file_exists(_LEGACY.path_join("late.tres")), "nothing moved")


func test_an_old_folder_with_no_presets_moves_nothing():
	_write(_LEGACY.path_join("notes.txt"))

	assert_eq(DockType.migrate_legacy_presets(_LEGACY, _TARGET), 0)

	assert_false(DirAccess.dir_exists_absolute(_TARGET), "no empty folder is made")
	assert_true(FileAccess.file_exists(_LEGACY.path_join("notes.txt")))


func test_an_empty_old_folder_is_cleared_away():
	assert_eq(DockType.migrate_legacy_presets(_LEGACY, _TARGET), 0)
	assert_false(DirAccess.dir_exists_absolute(_LEGACY), "every earlier version made it on load")
	assert_false(DirAccess.dir_exists_absolute(_TARGET))
