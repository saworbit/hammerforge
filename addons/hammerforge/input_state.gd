@tool
extends RefCounted
class_name HFInputState

enum Mode { IDLE, DRAG_BASE, DRAG_HEIGHT, SURFACE_PAINT }

var mode := Mode.IDLE

# Drag state
var drag_origin := Vector3.ZERO
var drag_end := Vector3.ZERO
var drag_operation: int = 0  # CSGShape3D.OPERATION_UNION
var drag_shape: int = 0  # BrushShape.BOX
var drag_sides: int = 4
var drag_height: float = 32.0
var drag_size_default := Vector3(32, 32, 32)

# Axis locking
var axis_lock: int = 0  # AxisLock.NONE
var manual_axis_lock := false
var lock_axis_active: int = 0
var locked_thickness := Vector3.ZERO

# Modifier keys
var shift_pressed := false
var alt_pressed := false

# Height stage tracking
var height_stage_start_mouse := Vector2.ZERO
var height_stage_start_height: float = 32.0


func is_idle() -> bool:
	return mode == Mode.IDLE


func is_dragging() -> bool:
	return mode == Mode.DRAG_BASE or mode == Mode.DRAG_HEIGHT


func is_drag_base() -> bool:
	return mode == Mode.DRAG_BASE


func is_drag_height() -> bool:
	return mode == Mode.DRAG_HEIGHT


func is_surface_painting() -> bool:
	return mode == Mode.SURFACE_PAINT


func begin_drag(
	origin: Vector3,
	operation: int,
	shape: int,
	sides: int,
	height: float,
	size_default: Vector3,
	mouse_pos: Vector2
) -> void:
	mode = Mode.DRAG_BASE
	drag_origin = origin
	drag_end = origin
	drag_operation = operation
	drag_shape = shape
	drag_sides = sides
	drag_height = height
	drag_size_default = size_default
	if not manual_axis_lock:
		axis_lock = 0  # AxisLock.NONE
	lock_axis_active = 0
	locked_thickness = Vector3.ZERO
	height_stage_start_mouse = mouse_pos
	height_stage_start_height = height


func advance_to_height(mouse_pos: Vector2) -> void:
	mode = Mode.DRAG_HEIGHT
	height_stage_start_mouse = mouse_pos
	height_stage_start_height = drag_height


func end_drag() -> void:
	mode = Mode.IDLE
	lock_axis_active = 0


func cancel() -> void:
	mode = Mode.IDLE
	lock_axis_active = 0


func begin_surface_paint() -> void:
	mode = Mode.SURFACE_PAINT


func end_surface_paint() -> void:
	mode = Mode.IDLE


# Backward-compat: map to legacy drag_stage int
func get_drag_stage() -> int:
	match mode:
		Mode.DRAG_BASE:
			return 1
		Mode.DRAG_HEIGHT:
			return 2
		_:
			return 0
