extends GutTest

const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")

# ===========================================================================
# encode / decode: Vector2
# ===========================================================================


func test_encode_decode_vector2():
	var v = Vector2(1.5, -3.25)
	var encoded = HFLevelIO.encode_variant(v)
	assert_eq(encoded[HFLevelIO.TYPE_KEY], "Vector2")
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_almost_eq(decoded.x, 1.5, 0.001, "Vector2.x round-trip")
	assert_almost_eq(decoded.y, -3.25, 0.001, "Vector2.y round-trip")


func test_encode_decode_vector2_zero():
	var v = Vector2.ZERO
	var encoded = HFLevelIO.encode_variant(v)
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_almost_eq(decoded.x, 0.0, 0.001, "Vector2.ZERO.x")
	assert_almost_eq(decoded.y, 0.0, 0.001, "Vector2.ZERO.y")


# ===========================================================================
# encode / decode: Vector3
# ===========================================================================


func test_encode_decode_vector3():
	var v = Vector3(10.0, -20.5, 0.75)
	var encoded = HFLevelIO.encode_variant(v)
	assert_eq(encoded[HFLevelIO.TYPE_KEY], "Vector3")
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_almost_eq(decoded.x, 10.0, 0.001, "Vector3.x round-trip")
	assert_almost_eq(decoded.y, -20.5, 0.001, "Vector3.y round-trip")
	assert_almost_eq(decoded.z, 0.75, 0.001, "Vector3.z round-trip")


func test_encode_decode_vector3_zero():
	var v = Vector3.ZERO
	var encoded = HFLevelIO.encode_variant(v)
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_almost_eq(decoded.x, 0.0, 0.001)
	assert_almost_eq(decoded.y, 0.0, 0.001)
	assert_almost_eq(decoded.z, 0.0, 0.001)


# ===========================================================================
# encode / decode: Transform3D
# ===========================================================================


func test_encode_decode_transform3d():
	var t = Transform3D(Basis.IDENTITY, Vector3(5, 10, 15))
	var encoded = HFLevelIO.encode_variant(t)
	assert_eq(encoded[HFLevelIO.TYPE_KEY], "Transform3D")
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_almost_eq(decoded.origin.x, 5.0, 0.001, "Transform3D origin.x")
	assert_almost_eq(decoded.origin.y, 10.0, 0.001, "Transform3D origin.y")
	assert_almost_eq(decoded.origin.z, 15.0, 0.001, "Transform3D origin.z")


func test_encode_decode_transform3d_rotated():
	var basis = Basis(Vector3(0, 1, 0), deg_to_rad(45))
	var t = Transform3D(basis, Vector3(1, 2, 3))
	var encoded = HFLevelIO.encode_variant(t)
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_almost_eq(decoded.origin.x, 1.0, 0.001, "Rotated origin.x")
	assert_almost_eq(decoded.basis.x.x, basis.x.x, 0.001, "Basis.x.x preserved")
	assert_almost_eq(decoded.basis.y.y, basis.y.y, 0.001, "Basis.y.y preserved")
	assert_almost_eq(decoded.basis.z.z, basis.z.z, 0.001, "Basis.z.z preserved")


# ===========================================================================
# encode / decode: Basis
# ===========================================================================


func test_encode_decode_basis_identity():
	var b = Basis.IDENTITY
	var encoded = HFLevelIO.encode_variant(b)
	assert_eq(encoded[HFLevelIO.TYPE_KEY], "Basis")
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_almost_eq(decoded.x.x, 1.0, 0.001, "Basis identity x.x")
	assert_almost_eq(decoded.y.y, 1.0, 0.001, "Basis identity y.y")
	assert_almost_eq(decoded.z.z, 1.0, 0.001, "Basis identity z.z")
	assert_almost_eq(decoded.x.y, 0.0, 0.001, "Basis identity x.y")


func test_encode_decode_basis_rotated():
	var b = Basis(Vector3(0, 0, 1), deg_to_rad(90))
	var encoded = HFLevelIO.encode_variant(b)
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_almost_eq(decoded.x.x, b.x.x, 0.001, "Rotated basis x.x")
	assert_almost_eq(decoded.x.y, b.x.y, 0.001, "Rotated basis x.y")
	assert_almost_eq(decoded.y.x, b.y.x, 0.001, "Rotated basis y.x")
	assert_almost_eq(decoded.y.y, b.y.y, 0.001, "Rotated basis y.y")


