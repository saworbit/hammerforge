@tool
class_name HFPluginGestureRecovery
extends RefCounted
## Settling gestures that were left running when nobody meant to leave them there.
##
## A drag, extrude, marquee or paint stroke is held open across frames by state on
## LevelRoot and on the plugin. Three things can strip away the release that was
## meant to close it: the application losing focus, Godot swallowing an LMB
## release across a viewport or focus change, and the user pressing RMB partway
## through. All three land here, because the alternative is a stroke that stays
## "active" forever and blocks every gesture after it.

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS


## The window went away mid-gesture. Deferred by _notification so the editor has
## finished its own focus handling before we touch shared state.
static func after_application_focus_loss(plugin: Object) -> void:
	plugin._focus_recovery_queued = false
	plugin._rmb_camera_navigation.active = false
	# Godot's 3D viewport owns native/custom gizmo focus-loss commit and clears
	# its private edit reference itself. Cancelling the local lifecycle here can
	# race that callback and restore a preview Godot has just committed.
	plugin._cancel_selection_gesture()
	if plugin._tool_registry:
		plugin._tool_registry.cancel_active_pointer_capture()
	plugin._queue_managed_brush_reconcile()
	var root: Node = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root:
		return
	# Quietly, and without touching the native gizmo: the user did not ask for
	# this and Godot is settling its own handle drag in parallel.
	plugin._prepare_tool_transition(root, false, false)
	_clear_hover(root)


## Close any paint stroke still marked active. Returns true when one was.
##
## Shared by the tool transition and by RMB cancel, because a stroke that outlived
## its release has to be finished the same way whichever of them notices first.
static func finish_stale_paint_strokes(
	plugin: Object, root: Node, input_state: Variant, paint_tool: Variant
) -> bool:
	var finished := false
	if (
		paint_tool != null
		and paint_tool.has_method("is_stroke_active")
		and paint_tool.is_stroke_active()
		and paint_tool.has_method("finish_stroke_if_active")
	):
		paint_tool.finish_stroke_if_active()
		finished = true
	if input_state != null and input_state.is_surface_painting():
		input_state.end_surface_paint()
		finished = true
	if plugin._disp_paint_active:
		if not plugin._disp_paint_pre_state.is_empty():
			plugin._commit_disp_paint_undo(root)
		plugin._disp_paint_active = false
		plugin._disp_paint_brush_id = ""
		plugin._disp_paint_face_idx = -1
		plugin._disp_paint_pre_state = {}
		finished = true
	return finished


## Run before viewport motion is dispatched, so a gesture whose LMB release never
## arrived cannot keep consuming input for the rest of the session.
##
## Only DRAG_BASE is recovered, not DRAG_HEIGHT: height is driven by motion alone
## after the base is committed, so a held button is not what keeps it open.
static func recover_stale_lmb_gestures(plugin: Object, root: Node) -> void:
	if not root:
		return
	var recovered := false
	var input_state = root.input_state if root.get("input_state") != null else null
	var paint_tool = root.get("paint_tool")
	if plugin._tool_registry and plugin._tool_registry.recover_active_pointer_capture():
		recovered = true
	if finish_stale_paint_strokes(plugin, root, input_state, paint_tool):
		recovered = true
	if plugin._vertex_drag_active and root.vertex_system:
		root.vertex_system.cancel_drag()
		plugin._vertex_drag_active = false
		recovered = true
	if input_state:
		if input_state.is_extruding():
			root.cancel_extrude()
			recovered = true
		elif input_state.is_drag_base():
			root.cancel_drag()
			recovered = true
	if recovered:
		plugin.numeric_buffer = ""
		_clear_hover(root)
		plugin._update_hud_context()


## RMB during a HammerForge gesture cancels it. RMB at rest belongs to Godot's
## camera. Returns STOP when we consumed the press, PASS when Godot should have it.
static func handle_rmb_cancel(plugin: Object, root: Node, event: InputEventMouseButton) -> int:
	var input_state = root.input_state if root else null
	var has_marquee: bool = (
		plugin._selection_gesture != null and plugin._selection_gesture.is_active()
	)
	var paint_tool = root.get("paint_tool") if root else null
	var surface_painting: bool = input_state != null and input_state.is_surface_painting()
	var floor_painting: bool = (
		paint_tool != null
		and paint_tool.has_method("is_stroke_active")
		and paint_tool.is_stroke_active()
	)
	var any_painting: bool = surface_painting or floor_painting or plugin._disp_paint_active
	var lmb_held := event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0
	if plugin.should_block_rmb_during_paint_stroke(
		surface_painting, floor_painting, plugin._disp_paint_active, lmb_held
	):
		return STOP
	if any_painting:
		# If Godot lost the LMB release during a focus/viewport transition,
		# finalize that stale stroke instead of blocking every future RMB press.
		finish_stale_paint_strokes(plugin, root, input_state, paint_tool)
	if not plugin.has_cancelable_rmb_gesture(input_state, has_marquee):
		# Idle RMB belongs to Godot's native camera controls.
		_clear_hover(root)
		plugin._rmb_camera_navigation.begin()
		return PASS
	if input_state and input_state.is_extruding():
		root.cancel_extrude()
	elif input_state and input_state.is_dragging():
		root.cancel_drag()
	plugin.numeric_buffer = ""
	plugin._cancel_selection_gesture()
	plugin._update_hud_context()
	return STOP


## Hover highlights are drawn for a pointer that is no longer where it was, so
## every recovery path drops them.
static func _clear_hover(root: Node) -> void:
	if not root:
		return
	root.clear_hover()
	if root.has_method("clear_face_hover_highlight"):
		root.clear_face_hover_highlight()
