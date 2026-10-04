extends GutTest
## A key the viewport handles is consumed, so Godot and our own _shortcut_input
## never act on it a second time, and a key Godot's 3D editor also binds goes
## back to Godot while only Godot nodes are selected (#927).

const HFPluginViewportInput = preload("res://addons/hammerforge/plugin_viewport_input.gd")
const HFPluginShortcuts = preload("res://addons/hammerforge/plugin_shortcuts.gd")
const HFPluginInputRouter = preload("res://addons/hammerforge/plugin_input_router.gd")
const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
const APPLY := -3
# plugin.SelectionScope
const SCOPE_EMPTY := 0
const SCOPE_NATIVE_ONLY := 1
const SCOPE_HAMMERFORGE_ONLY := 2


class FakeInputState:
	extends RefCounted

	var idle := true

	func is_idle() -> bool:
		return idle

	func is_dragging() -> bool:
		return false

	func is_extruding() -> bool:
		return false


class FakeDock:
	extends RefCounted

	var toasts: Array = []
	var extrude_tools: Array = []
	var tool_draw = null
	var tool_select = null

	func is_face_select_mode_enabled() -> bool:
		return false

	func is_paint_mode_enabled() -> bool:
		return false

	func get_tool() -> int:
		return 1

	func get_grid_snap() -> float:
		return 1.0

	func show_toast(text: String, level: int = 0) -> void:
		toasts.append({"text": text, "level": level})

	func highlight_tab(_name: String) -> void:
		pass

	func set_extrude_tool(direction: int) -> void:
		extrude_tools.append(direction)


class FakeGesture:
	extends RefCounted

	func is_active() -> bool:
		return false

	func should_yield_cancel_to_native() -> bool:
		return false


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var _keymap := HFKeymapType.load_or_default("")
	var _rmb_camera_navigation := HFPluginViewportInput.RmbCameraNavigationSession.new()
	var _selection_gesture := FakeGesture.new()
	var _radial_menu = null
	var _quick_property = null
	var _hotkey_palette = null
	var _tool_registry = null
	var _texture_picker_active := false
	var _disp_paint_active := false
	var _vertex_mode := false
	var _last_tap_keycode := 0
	var _last_tap_time := 0
	var _DOUBLE_TAP_MS := 300
	var active_root: Node = null
	var last_3d_camera = null
	var last_3d_mouse_pos := Vector2.ZERO
	var hf_selection: Array = []

	var viewport: Viewport = null
	var scope := SCOPE_EMPTY
	var keyboard_result := PASS
	var keyboard_calls := 0
	var duplicates := 0
	var guard_result := APPLY

	func get_viewport() -> Viewport:
		return viewport

	func _ensure_selection_runtime_state() -> void:
		pass

	func _get_level_root() -> Node:
		return active_root

	func _brush_gizmo_action_active() -> bool:
		return false

	func _should_start_disp_paint(_event, _root) -> bool:
		return false

	func _update_hud_context() -> void:
		pass

	## Stands in for the router: Ctrl+D duplicates and is handled, as the real
	## router does with a HammerForge selection.
	func _handle_keyboard_input(event: InputEventKey, _root, _tool_id, _paint_mode) -> int:
		keyboard_calls += 1
		if _keymap.matches("duplicate", event):
			_duplicate_selected(_root)
			return STOP
		return keyboard_result

	func _guard_hammerforge_shortcut(_root, _brushes_only, _minimum, _label) -> int:
		return guard_result

	func _duplicate_selected(_root) -> void:
		duplicates += 1

	func _get_nudge_direction(_keycode: int) -> Vector3:
		return Vector3.ZERO

	func classify_selection_scope(_nodes: Array, _root) -> int:
		return scope

	func _current_selection_nodes() -> Array:
		return []

	func _cancel_escape_step(_root) -> bool:
		return false

	func _handle_double_tap(_keycode, _root, _paint_mode) -> bool:
		return false

	func _prepare_tool_transition(_root) -> void:
		pass

	func _deactivate_external_tool() -> void:
		pass


## The 3D viewport's surface: a focused control that hands its keys to the
## forwarding hook, the way Node3DEditorViewport does. Named for the real panel
## so the shortcut hook treats focus here as the viewport's.
class ForwardingSurface:
	extends Control

	var plugin: FakePlugin

	func _gui_input(event: InputEvent) -> void:
		HFPluginViewportInput.handle(plugin, null, event)


## The shortcut stage: our own _shortcut_input, which runs after the GUI stage
## unless the event was consumed there.
class ShortcutStage:
	extends Node

	var plugin: FakePlugin
	var calls := 0

	func _shortcut_input(event: InputEvent) -> void:
		calls += 1
		HFPluginShortcuts.handle(plugin, event)


var plugin: FakePlugin
var viewport: SubViewport


func before_each():
	viewport = SubViewport.new()
	add_child_autofree(viewport)
	plugin = FakePlugin.new()
	plugin.viewport = viewport
	plugin.active_root = _make_root()
	add_child_autofree(plugin.active_root)


func after_each():
	plugin = null
	viewport = null


func _make_root() -> Node3D:
	var script := GDScript.new()
	script.source_code = """
extends Node3D

var grid_snap := 0.5
var input_state = null
var face_selection: Dictionary = {}

func update_editor_grid(_camera, _pos) -> void:
	pass

func clear_hover() -> void:
	pass
"""
	script.reload()
	var node := Node3D.new()
	node.set_script(script)
	node.input_state = FakeInputState.new()
	return node


