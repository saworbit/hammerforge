@tool
class_name HFClipPreview
extends "hf_system.gd"
## Real-time preview showing the two resulting pieces from a clip operation,
## plus a translucent split plane.  Wireframe boxes show the two halves;
## a quad mesh shows the cut plane itself.

const DraftBrush = preload("../brush_instance.gd")
const HFOutlineUtil = preload("../hf_outline_util.gd")
const HFConvexClip = preload("../hf_convex_clip.gd")

var _preview_container: Node3D
var _piece_a_mesh: MeshInstance3D
var _piece_b_mesh: MeshInstance3D
var _plane_mesh: MeshInstance3D
var _wire_material: StandardMaterial3D
var _plane_material: StandardMaterial3D

## Current preview parameters
var _brush_id: String = ""
var _axis: int = 1  # 0=X, 1=Y, 2=Z
var _split_pos: float = 0.0


func _init(p_root: Node3D = null) -> void:
	super(p_root)
	_enabled = false
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

	# The preview must not promise a cut the tool will refuse. Ask the same
	# validator clip_brush_by_id uses instead of keeping a second copy of the
	# shape, rotation and bounds rules here.
	var check: HFOpResult = root.brush_system.can_clip_brush(_brush_id, _axis, _split_pos)
	if not check.ok:
		clear()
		return

	var draft := brush as DraftBrush
	# Snap the split position the same way the validator above did.
	var snap: float = root.grid_snap if root.grid_snap > 0.0 else 0.0
	var split: float = _split_pos
	if snap > 0.0:
		split = snapped(split, snap)

	# Preview the cut the tool will actually make, by running the same split.
	# Drawing two bounding boxes instead would be a lie for every angled cut and
	# for every brush that is not a box.
	var xform := draft.global_transform
	var world_plane := Plane(HFConvexClip.axis_normal(_axis), split)
	var halves: Dictionary = HFConvexClip.split(
		draft.get_faces(), xform.affine_inverse() * world_plane
	)
	var front: Array = halves["front"]
	var back: Array = halves["back"]
	if front.is_empty() or back.is_empty():
		clear()
		return

	_ensure_container()

	_piece_a_mesh.mesh = _lines_mesh(HFOutlineUtil.face_boundary_lines(front))
	_piece_a_mesh.transform = xform
	_piece_a_mesh.visible = true
	_piece_b_mesh.mesh = _lines_mesh(HFOutlineUtil.face_boundary_lines(back))
	_piece_b_mesh.transform = xform
	_piece_b_mesh.visible = true

	var bounds: AABB = root.brush_system.world_bounds_of(draft)
	_plane_mesh.mesh = _build_plane_mesh(bounds.get_center(), bounds.size, _axis, split)
	_plane_mesh.transform = Transform3D.IDENTITY
	_plane_mesh.visible = true
	_preview_container.visible = true


## Wrap a flat list of line-segment endpoints into a drawable mesh.
static func _lines_mesh(points: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < 2:
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


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
