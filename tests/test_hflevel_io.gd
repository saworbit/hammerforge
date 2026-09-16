extends GutTest

const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")


func before_each():
	HFLog.end_test_capture()


func after_each():
	HFLog.end_test_capture()


func _capture_warning(pattern: String) -> void:
	HFLog.begin_test_capture([pattern])


func _assert_captured_warning(pattern: String) -> void:
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(warnings.size(), 1, "Should capture exactly one warning")
	if warnings.size() > 0:
		assert_string_contains(warnings[0], pattern, "Should capture expected warning text")


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
	_capture_warning("HFLevelIO: Invalid header")
	var parsed = HFLevelIO.parse_payload(bad)
	assert_eq(parsed.size(), 0, "Invalid header returns empty dict")
	_assert_captured_warning("HFLevelIO: Invalid header")


func test_parse_no_newline_returns_empty():
	var no_nl = 'HFLEVEL1{"key":"value"}'.to_utf8_buffer()
	var parsed = HFLevelIO.parse_payload(no_nl)
	assert_eq(parsed.size(), 0, "No newline returns empty dict")


func test_parse_empty_body_returns_empty():
	var empty_body = "HFLEVEL1\n".to_utf8_buffer()
	_capture_warning("HFLevelIO: Empty JSON body in payload")
	var parsed = HFLevelIO.parse_payload(empty_body)
	assert_eq(parsed.size(), 0, "Empty JSON body returns empty dict")
	_assert_captured_warning("HFLevelIO: Empty JSON body in payload")


func test_build_parse_complex_payload():
	var data = {
		"brushes": [{"id": "brush_1", "pos": [1, 2, 3]}, {"id": "brush_2", "pos": [4, 5, 6]}],
		"version": 2,
		"settings": {"grid": 8},
	}
	var payload = HFLevelIO.build_payload(data)
	var parsed = HFLevelIO.parse_payload(payload)
	assert_eq(int(parsed.get("version", 0)), 2)
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
	assert_eq(int(decoded["count"]), 42, "Full pipeline: integer value survives")


func test_compressed_payload_round_trip_and_smaller_than_raw():
	var blob := ""
	for _i in range(80):
		blob += "HammerForge greybox payload padding. "
	var data := {"name": "packed", "blob": blob}
	var raw: PackedByteArray = HFLevelIO.build_payload(data, false)
	var packed: PackedByteArray = HFLevelIO.build_payload(data, true)
	assert_true(packed.size() < raw.size(), "Compressed payload should be smaller than raw JSON")
	var header := packed.slice(0, 9).get_string_from_utf8()
	assert_eq(header, "HFLEVEL1C", "Compressed payload uses HFLEVEL1C header")
	var parsed: Dictionary = HFLevelIO.parse_payload(packed)
	assert_eq(parsed.get("name"), "packed")
	assert_eq(parsed.get("blob"), blob)


func test_uncompressed_payload_keeps_legacy_header():
	var data := {"name": "plain"}
	var payload: PackedByteArray = HFLevelIO.build_payload(data, false)
	var header := payload.slice(0, HFLevelIO.MAGIC.length()).get_string_from_utf8()
	assert_eq(header, HFLevelIO.MAGIC)
	var parsed: Dictionary = HFLevelIO.parse_payload(payload)
	assert_eq(parsed.get("name"), "plain")


func test_save_to_path_is_atomic_and_leaves_no_writing_sidecar():
	var path := "user://hflevel_atomic_test.hflevel"
	var writing := path + ".writing"
	var previous := path + ".previous"
	HFLevelIO.save_to_path(path, {"v": 1}, false)
	HFLevelIO.save_to_path(path, {"v": 2}, false)
	var loaded: Dictionary = HFLevelIO.load_from_path(path)
	assert_eq(int(loaded.get("v", 0)), 2)
	assert_false(FileAccess.file_exists(writing), "Sidecar .writing file should be gone after save")
	assert_false(
		FileAccess.file_exists(previous), "Successful replacement should remove its backup"
	)
	DirAccess.remove_absolute(path)


func test_failed_replacement_restores_valid_destination():
	var path := "user://hflevel_atomic_restore_test.hflevel"
	var missing_tmp := path + ".missing"
	var backup := path + ".previous"
	HFLevelIO.save_to_path(path, {"v": 1}, false)
	var err := HFLevelIO._replace_file_atomic(path, missing_tmp)
	assert_push_error("rename failed")
	assert_ne(err, OK)
	var loaded: Dictionary = HFLevelIO.load_from_path(path)
	assert_eq(int(loaded.get("v", 0)), 1, "Failed replacement must restore the last good save")
	assert_false(FileAccess.file_exists(backup), "Restored backup should return to the main path")
	DirAccess.remove_absolute(path)


