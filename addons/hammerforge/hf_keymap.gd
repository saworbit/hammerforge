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
	var defaults := _default_bindings()
	if path != "" and FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var text = file.get_as_text()
			var data = JSON.parse_string(text)
			if data is Dictionary:
				# Merge: user overrides take priority, but new default
				# actions are added so new features work out of the box.
				km._bindings = _validated(data, defaults, path)
				return km
	km._bindings = defaults
	return km


## The bindings from a user file, with anything unusable dropped.
##
## This is the one file a user is obliged to hand edit, so a typo in it must not
## become an error on every key event in the viewport. `matches()` runs on each
## one and starts by assigning the entry to a Dictionary, so a value of the wrong
## type errors there, naming this script rather than the file the user got wrong.
## Each rejection is reported once, on load, naming the file and the key.
static func _validated(data: Dictionary, defaults: Dictionary, path: String) -> Dictionary:
	var out: Dictionary = {}
	for action in data:
		var key := str(action)
		if not defaults.has(key):
			HFLog.warn("%s: '%s' is not a HammerForge action. Ignored." % [path, key])
			continue
		var binding = data[action]
		if not (binding is Dictionary):
			HFLog.warn(
				(
					"%s: '%s' is a %s, not a binding. The default is used."
					% [path, key, type_string(typeof(binding))]
				)
			)
			continue
		var keycode = binding.get("keycode", null)
		if not (keycode is int or keycode is float) or int(keycode) == 0:
			HFLog.warn("%s: '%s' has no usable keycode. The default is used." % [path, key])
			continue
		out[key] = binding
	for action in defaults:
		if not out.has(action):
			out[action] = defaults[action]
	_warn_about_conflicts(out, path)
	return out


## One line per pair of actions that can fire in the same mode on one chord.
## A hand-edited file is where these arrive, so the load is where to say so.
static func _warn_about_conflicts(bindings: Dictionary, path: String) -> void:
	var reported: Dictionary = {}
	for action in bindings:
		var first := str(action)
		for other in bindings:
			var second := str(other)
			if first == second:
				continue
			if action_mode(first) != action_mode(second):
				continue
			if not _same_chord(bindings[first], bindings[second]):
				continue
			var pair_key: String = first + "|" + second if first < second else second + "|" + first
			if reported.has(pair_key):
				continue
			reported[pair_key] = true
			HFLog.warn(
				(
					(
						"%s: '%s' and '%s' share a shortcut and both fire in the same mode."
						% [path, get_action_label(first), get_action_label(second)]
					)
					+ " Only one of them will work."
				)
			)


