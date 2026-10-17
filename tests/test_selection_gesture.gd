extends GutTest
## Focused ownership tests for Select-tool click, marquee, and native gizmo gestures.

const SelectionGesture = preload("res://addons/hammerforge/hf_selection_gesture.gd")
const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const BrushChangeTracker = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")
const DraftBrushScript = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const DisplacementData = preload("res://addons/hammerforge/displacement_data.gd")
const THRESHOLD := 6.0
const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPrefabSystemScript = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
const CUSTOM := EditorPlugin.AFTER_GUI_INPUT_CUSTOM
## The middle of the rig's viewport, where the camera looks at the origin.
const AIM := Vector2(400, 300)

## The real plugin, for the tests below that check what it does with input.
var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self)


func after_all() -> void:
	await rig.take_down()


## An external tool that writes down what it is handed and asked.
class RecordingTool:
	extends HFEditorTool
	const ID := 191
	var events: Array = []
	var calls: Array = []
	var cancelled := 0

	func tool_id() -> int:
		return ID

	func tool_name() -> String:
		return "Recording Tool"

	func handle_input(event: InputEvent, _camera: Camera3D, _mouse_pos: Vector2) -> int:
		events.append(event)
		calls.append("input")
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	func recover_lost_pointer_capture() -> bool:
		calls.append("recover")
		return false

	func cancel_pointer_capture() -> bool:
		cancelled += 1
		return false


func _left(pressed: bool, at: Vector2, shift := false, ctrl := false) -> int:
	var event := PluginRig.click(MOUSE_BUTTON_LEFT, pressed, at)
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	return rig.forward(event)


func _drag(to: Vector2) -> int:
	return rig.forward(PluginRig.motion(to, MOUSE_BUTTON_MASK_LEFT))


func _pick_tool(action: String) -> void:
	rig.plugin._hotkey_palette.action_invoked.emit(action)


## Turn Face Select on or off with the dock's own button.
func _face_select(on: bool) -> void:
	rig.plugin.dock.face_select_mode.button_pressed = on


func _start_tool(level: Node) -> RecordingTool:
	var tool := RecordingTool.new()
	rig.plugin._tool_registry.register_tool(tool)
	rig.plugin._activate_external_tool(RecordingTool.ID, level)
	return tool


func _stop_tool() -> void:
	rig.plugin._tool_registry.unregister_tool(RecordingTool.ID)


func _top_face(brush: Node) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.y > 0.99:
			return i
	return -1


class SelectionScopeRoot:
	extends Node

	func is_brush_node(node: Node) -> bool:
		return node != null and str(node.get_meta("hf_kind", "")) == "brush"

	func is_entity_node(node: Node) -> bool:
		return node != null and str(node.get_meta("hf_kind", "")) == "entity"


## A level that counts the calls the change tracker makes into it, and still
## makes them.
class TrackedLevel:
	extends LevelRoot

	var full_reconcile_count := 0
	var structure_sync_count := 0
	var entity_name_reconciles: Array = []

	func tag_full_reconcile() -> void:
		full_reconcile_count += 1
		super()

	func reconcile_external_brush_structure() -> bool:
		structure_sync_count += 1
		return super()

	func reconcile_external_entity_names(
		previous_names: Dictionary, current_names: Dictionary
	) -> void:
		entity_name_reconciles.append({"previous": previous_names, "current": current_names})
		super(previous_names, current_names)


func test_click_stays_below_threshold_and_marquee_starts_at_threshold() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2(10, 20), false, false, false, true, true, false, [])

	assert_eq(
		gesture.update_motion(Vector2(15, 20), true, THRESHOLD),
		SelectionGesture.MotionDecision.WAITING,
	)
	var click := gesture.finish(Vector2(15, 20), THRESHOLD)
	assert_eq(click["decision"], SelectionGesture.ReleaseDecision.CLICK)
	assert_eq(click["distance"], 5.0)
	assert_false(gesture.is_active())

	gesture.begin(Vector2(10, 20), false, false, false, true, true, false, [])
	assert_eq(
		gesture.update_motion(Vector2(16, 20), true, THRESHOLD),
		SelectionGesture.MotionDecision.DRAW_MARQUEE,
		"The exact threshold belongs to marquee, not click",
	)
	assert_true(gesture.is_marquee_owned())
	var marquee := gesture.finish(Vector2(16, 20), THRESHOLD)
	assert_eq(marquee["decision"], SelectionGesture.ReleaseDecision.MARQUEE)
	assert_eq(marquee["origin"], Vector2(10, 20))
	assert_eq(marquee["position"], Vector2(16, 20))


func test_release_without_motion_still_classifies_threshold_as_marquee() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, false, [])

	var result := gesture.finish(Vector2(THRESHOLD, 0), THRESHOLD)
	assert_eq(result["decision"], SelectionGesture.ReleaseDecision.MARQUEE)
	assert_eq(result["distance"], THRESHOLD)
	assert_false(gesture.is_active())


func test_native_widget_claim_overrides_pending_and_marquee_ownership() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, true, [])
	gesture.claim_native_gizmo()

	assert_true(gesture.is_native_owned())
	assert_eq(
		gesture.update_motion(Vector2(40, 0), true, THRESHOLD),
		SelectionGesture.MotionDecision.NATIVE_GIZMO,
	)
	var pending_claim := gesture.finish(Vector2(40, 0), THRESHOLD)
	assert_eq(pending_claim["decision"], SelectionGesture.ReleaseDecision.NATIVE_GIZMO)

	# A late custom-gizmo signal must still win over a marquee already drawn for
	# this physical press; the gesture must never complete both operations.
	gesture.begin(Vector2.ZERO, false, false, false, true, true, false, [])
	assert_eq(
		gesture.update_motion(Vector2(40, 0), true, THRESHOLD),
		SelectionGesture.MotionDecision.DRAW_MARQUEE,
	)
	gesture.claim_native_gizmo()
	assert_true(gesture.is_native_owned())
	var marquee_claim := gesture.finish(Vector2(40, 0), THRESHOLD)
	assert_eq(marquee_claim["decision"], SelectionGesture.ReleaseDecision.NATIVE_GIZMO)


func test_native_candidates_yield_rmb_and_escape_before_any_value_moves() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, false, false, true, [], true)

	assert_true(gesture.should_yield_cancel_to_native())
	assert_false(gesture.is_native_owned(), "A candidate need not have mutated a value yet")
	gesture.reset()
	assert_false(gesture.should_yield_cancel_to_native())

	gesture.begin(Vector2.ZERO, false, false, true, true, true, false, [], true)
	assert_true(
		gesture.should_yield_cancel_to_native(),
		"CUSTOM face selection must still yield cancel when an opaque gizmo may own LMB",
	)
	var release := gesture.finish(Vector2.ZERO, THRESHOLD)
	assert_true(
		release["native_cancel_candidate"],
		"Release routing must retain the press-time native-gizmo candidate",
	)


## While Godot owns an Object Select press, the whole keyboard is Godot's: a key
## HammerForge would take changes nothing, and Escape lets go of the gesture.
func test_native_owned_selection_yields_all_keyboard_shortcuts_to_godot() -> void:
	assert_not_null(rig.plugin, rig.error())
	var level = await rig.make_level()
	_pick_tool("tool_select")
	assert_eq(_left(true, AIM), PASS, "an Object Select press is Godot's")
	var grid: float = rig.plugin.dock.get_grid_snap()
	assert_eq(rig.forward(PluginRig.key_for("grid_increase")), PASS, "so is a key while it is held")
	assert_eq(rig.plugin.dock.get_grid_snap(), grid, "which changes nothing of HammerForge's")
	assert_eq(rig.forward(PluginRig.key(KEY_ESCAPE)), PASS, "Escape goes to Godot as well")
	assert_false(rig.plugin._selection_gesture.is_active(), "and lets go of the gesture")
	_left(false, AIM)
	_pick_tool("tool_draw")
	await rig.leave_level(level)


func test_selected_transform_mutation_claims_native_before_distance_threshold() -> void:
	var selected := Node3D.new()
	add_child_autoqfree(selected)
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, true, [selected])

	selected.global_position = Vector3(1, 2, 3)
	assert_eq(
		gesture.update_motion(Vector2.ONE, true, THRESHOLD),
		SelectionGesture.MotionDecision.NATIVE_GIZMO,
		"A selected-node transform change takes precedence over click/marquee distance",
	)
	assert_true(gesture.is_native_owned())
	var result := gesture.finish(Vector2.ONE, THRESHOLD)
	assert_eq(result["decision"], SelectionGesture.ReleaseDecision.NATIVE_GIZMO)


