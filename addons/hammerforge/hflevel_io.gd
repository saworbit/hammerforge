@tool
extends RefCounted
class_name HFLevelIO

## The highest bundle version this build knows how to read.
##
## `capture_hflevel_state()` stamps this into every `.hflevel`. Nothing read it
## before, which protects new code reading old files - every key defaults - and
## does nothing for old code reading new ones, which is the case a version number
## exists for. Bump it here, in one place, when a format change is not purely
## additive.
const FORMAT_VERSION := 1

const MAGIC := "HFLEVEL1"
const MAGIC_COMPRESSED := "HFLEVEL1C"
const TYPE_KEY := "__hf_type"
const MAX_RECURSION_DEPTH := 64
const HFLog = preload("res://addons/hammerforge/hf_log.gd")
const COMPRESSION_MODE := FileAccess.COMPRESSION_DEFLATE


static func _is_vec3_arr(v: Variant) -> bool:
	return v is Array and v.size() >= 3


## Variant types that carry no data a level file can hold. Anything else the
## `_` arm meets is handed to `JSON.from_native()`, which covers every remaining
## engine type.
const UNSERIALIZABLE_TYPES := [TYPE_OBJECT, TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL]


static func encode_variant(value: Variant, _depth: int = 0) -> Variant:
	if _depth > MAX_RECURSION_DEPTH:
		push_warning("HFLevelIO: encode_variant max recursion depth exceeded")
		return null
	if value is Resource:
		var res: Resource = value
		var path = res.resource_path
		if path != "":
			return {TYPE_KEY: "ResourcePath", "path": path}
		# A resource built in memory has nothing this format can point at. Record
		# what it was so the load can name it, rather than writing a bare null and
		# leaving the reader to guess. Same resolution as `save_library()` (#515).
		var res_class := res.get_class()
		var res_name := res.resource_name
		HFLog.warn(
			(
				(
					"HFLevelIO: a %s with no resource path was written as an empty slot. "
					+ "Save it to disk before saving the level if it should survive."
				)
				% res_class
			)
		)
		return {TYPE_KEY: "MissingResource", "class": res_class, "name": res_name}
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			# JSON's own types. Written raw, which is what every existing file holds.
			return value
		TYPE_VECTOR2:
			return {TYPE_KEY: "Vector2", "value": [value.x, value.y]}
		TYPE_VECTOR3:
			return {TYPE_KEY: "Vector3", "value": [value.x, value.y, value.z]}
		TYPE_TRANSFORM3D:
			var origin = value.origin
			var basis = value.basis
			return {
				TYPE_KEY: "Transform3D",
				"origin": [origin.x, origin.y, origin.z],
				"basis":
				[
					[basis.x.x, basis.x.y, basis.x.z],
					[basis.y.x, basis.y.y, basis.y.z],
					[basis.z.x, basis.z.y, basis.z.z]
				]
			}
		TYPE_BASIS:
			return {
				TYPE_KEY: "Basis",
				"value":
				[
					[value.x.x, value.x.y, value.x.z],
					[value.y.x, value.y.y, value.y.z],
					[value.z.x, value.z.y, value.z.z]
				]
			}
		TYPE_COLOR:
			return {TYPE_KEY: "Color", "value": value.to_html()}
		TYPE_ARRAY:
			var out: Array = []
			for item in value:
				out.append(encode_variant(item, _depth + 1))
			return out
		TYPE_DICTIONARY:
			# JSON objects have String keys only, so a Vector2i or int key would be
			# flattened to its str() form and never come back. A dictionary that has
			# one is written as a list of encoded key/value pairs instead.
			var string_keys := true
			for key in value.keys():
				if typeof(key) != TYPE_STRING:
					string_keys = false
					break
			if string_keys:
				var dict_out: Dictionary = {}
				for key in value.keys():
					dict_out[key] = encode_variant(value[key], _depth + 1)
				return dict_out
			var entries: Array = []
			for key in value.keys():
				entries.append(
					[_encode_dict_key(key, _depth + 1), encode_variant(value[key], _depth + 1)]
				)
			return {TYPE_KEY: "Dictionary", "entries": entries}
		_:
			if typeof(value) in UNSERIALIZABLE_TYPES:
				push_warning(
					(
						(
							"HFLevelIO: a value of type %d cannot be written to a level file "
							+ "and was dropped."
						)
						% typeof(value)
					)
				)
				return null
			# Everything left is an engine data type. `JSON.from_native()` is the
			# engine's own JSON representation for these and round trips through
			# `to_native()` exactly, so the encoder no longer has a list to fall off
			# the end of.
			return {TYPE_KEY: "Native", "value": JSON.from_native(value)}


