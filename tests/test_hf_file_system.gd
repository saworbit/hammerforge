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

signal hflevel_save_failed(path: String, error_message: String)
signal autosave_failed(error_message: String)
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


# ===========================================================================
# Save queue ordering (#51)
# ===========================================================================


func _third_save_path() -> String:
	return "user://hf_encode_thread_test_third.hflevel"


func _big_capture(tag: String) -> Dictionary:
	# Big enough that the write thread is still running when the next save
	# arrives, which is what puts a job in the pending queue.
	var filler: Array = []
	for i in range(60000):
		filler.append(i)
	return {"name": tag, "filler": filler}


func _queue_a_save_behind_a_running_one() -> void:
	root.captured = _big_capture("A")
	assert_eq(files.save_hflevel(_save_path, true), OK)
	root.captured = {"name": "B"}
	assert_eq(files.save_hflevel(_second_save_path(), true), OK)
	assert_eq(files._hflevel_pending.size(), 1, "B has to be queued behind a running A")
	while files._hflevel_thread and files._hflevel_thread.is_alive():
		await get_tree().process_frame


func test_a_finished_worker_does_not_let_a_new_save_jump_the_queue():
	# A has finished but has not been collected, B is queued behind it, and C
	# arrives now. B and C share a path, so whichever runs last owns the file.
	await _queue_a_save_behind_a_running_one()
	root.captured = {"name": "C"}
	assert_eq(files.save_hflevel(_second_save_path(), true), OK)
	await _drain_write()

	var order: Array = []
	for entry in files.take_completed_saves():
		order.append(str(entry.get("path", "")))
	assert_eq(
		order,
		[_save_path, _second_save_path(), _second_save_path()],
		"Completion has to follow the order the saves were asked for"
	)
	var loaded: Dictionary = HFLevelIO.load_from_path(_second_save_path())
	assert_eq(str(loaded.get("name", "")), "C", "The newest save owns the file")


func test_three_distinct_paths_complete_in_order():
	await _queue_a_save_behind_a_running_one()
	root.captured = {"name": "C"}
	assert_eq(files.save_hflevel(_third_save_path(), true), OK)
	await _drain_write()

	var order: Array = []
	for entry in files.take_completed_saves():
		order.append(str(entry.get("path", "")))
	assert_eq(order, [_save_path, _second_save_path(), _third_save_path()])
	assert_eq(str(HFLevelIO.load_from_path(_second_save_path()).get("name", "")), "B")
	assert_eq(str(HFLevelIO.load_from_path(_third_save_path()).get("name", "")), "C")
	DirAccess.remove_absolute(_third_save_path())


func test_a_discarded_pending_job_does_not_stall_the_queue():
	assert_eq(files.save_hflevel(_save_path, true), OK)
	while files._hflevel_thread and files._hflevel_thread.is_alive():
		await get_tree().process_frame
	files._hflevel_pending.append({"path": "", "encoded": {}})
	root.captured = {"name": "after"}
	assert_eq(files.save_hflevel(_second_save_path(), true), OK)
	await _drain_write()
	assert_true(
		FileAccess.file_exists(_second_save_path()),
		"A junk entry must not strand the writes behind it"
	)


# ===========================================================================
# Region sidecar failures block the level save (#173)
# ===========================================================================


func _paint_shim(ok: bool) -> Node:
	var s := GDScript.new()
	s.source_code = (
		"""
extends Node

var base_paths: Array = []
var save_calls: int = 0

func set_region_base_path(path: String) -> void:
	base_paths.append(path)

func save_loaded_regions() -> Dictionary:
	save_calls += 1
	return {"ok": %s, "failed": [], "error": "sidecar directory is not writable"}
"""
		% ("true" if ok else "false")
	)
	s.reload()
	var node := Node.new()
	node.set_script(s)
	add_child_autoqfree(node)
	return node


func test_region_write_failure_blocks_the_level_save():
	root.paint_system = _paint_shim(false)
	var failures: Array = []
	root.hflevel_save_failed.connect(func(p, m): failures.append([p, m]))
	assert_ne(files.save_hflevel(_save_path, true), OK)
	assert_push_error("sidecar directory is not writable")
	assert_eq(failures.size(), 1, "The dock has to hear that the save failed")
	assert_eq(str(failures[0][0]), _save_path)
	assert_false(
		FileAccess.file_exists(_save_path), "No level file may claim region data that is missing"
	)


