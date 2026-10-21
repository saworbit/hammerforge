extends GutTest

## A brush preset is told apart from another only by its button label, so two
## buttons reading the same thing leave the mapper clicking one to find out which
## it is.
##
## `_suggest_preset_name()` counted the buttons on screen, which matches the
## highest name in use only while none has ever been deleted. `_unique_preset_path()`
## made the *file* unique and left `resource_name` alone, and
## `_preset_display_name()` returns `resource_name` when it is set, so the label
## was the one thing that collided.

const DockType = preload("res://addons/hammerforge/dock.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")

## Where the file tests below keep their presets, never the project's own folder.
const _SCRATCH := "user://test_brush_preset_files"


## A stand-in for the button row: `_suggest_preset_name()` reads `text` off each.
class FakePresetButton:
	extends Button


func after_each() -> void:
	if not DirAccess.dir_exists_absolute(_SCRATCH):
		return
	for file_name in DirAccess.get_files_at(_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_SCRATCH.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_SCRATCH))


func _dock_with_presets(names: Array) -> Node:
	# Not added to the tree: `_ready()` builds the whole dock and the naming does
	# not need any of it, only the button row.
	var dock := DockType.new()
	autofree(dock)
	for preset_name in names:
		var button := FakePresetButton.new()
		button.text = str(preset_name)
		autoqfree(button)
		dock.preset_buttons.append(button)
	return dock


func test_the_first_preset_is_preset_1():
	assert_eq(_dock_with_presets([])._suggest_preset_name(), "Preset 1")


func test_the_next_preset_follows_the_ones_on_screen():
	var dock := _dock_with_presets(["Preset 1", "Preset 2"])
	assert_eq(dock._suggest_preset_name(), "Preset 3")


## Three saves, delete the middle one, save again. The count says 3 and 3 is
## taken.
func test_deleting_from_the_middle_does_not_produce_a_second_preset_3():
	var dock := _dock_with_presets(["Preset 1", "Preset 3"])

	assert_ne(dock._suggest_preset_name(), "Preset 3", "that name is on screen already")


func test_a_longer_run_of_deletes_still_names_something_free():
	var dock := _dock_with_presets(["Preset 3", "Preset 4", "Preset 5"])

	var suggested: String = dock._suggest_preset_name()

	for existing in ["Preset 3", "Preset 4", "Preset 5"]:
		assert_ne(suggested, existing, "%s is taken" % existing)


func test_a_renamed_preset_still_counts_as_taken():
	var dock := _dock_with_presets(["Doorway", "Preset 2"])

	assert_ne(dock._suggest_preset_name(), "Preset 2")


## A preset renamed to something else entirely leaves the numbered names free.
func test_names_that_are_not_numbered_do_not_push_the_suggestion_up():
	var dock := _dock_with_presets(["Doorway"])

	assert_eq(dock._suggest_preset_name(), "Preset 2", "one button on screen, so the count is 2")


# ---------------------------------------------------------------------------
# The file a preset is saved in
# ---------------------------------------------------------------------------


## A dock in the tree, so the preset row is built, keeping presets in the scratch
## folder.
func _dock_saving_presets() -> Node:
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.presets_dir = _SCRATCH
	dock._load_presets()
	return dock


func _button_reading(dock: Node, label: String) -> Button:
	for button in dock.preset_buttons:
		if button.text == label:
			return button
	return null


## Save a new preset and rename it `new_name`. Returns the file of the button
## that then reads `new_name`, or "" when none does.
func _save_and_rename(dock: Node, new_name: String) -> String:
	var saved_as: String = dock._suggest_preset_name()
	dock._on_save_preset()
	var saved := _button_reading(dock, saved_as)
	if saved == null:
		return ""
	dock._rename_preset(saved, new_name)
	var renamed := _button_reading(dock, new_name)
	return "" if renamed == null else str(renamed.get_meta("preset_path", ""))


func _preset_files(dock: Node) -> Array:
	var files: Array = []
	for button in dock.preset_buttons:
		files.append(str(button.get_meta("preset_path", "")).get_file())
	return files


func test_a_preset_named_for_a_windows_device_still_gets_a_file_to_open():
	# Windows refuses `CON` and the rest as file names whatever extension
	# follows, so the rename failed with nothing on screen. The prefab names have
	# been renamed out of the way since #667 (#1464).
	var dock := _dock_saving_presets()
	for reserved in ["CON", "nul", "COM1", "lpt9"]:
		var path := _save_and_rename(dock, reserved)
		assert_ne(path, "", "%s is listed under the name it was given" % reserved)
		assert_ne(path.get_file().get_basename().to_upper(), reserved.to_upper(), path)
		assert_true(FileAccess.file_exists(path), "%s is on disk" % path)
		assert_true(load(path) is BrushPreset, "%s reads back as a preset" % path)


func test_a_preset_named_with_leading_dots_gets_a_visible_file_in_the_folder():
	# A file starting with a dot is hidden: the panel's own listing skips it on
	# Linux and macOS, and the editor's FileSystem dock everywhere (#1464).
	var dock := _dock_saving_presets()
	for dotted in ["..x", ".hidden", "../up"]:
		var path := _save_and_rename(dock, dotted)
		assert_ne(path, "", "%s is listed under the name it was given" % dotted)
		assert_false(path.get_file().begins_with("."), "%s is not hidden" % path)
		assert_eq(path.get_base_dir(), _SCRATCH, "%s stays in the presets folder" % path)
		assert_true(FileAccess.file_exists(path), "%s is on disk" % path)


func test_a_second_preset_of_one_name_is_numbered_as_a_prefab_is():
	# One next-free-name rule for every file a mapper names: the second is _2,
	# as a second quick-saved box is `box_2` (#1464).
	var dock := _dock_saving_presets()
	_save_and_rename(dock, "Doorway")
	_save_and_rename(dock, "Doorway")
	assert_eq(_preset_files(dock), ["Doorway.tres", "Doorway_2.tres"])


func test_renaming_a_preset_to_its_own_name_keeps_its_file():
	# A preset saved before the shared name rules keeps the file it has.
	var dock := _dock_saving_presets()
	dock._on_save_preset()
	assert_eq(_preset_files(dock), ["Preset_1.tres"])
	dock._rename_preset(dock.preset_buttons[0], "Preset 1")
	assert_eq(_preset_files(dock), ["Preset_1.tres"], "no file was renamed")
