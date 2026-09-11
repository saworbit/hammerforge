extends GutTest

## Three places where a name was tested against "" rather than stripped, so a
## whitespace-only name got in and two names a keystroke apart were two things
## (#374, #380, #381). #349 fixed the visgroup half and left a comment saying
## exactly what was wrong with the guard; these are the same guard elsewhere.
## #380 is the other half of the same file: a typed local assigned straight from
## parsed JSON.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFEntityDefType = preload("res://addons/hammerforge/hf_entity_def.gd")

var root: LevelRoot
var _written_paths: Array[String] = []


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	for path in _written_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_written_paths.clear()


func _write_definitions(name_hint: String, text: String) -> String:
	var path := "user://vibe_defs_%s.json" % name_hint
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	_written_paths.append(path)
	return path


func _box(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info({"size": Vector3(32, 32, 32), "brush_id": brush_id})
		as DraftBrush
	)


# ===========================================================================
# create_group (#374)
# ===========================================================================


func test_a_group_cannot_be_named_with_whitespace():
	for blank in ["", "   ", "\t", "\n"]:
		root.visgroup_system.create_group(blank)
	assert_eq(root.visgroup_system.get_group_names().size(), 0, "no blank rows")


func test_two_names_a_keystroke_apart_are_one_group():
	for name in ["lights", "lights ", " lights"]:
		root.visgroup_system.create_group(name)
	var names: PackedStringArray = root.visgroup_system.get_group_names()
	assert_eq(names.size(), 1, "one group, not three: %s" % [names])
	assert_eq(names[0], "lights", "stored stripped")


func test_grouping_a_selection_writes_the_stripped_name():
	var brush := _box("b")
	root.visgroup_system.group_selection("Arch ", [brush])
	assert_eq(str(brush.get_meta("group_id", "")), "Arch", "the meta is the stripped name")
	assert_eq(root.visgroup_system.get_group_names()[0], "Arch")
	assert_eq(
		root.visgroup_system.get_group_members("Arch").size(), 1, "the registry and the meta agree"
	)


func test_grouping_a_selection_with_a_blank_name_groups_nothing():
	var brush := _box("b")
	root.visgroup_system.group_selection("   ", [brush])
	assert_eq(str(brush.get_meta("group_id", "")), "", "nothing was written")
	assert_eq(root.visgroup_system.get_group_names().size(), 0)


# ===========================================================================
# entities.json with an "entities" key of the wrong type (#380)
# ===========================================================================


func test_an_entities_key_that_is_not_a_list_falls_back_to_the_built_ins():
	for text in ['{"entities": "nope"}', '{"entities": 7}', '{"entities": {"a": 1}}']:
		var path := _write_definitions("badkey", text)
		var defs = HFEntityDefType.load_definitions(path)
		assert_gt(defs.size(), 0, "the built-in fallback ran for %s" % text)


func test_the_cases_that_already_recovered_still_recover():
	# "not json at all" is left out on purpose: it push_error()s by design, which
	# is correct and which GUT counts as an unexpected error.
	for text in ["7", '{"entities": [null, "x"]}', '{"entities": []}']:
		var path := _write_definitions("recover", text)
		assert_gt(HFEntityDefType.load_definitions(path).size(), 0, "built-ins for %s" % text)


func test_a_level_keeps_its_entity_definitions_when_the_file_is_wrong():
	var path := _write_definitions("level", '{"entities": "nope"}')
	root.entity_definitions_path = path
	root.entity_system.load_entity_definitions()
	assert_gt(root.entity_definitions.size(), 0, "the class dropdown is not empty")


func test_an_ordinary_definitions_file_still_loads():
	var path := _write_definitions(
		"ok", '{"entities": [{"id": "func_door", "description": "a door"}]}'
	)
	var defs = HFEntityDefType.load_definitions(path)
	assert_eq(defs.size(), 1)
	assert_eq(defs[0].classname, "func_door")


# ===========================================================================
# Whitespace classnames (#381)
# ===========================================================================


func test_a_whitespace_classname_is_not_an_entity_class():
	var path := _write_definitions("blank", '{"entities": [{"id": "   ", "description": "x"}]}')
	var defs = HFEntityDefType.load_definitions(path)
	for def in defs:
		assert_ne(def.classname, "   ", "a blank classname did not become a class")
		assert_eq(def.classname, def.classname.strip_edges(), "every classname is stripped")


func test_a_classname_with_an_edge_space_is_stored_stripped():
	var path := _write_definitions(
		"space", '{"entities": [{"id": " func_door ", "description": "x"}]}'
	)
	var defs = HFEntityDefType.load_definitions(path)
	assert_eq(defs.size(), 1)
	assert_eq(defs[0].classname, "func_door", "so the overlay and the base agree")


func test_a_whitespace_classname_never_reaches_the_level():
	var path := _write_definitions("blank2", '{"entities": [{"id": "  ", "description": "x"}]}')
	root.entity_definitions_path = path
	root.entity_system.load_entity_definitions()
	for key in root.entity_definitions.keys():
		assert_ne(str(key).strip_edges(), "", "no blank row in the class dropdown")
