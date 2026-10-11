extends GutTest

## The MCP listener on a real loopback socket, with a client in the same
## process. Both sides are polled frame by frame.

const HFMcpListener = preload("res://addons/hammerforge/mcp/hf_mcp_listener.gd")
const HFMcpDispatcher = preload("res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd")
const HFMcpProtocol = preload("res://addons/hammerforge/mcp/hf_mcp_protocol.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const HostStandIn = preload("res://tests/mcp/mcp_test_host.gd")
const HFMcpPanel = preload("res://addons/hammerforge/ui/hf_mcp_panel.gd")

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


func _level_scene() -> LevelRoot:
	var scene := Node3D.new()
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	scene.add_child(level)
	add_child_autoqfree(scene)
	host.scene = scene
	return level


func _place(id: String, x: float) -> Dictionary:
	return {
		"type": "request",
		"id": id,
		"method": "hf_place_brush",
		"params": {"size": [1, 1, 1], "position": [x, 0.5, 0]},
	}


func test_queued_changes_are_answered_in_order():
	_level_scene()
	host.wait_frames = 3
	listener.start()
	var pair := await _authenticated()
	for i in 3:
		_send(pair[0], _place(["a", "b", "c"][i], i * 4.0))
	var ids := []
	for i in 3:
		ids.append((await _read(pair[0], pair[1])).get("id"))
	assert_eq(ids, ["a", "b", "c"])


func test_status_is_answered_while_a_change_runs():
	_level_scene()
	host.wait_frames = 30
	listener.start()
	var pair := await _authenticated()
	_send(pair[0], _place("slow", 0))
	assert_true(await _until(func(): return listener.state() == HFMcpListener.State.RUNNING))
	_send(pair[0], {"type": "request", "id": "quick", "method": "hf_get_status"})
	var first := await _read(pair[0], pair[1])
	assert_eq(first.get("id"), "quick", "status does not wait behind the change")
	assert_eq(first["result"]["busy"], "hf_place_brush")
	assert_true(float(first["result"]["busy_seconds"]) >= 0.0, "and says for how long")
	var second := await _read(pair[0], pair[1])
	assert_eq(second.get("id"), "slow")
	assert_true(second.get("ok"), str(second))


func test_a_second_client_mid_change_takes_over_and_the_change_still_lands():
	var level := _level_scene()
	host.wait_frames = 20
	listener.start()
	var first := await _authenticated()
	_send(first[0], _place("lost", 0))
	assert_true(await _until(func(): return listener.state() == HFMcpListener.State.RUNNING))
	var second := await _authenticated()
	assert_true(await _closed(first[0]))
	assert_true(await _until(func(): return level._iter_managed_brush_nodes().size() == 1))
	_send(second[0], {"type": "request", "id": "after", "method": "hf_get_status"})
	var reply := await _read(second[0], second[1])
	assert_eq(reply.get("id"), "after", "the lost answer never reaches the new client")
	assert_eq(int(reply["result"]["counts"]["brushes"]), 1)


func test_freeing_the_listener_mid_change_drops_the_answer_safely():
	var level := _level_scene()
	host.wait_frames = 5
	listener.start()
	var pair := await _authenticated()
	_send(pair[0], _place("orphan", 0))
	assert_true(await _until(func(): return listener.state() == HFMcpListener.State.RUNNING))
	remove_child(listener)
	listener.free()
	assert_true(await _until(func(): return HFMcpListener.Job._live.is_empty()))
	assert_eq(level._iter_managed_brush_nodes().size(), 1, "the change itself finished")


func test_a_bad_frame_puts_the_lamp_back_to_listening():
	listener.start()
	var pair := await _authenticated()
	(pair[0] as StreamPeerTCP).put_data(PackedByteArray([0x7f, 0xff, 0xff, 0xff]))
	# Read the refusal first: Godot reports a closed socket only once nothing is
	# left unread on it.
	var reply := await _read(pair[0], pair[1])
	assert_eq(reply["error"]["code"], "frame_too_large")
	assert_true(await _closed(pair[0]))
	assert_true(await _until(func(): return listener.state() == HFMcpListener.State.LISTENING))


func test_a_hello_past_4k_is_refused():
	listener.start()
	var peer := await _connect()
	var reader = HFMcpProtocol.FrameReader.new(HFMcpProtocol.MAX_RESPONSE_BYTES)
	var hello := _hello()
	hello["padding"] = "x".repeat(HFMcpListener.MAX_HELLO_BYTES)
	_send(peer, hello)
	var reply := await _read(peer, reader)
	assert_eq(reply["error"]["code"], "frame_too_large")
	assert_true(await _closed(peer))


func test_the_token_folder_is_closed_to_other_users():
	listener.start()
	var dir := ProjectSettings.globalize_path(DISCOVERY.get_base_dir())
	if OS.get_name() == "Windows":
		var output: Array = []
		OS.execute("icacls", [dir], output, true)
		var acl := "".join(output)
		assert_false(acl.contains("BUILTIN\\Users"), acl)
		assert_false(acl.contains("Everyone"), acl)
		assert_string_contains(acl, OS.get_environment("USERNAME"))
	else:
		var mode := FileAccess.get_unix_permissions(dir)
		assert_eq(mode & 63, 0, "no group or other access: %o" % mode)


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


func test_a_large_answer_reaches_a_slow_reader_whole():
	listener.start()
	var pair := await _authenticated()
	var peer: StreamPeerTCP = pair[0]
	var blob := "x".repeat(5 * 1024 * 1024)
	# The listener's own end of the connection, not the test client's.
	var server_side: StreamPeerTCP = listener._active["peer"]
	listener._send(server_side, {"type": "response", "id": "big", "blob": blob})
	# Read it a little at a time, the way a busy client might, while the
	# listener keeps getting frames.
	var reader = HFMcpProtocol.FrameReader.new(HFMcpProtocol.MAX_RESPONSE_BYTES)
	var got := {}
	var frames := 0
	while frames < 2000:
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			reader.feed(peer.get_data(mini(available, 65536))[1])
		var next: Dictionary = reader.next()
		if next["status"] == "frame":
			got = next["message"]
			break
		frames += 1
		await get_tree().process_frame
	assert_eq(got.get("id"), "big")
	assert_eq(str(got.get("blob", "")).length(), blob.length())
	assert_true(await _until(func(): return listener._outbox.is_empty()), "all of it went")


func test_a_client_that_stops_reading_is_let_go_past_the_outbox_cap():
	listener.max_outbox_bytes = 4 << 20
	listener.start()
	var pair := await _authenticated()
	var peer: StreamPeerTCP = pair[0]
	var server_side: StreamPeerTCP = listener._active["peer"]
	var chunk := "x".repeat(1 << 20)
	# The client reads nothing. The socket's own buffers take some; past them the
	# outbox grows, and past the cap the listener lets the client go.
	var sent := 0
	while sent < 64 and server_side.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		listener._send(server_side, {"type": "response", "id": "r%d" % sent, "blob": chunk})
		sent += 1
		await get_tree().process_frame
	assert_ne(server_side.get_status(), StreamPeerTCP.STATUS_CONNECTED, "let go")
	assert_lt(sent, 64, "within the socket's buffers and the cap")
	assert_true(listener._outbox.is_empty(), "nothing held for it")
	peer.disconnect_from_host()


var _finished: Array = []


func _on_finished(method: String, ok: bool, code: String, ms: int) -> void:
	_finished.append([method, ok, code, ms])


func test_each_answered_command_is_reported():
	_level_scene()
	listener.start()
	_finished = []
	listener.command_finished.connect(_on_finished)
	var pair := await _authenticated()
	_send(pair[0], _place("good", 0))
	assert_true((await _read(pair[0], pair[1])).get("ok"))
	var missing := {
		"type": "request",
		"id": "bad",
		"method": "hf_delete_brush",
		"params": {"brush_id": "no_such_brush"},
	}
	_send(pair[0], missing)
	assert_false((await _read(pair[0], pair[1])).get("ok"))
	listener.command_finished.disconnect(_on_finished)
	assert_eq(_finished.size(), 2, str(_finished))
	assert_eq(_finished[0].slice(0, 3), ["hf_place_brush", true, ""])
	assert_gte(int(_finished[0][3]), 0)
	assert_eq(_finished[1].slice(0, 3), ["hf_delete_brush", false, "brush_not_found"])


func _status(id: String) -> Dictionary:
	return {"type": "request", "id": id, "method": "hf_get_status"}


## Two frames in one write, as the bridge's client sends calls back to back.
func _send_both(peer: StreamPeerTCP, first: Dictionary, second: Dictionary) -> void:
	var bytes := HFMcpProtocol.encode_frame(first)
	bytes.append_array(HFMcpProtocol.encode_frame(second))
	peer.put_data(bytes)


func test_status_sent_with_a_change_in_one_write_does_not_wait_for_it():
	# Both were read in one frame, before the change had started, so the status
	# was queued behind it and answered after it (#1049).
	_level_scene()
	host.wait_frames = 30
	listener.start()
	var pair := await _authenticated()
	_send_both(pair[0], _place("slow", 0), _status("quick"))
	var first := await _read(pair[0], pair[1])
	assert_eq(first.get("id"), "quick", "status is answered as it is read")
	assert_eq(first["result"]["busy"], "hf_place_brush", "and says the change is running")
	var second := await _read(pair[0], pair[1])
	assert_eq(second.get("id"), "slow")
	assert_true(second.get("ok"), str(second))


func test_status_after_a_quick_change_in_one_write_sees_it():
	_level_scene()
	listener.start()
	var pair := await _authenticated()
	_send_both(pair[0], _place("fast", 0), _status("after"))
	var replies := {}
	for i in 2:
		var reply := await _read(pair[0], pair[1])
		replies[reply.get("id")] = reply
	assert_true(replies.has("after"), str(replies.keys()))
	if replies.has("after"):
		assert_eq(int(replies["after"]["result"]["counts"]["brushes"]), 1, "the change came first")


class EmptyAnswers:
	extends "res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd"

	func handle(request: Dictionary) -> Dictionary:
		if request.get("method") == "hf_place_brush":
			return {}
		return await super(request)


func test_a_script_error_answer_is_reported_as_one():
	# A typed dispatcher function that errors returns {}. The listener answers
	# internal_error, and the panel says the command hit a script error (#1053).
	_level_scene()
	listener.dispatcher = EmptyAnswers.new(host)
	listener.start()
	_finished = []
	listener.command_finished.connect(_on_finished)
	var panel := HFMcpPanel.new()
	add_child_autoqfree(panel)
	listener.command_finished.connect(panel.show_last)
	var pair := await _authenticated()
	_send(pair[0], _place("broken", 0))
	var reply := await _read(pair[0], pair[1])
	listener.command_finished.disconnect(_on_finished)
	listener.dispatcher.shutdown()
	listener.dispatcher = dispatcher
	assert_eq(reply["error"]["code"], "internal_error", str(reply))
	assert_eq(_finished.size(), 1, str(_finished))
	if _finished.size() == 1:
		assert_eq(_finished[0].slice(0, 3), ["hf_place_brush", false, "internal_error"])
	assert_string_contains(panel.last_label.text, "hit a script error")


func test_an_answer_that_lands_after_stop_is_not_reported():
	# Unticking stops the listener while a command is still in flight; its answer
	# has nowhere to go, and a report would put a Last line back on a panel that
	# was just cleared (#1053).
	_level_scene()
	host.wait_frames = 10
	listener.start()
	_finished = []
	listener.command_finished.connect(_on_finished)
	var pair := await _authenticated()
	_send(pair[0], _place("late", 0))
	assert_true(await _until(func(): return listener.state() == HFMcpListener.State.RUNNING))
	listener.stop()
	assert_true(await _until(func(): return HFMcpListener.Job._live.is_empty()))
	listener.command_finished.disconnect(_on_finished)
	assert_eq(_finished, [], "nothing reported after stop()")
