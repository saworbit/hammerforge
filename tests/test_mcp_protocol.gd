extends GutTest

## The MCP bridge's wire format and argument checks. Nothing here touches a
## scene: these are the rules both ends of the socket have to agree on.

const HFMcpProtocol = preload("res://addons/hammerforge/mcp/hf_mcp_protocol.gd")


func _frame_bytes(message: Dictionary) -> PackedByteArray:
	return HFMcpProtocol.encode_frame(message)


func _reader(max_bytes: int = HFMcpProtocol.MAX_REQUEST_BYTES):
	return HFMcpProtocol.FrameReader.new(max_bytes)


# --- Framing ---------------------------------------------------------------


func test_frame_is_big_endian_length_then_utf8_json():
	var bytes := _frame_bytes({"a": "é"})
	var body := JSON.stringify({"a": "é"}).to_utf8_buffer()
	assert_eq(bytes.size(), 4 + body.size())
	assert_eq(bytes[0], 0)
	assert_eq(bytes[1], 0)
	assert_eq(bytes[2], (body.size() >> 8) & 0xff)
	assert_eq(bytes[3], body.size() & 0xff)
	assert_eq(bytes.slice(4), body)


func test_whole_frame_reads_back():
	var reader = _reader()
	reader.feed(_frame_bytes({"type": "hello", "n": 3}))
	var got: Dictionary = reader.next()
	assert_eq(got["status"], "frame")
	assert_eq(got["message"]["type"], "hello")
	assert_eq(int(got["message"]["n"]), 3)
	assert_eq(reader.next()["status"], "need_more")


func test_frame_fed_one_byte_at_a_time_reads_back():
	var reader = _reader()
	var bytes := _frame_bytes({"type": "request", "id": "r1"})
	for i in bytes.size() - 1:
		reader.feed(bytes.slice(i, i + 1))
		assert_eq(reader.next()["status"], "need_more", "byte %d" % i)
	reader.feed(bytes.slice(bytes.size() - 1))
	var got: Dictionary = reader.next()
	assert_eq(got["status"], "frame")
	assert_eq(got["message"]["id"], "r1")


func test_two_frames_in_one_feed_read_back_in_order():
	var reader = _reader()
	var bytes := _frame_bytes({"id": "a"})
	bytes.append_array(_frame_bytes({"id": "b"}))
	reader.feed(bytes)
	assert_eq(reader.next()["message"]["id"], "a")
	assert_eq(reader.next()["message"]["id"], "b")
	assert_eq(reader.next()["status"], "need_more")


func test_declared_length_over_the_limit_fails_before_the_body_arrives():
	var reader = _reader(64)
	# 0x7fffffff, about 2 GiB: refused from the header alone.
	reader.feed(PackedByteArray([0x7f, 0xff, 0xff, 0xff]))
	var got: Dictionary = reader.next()
	assert_eq(got["status"], "error")
	assert_eq(got["code"], "frame_too_large")


func test_invalid_json_is_a_bad_request():
	var reader = _reader()
	var body := "{not json".to_utf8_buffer()
	var bytes := PackedByteArray([0, 0, 0, body.size()])
	bytes.append_array(body)
	reader.feed(bytes)
	var got: Dictionary = reader.next()
	assert_eq(got["status"], "error")
	assert_eq(got["code"], "bad_request")


func test_json_that_is_not_an_object_is_a_bad_request():
	var reader = _reader()
	var body := "[1, 2]".to_utf8_buffer()
	var bytes := PackedByteArray([0, 0, 0, body.size()])
	bytes.append_array(body)
	reader.feed(bytes)
	var got: Dictionary = reader.next()
	assert_eq(got["status"], "error")
	assert_eq(got["code"], "bad_request")


# --- Fingerprint and operation ids -----------------------------------------


