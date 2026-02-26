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
var numeric_buffer := ""
const LevelRootType = preload("level_root.gd")
const DraftEntityType = preload("draft_entity.gd")
const IconRes = preload("icon.png")
const HFUndoHelper = preload("undo_helper.gd")


func _enter_tree():
	add_custom_type("LevelRoot", "Node3D", LevelRootType, IconRes)
	add_custom_type("DraftEntity", "Node3D", DraftEntityType, IconRes)
	dock = preload("dock.tscn").instantiate()
	undo_redo_manager = get_undo_redo()
	brush_gizmo_plugin = preload("brush_gizmo_plugin.gd").new()
	if brush_gizmo_plugin:
		brush_gizmo_plugin.set_undo_redo(undo_redo_manager)
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
		dock.set_undo_redo(undo_redo_manager)
		if dock.has_signal("hud_visibility_changed"):
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
	if numeric_buffer.length() > 0:
		ctx["numeric"] = numeric_buffer
	hud.update_context(ctx)


func _on_editor_selection_changed() -> void:
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	hf_selection = selection.get_selected_nodes()
	if dock:
		dock.set_selection_count(hf_selection.size())
		dock.set_selection_nodes(hf_selection)


func _handles(object: Object) -> bool:
	if not object or not (object is Node):
		return false
	# Accept if the node is under a LevelRoot, OR if a LevelRoot exists anywhere
	# in the scene. This keeps _forward_3d_gui_input() active so the user can
	# draw/select without having to re-click the LevelRoot node.
	if _get_level_root_from_node(object as Node) != null:
		return true
	if active_root and is_instance_valid(active_root) and active_root.is_inside_tree():
		return true
	return _get_level_root() != null


func _edit(object: Object) -> void:
	if object and object is Node:
		var root = _get_level_root_from_node(object as Node)
		if root:
			active_root = root
			return
	# Don't null active_root — keep the previous root alive as long as it still
	# exists in the scene. This prevents losing the dock/3D connection when the
	# user clicks a Camera, Light, or other non-LevelRoot node.
	if active_root and is_instance_valid(active_root) and active_root.is_inside_tree():
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

	if event is InputEventMouseMotion or event is InputEventMouseButton:
		root.update_editor_grid(target_camera, target_pos)

	var tool_id = dock.get_tool()
	var paint_mode = dock.is_paint_mode_enabled()
	root.grid_snap = dock.get_grid_snap()

	# Paint mode intercept
	if paint_mode:
		var r = _handle_paint_input(event, root, target_camera, target_pos)
		if r != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return r

	# Keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		var r = _handle_keyboard_input(event, root, tool_id, paint_mode)
		if r != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return r

	# Hover update
	if tool_id == 1 and event is InputEventMouseMotion:
		root.update_hover(target_camera, target_pos)
	elif tool_id != 1:
		root.clear_hover()

	# Mouse button handling
	if event is InputEventMouseButton:
		if tool_id != 1:
			root.set_shift_pressed(event.shift_pressed)
			root.set_alt_pressed(event.alt_pressed)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			return _handle_rmb_cancel(root, tool_id)
		if event.button_index == MOUSE_BUTTON_LEFT:
			match tool_id:
				0:
					return _handle_draw_mouse(event, root, target_camera, target_pos)
				1:
					return _handle_select_mouse(event, root, target_camera, target_pos, paint_mode)
				2, 3:
					return _handle_extrude_mouse(event, root, target_camera, target_pos)

	# Mouse motion handling
	if event is InputEventMouseMotion:
		return _handle_mouse_motion(event, root, target_camera, target_pos, tool_id)

	_update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_paint_input(event: InputEvent, root: Node, cam: Camera3D, pos: Vector2) -> int:
	var paint_target = dock.get_paint_target()
	var op = dock.get_operation()
	var size = dock.get_brush_size()
	if paint_target == 0:
		var paint_tool_id = dock.get_paint_tool_id()
		var paint_radius_cells = dock.get_paint_radius_cells()
		var paint_brush_shape = dock.get_brush_shape()
		var handled = root.handle_paint_input(
			cam, event, pos, op, size, paint_tool_id, paint_radius_cells, paint_brush_shape
		)
		if handled:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	elif paint_target == 1:
		var radius_uv = dock.get_surface_paint_radius()
		var strength = dock.get_surface_paint_strength()
		var layer_idx = dock.get_surface_paint_layer()
		var handled_surface = root.handle_surface_paint_input(
			cam, event, pos, radius_uv, strength, layer_idx
		)
		if handled_surface:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _get_nudge_direction(keycode: int) -> Vector3:
	match keycode:
		KEY_UP:
			return Vector3(0.0, 0.0, -1.0)
		KEY_DOWN:
			return Vector3(0.0, 0.0, 1.0)
		KEY_LEFT:
			return Vector3(-1.0, 0.0, 0.0)
		KEY_RIGHT:
			return Vector3(1.0, 0.0, 0.0)
		KEY_PAGEUP:
			return Vector3(0.0, 1.0, 0.0)
		KEY_PAGEDOWN:
			return Vector3(0.0, -1.0, 0.0)
	return Vector3.ZERO