static func _default_bindings() -> Dictionary:
	return {
		# Tool selection
		"tool_draw": {"keycode": KEY_D},
		"tool_select": {"keycode": KEY_S},
		"tool_extrude_up": {"keycode": KEY_U},
		"tool_extrude_down": {"keycode": KEY_J},
		"tool_extrude": {"keycode": KEY_E},
		"tool_extrude_down_alt": {"keycode": KEY_E, "shift": true},
		# Workflow accelerators
		"toggle_operation": {"keycode": KEY_Q},
		"toggle_paint_mode": {"keycode": KEY_P, "shift": true},
		"quick_play": {"keycode": KEY_ENTER, "ctrl": true},
		"validate_level": {"keycode": KEY_ENTER, "ctrl": true, "shift": true},
		# Editing
		"delete": {"keycode": KEY_DELETE},
		"duplicate": {"keycode": KEY_D, "ctrl": true},
		"group": {"keycode": KEY_G, "ctrl": true},
		"ungroup": {"keycode": KEY_U, "ctrl": true},
		"hollow": {"keycode": KEY_H, "ctrl": true},
		"clip": {"keycode": KEY_X, "shift": true},
		"clip_to_face": {"keycode": KEY_X, "shift": true, "alt": true},
		"create_arch": {"keycode": KEY_A, "ctrl": true, "shift": true},
		"carve": {"keycode": KEY_R, "shift": true, "ctrl": true},
		"merge": {"keycode": KEY_M, "ctrl": true, "shift": true},
		"move_to_floor": {"keycode": KEY_F, "ctrl": true, "shift": true},
		"move_to_ceiling": {"keycode": KEY_C, "ctrl": true, "shift": true},
		# Free transform. R is also paint_ramp, which plugin_input_router only
		# dispatches while paint mode is active, so the two never both fire.
		"rotate_ccw": {"keycode": KEY_R},
		"rotate_cw": {"keycode": KEY_R, "shift": true},
		"flip_selection": {"keycode": KEY_M, "shift": true},
		"reset_rotation": {"keycode": KEY_R, "alt": true},
		# Paint tools
		"paint_bucket": {"keycode": KEY_B},
		"paint_erase": {"keycode": KEY_E},
		"paint_ramp": {"keycode": KEY_R},
		"paint_line": {"keycode": KEY_L},
		"paint_fill": {"keycode": KEY_K},
		"paint_blend": {"keycode": KEY_N},
		"paint_raise": {"keycode": KEY_Y},
		"paint_mirror_x": {"keycode": KEY_X},
		"paint_mirror_z": {"keycode": KEY_Z},
		"paint_room": {"keycode": KEY_H},
		"paint_confirm_connector": {"keycode": KEY_ENTER},
		# Vertex editing
		"vertex_edit": {"keycode": KEY_V},
		"vertex_edge_mode": {"keycode": KEY_E},
		"vertex_merge": {"keycode": KEY_W, "ctrl": true},
		"vertex_split_edge": {"keycode": KEY_E, "ctrl": true},
		# Material tools
		"texture_picker": {"keycode": KEY_T},
		"apply_last_texture": {"keycode": KEY_T, "shift": true},
		# Selection
		"select_all": {"keycode": KEY_A},
		"deselect_all": {"keycode": KEY_A, "shift": true},
		"select_similar": {"keycode": KEY_S, "shift": true},
		"selection_filter": {"keycode": KEY_F, "shift": true},
		# Axis lock
		"axis_x": {"keycode": KEY_X},
		"axis_y": {"keycode": KEY_Y},
		"axis_z": {"keycode": KEY_Z},
		# Grid snap
		"grid_increase": {"keycode": KEY_BRACKETRIGHT},
		"grid_decrease": {"keycode": KEY_BRACKETLEFT},
		# Viewport menus
		"context_menu": {"keycode": KEY_SPACE},
		"radial_menu": {"keycode": KEY_QUOTELEFT},
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
	if bool(b.get("meta", false)) != event.meta_pressed:
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
	if bool(b.get("meta", false)):
		parts.append("Meta")
	var keycode := int(b.get("keycode", 0))
	parts.append(_keycode_to_label(keycode))
	return "+".join(parts)


## Save current bindings to a JSON file.
func save(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_bindings, "\t"))


## Update a single binding.
##
## A chord another action in the same mode already uses is still written - it is
## what the caller asked for - but it is no longer silent. `plugin_input_router`
## tests actions one at a time and returns on the first hit, so the one it
## happens to check first wins and the other becomes unreachable with nothing
## said anywhere.
func set_binding(
	action: String,
	keycode: int,
	ctrl: bool = false,
	shift: bool = false,
	alt: bool = false,
	meta: bool = false
) -> void:
	var b := {"keycode": keycode}
	if ctrl:
		b["ctrl"] = true
	if shift:
		b["shift"] = true
	if alt:
		b["alt"] = true
	if meta:
		b["meta"] = true
	_bindings[action] = b
	var clashes := conflicts_for(action)
	if not clashes.is_empty():
		(
			HFLog
			. warn(
				(
					"Keymap: '%s' is now %s, which %s already uses. Only one of them will fire."
					% [
						get_action_label(action),
						get_display_string(action),
						_label_list(clashes),
					]
				)
			)
		)


## Actions that would fire on the same chord as `action`, in the same mode.
##
## The defaults share six chords on purpose - E is extrude, erase and edge mode;
## R is rotate and ramp; X, Y and Z are axis locks and paint mirrors - and the
## input router gates each family on its mode, so none of those pairs can both
## fire. So the question is not whether a chord is taken, it is whether it is
## taken by something that can fire at the same time.
func conflicts_for(action: String) -> PackedStringArray:
	var out := PackedStringArray()
	var binding: Dictionary = _bindings.get(action, {})
	if binding.is_empty():
		return out
	var mode := action_mode(action)
	for other in _bindings:
		var other_action := str(other)
		if other_action == action:
			continue
		if action_mode(other_action) != mode:
			continue
		if _same_chord(binding, _bindings[other]):
			out.append(other_action)
	return out


