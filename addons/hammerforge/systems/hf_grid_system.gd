@tool
extends RefCounted
class_name HFGridSystem

var root: Node3D


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


func update_grid_transform(axis: int, origin: Vector3) -> void:
	if not root.grid_mesh or not root.grid_mesh.is_inside_tree():
		return
	root.grid_plane_axis = axis
	root.grid_plane_origin = origin
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
	if origin == Vector3.ZERO and root.last_brush_center != Vector3.ZERO:
		origin = root.last_brush_center
	update_grid_transform(axis, origin)


func record_last_brush(center: Vector3) -> void:
	root.last_brush_center = center
	root.grid_axis_preference = effective_grid_axis()
	set_grid_plane_origin(center, root.grid_axis_preference)


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
		var hit = intersect_axis_plane(camera, mouse_pos, axis, root.grid_plane_origin)
		if hit != null:
			var snapped = root._snap_point(hit)
			set_grid_plane_origin(snapped, axis)
			return
	update_grid_transform(axis, root.grid_plane_origin)
