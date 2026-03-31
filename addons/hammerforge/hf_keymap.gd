@tool
class_name HFKeymap
extends RefCounted

## Customizable keyboard shortcut bindings for HammerForge.
##
## Each action maps to a binding dict: {keycode: int, ctrl: bool, shift: bool, alt: bool}.
## Load from JSON for user customization, or fall back to built-in defaults.

var _bindings: Dictionary = {}


static func load_or_default(path: String = "") -> HFKeymap:
	var km = HFKeymap.new()
	if path != "" and FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var text = file.get_as_text()
			var data = JSON.parse_string(text)
			if data is Dictionary:
				km._bindings = data
				return km
	km._bindings = _default_bindings()
	return km


static func _default_bindings() -> Dictionary:
	return {
		# Tool selection
		"tool_draw": {"keycode": KEY_D},
		"tool_select": {"keycode": KEY_S},
		"tool_extrude_up": {"keycode": KEY_U},
		"tool_extrude_down": {"keycode": KEY_J},
		# Editing
		"delete": {"keycode": KEY_DELETE},
		"duplicate": {"keycode": KEY_D, "ctrl": true},
		"group": {"keycode": KEY_G, "ctrl": true},
		"ungroup": {"keycode": KEY_U, "ctrl": true},
		"hollow": {"keycode": KEY_H, "ctrl": true},
		"clip": {"keycode": KEY_X, "shift": true},
		"carve": {"keycode": KEY_R, "shift": true, "ctrl": true},
		"move_to_floor": {"keycode": KEY_F, "ctrl": true, "shift": true},
		"move_to_ceiling": {"keycode": KEY_C, "ctrl": true, "shift": true},
		# Paint tools
		"paint_bucket": {"keycode": KEY_B},
		"paint_erase": {"keycode": KEY_E},
		"paint_ramp": {"keycode": KEY_R},
		"paint_line": {"keycode": KEY_L},
		"paint_blend": {"keycode": KEY_K},
		# Vertex editing
		"vertex_edit": {"keycode": KEY_V},
		"vertex_edge_mode": {"keycode": KEY_E},
		"vertex_merge": {"keycode": KEY_W, "ctrl": true},
		"vertex_split_edge": {"keycode": KEY_E, "ctrl": true},
		# Material tools
		"texture_picker": {"keycode": KEY_T},
		"apply_last_texture": {"keycode": KEY_T, "shift": true},
		# Selection
		"select_similar": {"keycode": KEY_S, "shift": true},
		"selection_filter": {"keycode": KEY_F, "shift": true},
		# Axis lock
		"axis_x": {"keycode": KEY_X},
		"axis_y": {"keycode": KEY_Y},
		"axis_z": {"keycode": KEY_Z},
	}


## Returns true if the given event matches the binding for the named action.
func matches(action: String, event: InputEventKey) -> bool:
	var b: Dictionary = _bindings.get(action, {})
	if b.is_empty():
		return false
	if event.keycode != int(b.get("keycode", 0)):
		return false
	if bool(b.get("ctrl", false)) != event.ctrl_pressed:
		return false
	if bool(b.get("shift", false)) != event.shift_pressed:
		return false
	if bool(b.get("alt", false)) != event.alt_pressed:
		return false
	return true


## Get a human-readable display string for an action's binding (e.g. "Ctrl+H").
func get_display_string(action: String) -> String:
	var b: Dictionary = _bindings.get(action, {})
	if b.is_empty():
		return "?"
	var parts: PackedStringArray = []
	if bool(b.get("ctrl", false)):
		parts.append("Ctrl")
	if bool(b.get("shift", false)):
		parts.append("Shift")
	if bool(b.get("alt", false)):
		parts.append("Alt")
	var keycode := int(b.get("keycode", 0))
	parts.append(_keycode_to_label(keycode))
	return "+".join(parts)


## Save current bindings to a JSON file.
func save(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_bindings, "\t"))


## Update a single binding.
func set_binding(
	action: String, keycode: int, ctrl: bool = false, shift: bool = false, alt: bool = false
) -> void:
	var b := {"keycode": keycode}
	if ctrl:
		b["ctrl"] = true
	if shift:
		b["shift"] = true
	if alt:
		b["alt"] = true
	_bindings[action] = b


## Get all action names.
func get_actions() -> PackedStringArray:
	var result := PackedStringArray()
	for key in _bindings.keys():
		result.append(str(key))
	return result


## Get a copy of all bindings for display purposes.
func get_all_bindings() -> Dictionary:
	return _bindings.duplicate()


## Map an action name to its UI category.
static func get_category(action: String) -> String:
	if action.begins_with("tool_"):
		return "Tools"
	if action.begins_with("paint_"):
		return "Paint"
	if action.begins_with("axis_"):
		return "Axis Lock"
	if (
		action
		in [
			"vertex_edit",
			"vertex_edge_mode",
			"vertex_merge",
			"vertex_split_edge",
			"texture_picker",
			"apply_last_texture",
		]
	):
		return "Tools"
	if action in ["select_similar", "selection_filter"]:
		return "Selection"
	return "Editing"


## Map an action name to a human-readable label.
static func get_action_label(action: String) -> String:
	const LABELS := {
		"tool_draw": "Draw",
		"tool_select": "Select",
		"tool_extrude_up": "Extrude Up",
		"tool_extrude_down": "Extrude Down",
		"vertex_edit": "Vertex Edit",
		"vertex_edge_mode": "Edge Mode",
		"vertex_merge": "Merge Vertices",
		"vertex_split_edge": "Split Edge",
		"delete": "Delete",
		"duplicate": "Duplicate",
		"group": "Group",
		"ungroup": "Ungroup",
		"hollow": "Hollow",
		"clip": "Clip",
		"carve": "Carve",
		"move_to_floor": "Move to Floor",
		"move_to_ceiling": "Move to Ceiling",
		"paint_bucket": "Paint Brush",
		"paint_erase": "Erase",
		"paint_ramp": "Ramp / Rect",
		"paint_line": "Line",
		"paint_blend": "Bucket Fill",
		"texture_picker": "Texture Picker",
		"apply_last_texture": "Apply Last Texture",
		"select_similar": "Select Similar",
		"selection_filter": "Selection Filters",
		"axis_x": "Lock X",
		"axis_y": "Lock Y",
		"axis_z": "Lock Z",
	}
	return LABELS.get(action, action.capitalize().replace("_", " "))


static func _keycode_to_label(keycode: int) -> String:
	match keycode:
		KEY_DELETE:
			return "Del"
		KEY_BACKSPACE:
			return "Bksp"
		KEY_ESCAPE:
			return "Esc"
		KEY_TAB:
			return "Tab"
		KEY_ENTER:
			return "Enter"
		KEY_SPACE:
			return "Space"
		KEY_UP:
			return "Up"
		KEY_DOWN:
			return "Down"
		KEY_LEFT:
			return "Left"
		KEY_RIGHT:
			return "Right"
		KEY_PAGEUP:
			return "PgUp"
		KEY_PAGEDOWN:
			return "PgDn"
	# Single letter keys
	if keycode >= KEY_A and keycode <= KEY_Z:
		return char(keycode)
	if keycode >= KEY_0 and keycode <= KEY_9:
		return str(keycode - KEY_0)
	return "Key%d" % keycode
