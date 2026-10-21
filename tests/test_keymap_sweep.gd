extends "res://tests/support/plugin_sweep_case.gd"
## Every key binding in `HFKeymap`, and the few chords the router hard-wires,
## pressed through the plugin's input path in every state the palette sweep runs.
##
## A key reaches HammerForge the way the editor delivers it. The 3D viewport's
## surface has focus, its `gui_input` hands the press to `_forward_3d_gui_input`,
## and unless the plugin marked it handled Godot goes on to the shortcut stage,
## where `_shortcut_input` (`plugin_shortcuts.gd`) sees it. Here the plugin sits
## in a SubViewport of its own beside a stand-in surface, and each press and
## release is pushed into that viewport, so Godot's own dispatch decides who sees
## it after the forward, as it does in the editor.
##
## A paint key is pressed in paint mode and a vertex key in vertex mode, with that
## mode's own key before and after, since in any other mode the chord belongs to
## another action: E is extrude, erase and edge mode. Each press counts as a
## separate one, never the second half of a double tap.
##
## The checks are the palette sweep's: no script error, no level made where there
## was none, and with nothing selected the level as it was, unless the key works
## on the level as a whole. A key no state ever consumes reaches nothing, so that
## fails too.

## Chords `plugin_input_router.gd` and `plugin_shortcuts.gd` match without the
## keymap. Ctrl+Arrow reaches only the shortcut stage: the viewport router leaves
## a nudge with Ctrl held to it.
const FIXED_KEYS := {
	"escape": {"keycode": KEY_ESCAPE},
	"palette_f1": {"keycode": KEY_F1},
	"palette_question_mark": {"keycode": KEY_SLASH, "shift": true},
	"palette_ctrl_k": {"keycode": KEY_K, "ctrl": true},
	"operation_replay": {"keycode": KEY_T, "ctrl": true, "shift": true},
	"nudge_left": {"keycode": KEY_LEFT},
	"nudge_page_up": {"keycode": KEY_PAGEUP},
	"global_nudge_right": {"keycode": KEY_RIGHT, "ctrl": true},
	"tenth_nudge_right": {"keycode": KEY_RIGHT, "alt": true},
	"tenth_nudge_page_up": {"keycode": KEY_PAGEUP, "shift": true, "alt": true},
}

## Keys that work on the level as a whole, so may change it with nothing
## selected. Create Structure builds at the origin when nothing is selected, the
## grid size is the level's own setting, and Quick Play makes a default spawn
## when the level has none, and bakes.
const WHOLE_LEVEL_KEYS := ["create_arch", "grid_decrease", "grid_increase", "quick_play"]

## Failures this sweep found that are filed and not fixed yet, as
## "action|state": issue. Their errors are let through and the case is marked
## pending; once one stops failing, the sweep says to take it off.
const KNOWN := {}

var _viewport: SubViewport
var _surface: Control
var _camera: Camera3D


static func swept_keys() -> Array:
	var keys: Array = Array(HFKeymapScript.load_or_default("").get_actions())
	keys.append_array(FIXED_KEYS.keys())
	return keys


func test_the_sweep_reads_every_binding():
	var keys := swept_keys()
	assert_gt(keys.size(), 50, "the keymap's bindings were read")
	for key in FIXED_KEYS:
		assert_false(_keymap.has_action(key), "%s is not a keymap action as well" % key)
	for known in KNOWN:
		var parts: PackedStringArray = str(known).split("|")
		assert_has(keys, parts[0], "KNOWN names a real key: %s" % known)
		assert_has(STATES, parts[1], "KNOWN names a real state: %s" % known)


func test_every_key_in_every_state(key = use_parameters(swept_keys())):
	await _bring_up_behind_a_surface()
	if plugin == null:
		fail_test(PluginStandIn.error())
		return
	var consumed := false
	for state in STATES:
		if await _check(key, state):
			consumed = true
	assert_true(consumed, "%s was consumed in some state" % key)
	await _take_down()
	assert_no_new_orphans("%s left nodes behind" % key)