# ===========================================================================
# encode / decode: Color
# ===========================================================================


func test_encode_decode_color():
	var c = Color(0.5, 0.25, 0.75, 1.0)
	var encoded = HFLevelIO.encode_variant(c)
	assert_eq(encoded[HFLevelIO.TYPE_KEY], "Color")
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_almost_eq(decoded.r, 0.5, 0.02, "Color.r round-trip")
	assert_almost_eq(decoded.g, 0.25, 0.02, "Color.g round-trip")
	assert_almost_eq(decoded.b, 0.75, 0.02, "Color.b round-trip")


func test_encode_decode_color_red():
	var c = Color.RED
	var encoded = HFLevelIO.encode_variant(c)
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_almost_eq(decoded.r, 1.0, 0.02, "Red.r")
	assert_almost_eq(decoded.g, 0.0, 0.02, "Red.g")
	assert_almost_eq(decoded.b, 0.0, 0.02, "Red.b")


# ===========================================================================
# encode / decode: primitives (passthrough)
# ===========================================================================


func test_encode_passthrough_int():
	var encoded = HFLevelIO.encode_variant(42)
	assert_eq(encoded, 42, "Int should pass through")


func test_encode_passthrough_float():
	var encoded = HFLevelIO.encode_variant(3.14)
	assert_almost_eq(encoded, 3.14, 0.001, "Float should pass through")


func test_encode_passthrough_string():
	var encoded = HFLevelIO.encode_variant("hello")
	assert_eq(encoded, "hello", "String should pass through")


func test_encode_passthrough_bool():
	assert_eq(HFLevelIO.encode_variant(true), true, "True should pass through")
	assert_eq(HFLevelIO.encode_variant(false), false, "False should pass through")


func test_decode_passthrough_int():
	var decoded = HFLevelIO.decode_variant(99)
	assert_eq(decoded, 99, "Int should decode as-is")


func test_decode_passthrough_string():
	var decoded = HFLevelIO.decode_variant("world")
	assert_eq(decoded, "world", "String should decode as-is")


# ===========================================================================
# encode / decode: Array (recursive)
# ===========================================================================


func test_encode_decode_array_of_vectors():
	var arr = [Vector2(1, 2), Vector3(3, 4, 5)]
	var encoded = HFLevelIO.encode_variant(arr)
	assert_eq(encoded.size(), 2, "Array size preserved")
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_true(decoded[0] is Vector2, "First element is Vector2")
	assert_true(decoded[1] is Vector3, "Second element is Vector3")
	assert_almost_eq(decoded[0].x, 1.0, 0.001, "Array[0].x")
	assert_almost_eq(decoded[1].z, 5.0, 0.001, "Array[1].z")


func test_encode_decode_mixed_array():
	var arr = [42, "hello", Vector3(1, 2, 3), true]
	var encoded = HFLevelIO.encode_variant(arr)
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_eq(decoded[0], 42)
	assert_eq(decoded[1], "hello")
	assert_true(decoded[2] is Vector3)
	assert_eq(decoded[3], true)


# ===========================================================================
# encode / decode: Dictionary (recursive)
# ===========================================================================


func test_encode_decode_dict_with_vectors():
	var dict = {"pos": Vector3(1, 2, 3), "scale": Vector2(4, 5), "name": "test"}
	var encoded = HFLevelIO.encode_variant(dict)
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_true(decoded["pos"] is Vector3, "Dict pos is Vector3")
	assert_true(decoded["scale"] is Vector2, "Dict scale is Vector2")
	assert_eq(decoded["name"], "test", "Dict string preserved")
	assert_almost_eq(decoded["pos"].x, 1.0, 0.001)


func test_encode_decode_nested_dict():
	var dict = {"outer": {"inner": Vector3(7, 8, 9)}}
	var encoded = HFLevelIO.encode_variant(dict)
	var decoded = HFLevelIO.decode_variant(encoded)
	assert_true(decoded["outer"] is Dictionary, "Nested dict preserved")
	assert_true(decoded["outer"]["inner"] is Vector3, "Deeply nested Vector3")
	assert_almost_eq(decoded["outer"]["inner"].y, 8.0, 0.001)


# ===========================================================================
# encode / decode: edge cases
# ===========================================================================


func test_encode_null_returns_null():
	var encoded = HFLevelIO.encode_variant(null)
	assert_null(encoded, "Null should encode as null")


