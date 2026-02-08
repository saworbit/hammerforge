@tool
extends EditorPlugin

const DockType = preload("dock.gd")
var dock: DockType
var hud: Control
var base_control: Control
var active_root: LevelRoot = null
var undo_redo_manager: EditorUndoRedoManager = null
var brush_gizmo_plugin: EditorNode3DGizmoPlugin = null
var hf_selection: Array = []
var select_drag_origin := Vector2.ZERO
var select_drag_active := false
var select_dragging := false
var select_additive := false
var select_drag_threshold := 6.0
var last_3d_camera: Camera3D = null
var last_3d_mouse_pos := Vector2.ZERO
const LevelRootType = preload("level_root.gd")
const DraftEntityType = preload("draft_entity.gd")
const IconRes = preload("icon.png")


func _enter_tree():
	add_custom_type("LevelRoot", "Node3D", LevelRootType, IconRes)
	add_custom_type("DraftEntity", "Node3D", DraftEntityType, IconRes)
	dock = preload("dock.tscn").instantiate()
	undo_redo_manager = get_undo_redo()
	brush_gizmo_plugin = preload("brush_gizmo_plugin.gd").new()
	if brush_gizmo_plugin and brush_gizmo_plugin.has_method("set_undo_redo"):
		brush_gizmo_plugin.call("set_undo_redo", undo_redo_manager)
	if brush_gizmo_plugin:
		add_node_3d_gizmo_plugin(brush_gizmo_plugin)
	base_control = get_editor_interface().get_base_control()
	if base_control:
		dock.theme = base_control.theme
		if dock:
			dock.apply_editor_styles(base_control)
		if not base_control.is_connected(
			"theme_changed", Callable(self, "_on_editor_theme_changed")
		):
			base_control.connect("theme_changed", Callable(self, "_on_editor_theme_changed"))
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
	if dock:
		dock.set_editor_interface(get_editor_interface())
	if dock:
		dock.set_undo_redo(undo_redo_manager)
	if dock and dock.has_signal("hud_visibility_changed"):
		dock.connect("hud_visibility_changed", Callable(self, "_on_hud_visibility_changed"))

	hud = preload("shortcut_hud.tscn").instantiate()
	if base_control:
		hud.theme = base_control.theme
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, hud)
	if dock:
		hud.visible = dock.get_show_hud()
	var selection = get_editor_interface().get_selection()
	if selection:
		if not selection.is_connected(
			"selection_changed", Callable(self, "_on_editor_selection_changed")
		):
			selection.connect("selection_changed", Callable(self, "_on_editor_selection_changed"))
		hf_selection = selection.get_selected_nodes()
	set_process(false)


func _exit_tree():
	remove_custom_type("LevelRoot")
	remove_custom_type("DraftEntity")
	undo_redo_manager = null
	if brush_gizmo_plugin:
		remove_node_3d_gizmo_plugin(brush_gizmo_plugin)
		brush_gizmo_plugin = null
	if (
		base_control
		and base_control.is_connected("theme_changed", Callable(self, "_on_editor_theme_changed"))
	):
		base_control.disconnect("theme_changed", Callable(self, "_on_editor_theme_changed"))
	if dock:
		if dock.is_connected(
			"hud_visibility_changed", Callable(self, "_on_hud_visibility_changed")
		):
			dock.disconnect("hud_visibility_changed", Callable(self, "_on_hud_visibility_changed"))
		remove_control_from_docks(dock)
		if is_instance_valid(dock):
			dock.queue_free()
		dock = null
	if hud:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, hud)
		if is_instance_valid(hud):
			hud.queue_free()
		hud = null
	var selection = get_editor_interface().get_selection()
	if (
		selection
		and selection.is_connected(
			"selection_changed", Callable(self, "_on_editor_selection_changed")
		)
	):
		selection.disconnect("selection_changed", Callable(self, "_on_editor_selection_changed"))
	set_process(false)


func _on_editor_theme_changed() -> void:
	if not base_control:
		return
	if dock:
		dock.theme = base_control.theme
		dock.apply_editor_styles(base_control)
	if hud:
		hud.theme = base_control.theme


func _on_hud_visibility_changed(visible: bool) -> void:
	if hud:
		hud.visible = visible