## A dictionary key has to come back as the exact type it went in as - an int key
## widened to a float by JSON no longer finds its own entry. `JSON.from_native()`
## tags the type of a raw number or string, which `encode_variant()` deliberately
## does not, so keys take that route instead.
static func _encode_dict_key(key: Variant, _depth: int = 0) -> Variant:
	if key is Resource or typeof(key) in UNSERIALIZABLE_TYPES:
		return encode_variant(key, _depth)
	return {TYPE_KEY: "Native", "value": JSON.from_native(key)}


static func decode_variant(value: Variant, _depth: int = 0) -> Variant:
	if _depth > MAX_RECURSION_DEPTH:
		push_warning("HFLevelIO: decode_variant max recursion depth exceeded")
		return null
	if value is Dictionary and value.has(TYPE_KEY):
		var type_name = str(value.get(TYPE_KEY, ""))
		match type_name:
			"Vector2":
				var vec = value.get("value", [])
				return Vector2(vec[0], vec[1]) if vec is Array and vec.size() >= 2 else Vector2.ZERO
			"Vector3":
				var vec3 = value.get("value", [])
				return (
					Vector3(vec3[0], vec3[1], vec3[2])
					if vec3 is Array and vec3.size() >= 3
					else Vector3.ZERO
				)
			"Transform3D":
				var origin_arr = value.get("origin", [])
				var basis_arr = value.get("basis", [])
				var origin = (
					Vector3(origin_arr[0], origin_arr[1], origin_arr[2])
					if origin_arr is Array and origin_arr.size() >= 3
					else Vector3.ZERO
				)
				var basis = Basis.IDENTITY
				if (
					basis_arr is Array
					and basis_arr.size() >= 3
					and _is_vec3_arr(basis_arr[0])
					and _is_vec3_arr(basis_arr[1])
					and _is_vec3_arr(basis_arr[2])
				):
					basis = Basis(
						Vector3(basis_arr[0][0], basis_arr[0][1], basis_arr[0][2]),
						Vector3(basis_arr[1][0], basis_arr[1][1], basis_arr[1][2]),
						Vector3(basis_arr[2][0], basis_arr[2][1], basis_arr[2][2])
					)
				return Transform3D(basis, origin)
			"Basis":
				var b = value.get("value", [])
				if (
					b is Array
					and b.size() >= 3
					and _is_vec3_arr(b[0])
					and _is_vec3_arr(b[1])
					and _is_vec3_arr(b[2])
				):
					return Basis(
						Vector3(b[0][0], b[0][1], b[0][2]),
						Vector3(b[1][0], b[1][1], b[1][2]),
						Vector3(b[2][0], b[2][1], b[2][2])
					)
				return Basis.IDENTITY
			"Color":
				return Color(str(value.get("value", "#ffffff")))
			"ResourcePath":
				var path = str(value.get("path", ""))
				if path != "" and ResourceLoader.exists(path):
					return ResourceLoader.load(path)
				return null
			"MissingResource":
				var lost_class = str(value.get("class", "Resource"))
				var lost_name = str(value.get("name", ""))
				HFLog.warn(
					(
						(
							"HFLevelIO: this level was saved with a %s that had no resource "
							+ "path%s, so the slot is empty."
						)
						% [lost_class, "" if lost_name == "" else " ('%s')" % lost_name]
					)
				)
				return null
			"Dictionary":
				var entries = value.get("entries", [])
				var pairs_out: Dictionary = {}
				if entries is Array:
					for entry in entries:
						if entry is Array and entry.size() >= 2:
							pairs_out[decode_variant(entry[0], _depth + 1)] = decode_variant(
								entry[1], _depth + 1
							)
				return pairs_out
			"Native":
				# `allow_objects` stays false. A level file is untrusted input, and
				# turning it on lets one name a class to instantiate on load.
				return JSON.to_native(value.get("value"), false)
			_:
				return null
	if value is Array:
		var list_out: Array = []
		for item in value:
			list_out.append(decode_variant(item, _depth + 1))
		return list_out
	if value is Dictionary:
		var dict_out: Dictionary = {}
		for key in value.keys():
			dict_out[key] = decode_variant(value[key], _depth + 1)
		return dict_out
	return value


static func build_payload(data: Dictionary, compress: bool = true) -> PackedByteArray:
	var json = JSON.stringify(data)
	return build_payload_from_json(json, compress)


## Stringify, hash, and pack a captured state dict. Safe to call off the main
## thread because it only touches primitives / PackedByteArray.
static func encode_payload_job(data: Dictionary, compress: bool = true) -> Dictionary:
	var json := JSON.stringify(data)
	var hash_value := json.hash()
	return {
		"hash": hash_value,
		"payload": build_payload_from_json(json, compress),
	}


