extends GutTest
## Boundary coverage for extracted tool and mode transitions.

const HFPluginToolModes = preload("res://addons/hammerforge/plugin_tool_modes.gd")


class FakeInputState:
	extends RefCounted

	var extruding := false
	var dragging := false

	func is_extruding() -> bool:
		return extruding

	func is_dragging() -> bool:
		return dragging


class FakeVertexSystem:
	extends RefCounted

	var cancels := 0

	func cancel_drag() -> void:
		cancels += 1


class FakeGizmoPlugin:
	extends RefCounted

	var cancels := 0

	func cancel_active_handle_action() -> void:
		cancels += 1


class FakeButton:
	extends RefCounted

	var button_pressed := false
	var silent_states: Array = []

	func set_pressed_no_signal(value: bool) -> void:
		silent_states.append(value)
		button_pressed = value


class FakeRadial:
	extends RefCounted

	var active := false
	var hides := 0

	func is_active() -> bool:
		return active

	func hide_menu() -> void:
		hides += 1
		active = false


class FakeToolRegistry:
	extends RefCounted

	var has_external := false
	var deactivations := 0
	var activations: Array = []

	func has_active_external_tool() -> bool:
		return has_external

	func deactivate_current() -> void:
		deactivations += 1
		has_external = false

	func activate_tool(tool_id: int, _root, _cam, _undo, _record) -> void:
		activations.append(tool_id)


class FakeDock:
	extends RefCounted

	var paint_mode := FakeButton.new()
	var tool_select := FakeButton.new()
	var tool_draw := FakeButton.new()
	var face_select_mode := FakeButton.new()
	var toasts: Array = []
	var highlighted: Array = []
	var extrude_calls: Array = []
	var tool_id := 1
	var face_select_enabled := false

	func show_toast(text: String, level: int = 0) -> void:
		toasts.append({"text": text, "level": level})

	func highlight_tab(tab_name: String) -> void:
		highlighted.append(tab_name)

	func get_tool() -> int:
		return tool_id

	func set_extrude_tool(direction: int) -> void:
		extrude_calls.append(direction)

	func is_face_select_mode_enabled() -> bool:
		return face_select_enabled

	func toast_texts() -> Array:
		var out: Array = []
		for toast in toasts:
			out.append(toast["text"])
		return out


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var brush_gizmo_plugin := FakeGizmoPlugin.new()
	var _tool_registry := FakeToolRegistry.new()
	var _radial_menu := FakeRadial.new()
	var active_root: Node = null
	var last_3d_camera = null
	var undo_redo_manager = null
	var numeric_buffer := "42"
	var hf_selection: Array = []
	var _face_mode_saved_object_selection: Array = []
	var _vertex_mode := false
	var _vertex_drag_active := false
	var _texture_picker_active := false

	var gizmo_active := false
	var stale_paint_result := false
	var stale_paint_calls := 0
	var vertex_toggles := 0
	var selection_cancel_result := false
	var selection_cancels := 0
	var hud_updates := 0
	var coach_marks: Array = []
	var runtime_state_repairs := 0
	var applied_selections := 0
	var current_nodes: Array = []
	var editor_selection = null

	func _get_level_root() -> Node:
		return active_root

	func _brush_gizmo_action_active() -> bool:
		return gizmo_active

	func _finish_stale_paint_strokes(_root: Node, _input_state, _paint_tool) -> bool:
		stale_paint_calls += 1
		return stale_paint_result

	func _cancel_selection_gesture() -> bool:
		selection_cancels += 1
		return selection_cancel_result

	func _toggle_vertex_mode(_root: Node) -> void:
		vertex_toggles += 1
		_vertex_mode = not _vertex_mode

	func _update_hud_context() -> void:
		hud_updates += 1

	func _show_coach_mark_for_action(action: String) -> void:
		coach_marks.append(action)

	func _ensure_selection_runtime_state() -> void:
		runtime_state_repairs += 1

	func _current_selection_nodes() -> Array:
		return current_nodes

	func _apply_hf_selection(_selection) -> void:
		applied_selections += 1

	func _record_history(_action: String) -> void:
		pass

	func get_editor_interface():
		return self

	func get_selection():
		return editor_selection


var plugin: FakePlugin


func before_each():
	plugin = FakePlugin.new()


func after_each():
	plugin = null


func _make_root() -> Node3D:
	var script := GDScript.new()
	script.source_code = """
extends Node3D

var input_state = null
var vertex_system = null
var paint_tool = null
var face_cleared := 0

func cancel_extrude() -> void:
	input_state.extruding = false

func cancel_drag() -> void:
	input_state.dragging = false

func clear_face_selection() -> void:
	face_cleared += 1
"""
	script.reload()
	var node := Node3D.new()
	node.set_script(script)
	node.input_state = FakeInputState.new()
	node.vertex_system = FakeVertexSystem.new()
	add_child_autofree(node)
	return node