func _update_hud_context() -> void:
	if not hud or not hud.has_method("update_context"):
		return
	var ctx := {}
	ctx["tool"] = dock.get_tool() if dock else 0
	ctx["paint_mode"] = dock.is_paint_mode_enabled() if dock else false
	ctx["paint_target"] = dock.get_paint_target() if dock else 0
	ctx["mode"] = 0
	ctx["axis_lock"] = 0
	var root = active_root if active_root else _get_level_root()
	if root and root.input_state:
		ctx["mode"] = root.input_state.mode
		ctx["axis_lock"] = root.input_state.axis_lock
	hud.update_context(ctx)


func _on_editor_selection_changed() -> void:
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	hf_selection = selection.get_selected_nodes()
	if dock:
		dock.set_selection_count(hf_selection.size())


func _handles(object: Object) -> bool:
	if not object or not (object is Node):
		return false
	return _get_level_root_from_node(object as Node) != null


func _edit(object: Object) -> void:
	if object and object is Node:
		var root = _get_level_root_from_node(object as Node)
		if root:
			active_root = root
			return
	active_root = null


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var root = active_root if active_root else _get_level_root()
	if not root:
		root = _create_level_root()
	if not root or not dock:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if camera:
		last_3d_camera = camera
	if event is InputEventMouse:
		last_3d_mouse_pos = event.position

	var target_camera = camera
	var target_pos = event.position if event is InputEventMouse else Vector2.ZERO

	if root:
		if event is InputEventMouseMotion or event is InputEventMouseButton:
			root.update_editor_grid(target_camera, target_pos)

	var tool = dock.get_tool()
	var op = dock.get_operation()
	var size = dock.get_brush_size()
	var shape = dock.get_shape()
	var sides = dock.get_sides() if dock else 4
	var grid = dock.get_grid_snap()
	root.grid_snap = grid
	var paint_mode = dock != null and dock.is_paint_mode_enabled()
	var paint_target = dock.get_paint_target() if dock else 0

	if paint_mode:
		if paint_target == 0 and root:
			var paint_tool_id = dock.get_paint_tool_id() if dock else 0
			var paint_radius_cells = dock.get_paint_radius_cells() if dock else 1
			var paint_brush_shape = dock.get_brush_shape() if dock else 1
			var handled = root.handle_paint_input(
				target_camera,
				event,
				target_pos,
				op,
				size,
				paint_tool_id,
				paint_radius_cells,
				paint_brush_shape
			)
			if handled:
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		elif paint_target == 1 and root:
			var radius_uv = dock.get_surface_paint_radius() if dock else 0.1
			var strength = dock.get_surface_paint_strength() if dock else 1.0
			var layer_idx = dock.get_surface_paint_layer() if dock else 0
			var handled_surface = root.handle_surface_paint_input(
				target_camera, event, target_pos, radius_uv, strength, layer_idx
			)
			if handled_surface:
				return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_DELETE:
				var deleted = _delete_selected(root)
				return (
					EditorPlugin.AFTER_GUI_INPUT_STOP
					if deleted
					else EditorPlugin.AFTER_GUI_INPUT_PASS
				)
			if event.ctrl_pressed and event.keycode == KEY_D:
				_duplicate_selected(root)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.keycode == KEY_UP:
				_nudge_selected(root, Vector3(0.0, 0.0, -1.0))
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.keycode == KEY_DOWN:
				_nudge_selected(root, Vector3(0.0, 0.0, 1.0))
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.keycode == KEY_LEFT:
				_nudge_selected(root, Vector3(-1.0, 0.0, 0.0))
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.keycode == KEY_RIGHT:
				_nudge_selected(root, Vector3(1.0, 0.0, 0.0))
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.keycode == KEY_PAGEUP:
				_nudge_selected(root, Vector3(0.0, 1.0, 0.0))
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.keycode == KEY_PAGEDOWN:
				_nudge_selected(root, Vector3(0.0, -1.0, 0.0))
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.keycode == KEY_U:
				dock.set_extrude_tool(1)
				_update_hud_context()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.keycode == KEY_J:
				dock.set_extrude_tool(-1)
				_update_hud_context()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if paint_mode:
				var paint_key := -1
				match event.keycode:
					KEY_B:
						paint_key = 0
					KEY_E:
						paint_key = 1
					KEY_R:
						paint_key = 2
					KEY_L:
						paint_key = 3
					KEY_K:
						paint_key = 4
				if paint_key >= 0:
					dock.set_paint_tool(paint_key)
					return EditorPlugin.AFTER_GUI_INPUT_STOP
			if tool != 1:
				if event.keycode == KEY_X:
					root.set_axis_lock(LevelRootType.AxisLock.X, true)
					_update_hud_context()
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if event.keycode == KEY_Y:
					root.set_axis_lock(LevelRootType.AxisLock.Y, true)
					_update_hud_context()
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if event.keycode == KEY_Z:
					root.set_axis_lock(LevelRootType.AxisLock.Z, true)
					_update_hud_context()
					return EditorPlugin.AFTER_GUI_INPUT_STOP

	if tool == 1 and event is InputEventMouseMotion:
		if root:
			root.update_hover(target_camera, target_pos)
	elif tool != 1 and root:
		root.clear_hover()

	if event is InputEventMouseButton:
		if tool != 1:
			root.set_shift_pressed(event.shift_pressed)
			root.set_alt_pressed(event.alt_pressed)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if tool == 2 or tool == 3:
				root.cancel_extrude()
			else:
				root.cancel_drag()
			select_drag_active = false
			select_dragging = false
			_update_hud_context()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	var face_select = dock != null and dock.is_face_select_mode_enabled()
	if tool == 1:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if face_select and root:
					var additive_face = (
						event.shift_pressed
						or event.ctrl_pressed
						or event.meta_pressed
						or Input.is_key_pressed(KEY_SHIFT)
						or Input.is_key_pressed(KEY_CTRL)
						or Input.is_key_pressed(KEY_META)
					)
					var face_handled = root.select_face_at_screen(
						target_camera, target_pos, additive_face
					)
					return (
						EditorPlugin.AFTER_GUI_INPUT_STOP
						if face_handled
						else EditorPlugin.AFTER_GUI_INPUT_PASS
					)
				var active_mat = dock.get_active_material() if dock else null
				if paint_mode and active_mat:
					var painted = root.pick_brush(target_camera, target_pos, false)
					if painted:
						_paint_brush_with_undo(root, painted, active_mat)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
				select_drag_origin = target_pos
				select_drag_active = true
				select_dragging = false
				select_additive = (
					event.shift_pressed
					or event.ctrl_pressed
					or event.meta_pressed
					or Input.is_key_pressed(KEY_SHIFT)
					or Input.is_key_pressed(KEY_CTRL)
					or Input.is_key_pressed(KEY_META)
				)
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			var selection_action := false
			if select_drag_active:
				if select_dragging:
					selection_action = false
				else:
					if not face_select:
						var picked = root.pick_brush(target_camera, target_pos)
						_select_node(picked, select_additive)
						selection_action = true
			select_drag_active = false
			select_dragging = false
			return (
				EditorPlugin.AFTER_GUI_INPUT_STOP
				if selection_action
				else EditorPlugin.AFTER_GUI_INPUT_PASS
			)
	elif tool == 2 or tool == 3:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var extrude_dir = dock.get_extrude_direction()
				var started = root.begin_extrude(target_camera, target_pos, extrude_dir)
				return (
					EditorPlugin.AFTER_GUI_INPUT_STOP
					if started
					else EditorPlugin.AFTER_GUI_INPUT_PASS
				)
			var info = root.end_extrude_info()
			if not info.is_empty():
				_commit_brush_placement(root, info)
			_update_hud_context()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	else:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var started = root.begin_drag(target_camera, target_pos, op, size, shape, sides)
				return (
					EditorPlugin.AFTER_GUI_INPUT_STOP
					if started
					else EditorPlugin.AFTER_GUI_INPUT_PASS
				)
			var result = root.end_drag_info(target_camera, target_pos, size)
			if result.get("handled", false):
				if result.get("placed", false):
					_commit_brush_placement(root, result.get("info", {}))
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		if tool != 1:
			root.set_shift_pressed(event.shift_pressed)
			root.set_alt_pressed(event.alt_pressed)
		if (
			tool == 1
			and select_drag_active
			and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0
			and not face_select
		):
			if (
				not select_dragging
				and select_drag_origin.distance_to(target_pos) >= select_drag_threshold
			):
				select_dragging = true
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if (tool == 2 or tool == 3) and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
			root.update_extrude(target_camera, target_pos)
			_update_hud_context()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if tool == 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
			root.update_drag(target_camera, target_pos)
			_update_hud_context()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	_update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if select_drag_active:
			select_drag_active = false
			select_dragging = false
		var selection = get_editor_interface().get_selection()
		if selection:
			selection.clear()
		hf_selection.clear()
		if dock:
			dock.set_selection_count(0)
		_update_hud_context()
		event.accept()
		return
	if not event.ctrl_pressed:
		return
	var root = active_root if active_root else _get_level_root()
	if not root:
		return
	match event.keycode:
		KEY_UP:
			_nudge_selected(root, Vector3(0.0, 0.0, -1.0))
			event.accept()
		KEY_DOWN:
			_nudge_selected(root, Vector3(0.0, 0.0, 1.0))
			event.accept()
		KEY_LEFT:
			_nudge_selected(root, Vector3(-1.0, 0.0, 0.0))
			event.accept()
		KEY_RIGHT:
			_nudge_selected(root, Vector3(1.0, 0.0, 0.0))
			event.accept()
		KEY_PAGEUP:
			_nudge_selected(root, Vector3(0.0, 1.0, 0.0))
			event.accept()
		KEY_PAGEDOWN:
			_nudge_selected(root, Vector3(0.0, -1.0, 0.0))
			event.accept()


