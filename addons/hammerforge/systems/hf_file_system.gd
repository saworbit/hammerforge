@tool
extends RefCounted
class_name HFFileSystem

const HFLevelIO = preload("../hflevel_io.gd")
const MapIO = preload("../map_io.gd")
const HFMapQuakeType = preload("../map_adapters/hf_map_quake.gd")
const HFMapValve220Type = preload("../map_adapters/hf_map_valve220.gd")

var root: Node3D
var _hflevel_thread: Thread = null
var _hflevel_pending: Array[Dictionary] = []
var _hflevel_last_hash: int = 0
var _completed_saves: Array[Dictionary] = []
## Last write error observed on the main thread (thread result is returned from wait_to_finish).
## Set by process_thread_queue() from the worker result (true when hash matched).
var last_encode_skipped := false
## The target an autosave collision was last reported against, so the refusal is
## said once rather than every five minutes -- and said again if the level is
## later pointed at a different file that is also somebody else's.
var _autosave_collision_path := ""


func _init(level_root: Node3D) -> void:
	root = level_root


func save_hflevel(path: String = "", force: bool = false, autosave: bool = false) -> int:
	var target = path if path != "" else root.resolved_hflevel_path()
	if target == "":
		return ERR_INVALID_PARAMETER
	if autosave:
		var occupant := autosave_target_belongs_elsewhere(target)
		if occupant != "":
			var message := (
				"Autosave skipped: %s holds %s, not this level. Set this level's own autosave path."
				% [target.get_file(), occupant.get_file()]
			)
			if _autosave_collision_path != target:
				_autosave_collision_path = target
				HFLog.warn("HammerForge: %s" % message)
				if root.has_signal("autosave_failed"):
					root.autosave_failed.emit(message)
			return ERR_FILE_CANT_WRITE
	ensure_dir_for_path(target)
	if root.paint_system:
		root.paint_system.set_region_base_path(target)
		var regions: Dictionary = root.paint_system.save_loaded_regions()
		if not bool(regions.get("ok", true)):
			# The index would claim region data that is missing or stale, and the
			# level write would still report success. Stop here instead.
			var message := str(regions.get("error", "region write failed"))
			push_error("HFLevel: %s" % message)
			# Report it as the kind of save it actually was, the way the worker
			# results are reported in _process_hflevel_saves.
			if autosave:
				if root.has_signal("autosave_failed"):
					root.autosave_failed.emit(message)
			elif root.has_signal("hflevel_save_failed"):
				root.hflevel_save_failed.emit(target, message)
			return ERR_FILE_CANT_WRITE
	# The capture is a fresh structure with nothing else holding a reference to
	# it, so the deep copy this used to take was protecting it from nobody. The
	# encode that used to happen here happens on the write thread now (#601).
	var payload: Dictionary = {}
	var captured: Variant = root._capture_hflevel_payload()
	if captured is Dictionary:
		payload = captured
	var compress := true
	if root:
		compress = bool(root.hflevel_compress)
	start_hflevel_thread(target, payload, compress, force, autosave)
	return OK


func load_hflevel(path: String = "") -> bool:
	var target = path if path != "" else root.resolved_hflevel_path()
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
	# Before anything is applied, because `restore_state()` clears the level first
	# and a file this build cannot read correctly must not cost the open one. A
	# missing or zero version is an older file and still loads: every key defaults,
	# which is the direction that has always been safe.
	var version := int(decoded.get("version", 0))
	if version > HFLevelIO.FORMAT_VERSION:
		var message := (
			"%s was written by a newer build (format %d, this build reads %d)"
			% [target.get_file(), version, HFLevelIO.FORMAT_VERSION]
		)
		HFLog.warn("HFFileSystem: %s" % message)
		if root.has_signal("user_message"):
			root.user_message.emit("Level not loaded: %s" % message, 2)
		return false
	var settings = decoded.get("settings", {})
	var state = decoded.get("state", {})
	root._apply_hflevel_settings(settings if settings is Dictionary else {})
	root.restore_state(state if state is Dictionary else {})
	return true


