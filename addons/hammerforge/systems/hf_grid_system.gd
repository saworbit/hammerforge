@tool
extends RefCounted
class_name HFGridSystem

var root: Node3D
## View state only. A manual plane stays put until Reset Grid.
var _position_held := false


func _init(level_root: Node3D) -> void:
	root = level_root


func setup_editor_grid() -> void:
	if not Engine.is_editor_hint():
		var existing = root.get_node_or_null("EditorGrid") as MeshInstance3D
		if existing:
			existing.queue_free()
		return
	root.grid_mesh = root.get_node_or_null("EditorGrid") as MeshInstance3D
	if not root.grid_mesh:
		root.grid_mesh = MeshInstance3D.new()
		root.grid_mesh.name = "EditorGrid"
		root.add_child(root.grid_mesh)
	root.grid_mesh.owner = null
	var plane := PlaneMesh.new()
	plane.size = Vector2(root.grid_plane_size, root.grid_plane_size)
	root.grid_mesh.mesh = plane
	root.grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not root.grid_material:
		root.grid_material = ShaderMaterial.new()
		root.grid_material.shader = preload("../editor_grid.gdshader")
	root.grid_mesh.material_override = root.grid_material
	root.grid_mesh.visible = root._grid_visible
	root.grid_plane_origin = root.global_position
	root.grid_axis_preference = root.AxisLock.Y
	update_grid_material()
	update_grid_transform(root.grid_axis_preference, root.grid_plane_origin)


func set_grid_visible(value: bool) -> void:
	if root._grid_visible == value:
		return
	root._grid_visible = value
	if root.grid_mesh and root.grid_mesh.is_inside_tree():
		root.grid_mesh.visible = root._grid_visible


func update_grid_material() -> void:
	if not root.grid_material:
		return
	var size = max(root._grid_snap, 0.001)
	root.grid_material.set_shader_parameter("snap_size", size)
	root.grid_material.set_shader_parameter("grid_color", root.grid_color)
	root.grid_material.set_shader_parameter(
		"major_line_frequency", float(root.grid_major_line_frequency)
	)


## Brighten the two grid lines through `point`, where a draw would start
## (#1400). The point is in the world, and the shader finds it on the grid
## wherever the grid has moved to since, so a grid that follows the cursor
## keeps the lines on it.
func set_cursor(point: Vector3, shown: bool) -> void:
	if not root.grid_material:
		return
	root.grid_material.set_shader_parameter("cursor_point", point)
	root.grid_material.set_shader_parameter("cursor_visible", shown)


func update_grid_transform(axis: int, origin: Vector3) -> void:
	root.grid_plane_origin = origin
	if not root.grid_mesh or not root.grid_mesh.is_inside_tree():
		return
	var rot = Vector3.ZERO
	match axis:
		root.AxisLock.X:
			rot = Vector3(0.0, 0.0, -90.0)
		root.AxisLock.Z:
			rot = Vector3(90.0, 0.0, 0.0)
		_:
			rot = Vector3.ZERO
	root.grid_mesh.rotation_degrees = rot
	root.grid_mesh.global_position = origin


func effective_grid_axis() -> int:
	if root.manual_axis_lock and root.axis_lock != root.AxisLock.NONE:
		return root.axis_lock
	return root.grid_axis_preference


func set_grid_plane_origin(origin: Vector3, axis: int) -> void:
	update_grid_transform(axis, origin)


func refresh_grid_plane() -> void:
	if not Engine.is_editor_hint():
		return
	var axis = effective_grid_axis()
	var origin = root.grid_plane_origin
	if not _position_held and origin == Vector3.ZERO and root.last_brush_center != Vector3.ZERO:
		origin = root.last_brush_center
	update_grid_transform(axis, origin)


## Record a completed draw's world-space base, despite the legacy center name.
## Restore/import callers must not move the construction plane.
func record_last_brush(center: Vector3) -> void:
	root.last_brush_center = center
	if _position_held:
		return
	root.grid_axis_preference = effective_grid_axis()
	set_grid_plane_origin(center, root.grid_axis_preference)


## The same commands for keys, the palette and dock buttons. No level mutation
## or undo step: these only choose where a later draw starts.
## `grid_up`/`grid_down` move one step; `grid_reset` returns to the root origin
## on Y. `grid_align` uses selected vertices, then a selected face's dominant
## world axis through its center, then selected brush bounds' top; none resets.
## The held plane is editor view state and is not serialized into the level.
func run_command(action: String, nodes: Array = []) -> void:
	match action:
		"grid_up", "grid_down":
			var axis := effective_grid_axis()
			var point: Vector3 = root.grid_plane_origin
			point[axis - 1] += maxf(root.grid_snap, 0.001) * (1.0 if action == "grid_up" else -1.0)
			_hold_plane(point, axis)
		"grid_reset":
			_position_held = false
			root.grid_axis_preference = root.AxisLock.Y
			root.manual_axis_lock = false
			root.axis_lock = root.AxisLock.NONE
			root.last_brush_center = root.global_position
			set_grid_plane_origin(root.global_position, root.AxisLock.Y)
		"grid_align":
			_align_to_selection(nodes)