func _select_node(node: Node, additive: bool = false) -> void:
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	var toggle = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	if not additive:
		hf_selection.clear()
		if node:
			hf_selection.append(node)
	else:
		_sync_hf_selection_if_empty()
		if node:
			if toggle and hf_selection.has(node):
				hf_selection.erase(node)
			elif not hf_selection.has(node):
				hf_selection.append(node)
	if not additive and node == null:
		hf_selection.clear()
	_apply_hf_selection(selection)


func _select_nodes_in_rect(
	root: Node, camera: Camera3D, from: Vector2, to: Vector2, additive: bool
) -> void:
	if not root or not camera:
		return
	var rect = Rect2(from, to - from).abs()
	var nodes: Array = []
	if root:
		nodes = root._iter_pick_nodes()
	var picked: Array = []
	for node in nodes:
		if not (node is Node3D):
			continue
		if root and root.is_brush_node(node):
			pass
		elif root and root.is_entity_node(node):
			pass
		else:
			continue
		var bounds = _node_screen_bounds(camera, node as Node3D, root)
		if bounds.size == Vector2.ZERO:
			continue
		if (
			rect.intersects(bounds)
			or bounds.has_point(rect.position)
			or bounds.has_point(rect.position + rect.size)
		):
			picked.append(node)
	if not additive and picked.is_empty():
		hf_selection.clear()
		var selection = get_editor_interface().get_selection()
		if selection:
			selection.clear()
		return
	_apply_selection_list(picked, additive)


