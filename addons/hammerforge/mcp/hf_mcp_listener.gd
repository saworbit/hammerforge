@tool
class_name HFMcpListener
extends Node
## The editor end of the MCP bridge: a loopback socket the Python server talks to.
##
## Off until the user ticks "Allow agent connections" in the Test tab, and off
## again at every editor start. Only the plugin makes one, and `start()` refuses
## outside the editor, so a game export carries the script and never runs it.
##
## Everything happens on the main thread. Godot's sockets do not block, so
## `_process` polls for connections and bytes, and the dispatcher runs one
## command at a time from a queue. A command that awaits (a bake, a screenshot)
## holds the queue until it is done; `hf_get_status` is answered straight away
## even then, so an agent can see the editor is busy.
##
## On start it writes `res://.godot/hammerforge_mcp.json` with the port, this
## editor's pid and a new token, and deletes it on stop. `.godot/` is in Godot's
## own `.gitignore` and never goes into an export, so the token cannot be
## committed or shipped by accident. The protocol is in
## `docs/superpowers/specs/2026-10-11-mcp-bridge-design.md`.

enum State { OFF, LISTENING, CONNECTED, RUNNING, FAILED }

signal state_changed(state: int, detail: String)

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFMcpProtocol = preload("hf_mcp_protocol.gd")
const HFMcpDispatcher = preload("hf_mcp_dispatcher.gd")
@warning_ignore_restore("shadowed_global_identifier")

const DISCOVERY_PATH := "res://.godot/hammerforge_mcp.json"
const HANDSHAKE_TIMEOUT_MS := 5000
const BIND_ADDRESS := "127.0.0.1"

## Owner read and write only, 0o600, where the platform has unix permissions.
const DISCOVERY_PERMISSIONS := 384

var dispatcher: HFMcpDispatcher
var discovery_path := DISCOVERY_PATH
var handshake_timeout_ms := HANDSHAKE_TIMEOUT_MS
## Lets a test or the bridge smoke script run it without the editor. Nothing a
## game runs sets it.
var allow_outside_editor := false

var _server: TCPServer = null
var _token := ""
## Connections that have not said hello yet: {peer, reader, deadline}.
var _pending: Array[Dictionary] = []
## The one authenticated connection: {peer, reader}, or empty.
var _active: Dictionary = {}
## Requests waiting their turn: {peer, request}.
var _queue: Array[Dictionary] = []
var _running := false
var _state: int = State.OFF


func _ready() -> void:
	set_process(_server != null)


func _exit_tree() -> void:
	stop()


func state() -> int:
	return _state


func port() -> int:
	return _server.get_local_port() if _server != null else 0


func start() -> int:
	if _server != null:
		return OK
	if not (Engine.is_editor_hint() or allow_outside_editor):
		return ERR_UNAVAILABLE
	if dispatcher == null:
		return ERR_UNCONFIGURED
	_server = TCPServer.new()
	var err: int = _server.listen(0, BIND_ADDRESS)
	if err != OK:
		_server = null
		_set_state(State.FAILED, "Could not open a port: %s" % error_string(err))
		return err
	_token = Crypto.new().generate_random_bytes(32).hex_encode()
	err = _write_discovery()
	if err != OK:
		stop()
		_set_state(State.FAILED, "Could not write %s: %s" % [discovery_path, error_string(err)])
		return err
	set_process(true)
	_set_state(State.LISTENING, "Listening on %s:%d" % [BIND_ADDRESS, port()])
	return OK


func stop() -> void:
	set_process(false)
	for entry in _pending:
		(entry["peer"] as StreamPeerTCP).disconnect_from_host()
	_pending.clear()
	if not _active.is_empty():
		(_active["peer"] as StreamPeerTCP).disconnect_from_host()
	_active = {}
	_queue.clear()
	var was_on := _server != null
	if _server != null:
		_server.stop()
		_server = null
	_token = ""
	if was_on:
		_remove_discovery()
	_set_state(State.OFF, "Off")


