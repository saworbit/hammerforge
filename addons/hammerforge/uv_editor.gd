@tool
extends Control
class_name UVEditor

signal uv_changed(face)

const FaceData = preload("face_data.gd")

@export var point_radius: float = 6.0
@export var line_color: Color = Color(0.8, 0.9, 1.0, 0.9)
@export var point_color: Color = Color(0.2, 0.9, 0.4, 1.0)
@export var point_color_selected: Color = Color(1.0, 0.8, 0.2, 1.0)

## Space left around the face so the outermost points are inside the control and
## can be grabbed rather than sitting on its edge.
const CANVAS_MARGIN := 12.0

## The extent a degenerate axis is given. A CYLINDRICAL projection, or any face
## whose UV span is zero in one direction, has nothing to divide by otherwise.
const MIN_UV_EXTENT := 1.0

var _face: FaceData = null
var _drag_index: int = -1

## The face's own UV bounding box, which is what the canvas shows.
##
## A HammerForge UV is a world coordinate, not a 0..1 fraction:
## `_project_uvs_for_vertices()` reads `Vector2(v.x, v.y)` straight off the
## vertex, so a 64 unit box spans 64. Drawing it as a fraction of the control put
## every point far outside, which is why the panel was blank on every brush, and
## clamping a drag to 0..1 collapsed whatever it was into the corner and left the
## face's UV quad no longer a quad.
##
## Held rather than recomputed per draw, so the canvas does not rescale under the
## cursor while a point is being dragged.
var _uv_bounds := Rect2(Vector2.ZERO, Vector2(MIN_UV_EXTENT, MIN_UV_EXTENT))


func set_face(face: FaceData) -> void:
	_face = face
	if _face:
		_face.ensure_custom_uvs()
	_fit_bounds_to_face()
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
			_face.custom_uvs[_drag_index] = _screen_to_uv(point)
			emit_signal("uv_changed", _face)
			queue_redraw()


func _draw() -> void:
	if _face == null:
		return
	var uv_points = _face.custom_uvs
	if uv_points.is_empty():
		return
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


func _uv_to_screen(uv: Vector2) -> Vector2:
	var canvas := _canvas_rect()
	var fx := (uv.x - _uv_bounds.position.x) / _uv_bounds.size.x
	var fy := (uv.y - _uv_bounds.position.y) / _uv_bounds.size.y
	return canvas.position + Vector2(fx * canvas.size.x, (1.0 - fy) * canvas.size.y)


func _screen_to_uv(pos: Vector2) -> Vector2:
	var canvas := _canvas_rect()
	var fx := (pos.x - canvas.position.x) / canvas.size.x
	var fy := 1.0 - ((pos.y - canvas.position.y) / canvas.size.y)
	return _uv_bounds.position + Vector2(fx * _uv_bounds.size.x, fy * _uv_bounds.size.y)