func _apply_selection_list(nodes: Array, additive: bool) -> void:
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	if not additive:
		hf_selection.clear()
	else:
		_sync_hf_selection_if_empty()
	for node in nodes:
		if node and not hf_selection.has(node):
			hf_selection.append(node)
	_apply_hf_selection(selection)


func _apply_hf_selection(selection: EditorSelection) -> void:
	selection.clear()
	for node in hf_selection:
		if is_instance_valid(node):
			selection.add_node(node)


func _sync_hf_selection_if_empty() -> void:
	if not hf_selection.is_empty():
		return
	var selection = get_editor_interface().get_selection()
	if selection:
		hf_selection = selection.get_selected_nodes()


func _project_to_screen(camera: Camera3D, position: Vector3) -> Variant:
	if camera.is_position_behind(position):
		return null
	return camera.unproject_position(position)


func _node_screen_bounds(camera: Camera3D, node: Node3D, root: Node) -> Rect2:
	if not camera or not node:
		return Rect2()
	var visuals: Array = []
	if root:
		root._gather_visual_instances(node, visuals)
	else:
		_gather_visual_instances_local(node, visuals)
	if visuals.is_empty():
		var fallback = _project_to_screen(camera, node.global_transform.origin)
		return Rect2(fallback - Vector2.ONE, Vector2.ONE * 2.0) if fallback != null else Rect2()
	var min_pt = Vector2(INF, INF)
	var max_pt = Vector2(-INF, -INF)
	var had_point = false
	for visual in visuals:
		if not (visual is VisualInstance3D):
			continue
		var vis := visual as VisualInstance3D
		var aabb = vis.get_aabb()
		var corners = [
			aabb.position,
			aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
			aabb.position + Vector3(0.0, aabb.size.y, 0.0),
			aabb.position + Vector3(0.0, 0.0, aabb.size.z),
			aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
			aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
			aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
			aabb.position + aabb.size
		]
		var center_world = vis.global_transform * aabb.get_center()
		if camera.is_position_behind(center_world):
			var all_behind = true
			for corner in corners:
				if not camera.is_position_behind(vis.global_transform * corner):
					all_behind = false
					break
			if all_behind:
				continue
		for corner in corners:
			var world_pos = vis.global_transform * corner
			var screen = _project_to_screen(camera, world_pos)
			if screen == null:
				continue
			had_point = true
			min_pt.x = min(min_pt.x, screen.x)
			min_pt.y = min(min_pt.y, screen.y)
			max_pt.x = max(max_pt.x, screen.x)
			max_pt.y = max(max_pt.y, screen.y)
	if not had_point:
		return Rect2()
	var size = max_pt - min_pt
	if size == Vector2.ZERO:
		size = Vector2.ONE * 2.0
		min_pt -= Vector2.ONE
	return Rect2(min_pt, size)