func test_replacement_recovers_interrupted_backup_before_writing():
	var path := "user://hflevel_atomic_recovery_test.hflevel"
	var writing := path + ".writing"
	var backup := path + ".previous"
	HFLevelIO.save_to_path(backup, {"v": 1}, false)
	var next_payload := HFLevelIO.build_payload({"v": 2}, false)
	var file := FileAccess.open(writing, FileAccess.WRITE)
	file.store_buffer(next_payload)
	file.close()
	assert_eq(HFLevelIO._replace_file_atomic(path, writing), OK)
	var loaded: Dictionary = HFLevelIO.load_from_path(path)
	assert_eq(int(loaded.get("v", 0)), 2)
	assert_false(FileAccess.file_exists(backup))
	DirAccess.remove_absolute(path)


func test_load_recovers_previous_file_after_interrupted_replacement():
	var path := "user://hflevel_atomic_load_recovery_test.hflevel"
	var backup := path + ".previous"
	HFLevelIO.save_to_path(path, {"v": 1}, false)
	assert_eq(DirAccess.rename_absolute(path, backup), OK)
	var loaded: Dictionary = HFLevelIO.load_from_path(path)
	assert_eq(int(loaded.get("v", 0)), 1)
	assert_true(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(backup))
	DirAccess.remove_absolute(path)


func test_encode_payload_job_returns_hash_and_round_trips():
	var data := {"name": "offthread", "count": 3}
	var job: Dictionary = HFLevelIO.encode_payload_job(data, false)
	assert_true(int(job.get("hash", 0)) != 0, "Job should include a content hash")
	var parsed: Dictionary = HFLevelIO.parse_payload(job.get("payload", PackedByteArray()))
	assert_eq(parsed.get("name"), "offthread")
	assert_eq(int(parsed.get("count", 0)), 3)


func test_encode_payload_job_stable_hash_for_same_data():
	var data := {"a": 1, "b": ["x", "y"]}
	var first: Dictionary = HFLevelIO.encode_payload_job(data, false)
	var second: Dictionary = HFLevelIO.encode_payload_job(data, false)
	assert_eq(int(first.get("hash", 0)), int(second.get("hash", 0)))


func test_encode_payload_job_hash_changes_when_data_changes():
	var a: Dictionary = HFLevelIO.encode_payload_job({"n": 1}, false)
	var b: Dictionary = HFLevelIO.encode_payload_job({"n": 2}, false)
	assert_ne(int(a.get("hash", 0)), int(b.get("hash", 0)))


# ===========================================================================
# What crosses to the write thread (#601)
# ===========================================================================