func test_release_detects_selected_transform_mutation_without_motion_event() -> void:
	var selected := Node3D.new()
	add_child_autoqfree(selected)
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, true, [selected])

	selected.global_rotation = Vector3(0, 0.25, 0)
	var result := gesture.finish(Vector2.ONE, THRESHOLD)
	assert_eq(result["decision"], SelectionGesture.ReleaseDecision.NATIVE_GIZMO)
	assert_false(gesture.is_active())


func test_selected_node_gets_one_native_probe_before_marquee_claim() -> void:
	var selected := Node3D.new()
	add_child_autoqfree(selected)
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, true, [selected])

	assert_eq(
		gesture.update_motion(Vector2(20, 0), true, THRESHOLD),
		SelectionGesture.MotionDecision.WAITING,
		"The first forwarded motion lets the native transform gizmo mutate selection",
	)
	assert_false(gesture.is_marquee_owned())
	assert_eq(
		gesture.update_motion(Vector2(20, 0), true, THRESHOLD),
		SelectionGesture.MotionDecision.DRAW_MARQUEE,
	)
	assert_true(gesture.is_marquee_owned())


func test_press_time_modifiers_are_returned_unchanged_at_release() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2(3, 4), true, true, true, true, true, false, [])

	var result := gesture.finish(Vector2(4, 4), THRESHOLD)
	assert_eq(result["decision"], SelectionGesture.ReleaseDecision.CLICK)
	assert_true(result["additive"])
	assert_true(result["toggle"])
	assert_true(result["face_select"])
	assert_eq(result["origin"], Vector2(3, 4))

	# A new press resets captured modifiers instead of leaking the prior press.
	gesture.begin(Vector2.ZERO, false, false, false, true, true, false, [])
	var next_result := gesture.finish(Vector2.ZERO, THRESHOLD)
	assert_false(next_result["additive"])
	assert_false(next_result["toggle"])
	assert_false(next_result["face_select"])


func test_motion_without_left_button_recovers_from_a_missed_release() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2(8, 9), true, true, false, true, true, false, [])

	assert_eq(
		gesture.update_motion(Vector2(30, 40), false, THRESHOLD),
		SelectionGesture.MotionDecision.RECOVERED,
	)
	assert_false(gesture.is_active())
	assert_eq(gesture.owner, SelectionGesture.Owner.NONE)
	assert_eq(gesture.origin, Vector2.ZERO)
	assert_eq(gesture.current, Vector2.ZERO)
	var stale_release := gesture.finish(Vector2(30, 40), THRESHOLD)
	assert_eq(stale_release["decision"], SelectionGesture.ReleaseDecision.PASS_THROUGH)


func test_no_marquee_selected_or_native_press_remains_pass_through() -> void:
	var selected := Node3D.new()
	add_child_autoqfree(selected)
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, false, false, true, [selected])

	assert_true(gesture.native_passthrough)
	assert_eq(
		gesture.update_motion(Vector2(40, 0), true, THRESHOLD),
		SelectionGesture.MotionDecision.WAITING,
	)
	assert_false(gesture.is_marquee_owned())
	var drag_result := gesture.finish(Vector2(40, 0), THRESHOLD)
	assert_eq(drag_result["decision"], SelectionGesture.ReleaseDecision.PASS_THROUGH)

	# The same ownership policy also leaves a short click to Godot/native tools.
	gesture.begin(Vector2.ZERO, false, false, false, false, false, true, [selected])
	var click_result := gesture.finish(Vector2.ONE, THRESHOLD)
	assert_eq(click_result["decision"], SelectionGesture.ReleaseDecision.PASS_THROUGH)
	assert_false(gesture.is_active())


func test_geometry_drag_without_marquee_resolves_to_pressed_object_click() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2(12, 18), false, false, false, false, true, false, [])

	assert_eq(
		gesture.update_motion(Vector2(90, 18), true, THRESHOLD),
		SelectionGesture.MotionDecision.WAITING,
	)
	assert_false(gesture.is_marquee_owned())
	var result := gesture.finish(Vector2(90, 18), THRESHOLD)
	assert_eq(result["decision"], SelectionGesture.ReleaseDecision.CLICK)
	assert_eq(result["origin"], Vector2(12, 18), "Selection must use the pressed geometry")


func test_reset_restores_all_defaults_and_cannot_create_native_ownership() -> void:
	var selected := Node3D.new()
	add_child_autoqfree(selected)
	var gesture := _new_gesture()
	gesture.begin(Vector2(5, 7), true, true, true, true, false, true, [selected])
	gesture.update_motion(Vector2(20, 7), true, THRESHOLD)
	gesture.reset()

	assert_eq(gesture.owner, SelectionGesture.Owner.NONE)
	assert_eq(gesture.origin, Vector2.ZERO)
	assert_eq(gesture.current, Vector2.ZERO)
	assert_false(gesture.additive)
	assert_false(gesture.toggle)
	assert_false(gesture.face_select)
	assert_false(gesture.marquee_allowed)
	assert_true(gesture.click_allowed)
	assert_false(gesture.native_passthrough)
	assert_false(gesture.native_cancel_candidate)
	assert_false(gesture._native_probe_complete)
	assert_true(gesture._transform_snapshots.is_empty())
	assert_eq(
		gesture.update_motion(Vector2.ONE, true, THRESHOLD),
		SelectionGesture.MotionDecision.IDLE,
	)

	gesture.claim_native_gizmo()
	assert_false(gesture.is_active(), "A stale native claim cannot resurrect a reset gesture")
	assert_false(gesture.is_native_owned())


func test_buttonless_motion_is_the_only_lmb_capture_recovery_signal() -> void:
	var idle_motion := InputEventMouseMotion.new()
	assert_true(HammerForgePlugin.is_lmb_release_recovery_motion(idle_motion))

	var dragging_motion := InputEventMouseMotion.new()
	dragging_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	assert_false(HammerForgePlugin.is_lmb_release_recovery_motion(dragging_motion))

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	assert_false(HammerForgePlugin.is_lmb_release_recovery_motion(release))


## Every Object Select press stays native and opens a native selection session,
## and while it is held its motion goes nowhere else: an external tool switched
## on partway through never sees it. A press on a face in Face Select is
## HammerForge's.
func test_plugin_routes_owned_selection_before_raycast_and_tool_dispatch() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	_pick_tool("tool_select")
	assert_eq(_left(true, AIM), PASS, "an Object Select press is native")
	assert_true(rig.plugin._native_selection_active, "and opens a native selection session")
	# Switched on through the registry, as a project script might, so the press
	# in hand is not cancelled the way a tool change from the dock cancels it.
	var tool := RecordingTool.new()
	rig.plugin._tool_registry.register_tool(tool)
	rig.plugin._tool_registry.activate_tool(RecordingTool.ID, level, rig.camera)
	assert_eq(_drag(AIM + Vector2(20, 0)), PASS)
	assert_eq(tool.events.size(), 0, "the held press's motion is the selection's, not the tool's")
	_left(false, AIM + Vector2(20, 0))
	_stop_tool()
	await rig.frame()

	_face_select(true)
	var on_top := rig.camera.unproject_position(Vector3(0, 4, 0))
	assert_eq(_left(true, on_top), CUSTOM, "a face press in Face Select is HammerForge's")
	_left(false, on_top)
	assert_eq(level.face_selection.get("a", []), [_top_face(box)], "and picks the face")
	_face_select(false)
	_pick_tool("tool_draw")
	await rig.leave_level(level)


func test_the_old_gizmo_guard_stays_gone() -> void:
	# A grep on purpose: Godot's own gizmo hit-testing replaced a radius guess, and
	# the names of the guess are what would come back with it.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_false(source.contains("SELECT_GIZMO_GUARD_RADIUS"))
	assert_false(source.contains("_pointer_near_selected_gizmo"))


## Object Select records Shift as adding to Godot's selection and leaves Ctrl to
## Godot; Face Select takes Ctrl as a toggle.
func test_object_select_keeps_native_shift_and_leaves_ctrl_cmd_to_godot() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	_pick_tool("tool_select")
	assert_eq(_left(true, AIM, true), PASS, "Shift+click is Godot's")
	assert_true(rig.plugin._native_selection_additive, "recorded as adding")
	assert_false(rig.plugin._native_selection_toggle)
	_left(false, AIM)
	assert_eq(_left(true, AIM, false, true), PASS, "Ctrl+click is Godot's")
	assert_false(rig.plugin._native_selection_additive, "and not taken as adding")
	assert_false(rig.plugin._native_selection_toggle, "or toggling")
	_left(false, AIM)
	await rig.frame()

	_face_select(true)
	var on_top := rig.camera.unproject_position(Vector3(0, 4, 0))
	_left(true, on_top)
	_left(false, on_top)
	assert_eq(level.face_selection.get("a", []), [_top_face(box)], "a face click picks the face")
	_left(true, on_top, false, true)
	assert_true(rig.plugin._selection_gesture.toggle, "Ctrl in Face Select toggles")
	_left(false, on_top, false, true)
	assert_eq(level.face_selection.get("a", []), [], "so Ctrl+click on it again drops it")
	_face_select(false)
	_pick_tool("tool_draw")
	await rig.leave_level(level)


