@tool
class_name HFClipPreview
extends RefCounted
## Real-time preview showing the two resulting pieces from a clip operation,
## plus a translucent split plane.  Wireframe boxes show the two halves;
## a quad mesh shows the cut plane itself.

const DraftBrush = preload("../brush_instance.gd")

var root: Node3D  # LevelRoot — untyped to avoid circular preload

var _preview_container: Node3D
var _piece_a_mesh: MeshInstance3D
var _piece_b_mesh: MeshInstance3D
var _plane_mesh: MeshInstance3D
var _wire_material: StandardMaterial3D
var _plane_material: StandardMaterial3D
var _enabled: bool = false

## Current preview parameters
var _brush_id: String = ""
var _axis: int = 1  # 0=X, 1=Y, 2=Z
var _split_pos: float = 0.0


func _init(p_root: Node3D) -> void:
	root = p_root
	# Wireframe for the two resulting pieces — cyan
	_wire_material = StandardMaterial3D.new()
	_wire_material.albedo_color = Color(0.2, 0.8, 1.0, 0.7)
	_wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wire_material.no_depth_test = true

	# Semi-transparent plane showing the cut surface — orange
	_plane_material = StandardMaterial3D.new()
	_plane_material.albedo_color = Color(1.0, 0.6, 0.1, 0.3)
	_plane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plane_material.no_depth_test = true
	_plane_material.cull_mode = BaseMaterial3D.CULL_DISABLED


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


## Show preview for a clip operation on the given brush.
func show_preview(brush_id: String, axis: int, split_pos: float) -> void:
	_brush_id = brush_id
	_axis = axis
	_split_pos = split_pos
	set_enabled(true)
	_rebuild()


## Update split position without changing brush/axis (for interactive dragging).
func update_split(split_pos: float) -> void:
	_split_pos = split_pos
	if _enabled:
		_rebuild()


## Hide the preview.
func clear() -> void:
	_brush_id = ""
	if _piece_a_mesh and is_instance_valid(_piece_a_mesh):
		_piece_a_mesh.visible = false
	if _piece_b_mesh and is_instance_valid(_piece_b_mesh):
		_piece_b_mesh.visible = false
	if _plane_mesh and is_instance_valid(_plane_mesh):
		_plane_mesh.visible = false
	if _preview_container and is_instance_valid(_preview_container):
		_preview_container.visible = false


## Free all resources immediately.
func destroy() -> void:
	if _preview_container and is_instance_valid(_preview_container):
		if _preview_container.get_parent():
			_preview_container.get_parent().remove_child(_preview_container)
		_preview_container.free()
	_preview_container = null
	_piece_a_mesh = null
	_piece_b_mesh = null
	_plane_mesh = null
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
	var pos: Vector3 = draft.global_position
	var half: Vector3 = draft.size * 0.5

	# Compute brush min/max along clip axis
	var brush_min: float
	var brush_max: float
	match _axis:
		0:
			brush_min = pos.x - half.x
			brush_max = pos.x + half.x
		1:
			brush_min = pos.y - half.y
			brush_max = pos.y + half.y
		_:
			brush_min = pos.z - half.z
			brush_max = pos.z + half.z

	# Snap split position
	var snap: float = root.grid_snap if root.grid_snap > 0.0 else 0.0
	var split: float = _split_pos
	if snap > 0.0:
		split = snapped(split, snap)

	var margin: float = snap if snap > 0.0 else 0.01
	if split <= brush_min + margin or split >= brush_max - margin:
		clear()
		return

	# Compute the two piece AABBs
	var size_a: Vector3 = draft.size.abs()
	var size_b: Vector3 = draft.size.abs()
	var center_a: Vector3 = pos
	var center_b: Vector3 = pos

	match _axis:
		0:
			size_a.x = split - brush_min
			size_b.x = brush_max - split
			center_a.x = (brush_min + split) / 2.0
			center_b.x = (split + brush_max) / 2.0
		1:
			size_a.y = split - brush_min
			size_b.y = brush_max - split
			center_a.y = (brush_min + split) / 2.0
			center_b.y = (split + brush_max) / 2.0
		_:
			size_a.z = split - brush_min
			size_b.z = brush_max - split
			center_a.z = (brush_min + split) / 2.0
			center_b.z = (split + brush_max) / 2.0

	var aabb_a := AABB(center_a - size_a * 0.5, size_a)
	var aabb_b := AABB(center_b - size_b * 0.5, size_b)

	_ensure_container()

	# Update piece wireframes
	_piece_a_mesh.mesh = _build_wireframe_mesh(aabb_a)
	_piece_a_mesh.visible = true
	_piece_b_mesh.mesh = _build_wireframe_mesh(aabb_b)
	_piece_b_mesh.visible = true

	# Update split plane quad
	_plane_mesh.mesh = _build_plane_mesh(pos, draft.size, _axis, split)
	_plane_mesh.visible = true
	_preview_container.visible = true


func _ensure_container() -> void:
	if _preview_container and is_instance_valid(_preview_container):
		_preview_container.visible = true
		return
	_preview_container = Node3D.new()
	_preview_container.name = "ClipPreview"
	root.add_child(_preview_container)

	_piece_a_mesh = MeshInstance3D.new()
	_piece_a_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_piece_a_mesh.material_override = _wire_material
	_preview_container.add_child(_piece_a_mesh)

	_piece_b_mesh = MeshInstance3D.new()
	_piece_b_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_piece_b_mesh.material_override = _wire_material
	_preview_container.add_child(_piece_b_mesh)

	_plane_mesh = MeshInstance3D.new()
	_plane_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plane_mesh.material_override = _plane_material
	_preview_container.add_child(_plane_mesh)


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


## Build a translucent quad representing the split plane.
func _build_plane_mesh(center: Vector3, size: Vector3, axis: int, split: float) -> ImmediateMesh:
	var im = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := size * 0.5
	var corners: Array = []

	match axis:
		0:  # X — plane is YZ
			corners = [
				Vector3(split, center.y - half.y, center.z - half.z),
				Vector3(split, center.y + half.y, center.z - half.z),
				Vector3(split, center.y + half.y, center.z + half.z),
				Vector3(split, center.y - half.y, center.z + half.z),
			]
		1:  # Y — plane is XZ
			corners = [
				Vector3(center.x - half.x, split, center.z - half.z),
				Vector3(center.x + half.x, split, center.z - half.z),
				Vector3(center.x + half.x, split, center.z + half.z),
				Vector3(center.x - half.x, split, center.z + half.z),
			]
		_:  # Z — plane is XY
			corners = [
				Vector3(center.x - half.x, center.y - half.y, split),
				Vector3(center.x + half.x, center.y - half.y, split),
				Vector3(center.x + half.x, center.y + half.y, split),
				Vector3(center.x - half.x, center.y + half.y, split),
			]

	# Two triangles for the quad (CW winding for both sides via CULL_DISABLED)
	im.surface_add_vertex(corners[0])
	im.surface_add_vertex(corners[1])
	im.surface_add_vertex(corners[2])
	im.surface_add_vertex(corners[0])
	im.surface_add_vertex(corners[2])
	im.surface_add_vertex(corners[3])

	im.surface_end()
	return im