func _handle_numeric_input(event: InputEventKey, root: Node) -> int:
	if not root.input_state.is_dragging() and not root.input_state.is_extruding():
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var keycode = event.keycode
	# Digit keys (0-9)
	if keycode >= KEY_0 and keycode <= KEY_9:
		numeric_buffer += str(keycode - KEY_0)
		_update_numeric_preview(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Decimal point
	if keycode == KEY_PERIOD and "." not in numeric_buffer:
		numeric_buffer += "."
		_update_numeric_preview(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Backspace: remove last character
	if keycode == KEY_BACKSPACE and numeric_buffer.length() > 0:
		numeric_buffer = numeric_buffer.substr(0, numeric_buffer.length() - 1)
		_update_numeric_preview(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Enter: apply the numeric value
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		if numeric_buffer.length() > 0:
			_apply_numeric_value(root)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Tab: apply and move to next dimension (base → height)
	if keycode == KEY_TAB and numeric_buffer.length() > 0:
		_apply_numeric_value(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _update_numeric_preview(root: Node) -> void:
	if not root.input_state.is_dragging() and not root.input_state.is_extruding():
		return
	if numeric_buffer.length() == 0:
		return
	var value = float(numeric_buffer) if numeric_buffer.is_valid_float() else 0.0
	if value <= 0.0:
		return
	if root.input_state.is_drag_height() or root.input_state.is_extruding():
		root.input_state.drag_height = value
		root.update_drag(last_3d_camera, last_3d_mouse_pos)
	elif root.input_state.is_drag_base():
		# Set the base extent from the origin
		var snap = root.grid_snap if root.grid_snap > 0.0 else 1.0
		var extent = Vector3(value, 0.0, value)
		root.input_state.drag_end = root.input_state.drag_origin + extent
		root.update_drag(last_3d_camera, last_3d_mouse_pos)
	_update_hud_context()


func _apply_numeric_value(root: Node) -> void:
	if numeric_buffer.length() == 0:
		return
	var value = float(numeric_buffer) if numeric_buffer.is_valid_float() else 0.0
	numeric_buffer = ""
	if value <= 0.0:
		return
	if root.input_state.is_drag_height():
		root.input_state.drag_height = value
		# Finalize: place the brush
		var size = dock.get_brush_size()
		var info_result = root.end_drag_info(last_3d_camera, last_3d_mouse_pos, size)
		if info_result.get("placed", false):
			_commit_brush_placement(root, info_result.get("info", {}))
		_update_hud_context()
	elif root.input_state.is_drag_base():
		# Apply base size and advance to height
		var extent = Vector3(value, 0.0, value)
		root.input_state.drag_end = root.input_state.drag_origin + extent
		root.input_state.advance_to_height(last_3d_mouse_pos)
		root.update_drag(last_3d_camera, last_3d_mouse_pos)
		_update_hud_context()
	elif root.input_state.is_extruding():
		root.input_state.drag_height = value
		var info = root.end_extrude_info()
		if not info.is_empty():
			_commit_brush_placement(root, info)
		_update_hud_context()


func _handle_keyboard_input(
	event: InputEventKey, root: Node, tool_id: int, paint_mode: bool
) -> int:
	# Numeric input during drag/extrude
	if root.input_state.is_dragging() or root.input_state.is_extruding():
		var nr = _handle_numeric_input(event, root)
		if nr != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return nr

	if event.keycode == KEY_DELETE:
		var deleted = _delete_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if deleted else EditorPlugin.AFTER_GUI_INPUT_PASS
	if event.ctrl_pressed and event.keycode == KEY_D:
		_duplicate_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event.ctrl_pressed and event.keycode == KEY_G:
		_group_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event.ctrl_pressed and event.keycode == KEY_U:
		_ungroup_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event.ctrl_pressed and event.keycode == KEY_H:
		_hollow_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_F:
		_move_selected_to_floor(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_C:
		_move_selected_to_ceiling(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event.shift_pressed and not event.ctrl_pressed and event.keycode == KEY_X:
		_clip_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Nudge keys
	var nudge = _get_nudge_direction(event.keycode)
	if nudge != Vector3.ZERO:
		_nudge_selected(root, nudge)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Extrude tool shortcuts
	if event.keycode == KEY_U:
		dock.set_extrude_tool(1)
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event.keycode == KEY_J:
		dock.set_extrude_tool(-1)
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Paint tool shortcuts
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
	# Axis lock (non-select tools only)
	if tool_id != 1:
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
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_rmb_cancel(root: Node, tool_id: int) -> int:
	if tool_id == 2 or tool_id == 3:
		root.cancel_extrude()
	else:
		root.cancel_drag()
	numeric_buffer = ""
	select_drag_active = false
	select_dragging = false
	_update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func _handle_select_mouse(
	event: InputEventMouseButton,
	root: Node,
	cam: Camera3D,
	pos: Vector2,
	paint_mode: bool,
) -> int:
	var face_select = dock.is_face_select_mode_enabled()
	if event.pressed:
		if face_select:
			var additive_face = (
				event.shift_pressed
				or event.ctrl_pressed
				or event.meta_pressed
				or Input.is_key_pressed(KEY_SHIFT)
				or Input.is_key_pressed(KEY_CTRL)
				or Input.is_key_pressed(KEY_META)
			)
			var face_handled = root.select_face_at_screen(cam, pos, additive_face)
			return (
				EditorPlugin.AFTER_GUI_INPUT_STOP
				if face_handled
				else EditorPlugin.AFTER_GUI_INPUT_PASS
			)
		var active_mat = dock.get_active_material()
		if paint_mode and active_mat:
			var painted = root.pick_brush(cam, pos, false)
			if painted:
				_paint_brush_with_undo(root, painted, active_mat)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		select_drag_origin = pos
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
	# Mouse release
	var selection_action := false
	if select_drag_active:
		if not select_dragging and not face_select:
			var picked = root.pick_brush(cam, pos)
			_select_node(picked, select_additive)
			selection_action = true
	select_drag_active = false
	select_dragging = false
	return (
		EditorPlugin.AFTER_GUI_INPUT_STOP if selection_action else EditorPlugin.AFTER_GUI_INPUT_PASS
	)


func _handle_extrude_mouse(
	event: InputEventMouseButton, root: Node, cam: Camera3D, pos: Vector2
) -> int:
	if event.pressed:
		numeric_buffer = ""
		var extrude_dir = dock.get_extrude_direction()
		var started = root.begin_extrude(cam, pos, extrude_dir)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if started else EditorPlugin.AFTER_GUI_INPUT_PASS
	var info = root.end_extrude_info()
	if not info.is_empty():
		_commit_brush_placement(root, info)
	_update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func _handle_draw_mouse(
	event: InputEventMouseButton, root: Node, cam: Camera3D, pos: Vector2
) -> int:
	var op = dock.get_operation()
	var size = dock.get_brush_size()
	var shape = dock.get_shape()
	var sides = dock.get_sides()
	if event.pressed:
		numeric_buffer = ""
		var started = root.begin_drag(cam, pos, op, size, shape, sides)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if started else EditorPlugin.AFTER_GUI_INPUT_PASS
	var result = root.end_drag_info(cam, pos, size)
	if result.get("handled", false):
		if result.get("placed", false):
			_commit_brush_placement(root, result.get("info", {}))
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_mouse_motion(
	event: InputEventMouseMotion,
	root: Node,
	cam: Camera3D,
	pos: Vector2,
	tool_id: int,
) -> int:
	if tool_id != 1:
		root.set_shift_pressed(event.shift_pressed)
		root.set_alt_pressed(event.alt_pressed)
	var face_select = dock.is_face_select_mode_enabled()
	if (
		tool_id == 1
		and select_drag_active
		and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0
		and not face_select
	):
		if not select_dragging and select_drag_origin.distance_to(pos) >= select_drag_threshold:
			select_dragging = true
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if (tool_id == 2 or tool_id == 3) and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		root.update_extrude(cam, pos)
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if tool_id == 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		root.update_drag(cam, pos)
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
	var nudge = _get_nudge_direction(event.keycode)
	if nudge != Vector3.ZERO:
		_nudge_selected(root, nudge)
		event.accept()


func _select_node(node: Node, additive: bool = false) -> void:
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	var toggle = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	# Expand grouped nodes
	var expanded: Array = [node] if node else []
	var root = active_root if active_root else _get_level_root()
	if node and root and root.visgroup_system:
		var group_id = root.visgroup_system.get_group_of(node)
		if group_id != "":
			expanded = root.visgroup_system.get_group_members(group_id)
	if not additive:
		hf_selection.clear()
		for n in expanded:
			if n and not hf_selection.has(n):
				hf_selection.append(n)
	else:
		_sync_hf_selection_if_empty()
		for n in expanded:
			if n:
				if toggle and hf_selection.has(n):
					hf_selection.erase(n)
				elif not hf_selection.has(n):
					hf_selection.append(n)
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
	var prev = (
		brush.get("material_override") if brush.get("material_override") else brush.get("material")
	)
	if prev == mat:
		return
	var brush_id := ""
	if root.has_method("get_brush_info_from_node"):
		var info = root.get_brush_info_from_node(brush)
		brush_id = str(info.get("brush_id", ""))
	var method_name = "apply_material_to_brush"
	var args: Array = [brush, mat]
	if brush_id != "":
		method_name = "apply_material_to_brush_by_id"
		args = [brush_id, mat]
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Paint Brush",
		method_name,
		args,
		false,
		Callable(self, "_record_history")
	)


func _commit_brush_placement(root: Node, info: Dictionary) -> void:
	if info.is_empty():
		return
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Place Brush",
		"create_brush_from_info",
		[info],
		false,
		Callable(self, "_record_history")
	)


func _delete_selected(root: Node) -> bool:
	var selection = get_editor_interface().get_selection()
	var nodes = _current_selection_nodes()
	var brush_ids: Array = []
	for node in nodes:
		if root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			if info.is_empty():
				continue
			var brush_id = str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
	if brush_ids.is_empty():
		return false
	selection.clear()
	hf_selection.clear()
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Delete Brushes",
		"delete_brushes_by_id",
		[brush_ids],
		false,
		Callable(self, "_record_history")
	)
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
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Duplicate Brushes",
		"create_brushes_from_infos",
		[infos],
		false,
		Callable(self, "_record_history")
	)
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
	var brush_ids: Array = []
	for node in nodes:
		if node and node is Node3D and root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			var brush_id = str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
	if brush_ids.is_empty():
		return
	var offset = dir * step
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Nudge Brushes",
		"nudge_brushes_by_id",
		[brush_ids, offset],
		false,
		Callable(self, "_record_history")
	)


func _group_selected(root: Node) -> void:
	var nodes = _current_selection_nodes()
	if nodes.size() < 2 or not root or not root.visgroup_system:
		return
	var group_name = "group_%d" % Time.get_ticks_usec()
	root.visgroup_system.group_selection(group_name, nodes)
	_record_history("Group Selection")
	if dock:
		dock.refresh_visgroup_ui()


func _ungroup_selected(root: Node) -> void:
	var nodes = _current_selection_nodes()
	if nodes.is_empty() or not root or not root.visgroup_system:
		return
	root.visgroup_system.ungroup_nodes(nodes)
	_record_history("Ungroup Selection")
	if dock:
		dock.refresh_visgroup_ui()


func _hollow_selected(root: Node) -> void:
	var nodes = _current_selection_nodes()
	if nodes.is_empty():
		return
	var brush = nodes[0]
	if not root.is_brush_node(brush):
		return
	var info = root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return
	var thickness = dock.get_hollow_thickness() if dock else 4.0
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Hollow",
		"hollow_brush_by_id",
		[brush_id, thickness],
		false,
		Callable(self, "_record_history")
	)


