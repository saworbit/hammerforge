extends GutTest

## The MCP listener on a real loopback socket, with a client in the same
## process. Both sides are polled frame by frame.

const HFMcpListener = preload("res://addons/hammerforge/mcp/hf_mcp_listener.gd")
const HFMcpDispatcher = preload("res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd")
const HFMcpProtocol = preload("res://addons/hammerforge/mcp/hf_mcp_protocol.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const HostStandIn = preload("res://tests/mcp/mcp_test_host.gd")

const DISCOVERY := "user://mcp_listener_test/hammerforge_mcp.json"

var undo
var host: HostStandIn
var dispatcher
var listener
var _clients: Array[StreamPeerTCP] = []


func before_each() -> void:
	undo = UndoStandIn.new()
	host = HostStandIn.new()
	host.undo = undo
	host.tree = get_tree()
	dispatcher = HFMcpDispatcher.new(host)
	listener = HFMcpListener.new()
	listener.dispatcher = dispatcher
	listener.discovery_path = DISCOVERY
	listener.allow_outside_editor = true
	add_child_autoqfree(listener)


func after_each() -> void:
	for client in _clients:
		client.disconnect_from_host()
	_clients.clear()
	if is_instance_valid(listener):
		listener.stop()
	dispatcher.shutdown()
	undo.free_histories()


func _discovery() -> Dictionary:
	var text := FileAccess.get_file_as_string(DISCOVERY)
	var json := JSON.new()
	if text == "" or json.parse(text) != OK:
		return {}
	return json.data


func _until(condition: Callable, max_frames := 300) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _connect() -> StreamPeerTCP:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", listener.port())
	_clients.append(peer)
	await _until(
		func():
			peer.poll()
			return peer.get_status() == StreamPeerTCP.STATUS_CONNECTED
	)
	return peer


func _send(peer: StreamPeerTCP, message: Dictionary) -> void:
	peer.put_data(HFMcpProtocol.encode_frame(message))


## The next frame from the listener, or {} if none comes.
func _read(peer: StreamPeerTCP, reader) -> Dictionary:
	var got := {}
	await _until(
		func():
			peer.poll()
			var available := peer.get_available_bytes()
			if available > 0:
				reader.feed(peer.get_data(available)[1])
			var next: Dictionary = reader.next()
			if next["status"] == "frame":
				got.merge(next["message"])
				return true
			return false
	)
	return got


func _closed(peer: StreamPeerTCP) -> bool:
	return await _until(
		func():
			peer.poll()
			return peer.get_status() != StreamPeerTCP.STATUS_CONNECTED
	)


func _hello(token: String = "", version := 1) -> Dictionary:
	return {
		"type": "hello",
		"bridge_version": version,
		"token": token if token != "" else str(_discovery().get("token", "")),
		"client": {"name": "test", "version": "0"},
	}


func _authenticated() -> Array:
	var peer := await _connect()
	var reader = HFMcpProtocol.FrameReader.new(HFMcpProtocol.MAX_RESPONSE_BYTES)
	_send(peer, _hello())
	var welcome := await _read(peer, reader)
	assert_eq(welcome.get("type"), "welcome", str(welcome))
	return [peer, reader]


# --- Start and stop --------------------------------------------------------


func test_start_writes_the_discovery_file_and_stop_removes_it():
	assert_eq(listener.start(), OK)
	assert_gt(listener.port(), 0)
	var found := _discovery()
	assert_eq(int(found.get("port", 0)), listener.port())
	assert_eq(int(found.get("pid", 0)), OS.get_process_id())
	assert_eq(int(found.get("bridge_version", 0)), HFMcpProtocol.BRIDGE_VERSION)
	var token := str(found.get("token", ""))
	assert_eq(token.length(), 64)
	assert_true(token.is_valid_hex_number())
	assert_eq(listener.state(), HFMcpListener.State.LISTENING)
	listener.stop()
	assert_false(FileAccess.file_exists(DISCOVERY))
	assert_eq(listener.state(), HFMcpListener.State.OFF)
	assert_eq(listener.start(), OK)
	assert_ne(str(_discovery().get("token", "")), token, "a new token each time")


func test_start_outside_the_editor_is_refused_without_the_test_switch():
	listener.allow_outside_editor = false
	assert_eq(listener.start(), ERR_UNAVAILABLE)
	assert_false(FileAccess.file_exists(DISCOVERY))
	assert_eq(listener.port(), 0)


func test_leaving_the_tree_stops_it():
	assert_eq(listener.start(), OK)
	remove_child(listener)
	assert_false(FileAccess.file_exists(DISCOVERY))
	add_child(listener)


# --- Handshake -------------------------------------------------------------


func test_a_wrong_token_is_refused_and_closed():
	listener.start()
	var peer := await _connect()
	var reader = HFMcpProtocol.FrameReader.new(HFMcpProtocol.MAX_RESPONSE_BYTES)
	_send(peer, _hello("0".repeat(64)))
	var reply := await _read(peer, reader)
	assert_eq(reply.get("type"), "error")
	assert_eq(reply["error"]["code"], "auth_failed")
	assert_false(JSON.stringify(reply).contains(str(_discovery()["token"])), "no token in errors")
	assert_true(await _closed(peer))


func test_no_hello_in_time_is_closed():
	listener.handshake_timeout_ms = 200
	listener.start()
	var peer := await _connect()
	assert_true(await _closed(peer))


func test_an_unsupported_bridge_version_is_refused():
	listener.start()
	var peer := await _connect()
	var reader = HFMcpProtocol.FrameReader.new(HFMcpProtocol.MAX_RESPONSE_BYTES)
	_send(peer, _hello("", 99))
	var reply := await _read(peer, reader)
	assert_eq(reply["error"]["code"], "unsupported_bridge_version")
	assert_eq(reply["error"]["details"]["supported"], [1.0])


func test_a_request_before_the_hello_is_refused():
	listener.start()
	var peer := await _connect()
	var reader = HFMcpProtocol.FrameReader.new(HFMcpProtocol.MAX_RESPONSE_BYTES)
	_send(peer, {"type": "request", "id": "a", "method": "hf_get_status"})
	var reply := await _read(peer, reader)
	assert_eq(reply["error"]["code"], "bad_request")
	assert_true(await _closed(peer))


func test_welcome_names_the_editor():
	listener.start()
	var pair := await _authenticated()
	assert_eq(listener.state(), HFMcpListener.State.CONNECTED)
	(pair[0] as StreamPeerTCP).disconnect_from_host()
	await _until(func(): return listener.state() == HFMcpListener.State.LISTENING)
	assert_eq(listener.state(), HFMcpListener.State.LISTENING)


# --- Requests --------------------------------------------------------------


func test_status_round_trip_echoes_the_string_id():
	listener.start()
	var pair := await _authenticated()
	_send(pair[0], {"type": "request", "id": "s-1", "method": "hf_get_status", "params": {}})
	var reply := await _read(pair[0], pair[1])
	assert_eq(reply.get("type"), "response")
	assert_eq(reply.get("id"), "s-1")
	assert_true(reply.get("ok"))


func test_requests_are_answered_in_order():
	listener.start()
	var pair := await _authenticated()
	for id in ["a", "b", "c"]:
		_send(pair[0], {"type": "request", "id": id, "method": "hf_get_status"})
	var ids := []
	for i in 3:
		ids.append((await _read(pair[0], pair[1])).get("id"))
	assert_eq(ids, ["a", "b", "c"])


func test_place_through_the_socket_makes_one_brush():
	var scene := Node3D.new()
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	scene.add_child(level)
	add_child_autoqfree(scene)
	host.scene = scene
	listener.start()
	var pair := await _authenticated()
	var place := {
		"type": "request",
		"id": "p",
		"method": "hf_place_brush",
		"params": {"size": [2, 2, 2], "position": [0, 1, 0]},
		"operation_id": "socket-1",
	}
	_send(pair[0], place)
	var first := await _read(pair[0], pair[1])
	assert_true(first.get("ok"), str(first))
	_send(pair[0], place)
	var second := await _read(pair[0], pair[1])
	assert_true(second.get("replayed"))
	assert_eq(level._iter_managed_brush_nodes().size(), 1)


func test_a_frame_over_the_limit_is_refused_and_closed():
	listener.start()
	var pair := await _authenticated()
	var peer: StreamPeerTCP = pair[0]
	peer.put_data(PackedByteArray([0x7f, 0xff, 0xff, 0xff]))
	var reply := await _read(peer, pair[1])
	assert_eq(reply["error"]["code"], "frame_too_large")
	assert_true(await _closed(peer))


func test_a_frame_that_is_not_a_request_gets_bad_request():
	listener.start()
	var pair := await _authenticated()
	_send(pair[0], {"type": "chat", "id": "z"})
	var reply := await _read(pair[0], pair[1])
	assert_eq(reply.get("type"), "response")
	assert_eq(reply.get("id"), "z")
	assert_eq(reply["error"]["code"], "bad_request")


func test_a_second_client_replaces_the_first():
	listener.start()
	var first := await _authenticated()
	var second := await _authenticated()
	assert_true(await _closed(first[0]))
	_send(second[0], {"type": "request", "id": "after", "method": "hf_get_status"})
	var reply := await _read(second[0], second[1])
	assert_eq(reply.get("id"), "after")