func _process(_delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		peer.set_no_delay(true)
		var entry := {
			"peer": peer,
			"reader": HFMcpProtocol.FrameReader.new(HFMcpProtocol.MAX_REQUEST_BYTES),
			"deadline": Time.get_ticks_msec() + handshake_timeout_ms,
		}
		_pending.append(entry)
	_poll_pending()
	_poll_active()
	_pump_queue()


# ---------------------------------------------------------------------------
# Connections
# ---------------------------------------------------------------------------


func _poll_pending() -> void:
	for entry in _pending.duplicate():
		var peer: StreamPeerTCP = entry["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_pending.erase(entry)
			continue
		_take_bytes(peer, entry["reader"])
		var next: Dictionary = entry["reader"].next()
		match next["status"]:
			"frame":
				_pending.erase(entry)
				_handshake(entry, next["message"])
			"error":
				_pending.erase(entry)
				_refuse(peer, next["code"], next["message"])
			_:
				if Time.get_ticks_msec() > int(entry["deadline"]):
					_pending.erase(entry)
					peer.disconnect_from_host()


func _handshake(entry: Dictionary, message: Dictionary) -> void:
	var peer: StreamPeerTCP = entry["peer"]
	if message.get("type") != "hello":
		_refuse(peer, HFMcpProtocol.E_BAD_REQUEST, "Say hello first")
		return
	var version = message.get("bridge_version")
	if (
		not (version is float or version is int)
		or not (int(version) in HFMcpProtocol.SUPPORTED_BRIDGE_VERSIONS)
	):
		_refuse(
			peer,
			HFMcpProtocol.E_UNSUPPORTED_VERSION,
			"This editor speaks bridge version %d" % HFMcpProtocol.BRIDGE_VERSION,
			{"supported": HFMcpProtocol.SUPPORTED_BRIDGE_VERSIONS}
		)
		return
	if not _token_matches(message.get("token")):
		_refuse(peer, HFMcpProtocol.E_AUTH_FAILED, "The token does not match this editor's")
		return
	# One client at a time. A reconnect after a dropped socket is a new client,
	# and it is the one to keep. The old one's queued requests still run; their
	# answers have nowhere to go, and a retry with the same operation_id gets
	# them back from the dispatcher's cache.
	if not _active.is_empty():
		(_active["peer"] as StreamPeerTCP).disconnect_from_host()
	_active = {"peer": peer, "reader": entry["reader"]}
	var host = dispatcher.host
	_send(
		peer,
		{
			"type": "welcome",
			"bridge_version": HFMcpProtocol.BRIDGE_VERSION,
			"schema_version": HFMcpProtocol.SCHEMA_VERSION,
			"hammerforge_version": host.hammerforge_version(),
			"editor_pid": host.editor_pid(),
			"project_path": host.project_path(),
		}
	)
	if not _running:
		_set_state(State.CONNECTED, "Agent connected")


## Compared over the whole length, so how long a wrong token took to refuse says
## nothing about how much of it was right.
func _token_matches(offered) -> bool:
	if not (offered is String) or _token.is_empty():
		return false
	var text := offered as String
	if text.length() != _token.length():
		return false
	var difference := 0
	for i in _token.length():
		difference |= text.unicode_at(i) ^ _token.unicode_at(i)
	return difference == 0


func _poll_active() -> void:
	if _active.is_empty():
		return
	var peer: StreamPeerTCP = _active["peer"]
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_active = {}
		if not _running:
			_set_state(State.LISTENING, "Listening on %s:%d" % [BIND_ADDRESS, port()])
		return
	_take_bytes(peer, _active["reader"])
	while not _active.is_empty():
		var next: Dictionary = _active["reader"].next()
		if next["status"] == "need_more":
			return
		if next["status"] == "error":
			_active = {}
			_refuse(peer, next["code"], next["message"])
			return
		_accept_request(peer, next["message"])


func _accept_request(peer: StreamPeerTCP, message: Dictionary) -> void:
	var id := str(message.get("id", ""))
	if message.get("type") != "request":
		_send(
			peer,
			HFMcpProtocol.response_error(
				id, HFMcpProtocol.E_BAD_REQUEST, "Expected a request", {}, dispatcher.revision(), ""
			)
		)
		return
	var method := str(message.get("method", ""))
	if _running and dispatcher.runs_while_busy(method):
		_answer_now(peer, message)
		return
	_queue.append({"peer": peer, "request": message})


func _answer_now(peer: StreamPeerTCP, request: Dictionary) -> void:
	var response: Dictionary = await dispatcher.handle(request)
	_send(peer, response)


func _pump_queue() -> void:
	if _running or _queue.is_empty():
		return
	var job: Dictionary = _queue.pop_front()
	_running = true
	var method := str(job["request"].get("method", ""))
	_set_state(State.RUNNING, "Running: %s" % method.trim_prefix("hf_").replace("_", " "))
	_run(job)


## A coroutine: one queued command from start to answer.
func _run(job: Dictionary) -> void:
	var response: Dictionary = await dispatcher.handle(job["request"])
	_running = false
	if _server == null:
		return
	_send(job["peer"], response)
	if _active.is_empty():
		_set_state(State.LISTENING, "Listening on %s:%d" % [BIND_ADDRESS, port()])
	else:
		_set_state(State.CONNECTED, "Agent connected")


func _take_bytes(peer: StreamPeerTCP, reader) -> void:
	var available := peer.get_available_bytes()
	if available <= 0:
		return
	var got: Array = peer.get_data(available)
	if int(got[0]) == OK:
		reader.feed(got[1])


func _send(peer: StreamPeerTCP, message: Dictionary) -> void:
	if peer == null or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var bytes := HFMcpProtocol.encode_frame(message)
	if bytes.size() - 4 > HFMcpProtocol.MAX_RESPONSE_BYTES:
		var too_big := HFMcpProtocol.response_error(
			str(message.get("id", "")),
			HFMcpProtocol.E_INTERNAL,
			(
				"The answer was %d bytes, over the %d byte limit"
				% [bytes.size() - 4, HFMcpProtocol.MAX_RESPONSE_BYTES]
			),
			{},
			int(message.get("revision", 0)),
			str(message.get("target_id", ""))
		)
		bytes = HFMcpProtocol.encode_frame(too_big)
	peer.put_data(bytes)


## Send an error frame, then close. For a handshake that failed and a frame that
## cannot be read, after which nothing on the connection can be trusted.
func _refuse(peer: StreamPeerTCP, code: String, message: String, details := {}) -> void:
	_send(peer, HFMcpProtocol.error_frame(code, message, details))
	peer.disconnect_from_host()


func _set_state(new_state: int, detail: String) -> void:
	var changed := new_state != _state
	_state = new_state
	if changed or new_state == State.RUNNING:
		state_changed.emit(new_state, detail)


# ---------------------------------------------------------------------------
# Discovery file
# ---------------------------------------------------------------------------


func _write_discovery() -> int:
	var dir := discovery_path.get_base_dir()
	var made := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if made != OK:
		return made
	var host = dispatcher.host
	var body := {
		"bridge_version": HFMcpProtocol.BRIDGE_VERSION,
		"port": port(),
		"pid": OS.get_process_id(),
		"token": _token,
		"project_path": host.project_path(),
		"hammerforge_version": host.hammerforge_version(),
		"started_at": Time.get_datetime_string_from_system(true),
	}
	# Written beside and renamed over, so a reader never sees half a file.
	var writing := discovery_path + ".writing"
	var file := FileAccess.open(writing, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	# Before the token goes in. Windows has no unix permissions and answers
	# ERR_UNAVAILABLE; the file then has the project folder's own access rules.
	FileAccess.set_unix_permissions(writing, DISCOVERY_PERMISSIONS)
	file.store_string(JSON.stringify(body, "  "))
	file.close()
	if FileAccess.file_exists(discovery_path):
		DirAccess.remove_absolute(discovery_path)
	return DirAccess.rename_absolute(writing, discovery_path)


## Delete the file, unless another editor on the same project has written its
## own over it since.
func _remove_discovery() -> void:
	if not FileAccess.file_exists(discovery_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(discovery_path)) == OK:
		var data = json.data
		if data is Dictionary and int(data.get("pid", -1)) != OS.get_process_id():
			return
	DirAccess.remove_absolute(discovery_path)