func test_face_selection_release_keeps_native_gizmo_cleanup_alive() -> void:
	assert_eq(
		HammerForgePlugin.custom_selection_release_result(true),
		EditorPlugin.AFTER_GUI_INPUT_CUSTOM,
	)
	assert_eq(
		HammerForgePlugin.custom_selection_release_result(false),
		EditorPlugin.AFTER_GUI_INPUT_PASS,
	)
	# Through the plugin: a face click and a face marquee both end on a CUSTOM
	# release, which is what lets the native gizmo commit and clean up.
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	_pick_tool("tool_select")
	_face_select(true)
	var on_top := rig.camera.unproject_position(Vector3(0, 4, 0))
	assert_eq(_left(true, on_top), CUSTOM)
	assert_eq(_left(false, on_top), CUSTOM, "a face click's release")
	assert_eq(level.face_selection.get("a", []), [_top_face(box)], "picks the face")
	assert_eq(_left(true, Vector2(40, 40)), CUSTOM)
	assert_eq(_drag(Vector2(760, 560)), CUSTOM, "the drag draws the marquee")
	assert_eq(_left(false, Vector2(760, 560)), CUSTOM, "and the marquee's release")
	var picked: Array = level.face_selection.get("a", [])
	assert_gt(picked.size(), 1, "selects the faces it covers")
	assert_lt(picked.size(), 6, "that can be seen, not the ones facing away")
	_face_select(false)
	_pick_tool("tool_draw")
	await rig.leave_level(level)


## The press, release and in-gesture callbacks plugin.gd owns reach the selection
## module: a press opens the gesture, motion beyond the threshold becomes a
## marquee, and the release closes it.
func test_plugin_selection_callbacks_are_thin_delegates() -> void:
	var level = await rig.make_level()
	rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	_pick_tool("tool_select")
	_face_select(true)
	assert_eq(_left(true, Vector2(40, 40)), CUSTOM, "the press opens the gesture")
	assert_true(rig.plugin._selection_gesture.is_active())
	assert_eq(_drag(Vector2(400, 400)), CUSTOM)
	assert_true(rig.plugin._marquee_overlay_active, "motion past the threshold draws a marquee")
	assert_eq(_left(false, Vector2(400, 400)), CUSTOM)
	assert_false(rig.plugin._selection_gesture.is_active(), "and the release closes it")
	assert_false(rig.plugin._marquee_overlay_active)
	_face_select(false)
	_pick_tool("tool_draw")
	await rig.leave_level(level)


## The dock's Face Select button makes face editing modal: the object selection
## is put aside and its gizmos with it, Select is the tool, paint mode and any
## external tool are off, and while it is on a press picks a face whatever the
## dock says. Selecting an object closes it; turning it off brings the object
## selection back.
func test_face_select_is_modal_and_hides_ambiguous_object_gizmos() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	var dock = rig.plugin.dock
	rig.select([box])
	rig.plugin._toggle_paint_mode()
	var tool := _start_tool(level)
	assert_true(tool.is_active, "a tool is active going in")

	_face_select(true)
	assert_eq(rig.plugin.stand_in_editor.selection.get_selected_nodes(), [], "objects put aside")
	assert_true(dock.tool_select.button_pressed, "Select is the tool")
	assert_false(dock.is_paint_mode_enabled(), "paint mode is off")
	assert_false(tool.is_active, "and the external tool too")

	# The dock re-reporting Draw and paint mode changes nothing while it is on.
	dock.tool_draw.set_pressed_no_signal(true)
	dock.paint_mode.set_pressed_no_signal(true)
	var on_top := rig.camera.unproject_position(Vector3(0, 4, 0))
	assert_eq(_left(true, on_top), CUSTOM, "a press still picks a face")
	_left(false, on_top)
	assert_eq(level.face_selection.get("a", []), [_top_face(box)])
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "rather than drawing")
	dock.tool_draw.set_pressed_no_signal(false)
	dock.paint_mode.set_pressed_no_signal(false)

	rig.select([box])
	assert_false(dock.is_face_select_mode_enabled(), "selecting an object closes Face Select")
	assert_has(rig.toasts(), "Face Select closed for object editing")
	assert_true(level.face_selection.is_empty(), "and lets go of the faces")

	_face_select(true)
	_face_select(false)
	assert_eq(
		rig.plugin.stand_in_editor.selection.get_selected_nodes(),
		[box],
		"turning it off brings the objects back"
	)
	_stop_tool()
	_pick_tool("tool_draw")
	await rig.leave_level(level)


## A hot reload can leave the gesture unset on the live plugin. The next viewport
## event puts it back before anything asks it who owns the pointer.
func test_selection_runtime_state_self_heals_after_editor_hot_reload() -> void:
	var level = await rig.make_level()
	rig.plugin._selection_gesture = null
	rig.forward(PluginRig.motion(AIM))
	assert_not_null(rig.plugin._selection_gesture, "the gesture is back")
	await rig.leave_level(level)


## The native Scene selection can hold a plain Node or a CanvasItem; selecting
## them, and pressing a key over the viewport with them selected, raises nothing.
func test_native_selection_accepts_non_node3d_editor_nodes() -> void:
	var level = await rig.make_level()
	var plain := Node.new()
	plain.name = "Plain"
	rig.scene_root.add_child(plain)
	var label := Label.new()
	label.name = "Label"
	rig.scene_root.add_child(label)
	rig.select([plain, label])
	assert_eq(rig.plugin.hf_selection, [plain, label], "the plugin holds them")
	rig.plugin._update_hud_context()
	assert_eq(rig.forward(PluginRig.key_for("delete")), PASS, "and leaves them to Godot")
	await rig.leave_level(level)


func test_nested_entity_children_normalize_to_the_managed_entity_owner() -> void:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	var entity := DraftEntity.new()
	entity.name = "Entity"
	root.entities_node.add_child(entity)
	var preview_child := Node3D.new()
	preview_child.name = "PreviewChild"
	entity.add_child(preview_child)
	assert_same(
		HammerForgePlugin.normalize_managed_selection_owner(preview_child, root),
		entity,
	)

	var legacy_entity := Node3D.new()
	legacy_entity.name = "LegacyEntity"
	root.entities_node.add_child(legacy_entity)
	var legacy_child := Node3D.new()
	legacy_entity.add_child(legacy_child)
	assert_same(
		HammerForgePlugin.normalize_managed_selection_owner(legacy_child, root),
		legacy_entity,
	)


func test_shortcut_scope_separates_native_hammerforge_and_mixed_selection() -> void:
	var fake_root := SelectionScopeRoot.new()
	add_child_autoqfree(fake_root)
	var brush := Node3D.new()
	brush.set_meta("hf_kind", "brush")
	add_child_autoqfree(brush)
	var entity := Node3D.new()
	entity.set_meta("hf_kind", "entity")
	add_child_autoqfree(entity)
	var camera := Camera3D.new()
	add_child_autoqfree(camera)

	assert_eq(
		HammerForgePlugin.classify_selection_scope([], fake_root),
		HammerForgePlugin.SelectionScope.EMPTY,
	)
	assert_eq(
		HammerForgePlugin.classify_selection_scope([camera], fake_root),
		HammerForgePlugin.SelectionScope.NATIVE_ONLY,
	)
	assert_eq(
		HammerForgePlugin.classify_selection_scope([brush, entity], fake_root),
		HammerForgePlugin.SelectionScope.HAMMERFORGE_ONLY,
	)
	assert_eq(
		HammerForgePlugin.classify_selection_scope([brush, camera], fake_root),
		HammerForgePlugin.SelectionScope.MIXED,
	)


