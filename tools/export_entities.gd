extends SceneTree
## Write a level's entities to a CSV with no editor open, for a CI job or a build
## script (#1709). The same table the Console's Export Entities writes, from
## `HFEntityCensus`: one row per entity, point and brush entities both, one column
## per property.
##
## Usage:
##   godot --headless -s res://tools/export_entities.gd --path . -- level.hflevel out.csv
##   godot --headless -s res://tools/export_entities.gd --path . -- level.hflevel out.csv --scope=cordons
##
## `--scope=` takes `cordons` or `visgroup:<name>`, as the Console's Count in
## does. The paths may be `res://`, `user://` or on disk.

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFEntityCensus = preload("res://addons/hammerforge/hf_entity_census.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var paths: Array = []
	var scope := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scope="):
			scope = arg.trim_prefix("--scope=")
		else:
			paths.append(arg)
	if paths.size() != 2:
		printerr("export_entities: give a .hflevel and the CSV to write")
		quit(2)
		return
	await process_frame
	var err := await export_level(str(paths[0]), str(paths[1]), scope, get_root())
	if err != OK:
		printerr("export_entities: %s" % error_string(err))
	quit(0 if err == OK else 1)


## Load `level_path` into a level of its own under `parent`, write its entities
## to `csv_path`, and take the level away again. OK, or what went wrong.
static func export_level(level_path: String, csv_path: String, scope: String, parent: Node) -> int:
	var level: Node3D = LevelRootScript.new()
	level.name = "ExportLevel"
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	parent.add_child(level)
	await parent.get_tree().process_frame
	var err := OK
	if not level.load_hflevel(level_path):
		err = ERR_FILE_CANT_READ
	else:
		err = HFEntityCensus.write_csv(level, csv_path, scope)
	parent.remove_child(level)
	level.free()
	return err
