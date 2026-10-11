@tool
class_name HFMcpProtocol
extends RefCounted
## The MCP bridge's wire format and argument checks.
##
## A frame is a 4-byte unsigned big-endian length and then that many bytes of
## UTF-8 JSON holding one object. Both ends of the socket follow these rules,
## the listener here and `hammerforge_mcp/framing.py` in Python, so this file
## touches no scene and can be tested on its own. The full protocol is in
## `docs/superpowers/specs/2026-10-11-mcp-bridge-design.md`.

const BRIDGE_VERSION := 1
const SCHEMA_VERSION := 1
const SUPPORTED_BRIDGE_VERSIONS := [1]

const MAX_REQUEST_BYTES := 1 << 20
const MAX_RESPONSE_BYTES := 16 << 20

## Every undo step the bridge records starts with this, and `hf_undo` only takes
## back a step that does.
const ACTION_PREFIX := "MCP: "

const OPERATION_ID_MAX := 128

## No coordinate or size past this many metres. Far beyond any level, and small
## enough that a typo of a few extra zeros is refused instead of building a brush
## the bake cannot handle.
const WORLD_LIMIT := 100000.0

## Error codes. Domain errors come back to the agent as an ordinary result with
## `ok: false`; the protocol ones are failures of the bridge itself.
const E_BAD_REQUEST := "bad_request"
const E_UNKNOWN_METHOD := "unknown_method"
const E_FRAME_TOO_LARGE := "frame_too_large"
const E_AUTH_FAILED := "auth_failed"
const E_UNSUPPORTED_VERSION := "unsupported_bridge_version"
const E_INTERNAL := "internal_error"
const E_INVALID_ARGUMENT := "invalid_argument"
const E_NO_EDITED_SCENE := "no_edited_scene"
const E_NO_LEVEL := "no_level"
const E_TARGET_CHANGED := "target_changed"
const E_OPERATION_ID_CONFLICT := "operation_id_conflict"
const E_OPERATION_FAILED := "operation_failed"
const E_LEVEL_EXISTS := "level_exists"
const E_BRUSH_NOT_FOUND := "brush_not_found"
const E_FACE_NOT_FOUND := "face_not_found"
const E_AMBIGUOUS_FACE := "ambiguous_face"
const E_UNSUPPORTED_SHAPE := "unsupported_shape"
const E_UNKNOWN_MATERIAL := "unknown_material"
const E_AMBIGUOUS_MATERIAL := "ambiguous_material"
const E_UNDO_CONFLICT := "undo_conflict"
const E_REDO_CONFLICT := "redo_conflict"
const E_NOTHING_TO_UNDO := "nothing_to_undo"
const E_NOTHING_TO_REDO := "nothing_to_redo"

const _OPERATION_ID_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"