func _key(keycode: int, ctrl := false, shift := false, alt := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.alt_pressed = alt
	return event


func _key_for(binding: Dictionary) -> InputEventKey:
	return _key(
		int(binding["keycode"]),
		bool(binding.get("ctrl", false)),
		bool(binding.get("shift", false)),
		bool(binding.get("alt", false))
	)


# ---------------------------------------------------------------------------
# Consuming what the viewport handles
# ---------------------------------------------------------------------------


func test_a_key_the_viewport_stops_is_consumed():
	plugin.keyboard_result = STOP
	assert_eq(HFPluginViewportInput.handle(plugin, null, _key(KEY_E)), STOP)
	assert_true(viewport.is_input_handled(), "Godot must not act on a key we handled")


func test_a_key_the_viewport_passes_is_left_for_godot():
	plugin.keyboard_result = PASS
	assert_eq(HFPluginViewportInput.handle(plugin, null, _key(KEY_J)), PASS)
	assert_eq(plugin.keyboard_calls, 1)
	assert_false(viewport.is_input_handled())


func test_one_ctrl_d_in_the_viewport_duplicates_once():
	var surface := ForwardingSurface.new()
	surface.name = "Node3DEditorViewport"
	surface.plugin = plugin
	surface.focus_mode = Control.FOCUS_ALL
	surface.size = Vector2(64, 64)
	viewport.add_child(surface)
	var stage := ShortcutStage.new()
	stage.plugin = plugin
	viewport.add_child(stage)
	surface.grab_focus()
	assert_true(surface.has_focus(), "The surface must own the keyboard for this to mean anything")

	viewport.push_input(_key(KEY_D, true))

	assert_eq(plugin.keyboard_calls, 1, "The forwarded key reached the router")
	assert_eq(plugin.duplicates, 1, "One press is one duplicate")
	assert_eq(stage.calls, 0, "The shortcut stage never saw a key the viewport consumed")


# ---------------------------------------------------------------------------
# Keys Godot's 3D editor also binds
# ---------------------------------------------------------------------------


func test_every_general_key_godot_also_binds_goes_back_to_godot_for_its_selection():
	plugin.scope = SCOPE_NATIVE_ONLY
	var root: Node = plugin.active_root
	var defaults := HFKeymapType._default_bindings()
	var checked := 0
	for action in defaults:
		if HFKeymapType.action_mode(action) != "general":
			continue
		var event := _key_for(defaults[action])
		if not HFKeymapType.godot_3d_uses(event):
			continue
		checked += 1
		assert_eq(
			HFPluginInputRouter.handle_keyboard(plugin, event, root, 0, false),
			PASS,
			(
				"%s (%s) must go to Godot when only Godot nodes are selected"
				% [action, plugin._keymap.get_display_string(action)]
			)
		)
	assert_gt(checked, 5, "E, Q, T, U, R, V and the axis locks all collide today")


func test_a_colliding_key_stays_ours_with_nothing_selected():
	plugin.scope = SCOPE_EMPTY
	var result := HFPluginInputRouter.handle_keyboard(
		plugin, _key(KEY_E), plugin.active_root, 0, false
	)
	assert_eq(result, STOP)
	assert_eq(plugin.dock.extrude_tools, [1], "E is Extrude in a level with nothing selected")


func test_a_colliding_key_stays_ours_mid_gesture():
	plugin.scope = SCOPE_NATIVE_ONLY
	plugin.active_root.input_state.idle = false
	assert_false(
		HFPluginInputRouter.yields_to_godot(plugin, _key(KEY_X), plugin.active_root, false),
		"An axis lock mid-draw is ours whatever is selected"
	)


func test_paint_mode_keeps_its_keys():
	plugin.scope = SCOPE_NATIVE_ONLY
	assert_false(HFPluginInputRouter.yields_to_godot(plugin, _key(KEY_B), plugin.active_root, true))


func test_a_key_godot_does_not_bind_never_yields():
	plugin.scope = SCOPE_NATIVE_ONLY
	assert_false(
		HFPluginInputRouter.yields_to_godot(plugin, _key(KEY_J), plugin.active_root, false)
	)


func test_selection_filter_is_off_godots_freelook():
	var keymap := HFKeymapType.load_or_default("")
	assert_false(keymap.matches("selection_filter", _key(KEY_F, false, true)))
	assert_true(HFKeymapType.godot_3d_uses(_key(KEY_F, false, true)), "Shift+F is Toggle Freelook")
	assert_false(
		HFKeymapType.godot_3d_uses(_key_for(HFKeymapType._default_bindings()["selection_filter"])),
		"Its new chord is one Godot's 3D editor leaves free"
	)


# ---------------------------------------------------------------------------
# The keymap file
# ---------------------------------------------------------------------------


func test_a_keymap_file_can_name_its_keys():
	var path := "user://test_keymap_names_927.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	(
		file
		. store_string(
			(
				JSON
				. stringify(
					{
						"selection_filter": {"keycode": "G", "alt": true},
						"duplicate": {"keycode": "NoSuchKey", "ctrl": true},
						"grid_increase": {"keycode": "Shift+F"},
					}
				)
			)
		)
	)
	file.close()
	var keymap := HFKeymapType.load_or_default(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	assert_true(keymap.matches("selection_filter", _key(KEY_G, false, false, true)))
	assert_true(keymap.matches("duplicate", _key(KEY_D, true)), "An unknown name keeps the default")
	assert_true(
		keymap.matches("grid_increase", _key(KEY_BRACKETRIGHT)),
		"A modifier belongs in its own field, so a name carrying one keeps the default"
	)
