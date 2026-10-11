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
## On start it writes `res://.godot/hammerforge_mcp/discovery.json` with the
## port, this editor's pid and a new token, and deletes it on stop. `.godot/` is
## in Godot's own `.gitignore` and never goes into an export, so the token cannot
## be committed or shipped by accident, and the folder it sits in is closed to
## other users before the token is written. The protocol is in
## `docs/superpowers/specs/2026-10-11-mcp-bridge-design.md`.

enum State { OFF, LISTENING, CONNECTED, RUNNING, FAILED }

signal state_changed(state: int, detail: String)
## A queued command was answered: its method, whether it went through, the error
## code when it did not, and how long it took from leaving the queue.
signal command_finished(method: String, ok: bool, code: String, ms: int)

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFMcpProtocol = preload("hf_mcp_protocol.gd")
const HFMcpDispatcher = preload("hf_mcp_dispatcher.gd")
@warning_ignore_restore("shadowed_global_identifier")

const DISCOVERY_PATH := "res://.godot/hammerforge_mcp/discovery.json"
const HANDSHAKE_TIMEOUT_MS := 5000
const BIND_ADDRESS := "127.0.0.1"

## More than this waiting to go out to one client, and it has stopped reading:
## let it go rather than hold the bytes.
const MAX_OUTBOX_BYTES := 64 << 20

## A hello is a few hundred bytes. Until a connection has shown the token it
## gets no more than this, and only this many may wait at once.
const MAX_HELLO_BYTES := 4096
const MAX_PENDING := 8
## Status-only connections at once, such as `hammerforge-mcp --check`.
const MAX_OBSERVERS := 4

## Owner only, 0o700 for the folder and 0o600 for the file, where the platform
## has unix permissions.
const DIRECTORY_PERMISSIONS := 448
const DISCOVERY_PERMISSIONS := 384


## One queued command from start to answer.
##
## A RefCounted rather than a method on the listener. If the plugin frees the
## listener while a command awaits (the editor closing during a bake), the
## coroutine resumes in an object that still exists, finds the listener gone, and
## drops the answer, instead of resuming inside a freed node. `_live` keeps it
## alive until then, since nothing else holds it.
class Job:
	extends RefCounted

	static var _live: Array = []

	var listener_ref: WeakRef
	var peer: StreamPeerTCP
	var request: Dictionary
	var generation: int
	var started_ms := 0

	func run(dispatcher) -> void:
		_live.append(self)
		var response = await dispatcher.handle(request)
		_live.erase(self)
		var listener = listener_ref.get_ref()
		if listener != null:
			listener._finish(self, response)


var dispatcher: HFMcpDispatcher
var discovery_path := DISCOVERY_PATH
var handshake_timeout_ms := HANDSHAKE_TIMEOUT_MS
var max_outbox_bytes := MAX_OUTBOX_BYTES
## Lets a test or the bridge smoke script run it without the editor. Nothing a
## game runs sets it.
var allow_outside_editor := false

var _server: TCPServer = null
var _token := ""
## Connections that have not said hello yet: {peer, reader, deadline}.
var _pending: Array[Dictionary] = []
## The one authenticated connection: {peer, reader}, or empty.
var _active: Dictionary = {}
## Connections whose hello said `"role": "observer"`: {peer, reader} each. They
## ask for status beside the agent rather than taking its place, which is what
## `hammerforge-mcp --check` did to a working agent (#1060).
var _observers: Array[Dictionary] = []
## Requests waiting their turn: {peer, request}.
var _queue: Array[Dictionary] = []
var _running := false
## Bytes still to go out, per connection: peer instance id -> {peer, bytes,
## close}. `put_data()` would wait until the last byte was sent, so a client that
## stopped reading a large screenshot would hold the editor's main thread; this
## writes what the socket takes each frame instead.
var _outbox: Dictionary = {}
## Goes up on every stop, so a command still finishing from before it knows the
## listener it started under is gone.
var _generation := 0
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
	for entry in _observers:
		(entry["peer"] as StreamPeerTCP).disconnect_from_host()
	_observers.clear()
	_queue.clear()
	_outbox.clear()
	_running = false
	_generation += 1
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
		if _pending.size() >= MAX_PENDING:
			(_pending.pop_front()["peer"] as StreamPeerTCP).disconnect_from_host()
		var entry := {
			"peer": peer,
			"reader": HFMcpProtocol.FrameReader.new(MAX_HELLO_BYTES),
			"deadline": Time.get_ticks_msec() + handshake_timeout_ms,
		}
		_pending.append(entry)
	_poll_pending()
	_poll_active()
	_poll_observers()
	_pump_queue()
	_flush()


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
	# Past the token, a request may be as large as a request can be. Bytes that
	# came in behind the hello stay in the reader.
	entry["reader"].max_bytes = HFMcpProtocol.MAX_REQUEST_BYTES
	if str(message.get("role", "agent")) == "observer":
		if _observers.size() >= MAX_OBSERVERS:
			(_observers.pop_front()["peer"] as StreamPeerTCP).disconnect_from_host()
		_observers.append({"peer": peer, "reader": entry["reader"]})
		_send(peer, _welcome())
		return
	# One agent at a time. A reconnect after a dropped socket is a new client,
	# and it is the one to keep. The old one's queued requests still run; their
	# answers have nowhere to go, and a retry with the same operation_id gets
	# them back from the dispatcher's cache.
	if not _active.is_empty():
		(_active["peer"] as StreamPeerTCP).disconnect_from_host()
	_active = {"peer": peer, "reader": entry["reader"]}
	_send(peer, _welcome())
	if not _running:
		_set_state(State.CONNECTED, "Agent connected")