## One message as the bytes that go on the socket.
static func encode_frame(message: Dictionary) -> PackedByteArray:
	var body := JSON.stringify(message).to_utf8_buffer()
	var size := body.size()
	var bytes := PackedByteArray(
		[(size >> 24) & 0xff, (size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff]
	)
	bytes.append_array(body)
	return bytes


static func response_ok(
	id: String, result: Dictionary, revision: int, target_id: String, replayed := false
) -> Dictionary:
	return {
		"type": "response",
		"id": id,
		"ok": true,
		"result": result,
		"revision": revision,
		"target_id": target_id,
		"replayed": replayed,
	}


static func response_error(
	id: String, code: String, message: String, details: Dictionary, revision: int, target_id: String
) -> Dictionary:
	return {
		"type": "response",
		"id": id,
		"ok": false,
		"error": error_body(code, message, details),
		"revision": revision,
		"target_id": target_id,
	}


## A frame that is not an answer to a request: a failed handshake, a frame too
## large to read. The connection is closed after it.
static func error_frame(code: String, message: String, details := {}) -> Dictionary:
	return {"type": "error", "error": error_body(code, message, details)}


static func error_body(code: String, message: String, details := {}) -> Dictionary:
	return {"code": code, "message": message, "details": details}


## What makes two requests "the same" for the operation cache. Keys are sorted, so
## the order the client wrote them in does not matter, and the values are the
## parsed ones, so neither does its number formatting.
static func fingerprint(method: String, params: Dictionary, expect_target: String) -> String:
	# Full precision, so two positions a hair apart are two different requests.
	var canonical := JSON.stringify(
		{"method": method, "params": params, "expect_target": expect_target}, "", true, true
	)
	return canonical.sha256_text()


static func valid_operation_id(value) -> bool:
	if not (value is String):
		return false
	var text := value as String
	if text.is_empty() or text.length() > OPERATION_ID_MAX:
		return false
	for i in text.length():
		if not _OPERATION_ID_CHARS.contains(text[i]):
			return false
	return true


# ---------------------------------------------------------------------------
# Argument readers: {"ok": true, "value": v} or {"ok": false, "error": {...}}
# ---------------------------------------------------------------------------


static func invalid(param: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": error_body(E_INVALID_ARGUMENT, message, {"param": param}),
	}


static func read_vec3(
	params: Dictionary, key: String, required: bool, default := Vector3.ZERO
) -> Dictionary:
	if not params.has(key) or params[key] == null:
		if required:
			return invalid(key, "%s is required: [x, y, z]" % key)
		return {"ok": true, "value": default}
	var raw = params[key]
	if not (raw is Array) or (raw as Array).size() != 3:
		return invalid(key, "%s must be three numbers: [x, y, z]" % key)
	var values: Array[float] = []
	for item in raw:
		# JSON true and false are not numbers, though GDScript would convert them.
		if not (item is float or item is int):
			return invalid(key, "%s must be three numbers: [x, y, z]" % key)
		var number := float(item)
		if not is_finite(number):
			return invalid(key, "%s must be finite" % key)
		if absf(number) > WORLD_LIMIT:
			return invalid(key, "%s is past %d metres" % [key, int(WORLD_LIMIT)])
		values.append(number)
	return {"ok": true, "value": Vector3(values[0], values[1], values[2])}


static func read_positive_vec3(
	params: Dictionary, key: String, required: bool, default := Vector3.ONE
) -> Dictionary:
	var read := read_vec3(params, key, required, default)
	if not read["ok"]:
		return read
	var value: Vector3 = read["value"]
	if value.x <= 0.0 or value.y <= 0.0 or value.z <= 0.0:
		return invalid(key, "%s must be above zero on every axis" % key)
	return read


## A finite number, not true or false, within the world limit.
static func read_number(
	params: Dictionary, key: String, required: bool, default := 0.0
) -> Dictionary:
	if not params.has(key) or params[key] == null:
		if required:
			return invalid(key, "%s is required" % key)
		return {"ok": true, "value": default}
	var raw = params[key]
	if not (raw is float or raw is int):
		return invalid(key, "%s must be a number" % key)
	var number := float(raw)
	if not is_finite(number):
		return invalid(key, "%s must be finite" % key)
	if absf(number) > WORLD_LIMIT:
		return invalid(key, "%s is past %d" % [key, int(WORLD_LIMIT)])
	return {"ok": true, "value": number}


## A whole number from `low` to `high`. JSON numbers arrive as floats, so 3.0
## counts and 3.5 does not.
static func read_int(
	params: Dictionary, key: String, required: bool, default: int, low: int, high: int
) -> Dictionary:
	var read := read_number(params, key, required, float(default))
	if not read["ok"]:
		return read
	var number: float = read["value"]
	if number != floorf(number) or number < low or number > high:
		return invalid(key, "%s must be a whole number from %d to %d" % [key, low, high])
	return {"ok": true, "value": int(number)}


## A list of strings, or `default` when absent.
static func read_string_array(
	params: Dictionary, key: String, required: bool, default: Array = []
) -> Dictionary:
	if not params.has(key) or params[key] == null:
		if required:
			return invalid(key, "%s is required" % key)
		return {"ok": true, "value": default}
	var raw = params[key]
	if not (raw is Array):
		return invalid(key, "%s must be a list of strings" % key)
	for item in raw:
		if not (item is String):
			return invalid(key, "%s must be a list of strings" % key)
	return {"ok": true, "value": raw}


static func read_bool(params: Dictionary, key: String, default: bool) -> Dictionary:
	if not params.has(key) or params[key] == null:
		return {"ok": true, "value": default}
	if not (params[key] is bool):
		return invalid(key, "%s must be true or false" % key)
	return {"ok": true, "value": params[key]}


static func read_string(
	params: Dictionary, key: String, required: bool, default := ""
) -> Dictionary:
	if not params.has(key) or params[key] == null:
		if required:
			return invalid(key, "%s is required" % key)
		return {"ok": true, "value": default}
	if not (params[key] is String):
		return invalid(key, "%s must be a string" % key)
	return {"ok": true, "value": params[key]}


## A vector as JSON, with float noise from a transform round trip taken off so
## a brush placed at 1.5 reads back as 1.5.
static func vec3_to_array(v: Vector3) -> Array:
	return [_clean(v.x), _clean(v.y), _clean(v.z)]


## A vector as JSON when it is one, and null otherwise: for engine calls that
## answer a position or nothing.
static func vec3_or_null(value: Variant) -> Variant:
	if value is Vector3:
		return vec3_to_array(value)
	return null


static func _clean(value: float) -> float:
	var rounded := snappedf(value, 0.000001)
	# Negative zero prints as -0.0 in JSON. It is the same number.
	return 0.0 if is_zero_approx(rounded) else rounded


# ---------------------------------------------------------------------------
# Reading frames off a stream
# ---------------------------------------------------------------------------


## Collects bytes as they arrive and hands back whole messages.
##
## `next()` gives `{"status": "need_more"}` until a frame is complete, then
## `{"status": "frame", "message": {...}}`. A length over `max_bytes` gives
## `{"status": "error", "code": "frame_too_large"}` from the header alone, so a
## hostile 2 GiB header costs four bytes, not a 2 GiB buffer. After an error the
## caller closes the connection; the reader is not usable again.
class FrameReader:
	extends RefCounted

	var max_bytes: int
	var _buffer := PackedByteArray()

	func _init(limit: int) -> void:
		max_bytes = limit

	func feed(bytes: PackedByteArray) -> void:
		_buffer.append_array(bytes)

	func next() -> Dictionary:
		if _buffer.size() < 4:
			return {"status": "need_more"}
		var size: int = (_buffer[0] << 24) | (_buffer[1] << 16) | (_buffer[2] << 8) | _buffer[3]
		if size > max_bytes:
			return {
				"status": "error",
				"code": "frame_too_large",
				"message": "A frame of %d bytes is over the %d byte limit" % [size, max_bytes],
			}
		if _buffer.size() < 4 + size:
			return {"status": "need_more"}
		var body := _buffer.slice(4, 4 + size)
		_buffer = _buffer.slice(4 + size)
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK:
			return {
				"status": "error",
				"code": "bad_request",
				"message": "Not JSON: %s" % json.get_error_message(),
			}
		if not (json.data is Dictionary):
			return {
				"status": "error",
				"code": "bad_request",
				"message": "A frame must hold one JSON object",
			}
		return {"status": "frame", "message": json.data}
