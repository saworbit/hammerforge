@tool
extends Control
class_name UVEditor

signal uv_changed(face)

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("face_data.gd")
@warning_ignore_restore("shadowed_global_identifier")

@export var point_radius: float = 6.0
@export var line_color: Color = Color(0.8, 0.9, 1.0, 0.9)
@export var point_color: Color = Color(0.2, 0.9, 0.4, 1.0)
@export var point_color_selected: Color = Color(1.0, 0.8, 0.2, 1.0)
## The texture is drawn through this, faint enough that the outline stays the
## thing that reads.
@export var texture_tint: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var grid_color: Color = Color(1.0, 1.0, 1.0, 0.08)
@export var grid_unit_color: Color = Color(1.0, 1.0, 1.0, 0.25)

## Space left around the face so the outermost points are inside the control and
## can be grabbed rather than sitting on its edge.
const CANVAS_MARGIN := 12.0

## The extent a degenerate axis is given. A CYLINDRICAL projection, or any face
## whose UV span is zero in one direction, has nothing to divide by otherwise.
const MIN_UV_EXTENT := 1.0

## The UV Snap row's steps, in UV units, which are repeats of the texture.
const SNAP_PRESETS := [0.03125, 0.0625, 0.125, 0.25, 0.5, 1.0]
const SNAP_PRESET_LABELS := ["1/32", "1/16", "1/8", "1/4", "1/2", "1"]
const DEFAULT_SNAP_STEP := 0.125

## Grid lines closer than this many pixels are left out, so a large face does not
## turn into a grey block.
const MIN_GRID_SPACING := 4.0

var _face: FaceData = null
var _drag_index: int = -1

## The face's albedo texture, drawn under the outline once per repeat. Null keeps
## the canvas blank.
var _texture: Texture2D = null

## Whether a dragged corner lands on the nearest multiple of `snap_step` on each
## axis. Ctrl (Cmd on macOS) places it freely for that drag.
var snap_enabled := true
var snap_step := DEFAULT_SNAP_STEP

## The face's own UV bounding box, which is what the canvas shows.
##
## A HammerForge UV is a world coordinate, not a 0..1 fraction:
## `_project_uvs_for_vertices()` reads it straight off the vertex along the
## projection's axes, so a 64 unit box spans 64. Drawing it as a fraction of the control put
## every point far outside, which is why the panel was blank on every brush, and
## clamping a drag to 0..1 collapsed whatever it was into the corner and left the
## face's UV quad no longer a quad.
##
## Held rather than recomputed per draw, so the canvas does not rescale under the
## cursor while a point is being dragged.
var _uv_bounds := Rect2(Vector2.ZERO, Vector2(MIN_UV_EXTENT, MIN_UV_EXTENT))


func _init() -> void:
	# The texture is drawn as one region of UV space, which is only one tile per
	# repeat when sampling wraps.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func set_face(face: FaceData) -> void:
	_face = face
	if _face:
		_face.ensure_custom_uvs()
	_fit_bounds_to_face()
	queue_redraw()


func set_texture(texture: Texture2D) -> void:
	_texture = texture
	queue_redraw()


## A step that is not a positive number is ignored, and the one before it kept.
func set_snap(enabled: bool, step: float) -> void:
	snap_enabled = enabled
	if is_finite(step) and step > 0.0:
		snap_step = step
	queue_redraw()


## Fit the canvas to the face it was handed.
func _fit_bounds_to_face() -> void:
	if _face == null or _face.custom_uvs.is_empty():
		_uv_bounds = Rect2(Vector2.ZERO, Vector2(MIN_UV_EXTENT, MIN_UV_EXTENT))
		return
	var low: Vector2 = _face.custom_uvs[0]
	var high: Vector2 = _face.custom_uvs[0]
	for uv in _face.custom_uvs:
		low = Vector2(minf(low.x, uv.x), minf(low.y, uv.y))
		high = Vector2(maxf(high.x, uv.x), maxf(high.y, uv.y))
	var extent := high - low
	if not is_finite(extent.x) or extent.x <= 0.0:
		extent.x = MIN_UV_EXTENT
	if not is_finite(extent.y) or extent.y <= 0.0:
		extent.y = MIN_UV_EXTENT
	if not is_finite(low.x) or not is_finite(low.y):
		low = Vector2.ZERO
	_uv_bounds = Rect2(low, extent)


## The part of the control the face is drawn into.
func _canvas_rect() -> Rect2:
	var inner := size - Vector2(CANVAS_MARGIN, CANVAS_MARGIN) * 2.0
	inner.x = maxf(inner.x, 1.0)
	inner.y = maxf(inner.y, 1.0)
	return Rect2(Vector2(CANVAS_MARGIN, CANVAS_MARGIN), inner)


func _gui_input(event: InputEvent) -> void:
	if _face == null:
		return
	if event is InputEventMouseButton:
		var mouse = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag_index = _find_nearest_uv_index(mouse)
				queue_redraw()
			else:
				_drag_index = -1
				queue_redraw()
	if event is InputEventMouseMotion:
		if _drag_index >= 0 and _drag_index < _face.custom_uvs.size():
			# Constrained in screen space, which is the canvas the mapper can see.
			# The old 0..1 clamp was in UV space and had nothing to do with the
			# face's own range.
			var canvas := _canvas_rect()
			var point := Vector2(
				clampf(event.position.x, canvas.position.x, canvas.end.x),
				clampf(event.position.y, canvas.position.y, canvas.end.y)
			)
			var uv := _screen_to_uv(point)
			if snap_enabled and not event.is_command_or_control_pressed():
				uv = _snapped_uv(uv)
			_face.custom_uvs[_drag_index] = uv
			emit_signal("uv_changed", _face)
			queue_redraw()