func test_fingerprint_ignores_key_order():
	var a := HFMcpProtocol.fingerprint("hf_place_brush", {"x": 1, "y": {"b": 2, "a": 1}}, "t")
	var b := HFMcpProtocol.fingerprint("hf_place_brush", {"y": {"a": 1, "b": 2}, "x": 1}, "t")
	assert_eq(a, b)


func test_fingerprint_changes_with_a_value_method_or_target():
	var base := HFMcpProtocol.fingerprint("hf_place_brush", {"x": 1}, "t")
	assert_ne(base, HFMcpProtocol.fingerprint("hf_place_brush", {"x": 2}, "t"))
	assert_ne(base, HFMcpProtocol.fingerprint("hf_delete_brush", {"x": 1}, "t"))
	assert_ne(base, HFMcpProtocol.fingerprint("hf_place_brush", {"x": 1}, "u"))


func test_operation_id_rules():
	assert_true(HFMcpProtocol.valid_operation_id("op-1.2:3_x"))
	assert_true(HFMcpProtocol.valid_operation_id("a".repeat(128)))
	assert_false(HFMcpProtocol.valid_operation_id(""))
	assert_false(HFMcpProtocol.valid_operation_id("a".repeat(129)))
	assert_false(HFMcpProtocol.valid_operation_id("a b"))
	assert_false(HFMcpProtocol.valid_operation_id("é"))
	assert_false(HFMcpProtocol.valid_operation_id(5))
	assert_false(HFMcpProtocol.valid_operation_id(null))


# --- Argument readers ------------------------------------------------------


func _assert_invalid(result: Dictionary, param: String) -> void:
	assert_false(result["ok"], "expected a refusal for %s" % param)
	if result["ok"]:
		return
	assert_eq(result["error"]["code"], "invalid_argument")
	assert_eq(result["error"]["details"]["param"], param)


func test_read_vec3_accepts_three_numbers():
	var got := HFMcpProtocol.read_vec3({"p": [1, 2.5, -3]}, "p", true)
	assert_true(got["ok"])
	assert_eq(got["value"], Vector3(1, 2.5, -3))


func test_read_vec3_default_when_optional_and_missing():
	var got := HFMcpProtocol.read_vec3({}, "p", false, Vector3(4, 5, 6))
	assert_true(got["ok"])
	assert_eq(got["value"], Vector3(4, 5, 6))


func test_read_vec3_refuses_bad_shapes():
	_assert_invalid(HFMcpProtocol.read_vec3({}, "p", true), "p")
	_assert_invalid(HFMcpProtocol.read_vec3({"p": [1, 2]}, "p", true), "p")
	_assert_invalid(HFMcpProtocol.read_vec3({"p": [1, 2, 3, 4]}, "p", true), "p")
	_assert_invalid(HFMcpProtocol.read_vec3({"p": [1, "2", 3]}, "p", true), "p")
	_assert_invalid(HFMcpProtocol.read_vec3({"p": "x"}, "p", true), "p")
	_assert_invalid(HFMcpProtocol.read_vec3({"p": [1, NAN, 3]}, "p", true), "p")
	_assert_invalid(HFMcpProtocol.read_vec3({"p": [INF, 0, 0]}, "p", true), "p")
	_assert_invalid(HFMcpProtocol.read_vec3({"p": [true, 0, 0]}, "p", true), "p")


func test_read_vec3_refuses_a_number_past_the_world_limit():
	_assert_invalid(HFMcpProtocol.read_vec3({"p": [1e7, 0, 0]}, "p", true), "p")


func test_read_positive_vec3_refuses_zero_and_negative():
	assert_true(HFMcpProtocol.read_positive_vec3({"s": [1, 2, 3]}, "s", true)["ok"])
	_assert_invalid(HFMcpProtocol.read_positive_vec3({"s": [0, 1, 1]}, "s", true), "s")
	_assert_invalid(HFMcpProtocol.read_positive_vec3({"s": [1, -1, 1]}, "s", true), "s")


