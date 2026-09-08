extends GutTest

## The suite is only as honest as the files it can actually load.
##
## GUT collects `test_*.gd` from `tests/`, and a script that fails to parse is
## skipped with a warning rather than failing. The counts stay plausible — a
## slightly smaller number that nobody notices — and the coverage is simply gone.
##
## That is not hypothetical. Two transform test files, 121 tests between them,
## sat dark for two waves because a helper they called
## (`HFBrushSystem._check_axis_aligned_box()`) was deleted when hollow stopped
## needing it, and nothing said so. This is the check that would have said so.

const TESTS_DIR := "res://tests/"


func _test_scripts() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			out.append(TESTS_DIR + file_name)
	return out


func test_there_are_test_scripts_to_check():
	assert_gt(_test_scripts().size(), 100, "the collector found nothing, which cannot be right")


func test_every_test_script_loads_and_extends_gut_test():
	# A script that cannot be loaded is a script that is not being run.
	var broken: Array = []
	for path in _test_scripts():
		var script = load(path)
		if script == null:
			broken.append("%s (does not parse)" % path)
			continue
		var base = script
		var found := false
		while base != null:
			if str(base.get_global_name()) == "GutTest":
				found = true
				break
			base = base.get_base_script()
		if not found:
			broken.append("%s (does not extend GutTest)" % path)
	assert_eq(broken, [], "these files are silently not being run")


func test_the_helper_scripts_beside_the_tests_are_not_collected_by_accident():
	# Shared helpers live in `tests/` too. They must not begin with the collector
	# prefix, or GUT will try to run them as tests and report them as empty.
	var dir := DirAccess.open(TESTS_DIR)
	assert_not_null(dir)
	for file_name in dir.get_files():
		if not file_name.ends_with(".gd") or file_name.begins_with("test_"):
			continue
		var script = load(TESTS_DIR + file_name)
		assert_not_null(script, "%s does not parse" % file_name)
