@tool
class_name HFPluginPointerTools
extends RefCounted
## Draw, extrude, hover, and prefab pointer handling extracted from plugin.gd.


static func handle_extrude(
	plugin: Object, event: InputEventMouseButton, root: Node, camera: Camera3D, position: Vector2
) -> int:
	if event.pressed:
		plugin.numeric_buffer = ""
		var started = root.begin_extrude(camera, position, plugin.dock.get_extrude_direction())
		return EditorPlugin.AFTER_GUI_INPUT_STOP if started else EditorPlugin.AFTER_GUI_INPUT_PASS
	var info = root.end_extrude_info()
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
	if root.prefab_overlay and event.button_mask == 0 and camera:
		update_prefab_hover(root, camera, position)
	plugin._update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


static func update_prefab_hover(root: Node, camera: Camera3D, position: Vector2) -> void:
	var ray_origin: Vector3 = camera.project_ray_origin(position)
	var ray_direction: Vector3 = camera.project_ray_normal(position)
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	if not space:
		root.prefab_overlay.hide_overlay()
		return
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000.0)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		root.prefab_overlay.hide_overlay()
		return
	var collider = hit.get("collider")
	if not collider or not collider is Node3D:
		root.prefab_overlay.hide_overlay()
		return
	var node: Node = collider
	var instance_id := ""
	while node and node != root:
		instance_id = str(node.get_meta("hf_prefab_instance", ""))
		if not instance_id.is_empty():
			break
		node = node.get_parent()
	if instance_id.is_empty():
		root.prefab_overlay.hide_overlay()
	else:
		root.prefab_overlay.show_instance_overlay(instance_id)
