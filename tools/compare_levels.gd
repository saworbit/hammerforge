extends SceneTree
## Print what changed between two `.hflevel` files, one change a line, as the
## Console's Compare tab lists it (#1701). For a CI job or a pull request comment.
##
## Usage:
##   godot --headless -s res://tools/compare_levels.gd --path . -- old.hflevel new.hflevel
##   git show HEAD~3:level.hflevel > old.hflevel
##
## Exits 0 when nothing changed, 1 when something did, and 2 when a file does not
## read, as `diff` does.

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFLevelCompare = preload("res://addons/hammerforge/hf_level_compare.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var paths := OS.get_cmdline_user_args()
	if paths.size() != 2:
		printerr("compare_levels: give the older .hflevel and the newer one")
		quit(2)
		return
	await process_frame
	# A level to read the files with: `read_hflevel()` checks and decodes a file
	# and applies nothing.
	var level: Node3D = LevelRootScript.new()
	level.name = "CompareLevel"
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	get_root().add_child(level)
	await process_frame
	var sides: Array = []
	for path in paths:
		var read: Dictionary = level.file_system.read_hflevel(str(path))
		if not bool(read.get("ok", false)):
			printerr("compare_levels: %s" % read.get("error", "could not read %s" % path))
			quit(2)
			return
		sides.append(read["bundle"])
	var result := HFLevelCompare.compare(sides[0], sides[1])
	for line in result["lines"]:
		print(line)
	var changed: bool = (result["counts"] as Dictionary).values().any(func(n): return int(n) > 0)
	quit(1 if changed else 0)