## Every managed key over the viewport is refused for a selection holding a
## Godot node as well as HammerForge's: consumed, explained, and nothing done.
## While Godot owns a press, the editor shortcuts are Godot's too.
func test_managed_shortcuts_share_the_native_and_mixed_selection_guard() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(4, 0, 0))
	rig.select([a, b, rig.native_node()])
	var before := var_to_str(level.capture_state(false))
	var prefabs_before := _prefab_files()
	var keys := {}
	for action in [
		"delete",
		"duplicate",
		"group",
		"hollow",
		"move_to_floor",
		"clip",
		"carve",
		"merge",
		"apply_last_texture",
		"select_similar",
		"vertex_edit",
		"quick_save_prefab",
	]:
		keys[action] = PluginRig.key_for(action)
	keys["nudge"] = PluginRig.key(KEY_LEFT)
	for action in keys:
		rig.clear_toasts()
		assert_eq(rig.forward(keys[action]), STOP, "%s is consumed" % action)
		assert_has(rig.toasts(), "Edit HammerForge and Godot nodes separately", action)
	assert_eq(var_to_str(level.capture_state(false)), before, "and none of them ran")
	_remove_prefabs_since(prefabs_before)
	assert_false(rig.plugin._vertex_mode)

	rig.select([a])
	_pick_tool("tool_select")
	_left(true, AIM)
	rig.plugin._on_brush_gizmo_action_started()
	assert_false(rig.press_shortcut(PluginRig.key(KEY_RIGHT, true)), "Ctrl+Right is Godot's")
	assert_false(rig.press_shortcut(PluginRig.key(KEY_ESCAPE)), "and Escape")
	assert_eq(a.global_position, Vector3.ZERO, "during a press Godot owns")
	rig.plugin._on_brush_gizmo_action_finished()
	_left(false, AIM)
	_pick_tool("tool_draw")
	await rig.leave_level(level)


func _prefab_files() -> PackedStringArray:
	var dir := HFPrefabSystemScript.PREFAB_DIR
	return (
		DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
	)


## Quick Save Prefab writes into the project, so anything a broken guard let it
## write is taken away again.
func _remove_prefabs_since(before: PackedStringArray) -> void:
	for file_name in _prefab_files():
		if not before.has(file_name):
			DirAccess.remove_absolute(HFPrefabSystemScript.PREFAB_DIR.path_join(file_name))


func test_every_managed_action_surface_uses_the_shared_scope_guard() -> void:
	var delete_requirement := HammerForgePlugin.managed_surface_action_requirement("delete")
	assert_false(delete_requirement["brushes_only"])
	assert_eq(delete_requirement["minimum"], 1)
	var merge_requirement := HammerForgePlugin.managed_surface_action_requirement("merge")
	assert_true(merge_requirement["brushes_only"])
	assert_eq(merge_requirement["minimum"], 2)
	assert_true(
		HammerForgePlugin.managed_surface_action_requirement("apply_to_brush")["allow_faces"]
	)
	assert_true(HammerForgePlugin.managed_surface_action_requirement("toggle_grid").is_empty())

	# Through the plugin: with a brush and a Godot node selected, Delete from the
	# toolbar, the palette and the viewport menu is refused, and so is a material
	# swatch on the context toolbar.
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var box = rig.box(level, "a", Vector3.ZERO)
	rig.select([box, rig.native_node()])
	rig.plugin._context_toolbar.action_requested.emit("delete", [])
	rig.plugin._hotkey_palette.action_invoked.emit("delete")
	rig.plugin._viewport_context_menu.action_requested.emit("delete", [])
	assert_not_null(level.find_brush_by_id("a"), "no surface deleted part of a mixed selection")
	var paint_before = box.material_override
	rig.clear_toasts()
	rig.plugin._context_toolbar.material_quick_apply.emit(1)
	assert_eq(box.material_override, paint_before, "and the swatch painted nothing")
	assert_has(rig.toasts(), "Edit HammerForge and Godot nodes separately", "but said why")
	await rig.leave_level(level)


## Motion with the left button up proves a release went missing. The plugin
## settles what that release would have ended before anything else sees the
## motion: the active tool is asked to recover first, and a Draw drag left open
## is closed.
func test_plugin_recovers_stale_gizmo_and_lmb_owners_before_tool_motion() -> void:
	var level = await rig.make_level()
	var tool := _start_tool(level)
	tool.calls.clear()
	rig.forward(PluginRig.motion(AIM))
	assert_eq(tool.calls, ["recover", "input"], "the tool recovers before it sees the motion")
	_stop_tool()

	_pick_tool("tool_draw")
	assert_eq(_left(true, AIM), STOP, "a Draw press")
	assert_true(level.input_state.is_drag_base(), "opens a drag")
	rig.forward(PluginRig.motion(AIM + Vector2(30, 0)))
	assert_true(level.input_state.is_idle(), "which motion without the button closes")
	await rig.leave_level(level)


func test_the_brush_gizmo_settles_its_own_handle_drag() -> void:
	# A grep, because the brush gizmo plugin is an EditorNode3DGizmoPlugin, which
	# only the editor can build.
	var gizmo_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/brush_gizmo_plugin.gd"
	)
	assert_true(gizmo_source.contains("func cancel_active_handle_action() -> bool:"))
	assert_true(gizmo_source.contains("_active_handle_restore"))
	assert_true(
		gizmo_source.contains("apply_resize_transaction(brush, _active_handle_restore, true")
	)


## When the editor window loses focus, every transient pointer owner lets go on
## the next frame: Godot's camera look, the active tool's capture, a selection
## press and a Draw drag, quietly. Motion with the button up ends a selection
## press the same way.
func test_focus_loss_cancels_transient_pointer_ownership() -> void:
	var level = await rig.make_level()
	var tool := _start_tool(level)
	rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true))
	assert_true(rig.plugin._rmb_camera_navigation.active, "camera look is on")
	rig.plugin.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await rig.frame()
	assert_false(rig.plugin._rmb_camera_navigation.active, "focus loss ends camera look")
	assert_eq(tool.cancelled, 1, "and the tool's capture")
	assert_true(tool.is_active, "without switching the tool off")
	_stop_tool()

	_pick_tool("tool_select")
	_left(true, AIM)
	assert_true(rig.plugin._selection_gesture.is_active(), "a selection press is held")
	rig.plugin.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await rig.frame()
	assert_false(rig.plugin._selection_gesture.is_active(), "and focus loss lets it go")

	_pick_tool("tool_draw")
	_left(true, AIM)
	assert_true(level.input_state.is_drag_base(), "a Draw drag is open")
	rig.clear_toasts()
	rig.plugin.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await rig.frame()
	assert_true(level.input_state.is_idle(), "focus loss closes it")
	assert_eq(rig.toasts(), [], "without a word, since the user did not ask")

	_pick_tool("tool_select")
	_left(true, AIM)
	assert_eq(rig.forward(PluginRig.motion(AIM + Vector2(2, 0))), PASS)
	assert_false(rig.plugin._selection_gesture.is_active(), "motion with the button up ends it too")
	_pick_tool("tool_draw")
	await rig.leave_level(level)


## A face marquee takes only faces that can be seen: none of a hidden brush, and
## none a brush faces away. Ctrl+marquee over picked faces drops them.
func test_face_marquee_honors_toggle_and_visibility_contracts() -> void:
	var level = await rig.make_level()
	rig.box(level, "shown", Vector3(-8, 0, 0), Vector3(6, 6, 6))
	var hidden = rig.box(level, "hidden", Vector3(8, 0, 0), Vector3(6, 6, 6))
	hidden.visible = false
	_pick_tool("tool_select")
	_face_select(true)
	_left(true, Vector2(5, 5))
	_drag(Vector2(795, 595))
	_left(false, Vector2(795, 595))
	assert_eq(level.face_selection.keys(), ["shown"], "the hidden brush gives no faces")
	var picked: Array = level.face_selection["shown"]
	assert_lt(picked.size(), 6, "and the shown one only those facing the camera")
	_left(true, Vector2(5, 5), false, true)
	_drag(Vector2(795, 595))
	_left(false, Vector2(795, 595), false, true)
	assert_true(level.face_selection.is_empty(), "Ctrl+marquee drops them again")
	_face_select(false)
	_pick_tool("tool_draw")
	await rig.leave_level(level)


func test_object_marquee_stays_godots() -> void:
	# A grep on purpose: an object marquee of HammerForge's own was removed for
	# Godot's native one, and this keeps it from coming back.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_false(
		source.contains("func _select_nodes_in_rect"),
		"Object marquee belongs wholly to Godot's native viewport selection",
	)


## With an external tool active and idle, RMB is offered to the tool and then
## starts one native camera session, which RMB up ends.
func test_idle_external_tool_rmb_starts_one_native_camera_session() -> void:
	var level = await rig.make_level()
	var tool := _start_tool(level)
	tool.events.clear()
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true)), PASS, "RMB is Godot's")
	assert_eq(tool.events.size(), 1, "after the tool was offered it")
	assert_true(rig.plugin._rmb_camera_navigation.active, "and camera look begins")
	rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, false))
	assert_false(rig.plugin._rmb_camera_navigation.active, "RMB up ends it")
	_stop_tool()
	await rig.leave_level(level)


