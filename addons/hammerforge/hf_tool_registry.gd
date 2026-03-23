@tool
class_name HFToolRegistry
extends RefCounted

## Manages registration and dispatch of HFEditorTool instances.

var _tools: Array = []
var _active_tool: HFEditorTool = null
var _tool_by_id: Dictionary = {}


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


func activate_tool(tool_id: int, root: Node3D, camera: Camera3D) -> void:
	if _active_tool and _active_tool.tool_id() == tool_id:
		return
	if _active_tool:
		_active_tool.deactivate()
		_active_tool = null
	if _tool_by_id.has(tool_id):
		_active_tool = _tool_by_id[tool_id]
		_active_tool.activate(root, camera)


## Deactivate the current tool without activating another.
func deactivate_current() -> void:
	if _active_tool:
		_active_tool.deactivate()
		_active_tool = null


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


## Check if any external tool wants this shortcut key.
func check_shortcut(keycode: int) -> int:
	for t in _tools:
		if t.tool_id() >= 100 and t.tool_shortcut_key() == keycode:
			return t.tool_id()
	return -1


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
			if script:
				var instance = script.new()
				if instance is HFEditorTool and instance.tool_id() >= 100:
					register_tool(instance)
				else:
					instance = null
		file_name = dir.get_next()
	dir.list_dir_end()
