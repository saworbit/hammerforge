@tool
class_name HFPluginPaintInput
extends RefCounted
## Floor, surface, and displacement paint pointer handling extracted from plugin.gd.


static func should_start_displacement(plugin: Object, event: InputEvent, root: Node) -> bool:
	if not event is InputEventMouseButton or not event.pressed:
		return false
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not root or not root.displacement_system:
		return false
	if plugin == null or not plugin.dock or not plugin.dock._disp_section:
		return false
	if not plugin.dock.is_paint_mode_enabled() or not plugin.dock._disp_section.is_expanded():
		return false
	var info: Dictionary = plugin.dock._get_selected_face_info()
	if info.is_empty():
		return false
	var brush: Node3D = root.find_brush_by_id(info["brush_id"])
	if not brush or not _is_visible_pick(root, brush):
		return false
	var face_index: int = info["face_index"]
	return (
		face_index >= 0
		and face_index < brush.faces.size()
		and brush.faces[face_index].displacement != null
	)


static func handle_displacement(
	plugin: Object, event: InputEvent, root: Node, camera: Camera3D, position: Vector2
) -> int:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var info: Dictionary = plugin.dock._get_selected_face_info()
			if info.is_empty():
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			if root.has_method("capture_state"):
				plugin._disp_paint_pre_state = root.capture_state()
			plugin._disp_paint_active = true
			plugin._disp_paint_brush_id = info["brush_id"]
			plugin._disp_paint_face_idx = info["face_index"]
			do_displacement_stroke(plugin, root, camera, position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if plugin._disp_paint_active and not plugin._disp_paint_pre_state.is_empty():
			commit_displacement_undo(plugin, root)
		plugin._disp_paint_active = false
		plugin._disp_paint_brush_id = ""
		plugin._disp_paint_face_idx = -1
		plugin._disp_paint_pre_state = {}
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and plugin._disp_paint_active:
		do_displacement_stroke(plugin, root, camera, position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


static func commit_displacement_undo(plugin: Object, root: Node) -> void:
	if plugin == null or not plugin.undo_redo_manager or plugin._disp_paint_pre_state.is_empty():
		return
	if not root.has_method("restore_state") or not root.has_method("capture_state"):
		return
	var post_state: Dictionary = root.capture_state()
	plugin.undo_redo_manager.create_action("Paint Displacement", 0, null, false)
	plugin.undo_redo_manager.add_do_method(root, "restore_state", post_state)
	plugin.undo_redo_manager.add_undo_method(root, "restore_state", plugin._disp_paint_pre_state)
	plugin.undo_redo_manager.commit_action(false)
	plugin._record_history("Paint Displacement")


static func do_displacement_stroke(
	plugin: Object, root: Node, camera: Camera3D, position: Vector2
) -> void:
	if not root.displacement_system:
		return
	if plugin._disp_paint_brush_id == "" or plugin._disp_paint_face_idx < 0:
		return
	var brush: Node3D = root.find_brush_by_id(plugin._disp_paint_brush_id)
	if not brush or not _is_visible_pick(root, brush):
		return
	var faces: Array = brush.faces
	if plugin._disp_paint_face_idx >= faces.size():
		return
	var face = faces[plugin._disp_paint_face_idx]
	if face.local_verts.size() < 3:
		return
	var basis: Basis = brush.global_transform.basis
	var origin: Vector3 = brush.global_transform.origin
	var world_normal: Vector3 = (basis * face.normal).normalized()
	var world_vertices := PackedVector3Array()
	for local_vertex in face.local_verts:
		world_vertices.append(origin + basis * local_vertex)
	var ray_origin: Vector3 = camera.project_ray_origin(position)
	var ray_direction: Vector3 = camera.project_ray_normal(position)
	var denominator: float = world_normal.dot(ray_direction)
	if abs(denominator) < 0.0001:
		return
	var distance: float = world_normal.dot(world_vertices[0] - ray_origin) / denominator
	if distance < 0:
		return
	var hit_position: Vector3 = ray_origin + ray_direction * distance
	var radius: float = (
		plugin.dock._disp_radius_spin.value
		if plugin.dock and plugin.dock._disp_radius_spin
		else 4.0
	)
	if not point_near_polygon_3d(hit_position, world_vertices, world_normal, radius):
		return
	var strength: float = (
		plugin.dock._disp_strength_spin.value
		if plugin.dock and plugin.dock._disp_strength_spin
		else 0.5
	)
	var mode := 0
	if plugin.dock and plugin.dock._disp_paint_mode_opt:
		mode = plugin.dock._disp_paint_mode_opt.get_selected_id()
	root.displacement_system.paint(
		plugin._disp_paint_brush_id,
		plugin._disp_paint_face_idx,
		hit_position,
		radius,
		strength,
		mode
	)


static func point_near_polygon_3d(
	point: Vector3, vertices: PackedVector3Array, normal: Vector3, margin: float
) -> bool:
	var count := vertices.size()
	if count < 3:
		return false
	for index in range(count):
		var a: Vector3 = vertices[index]
		var b: Vector3 = vertices[(index + 1) % count]
		var inward: Vector3 = normal.cross(b - a).normalized()
		if inward.dot(point - a) < -margin:
			return false
	return true


static func handle_paint(
	plugin: Object, event: InputEvent, root: Node, camera: Camera3D, position: Vector2
) -> int:
	var paint_target = plugin.dock.get_paint_target()
	var operation = plugin.dock.get_operation()
	var size = plugin.dock.get_brush_size()
	if paint_target == 0:
		var floor_press: bool = (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		)
		var floor_release: bool = (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and not event.pressed
		)
		var eyedropper: bool = (
			floor_press and (event as InputEventMouseButton).is_command_or_control_pressed()
		)
		var paint_tool = root.get("paint_tool")
		var height_confirm: bool = (
			floor_press
			and paint_tool != null
			and paint_tool.has_method("is_height_gesture_active")
			and paint_tool.is_height_gesture_active()
		)
		if floor_press and not eyedropper and not height_confirm:
			# Region sidecars must be loaded before the pre-stroke snapshot, or Undo
			# would mistake their existing cells for paint created by this stroke.
			if root.has_method("prepare_paint_stroke"):
				root.prepare_paint_stroke(camera, position)
			begin_floor_paint_undo(plugin, root)
		var handled = (
			root
			. handle_paint_input(
				camera,
				event,
				position,
				operation,
				size,
				plugin.dock.get_paint_tool_id(),
				plugin.dock.get_paint_radius_cells(),
				plugin.dock.get_brush_shape(),
				{
					"inference_enabled": plugin.dock.get_paint_inference_enabled(),
					"mirror_x_enabled": plugin.dock.get_paint_mirror_x_enabled(),
					"mirror_z_enabled": plugin.dock.get_paint_mirror_z_enabled(),
				}
			)
		)
		plugin._update_hud_context()
		if plugin.has_method("_update_paint_overlay"):
			plugin._update_paint_overlay(root)
		if handled:
			if eyedropper and root.get("paint_tool"):
				plugin.dock.show_toast(
					"Picked floor material %d" % root.paint_tool.blend_material_id, 0
				)
			elif height_confirm:
				commit_floor_paint_undo(plugin, root, "Raise Paint Walls")
			elif floor_release:
				commit_floor_paint_undo(plugin, root)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if floor_press:
			plugin._floor_paint_pre_state = {}
			if root.has_signal("user_message"):
				root.user_message.emit("Floor Paint could not reach the active layer plane", 1)
			# Paint mode owns LMB even when the ray misses. Passing it onward can
			# accidentally start the build tool underneath the paint workflow.
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	elif paint_target == 1:
		var handled_surface = root.handle_surface_paint_input(
			camera,
			event,
			position,
			plugin.dock.get_surface_paint_radius(),
			plugin.dock.get_surface_paint_strength(),
			plugin.dock.get_surface_paint_layer()
		)
		if handled_surface:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


static func begin_floor_paint_undo(plugin: Object, root: Node) -> void:
	if plugin == null or not root or not plugin._floor_paint_pre_state.is_empty():
		return
	if root.has_method("capture_state"):
		plugin._floor_paint_pre_state = root.capture_state()


static func commit_floor_paint_undo(
	plugin: Object, root: Node, action_name: String = "Paint Floor"
) -> void:
	if plugin == null or not root or plugin._floor_paint_pre_state.is_empty():
		return
	var before: Dictionary = plugin._floor_paint_pre_state
	plugin._floor_paint_pre_state = {}
	_release_region_pins(root)
	var paint_tool = root.get("paint_tool")
	if (
		paint_tool == null
		or not paint_tool.has_method("get_last_committed_cell_count")
		or paint_tool.get_last_committed_cell_count() <= 0
	):
		return
	if not root.has_method("capture_state") or not root.has_method("restore_state"):
		return
	var after: Dictionary = root.capture_state()
	if plugin.undo_redo_manager:
		plugin.undo_redo_manager.create_action(action_name, 0, null, false)
		plugin.undo_redo_manager.add_do_method(root, "restore_state", after)
		plugin.undo_redo_manager.add_undo_method(root, "restore_state", before)
		plugin.undo_redo_manager.commit_action(false)
	plugin._record_history(action_name)


static func begin_floor_paint_raise(plugin: Object, root: Node, screen_y: float) -> bool:
	if plugin == null or not root:
		return false
	var paint_tool = root.get("paint_tool")
	if paint_tool == null or not paint_tool.has_method("begin_height_gesture"):
		return false
	begin_floor_paint_undo(plugin, root)
	if paint_tool.begin_height_gesture(screen_y):
		plugin._update_hud_context()
		if plugin.has_method("_update_paint_overlay"):
			plugin._update_paint_overlay(root)
		return true
	plugin._floor_paint_pre_state = {}
	return false


static func stamp_floor_paint_room(plugin: Object, root: Node) -> bool:
	if plugin == null or not root:
		return false
	var paint_tool = root.get("paint_tool")
	if paint_tool == null or not paint_tool.has_method("stamp_room_from_last_rect"):
		return false
	begin_floor_paint_undo(plugin, root)
	if paint_tool.stamp_room_from_last_rect() <= 0:
		plugin._floor_paint_pre_state = {}
		return false
	commit_floor_paint_undo(plugin, root, "Stamp Paint Room")
	plugin._update_hud_context()
	if plugin.has_method("_update_paint_overlay"):
		plugin._update_paint_overlay(root)
	return true


static func confirm_floor_paint_connector(plugin: Object, root: Node) -> bool:
	if plugin == null or not root:
		return false
	var paint_tool = root.get("paint_tool")
	if paint_tool == null or not paint_tool.has_method("confirm_connector_ghosts"):
		return false
	begin_floor_paint_undo(plugin, root)
	if paint_tool.confirm_connector_ghosts() <= 0:
		plugin._floor_paint_pre_state = {}
		return false
	commit_floor_paint_undo(plugin, root, "Confirm Paint Connector")
	plugin._update_hud_context()
	if plugin.has_method("_update_paint_overlay"):
		plugin._update_paint_overlay(root)
	return true


static func cancel_floor_paint(plugin: Object, root: Node) -> bool:
	if plugin == null or not root:
		return false
	var paint_tool = root.get("paint_tool")
	if paint_tool == null:
		return false
	var stroke_active: bool = (
		paint_tool.has_method("is_stroke_active") and paint_tool.is_stroke_active()
	)
	var pending_active: bool = (
		paint_tool.has_method("is_height_gesture_active") and paint_tool.is_height_gesture_active()
	)
	if not stroke_active and paint_tool.has_method("cancel_pending_action"):
		pending_active = paint_tool.cancel_pending_action() or pending_active
	if not stroke_active and not pending_active:
		return false
	if stroke_active and paint_tool.has_method("cancel_stroke"):
		paint_tool.cancel_stroke()
	if not plugin._floor_paint_pre_state.is_empty() and root.has_method("restore_state"):
		root.restore_state(plugin._floor_paint_pre_state)
	plugin._floor_paint_pre_state = {}
	_release_region_pins(root)
	plugin._update_hud_context()
	if plugin.has_method("_update_paint_overlay"):
		plugin._update_paint_overlay(root)
	return true


static func _release_region_pins(root: Node) -> void:
	var paint_system = root.get("paint_system")
	if paint_system != null and paint_system.has_method("release_paint_region_pins"):
		paint_system.release_paint_region_pins()


static func _is_visible_pick(root: Node, brush: Node3D) -> bool:
	if root.has_method("_is_pick_visible") and not root._is_pick_visible(brush):
		return false
	return not (
		brush.get("mesh_instance") is Node3D
		and root.has_method("_is_pick_visible")
		and not root._is_pick_visible(brush.get("mesh_instance"))
	)
