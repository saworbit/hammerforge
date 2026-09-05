@tool
class_name HFPluginToolModes
extends RefCounted
## Which tool or mode owns the viewport, and what has to be closed to hand it over.
##
## Draw, Select, the extrude tools, the external tools, vertex edit, Face Select
## and paint mode are mutually exclusive owners of the pointer. Every switch
## between them runs the same errand first: settle whatever gesture is mid-flight
## so nothing is left half-dragged behind the new owner. That errand is
## prepare_transition(), and the rest of this module is the handful of entry
## points that call it.

const EXTRUDE_TOOL_UP := 2
const EXTRUDE_TOOL_DOWN := 3


## The active level, or the one discovery can find. Every entry point here needs
## it and none of them can create one.
static func _root(plugin: Object) -> Node:
	return plugin.active_root if plugin.active_root else plugin._get_level_root()


## Settle any in-progress gesture before another owner takes the pointer.
##
## `notify_user` is off for transitions the user did not ask for, such as the one
## behind a selection change. `settle_custom_gizmo` is off when Godot is already
## unwinding its own handle drag and a second cancel would fight it.
static func prepare_transition(
	plugin: Object, root: Node, notify_user: bool = true, settle_custom_gizmo: bool = true
) -> void:
	var cancelled := false
	if (
		settle_custom_gizmo
		and plugin._brush_gizmo_action_active()
		and plugin.brush_gizmo_plugin.has_method("cancel_active_handle_action")
	):
		# Restore and freeze locally; keep yielding until Godot delivers the
		# matching commit/cancel callback and releases its private gizmo owner.
		plugin.brush_gizmo_plugin.call("cancel_active_handle_action")
		cancelled = true
	if not root or not root.input_state:
		if cancelled and notify_user and plugin.dock:
			plugin.dock.show_toast("In-progress brush resize closed for tool switch", 1)
		return
	var paint_tool = root.get("paint_tool")
	if plugin._finish_stale_paint_strokes(root, root.input_state, paint_tool):
		cancelled = true
	if plugin._vertex_drag_active and root.vertex_system:
		root.vertex_system.cancel_drag()
		plugin._vertex_drag_active = false
		cancelled = true
	if root.input_state.is_extruding():
		root.cancel_extrude()
		cancelled = true
	elif root.input_state.is_dragging():
		root.cancel_drag()
		cancelled = true
	if plugin._cancel_selection_gesture():
		cancelled = true
	if cancelled:
		plugin.numeric_buffer = ""
		if notify_user and plugin.dock:
			plugin.dock.show_toast("In-progress gesture closed for tool switch", 1)


# ---------------------------------------------------------------------------
# External tools
# ---------------------------------------------------------------------------


static func deactivate_external(plugin: Object) -> void:
	if plugin._tool_registry and plugin._tool_registry.has_active_external_tool():
		plugin._tool_registry.deactivate_current()


static func activate_external(plugin: Object, tool_id: int, root: Node) -> void:
	if not plugin._tool_registry or not root:
		return
	close_face_select(plugin, "Face Select closed for tool change")
	prepare_transition(plugin, root)
	if plugin._vertex_mode:
		plugin._toggle_vertex_mode(root)
	if plugin.dock and plugin.dock.paint_mode and plugin.dock.paint_mode.button_pressed:
		plugin.dock.paint_mode.set_pressed_no_signal(false)
		plugin.dock.highlight_tab("Brush")
	plugin._tool_registry.activate_tool(
		tool_id, root, plugin.last_3d_camera, plugin.undo_redo_manager, plugin._record_history
	)


# ---------------------------------------------------------------------------
# Built-in tools
# ---------------------------------------------------------------------------


static func on_builtin_tool_changed(plugin: Object) -> void:
	close_face_select(plugin, "Face Select closed for tool change")
	var root := _root(plugin)
	prepare_transition(plugin, root)
	deactivate_external(plugin)
	if plugin._vertex_mode:
		plugin._toggle_vertex_mode(root)
	# Show coach marks for extrude tools on first use
	if plugin.dock:
		var tool_id: int = plugin.dock.get_tool()
		if tool_id == EXTRUDE_TOOL_UP or tool_id == EXTRUDE_TOOL_DOWN:
			plugin._show_coach_mark_for_action("tool_extrude_up")
	plugin._update_hud_context()