## Returns whether the key was consumed, so went no further than HammerForge.
func _check(key: String, state: String) -> bool:
	var label := "%s in %s" % [key, state]
	var root = await _enter_state(state)
	plugin.stand_in_undo.clear()
	var before := _snapshot(root)
	var errors_before := get_errors().size()
	var mode_key := _mode_key(key)
	if mode_key != "":
		await _press(mode_key)
	var consumed := await _press(key)
	if await _accept_dialogs() > 0:
		label += ", then OK"
	await _settle(root)
	if mode_key != "" and _in_mode(mode_key):
		await _press(mode_key)
	var errors: Array = get_errors().slice(errors_before)
	var known := "%s|%s" % [key, state]
	if KNOWN.has(known):
		for e in errors:
			e.handled = true
		if errors.is_empty():
			fail_test("%s no longer fails; take it off KNOWN (%s)" % [label, KNOWN[known]])
		else:
			pending("%s: %s" % [label, KNOWN[known]])
	else:
		assert_eq(_describe(errors), [], "%s raised no error" % label)
	if state == "no_level":
		assert_eq(_level_roots(), 0, "%s made no level" % label)
	elif state == "nothing_selected" and not WHOLE_LEVEL_KEYS.has(key):
		assert_eq(_snapshot(root), before, "%s left the level as it was" % label)
	_escape_to_idle(root)
	plugin.stand_in_undo.clear()
	await _leave_level(root)
	return consumed


## The key that puts the plugin in the mode `key` fires in, or "" for none.
func _mode_key(key: String) -> String:
	if not _keymap.has_action(key):
		return ""
	match HFKeymapScript.action_mode(key):
		"paint":
			return "toggle_paint_mode"
		"vertex":
			return "vertex_edit"
	return ""


func _in_mode(mode_key: String) -> bool:
	if mode_key == "toggle_paint_mode":
		return plugin.dock != null and plugin.dock.is_paint_mode_enabled()
	return plugin._vertex_mode


## Press and release `key` with the viewport surface focused, the way a mapper
## who has just clicked in the viewport does. True when the plugin consumed the
## press.
func _press(key: String) -> bool:
	var binding: Dictionary = (
		FIXED_KEYS[key] if FIXED_KEYS.has(key) else _keymap.get_all_bindings()[key]
	)
	var event := InputEventKey.new()
	event.keycode = int(binding.get("keycode", 0))
	event.ctrl_pressed = bool(binding.get("ctrl", false))
	event.shift_pressed = bool(binding.get("shift", false))
	event.alt_pressed = bool(binding.get("alt", false))
	event.meta_pressed = bool(binding.get("meta", false))
	event.pressed = true
	# A press of its own, not the second half of a double tap: the sweep presses
	# keys far faster than a hand does.
	plugin._last_tap_keycode = 0
	_surface.grab_focus()
	_viewport.push_input(event)
	var consumed := _viewport.is_input_handled()
	await get_tree().process_frame
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	_surface.grab_focus()
	_viewport.push_input(release)
	await get_tree().process_frame
	return consumed


## The plugin in a SubViewport with the stand-in viewport surface, so a pushed
## key goes through Godot's dispatch in that viewport alone.
func _bring_up_behind_a_surface() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "EditorWindow"
	_viewport.size = Vector2i(800, 600)
	add_child(_viewport)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_camera.look_at_from_position(Vector3(0, 12, 24), Vector3.ZERO)
	# Named as the editor's, which the shortcut stage checks focus against.
	var viewport_editor := Control.new()
	viewport_editor.name = "Node3DEditorViewport"
	viewport_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(viewport_editor)
	_surface = Control.new()
	_surface.name = "surface"
	_surface.focus_mode = Control.FOCUS_ALL
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_surface.gui_input.connect(_on_surface_input)
	viewport_editor.add_child(_surface)
	await _bring_up(true, _viewport)


func _on_surface_input(event: InputEvent) -> void:
	if plugin != null and is_instance_valid(plugin):
		plugin._forward_3d_gui_input(_camera, event)


func _take_down() -> void:
	await super()
	if _viewport != null and is_instance_valid(_viewport):
		remove_child(_viewport)
		_viewport.free()
	_viewport = null
	_surface = null
	_camera = null
