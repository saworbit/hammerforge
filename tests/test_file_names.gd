extends GutTest

## One set of rules for the files a mapper names: prefabs and brush presets
## (#1464). The prefab side is in `test_prefab_name_validation.gd`, the preset
## side in `test_brush_preset_names.gd`.

const HFFileNames = preload("res://addons/hammerforge/hf_file_names.gd")

const _SCRATCH := "user://test_file_names_1464"


func after_each() -> void:
	if not DirAccess.dir_exists_absolute(_SCRATCH):
		return
	for file_name in DirAccess.get_files_at(_SCRATCH):
		DirAccess.remove_absolute(_SCRATCH.path_join(file_name))
	DirAccess.remove_absolute(_SCRATCH)


func _touch(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(_SCRATCH)
	FileAccess.open(_SCRATCH.path_join(file_name), FileAccess.WRITE).close()


func _free_file(stem: String) -> String:
	return HFFileNames.unused_path(_SCRATCH, stem, "tres").get_file()


func _stem(file_name: String) -> String:
	return HFFileNames.safe_file_stem(file_name, "Preset", "preset")


func test_a_device_name_is_judged_by_what_comes_before_its_first_dot():
	# Godot's Windows file access refuses every one of these, extension or not.
	assert_eq(_stem("CON"), "CON_preset")
	assert_eq(_stem("com0"), "com0_preset")
	assert_eq(_stem("LPT¹"), "LPT¹_preset")
	assert_eq(_stem("con.wall"), "con_preset.wall")


func test_a_name_that_only_starts_like_a_device_is_untouched():
	assert_eq(_stem("console"), "console")
	assert_eq(_stem("CON_wall"), "CON_wall")


func test_leading_dots_and_separators_neither_hide_nor_move_a_file():
	assert_eq(_stem("..x"), "x")
	assert_eq(_stem("../up"), "_up")
	assert_eq(_stem("..."), "Preset", "nothing left, so the fallback")


func test_case_and_spacing_are_the_callers_to_decide():
	assert_eq(_stem("Wide_Wall"), "Wide_Wall")


func test_a_free_name_is_kept_and_a_taken_one_is_numbered_from_2():
	assert_eq(_free_file("Doorway"), "Doorway.tres")
	_touch("Doorway.tres")
	assert_eq(_free_file("Doorway"), "Doorway_2.tres")
	_touch("Doorway_2.tres")
	assert_eq(_free_file("Doorway"), "Doorway_3.tres")


func test_a_numbered_stem_stays_inside_the_length_cap():
	var stem := _stem("a".repeat(300))
	assert_eq(stem.length(), HFFileNames.MAX_STEM_LENGTH)
	_touch(stem + ".tres")
	var numbered := HFFileNames.unused_path(_SCRATCH, stem, "tres").get_file().get_basename()
	assert_true(numbered.ends_with("_2"), numbered)
	assert_eq(numbered.length(), HFFileNames.MAX_STEM_LENGTH)
	assert_eq(_stem(numbered), numbered, "and the rules give it back unchanged")
