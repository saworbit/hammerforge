@tool
class_name HFHollowPreview
extends "hf_system.gd"
## Real-time wireframe preview showing the 6 wall pieces that would result
## from a hollow operation.  Drawn in yellow wireframe over the original brush.

const DraftBrush = preload("../brush_instance.gd")
const HFOutlineUtil = preload("../hf_outline_util.gd")

var _preview_container: Node3D
var _mesh_pool: Array = []  # Array[MeshInstance3D] — 6 walls max
var _active_count: int = 0
var _material: StandardMaterial3D

## Current preview parameters
var _brush_id: String = ""
var _wall_thickness: float = 4.0


func _init(p_root: Node3D = null) -> void:
	super(p_root)
	_enabled = false
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

	# Preview the walls the tool will actually build. Ask its planner rather than
	# keeping a second copy of the thickness rules here — and take the real wall
	# geometry from it, because drawing axis-aligned slabs would be a lie for every
	# rotated brush and every shape that is not a box.
	var draft := brush as DraftBrush
	var plan: Dictionary = root.brush_system._plan_hollow(draft, _wall_thickness)
	var check: HFOpResult = plan["result"]
	if not check.ok:
		clear()
		return
	var walls: Array = plan["walls"]
	if walls.is_empty():
		clear()
		return
	var xform: Transform3D = draft.global_transform

	_ensure_container()

	# Grow pool if needed
	while _mesh_pool.size() < walls.size():
		var mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _material
		_preview_container.add_child(mi)
		_mesh_pool.append(mi)

	# Update active wireframes with the real outline of each wall.
	for i in walls.size():
		var mi: MeshInstance3D = _mesh_pool[i]
		mi.mesh = _lines_mesh(HFOutlineUtil.face_boundary_lines(walls[i]))
		# Placed in world space, not the container's. The outlines come from the
		# brush's own global transform, and the container hangs off LevelRoot — so
		# a level whose root has been moved or turned drew this a whole root
		# transform away from the brush it claimed to preview.
		mi.global_transform = xform
		mi.visible = true

	# Hide unused
	for i in range(walls.size(), _mesh_pool.size()):
		if is_instance_valid(_mesh_pool[i]):
			_mesh_pool[i].visible = false

	_active_count = walls.size()
	_preview_container.visible = _active_count > 0


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
	_preview_container.name = "HollowPreview"
	root.add_child(_preview_container)
