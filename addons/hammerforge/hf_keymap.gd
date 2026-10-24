@tool
class_name HFKeymap
extends RefCounted

## Customizable keyboard shortcut bindings for HammerForge.
##
## Each action maps to a binding dict: {keycode: int, ctrl: bool, shift: bool, alt: bool},
## with an optional second chord under `second` in the same shape, and `{}` for an
## action with no key. Load from JSON for user customization, or fall back to
## built-in defaults. The shortcut dialog edits a keymap in place and writes the
## entries that differ from the defaults (#1733).

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFCommandRegistry = preload("hf_command_registry.gd")
const HFSettingsFile = preload("hf_settings_file.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The chords Godot 4.7's 3D editor binds by default, from the spatial_editor
## shortcuts in editor/scene/3d/node_3d_editor_plugin.cpp. Escape is left out:
## the cancel ladder already decides when Godot gets it. A HammerForge key on
## one of these steps aside when only Godot nodes are selected, so a mapper with
## a light selected still gets Godot's Rotate on E (#927).
const GODOT_3D_DEFAULTS := [
	{"keycode": KEY_Q},
	{"keycode": KEY_W},
	{"keycode": KEY_E},
	{"keycode": KEY_R},
	{"keycode": KEY_V},
	{"keycode": KEY_M},
	{"keycode": KEY_T},
	{"keycode": KEY_Y},
	{"keycode": KEY_U},
	{"keycode": KEY_P},
	{"keycode": KEY_B},
	{"keycode": KEY_K},
	{"keycode": KEY_O},
	{"keycode": KEY_F},
	{"keycode": KEY_X},
	{"keycode": KEY_Z},
	{"keycode": KEY_PAGEDOWN},
	{"keycode": KEY_NUMBERSIGN},
	{"keycode": KEY_X, "shift": true},
	{"keycode": KEY_Y, "shift": true},
	{"keycode": KEY_Z, "shift": true},
	{"keycode": KEY_G, "shift": true},
	{"keycode": KEY_F, "shift": true},
	{"keycode": KEY_W, "alt": true},
	{"keycode": KEY_E, "alt": true},
	{"keycode": KEY_R, "alt": true},
	{"keycode": KEY_P, "ctrl": true},
	{"keycode": KEY_EQUAL, "ctrl": true},
	{"keycode": KEY_MINUS, "ctrl": true},
	{"keycode": KEY_0, "ctrl": true},
	{"keycode": KEY_1, "ctrl": true},
	{"keycode": KEY_2, "ctrl": true},
	{"keycode": KEY_3, "ctrl": true},
	{"keycode": KEY_4, "ctrl": true},
	{"keycode": KEY_2, "ctrl": true, "alt": true},
	{"keycode": KEY_3, "ctrl": true, "alt": true},
	{"keycode": KEY_F, "ctrl": true, "alt": true},
	{"keycode": KEY_M, "ctrl": true, "alt": true},
	{"keycode": KEY_G, "ctrl": true, "alt": true},
	{"keycode": KEY_KP_0, "ctrl": true, "alt": true},
	{"keycode": KEY_KP_1},
	{"keycode": KEY_KP_2},
	{"keycode": KEY_KP_3},
	{"keycode": KEY_KP_4},
	{"keycode": KEY_KP_5},
	{"keycode": KEY_KP_6},
	{"keycode": KEY_KP_7},
	{"keycode": KEY_KP_8},
	{"keycode": KEY_KP_9},
	{"keycode": KEY_KP_1, "alt": true},
	{"keycode": KEY_KP_3, "alt": true},
	{"keycode": KEY_KP_7, "alt": true},
]

## The chords Godot 4.7's editor answers wherever the focus is: Undo and Redo
## (`ui_undo` and `ui_redo` in core/input/input_map.cpp), the scene file and Quit
## shortcuts in editor/editor_node.cpp and the run keys in
## editor/run/editor_run_bar.cpp. Only those no HammerForge default takes; the
## viewport keeps Ctrl+Shift+F, Ctrl+Shift+P, Ctrl+Shift+T and F1 on purpose. The
## router hands these to Godot ahead of every binding and `conflicts_for()` reports
## a binding on one as taken, so no binding can take Undo or Save (#1617).
const GODOT_EDITOR_KEYS := [
	{"keycode": KEY_Z, "ctrl": true},
	{"keycode": KEY_Y, "ctrl": true},
	{"keycode": KEY_Z, "ctrl": true, "shift": true},
	{"keycode": KEY_S, "ctrl": true},
	{"keycode": KEY_S, "ctrl": true, "shift": true},
	{"keycode": KEY_S, "ctrl": true, "shift": true, "alt": true},
	{"keycode": KEY_N, "ctrl": true},
	{"keycode": KEY_N, "ctrl": true, "shift": true},
	{"keycode": KEY_O, "ctrl": true},
	{"keycode": KEY_O, "ctrl": true, "shift": true},
	{"keycode": KEY_O, "ctrl": true, "alt": true},
	{"keycode": KEY_O, "shift": true, "alt": true},
	{"keycode": KEY_W, "ctrl": true, "shift": true},
	{"keycode": KEY_Q, "ctrl": true},
	{"keycode": KEY_Q, "ctrl": true, "shift": true},
	{"keycode": KEY_F5},
	{"keycode": KEY_F5, "ctrl": true, "shift": true},
	{"keycode": KEY_F6},
	{"keycode": KEY_F7},
	{"keycode": KEY_F8},
]
## What a clash with one of `GODOT_EDITOR_KEYS` is called in a report.
const GODOT_EDITOR := "godot_editor"

## Keys held through a drag rather than pressed to run a command, with what the
## docs and hints call them (#1431, #1399). They are bindings like the rest, so a
## hint names whatever they are bound to and a user's file can move them, but
## they run nothing: `get_actions()`, which the palette, the shortcut list and
## the command sweeps read, leaves them out. A hold is one key, read with
## `held()`; modifiers in its binding are not part of it.
const HOLDS := {
	"snap_invert_hold": "Invert Grid Snap (hold)",
	"snap_vertex_hold": "Snap to Vertices (hold)",
}

## Keys the input router takes ahead of every binding, and no binding moves: the
## command palette's three chords, Escape's cancel ladder, and a nudge (#1614).
## A chord names its keys, the modifiers it needs, and in `any` the ones it is
## taken with whether held or not, so F1 opens the palette whatever else is down.
## Alt with PgUp or PgDn alone is Grid Up and Grid Down, so a vertical tenth takes
## Shift as well. Ctrl's nudge is the shortcut stage's (`plugin_shortcuts.gd`),
## which the viewport passes it on to, so a binding on it would take it there. The
## router matches these through `fixed_key()`, and `conflicts_for()` reports a
## binding on any of them as taken, so neither can drift from the other.
const FIXED_KEYS := {
	"command_palette":
	{
		"label": "Command Palette",
		"chords":
		[
			{"keys": [KEY_F1], "any": ["ctrl", "shift", "alt", "meta"]},
			{"keys": [KEY_SLASH], "shift": true, "any": ["ctrl", "alt", "meta"]},
			{"keys": [KEY_K], "ctrl": true, "any": ["shift", "alt", "meta"]},
		],
	},
	"cancel":
	{
		"label": "Cancel",
		"chords": [{"keys": [KEY_ESCAPE], "any": ["ctrl", "shift", "alt", "meta"]}],
	},
	"nudge":
	{
		"label": "Nudge",
		"chords":
		[
			{"keys": [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT], "any": ["shift", "alt", "meta"]},
			{"keys": [KEY_PAGEUP, KEY_PAGEDOWN], "any": ["shift", "meta"]},
			{"keys": [KEY_PAGEUP, KEY_PAGEDOWN], "shift": true, "alt": true, "any": ["meta"]},
			{
				"keys": [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN],
				"ctrl": true,
				"any": ["shift", "alt", "meta"],
			},
		],
	},
}

## The actions the router answers ahead of a mode's own keys, so in every tool
## and mode: the workflow switches at the top of `plugin_input_router.gd` and the
## two viewport menus. In paint mode the paint keys come next and every other
## action after them, so a paint key on a general action's chord just takes it for
## as long as paint mode is on, but a paint key on one of these never fires
## (#1614). Vertex keys are asked before the router, so a vertex key on one of
## these takes it from a switch that should answer everywhere.
const EVERY_MODE := [
	"toggle_operation",
	"toggle_paint_mode",
	"quick_play",
	"validate_level",
	"toggle_selection_size",
	"toggle_operation_replay",
	"context_menu",
	"radial_menu",
]

## A binding, or a chord, changed: what shows chords redraws them.
signal changed

## What a user file writes for an action they took the key off.
const NO_KEY := {"none": true}

var _bindings: Dictionary = {}
## The file this keymap was read from and writes its changes to, or "" for one
## that writes nothing, as a test's does.
var _path := ""


static func load_or_default(path: String = "") -> HFKeymap:
	var km = HFKeymap.new()
	km._path = path
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
		# Any command the palette runs can take a key, not only those that ship
		# with one (#1733).
		if not defaults.has(key) and not HFCommandRegistry.dispatches(key):
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
		if binding.get("none") == true:
			out[key] = {}
			continue
		var chord := _read_chord(binding, path, key)
		if chord.is_empty():
			continue
		if binding.get("second") is Dictionary:
			var second := _read_chord(binding["second"], path, key + " (second)")
			if not second.is_empty():
				chord["second"] = second
		out[key] = chord
	for action in defaults:
		if not out.has(action):
			out[action] = defaults[action]
	_warn_about_conflicts(out, path)
	return out


## One chord out of a file's entry, its key name read into a keycode, or `{}`,
## said, when it has no usable key.
static func _read_chord(raw: Dictionary, path: String, key: String) -> Dictionary:
	var chord := {}
	var keycode = raw.get("keycode", null)
	# A key name ("F", "PageDown", "BracketLeft") is what a person writes by
	# hand. Modifiers belong in ctrl, shift and alt, so a name carrying one is
	# refused rather than half read.
	if keycode is String:
		var named := OS.find_keycode_from_string(keycode)
		if named == KEY_NONE or (named & KEY_MODIFIER_MASK) != 0:
			HFLog.warn(
				(
					"%s: '%s' names a key Godot does not know: '%s'. The default is used."
					% [path, key, keycode]
				)
			)
			return {}
		keycode = int(named)
	if not (keycode is int or keycode is float) or int(keycode) == 0:
		HFLog.warn("%s: '%s' has no usable keycode. The default is used." % [path, key])
		return {}
	chord["keycode"] = int(keycode)
	for modifier in ["ctrl", "shift", "alt", "meta"]:
		if raw.get(modifier) == true:
			chord[modifier] = true
	return chord


## One line per pair of actions that can fire in the same mode on one chord, and
## per action on a key the router takes first. A hand-edited file is where these
## arrive, so the load is where to say so.
static func _warn_about_conflicts(bindings: Dictionary, path: String) -> void:
	var reported: Dictionary = {}
	for action in bindings:
		var first := str(action)
		for second in _clashes_in(bindings, first):
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


## The defaults, built once: `user_bound_command()` asks on every key press.
static var _default_cache: Dictionary = {}


static func _defaults() -> Dictionary:
	if _default_cache.is_empty():
		_default_cache = _default_bindings()
	return _default_cache


static func _default_bindings() -> Dictionary:
	return {
		# Tool selection
		"tool_draw": {"keycode": KEY_D},
		"tool_select": {"keycode": KEY_S},
		"tool_extrude_up": {"keycode": KEY_U},
		"tool_extrude_down": {"keycode": KEY_J},
		"tool_extrude": {"keycode": KEY_E},
		"tool_extrude_down_alt": {"keycode": KEY_E, "shift": true},
		# The tools in the toolbar's second row, each a bare key (#1820).
		"measure": {"keycode": KEY_M},
		"tool_decal": {"keycode": KEY_N},
		"tool_polygon": {"keycode": KEY_P},
		"tool_path": {"keycode": KEY_SEMICOLON},
		"tool_clip": {"keycode": KEY_C},
		# Draw's own key with Shift: the last brush drawn, again (#1407).
		"repeat_brush": {"keycode": KEY_D, "shift": true},
		# Workflow accelerators
		"toggle_operation": {"keycode": KEY_Q},
		"toggle_paint_mode": {"keycode": KEY_P, "shift": true},
		"quick_play": {"keycode": KEY_ENTER, "ctrl": true},
		"validate_level": {"keycode": KEY_ENTER, "ctrl": true, "shift": true},
		# Editing
		"delete": {"keycode": KEY_DELETE},
		"duplicate": {"keycode": KEY_D, "ctrl": true},
		"copy": {"keycode": KEY_C, "ctrl": true},
		"paste": {"keycode": KEY_V, "ctrl": true},
		"paste_at_cursor": {"keycode": KEY_V, "ctrl": true, "alt": true},
		"group": {"keycode": KEY_G, "ctrl": true},
		"ungroup": {"keycode": KEY_U, "ctrl": true},
		"hollow": {"keycode": KEY_H, "ctrl": true},
		"hide_selection": {"keycode": KEY_H, "alt": true},
		"show_hidden": {"keycode": KEY_H, "alt": true, "shift": true},
		"clip": {"keycode": KEY_X, "shift": true},
		"clip_to_face": {"keycode": KEY_X, "shift": true, "alt": true},
		"create_arch": {"keycode": KEY_A, "ctrl": true, "shift": true},
		"run_trim_along_faces": {"keycode": KEY_T, "shift": true, "alt": true},
		"carve": {"keycode": KEY_R, "shift": true, "ctrl": true},
		"merge": {"keycode": KEY_M, "ctrl": true, "shift": true},
		"intersect": {"keycode": KEY_I, "ctrl": true, "shift": true},
		"quick_save_prefab": {"keycode": KEY_P, "ctrl": true, "shift": true},
		"cycle_variant": {"keycode": KEY_V, "ctrl": true, "shift": true},
		"move_to_floor": {"keycode": KEY_F, "ctrl": true, "shift": true},
		"move_to_ceiling": {"keycode": KEY_C, "ctrl": true, "shift": true},
		# Shared with Snap Vertices to Grid, which fires only in vertex mode.
		"snap_to_grid": {"keycode": KEY_B, "ctrl": true},
		# Free transform. R is also paint_ramp, which plugin_input_router only
		# dispatches while paint mode is active, so the two never both fire.
		"rotate_ccw": {"keycode": KEY_R},
		"rotate_cw": {"keycode": KEY_R, "shift": true},
		"flip_selection": {"keycode": KEY_M, "shift": true},
		"mirror_copy": {"keycode": KEY_M, "alt": true},
		"reset_rotation": {"keycode": KEY_R, "alt": true},
		"offset_selection": {"keycode": KEY_G, "alt": true},
		"pick_pivot": {"keycode": KEY_P, "alt": true},
		"clear_pivot": {"keycode": KEY_P, "shift": true, "alt": true},
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
		"vertex_snap_to_grid": {"keycode": KEY_B, "ctrl": true},
		# Material tools
		"texture_picker": {"keycode": KEY_T},
		"apply_last_texture": {"keycode": KEY_T, "shift": true},
		"apply_picked_look": {"keycode": KEY_T, "alt": true},
		# The context toolbar's favourites, by number (#1439). Alt and a top-row
		# digit is free in Godot's 3D editor; mid-draw the digit is a typed size.
		"apply_favorite_1": {"keycode": KEY_1, "alt": true},
		"apply_favorite_2": {"keycode": KEY_2, "alt": true},
		"apply_favorite_3": {"keycode": KEY_3, "alt": true},
		"apply_favorite_4": {"keycode": KEY_4, "alt": true},
		"apply_favorite_5": {"keycode": KEY_5, "alt": true},
		"apply_favorite_6": {"keycode": KEY_6, "alt": true},
		"apply_favorite_7": {"keycode": KEY_7, "alt": true},
		"apply_favorite_8": {"keycode": KEY_8, "alt": true},
		"apply_favorite_9": {"keycode": KEY_9, "alt": true},
		# Selection
		"select_all": {"keycode": KEY_A},
		"deselect_all": {"keycode": KEY_A, "shift": true},
		"select_similar": {"keycode": KEY_S, "shift": true},
		# Not Shift+F, which is Godot's Toggle Freelook (#927).
		"selection_filter": {"keycode": KEY_F, "alt": true},
		# Ctrl and a bracket: the bare brackets are the grid size (#1433).
		"grow_selection": {"keycode": KEY_BRACKETRIGHT, "ctrl": true},
		"shrink_selection": {"keycode": KEY_BRACKETLEFT, "ctrl": true},
		# Alt+X alone: Shift+Alt+X is Clip to Face Plane (#1432).
		"toggle_face_xray": {"keycode": KEY_X, "alt": true},
		"toggle_selection_size": {"keycode": KEY_D, "alt": true},
		# Axis lock
		"axis_x": {"keycode": KEY_X},
		"axis_y": {"keycode": KEY_Y},
		"axis_z": {"keycode": KEY_Z},
		# L is the paint Line tool only while Paint is on (#1401).
		"toggle_draw_on_face": {"keycode": KEY_L},
		# Grid snap
		"grid_increase": {"keycode": KEY_BRACKETRIGHT},
		"grid_decrease": {"keycode": KEY_BRACKETLEFT},
		"grid_up": {"keycode": KEY_PAGEUP, "alt": true},
		"grid_down": {"keycode": KEY_PAGEDOWN, "alt": true},
		"grid_reset": {"keycode": KEY_HOME, "alt": true},
		"grid_align": {"keycode": KEY_END, "alt": true},
		# Viewport menus
		"context_menu": {"keycode": KEY_SPACE},
		"radial_menu": {"keycode": KEY_QUOTELEFT},
		# The Operation Replay timeline, a power-user overlay like the radial menu.
		"toggle_operation_replay": {"keycode": KEY_T, "ctrl": true, "shift": true},
		# Held through a drag (HOLDS). Ctrl is free once a drag is under way: a
		# click's own Ctrl is read at the press. Alt is unused in a vertex or
		# handle drag, and in a draw it means height, which these do not reach.
		"snap_invert_hold": {"keycode": KEY_CTRL},
		"snap_vertex_hold": {"keycode": KEY_ALT},
	}


## Returns true if the given event matches the binding for the named action, by
## its first chord or its second.
func matches(action: String, event: InputEventKey) -> bool:
	for chord in _chords(_bindings.get(action, {})):
		if _chord_matches(chord, event):
			return true
	return false


static func _chord_matches(chord: Dictionary, event: InputEventKey) -> bool:
	if event.keycode != int(chord.get("keycode", 0)):
		return false
	if bool(chord.get("ctrl", false)) != event.ctrl_pressed:
		return false
	if bool(chord.get("shift", false)) != event.shift_pressed:
		return false
	if bool(chord.get("alt", false)) != event.alt_pressed:
		return false
	if bool(chord.get("meta", false)) != event.meta_pressed:
		return false
	return true


## The chords a binding holds: its own, and its second when it has one.
static func _chords(binding: Variant) -> Array:
	if not (binding is Dictionary) or (binding as Dictionary).is_empty():
		return []
	var first := (binding as Dictionary).duplicate()
	first.erase("second")
	var out: Array = [first]
	var second: Variant = binding.get("second")
	if second is Dictionary and not (second as Dictionary).is_empty():
		out.append(second)
	return out


## The command a key press runs that has no key by default and was given one, or
## "". The router asks the actions it knows by name first; this is how a command
## bound in the shortcut dialog is reached (#1733).
func user_bound_command(event: InputEventKey) -> String:
	var defaults := _defaults()
	for action in _bindings:
		if defaults.has(action) or HOLDS.has(action):
			continue
		if matches(str(action), event):
			return str(action)
	return ""


## Whether the key bound to the hold `action` is down as of `event`. A modifier
## is read off the event, so a mouse motion says whether it is held, and the
## key's own press or release says so too. Any other key is asked of `Input`.
func held(action: String, event: InputEvent) -> bool:
	var b: Dictionary = _bindings.get(action, {})
	if b.is_empty():
		return false
	var keycode := int(b.get("keycode", 0))
	if event is InputEventKey and (event as InputEventKey).keycode == keycode:
		return (event as InputEventKey).pressed
	if event is InputEventWithModifiers:
		var mods := event as InputEventWithModifiers
		match keycode:
			KEY_CTRL:
				return mods.ctrl_pressed
			KEY_SHIFT:
				return mods.shift_pressed
			KEY_ALT:
				return mods.alt_pressed
			KEY_META:
				return mods.meta_pressed
	return Input.is_key_pressed(keycode)


## Whether Godot's 3D editor binds this key press by default.
static func godot_3d_uses(event: InputEventKey) -> bool:
	var chord := _chord_of(event)
	for binding in GODOT_3D_DEFAULTS:
		if _same_chord(binding, chord):
			return true
	return false


## Whether Godot's editor answers this key press wherever the focus is.
static func godot_editor_uses(event: InputEventKey) -> bool:
	return _godot_editor_takes(_chord_of(event))


static func _godot_editor_takes(binding: Dictionary) -> bool:
	for chord in GODOT_EDITOR_KEYS:
		if _same_chord(chord, binding):
			return true
	return false


## The `FIXED_KEYS` entry that takes this key press ahead of every binding, or ""
## when none does.
static func fixed_key(event: InputEventKey) -> String:
	var chord := _chord_of(event)
	for fixed in FIXED_KEYS:
		if _fixed_takes(str(fixed), chord):
			return str(fixed)
	return ""


static func _chord_of(event: InputEventKey) -> Dictionary:
	return {
		"keycode": event.keycode,
		"ctrl": event.ctrl_pressed,
		"shift": event.shift_pressed,
		"alt": event.alt_pressed,
		"meta": event.meta_pressed,
	}


## Whether the `FIXED_KEYS` entry `fixed` takes the chord `binding` names.
static func _fixed_takes(fixed: String, binding: Dictionary) -> bool:
	var keycode := int(binding.get("keycode", 0))
	for chord in FIXED_KEYS[fixed]["chords"]:
		if not chord["keys"].has(keycode):
			continue
		var fits := true
		for modifier in ["ctrl", "shift", "alt", "meta"]:
			if chord.get("any", []).has(modifier):
				continue
			if bool(binding.get(modifier, false)) != bool(chord.get(modifier, false)):
				fits = false
				break
		if fits:
			return true
	return false


## Get a human-readable display string for an action's binding (e.g. "Ctrl+H"):
## its first chord, which every surface that names a key shows.
func get_display_string(action: String) -> String:
	var b: Dictionary = _bindings.get(action, {})
	if b.is_empty():
		return "?"
	return chord_text(b)


## A chord as the editor writes one, such as "Ctrl+Shift+T".
static func chord_text(chord: Dictionary) -> String:
	var parts: PackedStringArray = []
	if bool(chord.get("ctrl", false)):
		parts.append("Ctrl")
	if bool(chord.get("shift", false)):
		parts.append("Shift")
	if bool(chord.get("alt", false)):
		parts.append("Alt")
	if bool(chord.get("meta", false)):
		parts.append("Meta")
	parts.append(_keycode_to_label(int(chord.get("keycode", 0))))
	return "+".join(parts)


## The chord an action holds in `slot`, 0 its first and 1 its second, or `{}`.
func chord_of(action: String, slot: int) -> Dictionary:
	var chords := _chords(_bindings.get(action, {}))
	return chords[slot] if slot < chords.size() else {}


## A key press as a chord a binding can hold.
static func chord_from_event(event: InputEventKey) -> Dictionary:
	var chord := {"keycode": int(event.keycode)}
	for modifier in ["ctrl", "shift", "alt", "meta"]:
		if bool(event.get(modifier + "_pressed")):
			chord[modifier] = true
	return chord


## Whether this keymap knows an action at all.
func has_action(action: String) -> bool:
	return _bindings.has(action)


## Replace every `{action}` in `text` with the chord bound to that action.
##
## The surfaces that tell a mapper which key does what used to spell their
## chords into string literals, so a rebind left them advertising a chord that
## no longer did anything, and changing a default here left them behind with no
## error. A token naming an action nothing is bound to is left alone rather than
## quietly turning into "?", so a typo is visible on screen and a test can find
## it.
func format_chords(text: String) -> String:
	var out := ""
	var rest := text
	while true:
		var open_at := rest.find("{")
		if open_at < 0:
			return out + rest
		var close_at := rest.find("}", open_at)
		if close_at < 0:
			return out + rest
		var action := rest.substr(open_at + 1, close_at - open_at - 1)
		if has_action(action):
			out += rest.substr(0, open_at) + get_display_string(action)
		else:
			out += rest.substr(0, close_at + 1)
		rest = rest.substr(close_at + 1)
	return out


## Save current bindings to a JSON file, whole or not at all (#1663).
func save(path: String) -> void:
	var err := HFSettingsFile.write_text(path, JSON.stringify(_bindings, "\t"))
	if err != OK:
		HFLog.warn("Keymap: cannot write %s (%s)" % [path, error_string(err)])


## Give `action` the chord `chord` in `slot`, 0 its first and 1 its second, and
## say so. A second chord on an action with no first becomes its first.
func set_chord(action: String, chord: Dictionary, slot: int = 0) -> void:
	var clean := {"keycode": int(chord.get("keycode", 0))}
	for modifier in ["ctrl", "shift", "alt", "meta"]:
		if bool(chord.get(modifier, false)):
			clean[modifier] = true
	var chords := _chords(_bindings.get(action, {}))
	if slot <= 0 or chords.is_empty():
		var kept: Variant = chords[1] if chords.size() > 1 else null
		_bindings[action] = _binding_from(clean, kept)
	else:
		_bindings[action] = _binding_from(chords[0], clean)
	changed.emit()


## Take the chord in `slot` off `action`, or every chord with -1. Taking its first
## moves its second up.
func clear_chord(action: String, slot: int = -1) -> void:
	var chords := _chords(_bindings.get(action, {}))
	if slot < 0:
		_bindings[action] = {}
	elif slot == 0:
		_bindings[action] = _binding_from(chords[1], null) if chords.size() > 1 else {}
	elif chords.size() > 1:
		_bindings[action] = _binding_from(chords[0], null)
	changed.emit()


## Put `action` back to the key it ships with, or none.
func reset_binding(action: String) -> void:
	var defaults := _defaults()
	if defaults.has(action):
		_bindings[action] = (defaults[action] as Dictionary).duplicate(true)
	else:
		_bindings.erase(action)
	changed.emit()


## Every action back to the keys they ship with.
func reset_all() -> void:
	_bindings = _default_bindings()
	changed.emit()


## The actions that would fire on `chord` if `action` held it, and the keys taken
## ahead of every binding that it would land on, as `conflicts_for()` names them.
func clashes_if(action: String, chord: Dictionary, slot: int = 0) -> PackedStringArray:
	var trial := _bindings.duplicate(true)
	var chords := _chords(trial.get(action, {}))
	if slot <= 0 or chords.is_empty():
		trial[action] = _binding_from(chord, null)
	else:
		trial[action] = _binding_from(chords[0], chord)
	var out := PackedStringArray()
	for clash in _clashes_in(trial, action):
		# Only what the new chord meets, not a clash the other slot already had.
		var other: Variant = trial.get(clash, null)
		if other is Dictionary and _shares_a_chord(_binding_from(chord, null), other):
			out.append(clash)
		elif not (other is Dictionary) and _takes_ahead(clash, chord):
			out.append(clash)
	return out


static func _takes_ahead(taker: String, chord: Dictionary) -> bool:
	if taker == GODOT_EDITOR:
		return _godot_editor_takes(chord)
	return FIXED_KEYS.has(taker) and _fixed_takes(taker, chord)


static func _binding_from(first: Dictionary, second: Variant) -> Dictionary:
	var out := first.duplicate()
	out.erase("second")
	if second is Dictionary and not (second as Dictionary).is_empty():
		out["second"] = (second as Dictionary).duplicate()
	return out


## The entries that differ from the defaults: what a user file holds, so a later
## change to a default reaches every action the user left alone.
func changes() -> Dictionary:
	var defaults := _defaults()
	var out := {}
	for action in _bindings:
		var binding: Dictionary = _bindings[action]
		if defaults.has(action):
			if binding.is_empty():
				out[action] = NO_KEY.duplicate()
			elif not _same_binding(binding, defaults[action]):
				out[action] = binding.duplicate(true)
		elif not binding.is_empty():
			out[action] = binding.duplicate(true)
	return out


static func _same_binding(a: Dictionary, b: Dictionary) -> bool:
	var a_chords := _chords(a)
	var b_chords := _chords(b)
	if a_chords.size() != b_chords.size():
		return false
	for i in a_chords.size():
		if not _same_chord(a_chords[i], b_chords[i]):
			return false
	return true


## Write the changes to the file this keymap was read from, whole. Nothing for a
## keymap read from no file. OK, or why not.
func save_changes() -> int:
	if _path == "":
		return OK
	return export_to(_path)


## Write the changes to `path`, for a team to share. OK, or why not.
func export_to(path: String) -> int:
	var err := HFSettingsFile.write_text(path, JSON.stringify(changes(), "\t", true) + "\n")
	if err != OK:
		HFLog.warn("Keymap: cannot write %s (%s)" % [path, error_string(err)])
	return err


## Take the bindings a shared file holds, over the defaults. False, with the
## keymap as it was, for a file that is not a keymap.
func import_from(path: String) -> bool:
	var parser := JSON.new()
	if not FileAccess.file_exists(path) or parser.parse(FileAccess.get_file_as_string(path)) != OK:
		HFLog.warn("Keymap: %s is not a keymap file" % path)
		return false
	if not (parser.data is Dictionary):
		HFLog.warn("Keymap: %s is not a keymap file" % path)
		return false
	_bindings = _validated(parser.data, _default_bindings(), path)
	changed.emit()
	return true


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


## Actions that would fire on the same chord as `action`, in the same mode, and
## the `FIXED_KEYS` entry that takes the chord ahead of it, if one does.
##
## The defaults share seven chords on purpose - E is extrude, erase and edge mode;
## R is rotate and ramp; X, Y and Z are axis locks and paint mirrors; Ctrl+B snaps
## the selection or, in vertex mode, its vertices - and the input router asks a
## mode's own keys first while the mode is on, so none of those pairs can both
## fire. So the question is not whether a chord is taken, it is whether it is
## taken by something that can fire at the same time.
func conflicts_for(action: String) -> PackedStringArray:
	return _clashes_in(_bindings, action)


## `conflicts_for()` over any bindings, so the load can ask it of a user's file.
static func _clashes_in(bindings: Dictionary, action: String) -> PackedStringArray:
	var out := PackedStringArray()
	var binding = bindings.get(action, {})
	if not (binding is Dictionary) or binding.is_empty():
		return out
	for other in bindings:
		var other_action := str(other)
		if other_action == action or not _fire_together(action, other_action):
			continue
		if _shares_a_chord(binding, bindings[other]):
			out.append(other_action)
	# A hold is read through a drag, never matched, so no fixed key takes it.
	if action_mode(action) != "hold":
		for chord in _chords(binding):
			for fixed in FIXED_KEYS:
				if _fixed_takes(str(fixed), chord) and not out.has(str(fixed)):
					out.append(str(fixed))
			if _godot_editor_takes(chord) and not out.has(GODOT_EDITOR):
				out.append(GODOT_EDITOR)
	return out


## Whether any chord of `a` is any chord of `b`.
static func _shares_a_chord(a: Variant, b: Variant) -> bool:
	for chord_a in _chords(a):
		for chord_b in _chords(b):
			if _same_chord(chord_a, chord_b):
				return true
	return false


## Whether `a` and `b` can both answer one press. Two actions of one mode can,
## and an `EVERY_MODE` action can with any action; a general action and a mode's
## own key cannot, because the router asks the mode's keys first while it is on.
static func _fire_together(a: String, b: String) -> bool:
	var mode_a := action_mode(a)
	var mode_b := action_mode(b)
	if mode_a == "hold" or mode_b == "hold":
		return mode_a == mode_b
	return mode_a == mode_b or EVERY_MODE.has(a) or EVERY_MODE.has(b)


## Which mode an action belongs to. `plugin_input_router` dispatches the paint
## family only while paint mode is on and the vertex family only while vertex
## mode is on, and asks them before the general actions then, so a general
## action sharing a chord with one answers it only while neither mode is on,
## unless it is in `EVERY_MODE`.
## A hold is read through a drag, never matched as a chord, so it clashes only
## with another hold.
static func action_mode(action: String) -> String:
	if HOLDS.has(action):
		return "hold"
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


## Get all action names: the commands, without the holds.
func get_actions() -> PackedStringArray:
	var result := PackedStringArray()
	for key in _bindings.keys():
		if not HOLDS.has(key):
			result.append(str(key))
	return result


## The actions bucketed by `get_category()`, for the categories in `order` and in
## that order: `[[category, actions], ...]`. A category with no action is left out.
## The hotkey palette and the shortcut dialog both list actions this way, each in
## an order of its own (#906).
func grouped_actions(order: Array) -> Array:
	var by_category: Dictionary = {}
	for action in get_actions():
		var category := get_category(action)
		if not by_category.has(category):
			by_category[category] = []
		by_category[category].append(action)
	var out: Array = []
	for category in order:
		var actions: Array = by_category.get(category, [])
		if not actions.is_empty():
			out.append([category, actions])
	return out


## Get a copy of all bindings for display purposes.
func get_all_bindings() -> Dictionary:
	return _bindings.duplicate()


## The group the palette and the rebind dialog list an action under. Kept in
## `HFCommandRegistry` with the rest of what describes a command; a name the table
## does not know is "Editing".
static func get_category(action: String) -> String:
	var category := HFCommandRegistry.category(action)
	return category if category != "" else "Editing"


## What the palette and the rebind dialog call an action. Kept in
## `HFCommandRegistry`; a name the table does not know reads as its words.
static func get_action_label(action: String) -> String:
	if HOLDS.has(action):
		return HOLDS[action]
	if FIXED_KEYS.has(action):
		return FIXED_KEYS[action]["label"]
	if action == GODOT_EDITOR:
		return "Godot's own shortcut"
	var label := HFCommandRegistry.label(action)
	return label if label != "" else action.capitalize().replace("_", " ")


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
		KEY_SEMICOLON:
			return ";"
	# Single letter keys
	if keycode >= KEY_A and keycode <= KEY_Z:
		return char(keycode)
	if keycode >= KEY_0 and keycode <= KEY_9:
		return str(keycode - KEY_0)
	# Anything else gets Godot's own name for the key rather than its number.
	# "Key91" told a user nothing about which key to press.
	var named := OS.get_keycode_string(keycode)
	return named if named != "" else "Key%d" % keycode
