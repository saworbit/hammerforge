extends GutTest

## Structure presets, bake profiles, the keymap, I/O presets and the material
## library were written with `FileAccess.WRITE`, which empties the file before the
## new text is stored, so a write cut short lost every entry in it (#1663). They
## write whole now, through `HFSettingsFile` (#1679).

const HFSettingsFile = preload("res://addons/hammerforge/hf_settings_file.gd")
const HFStructurePresets = preload("res://addons/hammerforge/hf_structure_presets.gd")
const HFBakeProfiles = preload("res://addons/hammerforge/hf_bake_profiles.gd")
const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

const PATH := "user://hf_settings_file_test/shared.json"


func after_each() -> void:
	HFLog.end_test_capture()
	for suffix in ["", ".writing", ".previous"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))


func test_a_write_and_a_read_give_back_the_section():
	assert_true(HFSettingsFile.write(PATH, "presets", {"stairs": {"Main": {"steps": 8}}}, "T"))
	assert_eq(HFSettingsFile.read(PATH, "presets", "T"), {"stairs": {"Main": {"steps": 8.0}}})
	assert_false(FileAccess.file_exists(PATH + ".writing"), "no temporary file left")
	assert_false(FileAccess.file_exists(PATH + ".previous"), "no backup left")


func test_a_write_cut_short_leaves_the_old_file_to_read():
	assert_true(HFSettingsFile.write(PATH, "presets", {"stairs": {"Main": {}}}, "T"))
	# What a kill between the backup and the rename leaves: the old file as
	# `.previous`, and no file of its own name.
	var full := ProjectSettings.globalize_path(PATH)
	assert_eq(DirAccess.rename_absolute(full, full + ".previous"), OK)
	assert_eq(HFSettingsFile.read(PATH, "presets", "T"), {"stairs": {"Main": {}}}, "read back")
	assert_false(HFSettingsFile.unreadable(PATH, "presets"))


func _said(text: String) -> int:
	return HFLog.get_captured_warnings().filter(func(w): return str(w).contains(text)).size()


func test_structure_presets_and_bake_profiles_say_a_broken_file_once():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("<<<<<<< conflict")
	file.close()
	HFLog.begin_test_capture(["is not a presets file", "is not a profiles file"])
	for _i in 3:
		assert_eq(HFStructurePresets.read_raw(PATH), {})
		assert_eq(HFBakeProfiles.read_project_raw(PATH), {})
	assert_eq(_said("is not a presets file"), 1, "presets say it once")
	assert_eq(_said("is not a profiles file"), 1, "profiles say it once")
	assert_true(HFStructurePresets.file_unreadable(PATH))
	assert_true(HFBakeProfiles.project_file_unreadable(PATH))


func test_the_writers_leave_no_temporary_file():
	assert_true(HFStructurePresets.write({"stairs": {}}, PATH))
	assert_eq(HFStructurePresets.read_raw(PATH), {"stairs": {}})
	assert_true(HFBakeProfiles.write_project({"Fast": {}}, PATH))
	assert_eq(HFBakeProfiles.read_project_raw(PATH), {"Fast": {}})
	var keymap := HFKeymapType.load_or_default("")
	keymap.save(PATH)
	assert_true(HFKeymapType.load_or_default(PATH).has_action("hollow"))
	assert_false(FileAccess.file_exists(PATH + ".writing"))


## A write that cannot finish leaves the file as it was. A directory where the
## temporary file goes stops the write before it touches the file; writing in
## place emptied the file first and lost every preset in it.
func test_a_write_that_cannot_finish_leaves_the_old_presets():
	assert_true(HFStructurePresets.write({"stairs": {"Main": {}}}, PATH))
	var blocker := ProjectSettings.globalize_path(PATH + ".writing")
	assert_eq(DirAccess.make_dir_recursive_absolute(blocker), OK)
	HFLog.begin_test_capture(["cannot write"])
	assert_false(HFStructurePresets.write({}, PATH), "the write says it failed")
	DirAccess.remove_absolute(blocker)
	assert_eq(HFStructurePresets.read_raw(PATH), {"stairs": {"Main": {}}}, "the old presets stay")
