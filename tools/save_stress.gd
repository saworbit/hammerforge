extends SceneTree
## Saves a level over and over, for `tests/nightly/test_save_kill_loop.gd` to
## kill partway through a save (#1642).
##
## It builds a level of box brushes, saves it once, writes `ready` to
## `<dir>/markers.txt`, then saves again and again until `--seconds` have gone.
## Each save writes `begin N` to the markers before the write and `end N` after
## it, each flushed, so whoever kills the process can tell whether it stopped
## during a write.
##
## Each save is the real write, `HFLevelIO.write_bytes_atomic()`, of the level's
## own bytes with its save number in them. The number is patched into the bytes
## rather than the level encoded again, so the loop spends its time in the write,
## which is what the kills are aimed at.
##
## Usage:
##   godot --headless -s res://tools/save_stress.gd --path . -- --dir=user://stress
##   godot --headless -s res://tools/save_stress.gd --path . -- --dir=user://stress --brushes=300 --seconds=20

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")

const FILE_NAME := "level.hflevel"
const MARKERS := "markers.txt"
## Where the save number goes in the file: a fixed width string, so a number
## patched in never moves a byte after it.
const NUMBER_KEY := "save_number"
const NUMBER_WIDTH := 6

var _dir := ""
var _brushes := 300
var _seconds := 20.0


func _init() -> void:
	_run()


func _run() -> void:
	if not _parse_args(OS.get_cmdline_user_args()):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_dir)
	var level: Node3D = LevelRootScript.new()
	level.name = "StressLevel"
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	get_root().add_child(level)
	await process_frame
	var infos: Array = []
	var side := ceili(sqrt(float(_brushes)))
	for i in range(_brushes):
		infos.append(
			{
				"size": Vector3.ONE * 2.0,
				"center": Vector3(i % side, 0.5, floori(float(i) / side)) * 4.0
			}
		)
	level.create_brushes_from_infos(infos)
	await process_frame

	var data: Dictionary = level.state_system.capture_hflevel_state()
	data[NUMBER_KEY] = "0".repeat(NUMBER_WIDTH)
	var text := HFLevelIO.stringify_level_json(data, false)
	var payload := HFLevelIO.build_payload_from_json(text, false)
	var pattern := '"%s": "%s"' % [NUMBER_KEY, "0".repeat(NUMBER_WIDTH)]
	var found := text.find(pattern)
	# The offset is counted in characters, which are bytes only in ASCII.
	if found < 0 or text.to_utf8_buffer().size() != text.length():
		printerr("save_stress: cannot find where the save number goes")
		quit(1)
		return
	var at := payload.size() - text.length() + found + pattern.length() - NUMBER_WIDTH - 1

	var path := _dir.path_join(FILE_NAME)
	var markers := FileAccess.open(_dir.path_join(MARKERS), FileAccess.WRITE)
	if HFLevelIO.write_bytes_atomic(path, payload) != OK:
		printerr("save_stress: the first save failed")
		quit(1)
		return
	markers.store_line("ready")
	markers.flush()
	var number := 1
	var stop_at := Time.get_ticks_msec() + int(_seconds * 1000.0)
	while Time.get_ticks_msec() < stop_at:
		var digits := str(number).pad_zeros(NUMBER_WIDTH)
		for i in NUMBER_WIDTH:
			payload[at + i] = digits.unicode_at(i)
		markers.store_line("begin %d" % number)
		markers.flush()
		var err := HFLevelIO.write_bytes_atomic(path, payload)
		markers.store_line("end %d %d" % [number, err])
		markers.flush()
		number += 1
	markers.close()
	quit()


func _parse_args(args: PackedStringArray) -> bool:
	for arg in args:
		if arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
		elif arg.begins_with("--brushes="):
			_brushes = maxi(1, int(arg.trim_prefix("--brushes=")))
		elif arg.begins_with("--seconds="):
			_seconds = maxf(0.1, float(arg.trim_prefix("--seconds=")))
		else:
			printerr("Unknown argument '%s'. Takes --dir=, --brushes= and --seconds=." % arg)
			return false
	if _dir.is_empty():
		printerr("--dir= is needed: the folder the level and the markers go in")
		return false
	return true