## The plugin draws the marquee through the Control Godot hands it for the 3D
## viewport's overlay, and adopts that Control as its overlay host.
func test_marquee_draws_in_the_native_3d_viewport_overlay() -> void:
	# Kept until the rig goes: the plugin parents its viewport overlays on it.
	var host := Control.new()
	rig.viewport.add_child(host)
	rig.plugin._forward_3d_force_draw_over_viewport(host)
	assert_eq(rig.plugin._viewport_overlay_host, host, "the viewport's overlay Control is kept")
	# Greps, for what the stand-in cannot see: the force-draw registration with the
	# editor, the canvas commands the draw makes, and the redraw request.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var overlay_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/plugin_overlays.gd"
	)
	assert_true(source.contains("set_force_draw_over_forwarding_enabled()"))
	assert_true(overlay_source.contains("viewport_control.draw_rect"))
	assert_true(overlay_source.contains("update_overlays()"))
	assert_false(
		source.contains(
			"add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _marquee_overlay)"
		),
		"A viewport marquee must not be laid out or clipped by the spatial toolbar",
	)


func test_native_marquee_expands_and_toggles_groups_as_units() -> void:
	var first := Node3D.new()
	var second := Node3D.new()
	add_child_autoqfree(first)
	add_child_autoqfree(second)
	var groups := {"pair": [first, second]}

	var added := HammerForgePlugin.expand_native_group_members([], [first], false, groups)
	assert_has(added, first)
	assert_has(added, second)

	var toggled_off := HammerForgePlugin.expand_native_group_members(
		[first, second], [second], true, groups
	)
	assert_true(toggled_off.is_empty(), "Native removal of one member removes the whole group")

	var plain_reselect := HammerForgePlugin.expand_native_group_members(
		[first, second], [first], false, groups
	)
	assert_has(plain_reselect, first)
	assert_has(plain_reselect, second)

	var replaced_member := HammerForgePlugin.expand_native_group_members(
		[first], [second], false, groups
	)
	assert_has(replaced_member, first)
	assert_has(replaced_member, second)

	var toggled_replacement := HammerForgePlugin.expand_native_group_members(
		[first], [second], true, groups
	)
	assert_true(
		toggled_replacement.is_empty(),
		"Equal member counts can still represent a native member replacement",
	)

	# Through the plugin: selecting one member of a group selects the group, and
	# the dock and vertex mode follow; a Shift+click that drops one member while
	# Godot owns the press drops the whole group.
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(6, 0, 0))
	var c = rig.box(level, "c", Vector3(20, 0, 0))
	level.visgroup_system.group_selection("pair", [a, b])
	var selection = rig.plugin.stand_in_editor.selection
	rig.select([a])
	assert_eq(selection.get_selected_nodes().size(), 2, "one member selects the group")
	assert_has(selection.get_selected_nodes(), b)
	assert_string_contains(rig.plugin.dock.selection_label.text, "2 brushes")
	_pick_tool("tool_select")
	_left(true, AIM, true)
	selection.remove_node(b)
	assert_eq(selection.get_selected_nodes(), [], "dropping one member drops the group")
	_left(false, AIM, true)
	await rig.frame()
	rig.select([c])
	_pick_tool("vertex_edit")
	rig.select([a])
	for position in level.vertex_system.get_all_vertex_world_positions():
		assert_lt(position.pos.x, 10.0, "vertex mode follows the selection to the group")
	_pick_tool("vertex_edit")
	_pick_tool("tool_draw")
	await rig.leave_level(level)


## The selection-state callbacks plugin.gd owns reach the module, each doing
## its own part through the real plugin.
func test_plugin_selection_state_callbacks_are_thin_delegates() -> void:
	var level = await rig.make_level()
	var plugin: Node = rig.plugin
	var a = rig.box(level, "a", Vector3.ZERO)
	var lamp := rig.native_node()
	var entity = DraftEntity.new()
	entity.entity_type = "light_point"
	level.add_entity(entity)
	var selection = plugin.stand_in_editor.selection

	rig.select([a])
	assert_eq(plugin.hf_selection, [a], "the editor's selection reaches the plugin")
	assert_eq(plugin._current_selection_nodes(), [a])
	plugin._apply_selection_list([entity], false)
	assert_eq(selection.get_selected_nodes(), [entity], "a list applies to the editor")
	plugin.hf_selection = [a, entity]
	plugin._apply_hf_selection(selection)
	assert_eq(selection.get_selected_nodes(), [a, entity], "and so does the plugin's own")
	assert_eq(plugin._hammerforge_selection_nodes(level, true), [a], "brushes only")
	assert_eq(plugin._managed_entity_owner(level, entity), entity)
	assert_eq(plugin._hammerforge_selection_owner(entity, level), entity)
	assert_eq(HammerForgePlugin.normalize_managed_selection_owner(a, level), a)
	assert_eq(
		HammerForgePlugin.classify_selection_scope([a, lamp], level),
		HammerForgePlugin.SelectionScope.MIXED
	)
	assert_eq(plugin._guard_hammerforge_shortcut(level, false, 1, "Test"), -3, "owned: apply")
	assert_true(plugin._managed_action_surface_allowed(level, "delete"))
	rig.select([a, lamp])
	assert_eq(plugin._guard_hammerforge_shortcut(level, false, 1, "Test"), STOP, "mixed: refused")
	assert_false(plugin._managed_action_surface_allowed(level, "delete"))
	rig.select([lamp])
	assert_eq(plugin._guard_hammerforge_shortcut(level, false, 1, "Test"), PASS, "Godot's: passed")
	await rig.leave_level(level)


func test_group_removal_uses_the_owner_sessions_actual_modifier_intent() -> void:
	assert_false(
		HammerForgePlugin.group_removal_requested(false, false, false, false, false, false),
		"A plain Scene-tree reselect must expand the group instead of clearing it",
	)
	assert_true(
		HammerForgePlugin.group_removal_requested(false, false, false, true, false, false),
		"A modified Scene-tree removal should remove the complete group",
	)
	assert_true(HammerForgePlugin.group_removal_requested(true, true, false, false, false, false))
	assert_false(
		HammerForgePlugin.group_removal_requested(true, false, false, false, true, false),
		"Ambient Ctrl cannot reinterpret an already-captured native viewport press",
	)


func test_native_brush_change_tracker_is_exact_idempotent_and_undo_safe() -> void:
	var level := _tracked_level()
	var brush_a := _new_tracked_brush(level, "brush_a")
	var brush_b := _new_tracked_brush(level, "brush_b")
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)

	brush_a.position = Vector3(4, 2, -1)
	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_a"]))
	assert_eq(_dirty_ids(level), PackedStringArray(["brush_a"]))
	assert_true(tracker.reconcile(level).is_empty(), "A repeated release hook is a no-op")
	assert_eq(_dirty_ids(level), PackedStringArray(["brush_a"]))

	# A successful incremental bake spends the tags, then native Undo and Redo.
	# Both transitions must become dirty again even though selection did not change.
	level.consume_dirty_tags()
	brush_a.transform = Transform3D.IDENTITY
	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_a"]))
	level.consume_dirty_tags()
	brush_a.position = Vector3(4, 2, -1)
	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_a"]))

	level.consume_dirty_tags()
	brush_b.rotation = Vector3(0.2, 0.4, 0.1)
	brush_b.scale = Vector3(2, 1, 0.5)
	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_b"]))

	level.consume_dirty_tags()
	brush_a.visible = false
	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_a"]))
	level.consume_dirty_tags()
	brush_a.visible = true
	assert_eq(
		tracker.reconcile(level),
		PackedStringArray(["brush_a"]),
		"Undoing Scene-tree visibility must invalidate visible-only bakes",
	)
	assert_true(tracker.reconcile(level).is_empty())


