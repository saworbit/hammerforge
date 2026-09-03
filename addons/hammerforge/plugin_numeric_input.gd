class_name HFPluginNumericInput
extends RefCounted
## Owns numeric dimension entry for active draw and extrude gestures.

const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP


static func handle(plugin: Object, event: InputEventKey, root: Node) -> int:
	if plugin == null or event == null or root == null or root.input_state == null:
		return PASS
	if not root.input_state.is_dragging() and not root.input_state.is_extruding():
		return PASS

	var keycode := event.keycode
	if keycode >= KEY_0 and keycode <= KEY_9:
		plugin.numeric_buffer += str(keycode - KEY_0)
		update_preview(plugin, root)
		return STOP

	if keycode == KEY_PERIOD and "." not in plugin.numeric_buffer:
		plugin.numeric_buffer += "."
		update_preview(plugin, root)
		return STOP

	if keycode == KEY_BACKSPACE and plugin.numeric_buffer.length() > 0:
		plugin.numeric_buffer = plugin.numeric_buffer.substr(0, plugin.numeric_buffer.length() - 1)
		update_preview(plugin, root)
		return STOP

	if keycode in [KEY_ENTER, KEY_KP_ENTER] and plugin.numeric_buffer.length() > 0:
		apply_value(plugin, root)
		return STOP

	if keycode == KEY_TAB and plugin.numeric_buffer.length() > 0:
		apply_value(plugin, root)
		return STOP

	return PASS


static func update_preview(plugin: Object, root: Node) -> void:
	if plugin == null or root == null or root.input_state == null:
		return
	if not root.input_state.is_dragging() and not root.input_state.is_extruding():
		return
	if plugin.numeric_buffer.length() == 0:
		return
	var value := float(plugin.numeric_buffer) if plugin.numeric_buffer.is_valid_float() else 0.0
	if value <= 0.0:
		return
	if root.input_state.is_drag_height() or root.input_state.is_extruding():
		root.input_state.drag_height = value
		root.update_drag(plugin.last_3d_camera, plugin.last_3d_mouse_pos)
	elif root.input_state.is_drag_base():
		var extent := Vector3(value, 0.0, value)
		root.input_state.drag_end = root.input_state.drag_origin + extent
		root.update_drag(plugin.last_3d_camera, plugin.last_3d_mouse_pos)
	plugin._update_hud_context()


static func apply_value(plugin: Object, root: Node) -> void:
	if plugin == null or root == null or root.input_state == null:
		return
	if plugin.numeric_buffer.length() == 0:
		return
	var value := float(plugin.numeric_buffer) if plugin.numeric_buffer.is_valid_float() else 0.0
	plugin.numeric_buffer = ""
	if value <= 0.0:
		return
	if root.input_state.is_drag_height():
		root.input_state.drag_height = value
		var size = plugin.dock.get_brush_size()
		var info_result = root.end_drag_info(plugin.last_3d_camera, plugin.last_3d_mouse_pos, size)
		if info_result.get("placed", false):
			plugin._commit_brush_placement(root, info_result.get("info", {}))
		plugin._update_hud_context()
	elif root.input_state.is_drag_base():
		var extent := Vector3(value, 0.0, value)
		root.input_state.drag_end = root.input_state.drag_origin + extent
		root.input_state.advance_to_height(plugin.last_3d_mouse_pos)
		root.update_drag(plugin.last_3d_camera, plugin.last_3d_mouse_pos)
		plugin._update_hud_context()
	elif root.input_state.is_extruding():
		root.input_state.drag_height = value
		var info = root.end_extrude_info()
		if not info.is_empty():
			plugin._commit_brush_placement(root, info)
		plugin._update_hud_context()