func _move_selected_to_floor(root: Node) -> void:
	_move_selected_vertical(root, "Move to Floor", "move_brushes_to_floor")


func _move_selected_to_ceiling(root: Node) -> void:
	_move_selected_vertical(root, "Move to Ceiling", "move_brushes_to_ceiling")


func _move_selected_vertical(root: Node, action_name: String, method_name: String) -> void:
	var nodes = _current_selection_nodes()
	var brush_ids: Array = []
	for node in nodes:
		if node and root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		action_name,
		method_name,
		[brush_ids],
		false,
		Callable(self, "_record_history")
	)


func _clip_selected(root: Node) -> void:
	var nodes = _current_selection_nodes()
	if nodes.is_empty():
		return
	var brush = nodes[0]
	if not root.is_brush_node(brush):
		return
	var info = root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return
	# Default clip: split along Y axis at center
	var center = info.get("center", Vector3.ZERO)
	var split_pos = center.y if center is Vector3 else 0.0
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Clip Brush",
		"clip_brush_by_id",
		[brush_id, 1, split_pos],
		false,
		Callable(self, "_record_history")
	)


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
		# Check direct child (fast path)
		var node = scene.get_node_or_null("LevelRoot")
		if node:
			return node
		# Deep search — find any LevelRoot anywhere in the scene tree
		var found = _find_level_root_deep(scene)
		if found:
			return found
	var current = get_tree().get_current_scene()
	if current:
		var node = current.get_node_or_null("LevelRoot")
		if node:
			return node
		return _find_level_root_deep(current)
	return null


func _find_level_root_deep(node: Node) -> Node:
	for child in node.get_children():
		if child.get_script() == LevelRootType or child is LevelRoot:
			return child
		var found = _find_level_root_deep(child)
		if found:
			return found
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