## The tracker exists for edits HammerForge's own commands did not make, and
## Godot 4's Inspector has a Metadata section that edits exactly these three
## keys. The bake reads all of them: the class decides whether the brush is world
## geometry or a func_door, the name is what every connection aims at, and the
## outputs are the wiring. None of them was hashed, so the level looked right,
## Bake Changed said there was nothing to do, and the baked output still had the
## brush as plain geometry.
func test_native_metadata_edits_the_bake_reads_make_a_brush_dirty() -> void:
	var level := _tracked_level()
	var brush := _new_tracked_brush(level, "brush_a")
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)
	assert_true(tracker.reconcile(level).is_empty(), "nothing touched yet")

	brush.set_meta("brush_entity_class", "func_door")
	assert_eq(
		tracker.reconcile(level),
		PackedStringArray(["brush_a"]),
		"the brush is a door now and the bake has to be told",
	)

	level.consume_dirty_tags()
	brush.set_meta("entity_name", "secret_door")
	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_a"]))

	level.consume_dirty_tags()
	(
		brush
		. set_meta(
			"entity_io_outputs",
			[{"output_name": "OnOpen", "target_name": "light_1", "input_name": "TurnOn"}],
		)
	)
	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_a"]))
	assert_true(tracker.reconcile(level).is_empty(), "and it settles")


## The outputs are an Array of Dictionaries. Held by reference, the snapshot
## would change underneath the comparison and an edit to an existing connection
## would report nothing.
func test_editing_a_connection_in_place_is_noticed() -> void:
	var level := _tracked_level()
	var brush := _new_tracked_brush(level, "brush_a")
	var outputs: Array = [
		{"output_name": "OnOpen", "target_name": "light_1", "input_name": "TurnOn"}
	]
	brush.set_meta("entity_io_outputs", outputs)
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)

	outputs[0]["target_name"] = "light_2"

	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_a"]))


## Two more keys decide what the bake makes of a brush entity: its properties (a
## door's speed and lock, copied onto the baked mover) and its tie (which brushes
## are one door). The Inspector edits both, so Bake Changed said there was nothing
## to do and the level kept a door that was unlocked or opened in two halves
## (#1198).
func test_native_edits_to_entity_properties_and_tie_make_a_brush_dirty() -> void:
	var level := _tracked_level()
	var brush := _new_tracked_brush(level, "brush_a")
	brush.set_meta("brush_entity_class", "func_door")
	var data := {"speed": 2.0, "locked": false}
	brush.set_meta("brush_entity_data", data)
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)
	assert_true(tracker.reconcile(level).is_empty(), "nothing touched yet")

	brush.set_meta("brush_entity_data", {"speed": 9.0, "locked": false})
	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_a"]), "a new speed")

	level.consume_dirty_tags()
	# Held by reference, a snapshot would change with the edit and see nothing.
	(brush.get_meta("brush_entity_data") as Dictionary)["locked"] = true
	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_a"]), "locked in place")

	level.consume_dirty_tags()
	brush.set_meta("brush_entity_group", "tie_1")
	assert_eq(tracker.reconcile(level), PackedStringArray(["brush_a"]), "tied to another leaf")
	assert_true(tracker.reconcile(level).is_empty(), "and it settles")


## A door turned with Godot's gizmo or Inspector kept its angle, because only
## HammerForge's own Rotate turned it, so it slid out of its wall (#1256).
func _tracked_door(level: TrackedLevel, brush_id: String, angle: Variant = 0.0) -> DraftBrush:
	var brush := _new_tracked_brush(level, brush_id)
	level.tie_brushes_to_entity([brush_id], "func_door", "gate_%s" % brush_id)
	if angle != null:
		brush.set_meta("brush_entity_data", {"angle": angle})
	level.consume_dirty_tags()
	return brush


func _held_angle(brush: Node) -> Variant:
	return (brush.get_meta("brush_entity_data", {}) as Dictionary).get("angle", null)


## `brush` turned about world up by `degrees` round `pivot`, written straight onto
## the node as the gizmo, the Inspector and their undo write it.
func _native_turn(brush: Node3D, degrees: float, pivot: Vector3) -> void:
	brush.global_transform = HFTransformSystem.rotated_transform(
		brush.global_transform, Basis(Vector3.UP, deg_to_rad(degrees)), pivot
	)


func test_a_native_turn_turns_a_door_angle_and_its_undo_turns_it_back() -> void:
	var level := _tracked_level()
	var door := _tracked_door(level, "door_a")
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)
	var square := door.global_transform
	_native_turn(door, 90.0, door.global_position)
	var turned := door.global_transform
	door.global_transform = square
	# The gizmo's commit, then its undo and redo, over and over.
	for i in 3:
		door.global_transform = turned
		assert_eq(tracker.reconcile(level), PackedStringArray(["door_a"]))
		assert_eq(_held_angle(door), 90.0, "turned with it, round %d" % i)
		door.global_transform = square
		tracker.reconcile(level)
		assert_eq(_held_angle(door), 0.0, "and back to exactly where it was, round %d" % i)
	assert_true(tracker.reconcile(level).is_empty(), "and it settles")


func test_a_native_turn_turns_the_default_angle_of_a_door_that_never_set_one() -> void:
	var level := _tracked_level()
	var door := _tracked_door(level, "door_b", null)
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)
	_native_turn(door, 90.0, door.global_position)
	tracker.reconcile(level)
	assert_eq(_held_angle(door), 180.0, "func_door's 90, turned")


func test_two_brushes_of_one_door_turned_together_turn_its_angle_once() -> void:
	var level := _tracked_level()
	var first := _new_tracked_brush(level, "leaf_1")
	var second := _new_tracked_brush(level, "leaf_2")
	second.position = Vector3(0, 0, 2)
	level.tie_brushes_to_entity(["leaf_1", "leaf_2"], "func_door", "pair")
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)
	for leaf in [first, second]:
		_native_turn(leaf, 90.0, Vector3(0, 0, 1))
	tracker.reconcile(level)
	for leaf in [first, second]:
		assert_eq(_held_angle(leaf), 180.0, "%s turned once, not once a brush" % leaf.name)


func test_only_a_turn_about_up_turns_a_door_angle() -> void:
	var level := _tracked_level()
	var door := _tracked_door(level, "door_c")
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)
	var edits := {
		"tipped forward": func(n): n.rotation = Vector3(deg_to_rad(90.0), 0, 0),
		"rolled": func(n): n.rotation = Vector3(0, 0, deg_to_rad(30.0)),
		"rolled over": func(n): n.rotation = Vector3(0, 0, PI),
		"moved": func(n): n.position += Vector3(3, 1, 2),
		"scaled": func(n): n.scale = Vector3(2, 1, 0.5),
	}
	for label in edits:
		door.transform = Transform3D.IDENTITY
		tracker.reconcile(level)
		edits[label].call(door)
		assert_eq(tracker.reconcile(level), PackedStringArray(["door_c"]), "%s: noticed" % label)
		assert_eq(_held_angle(door), 0.0, "%s: not a turn of the compass" % label)


func test_a_door_hammerforge_turned_is_not_turned_again() -> void:
	# Rotate turns the angle itself and the tracker reconciles after every
	# command, so counting the turn again took the door round twice.
	var level := _tracked_level()
	var door := _tracked_door(level, "door_d")
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)
	var before := level.capture_brush_scope(["door_d"])
	level.rotate_managed_nodes(["door_d"], [], 1, 90.0, door.global_position)
	tracker.reconcile(level)
	assert_eq(_held_angle(door), 90.0, "turned once")
	level.restore_brush_scope(before)
	tracker.reconcile(level)
	# A record whose angle differs from the brush's is put back by a rebuild.
	door = level.find_brush_by_id("door_d") as DraftBrush
	assert_eq(_held_angle(door), 0.0, "and its undo puts back the angle it recorded")


func test_a_door_hammerforge_put_back_where_it_was_is_not_a_turn() -> void:
	# Reset Rotation clears a quarter-turned box by swapping its size, so its
	# basis turns and the box stays exactly where it is, and so does its slide.
	var level := _tracked_level()
	var door := _tracked_door(level, "door_e")
	door.size = Vector3(0.2, 2, 1.6)
	var tracker := BrushChangeTracker.new()
	level.rotate_managed_nodes(["door_e"], [], 1, 90.0, door.global_position)
	tracker.prime(level)
	level.reset_managed_rotation(["door_e"])
	tracker.reconcile(level)
	assert_eq(_held_angle(door), 90.0)