## Whether a level's two files are out of step, and which way.
##
## A level lives in a `.tscn` and a `.hflevel`, written by two different commands
## (#646). Ctrl+S writes the scene, Save Level writes the `.hflevel`, and on open
## the scene wins because the scene is what Godot loads. So a `.hflevel` saved
## after the last Ctrl+S is sitting beside the level unread, and nothing said so.
## Autosave puts the level in that state on a timer nobody chose.
##
## This only reports. Reconciling the two, or diffing them and letting the mapper
## pick, is a much larger feature; knowing they disagree is most of the value.
func check_hflevel_freshness() -> Dictionary:
	var report := {
		"stale": false,
		"reason": "",
		"message": "",
		"hflevel_path": "",
		"scene_path": "",
		"hflevel_time": 0,
		"scene_time": 0,
	}
	if root == null:
		report["reason"] = "no_level"
		return report
	var hflevel_path := str(root.resolved_hflevel_path()).strip_edges()
	if hflevel_path == "":
		report["reason"] = "no_hflevel_path"
		return report
	report["hflevel_path"] = hflevel_path
	# A scene that keeps only its baked geometry has no brushes to win with, so it
	# loads the `.hflevel` when it opens (#624). It is never the one behind.
	if root.has_method("scene_keeps_brushes") and not root.scene_keeps_brushes():
		report["reason"] = "loads_from_hflevel"
		return report
	var scene_path := str(root.scene_source_path())
	report["scene_path"] = scene_path
	if scene_path == "":
		report["reason"] = "scene_never_saved"
		return report
	var hflevel_time := FileAccess.get_modified_time(hflevel_path)
	var scene_time := FileAccess.get_modified_time(scene_path)
	report["hflevel_time"] = hflevel_time
	report["scene_time"] = scene_time
	if hflevel_time <= 0:
		report["reason"] = "no_hflevel_file"
		return report
	if scene_time <= 0:
		report["reason"] = "scene_never_saved"
		return report
	if not level_file_is_stale(hflevel_time, scene_time):
		report["reason"] = "scene_current"
		return report
	# Only now is the file worth opening. A level derives its own autosave name
	# from its scene now (#655), so a newer file next to this scene is usually
	# this one's -- but a level pointed at a shared path by hand, or a file
	# written before that derivation, can still be another level's, and Load
	# Level would overwrite the open level with it.
	var recorded := read_recorded_scene(hflevel_path)
	if recorded != "" and recorded != scene_path:
		report["reason"] = "another_level"
		return report
	report["stale"] = true
	if recorded == "":
		# Written before a `.hflevel` said where it came from. It may be this
		# level's and it may be the level next door's, and saying which is not
		# available here, so the message does not claim one.
		report["reason"] = "hflevel_newer_unattributed"
		report["message"] = (
			"%s was saved after %s, and does not say which level it holds. Load Level brings it in, and replaces what is open."
			% [hflevel_path.get_file(), scene_path.get_file()]
		)
		return report
	report["reason"] = "hflevel_newer"
	report["message"] = (
		"%s was saved after %s. The scene is what opened. Load Level brings the newer one in, and replaces what is open."
		% [hflevel_path.get_file(), scene_path.get_file()]
	)
	return report


## The scene a `.hflevel` records itself as holding, or "" for a file written
## before that was recorded or one this build cannot read.
##
## Deliberately not `HFLevelIO.load_from_path()`: that renames a `.previous`
## back over a missing file, and recovering a level is not something a question
## about one should do.
static func read_recorded_scene(path: String) -> String:
	if path == "" or not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var data: Variant = HFLevelIO.parse_payload(file.get_buffer(file.get_length()))
	file.close()
	if not (data is Dictionary):
		return ""
	return str((data as Dictionary).get("scene", "")).strip_edges()


## The scene an existing `.hflevel` says it holds, when that is not this level.
##
## An autosave is a write nobody asked for, on a timer, so it is the one save
## that must not land on another level's file. A file that records no scene is
## not attributed either way -- it was written before that was recorded, and
## refusing on a guess would stop a level autosaving to its own history (#655).
## Neither is a level whose scene has never been saved: it has no name to
## compare, and nothing yet to lose.
func autosave_target_belongs_elsewhere(target: String) -> String:
	if target == "" or not FileAccess.file_exists(target):
		return ""
	if root == null or not root.has_method("scene_source_path"):
		return ""
	var mine := str(root.scene_source_path()).strip_edges()
	if mine == "":
		return ""
	var recorded := read_recorded_scene(target)
	if recorded == "" or recorded == mine:
		return ""
	return recorded