func _gather_visual_instances_local(node: Node, out: Array) -> void:
	if not node:
		return
	if node is VisualInstance3D:
		out.append(node)
	for child in node.get_children():
		_gather_visual_instances_local(child, out)


func _selection_has_brush(nodes: Array, root: Node) -> bool:
	if not root:
		return false
	for node in nodes:
		if root.is_brush_node(node):
			return true
	return false


func _selection_has_entity(nodes: Array, root: Node) -> bool:
	if not root:
		return false
	for node in nodes:
		if root.is_entity_node(node):
			return true
	return false


func _current_selection_nodes() -> Array:
	if not hf_selection.is_empty():
		return hf_selection.duplicate()
	var selection = get_editor_interface().get_selection()
	if selection:
		return selection.get_selected_nodes()
	return []


func _get_undo_redo() -> EditorUndoRedoManager:
	return undo_redo_manager if undo_redo_manager else get_undo_redo()


func _record_history(action_name: String) -> void:
	if dock:
		dock.record_history(action_name)


func _paint_brush_with_undo(root: Node, brush: Node, mat: Material) -> void:
	if not root or not brush:
		return
	var undo_redo = _get_undo_redo()
	if not undo_redo:
		root.apply_material_to_brush(brush, mat)
		return
	var prev = (
		brush.get("material_override") if brush.get("material_override") else brush.get("material")
	)
	if prev == mat:
		return
	undo_redo.create_action("Paint Brush")
	undo_redo.add_do_method(root, "apply_material_to_brush", brush, mat)
	undo_redo.add_undo_method(root, "apply_material_to_brush", brush, prev)
	undo_redo.commit_action()
	_record_history("Paint Brush")


func _commit_brush_placement(root: Node, info: Dictionary) -> void:
	if info.is_empty():
		return
	var undo_redo = _get_undo_redo()
	if not undo_redo:
		root.create_brush_from_info(info)
		return
	undo_redo.create_action("Place Brush")
	undo_redo.add_do_method(root, "create_brush_from_info", info)
	undo_redo.add_undo_method(root, "delete_brush_by_id", info.get("brush_id", ""))
	undo_redo.commit_action()
	_record_history("Place Brush")


func _delete_selected(root: Node) -> bool:
	var selection = get_editor_interface().get_selection()
	var nodes = _current_selection_nodes()
	var deletable: Array = []
	for node in nodes:
		if root.is_brush_node(node):
			deletable.append(node)
	if deletable.is_empty():
		return false
	selection.clear()
	hf_selection.clear()
	var undo_redo = _get_undo_redo()
	if not undo_redo:
		for node in deletable:
			root.delete_brush(node)
		return true
	undo_redo.create_action("Delete Brushes")
	for node in deletable:
		var parent = node.get_parent()
		var owner = node.owner
		var index = -1
		if parent:
			index = parent.get_children().find(node)
		undo_redo.add_do_method(root, "delete_brush", node, false)
		undo_redo.add_undo_method(root, "restore_brush", node, parent, owner, index)
	undo_redo.commit_action()
	_record_history("Delete Brushes")
	return true


func _duplicate_selected(root: Node) -> void:
	var selection = get_editor_interface().get_selection()
	var nodes = _current_selection_nodes()
	var infos: Array = []
	var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
	for node in nodes:
		if root.is_brush_node(node):
			var info = root.build_duplicate_info(node, Vector3(step, 0.0, 0.0))
			if not info.is_empty():
				infos.append(info)
	if infos.is_empty():
		return
	var undo_redo = _get_undo_redo()
	if not undo_redo:
		selection.clear()
		hf_selection.clear()
		for info in infos:
			var dup = root.create_brush_from_info(info)
			if dup:
				selection.add_node(dup)
				hf_selection.append(dup)
		return
	undo_redo.create_action("Duplicate Brushes")
	for info in infos:
		undo_redo.add_do_method(root, "create_brush_from_info", info)
		undo_redo.add_undo_method(root, "delete_brush_by_id", info.get("brush_id", ""))
	undo_redo.commit_action()
	_record_history("Duplicate Brushes")
	selection.clear()
	hf_selection.clear()
	if root:
		for info in infos:
			var dup = root.find_brush_by_id(info.get("brush_id", ""))
			if dup:
				selection.add_node(dup)
				hf_selection.append(dup)


