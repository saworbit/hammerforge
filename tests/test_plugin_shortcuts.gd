extends GutTest
## Boundary coverage for the extracted global shortcut routing and Escape ladder.

const HFPluginShortcuts = preload("res://addons/hammerforge/plugin_shortcuts.gd")

const APPLY := -3
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS


class FakeGesture:
	extends RefCounted

	var yield_to_native := false

	func should_yield_cancel_to_native() -> bool:
		return yield_to_native


class FakeRmbSession:
	extends RefCounted

	var active := false


class FakePopup:
	extends RefCounted

	var visible := false
	var active := false
	var hides := 0

	func is_active() -> bool:
		return active

	func hide_menu() -> void:
		hides += 1
		active = false

	func hide_popup() -> void:
		hides += 1
		active = false


class FakeDock:
	extends RefCounted

	var toasts: Array = []
	var selection_calls: Array = []

	func show_toast(text: String, level: int = 0) -> void:
		toasts.append({"text": text, "level": level})

	func set_selection_nodes(nodes: Array) -> void:
		selection_calls.append(nodes.duplicate())


class FakeKeymap:
	extends RefCounted

	var matching := ""

	func matches(action: String, _event) -> bool:
		return action == matching


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var _keymap := FakeKeymap.new()
	var _selection_gesture := FakeGesture.new()
	var _rmb_camera_navigation := FakeRmbSession.new()
	var _hotkey_palette = null
	var _radial_menu = null
	var _quick_property = null
	var _tool_registry = null
	var _texture_picker_active := false
	var _disp_paint_active := false
	var _disp_paint_brush_id := "b1"
	var _disp_paint_face_idx := 2
	var _disp_paint_pre_state: Dictionary = {}
	var _vertex_mode := false
	var hf_selection: Array = []
	var active_root: Node = null
	var numeric_buffer := ""

	var viewport: Viewport = null
	var gizmo_active := false
	var guard_result := PASS
	var guard_calls: Array = []
	var deletes := 0
	var duplicates := 0
	var nudges: Array = []
	var hud_updates := 0
	var vertex_toggles := 0
	var face_select_closes: Array = []
	var selection_cancel_result := false
	var selection_cancels := 0
	var runtime_state_repairs := 0
	var nudge_direction := Vector3.ZERO

	func get_viewport() -> Viewport:
		return viewport

	func _ensure_selection_runtime_state() -> void:
		runtime_state_repairs += 1

	func _brush_gizmo_action_active() -> bool:
		return gizmo_active

	func _get_level_root() -> Node:
		return active_root

	func _guard_hammerforge_shortcut(
		_root: Node, _brushes_only: bool, _minimum: int, action_label: String
	) -> int:
		guard_calls.append(action_label)
		return guard_result

	func _get_nudge_direction(_keycode: int) -> Vector3:
		return nudge_direction

	func _delete_selected(_root: Node) -> void:
		deletes += 1

	func _duplicate_selected(_root: Node) -> void:
		duplicates += 1

	func _nudge_selected(_root: Node, direction: Vector3) -> void:
		nudges.append(direction)

	func _cancel_selection_gesture() -> bool:
		selection_cancels += 1
		return selection_cancel_result

	func _toggle_vertex_mode(_root: Node) -> void:
		vertex_toggles += 1

	func _close_face_select_mode(message: String = "") -> bool:
		face_select_closes.append(message)
		return false

	func _update_hud_context() -> void:
		hud_updates += 1

	func get_editor_interface():
		return null


var plugin: FakePlugin
var viewport: SubViewport


func before_each():
	# handle() reads the focus owner and consumes through the viewport, so the
	# fake plugin needs a real one rather than a stub.
	viewport = SubViewport.new()
	add_child_autofree(viewport)
	plugin = FakePlugin.new()
	plugin.viewport = viewport


func after_each():
	plugin = null
	viewport = null


