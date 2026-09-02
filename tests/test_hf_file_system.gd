extends GutTest

const HFFileSystemType = preload("res://addons/hammerforge/systems/hf_file_system.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")

var root: Node3D
var files: HFFileSystem
var _save_path := "user://hf_encode_thread_test.hflevel"


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	files = HFFileSystemType.new(root)


func after_each():
	if files:
		files.shutdown()
	if FileAccess.file_exists(_save_path):
		DirAccess.remove_absolute(_save_path)
	if FileAccess.file_exists(_second_save_path()):
		DirAccess.remove_absolute(_second_save_path())
	files = null
	root = null


func _root_shim_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = """
extends Node3D
var hflevel_autosave_path: String = "user://hf_encode_thread_test.hflevel"
var hflevel_compress: bool = false
var hflevel_autosave_keep: int = 0
var paint_system = null
var captured: Dictionary = {"name": "level", "n": 1}
func _capture_hflevel_state() -> Dictionary:
	return captured
"""
	s.reload()
	return s


func _drain_write() -> String:
	var guard := 0
	var last_error := ""
	while guard < 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			guard += 1
			continue
		last_error = files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return last_error
	return last_error


func _second_save_path() -> String:
	return "user://hf_encode_thread_test_second.hflevel"


func test_save_encodes_on_write_thread_and_round_trips():
	assert_eq(files.save_hflevel(_save_path, true), OK)
	var err: String = await _drain_write()
	assert_eq(err, "")
	assert_true(FileAccess.file_exists(_save_path))
	var loaded: Dictionary = HFLevelIO.load_from_path(_save_path)
	assert_eq(loaded.get("name"), "level")
	var completed := files.take_completed_saves()
	assert_eq(completed.size(), 1)
	assert_eq(completed[0].get("path"), _save_path)
	assert_false(bool(completed[0].get("autosave", true)))


func test_autosave_completion_keeps_its_kind():
	assert_eq(files.save_hflevel(_save_path, true, true), OK)
	await _drain_write()
	var completed := files.take_completed_saves()
	assert_eq(completed.size(), 1)
	assert_true(bool(completed[0].get("autosave", false)))


func test_queued_manual_saves_each_report_their_destination():
	assert_eq(files.save_hflevel(_save_path, true), OK)
	root.captured = {"name": "second"}
	assert_eq(files.save_hflevel(_second_save_path(), true), OK)
	await _drain_write()
	var completed := files.take_completed_saves()
	assert_eq(completed.size(), 2)
	assert_eq(completed[0].get("path"), _save_path)
	assert_eq(completed[1].get("path"), _second_save_path())
	assert_true(FileAccess.file_exists(_save_path))
	assert_true(FileAccess.file_exists(_second_save_path()))


func test_unchanged_save_skips_rewrite_after_hash_settles():
	assert_eq(files.save_hflevel(_save_path, true), OK)
	await _drain_write()
	assert_false(files.last_encode_skipped)
	assert_eq(files.save_hflevel(_save_path, false), OK)
	await _drain_write()
	assert_true(files.last_encode_skipped, "Identical capture should skip the disk write")


func test_changed_save_rewrites_file():
	assert_eq(files.save_hflevel(_save_path, true), OK)
	await _drain_write()
	root.captured = {"name": "level", "n": 2}
	assert_eq(files.save_hflevel(_save_path, false), OK)
	await _drain_write()
	var loaded: Dictionary = HFLevelIO.load_from_path(_save_path)
	assert_eq(int(loaded.get("n", 0)), 2)
