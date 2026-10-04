extends GutTest

## A prefab save never replaces a file without asking (#929).
##
## Quick Save named the file after what was selected, so a second box saved over
## the first box's file, and the instances linked to it followed. The panel's
## Save kept its own copy of the save that skipped the safe file name from #667,
## so "../escape" landed beside project.godot and "wall/trim" wrote nothing.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const HFPluginPrefabCommands = preload("res://addons/hammerforge/plugin_prefab_commands.gd")

const _SCRATCH := "user://test_prefab_save_929"


class FakeLibrary:
	extends RefCounted

	var refreshes := 0

	func on_prefab_saved() -> void:
		refreshes += 1


class FakeDock:
	extends RefCounted

	var toasts: Array = []
	var _prefab_library := FakeLibrary.new()

	func show_toast(message: String, _level: int = 0) -> void:
		toasts.append(message)


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var hf_selection: Array = []


var dock: HammerForgeDock
var root: LevelRoot
## res:// files this test wrote, removed again after each test.
var _written: Array = []
var _made_prefab_dir := false


func before_each() -> void:
	_made_prefab_dir = not DirAccess.dir_exists_absolute(HFPrefabSystemType.PREFAB_DIR)
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
	DirAccess.make_dir_recursive_absolute(_SCRATCH)


func after_each() -> void:
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_written.clear()
	if _made_prefab_dir and DirAccess.dir_exists_absolute(HFPrefabSystemType.PREFAB_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HFPrefabSystemType.PREFAB_DIR))
	for file_name in DirAccess.get_files_at(_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_SCRATCH.path_join(file_name)))
	dock = null
	root = null


func _brush(size: Vector3) -> Node:
	return root.create_brush_from_info({"size": size, "center": Vector3.ZERO})


func _expect(path: String) -> String:
	_written.append(path)
	return path


func _pending_dialog() -> ConfirmationDialog:
	return dock.get_node_or_null("PrefabReplaceConfirm") as ConfirmationDialog


# ---------------------------------------------------------------------------
# The next free name
# ---------------------------------------------------------------------------


func test_a_free_name_is_kept_and_a_taken_one_is_numbered():
	assert_eq(HFPrefabSystemType.unused_prefab_name("box", _SCRATCH), "box")
	FileAccess.open(_SCRATCH.path_join("box.hfprefab"), FileAccess.WRITE).close()
	assert_eq(HFPrefabSystemType.unused_prefab_name("box", _SCRATCH), "box_2")
	FileAccess.open(_SCRATCH.path_join("box_2.hfprefab"), FileAccess.WRITE).close()
	assert_eq(HFPrefabSystemType.unused_prefab_name("box", _SCRATCH), "box_3")


func test_two_quick_saves_of_different_shapes_leave_two_files():
	var plugin := FakePlugin.new()
	var first_path := _expect(HFPrefabSystemType.prefab_path("box"))
	var second_path := _expect(HFPrefabSystemType.prefab_path("box_2"))
	assert_false(FileAccess.file_exists(first_path), "the test needs a clean prefab folder")

	plugin.hf_selection = [_brush(Vector3(2, 2, 2))]
	HFPluginPrefabCommands.quick_save(plugin, root, false)
	var first := FileAccess.get_file_as_string(first_path)
	plugin.hf_selection = [_brush(Vector3(6, 1, 6))]
	HFPluginPrefabCommands.quick_save(plugin, root, false)

	assert_eq(FileAccess.get_file_as_string(first_path), first, "the first box is untouched")
	assert_true(FileAccess.file_exists(second_path), "the slab got a file of its own")
	assert_eq(plugin.dock.toasts, ["Saved prefab: box", "Saved prefab: box_2"])


# ---------------------------------------------------------------------------
# The panel's Save
# ---------------------------------------------------------------------------


func test_the_panel_save_keeps_a_slash_inside_the_prefab_folder():
	var path := _expect(HFPrefabSystemType.prefab_path("wall/trim"))
	assert_eq(path.get_base_dir(), HFPrefabSystemType.PREFAB_DIR)
	dock._save_prefab_from_panel("wall/trim", [_brush(Vector3(2, 2, 2))], [], false)
	assert_true(FileAccess.file_exists(path), "it used to write nothing and say nothing")


func test_the_panel_save_cannot_climb_out_of_the_prefab_folder():
	var path := _expect(HFPrefabSystemType.prefab_path("../escape"))
	_expect("res://escape.hfprefab")
	dock._save_prefab_from_panel("../escape", [_brush(Vector3(2, 2, 2))], [], false)
	assert_true(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists("res://escape.hfprefab"), "not beside project.godot")


func test_the_panel_save_asks_before_replacing_a_file():
	var path := _expect(HFPrefabSystemType.prefab_path("crate"))
	dock._save_prefab_from_panel("crate", [_brush(Vector3(2, 2, 2))], [], false)
	var before := FileAccess.get_file_as_string(path)
	assert_null(_pending_dialog(), "a new name needs no question")

	dock._save_prefab_from_panel("crate", [_brush(Vector3(6, 1, 6))], [], true)
	var dlg := _pending_dialog()
	assert_not_null(dlg, "an existing name asks first")
	assert_eq(FileAccess.get_file_as_string(path), before, "and writes nothing until answered")
	if dlg:
		assert_string_contains(dlg.dialog_text, "crate.hfprefab")
		dlg.confirmed.emit()
	assert_ne(FileAccess.get_file_as_string(path), before, "Replace writes the new shape")
