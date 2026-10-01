extends SceneTree

## Load every script under the given directories and fail if any does not load.
##
## Run it through tools/check_script_warnings.py, which writes the override.cfg
## that turns addons/ warnings on and raises them to errors, then removes it.
## Godot reads warning levels once at startup, so changing them from in here
## would do nothing (#836).
##
## Directories come after `--` on the command line, as res:// paths. With none,
## it checks the plugin.

const WARNINGS_PREFIX := "debug/gdscript/warnings/"
const DEFAULT_DIRS: Array[String] = ["res://addons/hammerforge"]


func _init() -> void:
	var problems := _settings_problems()
	var dirs: Array[String] = []
	dirs.assign(OS.get_cmdline_user_args())
	if dirs.is_empty():
		dirs = DEFAULT_DIRS
	var paths: Array[String] = []
	for dir in dirs:
		_collect_scripts(dir, paths)
	if paths.is_empty():
		problems.append("No scripts found under %s." % ", ".join(dirs))
	var failed: Array[String] = []
	if problems.is_empty():
		for path in paths:
			var script := (
				ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
			)
			if script == null or not script.can_instantiate():
				failed.append(path)
	for problem in problems:
		printerr("warnings: " + problem)
	for path in failed:
		printerr("warnings: does not load with warnings as errors: %s" % path)
	print("warnings: %d scripts checked, %d did not load." % [paths.size(), failed.size()])
	quit(0 if problems.is_empty() and failed.is_empty() else 1)


## A warning still at 1 would print and let the script load, so the check would
## pass on exactly what it exists to catch. That is what a missing override, or
## a warning a newer Godot added, looks like from in here.
func _settings_problems() -> Array[String]:
	var out: Array[String] = []
	var rules: Variant = ProjectSettings.get_setting(WARNINGS_PREFIX + "directory_rules", {})
	if not (rules is Dictionary) or int((rules as Dictionary).get("res://addons", 0)) != 1:
		out.append("res://addons is not opted in to warnings. Is override.cfg missing?")
	for prop in ProjectSettings.get_property_list():
		var setting := str(prop.get("name", ""))
		if not setting.begins_with(WARNINGS_PREFIX):
			continue
		var value: Variant = ProjectSettings.get_setting(setting)
		if typeof(value) == TYPE_INT and int(value) == 1:
			out.append(
				(
					"%s is a warning, not an error. Add it to WARNINGS in check_script_warnings.py."
					% setting.trim_prefix(WARNINGS_PREFIX)
				)
			)
	return out


func _collect_scripts(dir: String, out: Array[String]) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for file in access.get_files():
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	for sub in access.get_directories():
		_collect_scripts(dir.path_join(sub), out)