func test_decode_unknown_type_key_returns_null():
	var dict = {HFLevelIO.TYPE_KEY: "UnknownType", "value": 123}
	var decoded = HFLevelIO.decode_variant(dict)
	assert_null(decoded, "Unknown type key should decode to null")


func test_decode_vector2_missing_value_returns_zero():
	var dict = {HFLevelIO.TYPE_KEY: "Vector2", "value": []}
	var decoded = HFLevelIO.decode_variant(dict)
	assert_almost_eq(decoded.x, 0.0, 0.001, "Missing value returns ZERO")
	assert_almost_eq(decoded.y, 0.0, 0.001)


func test_decode_vector3_missing_value_returns_zero():
	var dict = {HFLevelIO.TYPE_KEY: "Vector3", "value": [1.0]}
	var decoded = HFLevelIO.decode_variant(dict)
	assert_almost_eq(decoded.x, 0.0, 0.001, "Short array returns ZERO")


# ===========================================================================
# build_payload / parse_payload
# ===========================================================================


func test_build_parse_payload_round_trip():
	var data = {"version": 1, "name": "test_level"}
	var payload = HFLevelIO.build_payload(data)
	assert_true(payload.size() > 0, "Payload should not be empty")
	var parsed = HFLevelIO.parse_payload(payload)
	assert_eq(parsed.get("name"), "test_level", "Name preserved in payload")


func test_payload_starts_with_magic():
	var data = {"key": "value"}
	var payload = HFLevelIO.build_payload(data)
	var header = payload.slice(0, HFLevelIO.MAGIC.length()).get_string_from_utf8()
	assert_eq(header, HFLevelIO.MAGIC, "Payload starts with magic header")


func test_parse_empty_payload_returns_empty():
	var parsed = HFLevelIO.parse_payload(PackedByteArray())
	assert_eq(parsed.size(), 0, "Empty payload returns empty dict")


func test_parse_invalid_header_returns_empty():
	var bad = 'BADHEADER\n{"key":"value"}'.to_utf8_buffer()
	var parsed = HFLevelIO.parse_payload(bad)
	assert_eq(parsed.size(), 0, "Invalid header returns empty dict")


func test_parse_no_newline_returns_empty():
	var no_nl = 'HFLEVEL1{"key":"value"}'.to_utf8_buffer()
	var parsed = HFLevelIO.parse_payload(no_nl)
	assert_eq(parsed.size(), 0, "No newline returns empty dict")


func test_parse_empty_body_returns_empty():
	var empty_body = "HFLEVEL1\n".to_utf8_buffer()
	var parsed = HFLevelIO.parse_payload(empty_body)
	assert_eq(parsed.size(), 0, "Empty JSON body returns empty dict")


func test_build_parse_complex_payload():
	var data = {
		"brushes": [{"id": "brush_1", "pos": [1, 2, 3]}, {"id": "brush_2", "pos": [4, 5, 6]}],
		"version": 2,
		"settings": {"grid": 8},
	}
	var payload = HFLevelIO.build_payload(data)
	var parsed = HFLevelIO.parse_payload(payload)
	assert_eq(parsed.get("version"), 2)
	var brushes = parsed.get("brushes", [])
	assert_eq(brushes.size(), 2, "Brushes array preserved")
	assert_eq(brushes[0].get("id"), "brush_1")


# ===========================================================================
# Full encode → build → parse → decode pipeline
# ===========================================================================


func test_full_pipeline_round_trip():
	var original = {
		"pos": Vector3(10, 20, 30),
		"scale": Vector2(2, 3),
		"color": Color.BLUE,
		"name": "level_1",
		"count": 42,
	}
	var encoded = HFLevelIO.encode_variant(original)
	var payload = HFLevelIO.build_payload(encoded)
	var parsed = HFLevelIO.parse_payload(payload)
	var decoded = HFLevelIO.decode_variant(parsed)
	assert_true(decoded["pos"] is Vector3, "Full pipeline: Vector3 survives")
	assert_almost_eq(decoded["pos"].x, 10.0, 0.001, "Full pipeline: pos.x")
	assert_true(decoded["scale"] is Vector2, "Full pipeline: Vector2 survives")
	assert_almost_eq(decoded["scale"].y, 3.0, 0.001, "Full pipeline: scale.y")
	assert_true(decoded["color"] is Color, "Full pipeline: Color survives")
	assert_eq(decoded["name"], "level_1", "Full pipeline: string survives")
	assert_eq(decoded["count"], 42, "Full pipeline: int survives")