# ---------------------------------------------------------------------------
# prepare_transition
# ---------------------------------------------------------------------------


func test_transition_settles_a_live_handle_drag_even_without_a_level():
	plugin.gizmo_active = true

	HFPluginToolModes.prepare_transition(plugin, null)

	assert_eq(plugin.brush_gizmo_plugin.cancels, 1)
	assert_eq(
		plugin.dock.toast_texts(),
		["In-progress brush resize closed for tool switch"],
		"A cancelled resize has to be reported even when there is no level yet"
	)


func test_transition_can_leave_the_native_gizmo_alone():
	plugin.gizmo_active = true

	HFPluginToolModes.prepare_transition(plugin, null, true, false)

	assert_eq(
		plugin.brush_gizmo_plugin.cancels,
		0,
		"Godot is already unwinding its own drag, a second cancel would fight it"
	)


func test_transition_cancels_an_extrude_and_clears_the_numeric_buffer():
	var root := _make_root()
	root.input_state.extruding = true

	HFPluginToolModes.prepare_transition(plugin, root)

	assert_false(root.input_state.extruding)
	assert_eq(plugin.numeric_buffer, "", "A half typed dimension does not survive the switch")
	assert_eq(plugin.dock.toast_texts(), ["In-progress gesture closed for tool switch"])


func test_transition_cancels_a_vertex_drag():
	var root := _make_root()
	plugin._vertex_drag_active = true

	HFPluginToolModes.prepare_transition(plugin, root)

	assert_eq(root.vertex_system.cancels, 1)
	assert_false(plugin._vertex_drag_active)


func test_transition_is_quiet_when_nothing_was_in_progress():
	HFPluginToolModes.prepare_transition(plugin, _make_root())

	assert_true(plugin.dock.toasts.is_empty(), "Nothing was interrupted, so say nothing")
	assert_eq(plugin.numeric_buffer, "42", "An untouched numeric entry is left alone")


func test_transition_can_be_silent_for_switches_the_user_did_not_ask_for():
	var root := _make_root()
	root.input_state.dragging = true

	HFPluginToolModes.prepare_transition(plugin, root, false)

	assert_false(root.input_state.dragging, "The gesture is still settled")
	assert_true(plugin.dock.toasts.is_empty(), "But an implicit switch does not narrate itself")


# ---------------------------------------------------------------------------
# Tool ownership
# ---------------------------------------------------------------------------


func test_activating_an_external_tool_closes_every_other_owner():
	var root := _make_root()
	plugin._vertex_mode = true
	plugin.dock.paint_mode.button_pressed = true
	plugin.dock.face_select_enabled = true

	HFPluginToolModes.activate_external(plugin, 100, root)

	assert_false(plugin.dock.face_select_mode.button_pressed, "Face Select is closed")
	assert_eq(plugin.vertex_toggles, 1, "Vertex edit is left")
	assert_false(plugin.dock.paint_mode.button_pressed, "Painting is turned off")
	assert_eq(plugin._tool_registry.activations, [100])


func test_external_tool_activation_needs_a_level():
	HFPluginToolModes.activate_external(plugin, 100, null)
	assert_true(plugin._tool_registry.activations.is_empty())


func test_builtin_tool_change_drops_the_active_external_tool():
	plugin.active_root = _make_root()
	plugin._tool_registry.has_external = true

	HFPluginToolModes.on_builtin_tool_changed(plugin)

	assert_eq(plugin._tool_registry.deactivations, 1)
	assert_eq(plugin.hud_updates, 1)


func test_builtin_tool_change_coaches_the_extrude_tools_only():
	plugin.active_root = _make_root()
	plugin.dock.tool_id = 1
	HFPluginToolModes.on_builtin_tool_changed(plugin)
	assert_true(plugin.coach_marks.is_empty(), "Select is not a tool anyone needs a guide for")

	plugin.dock.tool_id = 2
	HFPluginToolModes.on_builtin_tool_changed(plugin)
	assert_eq(plugin.coach_marks, ["tool_extrude_up"])


func test_context_toolbar_drives_the_dock_buttons():
	plugin.active_root = _make_root()

	HFPluginToolModes.switch_to_tool(plugin, 1)
	assert_true(plugin.dock.tool_select.button_pressed)
	assert_eq(plugin.dock.highlighted, ["Brush"])

	HFPluginToolModes.switch_to_tool(plugin, 3)
	assert_eq(plugin.dock.extrude_calls, [-1], "Extrude down is a direction, not a button")


