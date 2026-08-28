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
	while files._hflevel_thread and files._hflevel_thread.is_alive() and guard < 200:
		await get_tree().process_frame
		guard += 1
	return files.process_thread_queue()


func test_save_encodes_on_write_thread_and_round_trips():
	assert_eq(files.save_hflevel(_save_path, true), OK)
	var err: String = await _drain_write()
	assert_eq(err, "")
	assert_true(FileAccess.file_exists(_save_path))
	var loaded: Dictionary = HFLevelIO.load_from_path(_save_path)
	assert_eq(loaded.get("name"), "level")


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
