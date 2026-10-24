extends GutTest

## A `.hfprefab` was written with `FileAccess.WRITE`, which empties the file
## before the new text is stored. A save cut short, killed or out of power, left
## an empty or partial prefab, and every linked copy read it on its next Pull
## (#1758). It writes whole now, as the settings files do, and so do the `.map`
## export and Settings Export.

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")
const HFDockFileHandler = preload("res://addons/hammerforge/dock_file_handler.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const DIR := "user://hf_prefab_writes_whole_test"
const PREFAB_PATH := DIR + "/door.hfprefab"
const MAP_PATH := DIR + "/level.map"
const SETTINGS_PATH := DIR + "/settings.json"


func after_each() -> void:
	HFLog.end_test_capture()
	for path in [PREFAB_PATH, MAP_PATH, SETTINGS_PATH]:
		for suffix in ["", ".writing", ".previous"]:
			var full := ProjectSettings.globalize_path(path + suffix)
			if DirAccess.dir_exists_absolute(full):
				DirAccess.remove_absolute(full)
			elif FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(full)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _prefab(prefab_name: String) -> HFPrefab:
	var prefab := HFPrefabType.new()
	prefab.prefab_name = prefab_name
	return prefab


## A directory where the temporary file goes stops the write before it touches
## the file. Writing in place emptied the file first.
func _block_the_temporary_file(path: String) -> void:
	assert_eq(
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path + ".writing")), OK
	)


func test_a_prefab_save_leaves_no_temporary_file():
	assert_eq(_prefab("door").save_to_file(PREFAB_PATH), OK)
	assert_eq(HFPrefabType.load_from_file(PREFAB_PATH).prefab_name, "door")
	assert_false(FileAccess.file_exists(PREFAB_PATH + ".writing"), "no temporary file left")
	assert_false(FileAccess.file_exists(PREFAB_PATH + ".previous"), "no backup left")


func test_a_prefab_save_that_cannot_finish_leaves_the_old_prefab():
	assert_eq(_prefab("door").save_to_file(PREFAB_PATH), OK)
	_block_the_temporary_file(PREFAB_PATH)
	assert_ne(_prefab("gate").save_to_file(PREFAB_PATH), OK, "the save says it failed")
	var loaded := HFPrefabType.load_from_file(PREFAB_PATH)
	assert_not_null(loaded, "the old prefab still loads")
	if loaded:
		assert_eq(loaded.prefab_name, "door", "as it was")


## What a kill between the backup and the rename leaves: the old prefab as
## `.previous`, and no file of its own name.
func test_a_prefab_save_cut_short_leaves_the_old_prefab_to_load():
	assert_eq(_prefab("door").save_to_file(PREFAB_PATH), OK)
	var full := ProjectSettings.globalize_path(PREFAB_PATH)
	assert_eq(DirAccess.rename_absolute(full, full + ".previous"), OK)
	var loaded := HFPrefabType.load_from_file(PREFAB_PATH)
	assert_not_null(loaded, "the backup loads")
	if loaded:
		assert_eq(loaded.prefab_name, "door")


func test_a_map_export_that_cannot_finish_leaves_the_old_file():
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	(
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(2, 2, 2),
				"transform": Transform3D.IDENTITY,
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)
	assert_eq(root.export_map(MAP_PATH), OK)
	var before := FileAccess.get_file_as_string(MAP_PATH)
	assert_true(before.length() > 0, "fixture: a .map with a brush in it")
	assert_false(FileAccess.file_exists(MAP_PATH + ".writing"), "no temporary file left")
	_block_the_temporary_file(MAP_PATH)
	var errors_before := get_errors().size()
	assert_ne(root.export_map(MAP_PATH), OK, "the export says it failed")
	var said: Array = get_errors().slice(errors_before)
	assert_eq(said.size(), 1, "and reports it")
	for e in said:
		e.handled = true
	assert_eq(FileAccess.get_file_as_string(MAP_PATH), before, "the old .map stays")


class SettingsDock:
	extends RefCounted
	var said := ""
	var failed := false

	func _collect_editor_settings() -> Dictionary:
		return {"grid_snap": 2.0}

	func _set_status(text: String, is_error: bool = false, _timeout: float = 0.0) -> void:
		said = text
		failed = is_error


func test_a_settings_export_that_cannot_finish_leaves_the_old_file():
	var dock := SettingsDock.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	HFDockFileHandler.on_settings_export_selected(dock, SETTINGS_PATH)
	assert_false(dock.failed, dock.said)
	var before := FileAccess.get_file_as_string(SETTINGS_PATH)
	assert_string_contains(before, "grid_snap")
	assert_false(FileAccess.file_exists(SETTINGS_PATH + ".writing"), "no temporary file left")
	_block_the_temporary_file(SETTINGS_PATH)
	HFDockFileHandler.on_settings_export_selected(dock, SETTINGS_PATH)
	assert_true(dock.failed, "the export says it failed")
	assert_eq(FileAccess.get_file_as_string(SETTINGS_PATH), before, "the old settings stay")