# ---------------------------------------------------------------------------
# Vertex edit and paint mode
# ---------------------------------------------------------------------------


func test_vertex_mode_toggle_ignores_a_repeat_of_the_state_it_is_in():
	plugin._vertex_mode = true

	HFPluginToolModes.on_vertex_mode_toggled(plugin, true)

	assert_eq(plugin.vertex_toggles, 0, "_toggle_vertex_mode flips, so a repeat would leave it")


func test_vertex_mode_toggle_acts_on_a_real_change():
	HFPluginToolModes.on_vertex_mode_toggled(plugin, true)
	assert_eq(plugin.vertex_toggles, 1)

	HFPluginToolModes.on_vertex_mode_toggled(plugin, false)
	assert_eq(plugin.vertex_toggles, 2)


func test_paint_mode_toggle_reports_which_mode_it_landed_in():
	plugin.active_root = _make_root()

	HFPluginToolModes.toggle_paint_mode(plugin)
	assert_true(plugin.dock.paint_mode.button_pressed)
	assert_eq(plugin.dock.toast_texts(), ["Paint mode enabled"])

	HFPluginToolModes.toggle_paint_mode(plugin)
	assert_false(plugin.dock.paint_mode.button_pressed)
	assert_eq(plugin.dock.toast_texts()[1], "Build mode enabled")


# ---------------------------------------------------------------------------
# Face Select
# ---------------------------------------------------------------------------


func test_entering_face_select_saves_the_object_selection_it_hides():
	var kept := Node3D.new()
	add_child_autofree(kept)
	plugin.current_nodes = [kept]
	plugin.hf_selection = [kept]
	plugin.editor_selection = RefCounted.new()

	HFPluginToolModes.on_face_select_mode_toggled(plugin, true)

	assert_eq(plugin._face_mode_saved_object_selection, [kept], "It has to come back on exit")
	assert_true(plugin.hf_selection.is_empty(), "Object gizmos are hidden while the mode is on")
	assert_true(plugin.dock.tool_select.button_pressed, "Face Select runs on top of Select")
	assert_false(plugin.dock.paint_mode.button_pressed, "It is an edit mode, not a paint stroke")


func test_entering_face_select_closes_the_pointer_owners_it_conflicts_with():
	plugin._vertex_mode = true
	plugin._texture_picker_active = true
	plugin._tool_registry.has_external = true
	plugin._radial_menu.active = true
	plugin.editor_selection = RefCounted.new()

	HFPluginToolModes.on_face_select_mode_toggled(plugin, true)

	assert_eq(plugin._tool_registry.deactivations, 1)
	assert_eq(plugin.vertex_toggles, 1)
	assert_false(plugin._texture_picker_active)
	assert_eq(plugin._radial_menu.hides, 1)


func test_leaving_face_select_restores_the_saved_object_selection():
	var kept := Node3D.new()
	add_child_autofree(kept)
	plugin.active_root = _make_root()
	plugin._face_mode_saved_object_selection = [kept]
	plugin.editor_selection = RefCounted.new()

	HFPluginToolModes.on_face_select_mode_toggled(plugin, false)

	assert_eq(plugin.hf_selection, [kept])
	assert_eq(plugin.active_root.face_cleared, 1, "The face selection goes with the mode")
	assert_true(
		plugin._face_mode_saved_object_selection.is_empty(),
		"The saved copy is spent, holding it would leak freed nodes"
	)


func test_leaving_face_select_drops_freed_nodes_from_the_saved_selection():
	var gone := Node3D.new()
	gone.free()
	plugin.active_root = _make_root()
	plugin._face_mode_saved_object_selection = [gone]
	plugin.editor_selection = RefCounted.new()

	HFPluginToolModes.on_face_select_mode_toggled(plugin, false)

	assert_true(plugin.hf_selection.is_empty(), "A node deleted during the mode cannot come back")


func test_close_face_select_reports_whether_the_mode_was_open():
	assert_false(
		HFPluginToolModes.close_face_select(plugin, "closed"),
		"Nothing was open, so the caller has not consumed the user's key"
	)
	assert_true(plugin.dock.toasts.is_empty())

	plugin.dock.face_select_enabled = true
	plugin.dock.face_select_mode.button_pressed = true

	assert_true(HFPluginToolModes.close_face_select(plugin, "closed"))
	assert_false(plugin.dock.face_select_mode.button_pressed)
	assert_eq(plugin.dock.toast_texts(), ["closed"])


func test_close_face_select_can_stay_quiet():
	plugin.dock.face_select_enabled = true

	assert_true(HFPluginToolModes.close_face_select(plugin))

	assert_true(plugin.dock.toasts.is_empty(), "An empty message means no toast")