func test_region_write_failure_on_autosave_reports_as_an_autosave():
	root.paint_system = _paint_shim(false)
	var manual: Array = []
	var auto: Array = []
	root.hflevel_save_failed.connect(func(_p, _m): manual.append(true))
	root.autosave_failed.connect(func(m): auto.append(m))
	assert_ne(files.save_hflevel(_save_path, true, true), OK)
	assert_push_error("sidecar directory is not writable")
	assert_eq(auto.size(), 1, "An autosave failure is not a manual save failure")
	assert_eq(manual.size(), 0)


func test_region_write_success_lets_the_level_save_proceed():
	root.paint_system = _paint_shim(true)
	assert_eq(files.save_hflevel(_save_path, true), OK)
	await _drain_write()
	assert_true(FileAccess.file_exists(_save_path))
	assert_eq(root.paint_system.save_calls, 1)


# ===========================================================================
# Malformed .map import (#174)
# ===========================================================================


func _import_root() -> Node3D:
	var s := GDScript.new()
	s.source_code = """
extends Node3D

var cleared: int = 0
var created: Array = []

signal user_message(text: String, level: int)

func clear_brushes() -> void:
	cleared += 1

func _clear_entities() -> void:
	cleared += 1

func create_brush_from_info(info: Dictionary) -> Node:
	created.append(info)
	return null

func _create_entity_from_map(_info: Dictionary) -> Node:
	return null
"""
	s.reload()
	var node := Node3D.new()
	node.set_script(s)
	add_child_autoqfree(node)
	return node


func _write_map(path: String, text: String) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f = null
	return path


func _good_map_text() -> String:
	return (
		"{\n"
		+ '"classname" "worldspawn"'
		+ "\n{\n"
		+ "( 0 0 0 ) ( 10 0 0 ) ( 0 10 0 ) brick 0 0 0 1 1\n"
		+ "( 0 0 0 ) ( 0 10 0 ) ( 0 0 10 ) brick 0 0 0 1 1\n"
		+ "( 0 0 0 ) ( 0 0 10 ) ( 10 0 0 ) brick 0 0 0 1 1\n"
		+ "( 10 0 0 ) ( 0 0 10 ) ( 0 10 0 ) brick 0 0 0 1 1\n"
		+ "}\n}\n"
	)


func test_malformed_map_import_is_refused_and_leaves_the_level_alone():
	var import_root := _import_root()
	var fs := HFFileSystemType.new(import_root)
	var path := _write_map("user://hf_broken_import_test.map", "not a map")
	assert_eq(fs.import_map(path), ERR_INVALID_DATA)
	assert_push_error("Map import failed")
	assert_eq(import_root.cleared, 0, "A rejected import must not clear the level")
	assert_eq(import_root.created.size(), 0)
	DirAccess.remove_absolute(path)


func test_unbalanced_map_import_is_refused():
	var import_root := _import_root()
	var fs := HFFileSystemType.new(import_root)
	var text := "{\n" + '"classname" "worldspawn"' + "\n{\n"
	var path := _write_map("user://hf_unbalanced_import_test.map", text)
	assert_eq(fs.import_map(path), ERR_INVALID_DATA)
	assert_push_error("Map import failed")
	assert_eq(import_root.cleared, 0)
	DirAccess.remove_absolute(path)


func test_well_formed_map_import_still_replaces_the_level():
	var import_root := _import_root()
	var fs := HFFileSystemType.new(import_root)
	var path := _write_map("user://hf_good_import_test.map", _good_map_text())
	assert_eq(fs.import_map(path), OK)
	assert_eq(import_root.cleared, 2, "A good import clears brushes and entities")
	assert_eq(import_root.created.size(), 1)
	DirAccess.remove_absolute(path)


func test_validate_map_reports_the_first_problem():
	var fs := HFFileSystemType.new(_import_root())
	var path := _write_map("user://hf_validate_import_test.map", "not a map")
	var result: Dictionary = fs.validate_map(path)
	assert_false(bool(result.get("ok", true)))
	assert_ne(str(result.get("error", "")), "", "The dock needs something to show the user")
	DirAccess.remove_absolute(path)


func test_validate_map_passes_a_good_file():
	var fs := HFFileSystemType.new(_import_root())
	var path := _write_map("user://hf_validate_good_test.map", _good_map_text())
	assert_true(bool(fs.validate_map(path).get("ok", false)))
	DirAccess.remove_absolute(path)


func test_validate_map_rejects_a_missing_file():
	var fs := HFFileSystemType.new(_import_root())
	assert_false(bool(fs.validate_map("user://hf_does_not_exist.map").get("ok", true)))
