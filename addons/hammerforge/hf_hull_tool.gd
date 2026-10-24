@tool
class_name HFHullTool
extends "hf_editor_tool.gd"

## Click points, on faces or on the grid, and make one brush from their convex
## hull (#1715). A rock, an odd corner fill or a wedge between two posts is
## easier to click than to draw, and Polygon makes prisms only.
##
## A double click on a face adds all its corners. Shift and a drag on a face
## copies its corners out along its normal, so a face becomes a solid in one
## gesture. Enter makes the brush, Backspace or a right click takes the last
## point back, and Escape lets them all go. Points that hold no solid are refused
## with the reason.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFHullType = preload("res://addons/hammerforge/hf_hull.gd")
const HFOutlineUtilType = preload("res://addons/hammerforge/hf_outline_util.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
## How big the cross on each placed point is drawn, in world units.
const MARK := 0.15
const HULL_COLOR := Color(0.3, 0.9, 0.3, 0.6)

var _points := PackedVector3Array()
## How many points each click put in, so Backspace can take a face's corners
## back as it took them.
var _batches: Array[int] = []
var _cursor := Vector3.ZERO
var _cursor_valid := false
## The last press put one point in, so the double click it begins can take it out
## again and put the face's corners in instead.
var _last_press_added := false
## A Shift drag on a face: `{"corners", "normal", "start"}`, the face's corners in
## world space, its normal, and how far along it the press was. Empty otherwise.
var _pull: Dictionary = {}
var _pull_distance := 0.0
var _mesh_instance: MeshInstance3D = null


func tool_name() -> String:
	return "Hull"


func tool_id() -> int:
	return 105


func keymap_action() -> String:
	return "tool_hull"


func activate(p_root: Node3D, p_camera: Camera3D) -> void:
	super.activate(p_root, p_camera)
	_reset()


func deactivate() -> void:
	_reset()
	super.deactivate()


func has_work_in_progress() -> bool:
	return not _points.is_empty() or not _pull.is_empty()


func shows_draw_hover() -> bool:
	return _points.is_empty() and _pull.is_empty()


## The points placed so far, in world space.
func get_points() -> PackedVector3Array:
	return _points


func handle_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
	if not root or not camera:
		return PASS
	if event is InputEventKey:
		return handle_keyboard(event as InputEventKey)
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			return _take_back()
		if button.button_index != MOUSE_BUTTON_LEFT:
			return PASS
		if not button.pressed:
			return _end_pull() if not _pull.is_empty() else PASS
		if button.double_click:
			return _add_face_corners(camera, mouse_pos)
		if button.shift_pressed and _begin_pull(camera, mouse_pos):
			return STOP
		return _add_point(camera, mouse_pos)
	if event is InputEventMouseMotion:
		if not _pull.is_empty():
			_pull_distance = _pulled_to(camera, mouse_pos)
			_update_preview()
			return STOP
		var start := first_point_start(camera, mouse_pos)
		_cursor_valid = not start.is_empty()
		if _cursor_valid:
			_cursor = start["point"]
		_update_preview()
	return PASS


func handle_keyboard(event: InputEventKey) -> int:
	if not event.pressed or event.echo:
		return PASS
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if _points.is_empty():
				return PASS
			finish()
			return STOP
		KEY_BACKSPACE:
			if _points.is_empty():
				return PASS
			return _take_back()
		KEY_ESCAPE:
			if not has_work_in_progress():
				return PASS
			_reset()
			return STOP
	return PASS


func get_shortcut_hud_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("-- Hull Tool --")
	lines.append("Click: Add a point (%d placed)" % _points.size())
	lines.append("Double click a face: Add its corners")
	lines.append("Shift drag a face: Pull its corners out")
	lines.append("Enter: Make the brush")
	lines.append("Backspace/RMB: Take back")
	lines.append("Esc: Cancel")
	return lines


## Make the brush the hull of the points holds, as one undo step. Points that
## hold no solid are refused with the reason and kept, so one more can be added.
func finish() -> bool:
	var hull: Dictionary = HFHullType.of(_points)
	if not hull["ok"]:
		_warn(hull["reason"])
		return false
	var info := brush_info(hull["faces"])
	if root and root.get("brush_system"):
		var pre_state: Dictionary = {}
		if root.get("state_system") and root.state_system.has_method("capture_state"):
			pre_state = root.state_system.capture_state(true)
		root.brush_system.give_active_material(info)
		root.brush_system.create_brush_from_info(info)
		if not pre_state.is_empty():
			HFUndoHelper.commit_completed(
				undo_redo, root, "Create Hull Brush", pre_state, history_callback
			)
		elif history_callback.is_valid():
			history_callback.call("Create Hull Brush")
	_reset()
	return true


## What `create_brush_from_info()` takes to build `faces`, a hull in world space,
## as a brush centred on its own bounds.
static func brush_info(faces: Array) -> Dictionary:
	var bounds := AABB()
	var seeded := false
	for face in faces:
		for corner in (face as FaceData).local_verts:
			if seeded:
				bounds = bounds.expand(corner)
			else:
				bounds = AABB(corner, Vector3.ZERO)
				seeded = true
	var centre := bounds.get_center()
	var dicts: Array = []
	for face in faces:
		var built := face as FaceData
		var moved := PackedVector3Array()
		for corner in built.local_verts:
			moved.append(corner - centre)
		built.local_verts = moved
		built.ensure_geometry()
		dicts.append(built.to_dict())
	return {
		"shape": LevelRootType.BrushShape.CUSTOM,
		"size": bounds.size,
		"operation": CSGShape3D.OPERATION_UNION,
		"center": centre,
		"faces": dicts,
	}


func _add_point(camera: Camera3D, mouse_pos: Vector2) -> int:
	_last_press_added = false
	var start := first_point_start(camera, mouse_pos)
	if start.is_empty():
		return PASS
	var point: Vector3 = start["point"]
	_cursor = point
	_cursor_valid = true
	if _points.has(point):
		return STOP
	_points.append(point)
	_batches.append(1)
	_last_press_added = true
	_update_preview()
	return STOP


func _add_face_corners(camera: Camera3D, mouse_pos: Vector2) -> int:
	var face := _face_under(camera, mouse_pos)
	if face.is_empty():
		return _add_point(camera, mouse_pos)
	# The first press of the double click put a point in; the corners stand for it.
	if _last_press_added and not _batches.is_empty():
		_points.resize(_points.size() - _batches.pop_back())
	_last_press_added = false
	_add_batch(face["corners"])
	return STOP


func _begin_pull(camera: Camera3D, mouse_pos: Vector2) -> bool:
	var face := _face_under(camera, mouse_pos)
	if face.is_empty():
		return false
	var normal: Vector3 = face["normal"]
	var corners: PackedVector3Array = face["corners"]
	_pull = {"corners": corners, "normal": normal, "origin": _centre_of(corners)}
	_pull["start"] = _along(camera, mouse_pos, _pull["origin"], normal)
	_pull_distance = 0.0
	_last_press_added = false
	_update_preview()
	return true


func _end_pull() -> int:
	var corners: PackedVector3Array = _pull["corners"]
	var normal: Vector3 = _pull["normal"]
	var batch := PackedVector3Array(corners)
	if not is_zero_approx(_pull_distance):
		for corner in corners:
			batch.append(corner + normal * _pull_distance)
	_pull = {}
	_pull_distance = 0.0
	_add_batch(batch)
	return STOP


## How far along the face's normal the cursor is now from where the drag began,
## held to the grid.
func _pulled_to(camera: Camera3D, mouse_pos: Vector2) -> float:
	var distance: float = _along(camera, mouse_pos, _pull["origin"], _pull["normal"])
	distance -= float(_pull["start"])
	var step := grid_step()
	return snappedf(distance, step) if step > 0.0 else distance


## Where on the line through `origin` along `direction` the camera ray through
## `mouse_pos` passes closest, as a distance along it.
static func _along(
	camera: Camera3D, mouse_pos: Vector2, origin: Vector3, direction: Vector3
) -> float:
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)
	var between := origin - ray_origin
	var b := direction.dot(ray_direction)
	var d := direction.dot(between)
	var e := ray_direction.dot(between)
	var denominator := direction.dot(direction) * ray_direction.dot(ray_direction) - b * b
	if absf(denominator) < 1e-6:
		return 0.0
	return (b * e - ray_direction.dot(ray_direction) * d) / denominator