func _draw() -> void:
	if _face == null:
		return
	var uv_points = _face.custom_uvs
	if uv_points.is_empty():
		return
	var canvas := _canvas_rect()
	if _texture:
		# The region runs past the texture's own edge on purpose, and wrapping
		# fills it with repeats, so it is not clipped to the texture.
		draw_texture_rect_region(
			_texture, canvas, _texture_source_rect(), texture_tint, false, false
		)
	for line in _grid_lines(0):
		var x: float = _uv_to_screen(Vector2(line["at"], 0.0)).x
		draw_line(
			Vector2(x, canvas.position.y), Vector2(x, canvas.end.y), _grid_line_color(line), 1.0
		)
	for line in _grid_lines(1):
		var y: float = _uv_to_screen(Vector2(0.0, line["at"])).y
		draw_line(
			Vector2(canvas.position.x, y), Vector2(canvas.end.x, y), _grid_line_color(line), 1.0
		)
	var verts = uv_points
	var count = verts.size()
	for i in range(count):
		var a = _uv_to_screen(verts[i])
		var b = _uv_to_screen(verts[(i + 1) % count])
		draw_line(a, b, line_color, 1.5)
	for i in range(count):
		var p = _uv_to_screen(verts[i])
		var color = point_color_selected if i == _drag_index else point_color
		draw_circle(p, point_radius, color)


func _find_nearest_uv_index(pos: Vector2) -> int:
	var uv_points = _face.custom_uvs
	var best = -1
	var best_dist = point_radius * point_radius
	for i in range(uv_points.size()):
		var p = _uv_to_screen(uv_points[i])
		var d = p.distance_squared_to(pos)
		if d <= best_dist:
			best_dist = d
			best = i
	return best


## V runs down the canvas, the way it runs down an image, so a face is drawn
## the way up its texture is. It ran up the canvas while V ran up the walls,
## which drew every texture on a wall upside down (#907).
func _uv_to_screen(uv: Vector2) -> Vector2:
	var canvas := _canvas_rect()
	var fx := (uv.x - _uv_bounds.position.x) / _uv_bounds.size.x
	var fy := (uv.y - _uv_bounds.position.y) / _uv_bounds.size.y
	return canvas.position + Vector2(fx * canvas.size.x, fy * canvas.size.y)


func _screen_to_uv(pos: Vector2) -> Vector2:
	var canvas := _canvas_rect()
	var fx := (pos.x - canvas.position.x) / canvas.size.x
	var fy := (pos.y - canvas.position.y) / canvas.size.y
	return _uv_bounds.position + Vector2(fx * _uv_bounds.size.x, fy * _uv_bounds.size.y)


## The part of the texture behind the canvas, in its pixels. One UV unit is one
## repeat, so the face's UV bounds scaled by the texture's size are that part, and
## with sampling wrapping it is tiled once per repeat. V runs down both, so the
## top of the texture is at the top of the canvas.
func _texture_source_rect() -> Rect2:
	if _texture == null:
		return Rect2()
	var texels := _texture.get_size()
	return Rect2(_uv_bounds.position * texels, _uv_bounds.size * texels)


## The grid lines across one axis (0 for U, 1 for V) inside the canvas, each
## `{"at": its UV value, "unit": whether it falls on a whole repeat}`.
##
## Lines at the step when they are at least `MIN_GRID_SPACING` pixels apart. When
## they are closer, the whole repeats alone if those are far enough apart, and
## otherwise none. None while snapping is off: the grid is what a drag snaps to.
func _grid_lines(axis: int) -> Array:
	var lines: Array = []
	if not snap_enabled or not is_finite(snap_step) or snap_step <= 0.0:
		return lines
	var low: float = _uv_bounds.position[axis]
	var high: float = _uv_bounds.end[axis]
	var pixels_per_unit: float = _canvas_rect().size[axis] / _uv_bounds.size[axis]
	var spacing := snap_step
	if spacing * pixels_per_unit < MIN_GRID_SPACING:
		spacing = 1.0
		if snap_step >= 1.0 or pixels_per_unit < MIN_GRID_SPACING:
			return lines
	var first := int(ceilf(low / spacing - 0.000001))
	var last := int(floorf(high / spacing + 0.000001))
	for i in range(first, last + 1):
		var at := float(i) * spacing
		lines.append({"at": at, "unit": is_equal_approx(at, roundf(at))})
	return lines


func _grid_line_color(line: Dictionary) -> Color:
	return grid_unit_color if bool(line["unit"]) else grid_color


## `uv` on the nearest multiple of the snap step on each axis, kept on the canvas
## the drag is held to.
func _snapped_uv(uv: Vector2) -> Vector2:
	return Vector2(
		_snapped_axis(uv.x, _uv_bounds.position.x, _uv_bounds.end.x),
		_snapped_axis(uv.y, _uv_bounds.position.y, _uv_bounds.end.y)
	)


## The nearest multiple past the canvas's edge gives way to the one inside it. An
## axis with no multiple inside the canvas is left where the cursor put it.
func _snapped_axis(value: float, low: float, high: float) -> float:
	if not is_finite(snap_step) or snap_step <= 0.0:
		return value
	# A face's edge read back from its UVs can sit a rounding error short of the
	# multiple it is on, which is still on the canvas.
	var slack := snap_step * 0.001
	var on_step := roundf(value / snap_step) * snap_step
	if on_step > high + slack:
		on_step = floorf(high / snap_step) * snap_step
	elif on_step < low - slack:
		on_step = ceilf(low / snap_step) * snap_step
	if on_step < low - slack or on_step > high + slack:
		return value
	return on_step
