extends GutTest

## A save stopped at any step of `HFLevelIO.write_bytes_atomic()` leaves a file
## that loads, and nothing the next save trips over (#1642).
##
## The write puts the new level in `<path>.writing`, copies the old file to
## `<path>.previous`, removes the old file, renames `.writing` to the name and
## removes `.previous`. Each case here leaves the files as a stop after one step
## of that does, then loads. A stop after the old file is gone and before the new
## one has its name loads the new one: it was written whole before the old one
## was copied aside. `tests/nightly/test_save_kill_loop.gd` kills a real save.

const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")

const DIR := "user://test_save_interrupted"

var path := DIR.path_join("level.hflevel")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_clear()


func after_each() -> void:
	_clear()
	DirAccess.remove_absolute(DIR)


func _clear() -> void:
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))


func _payload(tag: String, compress: bool) -> PackedByteArray:
	return HFLevelIO.build_payload({"tag": tag, "state": {"brushes": []}}, compress)


func _write(file_path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _left() -> PackedStringArray:
	var names := PackedStringArray(DirAccess.get_files_at(DIR))
	names.sort()
	return names


## The files a save of B over A leaves when it stops after `step` steps.
func _stop_after(step: int, compress: bool) -> void:
	var old := _payload("A", compress)
	var fresh := _payload("B", compress)
	_write(path, old)
	match step:
		0:
			_write(path + ".writing", fresh.slice(0, floori(fresh.size() / 2.0)))
		1:
			_write(path + ".writing", fresh)
		2:
			_write(path + ".writing", fresh)
			_write(path + ".previous", old.slice(0, floori(old.size() / 2.0)))
		3:
			_write(path + ".writing", fresh)
			_write(path + ".previous", old)
		4:
			_write(path + ".writing", fresh)
			_write(path + ".previous", old)
			DirAccess.remove_absolute(path)
		5:
			_write(path, fresh)
			_write(path + ".previous", old)
		6:
			_write(path, fresh)


const LOADS := {0: "A", 1: "A", 2: "A", 3: "A", 4: "B", 5: "B", 6: "B"}


func test_a_save_stopped_at_any_step_loads_and_the_next_save_is_clean():
	for compress in [true, false]:
		for step in LOADS:
			_clear()
			_stop_after(step, compress)
			var loaded := HFLevelIO.load_from_path(path)
			var note := "stopped after step %d, %s" % [step, "compressed" if compress else "plain"]
			assert_eq(loaded.get("tag"), LOADS[step], note)
			assert_eq(HFLevelIO.write_bytes_atomic(path, _payload("C", compress)), OK, note)
			assert_eq(_left(), PackedStringArray(["level.hflevel"]), "%s: nothing left over" % note)
			assert_eq(HFLevelIO.load_from_path(path).get("tag"), "C", note)


## The window #1642 asked to decide: the old file gone, the new one whole under
## `.writing`. The new one is loaded and takes the name; the old copy goes.
func test_a_stop_between_removing_the_old_file_and_naming_the_new_keeps_the_new():
	_stop_after(4, true)
	assert_eq(HFLevelIO.load_from_path(path).get("tag"), "B")
	assert_eq(_left(), PackedStringArray(["level.hflevel"]))


## A `.writing` that is not a level, beside a `.previous` with no file, is not
## put back: the older save is.
func test_a_damaged_writing_file_falls_back_to_the_previous_one():
	_write(path + ".previous", _payload("A", true))
	_write(path + ".writing", "not a level".to_utf8_buffer())
	assert_eq(HFLevelIO.load_from_path(path).get("tag"), "A")