func _key(keycode: int, ctrl: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	return event


func _make_restorable_root() -> Node3D:
	var script := GDScript.new()
	script.source_code = """
extends Node3D

var restored: Array = []
var input_state = null
var face_selection: Dictionary = {}

func restore_state(state: Dictionary) -> void:
	restored.append(state)
"""
	script.reload()
	var node := Node3D.new()
	node.set_script(script)
	return node


# ---------------------------------------------------------------------------
# Escape ladder
# ---------------------------------------------------------------------------


func test_escape_dismisses_the_hotkey_palette_first():
	plugin._hotkey_palette = FakePopup.new()
	plugin._hotkey_palette.visible = true
	plugin._radial_menu = FakePopup.new()
	plugin._radial_menu.active = true

	assert_true(HFPluginShortcuts.cancel_escape_step(plugin, null))

	assert_false(plugin._hotkey_palette.visible, "The most local surface goes first")
	assert_eq(plugin._radial_menu.hides, 0, "Only one rung of the ladder runs per press")


func test_escape_dismisses_the_radial_menu_before_quick_property():
	plugin._radial_menu = FakePopup.new()
	plugin._radial_menu.active = true
	plugin._quick_property = FakePopup.new()
	plugin._quick_property.active = true

	assert_true(HFPluginShortcuts.cancel_escape_step(plugin, null))

	assert_eq(plugin._radial_menu.hides, 1)
	assert_eq(plugin._quick_property.hides, 0)


func test_escape_cancels_the_texture_picker_with_a_toast():
	plugin._texture_picker_active = true

	assert_true(HFPluginShortcuts.cancel_escape_step(plugin, null))

	assert_false(plugin._texture_picker_active)
	assert_eq(plugin.dock.toasts.size(), 1, "A cancelled picker has to say so")


func test_escape_restores_displacement_paint_state():
	var root := _make_restorable_root()
	add_child_autofree(root)
	plugin._disp_paint_active = true
	plugin._disp_paint_pre_state = {"marker": 7}

	assert_true(HFPluginShortcuts.cancel_escape_step(plugin, root))

	assert_eq(root.restored.size(), 1, "The pre-stroke state must come back")
	assert_eq(root.restored[0], {"marker": 7})
	assert_false(plugin._disp_paint_active)
	assert_eq(plugin._disp_paint_brush_id, "")
	assert_eq(plugin._disp_paint_face_idx, -1)
	assert_true(plugin._disp_paint_pre_state.is_empty())


func test_escape_yields_to_a_live_native_gizmo():
	plugin.gizmo_active = true

	assert_false(
		HFPluginShortcuts.cancel_escape_step(plugin, null),
		"Godot must see Escape so it can restore its own drag value"
	)
	assert_eq(plugin.selection_cancels, 0, "Nothing of ours is discarded either")


func test_escape_discards_our_bookkeeping_but_still_yields_to_native_selection():
	plugin._selection_gesture.yield_to_native = true

	assert_false(HFPluginShortcuts.cancel_escape_step(plugin, null))

	assert_eq(plugin.selection_cancels, 1, "Our parallel gesture state is dropped")


func test_escape_exits_vertex_mode_before_clearing_the_selection():
	var node := Node3D.new()
	add_child_autofree(node)
	plugin._vertex_mode = true
	plugin.hf_selection = [node]

	assert_true(HFPluginShortcuts.cancel_escape_step(plugin, null))

	assert_eq(plugin.vertex_toggles, 1)
	assert_eq(plugin.hf_selection.size(), 1, "The selection survives the mode exit")


func test_escape_reports_nothing_left_to_cancel():
	assert_false(
		HFPluginShortcuts.cancel_escape_step(plugin, null),
		"An idle Escape must pass through to Godot"
	)


# ---------------------------------------------------------------------------
# Global shortcut routing
# ---------------------------------------------------------------------------


func test_rmb_camera_flight_keeps_the_whole_keyboard_native():
	plugin._rmb_camera_navigation.active = true
	plugin._keymap.matching = "delete"
	plugin.active_root = Node3D.new()
	add_child_autofree(plugin.active_root)

	HFPluginShortcuts.handle(plugin, _key(KEY_DELETE))

	assert_eq(plugin.deletes, 0, "Delete must not fire while the camera is flying")
	assert_true(plugin.guard_calls.is_empty(), "The guard is not even consulted")


func test_a_live_native_gizmo_keeps_the_whole_keyboard_native():
	plugin.gizmo_active = true
	plugin._keymap.matching = "duplicate"
	plugin.active_root = Node3D.new()
	add_child_autofree(plugin.active_root)

	HFPluginShortcuts.handle(plugin, _key(KEY_D, true))

	assert_eq(plugin.duplicates, 0, "Ctrl+D belongs to the widget dragging the brush")


func test_owned_delete_runs_and_is_consumed():
	plugin._keymap.matching = "delete"
	plugin.guard_result = APPLY
	plugin.active_root = Node3D.new()
	add_child_autofree(plugin.active_root)

	HFPluginShortcuts.handle(plugin, _key(KEY_DELETE))

	assert_eq(plugin.guard_calls, ["Delete"], "Ownership is classified before the command")
	assert_eq(plugin.deletes, 1)
	assert_true(viewport.is_input_handled(), "Godot must not delete the same nodes again")


func test_claimed_but_rejected_delete_is_still_consumed():
	plugin._keymap.matching = "delete"
	plugin.guard_result = STOP
	plugin.active_root = Node3D.new()
	add_child_autofree(plugin.active_root)

	HFPluginShortcuts.handle(plugin, _key(KEY_DELETE))

	assert_eq(plugin.deletes, 0, "A refused command does not run")
	assert_true(
		viewport.is_input_handled(),
		"But Godot must not get a second go at a selection we already claimed"
	)


func test_unowned_delete_passes_through_to_godot():
	plugin._keymap.matching = "delete"
	plugin.guard_result = PASS
	plugin.active_root = Node3D.new()
	add_child_autofree(plugin.active_root)

	HFPluginShortcuts.handle(plugin, _key(KEY_DELETE))

	assert_eq(plugin.deletes, 0)
	assert_false(viewport.is_input_handled(), "A Godot selection stays Godot's to delete")


func test_nudge_needs_ctrl_and_a_direction():
	plugin.guard_result = APPLY
	plugin.active_root = Node3D.new()
	add_child_autofree(plugin.active_root)
	plugin.nudge_direction = Vector3.RIGHT

	HFPluginShortcuts.handle(plugin, _key(KEY_RIGHT, false))
	assert_true(plugin.nudges.is_empty(), "A bare arrow key is not a nudge")

	HFPluginShortcuts.handle(plugin, _key(KEY_RIGHT, true))
	assert_eq(plugin.nudges, [Vector3.RIGHT])
	assert_eq(plugin.guard_calls, ["Nudge"])


func test_shortcuts_need_a_root_except_escape():
	plugin._keymap.matching = "delete"
	plugin.guard_result = APPLY

	HFPluginShortcuts.handle(plugin, _key(KEY_DELETE))
	assert_eq(plugin.deletes, 0, "There is nothing to delete without a level")

	plugin._texture_picker_active = true
	HFPluginShortcuts.handle(plugin, _key(KEY_ESCAPE))
	assert_false(plugin._texture_picker_active, "Escape still cancels local UI with no level")


func test_key_releases_and_autorepeat_are_ignored():
	plugin._keymap.matching = "delete"
	plugin.guard_result = APPLY
	plugin.active_root = Node3D.new()
	add_child_autofree(plugin.active_root)

	var release := _key(KEY_DELETE)
	release.pressed = false
	HFPluginShortcuts.handle(plugin, release)

	var echo := _key(KEY_DELETE)
	echo.echo = true
	HFPluginShortcuts.handle(plugin, echo)

	assert_eq(plugin.deletes, 0, "Only a fresh press is a command")


func test_non_key_events_are_ignored():
	HFPluginShortcuts.handle(plugin, InputEventMouseButton.new())
	assert_eq(plugin.runtime_state_repairs, 0, "Mouse events never reach this hook")


# ---------------------------------------------------------------------------
# Focus ownership
# ---------------------------------------------------------------------------


func test_unknown_editor_panels_keep_their_own_shortcuts():
	var line_edit := LineEdit.new()
	add_child_autofree(line_edit)
	assert_true(HFPluginShortcuts.should_yield_to_focus(line_edit))


func test_marked_hammerforge_surfaces_keep_routing():
	var surface := Control.new()
	surface.set_meta("_hammerforge_managed_shortcut_surface", true)
	add_child_autofree(surface)
	assert_false(HFPluginShortcuts.should_yield_to_focus(surface))


func test_no_focus_owner_means_the_viewport():
	assert_false(HFPluginShortcuts.should_yield_to_focus(null))


func test_focus_ownership_walks_up_to_the_owning_panel():
	var tree := Control.new()
	tree.name = "SceneTreeDock"
	var child := LineEdit.new()
	tree.add_child(child)
	add_child_autofree(tree)
	assert_false(
		HFPluginShortcuts.should_yield_to_focus(child),
		"A field inside the Scene tree still belongs to a routing surface"
	)
