@tool
class_name HFHollowPreview
extends RefCounted
## Real-time wireframe preview showing the 6 wall pieces that would result
## from a hollow operation.  Drawn in yellow wireframe over the original brush.

const DraftBrush = preload("../brush_instance.gd")

var root: Node3D  # LevelRoot — untyped to avoid circular preload

var _preview_container: Node3D
var _mesh_pool: Array = []  # Array[MeshInstance3D] — 6 walls max
var _active_count: int = 0
var _material: StandardMaterial3D
var _enabled: bool = false

## Current preview parameters
var _brush_id: String = ""
var _wall_thickness: float = 4.0


func _init(p_root: Node3D) -> void:
	root = p_root
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(1.0, 0.85, 0.2, 0.6)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true


func set_enabled(value: bool) -> void:
	if value == _enabled:
		return
	_enabled = value
	if _enabled:
		_ensure_container()
	else:
		clear()


func is_enabled() -> bool:
	return _enabled


## Show preview for a hollow operation on the given brush.
func show_preview(brush_id: String, wall_thickness: float) -> void:
	_brush_id = brush_id
	_wall_thickness = wall_thickness
	set_enabled(true)
	_rebuild()


## Update wall thickness dynamically (e.g. while user drags the SpinBox).
func update_thickness(wall_thickness: float) -> void:
	_wall_thickness = wall_thickness
	if _enabled:
		_rebuild()


## Hide the preview.
func clear() -> void:
	_brush_id = ""
	for i in _mesh_pool.size():
		if is_instance_valid(_mesh_pool[i]):
			_mesh_pool[i].visible = false
	_active_count = 0
	if _preview_container and is_instance_valid(_preview_container):
		_preview_container.visible = false


## Free all resources immediately.
func destroy() -> void:
	_mesh_pool.clear()
	_active_count = 0
	if _preview_container and is_instance_valid(_preview_container):
		if _preview_container.get_parent():
			_preview_container.get_parent().remove_child(_preview_container)
		_preview_container.free()
	_preview_container = null
	_enabled = false


func _rebuild() -> void:
	if not root or _brush_id == "":
		clear()
		return

	var brush = root.brush_system.find_brush_by_id(_brush_id)
	if not brush or not (brush is DraftBrush):
		clear()
		return

	var draft := brush as DraftBrush
	if draft.shape == root.BrushShape.CUSTOM:
		clear()
		return

	var size: Vector3 = draft.size
	var pos: Vector3 = draft.global_position
	var t: float = _wall_thickness

	# Validate thickness
	var min_dim: float = min(size.x, min(size.y, size.z))
	if t * 2.0 >= min_dim:
		clear()
		return

	# Compute 6 wall AABBs (same logic as brush_system.hollow_brush_by_id)
	var walls: Array = []  # Array[AABB]

	# Top wall
	var top_size := Vector3(size.x, t, size.z)
	var top_center := Vector3(pos.x, pos.y + (size.y - t) / 2.0, pos.z)
	walls.append(AABB(top_center - top_size * 0.5, top_size))

	# Bottom wall
	var bot_size := Vector3(size.x, t, size.z)
	var bot_center := Vector3(pos.x, pos.y - (size.y - t) / 2.0, pos.z)
	walls.append(AABB(bot_center - bot_size * 0.5, bot_size))

	# Left wall (X-)
	var left_size := Vector3(t, size.y - 2.0 * t, size.z)
	var left_center := Vector3(pos.x - (size.x - t) / 2.0, pos.y, pos.z)
	walls.append(AABB(left_center - left_size * 0.5, left_size))

	# Right wall (X+)
	var right_size := Vector3(t, size.y - 2.0 * t, size.z)
	var right_center := Vector3(pos.x + (size.x - t) / 2.0, pos.y, pos.z)
	walls.append(AABB(right_center - right_size * 0.5, right_size))

	# Front wall (Z+)
	var front_size := Vector3(size.x - 2.0 * t, size.y - 2.0 * t, t)
	var front_center := Vector3(pos.x, pos.y, pos.z + (size.z - t) / 2.0)
	walls.append(AABB(front_center - front_size * 0.5, front_size))

	# Back wall (Z-)
	var back_size := Vector3(size.x - 2.0 * t, size.y - 2.0 * t, t)
	var back_center := Vector3(pos.x, pos.y, pos.z - (size.z - t) / 2.0)
	walls.append(AABB(back_center - back_size * 0.5, back_size))

	_ensure_container()

	# Grow pool if needed
	while _mesh_pool.size() < walls.size():
		var mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _material
		_preview_container.add_child(mi)
		_mesh_pool.append(mi)

	# Update active wireframes
	for i in walls.size():
		var mi: MeshInstance3D = _mesh_pool[i]
		mi.mesh = _build_wireframe_mesh(walls[i])
		mi.visible = true

	# Hide unused
	for i in range(walls.size(), _mesh_pool.size()):
		if is_instance_valid(_mesh_pool[i]):
			_mesh_pool[i].visible = false

	_active_count = walls.size()
	_preview_container.visible = _active_count > 0


func _ensure_container() -> void:
	if _preview_container and is_instance_valid(_preview_container):
		_preview_container.visible = true
		return
	_preview_container = Node3D.new()
	_preview_container.name = "HollowPreview"
	root.add_child(_preview_container)


func _build_wireframe_mesh(aabb: AABB) -> ImmediateMesh:
	var im = ImmediateMesh.new()
	var min_pt = aabb.position
	var max_pt = aabb.position + aabb.size
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners = [
		Vector3(min_pt.x, min_pt.y, min_pt.z),
		Vector3(max_pt.x, min_pt.y, min_pt.z),
		Vector3(max_pt.x, max_pt.y, min_pt.z),
		Vector3(min_pt.x, max_pt.y, min_pt.z),
		Vector3(min_pt.x, min_pt.y, max_pt.z),
		Vector3(max_pt.x, min_pt.y, max_pt.z),
		Vector3(max_pt.x, max_pt.y, max_pt.z),
		Vector3(min_pt.x, max_pt.y, max_pt.z),
	]
	var edges = [
		[0, 1],
		[1, 2],
		[2, 3],
		[3, 0],
		[4, 5],
		[5, 6],
		[6, 7],
		[7, 4],
		[0, 4],
		[1, 5],
		[2, 6],
		[3, 7],
	]
	for edge in edges:
		im.surface_add_vertex(corners[edge[0]])
		im.surface_add_vertex(corners[edge[1]])
	im.surface_end()
	return im
