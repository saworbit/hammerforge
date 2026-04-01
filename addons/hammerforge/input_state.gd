@tool
extends RefCounted
class_name HFInputState

enum Mode { IDLE, DRAG_BASE, DRAG_HEIGHT, SURFACE_PAINT, EXTRUDE, VERTEX_EDIT }

var mode := Mode.IDLE

## Optional callback invoked before a forced mode reset.  The coordinator
## (level_root) sets this so that active tool implementations (drag preview,
## extrude preview, etc.) are torn down before the mode enum changes.
## Signature: func(old_mode: int) -> void
var on_force_reset: Callable = Callable()

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
	if mode != Mode.IDLE:
		push_warning("HFInputState: begin_drag called while in %s — forcing reset" % _mode_name())
		_force_reset()
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
	if mode != Mode.DRAG_BASE:
		push_warning(
			"HFInputState: advance_to_height called while in %s (expected DRAG_BASE)" % _mode_name()
		)
		return
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
	if mode != Mode.IDLE:
		push_warning(
			"HFInputState: begin_surface_paint called while in %s — forcing reset" % _mode_name()
		)
		_force_reset()
	mode = Mode.SURFACE_PAINT


func end_surface_paint() -> void:
	mode = Mode.IDLE


func begin_extrude() -> void:
	if mode != Mode.IDLE:
		push_warning(
			"HFInputState: begin_extrude called while in %s — forcing reset" % _mode_name()
		)
		_force_reset()
	mode = Mode.EXTRUDE


func end_extrude() -> void:
	mode = Mode.IDLE


func is_extruding() -> bool:
	return mode == Mode.EXTRUDE


func begin_vertex_edit() -> void:
	if mode != Mode.IDLE:
		push_warning(
			"HFInputState: begin_vertex_edit called while in %s — forcing reset" % _mode_name()
		)
		_force_reset()
	mode = Mode.VERTEX_EDIT


func end_vertex_edit() -> void:
	mode = Mode.IDLE


func is_vertex_editing() -> bool:
	return mode == Mode.VERTEX_EDIT


func get_drag_dimensions() -> Vector3:
	if mode == Mode.DRAG_BASE:
		var delta = drag_end - drag_origin
		return Vector3(absf(delta.x), drag_height, absf(delta.z))
	if mode == Mode.DRAG_HEIGHT:
		var delta = drag_end - drag_origin
		return Vector3(absf(delta.x), drag_height, absf(delta.z))
	return Vector3.ZERO


static func format_dimensions(dims: Vector3) -> String:
	if dims == Vector3.ZERO:
		return ""
	# Show W x H x D, omitting decimals if whole numbers
	var w := _fmt_num(dims.x)
	var h := _fmt_num(dims.y)
	var d := _fmt_num(dims.z)
	return "%s x %s x %s" % [w, h, d]


static func _fmt_num(v: float) -> String:
	if absf(v - roundf(v)) < 0.01:
		return str(int(v))
	return "%.1f" % v


# Backward-compat: map to legacy drag_stage int
func get_drag_stage() -> int:
	match mode:
		Mode.DRAG_BASE:
			return 1
		Mode.DRAG_HEIGHT:
			return 2
		_:
			return 0


func _force_reset() -> void:
	var old_mode := mode
	if on_force_reset.is_valid():
		on_force_reset.call(old_mode)
	# Ensure mode is IDLE even if the callback forgot to call cancel()
	mode = Mode.IDLE
	lock_axis_active = 0


func _mode_name() -> String:
	match mode:
		Mode.IDLE:
			return "IDLE"
		Mode.DRAG_BASE:
			return "DRAG_BASE"
		Mode.DRAG_HEIGHT:
			return "DRAG_HEIGHT"
		Mode.SURFACE_PAINT:
			return "SURFACE_PAINT"
		Mode.EXTRUDE:
			return "EXTRUDE"
		Mode.VERTEX_EDIT:
			return "VERTEX_EDIT"
	return "UNKNOWN(%d)" % mode
