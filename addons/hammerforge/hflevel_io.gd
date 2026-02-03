@tool
extends RefCounted
class_name HFLevelIO

const MAGIC := "HFLEVEL1"
const TYPE_KEY := "__hf_type"

static func encode_variant(value: Variant) -> Variant:
	if value is Resource:
		var res: Resource = value
		var path = res.resource_path
		if path != "":
			return { TYPE_KEY: "ResourcePath", "path": path }
		return null
	match typeof(value):
		TYPE_VECTOR2:
			return { TYPE_KEY: "Vector2", "value": [value.x, value.y] }
		TYPE_VECTOR3:
			return { TYPE_KEY: "Vector3", "value": [value.x, value.y, value.z] }
		TYPE_TRANSFORM3D:
			var origin = value.origin
			var basis = value.basis
			return {
				TYPE_KEY: "Transform3D",
				"origin": [origin.x, origin.y, origin.z],
				"basis": [
					[basis.x.x, basis.x.y, basis.x.z],
					[basis.y.x, basis.y.y, basis.y.z],
					[basis.z.x, basis.z.y, basis.z.z]
				]
			}
		TYPE_BASIS:
			return {
				TYPE_KEY: "Basis",
				"value": [
					[value.x.x, value.x.y, value.x.z],
					[value.y.x, value.y.y, value.y.z],
					[value.z.x, value.z.y, value.z.z]
				]
			}
		TYPE_COLOR:
			return { TYPE_KEY: "Color", "value": value.to_html() }
		TYPE_ARRAY:
			var out: Array = []
			for item in value:
				out.append(encode_variant(item))
			return out
		TYPE_DICTIONARY:
			var dict_out: Dictionary = {}
			for key in value.keys():
				dict_out[key] = encode_variant(value[key])
			return dict_out
		_:
			return value

static func decode_variant(value: Variant) -> Variant:
	if value is Dictionary and value.has(TYPE_KEY):
		var type_name = str(value.get(TYPE_KEY, ""))
		match type_name:
			"Vector2":
				var vec = value.get("value", [])
				return Vector2(vec[0], vec[1]) if vec is Array and vec.size() >= 2 else Vector2.ZERO
			"Vector3":
				var vec3 = value.get("value", [])
				return Vector3(vec3[0], vec3[1], vec3[2]) if vec3 is Array and vec3.size() >= 3 else Vector3.ZERO
			"Transform3D":
				var origin_arr = value.get("origin", [])
				var basis_arr = value.get("basis", [])
				var origin = Vector3(origin_arr[0], origin_arr[1], origin_arr[2]) if origin_arr is Array and origin_arr.size() >= 3 else Vector3.ZERO
				var basis = Basis.IDENTITY
				if basis_arr is Array and basis_arr.size() >= 3:
					basis = Basis(
						Vector3(basis_arr[0][0], basis_arr[0][1], basis_arr[0][2]),
						Vector3(basis_arr[1][0], basis_arr[1][1], basis_arr[1][2]),
						Vector3(basis_arr[2][0], basis_arr[2][1], basis_arr[2][2])
					)
				return Transform3D(basis, origin)
			"Basis":
				var b = value.get("value", [])
				if b is Array and b.size() >= 3:
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
			_:
				return null
	if value is Array:
		var list_out: Array = []
		for item in value:
			list_out.append(decode_variant(item))
		return list_out
	if value is Dictionary:
		var dict_out: Dictionary = {}
		for key in value.keys():
			dict_out[key] = decode_variant(value[key])
		return dict_out
	return value

static func build_payload(data: Dictionary, _compress: bool = true) -> PackedByteArray:
	var json = JSON.stringify(data)
	return build_payload_from_json(json, _compress)

static func build_payload_from_json(json: String, _compress: bool = true) -> PackedByteArray:
	var raw = json.to_utf8_buffer()
	var header = "%s\n" % MAGIC
	var payload = PackedByteArray()
	payload.append_array(header.to_utf8_buffer())
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
	if not header.begins_with(MAGIC):
		return {}
	var body = payload.slice(newline + 1, payload.size())
	var json = body.get_string_from_utf8()
	var data = JSON.parse_string(json)
	return data if data is Dictionary else {}

static func save_to_path(path: String, data: Dictionary, compress: bool = true) -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	var payload = build_payload(data, compress)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ERR_CANT_OPEN
	file.store_buffer(payload)
	return OK

static func load_from_path(path: String) -> Dictionary:
	if path == "":
		return {}
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var payload = file.get_buffer(file.get_length())
	return parse_payload(payload)
