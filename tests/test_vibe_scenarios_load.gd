extends GutTest

## Every script in the vibe harness still loads against the plugin as it is (#955).
##
## Nothing else loads them. gdformat and gdlint read them as text, and the
## warnings check loads addons/hammerforge only. #938 renamed a function that
## `entity_props.gd` called, CI stayed green, and the next sweep graded all 137
## scenarios `script error`. Only a sweep run by hand showed it.

const VIBE_DIR := "res://tools/vibe"


func _scripts_under(dir: String, out: Array) -> void:
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(".gd"):
			out.append(dir.path_join(file_name))
	for sub in DirAccess.get_directories_at(dir):
		_scripts_under(dir.path_join(sub), out)


func test_every_vibe_script_loads():
	var paths: Array = []
	_scripts_under(VIBE_DIR, paths)
	assert_gt(paths.size(), 100, "the scenarios are where this test looks for them")
	var broken: Array = []
	for path in paths:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			broken.append(path)
	assert_eq(broken, [], "These no longer load. Run one to see why.")
