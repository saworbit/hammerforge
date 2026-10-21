@tool
extends RefCounted
class_name HFDragSystem

const HFInputStateType = preload("../input_state.gd")
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The shapes whose ground footprint is a circle, so a dragged rectangle has to
## be reduced to one diameter before it can become a brush.
const RADIAL_SHAPES := [
	DraftBrush.BrushShape.CYLINDER,
	DraftBrush.BrushShape.CONE,
	DraftBrush.BrushShape.SPHERE,
	DraftBrush.BrushShape.CAPSULE,
]

var root: Node3D
var input_state: HFInputStateType = HFInputStateType.new()
## The brush the last Draw made, for Repeat (#1407): its `shape`, `size` and
## `operation`, and its `sides` and `material` when it had them. Empty until a
## Draw places one.
var last_drawn: Dictionary = {}


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
	var start = draw_start(camera, mouse_pos)
	if start == null:
		return false
	var snapped_origin: Vector3 = start
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
		# A dimension typed into the HUD owns the field it was typed for until the
		# buffer empties. Recomputing it here is what made the number look like it
		# did nothing: it went on screen and the mouse took it straight back.
		var typed_base := input_state.has_numeric_override()
		if (not input_state.alt_pressed or input_state.shift_pressed) and not typed_base:
			input_state.drag_end = root.grid_system.snap_draw_hit(hit)
			input_state.drag_end = _apply_axis_lock(input_state.drag_origin, input_state.drag_end)
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
		if not input_state.has_numeric_override():
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


func end_drag_info(_camera: Camera3D, mouse_pos: Vector2, size_default: Vector3) -> Dictionary:
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
	info["draw_origin"] = input_state.drag_origin
	last_drawn = _repeatable(info)
	input_state.end_drag()
	_clear_preview()
	return {"handled": true, "placed": true, "info": info}


## Where a Draw pressed at `mouse_pos` starts: the face or the grid under the
## cursor, snapped. Null when the ray meets neither. Repeat stands its copies
## here too, so a stamp lands where a Draw would have begun.
func draw_start(camera: Camera3D, mouse_pos: Vector2) -> Variant:
	var hit = root._raycast(camera, mouse_pos)
	if not hit:
		return null
	return root.grid_system.snap_draw_hit(hit)


## What Repeat keeps of a Draw's info: the brush, not where it went.
static func _repeatable(info: Dictionary) -> Dictionary:
	var kept := {"shape": info["shape"], "size": info["size"], "operation": info["operation"]}
	for key in ["sides", "material"]:
		if info.has(key):
			kept[key] = info[key]
	return kept


## A copy of `brush`, a brush `last_drawn` describes, standing on `base`: centred
## over the point with its bottom on it, as the info `create_brush_from_info()`
## takes, with an id of its own. The grid moves to it, as it does after a Draw.
func repeat_info(brush: Dictionary, base: Vector3) -> Dictionary:
	var size: Vector3 = brush["size"]
	var operation := int(brush["operation"])
	var info := {
		"shape": brush["shape"],
		"size": size,
		"center": base + Vector3(0.0, size.y * 0.5, 0.0),
		"operation": operation,
		"pending": operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node != null,
		"brush_id": root._next_brush_id(),
		"draw_origin": base,
	}
	for key in ["sides", "material"]:
		if brush.has(key):
			info[key] = brush[key]
	return info


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
	var preview = root.preview_brush
	root.preview_brush = null
	if preview and is_instance_valid(preview) and preview.is_inside_tree():
		# Out of DraftBrushes now, not at the end of the frame: Place Brush
		# records the level in this frame, and a preview still there went into
		# the step's before state, so an undo rebuilt it as a real brush.
		preview.get_parent().remove_child(preview)
		preview.queue_free()


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
	root.brush_system.give_active_material(info)
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
	# The rectangle a mapper drags is ground they can see: up to a wall, between two
	# pillars, inside a doorway. A round brush has to end up inside it. That means
	# the *smaller* dragged side is the diameter, not the larger one, and the
	# footprint is centred on the rectangle rather than grown out of the corner the
	# drag started at. Both halves of that were the other way round (#604).
	if shape in RADIAL_SHAPES:
		var diameter := maxf(0.1, minf(final_size.x, final_size.z))
		if shape == DraftBrush.BrushShape.SPHERE:
			# A SPHERE is uniform by definition - ELLIPSOID is the shape with three
			# independent axes - so the height stage cannot set it alone. Taking the
			# height into the diameter is what makes that stage land at all, instead
			# of asking for a number and throwing it away (#605). The sphere is then
			# inscribed in the box that was dragged, which is the same rule as the
			# other three.
			diameter = maxf(0.1, minf(diameter, final_size.y))
			final_size = Vector3(diameter, diameter, diameter)
		else:
			final_size = Vector3(diameter, final_size.y, diameter)
	final_size = DraftBrush.normalized_size_for_shape(shape, final_size)
	if shape in RADIAL_SHAPES:
		# Every earlier branch - axis lock, equal_base, equal_all, the default-size
		# fallback - has already written the rectangle it wants into min/max, and for
		# all of those the midpoint is the origin. Centring on the midpoint is
		# therefore the one rule that serves them and a plain drag alike.
		var center_x: float = (min_x + max_x) * 0.5
		var center_z: float = (min_z + max_z) * 0.5
		min_x = center_x - final_size.x * 0.5
		max_x = center_x + final_size.x * 0.5
		min_z = center_z - final_size.z * 0.5
		max_z = center_z + final_size.z * 0.5
	var center = Vector3(
		(min_x + max_x) * 0.5,
		origin.y + final_size.y * 0.5,
		(min_z + max_z) * 0.5,
	)
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


func _apply_axis_lock(_origin: Vector3, current: Vector3) -> Vector3:
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


# ---------------------------------------------------------------------------
# Height
# ---------------------------------------------------------------------------


func _height_from_mouse(current: Vector2, start: Vector2, start_height: float) -> float:
	var delta = current.y - start.y
	var raw_height = start_height + (-delta / max(1.0, root.height_pixels_per_unit))
	if root.grid_snap > 0.0:
		raw_height = max(root.grid_snap, snappedf(raw_height, root.grid_snap))
	return max(0.1, raw_height)