func test_read_bool_and_string():
	assert_eq(HFMcpProtocol.read_bool({}, "b", true)["value"], true)
	assert_eq(HFMcpProtocol.read_bool({"b": false}, "b", true)["value"], false)
	_assert_invalid(HFMcpProtocol.read_bool({"b": 1}, "b", true), "b")
	assert_eq(HFMcpProtocol.read_string({"s": "box"}, "s", true)["value"], "box")
	assert_eq(HFMcpProtocol.read_string({}, "s", false, "box")["value"], "box")
	_assert_invalid(HFMcpProtocol.read_string({}, "s", true), "s")
	_assert_invalid(HFMcpProtocol.read_string({"s": 3}, "s", true), "s")


# --- Envelopes -------------------------------------------------------------


func test_response_ok_envelope():
	var r := HFMcpProtocol.response_ok("r7", {"a": 1}, 12, "1:2:3")
	assert_eq(r["type"], "response")
	assert_eq(r["id"], "r7")
	assert_true(r["ok"])
	assert_eq(r["result"], {"a": 1})
	assert_eq(r["revision"], 12)
	assert_eq(r["target_id"], "1:2:3")
	assert_false(r["replayed"])


func test_response_error_envelope():
	var r := HFMcpProtocol.response_error("r8", "no_level", "No LevelRoot", {"x": 1}, 4, "1:2:0")
	assert_eq(r["type"], "response")
	assert_eq(r["id"], "r8")
	assert_false(r["ok"])
	assert_eq(r["error"], {"code": "no_level", "message": "No LevelRoot", "details": {"x": 1}})
	assert_eq(r["revision"], 4)


func test_error_frame():
	var f := HFMcpProtocol.error_frame("auth_failed", "Wrong token")
	assert_eq(f["type"], "error")
	assert_eq(f["error"]["code"], "auth_failed")
	assert_eq(f["error"]["details"], {})


func test_vec3_to_array_rounds_float_noise():
	assert_eq(HFMcpProtocol.vec3_to_array(Vector3(1.0000001, -0.0, 2.5)), [1.0, 0.0, 2.5])


# --- Turns in degrees (#1223) ----------------------------------------------


func test_degrees_go_to_a_basis_and_come_back_the_same():
	var turns := [
		Vector3.ZERO,
		Vector3(0, 90, 0),
		Vector3(-90, 0, 0),
		Vector3(20, 30, 10),
		Vector3(-45, 60, 170),
		Vector3(135, -80, -30),
	]
	for degrees in turns:
		var back := HFMcpProtocol.degrees_from_basis(HFMcpProtocol.basis_from_degrees(degrees))
		assert_almost_eq(back, degrees, Vector3.ONE * 0.001, str(degrees))


func test_a_scaled_basis_reads_its_turn_and_not_its_scale():
	var degrees := Vector3(20, 30, 10)
	for scale in [Vector3(2, 2, 2), Vector3(2, 1, 0.5)]:
		var scaled := HFMcpProtocol.basis_from_degrees(degrees) * Basis.from_scale(scale)
		var back := HFMcpProtocol.degrees_from_basis(scaled)
		assert_almost_eq(back, degrees, Vector3.ONE * 0.001, "scaled %s" % str(scale))


func test_the_order_is_x_then_y_then_z_as_the_wire_has_always_had_it():
	var degrees := Vector3(20, 30, 10)
	var radians := Vector3(deg_to_rad(20.0), deg_to_rad(30.0), deg_to_rad(10.0))
	var xyz := Basis.from_euler(radians, EULER_ORDER_XYZ)
	assert_true(HFMcpProtocol.basis_from_degrees(degrees).is_equal_approx(xyz))
	assert_false(
		xyz.is_equal_approx(Basis.from_euler(radians, EULER_ORDER_YXZ)),
		"fixture: a turn whose order shows"
	)