## A material with a path of its own. Two live Resources claiming one path is a
## cyclic inclusion error in Godot, and the tests here run in one session.
func _a_material(named: bool = true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if named:
		mat.resource_path = "res://hf_test_%d.tres" % Time.get_ticks_usec()
	return mat


func test_resolve_resources_replaces_a_resource_where_it_stands():
	var mat := _a_material()
	var path := mat.resource_path
	var state := {"materials": [mat], "brushes": [{"material": mat, "size": Vector3(2, 2, 2)}]}
	state = HFLevelIO.resolve_resources(state)
	assert_false(HFLevelIO.holds_resource(state), "nothing live is left in the payload")
	assert_eq(state["materials"][0]["path"], path)
	assert_eq(state["brushes"][0]["material"]["path"], path)


func test_resolve_resources_leaves_every_other_value_exactly_as_it_was():
	# It walks the same structure `encode_variant()` does and rebuilds none of it,
	# which is the whole reason it is cheap enough to stay on the calling thread.
	var state := {
		"size": Vector3(2, 2, 2),
		"transform": Transform3D.IDENTITY,
		"nested": [1, "two", {"three": 3.0}],
		"flag": true,
	}
	HFLevelIO.resolve_resources(state)
	assert_eq(state["size"], Vector3(2, 2, 2), "a Vector3 is still a Vector3")
	assert_eq(state["transform"], Transform3D.IDENTITY, "a Transform3D is still a Transform3D")
	assert_eq(state["nested"][2]["three"], 3.0)
	assert_eq(state["flag"], true)


func test_a_resolved_payload_encodes_to_what_the_one_call_version_produces():
	# `capture_hflevel_state()` still exists and still returns the finished
	# structure. Splitting the work in two must not change what lands in the file.
	var mat := _a_material()
	var one := {"materials": [mat], "size": Vector3(1, 2, 3)}
	var two := {"materials": [mat], "size": Vector3(1, 2, 3)}
	var in_one_go: Variant = HFLevelIO.encode_variant(one)
	two = HFLevelIO.resolve_resources(two)
	var in_two_steps: Variant = HFLevelIO.encode_variant(two)
	assert_eq(JSON.stringify(in_two_steps), JSON.stringify(in_one_go), "the same bytes either way")


func test_a_resource_with_no_path_still_becomes_a_named_empty_slot():
	# #617 from the other side. The warning has to happen on the calling thread,
	# where the resource is, rather than inside the worker.
	var state := {"materials": [_a_material(false)]}
	state = HFLevelIO.resolve_resources(state)
	assert_false(HFLevelIO.holds_resource(state))
	assert_eq(state["materials"][0]["class"], "StandardMaterial3D")


func test_a_typed_array_of_resources_is_rebuilt_rather_than_written_through():
	# `MaterialManager.materials` is `Array[Material]`, and a typed array refuses
	# a Dictionary where a Material used to be. Writing through it left the live
	# Resource in place and raised an engine error nobody was reading.
	var mat := _a_material()
	var typed: Array[Material] = [mat]
	var state := {"materials": typed}
	state = HFLevelIO.resolve_resources(state)
	assert_false(HFLevelIO.holds_resource(state), "the material was actually replaced")
	assert_eq(state["materials"][0]["path"], mat.resource_path)


func test_a_typed_array_of_values_is_left_where_it_stands():
	# Only arrays that can hold objects need rebuilding. Colors pass through.
	var tints: Array[Color] = [Color.RED, Color.BLUE]
	var state := {"tints": tints}
	state = HFLevelIO.resolve_resources(state)
	assert_eq(state["tints"][0], Color.RED)
	assert_eq(state["tints"][1], Color.BLUE)
	assert_true(state["tints"] is Array)


func test_holds_resource_finds_one_however_deep_it_is():
	assert_false(HFLevelIO.holds_resource({"a": [1, {"b": "c"}]}), "values only, so no")
	assert_true(HFLevelIO.holds_resource({"a": [1, {"b": _a_material()}]}), "buried in a list")
	assert_true(HFLevelIO.holds_resource([_a_material()]), "at the top of an array")


# ===========================================================================
# encode / decode: the types that used to fall off the end of the match (#619)
# ===========================================================================


func _round_trip_value(value: Variant) -> Variant:
	var payload := HFLevelIO.build_payload({"v": HFLevelIO.encode_variant(value)}, false)
	return HFLevelIO.decode_variant(HFLevelIO.parse_payload(payload).get("v"))


func test_vector2i_survives_the_file():
	var out = _round_trip_value(Vector2i(3, -4))
	assert_true(out is Vector2i, "Vector2i should not come back as a String")
	assert_eq(out, Vector2i(3, -4))


func test_vector3i_survives_the_file():
	var out = _round_trip_value(Vector3i(1, 2, 3))
	assert_true(out is Vector3i, "Vector3i should not come back as a String")
	assert_eq(out, Vector3i(1, 2, 3))


func test_aabb_survives_the_file():
	var out = _round_trip_value(AABB(Vector3(1, 2, 3), Vector3(4, 5, 6)))
	assert_true(out is AABB, "AABB should not come back as a String")
	assert_almost_eq(out.position.y, 2.0, 0.001)
	assert_almost_eq(out.size.z, 6.0, 0.001)


func test_plane_survives_the_file():
	var out = _round_trip_value(Plane(Vector3.UP, 5.0))
	assert_true(out is Plane, "Plane should not come back as a String")
	assert_almost_eq(out.d, 5.0, 0.001)


func test_quaternion_survives_the_file():
	var out = _round_trip_value(Quaternion(0.0, 0.7071, 0.0, 0.7071))
	assert_true(out is Quaternion, "Quaternion should not come back as a String")
	assert_almost_eq(out.y, 0.7071, 0.001)


func test_rect2_and_rect2i_survive_the_file():
	var r = _round_trip_value(Rect2(1, 2, 3, 4))
	assert_true(r is Rect2, "Rect2 should not come back as a String")
	assert_almost_eq(r.size.x, 3.0, 0.001)
	var ri = _round_trip_value(Rect2i(1, 2, 3, 4))
	assert_true(ri is Rect2i, "Rect2i should not come back as a String")
	assert_eq(ri.size.y, 4)


func test_vector4_and_transform2d_survive_the_file():
	var v = _round_trip_value(Vector4(1, 2, 3, 4))
	assert_true(v is Vector4, "Vector4 should not come back as a String")
	assert_almost_eq(v.w, 4.0, 0.001)
	var t = _round_trip_value(Transform2D(0.0, Vector2(7, 8)))
	assert_true(t is Transform2D, "Transform2D should not come back as a String")
	assert_almost_eq(t.origin.x, 7.0, 0.001)


func test_string_name_survives_the_file():
	var out = _round_trip_value(StringName("hello"))
	assert_true(out is StringName, "StringName should not decay to String")
	assert_eq(str(out), "hello")


func test_packed_vector3_array_survives_the_file():
	var out = _round_trip_value(PackedVector3Array([Vector3(1, 1, 1), Vector3(2, 2, 2)]))
	assert_true(out is PackedVector3Array, "PackedVector3Array should not become a String")
	assert_eq(out.size(), 2)
	assert_almost_eq(out[1].x, 2.0, 0.001)


func test_packed_byte_array_survives_the_file():
	var out = _round_trip_value(PackedByteArray([1, 2, 3]))
	assert_true(out is PackedByteArray, "PackedByteArray should not become a String")
	assert_eq(out.size(), 3)
	assert_eq(int(out[2]), 3)


func test_packed_int32_array_survives_as_ints():
	var out = _round_trip_value(PackedInt32Array([4, 5, 6]))
	assert_true(out is PackedInt32Array, "PackedInt32Array should not become a float Array")
	assert_eq(int(out[0]), 4)


func test_types_already_handled_keep_their_on_disk_shape():
	# The added `_` arm must not swallow the types the format already writes, or
	# every file on disk would decode as null.
	assert_eq(HFLevelIO.encode_variant(Vector3(1, 2, 3))[HFLevelIO.TYPE_KEY], "Vector3")
	assert_eq(HFLevelIO.encode_variant(Color.RED)[HFLevelIO.TYPE_KEY], "Color")
	assert_eq(HFLevelIO.encode_variant(42), 42, "int stays a raw JSON number")
	assert_eq(HFLevelIO.encode_variant("s"), "s", "String stays a raw JSON string")
	assert_true(HFLevelIO.encode_variant([1, 2]) is Array, "Array stays an Array")


# ===========================================================================
# encode / decode: Dictionary keys that are not Strings (#619)
# ===========================================================================


func test_non_string_dictionary_keys_survive_the_file():
	var out = _round_trip_value({Vector2i(3, 4): "cell", 7: "int key", "s": "string key"})
	assert_true(out is Dictionary, "Should decode back to a Dictionary")
	assert_eq(out.get(Vector2i(3, 4)), "cell", "A Vector2i key should still be a Vector2i")
	assert_eq(out.get(7), "int key", "An int key should still be an int")
	assert_eq(out.get("s"), "string key", "A String key should be untouched")


func test_all_string_keys_keep_the_plain_json_object_shape():
	var encoded = HFLevelIO.encode_variant({"a": 1, "b": 2})
	assert_false(
		encoded.has(HFLevelIO.TYPE_KEY), "A plain dictionary must stay a plain JSON object"
	)
	assert_eq(encoded.get("a"), 1)


# ===========================================================================
# encode / decode: a Resource with no resource_path (#617)
# ===========================================================================


func test_pathless_resource_warns_and_records_what_was_lost():
	_capture_warning("no resource path")
	var mat := StandardMaterial3D.new()
	mat.resource_name = "runtime_brick"
	var encoded = HFLevelIO.encode_variant(mat)
	_assert_captured_warning("no resource path")
	assert_eq(encoded[HFLevelIO.TYPE_KEY], "MissingResource", "Should record the loss, not null")
	assert_eq(str(encoded.get("class")), "StandardMaterial3D")
	assert_eq(str(encoded.get("name")), "runtime_brick")


func test_pathless_resource_marker_names_it_on_load():
	_capture_warning("runtime_brick")
	var decoded = HFLevelIO.decode_variant(
		{
			HFLevelIO.TYPE_KEY: "MissingResource",
			"class": "StandardMaterial3D",
			"name": "runtime_brick"
		}
	)
	_assert_captured_warning("runtime_brick")
	assert_null(decoded, "The slot is still empty, but the load says what it was")


func test_resource_with_a_path_is_unchanged():
	var mat := StandardMaterial3D.new()
	mat.resource_path = "res://materials/does_not_exist.tres"
	var encoded = HFLevelIO.encode_variant(mat)
	assert_eq(encoded[HFLevelIO.TYPE_KEY], "ResourcePath")
	assert_eq(str(encoded.get("path")), "res://materials/does_not_exist.tres")


func test_values_that_are_not_data_are_dropped_with_a_warning():
	var encoded = HFLevelIO.encode_variant(Callable())
	assert_null(encoded, "A Callable cannot be written to a level file")