## The grid point nearest `point`: a whole number of `step`s from the world
## origin on each axis, the points a draw snaps to (`LevelRoot._snap_point()`).
## A held drawing plane changes where a draw starts, not where the points are:
## `_hold_plane()` and `follow_cursor()` keep its origin on them across the
## plane, and only its height may sit between two.
static func nearest_grid_point(point: Vector3, step: float) -> Vector3:
	if not (step > 0.0):
		return point
	return point.snapped(Vector3.ONE * step)


## Whether Snap to Grid has a grid to snap to. A grid snap of 0 turns snapping
## off, and then there are no grid points to move anything onto.
func can_snap_to_grid() -> HFOpResult:
	if root.grid_snap > 0.0:
		return HFOpResult.success()
	return HFOpResult.fail("Snap to Grid: grid snap is off", "Set a grid size first")


func _hold_plane(point: Vector3, axis: int) -> void:
	_position_held = true
	root.grid_axis_preference = axis
	if root.manual_axis_lock:
		root.axis_lock = axis
	var snap: float = maxf(root.grid_snap, 0.001)
	var origin := point.snapped(Vector3.ONE * snap)
	origin[axis - 1] = point[axis - 1]
	set_grid_plane_origin(origin, axis)


func _align_to_selection(nodes: Array) -> void:
	var points: PackedVector3Array = root.vertex_system.get_selected_world_positions()
	var axis := effective_grid_axis()
	if points.is_empty():
		var picked: Dictionary = root.get_primary_selected_face()
		if not picked.is_empty():
			var brush: Node3D = picked["brush"]
			var faces: Array = brush.get_faces()
			var index := int(picked["face_idx"])
			if index >= 0 and index < faces.size():
				var face: FaceData = faces[index]
				face.ensure_geometry()
				var normal := face.normal_through(brush.global_basis)
				axis = normal.abs().max_axis_index() + 1
				for vertex in face.local_verts:
					points.append(brush.global_transform * vertex)
	if not points.is_empty():
		var middle := Vector3.ZERO
		for point in points:
			middle += point
		_hold_plane(middle / float(points.size()), axis)
		return
	var bounds := AABB()
	var found := false
	for node in nodes:
		if not is_instance_valid(node) or not root.is_brush_node(node):
			continue
		var box: AABB = root.brush_system.world_bounds_of(node)
		bounds = bounds.merge(box) if found else box
		found = true
	if found:
		var point := bounds.get_center()
		point.y = bounds.end.y
		_hold_plane(point, root.AxisLock.Y)
	else:
		run_command("grid_reset")


## Snap the other axes without rounding an explicitly aligned plane away. Only a
## hit on the plane itself keeps the plane's height: a draw that starts on a
## draft face or a physics surface starts on that surface. A `drag` snaps with
## the grid the drag's held keys ask for (#1431).
func snap_draw_hit(hit: Dictionary, drag := false) -> Vector3:
	var point: Vector3 = (
		root._snap_drag_point(hit["position"]) if drag else root._snap_point(hit["position"])
	)
	if _position_held and hit.get(root.CONSTRUCTION_PLANE_HIT, false):
		var index := effective_grid_axis() - 1
		point[index] = root.grid_plane_origin[index]
	return point


## Follow only along the plane, including when its exact height is off-grid.
func follow_cursor(camera: Camera3D, mouse_pos: Vector2) -> void:
	var axis := effective_grid_axis()
	var hit = intersect_axis_plane(camera, mouse_pos, axis, root.grid_plane_origin)
	if hit is Vector3:
		var point: Vector3 = hit.snapped(Vector3.ONE * maxf(root.grid_snap, 0.001))
		point[axis - 1] = root.grid_plane_origin[axis - 1]
		set_grid_plane_origin(point, axis)


func intersect_axis_plane(
	camera: Camera3D, mouse_pos: Vector2, axis: int, origin: Vector3
) -> Variant:
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	var normal = Vector3.UP
	var distance = origin.y
	match axis:
		root.AxisLock.X:
			normal = Vector3.RIGHT
			distance = origin.x
		root.AxisLock.Z:
			normal = Vector3.BACK
			distance = origin.z
		_:
			normal = Vector3.UP
			distance = origin.y
	var denom = normal.dot(dir)
	if abs(denom) < 0.0001:
		return null
	var t = (distance - normal.dot(from)) / denom
	if t < 0.0:
		return null
	return from + dir * t


func update_editor_grid(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not Engine.is_editor_hint():
		return
	if not root._grid_visible:
		return
	if not root.grid_mesh or not root.grid_mesh.is_inside_tree() or not camera:
		return
	var axis = effective_grid_axis()
	if root.grid_follow_brush:
		follow_cursor(camera, mouse_pos)
		return
	update_grid_transform(axis, root.grid_plane_origin)
