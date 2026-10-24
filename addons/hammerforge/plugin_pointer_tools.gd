@tool
class_name HFPluginPointerTools
extends RefCounted
## Draw, extrude, and face hover pointer handling extracted from plugin.gd.

const HFOverlayColors = preload("hf_overlay_colors.gd")


static func handle_extrude(
	plugin: Object, event: InputEventMouseButton, root: Node, camera: Camera3D, position: Vector2
) -> int:
	if event.pressed:
		plugin.numeric_buffer = ""
		var started = root.begin_extrude(camera, position, plugin.dock.get_extrude_direction())
		return EditorPlugin.AFTER_GUI_INPUT_STOP if started else EditorPlugin.AFTER_GUI_INPUT_PASS
	var info = root.end_extrude_info()
	# The release ends the extrusion, at a typed depth if one was standing, so a
	# number left in the buffer has been used.
	plugin.numeric_buffer = ""
	if not info.is_empty():
		plugin._commit_brush_placement(root, info)
	plugin._update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


static func handle_draw(
	plugin: Object, event: InputEventMouseButton, root: Node, camera: Camera3D, position: Vector2
) -> int:
	var size = plugin.dock.get_brush_size()
	if event.pressed:
		if root.input_state.is_drag_height():
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		plugin.numeric_buffer = ""
		var started = root.begin_drag(
			camera,
			position,
			plugin.dock.get_operation(),
			size,
			plugin.dock.get_shape(),
			plugin.dock.get_sides(),
			plugin.dock.is_draw_on_face_enabled()
		)
		if started:
			clear_draw_hover(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if started else EditorPlugin.AFTER_GUI_INPUT_PASS
	var result = root.end_drag_info(camera, position, size)
	if result.get("handled", false):
		if result.get("placed", false):
			plugin._commit_brush_placement(root, result.get("info", {}))
		# The banner and the size beside the cursor move on with the drag: to the
		# height stage, or away once the brush is placed.
		plugin._update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


static func handle_motion(
	plugin: Object,
	event: InputEventMouseMotion,
	root: Node,
	camera: Camera3D,
	position: Vector2,
	tool_id: int
) -> int:
	if tool_id != 1:
		root.set_shift_pressed(event.shift_pressed)
		root.set_alt_pressed(event.alt_pressed)
	if tool_id in [2, 3] and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		root.update_extrude(camera, position)
		plugin._update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if (
		tool_id == 0
		and (
			root.input_state.is_drag_height()
			or (root.input_state.is_drag_base() and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0)
		)
	):
		root.update_drag(camera, position)
		plugin._update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if tool_id in [2, 3] and event.button_mask == 0:
		var hover_color := HFOverlayColors.get_color(
			HFOverlayColors.EXTRUDE_UP if tool_id == 2 else HFOverlayColors.EXTRUDE_DOWN
		)
		if root.has_method("highlight_hovered_face"):
			root.highlight_hovered_face(camera, position, hover_color)
	elif root.has_method("clear_face_hover_highlight"):
		root.clear_face_hover_highlight()
	if tool_id == 0:
		follow_draw_hover(plugin, root, camera, position)
	plugin._update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


# ---------------------------------------------------------------------------
# Draw hover preview (#1400)
# ---------------------------------------------------------------------------


## Whether the preview of where a draw lands belongs on screen: the switch is
## on, and Draw is idle, or Polygon or Path wait for their first point. Paint,
## vertex mode and Face Select own the pointer, so it has no place in them.
static func draw_hover_wanted(plugin: Object, root: Node) -> bool:
	if plugin == null or root == null or not is_instance_valid(root):
		return false
	if root.get("draw_hover") == null or root.get("input_state") == null:
		return false
	var prefs = plugin.get("_user_prefs")
	if prefs != null and not bool(prefs.get_pref("draw_hover_preview", true)):
		return false
	var dock = plugin.get("dock")
	if dock == null or plugin.get("_vertex_mode"):
		return false
	if dock.is_face_select_mode_enabled() or dock.is_paint_mode_enabled():
		return false
	var tool = _active_external_tool(plugin)
	if tool != null:
		return tool.has_method("shows_draw_hover") and bool(tool.shows_draw_hover())
	return dock.get_tool() == 0 and root.input_state.is_idle()


## Follow the pointer with the preview, or take it down where it no longer
## belongs. The face pick runs only when the pointer or the view has moved since
## the last one.
static func follow_draw_hover(
	plugin: Object, root: Node, camera: Camera3D, position: Vector2
) -> void:
	if not draw_hover_wanted(plugin, root):
		clear_draw_hover(root)
		return
	if camera == null or not is_instance_valid(camera):
		return
	var tool = _active_external_tool(plugin)
	var on_face: bool = tool == null and plugin.dock.is_draw_on_face_enabled()
	var view_key := [
		position,
		camera.global_transform,
		camera.size,
		on_face,
		tool.get_instance_id() if tool != null else 0,
		# A Tab step or a one-pick limit changes the snap with nothing moved.
		root.snap_system.revision if root.get("snap_system") else 0,
	]
	if root.draw_hover.is_current(view_key):
		return
	var start := {}
	if tool != null:
		var first: Dictionary = tool.first_point_start(camera, position)
		if not first.is_empty():
			start = root.drag_system.describe_start(first["hit"], first["point"])
	else:
		start = root.drag_system.draw_start(camera, position, on_face)
	root.draw_hover.show_start(start, view_key)


static func clear_draw_hover(root: Node) -> void:
	if root != null and is_instance_valid(root) and root.get("draw_hover") != null:
		root.draw_hover.clear()


static func _active_external_tool(plugin: Object) -> Object:
	var registry = plugin.get("_tool_registry")
	if registry and registry.has_active_external_tool():
		return registry.get_active_tool()
	return null