## Switch tools from the viewport context toolbar, which has its own buttons and
## so has to drive the dock's rather than being driven by them.
static func switch_to_tool(plugin: Object, tool_id: int) -> void:
	prepare_transition(plugin, _root(plugin))
	if plugin.dock:
		plugin.dock.highlight_tab("Brush")
	deactivate_external(plugin)
	if plugin.dock:
		match tool_id:
			0:
				plugin.dock.tool_draw.button_pressed = true
			1:
				plugin.dock.tool_select.button_pressed = true
			EXTRUDE_TOOL_UP:
				plugin.dock.set_extrude_tool(1)
			EXTRUDE_TOOL_DOWN:
				plugin.dock.set_extrude_tool(-1)
	plugin._update_hud_context()


# ---------------------------------------------------------------------------
# Vertex edit and paint mode
# ---------------------------------------------------------------------------


static func on_vertex_mode_toggled(plugin: Object, enabled: bool) -> void:
	# The dock button can re-report a state we are already in, so only act on a
	# real change. _toggle_vertex_mode flips, it does not set.
	if enabled != plugin._vertex_mode:
		plugin._toggle_vertex_mode(_root(plugin))


static func toggle_paint_mode(plugin: Object) -> void:
	if not plugin.dock or not plugin.dock.paint_mode:
		return
	prepare_transition(plugin, _root(plugin))
	plugin.dock.paint_mode.button_pressed = not plugin.dock.paint_mode.button_pressed
	plugin.dock.show_toast(
		"Paint mode enabled" if plugin.dock.paint_mode.button_pressed else "Build mode enabled", 0
	)
	plugin._update_hud_context()


# ---------------------------------------------------------------------------
# Face Select
# ---------------------------------------------------------------------------


static func on_face_select_mode_toggled(plugin: Object, enabled: bool) -> void:
	plugin._ensure_selection_runtime_state()
	var root := _root(plugin)
	prepare_transition(plugin, root)
	var selection = plugin.get_editor_interface().get_selection()
	if enabled:
		# Establish one unambiguous pointer owner before hiding object selection.
		# Keep the Paint tab visible, but turn painting itself off; Face Select is
		# an editing mode, not a paint stroke layered over Select.
		deactivate_external(plugin)
		if plugin._vertex_mode:
			plugin._toggle_vertex_mode(root)
		plugin._texture_picker_active = false
		if plugin._radial_menu and plugin._radial_menu.is_active():
			plugin._radial_menu.hide_menu()
		if plugin.dock:
			if plugin.dock.tool_select:
				plugin.dock.tool_select.set_pressed_no_signal(true)
			if plugin.dock.paint_mode:
				plugin.dock.paint_mode.set_pressed_no_signal(false)
		plugin._face_mode_saved_object_selection.clear()
		for node in plugin._current_selection_nodes():
			if is_instance_valid(node) and node is Node:
				plugin._face_mode_saved_object_selection.append(node)
		# Face editing is intentionally modal. Hiding object gizmos removes the
		# otherwise-opaque zero-motion overlap between a face and transform handle.
		plugin.hf_selection.clear()
		if selection:
			plugin._apply_hf_selection(selection)
		if plugin.dock:
			plugin.dock.show_toast("Face Select: object transform handles hidden", 0)
		return
	if root and root.has_method("clear_face_selection"):
		root.clear_face_selection()
	if selection:
		plugin.hf_selection.clear()
		for node in plugin._face_mode_saved_object_selection:
			if is_instance_valid(node) and node is Node:
				plugin.hf_selection.append(node)
		plugin._apply_hf_selection(selection)
	plugin._face_mode_saved_object_selection.clear()


## Leave Face Select from somewhere other than its own button. Returns true when
## the mode was open, which callers use to decide whether they have already
## consumed the user's Escape or tool change.
static func close_face_select(plugin: Object, message: String = "") -> bool:
	var dock = plugin.dock
	if not dock or not dock.is_face_select_mode_enabled() or not dock.face_select_mode:
		return false
	# Use the real toggle signal so face selection is cleared and the saved
	# object selection is restored through the same path as a manual exit.
	dock.face_select_mode.button_pressed = false
	if message != "":
		dock.show_toast(message, 0)
	return true
