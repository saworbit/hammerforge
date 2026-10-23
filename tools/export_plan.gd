extends SceneTree
## Write a top down plan of a level as an .svg and a .png, with no editor open,
## for CI or a design document (#1705). The same plan the dock's Export Plan
## writes and `hf_plan` answers, from `HFLevelPlan`.
##
## Usage:
##   godot --headless -s res://tools/export_plan.gd --path . -- level.hflevel plans/ground
##   godot --headless -s res://tools/export_plan.gd --path . -- level.hflevel plans/upper --y-min=3 --y-max=6 --size=2048 --labels
##
## The second path is the name without an extension: `plans/ground.svg` and
## `plans/ground.png` are written.

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFLevelPlan = preload("res://addons/hammerforge/hf_level_plan.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var paths: Array = []
	var y_min := -INF
	var y_max := INF
	var size := 1024
	var labels := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--y-min="):
			y_min = float(arg.trim_prefix("--y-min="))
		elif arg.begins_with("--y-max="):
			y_max = float(arg.trim_prefix("--y-max="))
		elif arg.begins_with("--size="):
			size = clampi(int(arg.trim_prefix("--size=")), 64, 4096)
		elif arg == "--labels":
			labels = true
		else:
			paths.append(arg)
	if paths.size() != 2:
		printerr("export_plan: give a .hflevel and the name to write the plan under")
		quit(2)
		return
	await process_frame
	var level: Node3D = LevelRootScript.new()
	level.name = "PlanLevel"
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	get_root().add_child(level)
	await process_frame
	var err := OK
	if not level.load_hflevel(str(paths[0])):
		err = ERR_FILE_CANT_READ
	else:
		err = HFLevelPlan.write_files(level, str(paths[1]), y_min, y_max, size, labels)
	if err != OK:
		printerr("export_plan: %s" % error_string(err))
	quit(0 if err == OK else 1)
