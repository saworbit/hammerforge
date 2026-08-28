@tool
extends RefCounted
class_name HFFileSystem

const HFLevelIO = preload("../hflevel_io.gd")
const MapIO = preload("../map_io.gd")
const HFMapQuakeType = preload("../map_adapters/hf_map_quake.gd")
const HFMapValve220Type = preload("../map_adapters/hf_map_valve220.gd")

var root: Node3D
var _hflevel_thread: Thread = null
var _hflevel_pending: Dictionary = {}
var _hflevel_last_hash: int = 0
## Last write error observed on the main thread (thread result is returned from wait_to_finish).
var _last_write_error := ""
## Set by process_thread_queue() from the worker result (true when hash matched).
var last_encode_skipped := false


func _init(level_root: Node3D) -> void:
	root = level_root


func save_hflevel(path: String = "", force: bool = false) -> int:
	var target = path if path != "" else root.hflevel_autosave_path
	if target == "":
		return ERR_INVALID_PARAMETER
	ensure_dir_for_path(target)
	if root.paint_system:
		root.paint_system.set_region_base_path(target)
		root.paint_system.save_loaded_regions()
	var encoded: Dictionary = {}
	var captured: Variant = root._capture_hflevel_state()
	if captured is Dictionary:
		encoded = (captured as Dictionary).duplicate(true)
	var compress := true
	if root:
		compress = bool(root.hflevel_compress)
	start_hflevel_thread(target, encoded, compress, force)
	return OK


func load_hflevel(path: String = "") -> bool:
	var target = path if path != "" else root.hflevel_autosave_path
	if target == "":
		return false
	if root.paint_system:
		root.paint_system.set_region_base_path(target)
	var data = HFLevelIO.load_from_path(target)
	if data.is_empty():
		return false
	var decoded = HFLevelIO.decode_variant(data)
	if not (decoded is Dictionary):
		return false
	var settings = decoded.get("settings", {})
	var state = decoded.get("state", {})
	root._apply_hflevel_settings(settings if settings is Dictionary else {})
	root.restore_state(state if state is Dictionary else {})
	return true


func import_map(path: String) -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	var map_data = MapIO.load_map(path)
	if map_data.is_empty():
		return ERR_INVALID_DATA
	root.clear_brushes()
	root._clear_entities()
	for info in map_data.get("brushes", []):
		if info is Dictionary:
			root.create_brush_from_info(info)
	for entity_info in map_data.get("entities", []):
		if entity_info is Dictionary:
			root._create_entity_from_map(entity_info)
	return OK


func export_map(path: String, format: String = "quake") -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	ensure_dir_for_path(path)
	var adapter: RefCounted
	if format == "valve220":
		adapter = HFMapValve220Type.new()
	else:
		adapter = HFMapQuakeType.new()
	var text = MapIO.export_map_from_level(root, adapter)
	if text == "":
		return ERR_INVALID_DATA
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ERR_CANT_OPEN
	file.store_string(text)
	var err = file.get_error()
	if err != OK:
		push_error("HFLevel: store_string failed for %s (error: %d)" % [path, err])
		if root and root.has_signal("user_message"):
			root.user_message.emit("File save failed: %s" % path.get_file(), 2)
		return err
	return OK


func export_baked_gltf(path: String) -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	if not root.baked_container:
		return ERR_DOES_NOT_EXIST
	if not ClassDB.class_exists("GLTFDocument"):
		return ERR_UNAVAILABLE
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	var err = doc.append_from_scene(root.baked_container, state)
	if err != OK:
		return err
	return doc.write_to_filesystem(state, path)


func ensure_dir_for_path(path: String) -> void:
	var abs_path = path
	if path.begins_with("res://") or path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	var dir_path = abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


func start_hflevel_thread(path: String, encoded: Dictionary, compress: bool, force: bool) -> void:
	if path == "":
		return
	var abs_path = ProjectSettings.globalize_path(path)
	var keep := 0
	var autosave_abs := ""
	if root:
		keep = int(root.hflevel_autosave_keep)
		autosave_abs = ProjectSettings.globalize_path(str(root.hflevel_autosave_path))
	var job := {
		"path": abs_path,
		"encoded": encoded,
		"compress": compress,
		"force": force,
		"keep": keep,
		"autosave_abs": autosave_abs,
		"last_hash": _hflevel_last_hash,
	}
	if _hflevel_thread and _hflevel_thread.is_alive():
		job["force"] = true
		_hflevel_pending = job
		return
	_hflevel_thread = Thread.new()
	_hflevel_thread.start(Callable(self, "_hflevel_thread_encode_and_write").bind(job))


