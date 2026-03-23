@tool
class_name HFEditorTool
extends RefCounted

## Base class for custom editor tools.
##
## Subclass this to create tools that integrate with HammerForge's tool system.
## Register instances with HFToolRegistry. The registry activates/deactivates
## tools and routes input events to the active tool.

## The LevelRoot this tool operates on (set by registry on activate).
var root: Node3D

## Whether this tool is currently active.
var is_active := false


## Returns true if this tool can execute in the current state.
## Override in subclass to add specific requirements.
func can_activate(p_root: Node3D) -> bool:
	return p_root != null


## Returns a user-facing reason string when can_activate() is false.
## Override in subclass to provide specific failure reasons.
func get_poll_fail_reason(p_root: Node3D) -> String:
	if p_root == null:
		return "No LevelRoot in scene"
	return ""


## Display name for toolbar button.
func tool_name() -> String:
	return "Custom Tool"


## Unique numeric tool ID. Built-in IDs: 0=Draw, 1=Select, 2=ExtrudeUp, 3=ExtrudeDown.
## External tools should use IDs >= 100.
func tool_id() -> int:
	return -1


## KEY_* constant for keyboard shortcut, or 0 for none.
func tool_shortcut_key() -> int:
	return 0


## Called when tool becomes active.
func activate(p_root: Node3D, p_camera: Camera3D) -> void:
	root = p_root
	is_active = true


## Called when tool is deactivated (another tool activated).
func deactivate() -> void:
	is_active = false
	root = null


## Handle mouse/key input. Return EditorPlugin.AFTER_GUI_INPUT_STOP to consume.
func handle_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Handle keyboard shortcut. Return EditorPlugin.AFTER_GUI_INPUT_STOP to consume.
func handle_keyboard(event: InputEventKey) -> int:
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Lines for the shortcut HUD overlay.
func get_shortcut_hud_lines() -> PackedStringArray:
	return PackedStringArray()


# ---------------------------------------------------------------------------
# Declarative settings — subclasses override get_settings_schema() to expose
# configurable properties.  The dock auto-generates UI controls from the schema.
# ---------------------------------------------------------------------------

## Internal settings storage.
var _settings: Dictionary = {}


## Return an array of setting descriptors.  Each is a dict with keys:
## "name" (String), "type" ("bool"|"int"|"float"|"string"|"enum"|"color"|"vector3"),
## "label" (String, display name), "default" (Variant), and optionally:
## "min"/"max" (numeric), "options" (PackedStringArray for enum).
## Override in subclass to expose tool-specific settings.
func get_settings_schema() -> Array:
	return []


## Read a setting value by key.
func get_setting(key: String) -> Variant:
	# Fall back to schema default if not explicitly set
	if _settings.has(key):
		return _settings[key]
	for prop in get_settings_schema():
		if prop.get("name", "") == key:
			return prop.get("default")
	return null


## Write a setting value by key.
func set_setting(key: String, value: Variant) -> void:
	_settings[key] = value
