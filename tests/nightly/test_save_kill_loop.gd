extends GutTest

## Kill a real save, again and again, and check what is left on disk (#1642).
##
## `tools/save_stress.gd` saves a level in a loop, marking the start and end of
## each write. This starts it as a child process 25 times and kills it at a
## different moment each time, spread over its first second and a half of saving.
## After each kill the level file, or the copy a write keeps beside it, loads; it
## is whole and one of the saves the loop made; and the next save leaves nothing
## behind. At least 20 of the kills must land during a write, or the test would
## pass by killing an idle process.
##
## Nightly only: it takes a minute or two. `.github/workflows/nightly.yml` runs
## this folder; the suite every pull request runs does not look in it.
## `tests/test_save_interrupted.gd` stops a save at each step by hand, in every
## run.

const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")

const KILLS := 25
const DURING_A_WRITE := 20
const BRUSHES := 300
const DIR := "user://test_save_kill_loop"
## How long to wait for the child to build its level and make its first save.
const READY_SECONDS := 90.0


func after_all() -> void:
	_clear()
	DirAccess.remove_absolute(DIR)


func _clear() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))


func _markers() -> PackedStringArray:
	var text := FileAccess.get_file_as_string(DIR.path_join("markers.txt"))
	return text.strip_edges().split("\n", false)


func _start_child() -> int:
	return (
		OS
		. create_process(
			OS.get_executable_path(),
			[
				"--headless",
				"--path",
				ProjectSettings.globalize_path("res://"),
				"-s",
				"res://tools/save_stress.gd",
				"--",
				"--dir=" + DIR,
				"--brushes=%d" % BRUSHES,
				"--seconds=30",
			]
		)
	)


func _wait_until_ready(pid: int) -> bool:
	var waited := 0.0
	while waited < READY_SECONDS:
		if _markers().has("ready"):
			return true
		if not OS.is_process_running(pid):
			return false
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return false


func _kill(pid: int) -> void:
	OS.kill(pid)
	# The process lets go of its files a moment after it is told to stop.
	for _i in 50:
		if not OS.is_process_running(pid):
			break
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.1).timeout


func test_a_save_killed_at_any_moment_leaves_a_level_that_loads():
	var during_a_write := 0
	for kill in KILLS:
		_clear()
		DirAccess.make_dir_recursive_absolute(DIR)
		var pid := _start_child()
		assert_gt(pid, 0, "the stress loop starts")
		if pid <= 0:
			return
		var ready: bool = await _wait_until_ready(pid)
		assert_true(ready, "kill %d: the stress loop made its first save" % kill)
		if not ready:
			await _kill(pid)
			return
		await get_tree().create_timer(0.05 + 1.5 * float(kill) / float(KILLS)).timeout
		await _kill(pid)

		var markers := _markers()
		var last := markers[markers.size() - 1]
		if last.begins_with("begin "):
			during_a_write += 1
		var begun := 0
		for line in markers:
			if line.begins_with("begin "):
				begun = line.split(" ")[1].to_int()
		var note := "kill %d, after %s" % [kill, last]

		var path := DIR.path_join("level.hflevel")
		var data := HFLevelIO.load_from_path(path)
		assert_false(data.is_empty(), "%s: the level loads" % note)
		var number := str(data.get("save_number", ""))
		assert_true(number.is_valid_int(), "%s: it is one of the loop's saves" % note)
		assert_between(number.to_int(), 0, begun, "%s: one the loop began" % note)
		var decoded: Dictionary = HFLevelIO.decode_variant(data)
		var brushes: Array = decoded.get("state", {}).get("brushes", [])
		assert_eq(brushes.size(), BRUSHES, "%s: whole" % note)

		var again := HFLevelIO.build_payload({"state": {"brushes": []}}, true)
		assert_eq(HFLevelIO.write_bytes_atomic(path, again), OK, "%s: the next save" % note)
		var left := PackedStringArray(DirAccess.get_files_at(DIR))
		left.sort()
		assert_eq(left, PackedStringArray(["level.hflevel", "markers.txt"]), "%s: no stray" % note)
	assert_gte(during_a_write, DURING_A_WRITE, "kills that landed during a write")
	gut.p("%d of %d kills landed during a write" % [during_a_write, KILLS])
