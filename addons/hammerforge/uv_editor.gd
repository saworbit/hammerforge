@tool
extends Control
class_name UVEditor

signal uv_changed(face)

const FaceData = preload("face_data.gd")

@export var point_radius: float = 6.0
@export var line_color: Color = Color(0.8, 0.9, 1.0, 0.9)
@export var point_color: Color = Color(0.2, 0.9, 0.4, 1.0)
@export var point_color_selected: Color = Color(1.0, 0.8, 0.2, 1.0)

var _face: FaceData = null
var _drag_index: int = -1


func set_face(face: FaceData) -> void:
	_face = face
	if _face:
		_face.ensure_custom_uvs()
	queue_redraw()


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
			var uv = _screen_to_uv(event.position)
			uv.x = clamp(uv.x, 0.0, 1.0)
			uv.y = clamp(uv.y, 0.0, 1.0)
			_face.custom_uvs[_drag_index] = uv
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
	var rect = Rect2(Vector2.ZERO, size)
	return rect.position + Vector2(uv.x * rect.size.x, (1.0 - uv.y) * rect.size.y)


func _screen_to_uv(pos: Vector2) -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2.ZERO
	var u = pos.x / size.x
	var v = 1.0 - (pos.y / size.y)
	return Vector2(u, v)
