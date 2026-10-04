extends GutTest

## Every script in the vibe harness still loads against the plugin as it is (#955).
##
## Nothing else loads them. gdformat and gdlint read them as text, and the
## warnings check loads addons/hammerforge only. #938 renamed a function that
## `entity_props.gd` called, CI stayed green, and the next sweep graded all 137
## scenarios `script error`. Only a sweep run by hand showed it.
##
## Loading only checks what the parser can see. A scenario's root is typed
## `Node3D` and most of the level's systems are untyped, so a call such as
## `root.vertex_system.validate_convexity(b)` is looked up at run time. The second
## test reads those calls from the source and asks a real level for each name
## (#958). Calls through any other local are still left to the sweep.

const VIBE_DIR := "res://tools/vibe"

## `root.method(` and `root.member.method(`, across gdformat's line breaks.
const ROOT_CALL := "\\broot\\d*\\s*\\.\\s*(\\w+)\\s*(?:\\.\\s*(\\w+)\\s*)?\\("


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


## Calls in `text` that `level` cannot answer, as "path:line root.name()" strings.
func _missing_calls(path: String, text: String, level: Node) -> Array:
	var missing: Array = []
	for found in RegEx.create_from_string(ROOT_CALL).search_all(text):
		var member := found.get_string(1)
		var method := found.get_string(2)
		var where := "%s:%d" % [path, text.substr(0, found.get_start()).count("\n") + 1]
		if method == "":
			if not level.has_method(member):
				missing.append("%s root.%s()" % [where, member])
		elif member not in level:
			missing.append("%s root.%s, which the level does not have" % [where, member])
		elif level.get(member) is Object and not level.get(member).has_method(method):
			missing.append("%s root.%s.%s()" % [where, member, method])
	return missing


func test_every_level_call_in_the_vibe_scripts_names_something_the_level_has():
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	var paths: Array = []
	_scripts_under(VIBE_DIR, paths)
	var missing: Array = []
	for path in paths:
		missing.append_array(_missing_calls(path, FileAccess.get_file_as_string(path), level))
	assert_eq(missing, [], "The level has no such method (#958):\n" + "\n".join(missing))
