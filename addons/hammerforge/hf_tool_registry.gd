@tool
class_name HFToolRegistry
extends RefCounted

## Manages registration and dispatch of HFEditorTool instances.

## Where `HFEditorTool` lives, so a candidate script can be checked against it
## without being constructed.
const EDITOR_TOOL_PATH := "res://addons/hammerforge/hf_editor_tool.gd"

var _tools: Array = []
var _active_tool: HFEditorTool = null
var _tool_by_id: Dictionary = {}
## Handed the tool that became active, or null. The dock builds an active tool's
## declared settings from it.
var _settings_callback: Callable = Callable()


func register_tool(tool: HFEditorTool) -> void:
	if tool == null or _tool_by_id.has(tool.tool_id()):
		return
	_tools.append(tool)
	_tool_by_id[tool.tool_id()] = tool


func unregister_tool(tool_id: int) -> void:
	if not _tool_by_id.has(tool_id):
		return
	var tool: HFEditorTool = _tool_by_id[tool_id]
	if tool == _active_tool:
		_active_tool.deactivate()
		_active_tool = null
	_tools.erase(tool)
	_tool_by_id.erase(tool_id)


## Make a tool active, if it says it can be.
##
## `p_settings_callback` is handed the tool that became active, or null when none
## did, so the dock can build the controls its `get_settings_schema()` declares.
func activate_tool(
	tool_id: int,
	root: Node3D,
	camera: Camera3D,
	p_undo_redo: EditorUndoRedoManager = null,
	p_history_callback: Callable = Callable(),
	p_settings_callback: Callable = Callable()
) -> void:
	_settings_callback = p_settings_callback
	if _active_tool and _active_tool.tool_id() == tool_id:
		deactivate_current()
		return
	# Look the id up before letting go of the tool in hand. Deactivating first and
	# checking after meant an id that is not registered - a tool whose script
	# failed to load, a toolbar button wired to an id that has since changed -
	# silently turned off the tool the mapper was using, with nothing said.
	if not _tool_by_id.has(tool_id):
		HFLog.warn("HammerForge: no tool registered with id %d" % tool_id)
		return
	# Ask before activating. `can_activate()` and `get_poll_fail_reason()` are the
	# one documented way an HFEditorTool says it cannot run in the current state,
	# and this is the only thing that activates a tool - so without the poll, a
	# tool that had already declared it could not run became active anyway, the
	# toolbar showed it as active, and every click did nothing. HFDecalTool and
	# HFMeasureTool both override it, so pressing N or M with no LevelRoot in the
	# scene was exactly that.
	var candidate: HFEditorTool = _tool_by_id[tool_id]
	if not candidate.can_activate(root):
		var reason := candidate.get_poll_fail_reason(root)
		if reason == "":
			reason = "%s cannot run right now" % candidate.tool_name()
		HFLog.warn("HammerForge: %s" % reason)
		if root and root.has_signal("user_message"):
			root.user_message.emit(reason, 1)
		return
	if _active_tool:
		_active_tool.deactivate()
		_active_tool = null
	_active_tool = candidate
	_active_tool.undo_redo = p_undo_redo
	_active_tool.history_callback = p_history_callback
	_active_tool.activate(root, camera)
	_notify_settings_host()


## Deactivate the current tool without activating another.
func deactivate_current() -> void:
	if _active_tool:
		_active_tool.deactivate()
		_active_tool = null
	_notify_settings_host()


func _notify_settings_host() -> void:
	if _settings_callback.is_valid():
		_settings_callback.call(_active_tool)


func get_active_tool() -> HFEditorTool:
	return _active_tool


## Returns true when an external tool (ID >= 100) is active.
func has_active_external_tool() -> bool:
	return _active_tool != null and _active_tool.tool_id() >= 100


func get_tool_by_id(id: int) -> HFEditorTool:
	return _tool_by_id.get(id) as HFEditorTool


func get_all_tools() -> Array:
	return _tools.duplicate()


## Get only external tools (ID >= 100).
func get_external_tools() -> Array:
	var out: Array = []
	for t in _tools:
		if t.tool_id() >= 100:
			out.append(t)
	return out


## Route input to active external tool. Returns STOP if consumed.
func dispatch_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
	if _active_tool and _active_tool.tool_id() >= 100:
		return _active_tool.handle_input(event, camera, mouse_pos)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Route keyboard event to active external tool. Returns STOP if consumed.
func dispatch_keyboard(event: InputEventKey) -> int:
	if _active_tool and _active_tool.tool_id() >= 100:
		return _active_tool.handle_keyboard(event)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Settle a stale LMB gesture without deactivating the selected tool.
func recover_active_pointer_capture() -> bool:
	if _active_tool and _active_tool.tool_id() >= 100:
		return _active_tool.recover_lost_pointer_capture()
	return false


## Cancel transient pointer ownership after focus loss without changing tools.
func cancel_active_pointer_capture() -> bool:
	if _active_tool and _active_tool.tool_id() >= 100:
		return _active_tool.cancel_pointer_capture()
	return false


## Which external tool wants this key, or -1.
##
## A tool shortcut is a bare key by construction - `tool_shortcut_key()` returns
## one keycode and has nowhere to say otherwise - so a chord built on that key is
## not it. Matching the keycode alone meant Ctrl+M activated Measure, and so did
## Shift+M in paint mode, where `flip_selection` is gated off and the event fell
## through to here. Activating a tool is not a quiet no-op: it takes the
## viewport's left click off whatever the mapper was building with.
func check_shortcut(event: InputEventKey) -> int:
	if event.ctrl_pressed or event.shift_pressed or event.alt_pressed or event.meta_pressed:
		return -1
	for t in _tools:
		if t.tool_id() >= 100 and t.tool_shortcut_key() == event.keycode:
			return t.tool_id()
	return -1


## Where a project keeps its own editor tools. Outside the addon on purpose: the
## upgrade instructions say to replace `addons/hammerforge`, so anything under it
## is deleted by a documented upgrade.
const PROJECT_TOOLS_PATH := "res://hammerforge_tools/"


## Scan a directory for .gd files that extend HFEditorTool, load and register them.
func load_external_tools(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".gd"):
			var full_path = path.path_join(file_name)
			var script = load(full_path)
			if script and _extends_editor_tool(script):
				var instance = script.new()
				if instance is HFEditorTool and instance.tool_id() >= 100:
					register_tool(instance)
				else:
					# Refused after construction, so it has to be freed. A
					# RefCounted goes when the reference does; a Node does not,
					# and stays an orphan for the life of the editor session.
					HFLog.warn(
						(
							"HammerForge: %s is an HFEditorTool with id %d, which is below 100"
							% [full_path, instance.tool_id() if instance is HFEditorTool else -1]
						)
					)
					if instance is Node:
						(instance as Node).queue_free()
					instance = null
			elif script:
				HFLog.warn("HammerForge: %s is not an HFEditorTool, skipping it" % full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


## Whether a script extends `HFEditorTool`, read off the script rather than off an
## instance of it.
##
## `script.new()` used to run first and the check came after, so every `.gd` file
## in the scanned directory was constructed: a Node subclass leaked, a script whose
## `_init()` takes arguments was a hard error, and one with side effects in
## `_init()` got them. Walking the base script chain answers the question without
## running any of it.
static func _extends_editor_tool(script: Script) -> bool:
	var current: Script = script
	while current != null:
		if current.resource_path == EDITOR_TOOL_PATH:
			return true
		current = current.get_base_script()
	return false