func test_one_reconcile_after_several_undos_lands_on_the_angle_they_recorded() -> void:
	# The History dock steps back over several actions before the deferred
	# reconcile runs: here a HammerForge nudge, then the gizmo turn before it.
	# The nudge's undo touches the door too, and the turn back still counts.
	var level := _tracked_level()
	var door := _tracked_door(level, "door_f")
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)
	var square := door.global_transform
	_native_turn(door, 90.0, door.global_position)
	var gizmo_turned := door.global_transform
	tracker.reconcile(level)
	var before := level.capture_brush_scope(["door_f"])
	level.nudge_managed_nodes(["door_f"], [], Vector3(1, 0, 0))
	var after := level.capture_brush_scope(["door_f"])
	tracker.reconcile(level)
	assert_eq(_held_angle(door), 90.0, "fixture: turned once and moved")

	level.restore_brush_scope(before)
	assert_eq(level.find_brush_by_id("door_f"), door, "fixture: put back in place")
	door.global_transform = square
	tracker.reconcile(level)
	assert_eq(_held_angle(door), 0.0, "both undone at once")

	door.global_transform = gizmo_turned
	level.restore_brush_scope(after)
	tracker.reconcile(level)
	door = level.find_brush_by_id("door_f") as DraftBrush
	assert_eq(_held_angle(door), 90.0, "and both redone at once")
	assert_true(tracker.reconcile(level).is_empty(), "and it settles")


func test_native_bake_configuration_edits_tag_one_full_reconcile_per_change() -> void:
	var level := _tracked_level()
	_new_tracked_brush(level, "stable_brush")
	var cordon_before := level.cordon_aabb
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)

	level.bake_visible_only = true
	assert_true(tracker.reconcile(level).is_empty())
	assert_eq(level.full_reconcile_count, 1)
	assert_true(_dirty_ids(level).is_empty())
	assert_true(tracker.reconcile(level).is_empty())
	assert_eq(level.full_reconcile_count, 1, "A stable setting must not repeatedly retag")

	level.cordon_enabled = true
	level.cordon_aabb = AABB(Vector3(-8, -4, -2), Vector3(16, 8, 4))
	assert_true(tracker.reconcile(level).is_empty())
	assert_eq(
		level.full_reconcile_count,
		2,
		"Multiple Inspector properties changed before one reconcile need one full tag",
	)

	# Native Undo returns through the same version-change hook and is itself a
	# new bake configuration, so it must invalidate the current output once.
	level.cordon_enabled = false
	level.cordon_aabb = cordon_before
	assert_true(tracker.reconcile(level).is_empty())
	assert_eq(level.full_reconcile_count, 3)


func test_brush_change_tracker_covers_inspector_geometry_and_root_switches() -> void:
	var first_root := _tracked_level()
	var brush := _new_tracked_brush(first_root, "inspector_brush")
	var tracker := BrushChangeTracker.new()
	tracker.prime(first_root)
	brush.size = Vector3(2, 3, 4)
	assert_eq(tracker.reconcile(first_root), PackedStringArray(["inspector_brush"]))
	first_root.consume_dirty_tags()
	brush.shape = 3
	brush.operation = 2
	brush.sides = 12
	brush.material_override = StandardMaterial3D.new()
	assert_eq(tracker.reconcile(first_root), PackedStringArray(["inspector_brush"]))
	assert_eq(_dirty_ids(first_root), PackedStringArray(["inspector_brush"]))

	var second_root := _tracked_level()
	var second := _new_tracked_brush(second_root, "second_brush")
	second.position = Vector3.UP
	assert_true(tracker.reconcile(second_root).is_empty(), "A new scene seeds without false dirt")
	second.position = Vector3.UP * 2.0
	assert_eq(tracker.reconcile(second_root), PackedStringArray(["second_brush"]))

	var drafts := first_root.draft_brushes_node
	drafts.remove_child(brush)
	assert_true(tracker.reconcile(first_root).is_empty(), "Returning to a root re-seeds safely")
	drafts.add_child(brush)
	tracker.prime(first_root)

	# What Godot's own Duplicate makes: a copy carrying the original's id.
	var duplicate := brush.duplicate() as DraftBrush
	drafts.add_child(duplicate)
	assert_eq(str(duplicate.get_meta("brush_id")), "inspector_brush")
	assert_true(tracker.reconcile(first_root).is_empty(), "New structure is not a property edit")
	assert_ne(
		duplicate.brush_id, brush.brush_id, "A native duplicate must receive a stable unique ID"
	)
	assert_eq(str(duplicate.get_meta("brush_id")), duplicate.brush_id)
	assert_eq(first_root.full_reconcile_count, 1)
	assert_eq(first_root.structure_sync_count, 1)
	drafts.remove_child(duplicate)
	duplicate.queue_free()
	assert_true(tracker.reconcile(first_root).is_empty())
	assert_eq(first_root.full_reconcile_count, 2, "A native deletion requires authoritative bake")
	assert_eq(first_root.structure_sync_count, 2)

	var pending := first_root.pending_node
	brush.reparent(pending)
	assert_true(tracker.reconcile(first_root).is_empty())
	assert_same(brush.get_parent(), drafts)
	assert_eq(
		first_root.full_reconcile_count,
		2,
		"An unsynchronized Scene-tree move must be repaired before it corrupts structure",
	)
	brush.reparent(pending)
	brush.set_meta("hf_container_role", "pending")
	assert_true(tracker.reconcile(first_root).is_empty())
	brush.reparent(drafts)
	brush.set_meta("hf_container_role", "draft")
	assert_true(tracker.reconcile(first_root).is_empty())
	assert_eq(
		first_root.full_reconcile_count,
		2,
		"A managed container move with a synchronized role must only re-seed",
	)

	var entity := DraftEntity.new()
	entity.name = "Door"
	first_root.entities_node.add_child(entity)
	tracker.prime(first_root)
	entity.name = "MainDoor"
	assert_true(tracker.reconcile(first_root).is_empty())
	assert_eq(first_root.entity_name_reconciles.size(), 1)
	assert_eq(first_root.entity_name_reconciles[0]["previous"][entity.get_instance_id()], "Door")
	assert_eq(first_root.entity_name_reconciles[0]["current"][entity.get_instance_id()], "MainDoor")
	brush.name = "Door"
	tracker.prime(first_root)
	brush.name = "RenamedStructuralBrush"
	assert_true(tracker.reconcile(first_root).is_empty())
	assert_eq(
		first_root.entity_name_reconciles.size(),
		1,
		"Renaming an ordinary brush must not hijack a same-named entity I/O target",
	)


func test_change_tracker_recovers_only_live_illegally_reparented_brushes() -> void:
	var level := _tracked_level()
	var drafts := level.draft_brushes_node
	var pending := level.pending_node
	var entities := level.entities_node
	var brush := _new_tracked_brush(level, "reparented_brush")
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)

	brush.reparent(entities)
	assert_true(tracker.reconcile(level).is_empty())
	assert_same(
		brush.get_parent(),
		drafts,
		"A Scene-tree drag into a non-brush container must return to its managed parent",
	)
	assert_eq(level.full_reconcile_count, 0)

	# A synchronized managed move is intentional, and an Undo-like restoration
	# back to DraftBrushes must update the cached parent in both directions.
	brush.reparent(pending)
	brush.set_meta("hf_container_role", "pending")
	assert_true(tracker.reconcile(level).is_empty())
	assert_same(brush.get_parent(), pending)
	brush.reparent(drafts)
	brush.set_meta("hf_container_role", "draft")
	assert_true(tracker.reconcile(level).is_empty())
	assert_same(brush.get_parent(), drafts)

	# Native deletion detaches before the authoritative index catches up. Never
	# re-add that node: soft entity I/O references must remain Undo-restorable.
	drafts.remove_child(brush)
	assert_true(tracker.reconcile(level).is_empty())
	assert_null(brush.get_parent())
	assert_eq(level.full_reconcile_count, 1)
	brush.free()


func test_native_entity_duplicate_unlinks_prefab_metadata_without_touching_source() -> void:
	var level := _tracked_level()
	var source_entity := DraftEntity.new()
	source_entity.name = "LinkedDoor"
	var prefab_meta := {
		"hf_prefab_entity_id": "door_uid",
		"hf_prefab_instance": "instance_7",
		"hf_prefab_source": "res://prefabs/door.hfprefab",
		"hf_prefab_variant": "locked",
	}
	for meta_name in prefab_meta:
		source_entity.set_meta(meta_name, prefab_meta[meta_name])
	level.entities_node.add_child(source_entity)
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)

	var native_copy := source_entity.duplicate() as Node3D
	level.entities_node.add_child(native_copy)
	assert_true(tracker.reconcile(level).is_empty())
	for meta_name in prefab_meta:
		assert_eq(source_entity.get_meta(meta_name), prefab_meta[meta_name])
		assert_false(
			native_copy.has_meta(meta_name),
			"A native entity copy must be independent from its source prefab instance",
		)