func _nudge_selected(root: Node, dir: Vector3) -> void:
	var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
	var selection = get_editor_interface().get_selection()
	var nodes = _current_selection_nodes()
	var targets: Array = []
	for node in nodes:
		if node and node is Node3D and root.is_brush_node(node):
			targets.append(node)
	if targets.is_empty():
		return
	var offset = dir * step
	var undo_redo = _get_undo_redo()
	if not undo_redo:
		for node in targets:
			node.global_position += offset
		return
	undo_redo.create_action("Nudge Brushes")
	for node in targets:
		var start_pos = node.global_position
		undo_redo.add_do_property(node, "global_position", start_pos + offset)
		undo_redo.add_undo_property(node, "global_position", start_pos)
	undo_redo.commit_action()
	_record_history("Nudge Brushes")


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return _is_entity_drag_data(data) or _is_brush_preset_drag_data(data)


func _drop_data(position: Vector2, data: Variant) -> void:
	if _is_brush_preset_drag_data(data):
		_handle_brush_preset_drop(position, data)
	else:
		_handle_entity_drop(position, data)


func _is_entity_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_entity"


func _handle_entity_drop(position: Vector2, data: Variant) -> void:
	if not _is_entity_drag_data(data):
		return
	var entity_id = str(data.get("entity_id", ""))
	if entity_id == "":
		return
	var root = active_root if active_root else _get_level_root()
	if not root:
		root = _create_level_root()
	if not root:
		return
	var camera = last_3d_camera
	var mouse_pos = position if position != null else last_3d_mouse_pos
	if camera and root:
		var entity = root.place_entity_at_screen(camera, mouse_pos, entity_id)
		if entity:
			var selection = get_editor_interface().get_selection()
			if selection:
				selection.clear()
				selection.add_node(entity)
			hf_selection.clear()
			hf_selection.append(entity)


func _is_brush_preset_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_brush_preset"


func _handle_brush_preset_drop(position: Vector2, data: Variant) -> void:
	if not _is_brush_preset_drag_data(data):
		return
	var preset_path = str(data.get("preset_path", ""))
	if preset_path == "":
		return
	var preset = load(preset_path)
	if not preset or not (preset is BrushPreset):
		return
	var root = active_root if active_root else _get_level_root()
	if not root:
		root = _create_level_root()
	if not root:
		return
	var camera = last_3d_camera
	var mouse_pos = position if position != null else last_3d_mouse_pos
	if not camera:
		return
	var hit = root._raycast(camera, mouse_pos)
	if hit.is_empty():
		return
	var point = root._snap_point(hit.get("position", Vector3.ZERO))
	var size = preset.size
	var center = point + Vector3(0, size.y * 0.5, 0)
	var operation = preset.operation
	var info = {
		"shape": preset.shape,
		"size": size,
		"center": center,
		"operation": operation,
		"pending": operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node != null,
		"brush_id": root._next_brush_id()
	}
	if root._shape_uses_sides(preset.shape):
		info["sides"] = preset.sides
	var mat = dock.get_active_material() if dock else null
	if mat:
		info["material"] = mat
	_commit_brush_placement(root, info)


func _get_level_root() -> Node:
	var scene = get_editor_interface().get_edited_scene_root()
	if scene:
		if scene.get_script() == LevelRootType or scene.name == "LevelRoot":
			return scene
		var node = scene.get_node_or_null("LevelRoot")
		if node:
			return node
	var current = get_tree().get_current_scene()
	if current:
		return current.get_node_or_null("LevelRoot")
	return null


func _get_level_root_from_node(node: Node) -> Node:
	var current: Node = node
	while current:
		if current.get_script() == LevelRootType or current.name == "LevelRoot":
			return current
		current = current.get_parent()
	return null


func _create_level_root() -> Node:
	var scene = get_editor_interface().get_edited_scene_root()
	if not scene:
		return null
	var root = LevelRootType.new()
	root.name = "LevelRoot"
	scene.add_child(root)
	root.owner = scene
	active_root = root
	var selection = get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(root)
	hf_selection.clear()
	hf_selection.append(root)
	return root