## Whether the `.hflevel` is ahead of the scene, given when each was written.
##
## Zero is what `FileAccess.get_modified_time()` returns for a file that is not
## there, and it means "never written" here: neither half of a level can be
## behind a file that does not exist.
##
## Equal is not stale. The stamps are whole seconds, so a scene and a level
## written inside the same second cannot be told apart, and under reporting is
## the right direction for a warning nobody asked for.
static func level_file_is_stale(hflevel_time: int, scene_time: int) -> bool:
	if hflevel_time <= 0 or scene_time <= 0:
		return false
	return hflevel_time > scene_time


## Parse a .map without touching the level. The dock preflights with this so a
## malformed file never clears the current work.
func validate_map(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {"ok": false, "error": "File not found: %s" % path}
	var map_data = MapIO.load_map(path)
	if map_data.is_empty():
		return {"ok": false, "error": "Could not read %s" % path.get_file()}
	var errors: Array = map_data.get("errors", [])
	if not errors.is_empty():
		return {"ok": false, "error": str(errors[0])}
	return {"ok": true, "error": ""}


func _report_map_error(path: String, message: String) -> void:
	var text := "Map import failed (%s): %s" % [path.get_file(), message]
	push_error(text)
	if root and root.has_signal("user_message"):
		root.user_message.emit(text, 2)


func import_map(path: String) -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	var map_data = MapIO.load_map(path)
	if map_data.is_empty():
		return ERR_INVALID_DATA
	var errors: Array = map_data.get("errors", [])
	if not errors.is_empty():
		_report_map_error(path, str(errors[0]))
		return ERR_INVALID_DATA
	root.clear_brushes()
	root._clear_entities()
	var worldspawn = map_data.get("worldspawn", {})
	if worldspawn is Dictionary and "map_worldspawn_properties" in root:
		root.map_worldspawn_properties = (worldspawn as Dictionary).duplicate()
	var palette := _palette_by_texture_token()
	for info in map_data.get("brushes", []):
		if info is Dictionary:
			var brush = root.create_brush_from_info(info)
			_apply_map_textures(brush, info, palette)
	for entity_info in map_data.get("entities", []):
		if entity_info is Dictionary:
			root._create_entity_from_map(entity_info)
	return OK


## The palette, keyed the way a texture name is written on a face line, so a name
## read back out of a `.map` finds the slot it was exported from.
func _palette_by_texture_token() -> Dictionary:
	var out: Dictionary = {}
	# Test shims stand in for LevelRoot on this path and do not all carry a
	# material manager, so ask before reaching for it.
	if not ("material_manager" in root) or root.material_manager == null:
		return out
	var names: Array = root.material_manager.get_material_names()
	for i in names.size():
		var token := MapIO.texture_token(str(names[i]))
		if token != MapIO.DEFAULT_TEXTURE and not out.has(token):
			out[token] = i
	return out


## Record each imported face's texture name, and point it at a palette slot.
##
## The name goes on the face whatever the palette holds. A fresh import is into
## an empty palette, so the old guard -- give up when the palette is empty --
## meant sixty faces arrived on slot -1 with their names nowhere, and an export
## wrote `__default` on all of them (#662). The name is not decoration in this
## lineage: `AAATRIGGER` is a trigger volume and `*water1` is water.
##
## A name the palette does not already hold mints a placeholder slot named after
## it, so the Surface panel says `*water1` on the water and the palette mirrors
## the file. A placeholder is deliberately not given a `resource_path`: a `.map`
## names a texture without saying where it lives, and guessing one would put a
## broken reference on the face.
func _apply_map_textures(brush, info: Dictionary, palette: Dictionary) -> void:
	if not is_instance_valid(brush):
		return
	var by_normal: Dictionary = info.get("map_textures_by_normal", {})
	if not by_normal.is_empty():
		for face in brush.faces:
			if face == null:
				continue
			_assign_map_texture(
				face, str(by_normal.get(MapIO.normal_key(face.normal), "")), palette
			)
		return
	var textures: Array = info.get("map_textures", [])
	for i in mini(textures.size(), brush.faces.size()):
		_assign_map_texture(brush.faces[i], str(textures[i]), palette)


func _assign_map_texture(face, token: String, palette: Dictionary) -> void:
	if face == null:
		return
	var name_token := token.strip_edges()
	if name_token == "" or name_token == MapIO.DEFAULT_TEXTURE:
		return
	face.map_texture = name_token
	if not palette.has(name_token):
		var minted := _mint_palette_slot(name_token)
		if minted < 0:
			return
		palette[name_token] = minted
	face.material_idx = int(palette[name_token])


## A palette slot standing in for a texture the file names and the project does
## not have. Returns its index, or -1 when there is no palette to add to.
func _mint_palette_slot(name_token: String) -> int:
	if not ("material_manager" in root) or root.material_manager == null:
		return -1
	var placeholder := StandardMaterial3D.new()
	placeholder.resource_name = name_token
	return int(root.material_manager.add_material(placeholder))


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


func start_hflevel_thread(
	path: String, state: Dictionary, compress: bool, force: bool, autosave: bool = false
) -> void:
	if path == "":
		return
	var abs_path = ProjectSettings.globalize_path(path)
	var keep := 0
	var autosave_abs := ""
	if root:
		keep = int(root.hflevel_autosave_keep)
		autosave_abs = ProjectSettings.globalize_path(root.resolved_hflevel_path())
	var job := {
		"path": abs_path,
		"display_path": path,
		"state": state,
		"compress": compress,
		"force": force,
		"keep": keep,
		"autosave_abs": autosave_abs,
		"autosave": autosave,
		"last_hash": _hflevel_last_hash,
	}
	if _hflevel_thread:
		if _hflevel_thread.is_alive():
			job["force"] = true
			_hflevel_pending.append(job)
			return
		_apply_thread_result(_hflevel_thread.wait_to_finish())
		_hflevel_thread = null
		# Collecting a finished worker does not entitle this job to run next.
		# Anything already queued was asked for first and still owns its slot.
		if not _hflevel_pending.is_empty():
			job["force"] = true
			_hflevel_pending.append(job)
			_start_next_pending()
			return
	_hflevel_thread = Thread.new()
	_hflevel_thread.start(Callable(self, "_hflevel_thread_encode_and_write").bind(job))


func _hflevel_thread_encode_and_write(job: Dictionary) -> Dictionary:
	var path: String = str(job.get("path", ""))
	var display_path: String = str(job.get("display_path", path))
	var state: Dictionary = job.get("state", {})
	var compress: bool = bool(job.get("compress", true))
	var force: bool = bool(job.get("force", false))
	var last_hash: int = int(job.get("last_hash", 0))
	var keep: int = int(job.get("keep", 0))
	var autosave_abs: String = str(job.get("autosave_abs", ""))
	var autosave: bool = bool(job.get("autosave", false))
	# The expensive half, and the reason the thread exists. Everything it touches
	# is a value, because `capture_hflevel_payload()` resolved the Resources
	# before the handoff. That is the precondition for running this here at all:
	# `encode_variant()` reads `resource_path` off a live Resource, and warns
	# through `HFLog` when there is not one, and neither is the worker's to do.
	# `test_the_payload_handed_to_the_write_thread_holds_nothing_live` is what
	# holds it.
	var packed: Dictionary = HFLevelIO.encode_payload_job(HFLevelIO.encode_variant(state), compress)
	var hash_value: int = int(packed.get("hash", 0))
	if not force and hash_value != 0 and hash_value == last_hash:
		return {
			"error": "",
			"hash": hash_value,
			"skipped": true,
			"path": display_path,
			"autosave": autosave,
		}
	var payload: PackedByteArray = packed.get("payload", PackedByteArray())
	if payload.is_empty():
		return {
			"error": "HFLevel: empty payload",
			"hash": hash_value,
			"skipped": true,
			"path": display_path,
			"autosave": autosave,
		}
	var err := HFLevelIO.write_bytes_atomic(path, payload)
	if err != OK:
		var msg := "HFLevel: Failed to write file: %s (error: %d)" % [path, err]
		push_error(msg)
		return {
			"error": msg,
			"hash": hash_value,
			"skipped": false,
			"path": display_path,
			"autosave": autosave,
		}
	_write_autosave_rotation(path, payload, keep, autosave_abs)
	return {
		"error": "",
		"hash": hash_value,
		"skipped": false,
		"path": display_path,
		"autosave": autosave,
	}


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
	var stamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	# To the second was not enough. Two writes inside one second landed on one path
	# and `write_bytes_atomic()` replaces rather than refuses, so three saves left
	# one backup and the keep count stopped meaning how far back the history goes.
	var timestamp = "%s-%03d" % [stamp, Time.get_ticks_msec() % 1000]
	var base_name = autosave_abs.get_file().get_basename()
	if base_name == "":
		base_name = "autosave"
	var history_path = history_dir.path_join("%s_%s.hflevel" % [base_name, timestamp])
	# The millisecond makes a same-second collision very unlikely rather than
	# impossible, and losing a backup to one is not a trade worth making.
	var attempt := 2
	while FileAccess.file_exists(history_path) and attempt < 100:
		history_path = history_dir.path_join("%s_%s-%d.hflevel" % [base_name, timestamp, attempt])
		attempt += 1
	var hist_err := HFLevelIO.write_bytes_atomic(history_path, payload)
	if hist_err != OK:
		push_warning("HFLevel: Failed to write autosave history file: %s" % history_path)
		return
	_prune_autosave_history(history_dir, keep, base_name)


## Delete the oldest history files for one level, keeping `keep` of them.
##
## `base_name` is the level's own autosave file name, and it is what stops this
## being every level's budget. Two levels in one project share a history folder,
## and pruning by folder meant autosaving one deleted the other's backups.
func _prune_autosave_history(history_dir: String, keep: int, base_name: String) -> void:
	if keep <= 0 or base_name == "":
		return
	var files = DirAccess.get_files_at(history_dir)
	if files.is_empty():
		return
	var prefix := base_name + "_"
	var entries: Array = []
	for file_name in files:
		if not file_name.ends_with(".hflevel") or not file_name.begins_with(prefix):
			continue
		# `level_` also prefixes `level_backup_...`, which belongs to another level.
		# What follows the name is a timestamp, so it starts with a year.
		var tail := file_name.substr(prefix.length())
		if tail.length() < 4 or not tail.substr(0, 4).is_valid_int():
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
		_start_next_pending()
		return error
	return ""


func take_completed_saves() -> Array[Dictionary]:
	var completed := _completed_saves.duplicate(true)
	_completed_saves.clear()
	return completed


func shutdown() -> void:
	if _hflevel_thread:
		_apply_thread_result(_hflevel_thread.wait_to_finish())
		_hflevel_thread = null
	while not _hflevel_pending.is_empty():
		var next: Dictionary = _hflevel_pending.pop_front()
		_flush_job_sync(next)


func _apply_thread_result(result: Variant) -> String:
	if result is Dictionary:
		var error := str(result.get("error", ""))
		if result.has("hash"):
			_hflevel_last_hash = int(result.get("hash", 0))
		last_encode_skipped = bool(result.get("skipped", false))
		_completed_saves.append((result as Dictionary).duplicate(true))
		return error
	if result is String:
		return result
	return ""


func _start_pending_job(job: Dictionary) -> bool:
	var pending_path: String = str(job.get("path", ""))
	if pending_path == "" or not (job.get("state") is Dictionary):
		push_warning("HFLevel: Discarding pending write with empty path or payload")
		return false
	_hflevel_thread = Thread.new()
	job["last_hash"] = _hflevel_last_hash
	_hflevel_thread.start(Callable(self, "_hflevel_thread_encode_and_write").bind(job))
	return true


## Start the oldest queued write, skipping any that cannot run. Without the
## loop a discarded job would leave the queue stalled with no live thread.
func _start_next_pending() -> void:
	while not _hflevel_pending.is_empty():
		if _start_pending_job(_hflevel_pending.pop_front()):
			return


func _flush_job_sync(job: Dictionary) -> void:
	var pending_path: String = str(job.get("path", ""))
	if pending_path == "":
		return
	if job.get("state") is Dictionary:
		var packed: Dictionary = HFLevelIO.encode_payload_job(
			HFLevelIO.encode_variant(job.get("state", {})), bool(job.get("compress", true))
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
