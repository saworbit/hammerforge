extends SceneTree

## The editor end of the MCP bridge smoke test, without the editor.
##
## `tools/mcp_bridge_smoke.py` starts this, waits for the discovery file, then
## drives it through hammerforge-mcp over stdio: the whole chain an agent uses,
## from MCP client to LevelRoot. An `EditorUndoRedoManager` cannot be built
## outside the editor, so undo goes through the same stand-in the GUT tests use.
##
##   godot --headless --path . -s res://tools/mcp_bridge_smoke.gd -- \
##       --discovery=<file> --done=<file> [--seconds=120]
##
## It quits when the `--done` file appears, or after `--seconds`. `--discovery`
## keeps it off the project's own discovery file, which an editor with the bridge
## on may be using.

const HFMcpDispatcher = preload("res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd")
const HFMcpListener = preload("res://addons/hammerforge/mcp/hf_mcp_listener.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const HostStandIn = preload("res://tests/mcp/mcp_test_host.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")

var _done_path := ""
var _discovery_path := ""
var _deadline_ms := 0
var _listener = null
var _dispatcher = null
var _undo = null
var _built := false


func _initialize() -> void:
	var seconds := 120.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--done="):
			_done_path = arg.trim_prefix("--done=")
		elif arg.begins_with("--discovery="):
			_discovery_path = arg.trim_prefix("--discovery=")
		elif arg.begins_with("--seconds="):
			seconds = float(arg.trim_prefix("--seconds="))
	_deadline_ms = Time.get_ticks_msec() + int(seconds * 1000.0)


func _process(_delta: float) -> bool:
	# Built on the first frame rather than in _initialize: a LevelRoot made there,
	# before the tree runs, hangs a headless run.
	if not _built:
		_built = true
		return not _build()
	if _done_path != "" and FileAccess.file_exists(_done_path):
		print("smoke: told to stop")
		_finish()
		return true
	if Time.get_ticks_msec() > _deadline_ms:
		printerr("smoke: timed out waiting for the client")
		_finish()
		quit(1)
	return false


func _build() -> bool:
	var scene := Node3D.new()
	scene.name = "SmokeScene"
	root.add_child(scene)
	var level = LevelRootScript.new()
	level.name = "LevelRoot"
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	scene.add_child(level)

	_undo = UndoStandIn.new()
	var host = HostStandIn.new()
	host.scene = scene
	host.undo = _undo
	host.tree = self
	_dispatcher = HFMcpDispatcher.new(host)
	_listener = HFMcpListener.new()
	_listener.dispatcher = _dispatcher
	_listener.allow_outside_editor = true
	if _discovery_path != "":
		_listener.discovery_path = _discovery_path
	root.add_child(_listener)
	var err: int = _listener.start()
	if err != OK:
		printerr("smoke: the listener would not start: %s" % error_string(err))
		quit(1)
		return false
	print("smoke: listening on 127.0.0.1:%d" % _listener.port())
	return true


func _finish() -> void:
	if _listener:
		_listener.stop()
	if _dispatcher:
		_dispatcher.shutdown()
	if _undo:
		_undo.free_histories()