## Which mode an action can fire in. `plugin_input_router` dispatches the paint
## family only while paint mode is on and the vertex family only while vertex
## mode is on, and everything else only while neither is.
static func action_mode(action: String) -> String:
	if action.begins_with("paint_") and action != "toggle_paint_mode":
		return "paint"
	if action.begins_with("vertex_") and action != "vertex_edit":
		return "vertex"
	return "general"


static func _same_chord(a, b) -> bool:
	if not (a is Dictionary and b is Dictionary):
		return false
	if int(a.get("keycode", 0)) != int(b.get("keycode", -1)):
		return false
	for modifier in ["ctrl", "shift", "alt", "meta"]:
		if bool(a.get(modifier, false)) != bool(b.get(modifier, false)):
			return false
	return true


func _label_list(actions: PackedStringArray) -> String:
	var labels := PackedStringArray()
	for action in actions:
		labels.append("'%s'" % get_action_label(action))
	return ", ".join(labels)


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
	if action in ["toggle_operation", "toggle_paint_mode", "quick_play", "validate_level"]:
		return "Workflow"
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
	if action in ["select_all", "deselect_all", "select_similar", "selection_filter"]:
		return "Selection"
	if action in ["rotate_ccw", "rotate_cw", "flip_selection", "reset_rotation"]:
		return "Transform"
	if action in ["context_menu", "radial_menu"]:
		return "Tools"
	return "Editing"


## Map an action name to a human-readable label.
static func get_action_label(action: String) -> String:
	const LABELS := {
		"tool_draw": "Draw",
		"tool_select": "Select",
		"tool_extrude_up": "Extrude Up",
		"tool_extrude_down": "Extrude Down",
		"tool_extrude": "Extrude Up",
		"tool_extrude_down_alt": "Extrude Down",
		"toggle_operation": "Toggle Add / Cut",
		"toggle_paint_mode": "Toggle Paint Mode",
		"quick_play": "Quick Play",
		"validate_level": "Validate Level",
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
		"clip_to_face": "Clip to Face Plane",
		"create_arch": "Create Structure",
		"carve": "Carve",
		"merge": "Merge Brushes",
		"move_to_floor": "Move to Floor",
		"move_to_ceiling": "Move to Ceiling",
		"rotate_ccw": "Rotate CCW",
		"rotate_cw": "Rotate CW",
		"flip_selection": "Flip Selection",
		"reset_rotation": "Reset Rotation",
		"paint_bucket": "Paint Brush",
		"paint_erase": "Erase",
		"paint_ramp": "Ramp / Rect",
		"paint_line": "Line",
		"paint_fill": "Bucket Fill",
		"paint_blend": "Blend",
		"paint_raise": "Raise Painted Walls",
		"paint_mirror_x": "Toggle Paint Mirror X",
		"paint_mirror_z": "Toggle Paint Mirror Z",
		"paint_room": "Stamp Painted Room",
		"paint_confirm_connector": "Confirm Paint Connector",
		"texture_picker": "Texture Picker",
		"apply_last_texture": "Apply Last Texture",
		"select_all": "Select All",
		"deselect_all": "Deselect All",
		"select_similar": "Select Similar",
		"selection_filter": "Selection Filters",
		"axis_x": "Lock X",
		"axis_y": "Lock Y",
		"axis_z": "Lock Z",
		"context_menu": "Context Menu",
		"radial_menu": "Radial Menu",
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
		KEY_QUOTELEFT:
			return "`"
		KEY_BRACKETLEFT:
			return "["
		KEY_BRACKETRIGHT:
			return "]"
	# Single letter keys
	if keycode >= KEY_A and keycode <= KEY_Z:
		return char(keycode)
	if keycode >= KEY_0 and keycode <= KEY_9:
		return str(keycode - KEY_0)
	# Anything else gets Godot's own name for the key rather than its number.
	# "Key91" told a user nothing about which key to press.
	var named := OS.get_keycode_string(keycode)
	return named if named != "" else "Key%d" % keycode
