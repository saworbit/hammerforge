extends GutTest
## A key asks the selection guard for what the palette, the toolbar and the menus
## ask for the same command.
##
## The palette's guard reads `HFCommandRegistry` through
## `HFPluginSelectionState.managed_surface_action_requirement()`. The keyboard
## router used to write its own numbers and its own label into each guard call,
## a second copy that could drift: its toast said "Move to Floor" while the
## palette's said "Move To Floor" (#1298). Each key below is pressed through the
## real router against a plugin whose guard records what it was asked and
## refuses, so the command itself never runs.

const HFPluginInputRouter = preload("res://addons/hammerforge/plugin_input_router.gd")
const HFPluginSelectionState = preload("res://addons/hammerforge/plugin_selection_state.gd")
const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
# plugin.SelectionScope.HAMMERFORGE_ONLY: never handed back to Godot.
const SCOPE_HAMMERFORGE_ONLY := 2

## command id -> the one label a refusal of it carries, from a key and from the
## palette alike.
const KEYS := {
	"delete": "Delete",
	"duplicate": "Duplicate",
	"copy": "Copy",
	"paste": "Paste",
	"group": "Group",
	"ungroup": "Ungroup",
	"hollow": "Hollow",
	"move_to_floor": "Move to Floor",
	"move_to_ceiling": "Move to Ceiling",
	"snap_to_grid": "Snap to Grid",
	"clip": "Clip",
	"carve": "Carve",
	"merge": "Merge",
	"intersect": "Intersect",
	"apply_last_texture": "Apply Last Texture",
	"select_similar": "Select Similar",
	"quick_save_prefab": "Quick Save Prefab",
	"cycle_variant": "Cycle Variant",
	"vertex_edit": "Vertex Edit",
}


class IdleState:
	extends RefCounted

	func is_dragging() -> bool:
		return false

	func is_extruding() -> bool:
		return false

	func is_idle() -> bool:
		return true


class QuietRoot:
	extends Node

	var input_state := IdleState.new()
	var face_selection := {}


class GuardRecorder:
	extends RefCounted

	var dock = null
	var _keymap := HFKeymapType.load_or_default("")
	var _hotkey_palette = null
	var _radial_menu = null
	var _tool_registry = null
	var _operation_replay = null
	var _vertex_mode := false
	var _last_tap_keycode := 0
	var _last_tap_time := 0
	var _DOUBLE_TAP_MS := 300
	var asked: Array = []
	var ran: Array = []

	func _guard_hammerforge_shortcut(_root, brushes_only, minimum, label) -> int:
		asked.append([brushes_only, minimum, label])
		return STOP

	func classify_selection_scope(_nodes: Array, _root) -> int:
		return SCOPE_HAMMERFORGE_ONLY

	func _current_selection_nodes() -> Array:
		return []

	func _cancel_escape_step(_root) -> bool:
		return false

	func _handle_double_tap(_keycode, _root, _paint_mode) -> bool:
		return false

	func _get_nudge_direction(_keycode: int) -> Vector3:
		return Vector3.ZERO

	func axis_lock_shortcuts_available(_tool_id, _vertex_mode_on) -> bool:
		return false

	func _show_coach_mark_for_action(action: String) -> void:
		ran.append(action)


func _press(plugin: GuardRecorder, root: Node, action: String) -> int:
	var binding: Dictionary = plugin._keymap.get_all_bindings()[action]
	var event := InputEventKey.new()
	event.keycode = int(binding["keycode"])
	event.pressed = true
	event.ctrl_pressed = bool(binding.get("ctrl", false))
	event.shift_pressed = bool(binding.get("shift", false))
	event.alt_pressed = bool(binding.get("alt", false))
	return HFPluginInputRouter.handle_keyboard(plugin, event, root, 1, false)


func test_each_key_asks_the_guard_what_the_palette_asks():
	var root := QuietRoot.new()
	add_child_autofree(root)
	for action in KEYS:
		var plugin := GuardRecorder.new()
		var answer := _press(plugin, root, action)
		var palette: Dictionary = HFPluginSelectionState.managed_surface_action_requirement(action)
		assert_eq(answer, STOP, "%s: the refusal is the router's answer" % action)
		assert_eq(
			plugin.asked,
			[
				[
					bool(palette.get("brushes_only", false)),
					int(palette.get("minimum", 1)),
					KEYS[action],
				]
			],
			"%s asks the guard once, for what the palette asks" % action
		)
		assert_eq(
			str(palette.get("label", "")),
			KEYS[action],
			"%s: the palette's refusal carries the same label as the key's" % action
		)
		assert_eq(plugin.ran, [], "%s did not run past a refusal" % action)