func test_brush_change_tracker_covers_nested_face_resource_inspector_edits() -> void:
	var level := _tracked_level()
	var brush := _new_tracked_brush(level, "face_resource_brush")
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	)
	face.ensure_geometry()
	var layer := FaceData.PaintLayer.new()
	layer.weight_image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	layer.weight_image.fill(Color.BLACK)
	face.paint_layers = [layer]
	var displacement := DisplacementData.new()
	displacement.init_flat(2)
	face.displacement = displacement
	brush.faces = [face]
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)

	face.uv_offset = Vector2(3, -2)
	assert_eq(tracker.reconcile(level), PackedStringArray(["face_resource_brush"]))
	level.consume_dirty_tags()
	face.local_verts[0] = Vector3(-2, 0, -1)
	assert_eq(tracker.reconcile(level), PackedStringArray(["face_resource_brush"]))
	level.consume_dirty_tags()
	layer.opacity = 0.4
	assert_eq(tracker.reconcile(level), PackedStringArray(["face_resource_brush"]))
	level.consume_dirty_tags()
	layer.weight_image.set_pixel(0, 0, Color.WHITE)
	assert_eq(tracker.reconcile(level), PackedStringArray(["face_resource_brush"]))
	level.consume_dirty_tags()
	displacement.distances[0] = 2.5
	assert_eq(tracker.reconcile(level), PackedStringArray(["face_resource_brush"]))
	assert_eq(_dirty_ids(level), PackedStringArray(["face_resource_brush"]))
	level.consume_dirty_tags()
	displacement.flip_diagonals = true
	assert_eq(tracker.reconcile(level), PackedStringArray(["face_resource_brush"]))

	var preview_brush := DraftBrush.new()
	preview_brush.shape = preview_brush.BrushShape.CUSTOM
	preview_brush.brush_id = "preview_brush"
	preview_brush.set_meta("brush_id", "preview_brush")
	preview_brush.set_meta("hf_kind", "brush")
	var preview_face := FaceData.new()
	preview_face.local_verts = PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	)
	preview_face.ensure_geometry()
	var preview_layer := FaceData.PaintLayer.new()
	preview_layer.weight_image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	preview_layer.weight_image.fill(Color.BLACK)
	preview_face.paint_layers = [preview_layer]
	var preview_displacement := DisplacementData.new()
	preview_displacement.init_flat(2)
	preview_face.displacement = preview_displacement
	preview_brush.faces = [preview_face]
	preview_brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	var prefab_meta := {
		"hf_prefab_entity_id": "brush_uid",
		"hf_prefab_instance": "instance_3",
		"hf_prefab_source": "res://prefabs/room.hfprefab",
		"hf_prefab_variant": "damaged",
	}
	for meta_name in prefab_meta:
		preview_brush.set_meta(meta_name, prefab_meta[meta_name])
	level.draft_brushes_node.add_child(preview_brush)
	tracker.prime(level)
	assert_almost_eq(preview_brush.mesh_instance.mesh.get_aabb().end.x, 1.0, 0.001)
	preview_face.local_verts[1] = Vector3(3, 0, -1)
	assert_eq(tracker.reconcile(level), PackedStringArray(["preview_brush"]))
	assert_almost_eq(
		preview_brush.mesh_instance.mesh.get_aabb().end.x,
		3.0,
		0.001,
		"Nested Inspector geometry must refresh the live preview in the same reconcile",
	)
	assert_true(tracker.reconcile(level).is_empty(), "Preview refresh must not phantom-dirty")

	var native_copy := preview_brush.duplicate() as DraftBrush
	var stale_base := MeshInstance3D.new()
	stale_base.name = "MeshCopy"
	stale_base.set_meta("_hammerforge_base_mesh", true)
	native_copy.add_child(stale_base)
	var stale_overlay := MeshInstance3D.new()
	stale_overlay.name = "_SubtractWireOverlayCopy"
	stale_overlay.set_meta("_hammerforge_visual_overlay", "subtract")
	native_copy.add_child(stale_overlay)
	level.draft_brushes_node.add_child(native_copy)
	assert_true(tracker.reconcile(level).is_empty())
	assert_ne(native_copy.brush_id, preview_brush.brush_id)
	assert_same(native_copy.mesh_instance.get_parent(), native_copy)
	var base_mesh_count := 0
	var overlay_count := 0
	for child in native_copy.get_children(true):
		if not child is MeshInstance3D:
			continue
		if bool(child.get_meta("_hammerforge_base_mesh", false)):
			base_mesh_count += 1
		if child.has_meta("_hammerforge_visual_overlay"):
			overlay_count += 1
	assert_eq(base_mesh_count, 1, "A native copy must adopt exactly one private base mesh")
	assert_eq(overlay_count, 1, "Stale copied overlays must collapse to the one required cue")
	for meta_name in prefab_meta:
		assert_eq(preview_brush.get_meta(meta_name), prefab_meta[meta_name])
		assert_false(native_copy.has_meta(meta_name))
	assert_not_same(native_copy.faces[0], preview_brush.faces[0])
	assert_not_same(native_copy.faces[0].paint_layers[0], preview_brush.faces[0].paint_layers[0])
	assert_not_same(
		native_copy.faces[0].paint_layers[0].weight_image,
		preview_brush.faces[0].paint_layers[0].weight_image,
	)
	assert_not_same(native_copy.faces[0].displacement, preview_brush.faces[0].displacement)
	var original_vertex := preview_brush.faces[0].local_verts[0]
	native_copy.faces[0].local_verts[0] += Vector3.LEFT
	assert_eq(preview_brush.faces[0].local_verts[0], original_vertex)


## A brush moved by Godot's gizmo or Inspector is reconciled once, a frame later,
## however many things asked: two undo version changes in one frame tag it once.
## The release of a native selection press asks too.
func test_plugin_defers_one_shared_native_and_inspector_brush_reconcile() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	rig.plugin._queue_managed_brush_reconcile()
	await rig.frame()
	watch_signals(level)
	a.global_position += Vector3(4, 0, 0)
	rig.plugin._on_undo_redo_version_changed()
	rig.plugin._on_undo_redo_version_changed()
	assert_signal_emit_count(level, "brush_changed", 0, "nothing before the frame ends")
	await rig.frame()
	assert_signal_emit_count(level, "brush_changed", 1, "then once for both")
	assert_eq(get_signal_parameters(level, "brush_changed"), ["a"])

	_pick_tool("tool_select")
	rig.select([a])
	_left(true, AIM)
	a.global_position += Vector3(4, 0, 0)
	_left(false, AIM)
	await rig.frame()
	assert_signal_emit_count(level, "brush_changed", 2, "a native press's release reconciles")
	_pick_tool("tool_draw")
	await rig.leave_level(level)


func _new_gesture() -> SelectionGesture:
	var gesture := SelectionGesture.new()
	autofree(gesture)
	return gesture


## Godot's own scale gizmo drags a handle past zero, or the Inspector takes a
## typed negative, and neither goes near HammerForge's Flip - which folds its
## reflection away precisely so a brush cannot end up mirrored. The brush then
## bakes inside out, and as a cutter it adds its volume instead of removing it.
## The tracker is where an edit Godot owns gets reconciled, so it is where the
## mirror comes off (#749).
func test_a_native_scale_that_mirrors_a_brush_has_the_mirror_taken_off() -> void:
	var level := _tracked_level()
	var brush := DraftBrushScript.new()
	brush.shape = 0
	brush.size = Vector3(32, 16, 8)
	brush.brush_id = "mirrored"
	brush.set_meta("brush_id", "mirrored")
	brush.set_meta("hf_kind", "brush")
	brush.set_meta("hf_container_role", "draft")
	level.draft_brushes_node.add_child(brush)
	brush.rebuild_preview()
	var tracker := BrushChangeTracker.new()
	tracker.prime(level)

	brush.scale = Vector3(-1, 1, 1)
	assert_lt(brush.global_transform.basis.determinant(), 0.0, "mirrored by the gizmo")
	var before := brush.global_position

	tracker.reconcile(level)

	assert_gt(brush.global_transform.basis.determinant(), 0.0, "the tracker took the mirror off")
	assert_almost_eq(
		brush.global_position.distance_to(before), 0.0, 0.0001, "without moving the brush"
	)


func _tracked_level() -> TrackedLevel:
	var level := TrackedLevel.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


## A brush made the way HammerForge makes one, with the tag its creation left
## already spent, as a bake would have spent it, and the counts back at zero.
func _new_tracked_brush(level: TrackedLevel, brush_id: String) -> DraftBrush:
	var brush := level.create_brush_from_info({"brush_id": brush_id}) as DraftBrush
	level.consume_dirty_tags()
	level.full_reconcile_count = 0
	level.structure_sync_count = 0
	return brush


func _dirty_ids(level: LevelRoot) -> PackedStringArray:
	return PackedStringArray(level._dirty_brush_ids.keys())