func _hflevel_thread_encode_and_write(job: Dictionary) -> Dictionary:
	var path: String = str(job.get("path", ""))
	var encoded: Dictionary = job.get("encoded", {})
	var compress: bool = bool(job.get("compress", true))
	var force: bool = bool(job.get("force", false))
	var last_hash: int = int(job.get("last_hash", 0))
	var keep: int = int(job.get("keep", 0))
	var autosave_abs: String = str(job.get("autosave_abs", ""))
	var packed: Dictionary = HFLevelIO.encode_payload_job(encoded, compress)
	var hash_value: int = int(packed.get("hash", 0))
	if not force and hash_value != 0 and hash_value == last_hash:
		return {"error": "", "hash": hash_value, "skipped": true}
	var payload: PackedByteArray = packed.get("payload", PackedByteArray())
	if payload.is_empty():
		return {"error": "HFLevel: empty payload", "hash": hash_value, "skipped": true}
	var err := HFLevelIO.write_bytes_atomic(path, payload)
	if err != OK:
		var msg := "HFLevel: Failed to write file: %s (error: %d)" % [path, err]
		push_error(msg)
		return {"error": msg, "hash": hash_value, "skipped": false}
	_write_autosave_rotation(path, payload, keep, autosave_abs)
	return {"error": "", "hash": hash_value, "skipped": false}


func _write_autosave_rotation(
	path: String, payload: PackedByteArray, keep: int, autosave_abs: String
) -> void:
	if payload.is_empty() or keep <= 0:
		return
	if autosave_abs == "" or path != autosave_abs:
		return
	var base_dir = autosave_abs.get_base_dir()
	var history_dir = base_dir.path_join("autosave_history")
	if not DirAccess.dir_exists_absolute(history_dir):
		DirAccess.make_dir_recursive_absolute(history_dir)
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var base_name = autosave_abs.get_file().get_basename()
	if base_name == "":
		base_name = "autosave"
	var history_path = history_dir.path_join("%s_%s.hflevel" % [base_name, timestamp])
	var hist_err := HFLevelIO.write_bytes_atomic(history_path, payload)
	if hist_err != OK:
		push_warning("HFLevel: Failed to write autosave history file: %s" % history_path)
		return
	_prune_autosave_history(history_dir, keep)


func _prune_autosave_history(history_dir: String, keep: int) -> void:
	if keep <= 0:
		return
	var files = DirAccess.get_files_at(history_dir)
	if files.is_empty():
		return
	var entries: Array = []
	for file_name in files:
		if not file_name.ends_with(".hflevel"):
			continue
		var full_path = history_dir.path_join(file_name)
		var mtime = FileAccess.get_modified_time(full_path)
		entries.append({"path": full_path, "mtime": int(mtime)})
	entries.sort_custom(func(a, b): return int(a.get("mtime", 0)) > int(b.get("mtime", 0)))
	for i in range(keep, entries.size()):
		var path = str(entries[i].get("path", ""))
		if path != "" and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Process the write thread queue.  Returns a non-empty error string if the
## most recent write failed, empty string otherwise.
func process_thread_queue() -> String:
	if _hflevel_thread and not _hflevel_thread.is_alive():
		var result: Variant = _hflevel_thread.wait_to_finish()
		_hflevel_thread = null
		var error := _apply_thread_result(result)
		if not _hflevel_pending.is_empty():
			var next = _hflevel_pending.duplicate(true)
			_hflevel_pending.clear()
			_start_pending_job(next)
		return error
	return ""


func shutdown() -> void:
	if _hflevel_thread:
		_apply_thread_result(_hflevel_thread.wait_to_finish())
		_hflevel_thread = null
	if not _hflevel_pending.is_empty():
		var next = _hflevel_pending.duplicate(true)
		_hflevel_pending.clear()
		_flush_job_sync(next)
	_last_write_error = ""


func _apply_thread_result(result: Variant) -> String:
	_last_write_error = ""
	if result is Dictionary:
		var error := str(result.get("error", ""))
		if result.has("hash"):
			_hflevel_last_hash = int(result.get("hash", 0))
		last_encode_skipped = bool(result.get("skipped", false))
		_last_write_error = error
		return error
	if result is String:
		_last_write_error = result
		return result
	return ""


func _start_pending_job(job: Dictionary) -> void:
	var pending_path: String = str(job.get("path", ""))
	if pending_path == "" or not (job.get("encoded") is Dictionary):
		push_warning("HFLevel: Discarding pending write with empty path or payload")
		return
	_hflevel_thread = Thread.new()
	job["last_hash"] = _hflevel_last_hash
	_hflevel_thread.start(Callable(self, "_hflevel_thread_encode_and_write").bind(job))


func _flush_job_sync(job: Dictionary) -> void:
	var pending_path: String = str(job.get("path", ""))
	if pending_path == "":
		return
	if job.get("encoded") is Dictionary:
		var packed: Dictionary = HFLevelIO.encode_payload_job(
			job.get("encoded", {}), bool(job.get("compress", true))
		)
		var payload: PackedByteArray = packed.get("payload", PackedByteArray())
		if not payload.is_empty():
			HFLevelIO.write_bytes_atomic(pending_path, payload)
		if packed.has("hash"):
			_hflevel_last_hash = int(packed.get("hash", 0))
		return
	var legacy_payload: PackedByteArray = job.get("payload", PackedByteArray())
	if not legacy_payload.is_empty():
		HFLevelIO.write_bytes_atomic(pending_path, legacy_payload)
