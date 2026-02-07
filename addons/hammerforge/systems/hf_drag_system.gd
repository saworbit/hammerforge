@tool
extends RefCounted
class_name HFDragSystem

const HFInputStateType = preload("../input_state.gd")
const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")

var root: Node3D
var input_state: HFInputStateType = HFInputStateType.new()


func _init(level_root: Node3D) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# Drag lifecycle
# ---------------------------------------------------------------------------


func begin_drag(
	camera: Camera3D, mouse_pos: Vector2, operation: int, size: Vector3, shape: int, sides: int = 4
) -> bool:
	if not input_state.is_idle():
		return false
	var hit = root._raycast(camera, mouse_pos)
	if not hit:
		return false
	var snapped_origin = root._snap_point(hit.position)
	var height = root.grid_snap if root.grid_snap > 0.0 else size.y
	input_state.begin_drag(snapped_origin, operation, shape, sides, height, size, mouse_pos)
	_ensure_preview(shape, operation, size, sides)
	_update_preview(
		snapped_origin,
		snapped_origin,
		height,
		shape,
		size,
		_current_axis_lock(),
		input_state.shift_pressed and not input_state.alt_pressed,
		input_state.shift_pressed and input_state.alt_pressed
	)
	return true


func update_drag(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not input_state.is_dragging():
		return
	if input_state.is_drag_base():
		var hit = root._raycast(camera, mouse_pos)
		if not hit:
			return
		if not input_state.alt_pressed or input_state.shift_pressed:
			input_state.drag_end = root._snap_point(hit.position)
			_apply_axis_lock(input_state.drag_origin, input_state.drag_end)
			_update_lock_state(input_state.drag_origin, input_state.drag_end)
		if input_state.alt_pressed:
			input_state.drag_height = _height_from_mouse(
				mouse_pos,
				input_state.height_stage_start_mouse,
				input_state.height_stage_start_height
			)
		_update_preview(
			input_state.drag_origin,
			input_state.drag_end,
			input_state.drag_height,
			input_state.drag_shape,
			input_state.drag_size_default,
			_current_axis_lock(),
			input_state.shift_pressed and not input_state.alt_pressed,
			input_state.shift_pressed and input_state.alt_pressed
		)
	elif input_state.is_drag_height():
		input_state.drag_height = _height_from_mouse(
			mouse_pos, input_state.height_stage_start_mouse, input_state.height_stage_start_height
		)
		_update_preview(
			input_state.drag_origin,
			input_state.drag_end,
			input_state.drag_height,
			input_state.drag_shape,
			input_state.drag_size_default,
			_current_axis_lock(),
			input_state.shift_pressed and not input_state.alt_pressed,
			input_state.shift_pressed and input_state.alt_pressed
		)


func end_drag_info(camera: Camera3D, mouse_pos: Vector2, size_default: Vector3) -> Dictionary:
	if not input_state.is_dragging():
		return {"handled": false}
	if input_state.is_drag_base():
		input_state.advance_to_height(mouse_pos)
		return {"handled": true, "placed": false}
	var info = _build_brush_info(
		input_state.drag_origin,
		input_state.drag_end,
		input_state.drag_height,
		input_state.drag_shape,
		size_default,
		input_state.drag_operation,
		input_state.shift_pressed and not input_state.alt_pressed,
		input_state.shift_pressed and input_state.alt_pressed
	)
	input_state.end_drag()
	_clear_preview()
	return {"handled": true, "placed": true, "info": info}


func end_drag(camera: Camera3D, mouse_pos: Vector2, size_default: Vector3) -> bool:
	var result = end_drag_info(camera, mouse_pos, size_default)
	if not result.get("handled", false):
		return false
	if result.get("placed", false):
		root.create_brush_from_info(result.get("info", {}))
	return true


func cancel_drag() -> void:
	input_state.cancel()
	_clear_preview()


# ---------------------------------------------------------------------------
# Preview management
# ---------------------------------------------------------------------------


func _ensure_preview(shape: int, operation: int, size_default: Vector3, sides: int) -> void:
	if root.preview_brush:
		var needs_replace = root.preview_brush.shape != shape
		if not needs_replace:
			root.preview_brush.sides = sides
			if operation == CSGShape3D.OPERATION_SUBTRACTION:
				root.preview_brush.operation = CSGShape3D.OPERATION_SUBTRACTION
				root._apply_brush_material(root.preview_brush, root._make_pending_cut_material())
			else:
				root.preview_brush.operation = operation
				root._apply_brush_material(root.preview_brush, root._make_brush_material(operation))
			return
		_clear_preview()
	root.preview_brush = root._create_brush(shape, size_default, operation, sides)
	if not root.preview_brush:
		return
	root.preview_brush.name = "PreviewBrush"
	if operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node:
		root.preview_brush.operation = CSGShape3D.OPERATION_SUBTRACTION
		root._apply_brush_material(root.preview_brush, root._make_pending_cut_material())
		root.pending_node.add_child(root.preview_brush)
	else:
		if root.draft_brushes_node:
			root.draft_brushes_node.add_child(root.preview_brush)


func _update_preview(
	origin: Vector3,
	current: Vector3,
	height: float,
	shape: int,
	size_default: Vector3,
	lock_axis: int,
	equal_base: bool,
	equal_all: bool
) -> void:
	if not root.preview_brush:
		return
	var info = _compute_brush_info(
		origin, current, height, shape, size_default, lock_axis, equal_base, equal_all
	)
	root.preview_brush.global_position = info.center
	root.preview_brush.size = info.size


func _clear_preview() -> void:
	if root.preview_brush and root.preview_brush.is_inside_tree():
		root.preview_brush.queue_free()
	root.preview_brush = null


# ---------------------------------------------------------------------------
# Brush info computation
# ---------------------------------------------------------------------------


func _build_brush_info(
	origin: Vector3,
	current: Vector3,
	height: float,
	shape: int,
	size_default: Vector3,
	operation: int,
	equal_base: bool,
	equal_all: bool
) -> Dictionary:
	var computed = _compute_brush_info(
		origin, current, height, shape, size_default, _current_axis_lock(), equal_base, equal_all
	)
	var info = {
		"shape": shape,
		"size": computed.size,
		"center": computed.center,
		"operation": operation,
		"pending": operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node != null,
		"brush_id": root._next_brush_id()
	}
	if root._shape_uses_sides(shape):
		info["sides"] = input_state.drag_sides
	return info


func _compute_brush_info(
	origin: Vector3,
	current: Vector3,
	height: float,
	shape: int,
	size_default: Vector3,
	lock_axis: int,
	equal_base: bool,
	equal_all: bool
) -> Dictionary:
	var min_x = min(origin.x, current.x)
	var max_x = max(origin.x, current.x)
	var min_z = min(origin.z, current.z)
	var max_z = max(origin.z, current.z)
	if lock_axis == root.AxisLock.X:
		var thickness_z = (
			input_state.locked_thickness.z
			if input_state.locked_thickness.z > 0.0
			else max(root.grid_snap, size_default.z * 0.25)
		)
		var half_z = max(0.1, thickness_z * 0.5)
		min_z = origin.z - half_z
		max_z = origin.z + half_z
	elif lock_axis == root.AxisLock.Z:
		var thickness_x = (
			input_state.locked_thickness.x
			if input_state.locked_thickness.x > 0.0
			else max(root.grid_snap, size_default.x * 0.25)
		)
		var half_x = max(0.1, thickness_x * 0.5)
		min_x = origin.x - half_x
		max_x = origin.x + half_x
	elif lock_axis == root.AxisLock.Y:
		var thickness_x = (
			input_state.locked_thickness.x
			if input_state.locked_thickness.x > 0.0
			else max(root.grid_snap, size_default.x * 0.25)
		)
		var thickness_z = (
			input_state.locked_thickness.z
			if input_state.locked_thickness.z > 0.0
			else max(root.grid_snap, size_default.z * 0.25)
		)
		var half_x = max(0.1, thickness_x * 0.5)
		var half_z = max(0.1, thickness_z * 0.5)
		min_x = origin.x - half_x
		max_x = origin.x + half_x
		min_z = origin.z - half_z
		max_z = origin.z + half_z
	var size_x = max_x - min_x
	var size_z = max_z - min_z
	if equal_base:
		var side = max(size_x, size_z)
		size_x = side
		size_z = side
		min_x = origin.x - side * 0.5
		max_x = origin.x + side * 0.5
		min_z = origin.z - side * 0.5
		max_z = origin.z + side * 0.5
	if equal_all:
		var side_all = max(size_x, size_z)
		size_x = side_all
		size_z = side_all
		height = side_all
		min_x = origin.x - side_all * 0.5
		max_x = origin.x + side_all * 0.5
		min_z = origin.z - side_all * 0.5
		max_z = origin.z + side_all * 0.5
	var extent = max(size_x, size_z)
	var min_extent = max(0.1, root.grid_snap * 0.5)
	var final_size = Vector3(size_x, height, size_z)
	if extent < min_extent:
		final_size = Vector3(size_default.x, height, size_default.z)
		min_x = origin.x - final_size.x * 0.5
		max_x = origin.x + final_size.x * 0.5
		min_z = origin.z - final_size.z * 0.5
		max_z = origin.z + final_size.z * 0.5
	var center = Vector3((min_x + max_x) * 0.5, origin.y + height * 0.5, (min_z + max_z) * 0.5)
	if shape == root.BrushShape.CYLINDER:
		var radius = max(final_size.x, final_size.z) * 0.5
		final_size = Vector3(radius * 2.0, height, radius * 2.0)
	return {"center": center, "size": final_size}


# ---------------------------------------------------------------------------
# Axis locking
# ---------------------------------------------------------------------------


func set_axis_lock(lock: int, manual: bool = true) -> void:
	if manual:
		if input_state.manual_axis_lock and input_state.axis_lock == lock:
			input_state.axis_lock = root.AxisLock.NONE
			input_state.manual_axis_lock = false
			root._refresh_grid_plane()
			return
		input_state.axis_lock = lock
		input_state.manual_axis_lock = true
		root._refresh_grid_plane()
		return
	input_state.axis_lock = lock
	root._refresh_grid_plane()


func set_shift_pressed(pressed: bool) -> void:
	input_state.shift_pressed = pressed
	if not pressed and not input_state.manual_axis_lock:
		input_state.axis_lock = root.AxisLock.NONE
	root._refresh_grid_plane()


func set_alt_pressed(pressed: bool) -> void:
	input_state.alt_pressed = pressed


func _current_axis_lock() -> int:
	if input_state.manual_axis_lock:
		return input_state.axis_lock
	return root.AxisLock.NONE


func _apply_axis_lock(origin: Vector3, current: Vector3) -> Vector3:
	return current


func _update_lock_state(origin: Vector3, current: Vector3) -> void:
	var lock = _current_axis_lock()
	if lock == root.AxisLock.NONE:
		input_state.lock_axis_active = root.AxisLock.NONE
		input_state.locked_thickness = Vector3.ZERO
		return
	if lock != input_state.lock_axis_active:
		input_state.lock_axis_active = lock
		if lock == root.AxisLock.X:
			input_state.locked_thickness.z = abs(current.z - origin.z)
		elif lock == root.AxisLock.Z:
			input_state.locked_thickness.x = abs(current.x - origin.x)
		elif lock == root.AxisLock.Y:
			input_state.locked_thickness.x = abs(current.x - origin.x)
			input_state.locked_thickness.z = abs(current.z - origin.z)


func _pick_axis(origin: Vector3, current: Vector3) -> int:
	var dx = abs(current.x - origin.x)
	var dz = abs(current.z - origin.z)
	return root.AxisLock.X if dx >= dz else root.AxisLock.Z


# ---------------------------------------------------------------------------
# Height
# ---------------------------------------------------------------------------


func _height_from_mouse(current: Vector2, start: Vector2, start_height: float) -> float:
	var delta = current.y - start.y
	var raw_height = start_height + (-delta / max(1.0, root.height_pixels_per_unit))
	if root.grid_snap > 0.0:
		raw_height = max(root.grid_snap, snappedf(raw_height, root.grid_snap))
	return max(0.1, raw_height)
