extends GutTest
## Boundary coverage for settling gestures that lost the release meant to close them.

const HFPluginGestureRecovery = preload("res://addons/hammerforge/plugin_gesture_recovery.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS


class FakeInputState:
	extends RefCounted

	var extruding := false
	var dragging := false
	var drag_base := false
	var surface_painting := false
	var surface_paint_ends := 0

	func is_extruding() -> bool:
		return extruding

	func is_dragging() -> bool:
		return dragging

	func is_drag_base() -> bool:
		return drag_base

	func is_surface_painting() -> bool:
		return surface_painting

	func end_surface_paint() -> void:
		surface_paint_ends += 1
		surface_painting = false


class FakePaintTool:
	extends RefCounted

	var stroke_active := false
	var finishes := 0

	func is_stroke_active() -> bool:
		return stroke_active

	func finish_stroke_if_active() -> void:
		finishes += 1
		stroke_active = false


class FakeVertexSystem:
	extends RefCounted

	var cancels := 0

	func cancel_drag() -> void:
		cancels += 1


class FakeToolRegistry:
	extends RefCounted

	var recovers := false
	var recover_calls := 0
	var capture_cancels := 0

	func recover_active_pointer_capture() -> bool:
		recover_calls += 1
		return recovers

	func cancel_active_pointer_capture() -> void:
		capture_cancels += 1


class FakeSelectionGesture:
	extends RefCounted

	var active := false

	func is_active() -> bool:
		return active


class FakeRmbSession:
	extends RefCounted

	var active := false
	var begins := 0

	func begin() -> void:
		begins += 1
		active = true


class FakePlugin:
	extends RefCounted

	var _tool_registry := FakeToolRegistry.new()
	var _selection_gesture := FakeSelectionGesture.new()
	var _rmb_camera_navigation := FakeRmbSession.new()
	var active_root: Node = null
	var numeric_buffer := "128"
	var _vertex_drag_active := false
	var _disp_paint_active := false
	var _disp_paint_brush_id := "b1"
	var _disp_paint_face_idx := 3
	var _disp_paint_pre_state: Dictionary = {}
	var _focus_recovery_queued := true

	var disp_undo_commits := 0
	var selection_cancels := 0
	var reconcile_queues := 0
	var hud_updates := 0
	var transitions: Array = []
	var block_rmb := false
	var cancelable_rmb := false

	func _get_level_root() -> Node:
		return active_root

	func _commit_disp_paint_undo(_root: Node) -> void:
		disp_undo_commits += 1

	func _cancel_selection_gesture() -> bool:
		selection_cancels += 1
		return false

	func _queue_managed_brush_reconcile() -> void:
		reconcile_queues += 1

	func _update_hud_context() -> void:
		hud_updates += 1

	func _prepare_tool_transition(
		_root: Node, notify_user: bool = true, settle_custom_gizmo: bool = true
	) -> void:
		transitions.append({"notify": notify_user, "settle_gizmo": settle_custom_gizmo})

	func should_block_rmb_during_paint_stroke(
		_surface: bool, _floor: bool, _disp: bool, _lmb_held: bool
	) -> bool:
		return block_rmb

	func has_cancelable_rmb_gesture(_input_state, _has_marquee: bool) -> bool:
		return cancelable_rmb


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
var hover_clears := 0
var face_hover_clears := 0

func cancel_extrude() -> void:
	input_state.extruding = false

func cancel_drag() -> void:
	input_state.dragging = false
	input_state.drag_base = false

func clear_hover() -> void:
	hover_clears += 1

func clear_face_hover_highlight() -> void:
	face_hover_clears += 1
"""
	script.reload()
	var node := Node3D.new()
	node.set_script(script)
	node.input_state = FakeInputState.new()
	node.vertex_system = FakeVertexSystem.new()
	node.paint_tool = FakePaintTool.new()
	add_child_autofree(node)
	return node


func _rmb(lmb_held: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	if lmb_held:
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event


# ---------------------------------------------------------------------------
# Focus loss
# ---------------------------------------------------------------------------


func test_focus_loss_drops_the_camera_session_and_pointer_capture():
	HFPluginGestureRecovery.after_application_focus_loss(plugin)

	assert_false(plugin._focus_recovery_queued, "The deferred call has run")
	assert_false(plugin._rmb_camera_navigation.active)
	assert_eq(plugin._tool_registry.capture_cancels, 1)
	assert_eq(plugin.selection_cancels, 1)
	assert_eq(plugin.reconcile_queues, 1)


func test_focus_loss_settles_quietly_and_leaves_the_native_gizmo_alone():
	var root := _make_root()
	plugin.active_root = root

	HFPluginGestureRecovery.after_application_focus_loss(plugin)

	assert_eq(plugin.transitions.size(), 1)
	assert_false(plugin.transitions[0]["notify"], "The user did not ask for this switch")
	assert_false(
		plugin.transitions[0]["settle_gizmo"],
		"Godot is committing its own handle drag, a second cancel would race it"
	)
	assert_eq(root.hover_clears, 1, "The pointer is no longer where the highlight says")
	assert_eq(root.face_hover_clears, 1)


func test_focus_loss_without_a_level_still_releases_ownership():
	HFPluginGestureRecovery.after_application_focus_loss(plugin)

	assert_true(plugin.transitions.is_empty(), "There is no level to settle")
	assert_eq(plugin._tool_registry.capture_cancels, 1, "But capture is still released")


# ---------------------------------------------------------------------------
# Stale paint strokes
# ---------------------------------------------------------------------------


func test_stale_floor_and_surface_strokes_are_both_finished():
	var root := _make_root()
	root.paint_tool.stroke_active = true
	root.input_state.surface_painting = true

	assert_true(
		HFPluginGestureRecovery.finish_stale_paint_strokes(
			plugin, root, root.input_state, root.paint_tool
		)
	)

	assert_eq(root.paint_tool.finishes, 1)
	assert_eq(root.input_state.surface_paint_ends, 1)


func test_stale_displacement_stroke_is_committed_not_discarded():
	var root := _make_root()
	plugin._disp_paint_active = true
	plugin._disp_paint_pre_state = {"marker": 1}

	assert_true(
		HFPluginGestureRecovery.finish_stale_paint_strokes(
			plugin, root, root.input_state, root.paint_tool
		)
	)

	assert_eq(plugin.disp_undo_commits, 1, "The sculpting the user did is theirs to undo")
	assert_false(plugin._disp_paint_active)
	assert_eq(plugin._disp_paint_brush_id, "")
	assert_eq(plugin._disp_paint_face_idx, -1)


func test_displacement_stroke_with_no_recorded_state_commits_nothing():
	var root := _make_root()
	plugin._disp_paint_active = true

	assert_true(
		HFPluginGestureRecovery.finish_stale_paint_strokes(
			plugin, root, root.input_state, root.paint_tool
		)
	)

	assert_eq(plugin.disp_undo_commits, 0, "An empty undo entry is worse than none")


func test_nothing_stale_reports_nothing_finished():
	var root := _make_root()

	assert_false(
		HFPluginGestureRecovery.finish_stale_paint_strokes(
			plugin, root, root.input_state, root.paint_tool
		)
	)


# ---------------------------------------------------------------------------
# Stale LMB gestures
# ---------------------------------------------------------------------------


func test_lost_release_during_the_base_drag_is_recovered():
	var root := _make_root()
	root.input_state.drag_base = true

	HFPluginGestureRecovery.recover_stale_lmb_gestures(plugin, root)

	assert_false(root.input_state.drag_base)
	assert_eq(plugin.numeric_buffer, "")
	assert_eq(plugin.hud_updates, 1)


func test_height_drag_is_left_alone():
	var root := _make_root()
	root.input_state.dragging = true

	HFPluginGestureRecovery.recover_stale_lmb_gestures(plugin, root)

	assert_true(
		root.input_state.dragging,
		"Height is driven by motion after the base commits, so no button is missing"
	)
	assert_eq(plugin.numeric_buffer, "128", "Nothing was recovered, so nothing is reset")


func test_stale_vertex_drag_is_cancelled():
	var root := _make_root()
	plugin._vertex_drag_active = true

	HFPluginGestureRecovery.recover_stale_lmb_gestures(plugin, root)

	assert_eq(root.vertex_system.cancels, 1)
	assert_false(plugin._vertex_drag_active)


func test_recovery_is_silent_when_there_was_nothing_to_recover():
	var root := _make_root()

	HFPluginGestureRecovery.recover_stale_lmb_gestures(plugin, root)

	assert_eq(root.hover_clears, 0)
	assert_eq(plugin.hud_updates, 0, "An idle viewport does not need a HUD refresh every motion")


func test_recovery_without_a_level_does_nothing():
	HFPluginGestureRecovery.recover_stale_lmb_gestures(plugin, null)
	assert_eq(plugin._tool_registry.recover_calls, 0)


# ---------------------------------------------------------------------------
# RMB
# ---------------------------------------------------------------------------


func test_rmb_is_swallowed_while_a_paint_stroke_holds_the_pointer():
	var root := _make_root()
	plugin.block_rmb = true

	assert_eq(
		HFPluginGestureRecovery.handle_rmb_cancel(plugin, root, _rmb(true)),
		STOP,
		"Starting camera look mid stroke would paint while the view moves"
	)
	assert_eq(plugin._rmb_camera_navigation.begins, 0)


func test_idle_rmb_belongs_to_the_native_camera():
	var root := _make_root()
	plugin.cancelable_rmb = false

	assert_eq(HFPluginGestureRecovery.handle_rmb_cancel(plugin, root, _rmb()), PASS)

	assert_eq(plugin._rmb_camera_navigation.begins, 1)
	assert_eq(root.hover_clears, 1, "Hover from the idle pointer goes before the camera flies")


func test_rmb_cancels_an_extrude_in_progress():
	var root := _make_root()
	root.input_state.extruding = true
	plugin.cancelable_rmb = true

	assert_eq(HFPluginGestureRecovery.handle_rmb_cancel(plugin, root, _rmb()), STOP)

	assert_false(root.input_state.extruding)
	assert_eq(plugin.numeric_buffer, "")
	assert_eq(plugin._rmb_camera_navigation.begins, 0, "The press was ours, not the camera's")


func test_rmb_finishes_a_stroke_whose_release_never_arrived():
	var root := _make_root()
	root.paint_tool.stroke_active = true
	plugin.cancelable_rmb = false

	assert_eq(HFPluginGestureRecovery.handle_rmb_cancel(plugin, root, _rmb()), PASS)

	assert_eq(
		root.paint_tool.finishes,
		1,
		"A stale stroke is closed rather than left to block every future RMB"
	)
	assert_eq(plugin._rmb_camera_navigation.begins, 1)
