extends GutTest

## A prefab name becomes a file name (#667).
##
## The library panel's Save box is free text and it went straight into a path.
## `to_snake_case()` normalises case and word breaks; it does not touch a slash,
## a dot or a leading `..`, so "../escape" resolved to `res://escape.hfprefab` --
## beside `project.godot`, outside the prefab directory, and invisible to the
## panel that made it.

const PrefabSystem = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")

const _DIR := "res://prefabs"


func _resolved(prefab_name: String) -> String:
	var file_name: String = PrefabSystem.prefab_file_name(prefab_name)
	return _DIR.path_join(file_name).simplify_path()


func test_a_traversal_cannot_leave_the_prefab_directory():
	var path := _resolved("../escape")
	assert_true(path.begins_with(_DIR), "'%s' is not inside %s" % [path, _DIR])


func test_a_deeper_traversal_cannot_either():
	assert_true(_resolved("../../../etc/passwd").begins_with(_DIR))
	assert_true(_resolved("..").begins_with(_DIR))
	assert_true(_resolved("....//....//x").begins_with(_DIR))


func test_a_separator_is_replaced_rather_than_failing_silently():
	# "level 2/pillar" is a name a mapper types on purpose. It used to produce
	# an empty return and no message at all.
	var file_name: String = PrefabSystem.prefab_file_name("level 2/pillar")
	assert_false(file_name.contains("/"), "no separator survives")
	assert_false(file_name.contains("\\"), "on either platform")
	assert_true(file_name.ends_with(".hfprefab"))
	assert_true(_resolved("level 2/pillar").begins_with(_DIR))


func test_a_name_cannot_start_with_a_dot():
	# A leading dot is what a traversal is made of, and hides the file besides.
	assert_false(PrefabSystem.prefab_file_name(".hidden").begins_with("."))


func test_a_very_long_name_is_capped():
	var long_name := "a".repeat(300)
	var file_name: String = PrefabSystem.prefab_file_name(long_name)
	assert_lt(file_name.length(), 255, "the usual filesystem limit for a whole name")
	assert_true(file_name.ends_with(".hfprefab"))


func test_a_name_that_cleans_to_nothing_still_gets_a_file():
	# `to_snake_case()` turns a run of spaces into a run of underscores, so the
	# whitespace case has to be trimmed before it rather than after.
	assert_eq(PrefabSystem.prefab_file_name("..."), "untitled.hfprefab")
	assert_eq(PrefabSystem.prefab_file_name("   "), "untitled.hfprefab")
	assert_eq(PrefabSystem.prefab_file_name(""), "untitled.hfprefab")


func test_an_ordinary_name_is_unchanged_apart_from_the_case_rule():
	# The existing behaviour has to survive: `to_snake_case()` is what the panel's
	# list and every saved prefab already assume.
	assert_eq(PrefabSystem.prefab_file_name("Stone Pillar"), "stone_pillar.hfprefab")
	assert_eq(PrefabSystem.prefab_file_name("wall_trim"), "wall_trim.hfprefab")


func test_a_reserved_device_name_still_gets_a_file():
	# `validate_filename()` replaces characters a filesystem refuses; it does not
	# know about names it refuses. On Windows these are devices whatever
	# extension follows, so `CON.hfprefab` could not be opened and the save
	# failed with nothing on screen.
	for reserved in ["CON", "con", "NUL", "com1", "LPT9", "aux"]:
		var file_name: String = PrefabSystem.prefab_file_name(reserved)
		assert_false(
			file_name.get_basename().to_upper() in PrefabSystem._RESERVED_FILE_NAMES,
			"'%s' became '%s', which Windows still refuses" % [reserved, file_name]
		)
		assert_true(file_name.ends_with(".hfprefab"))


func test_a_name_that_merely_contains_a_reserved_word_is_untouched():
	# "console" is not "CON". Only the whole name is a device.
	assert_eq(PrefabSystem.prefab_file_name("console"), "console.hfprefab")
	assert_eq(PrefabSystem.prefab_file_name("aux_wall"), "aux_wall.hfprefab")


func test_dots_inside_a_name_are_still_allowed():
	# `name.with.dots` saved fine before and should keep doing so; only a leading
	# dot is a problem.
	assert_eq(PrefabSystem.prefab_file_name("name.with.dots"), "name.with.dots.hfprefab")