static func build_payload_from_json(json: String, compress: bool = true) -> PackedByteArray:
	var raw: PackedByteArray = json.to_utf8_buffer()
	var payload := PackedByteArray()
	if compress:
		var packed: PackedByteArray = raw.compress(COMPRESSION_MODE)
		var header := "%s %d\n" % [MAGIC_COMPRESSED, raw.size()]
		payload.append_array(header.to_utf8_buffer())
		payload.append_array(packed)
		return payload
	payload.append_array(("%s\n" % MAGIC).to_utf8_buffer())
	payload.append_array(raw)
	return payload


static func parse_payload(payload: PackedByteArray) -> Dictionary:
	if payload.is_empty():
		return {}
	var newline = payload.find(10)
	if newline < 0:
		return {}
	var header_bytes = payload.slice(0, newline)
	var header = header_bytes.get_string_from_utf8()
	var compressed := header.begins_with(MAGIC_COMPRESSED)
	if not compressed and not header.begins_with(MAGIC):
		HFLog.warn("HFLevelIO: Invalid header, expected %s" % MAGIC)
		return {}
	var body: PackedByteArray = payload.slice(newline + 1, payload.size())
	if compressed:
		var parts: PackedStringArray = header.split(" ")
		var uncompressed_size: int = int(parts[1]) if parts.size() >= 2 else 0
		if uncompressed_size <= 0:
			HFLog.warn("HFLevelIO: Compressed payload missing size")
			return {}
		body = body.decompress(uncompressed_size, COMPRESSION_MODE)
		if body.is_empty():
			HFLog.warn("HFLevelIO: Decompress failed")
			return {}
	var json = body.get_string_from_utf8()
	if json == "":
		HFLog.warn("HFLevelIO: Empty JSON body in payload")
		return {}
	var data = JSON.parse_string(json)
	if data == null:
		HFLog.warn("HFLevelIO: JSON parse failed")
		return {}
	return data if data is Dictionary else {}


static func write_bytes_atomic(path: String, payload: PackedByteArray) -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	var tmp_path := path + ".writing"
	var file = FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		return ERR_CANT_OPEN
	file.store_buffer(payload)
	var err = file.get_error()
	file.close()
	if err != OK:
		push_error("HFLevelIO: store_buffer failed for %s (error: %d)" % [tmp_path, err])
		DirAccess.remove_absolute(tmp_path)
		return err
	return _replace_file_atomic(path, tmp_path)


static func _replace_file_atomic(path: String, tmp_path: String) -> int:
	var backup_path := path + ".previous"
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(backup_path):
			var recover_err := DirAccess.rename_absolute(backup_path, path)
			if recover_err != OK:
				return recover_err
		else:
			var first_rename := DirAccess.rename_absolute(tmp_path, path)
			if first_rename != OK:
				push_error("HFLevelIO: rename failed for %s (error: %d)" % [path, first_rename])
				DirAccess.remove_absolute(tmp_path)
			return first_rename
	if FileAccess.file_exists(backup_path):
		var stale_err := DirAccess.remove_absolute(backup_path)
		if stale_err != OK:
			return stale_err
	var backup_err := DirAccess.copy_absolute(path, backup_path)
	if backup_err != OK:
		push_error("HFLevelIO: backup failed for %s (error: %d)" % [path, backup_err])
		DirAccess.remove_absolute(tmp_path)
		return backup_err
	var remove_err := DirAccess.remove_absolute(path)
	if remove_err != OK:
		DirAccess.remove_absolute(backup_path)
		DirAccess.remove_absolute(tmp_path)
		return remove_err
	var renamed := DirAccess.rename_absolute(tmp_path, path)
	if renamed != OK:
		push_error("HFLevelIO: rename failed for %s (error: %d)" % [path, renamed])
		var restore_err := DirAccess.rename_absolute(backup_path, path)
		if restore_err != OK:
			push_error(
				(
					"HFLevelIO: restore failed for %s; previous file remains at %s (error: %d)"
					% [path, backup_path, restore_err]
				)
			)
		DirAccess.remove_absolute(tmp_path)
		return renamed
	DirAccess.remove_absolute(backup_path)
	return OK


static func save_to_path(path: String, data: Dictionary, compress: bool = true) -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	return write_bytes_atomic(path, build_payload(data, compress))


static func load_from_path(path: String) -> Dictionary:
	if path == "":
		return {}
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".previous"):
		var recover_err := DirAccess.rename_absolute(path + ".previous", path)
		if recover_err != OK:
			push_error("HFLevelIO: recovery failed for %s (error: %d)" % [path, recover_err])
			return {}
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var payload = file.get_buffer(file.get_length())
	return parse_payload(payload)