func _welcome() -> Dictionary:
	var host = dispatcher.host
	return {
		"type": "welcome",
		"bridge_version": HFMcpProtocol.BRIDGE_VERSION,
		"schema_version": HFMcpProtocol.SCHEMA_VERSION,
		"hammerforge_version": host.hammerforge_version(),
		"editor_pid": host.editor_pid(),
		"project_path": host.project_path(),
	}


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
			if not _running:
				_set_state(State.LISTENING, "Listening on %s:%d" % [BIND_ADDRESS, port()])
			return
		_accept_request(peer, next["message"])


## Each observer's requests, answered as they are read: status, and a refusal
## for anything else. They never queue, so they never wait behind the agent.
func _poll_observers() -> void:
	for entry in _observers.duplicate():
		var peer: StreamPeerTCP = entry["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_observers.erase(entry)
			continue
		_take_bytes(peer, entry["reader"])
		while true:
			var next: Dictionary = entry["reader"].next()
			if next["status"] == "need_more":
				break
			if next["status"] == "error":
				_observers.erase(entry)
				_refuse(peer, next["code"], next["message"])
				break
			var message: Dictionary = next["message"]
			if (
				message.get("type") == "request"
				and dispatcher.runs_while_busy(str(message.get("method", "")))
			):
				_answer_now(peer, message)
				continue
			_send(
				peer,
				HFMcpProtocol.response_error(
					str(message.get("id", "")),
					HFMcpProtocol.E_BAD_REQUEST,
					"A check connection asks for status only",
					{},
					dispatcher.revision(),
					""
				)
			)


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
	if dispatcher.runs_while_busy(method):
		# Start what came before it first, so a status read in the same frame as
		# a bake says the bake is running, and one behind a quick change sees the
		# change. Then answer at once: queued behind a command, it waited for the
		# whole of it (#1049).
		while not _running and not _queue.is_empty():
			_pump_queue()
		_answer_now(peer, message)
		return
	_queue.append({"peer": peer, "request": message})


func _answer_now(peer: StreamPeerTCP, request: Dictionary) -> void:
	var response = await dispatcher.handle(request)
	if response is Dictionary and (response as Dictionary).has("type"):
		_send(peer, response)


func _pump_queue() -> void:
	if _running or _queue.is_empty():
		return
	var job: Dictionary = _queue.pop_front()
	_running = true
	var method := str(job["request"].get("method", ""))
	_set_state(State.RUNNING, "Running: %s" % method.trim_prefix("hf_").replace("_", " "))
	var runner := Job.new()
	runner.listener_ref = weakref(self)
	runner.peer = job["peer"]
	runner.request = job["request"]
	runner.generation = _generation
	runner.started_ms = Time.get_ticks_msec()
	runner.run(dispatcher)


## A command is done. Called by its Job, which may outlive a stop() or a restart.
func _finish(job: Job, response) -> void:
	if job.generation != _generation:
		return
	_running = false
	if not (response is Dictionary and (response as Dictionary).has("type")):
		# A script error inside the dispatcher: a typed function that errors
		# returns an empty Dictionary. Answer, so the agent is not left waiting,
		# and keep taking requests.
		response = HFMcpProtocol.response_error(
			str(job.request.get("id", "")),
			HFMcpProtocol.E_INTERNAL,
			"The editor hit a script error; see its Output panel",
			{},
			dispatcher.revision(),
			""
		)
	if _server == null:
		return
	_send(job.peer, response)
	if _active.is_empty():
		_set_state(State.LISTENING, "Listening on %s:%d" % [BIND_ADDRESS, port()])
	else:
		_set_state(State.CONNECTED, "Agent connected")
	var error = response.get("error")
	var code := str((error as Dictionary).get("code", "")) if error is Dictionary else ""
	command_finished.emit(
		str(job.request.get("method", "")),
		bool(response.get("ok", false)),
		code,
		Time.get_ticks_msec() - job.started_ms
	)


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
	_queue_bytes(peer, bytes, false)


## Send an error frame, then close once it has gone. For a handshake that failed
## and a frame that cannot be read, after which nothing on the connection can be
## trusted.
func _refuse(peer: StreamPeerTCP, code: String, message: String, details := {}) -> void:
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var bytes := HFMcpProtocol.encode_frame(HFMcpProtocol.error_frame(code, message, details))
	_queue_bytes(peer, bytes, true)


func _queue_bytes(peer: StreamPeerTCP, bytes: PackedByteArray, close_after: bool) -> void:
	var key := peer.get_instance_id()
	if not _outbox.has(key):
		_outbox[key] = {"peer": peer, "bytes": PackedByteArray(), "close": false}
	var entry: Dictionary = _outbox[key]
	# Assigned back: a PackedByteArray taken out of a Dictionary is a copy, and
	# appending to it would leave the outbox empty.
	var pending: PackedByteArray = entry["bytes"]
	pending.append_array(bytes)
	entry["bytes"] = pending
	if pending.size() > max_outbox_bytes:
		_outbox.erase(key)
		peer.disconnect_from_host()
		return
	if close_after:
		entry["close"] = true
	# Most answers are small and go out at once, this frame.
	_flush_entry(key)


func _flush() -> void:
	for key in _outbox.keys():
		_flush_entry(key)


func _flush_entry(key: int) -> void:
	var entry: Dictionary = _outbox[key]
	var peer: StreamPeerTCP = entry["peer"]
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_outbox.erase(key)
		return
	var pending: PackedByteArray = entry["bytes"]
	# As much as the socket takes this frame, in a few writes, so an editor that
	# runs few frames when it is not in front still empties the outbox quickly.
	for attempt in 8:
		if pending.is_empty():
			break
		var sent: Array = peer.put_partial_data(pending)
		if int(sent[0]) != OK:
			_outbox.erase(key)
			peer.disconnect_from_host()
			return
		if int(sent[1]) <= 0:
			break
		pending = pending.slice(int(sent[1]))
	entry["bytes"] = pending
	if (entry["bytes"] as PackedByteArray).is_empty():
		_outbox.erase(key)
		if entry["close"]:
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
	var dir := ProjectSettings.globalize_path(discovery_path.get_base_dir())
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		return made
	_close_to_others(dir)
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


## Close the folder the token goes in to everyone but this user, before the
## token is written. A file chmodded after it is opened is not enough: another
## user who opened it in between keeps the handle. Without search permission on
## the folder, nobody else can open anything in it at all.
func _close_to_others(dir: String) -> void:
	if OS.get_name() != "Windows":
		FileAccess.set_unix_permissions(dir, DIRECTORY_PERMISSIONS)
		return
	# Windows hands a folder its parent's access rules, and a project at the root
	# of a drive lets every local user read. Replace them with this user alone.
	var user := OS.get_environment("USERNAME")
	if user.is_empty():
		return
	var domain := OS.get_environment("USERDOMAIN")
	var who := user if domain.is_empty() else "%s\\%s" % [domain, user]
	var output: Array = []
	var args := [dir, "/inheritance:r", "/grant:r", "%s:(OI)(CI)F" % who]
	var code := OS.execute("icacls", args, output, true)
	if code != 0:
		printerr("HammerForge MCP: could not restrict %s: %s" % [dir, "".join(output)])


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
