@tool
extends RefCounted
class_name HFFileSystem

const HFLevelIO = preload("../hflevel_io.gd")
const MapIO = preload("../map_io.gd")

var root: Node3D
var _hflevel_thread: Thread = null
var _hflevel_pending: Dictionary = {}
var _hflevel_last_hash: int = 0


func _init(level_root: Node3D) -> void:
	root = level_root


func save_hflevel(path: String = "", force: bool = false) -> int:
	var target = path if path != "" else root.hflevel_autosave_path
	if target == "":
		return ERR_INVALID_PARAMETER
	ensure_dir_for_path(target)
	var encoded = root._capture_hflevel_state()
	var json = JSON.stringify(encoded)
	var hash_value = json.hash()
	if not force and hash_value == _hflevel_last_hash:
		return OK
	_hflevel_last_hash = hash_value
	var payload = HFLevelIO.build_payload_from_json(json, root.hflevel_compress)
	start_hflevel_thread(target, payload)
	return OK


func load_hflevel(path: String = "") -> bool:
	var target = path if path != "" else root.hflevel_autosave_path
	if target == "":
		return false
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


func export_map(path: String) -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	ensure_dir_for_path(path)
	var text = MapIO.export_map_from_level(root)
	if text == "":
		return ERR_INVALID_DATA
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ERR_CANT_OPEN
	file.store_string(text)
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
	var err = ERR_CANT_CREATE
	if doc.has_method("append_from_scene"):
		err = doc.call("append_from_scene", root.baked_container, state)
	elif doc.has_method("append_from_node"):
		err = doc.call("append_from_node", root.baked_container, state)
	if err != OK:
		return err
	if doc.has_method("write_to_filesystem"):
		return doc.call("write_to_filesystem", state, path)
	return ERR_UNAVAILABLE


func ensure_dir_for_path(path: String) -> void:
	var abs_path = path
	if path.begins_with("res://") or path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	var dir_path = abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


func start_hflevel_thread(path: String, payload: PackedByteArray) -> void:
	if path == "" or payload.is_empty():
		return
	var abs_path = ProjectSettings.globalize_path(path)
	ensure_dir_for_path(abs_path)
	if _hflevel_thread and _hflevel_thread.is_alive():
		_hflevel_pending = {"path": abs_path, "payload": payload}
		return
	_hflevel_thread = Thread.new()
	_hflevel_thread.start(Callable(self, "_hflevel_thread_write").bind(abs_path, payload))


func _hflevel_thread_write(path: String, payload: PackedByteArray) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error(
			(
				"HFLevel: Failed to open file for write: %s (error: %d)"
				% [path, FileAccess.get_open_error()]
			)
		)
		return
	file.store_buffer(payload)
	var err = file.get_error()
	if err != OK:
		push_error("HFLevel: store_buffer failed for %s (error: %d)" % [path, err])


func process_thread_queue() -> void:
	if _hflevel_thread and not _hflevel_thread.is_alive():
		_hflevel_thread.wait_to_finish()
		_hflevel_thread = null
		if not _hflevel_pending.is_empty():
			var next = _hflevel_pending.duplicate(true)
			_hflevel_pending.clear()
			var pending_path: String = next.get("path", "")
			var pending_payload: PackedByteArray = next.get("payload", PackedByteArray())
			if pending_path == "" or pending_payload.is_empty():
				push_warning("HFLevel: Discarding pending write with empty path or payload")
			else:
				start_hflevel_thread(pending_path, pending_payload)