func _add_batch(batch: PackedVector3Array) -> void:
	var added := 0
	for point in batch:
		if not _points.has(point):
			_points.append(point)
			added += 1
	if added > 0:
		_batches.append(added)
	_update_preview()


func _take_back() -> int:
	if not _pull.is_empty():
		_pull = {}
		_update_preview()
		return STOP
	if _batches.is_empty():
		return PASS
	_points.resize(_points.size() - _batches.pop_back())
	_last_press_added = false
	_update_preview()
	return STOP


## The face under the cursor as `{"corners", "normal"}` in world space, or {}.
func _face_under(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	if not root.has_method("pick_face"):
		return {}
	var hit: Dictionary = root.pick_face(camera, mouse_pos)
	var brush = hit.get("brush", null)
	var index := int(hit.get("face_idx", -1))
	if brush == null or index < 0 or index >= (brush.faces as Array).size():
		return {}
	var face: FaceData = brush.faces[index]
	var place: Transform3D = brush.global_transform
	var corners := PackedVector3Array()
	for corner in face.local_verts:
		corners.append(place * corner)
	return {"corners": corners, "normal": face.normal_through(place.basis).normalized()}


static func _centre_of(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	return sum / maxf(1.0, float(points.size()))


func _warn(message: String) -> void:
	if root and root.has_signal("user_message"):
		root.emit_signal("user_message", message, 1)


func _update_preview() -> void:
	if not root:
		return
	var lines := PackedVector3Array()
	var shown := PackedVector3Array(_points)
	if not _pull.is_empty():
		for corner in _pull["corners"]:
			shown.append(corner)
			shown.append(corner + (_pull["normal"] as Vector3) * _pull_distance)
	for point in shown:
		_cross(lines, point, MARK)
	var hull: Dictionary = HFHullType.of(shown)
	if hull["ok"]:
		lines.append_array(HFOutlineUtilType.face_boundary_lines(hull["faces"]))
	elif shown.size() >= 2:
		for i in range(1, shown.size()):
			lines.append(shown[i - 1])
			lines.append(shown[i])
	if _cursor_valid and _pull.is_empty() and not _points.is_empty():
		lines.append(_points[_points.size() - 1])
		lines.append(_cursor)
	if lines.is_empty():
		_clear_visuals()
		return
	if _mesh_instance == null or not is_instance_valid(_mesh_instance):
		_mesh_instance = make_overlay_mesh(root, "_HullToolPreview")
	var mesh := _mesh_instance.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in lines.size():
		mesh.surface_set_color(HULL_COLOR)
		mesh.surface_add_vertex(lines[i])
	mesh.surface_end()


static func _cross(lines: PackedVector3Array, at: Vector3, size: float) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		lines.append(at - axis * size)
		lines.append(at + axis * size)


func _clear_visuals() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		free_overlay_mesh(_mesh_instance)
	_mesh_instance = null


func _reset() -> void:
	_points = PackedVector3Array()
	_batches.clear()
	_pull = {}
	_pull_distance = 0.0
	_last_press_added = false
	_cursor_valid = false
	_clear_visuals()
