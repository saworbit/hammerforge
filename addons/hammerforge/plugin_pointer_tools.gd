@tool
class_name HFPluginPointerTools
extends RefCounted
## Draw, extrude, and face hover pointer handling extracted from plugin.gd.


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
			plugin.dock.get_sides()
		)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if started else EditorPlugin.AFTER_GUI_INPUT_PASS
	var result = root.end_drag_info(camera, position, size)
	if result.get("handled", false):
		if result.get("placed", false):
			plugin._commit_brush_placement(root, result.get("info", {}))
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
		var hover_color = Color(0.2, 0.8, 0.3, 0.35) if tool_id == 2 else Color(0.8, 0.2, 0.2, 0.35)
		if root.has_method("highlight_hovered_face"):
			root.highlight_hovered_face(camera, position, hover_color)
	elif root.has_method("clear_face_hover_highlight"):
		root.clear_face_hover_highlight()
	plugin._update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_PASS
