@tool
extends RefCounted
class_name HFExtrudeTool

## Extrude tool for selecting a brush face and extruding upward or downward.
## Click a face to begin, drag mouse vertically to set extrude height, release to commit.

const DraftBrush = preload("brush_instance.gd")
const FaceSelector = preload("face_selector.gd")
const FaceData = preload("face_data.gd")

enum Direction { UP = 1, DOWN = -1 }

var root: Node3D

# Active extrude state
var active := false
var direction: int = Direction.UP
var source_brush: DraftBrush = null
var source_face_idx: int = -1
var source_face_center: Vector3 = Vector3.ZERO
var source_face_normal: Vector3 = Vector3.UP
var source_face_size: Vector3 = Vector3.ONE

var _start_mouse_y: float = 0.0
var _current_height: float = 0.0
var _preview_brush: DraftBrush = null
var _snap: float = 1.0

const HEIGHT_SENSITIVITY := 0.02  # world units per screen pixel
const MAX_EXTRUDE_HEIGHT := 256.0
const MIN_EXTRUDE_HEIGHT := 0.0


func _init(level_root: Node3D) -> void:
	root = level_root


func begin_extrude(camera: Camera3D, mouse_pos: Vector2, extrude_direction: int) -> bool:
	if not camera or not root:
		return false

	direction = extrude_direction
	_snap = root.grid_snap if root.grid_snap > 0.0 else 1.0

	# Raycast to find a brush face
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos).normalized()
	var brushes: Array = []
	for node in root._iter_pick_nodes():
		if node is DraftBrush:
			brushes.append(node)
	var hit := FaceSelector.intersect_brushes(brushes, ray_origin, ray_dir)
	if hit.is_empty():
		return false

	source_brush = hit.get("brush", null) as DraftBrush
	source_face_idx = int(hit.get("face_idx", -1))
	if not source_brush or source_face_idx < 0:
		return false
	if source_face_idx >= source_brush.faces.size():
		return false

	var face: FaceData = source_brush.faces[source_face_idx]
	if not face:
		return false

	# Compute face center and normal in world space
	face.ensure_geometry()
	source_face_normal = (source_brush.global_transform.basis * face.normal).normalized()
	source_face_center = _compute_face_center(source_brush, face)
	source_face_size = _compute_face_extents(face)

	_start_mouse_y = mouse_pos.y
	_current_height = 0.0
	active = true
	_update_preview(0.0)
	return true


func update_extrude(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not active:
		return
	# Dragging up (negative y delta) = positive height for UP direction
	var delta_px := _start_mouse_y - mouse_pos.y
	var raw_height := delta_px * HEIGHT_SENSITIVITY * _snap
	if direction == Direction.DOWN:
		raw_height = -raw_height
	_current_height = _snap_value(clampf(raw_height, MIN_EXTRUDE_HEIGHT, MAX_EXTRUDE_HEIGHT))
	_update_preview(_current_height)


func end_extrude_info() -> Dictionary:
	if not active or _current_height <= 0.0:
		cancel_extrude()
		return {}

	var info := _build_brush_info(_current_height)
	_clear_preview()
	active = false
	return info


func cancel_extrude() -> void:
	_clear_preview()
	active = false
	_current_height = 0.0
	source_brush = null
	source_face_idx = -1


func get_current_height() -> float:
	return _current_height


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------


func _update_preview(height: float) -> void:
	_clear_preview()
	if height <= 0.0:
		return

	_preview_brush = DraftBrush.new()
	_preview_brush.name = "_ExtrudePreview"
	_preview_brush.shape = DraftBrush.BrushShape.BOX
	_preview_brush.operation = CSGShape3D.OPERATION_UNION

	# Size: face width/depth for XZ, extrude height for Y
	var extrude_axis := _extrude_axis()
	var preview_size := _compute_preview_size(height, extrude_axis)
	_preview_brush.size = preview_size

	# Position: offset from face center along extrude direction
	var offset := extrude_axis * (height * 0.5)
	_preview_brush.global_position = source_face_center + offset

	# Align rotation to match source brush
	_preview_brush.global_transform.basis = source_brush.global_transform.basis

	# Semi-transparent preview material
	var mat := StandardMaterial3D.new()
	if direction == Direction.UP:
		mat.albedo_color = Color(0.3, 0.8, 0.3, 0.4)
	else:
		mat.albedo_color = Color(0.8, 0.3, 0.3, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.6
	_preview_brush.material_override = mat

	# Inherit material from source if available
	if source_brush.material_override:
		_preview_brush.set_meta("source_material", source_brush.material_override)

	if root.draft_brushes_node:
		root.draft_brushes_node.add_child(_preview_brush)


func _clear_preview() -> void:
	if _preview_brush and is_instance_valid(_preview_brush):
		if _preview_brush.get_parent():
			_preview_brush.get_parent().remove_child(_preview_brush)
		_preview_brush.queue_free()
		_preview_brush = null


# ---------------------------------------------------------------------------
# Brush info (for undo/redo compatible commit)
# ---------------------------------------------------------------------------


func _build_brush_info(height: float) -> Dictionary:
	var extrude_axis := _extrude_axis()
	var preview_size := _compute_preview_size(height, extrude_axis)
	var offset := extrude_axis * (height * 0.5)
	var center := source_face_center + offset

	var xform := Transform3D(source_brush.global_transform.basis, center)

	var info := {}
	info["shape"] = DraftBrush.BrushShape.BOX
	info["size"] = preview_size
	info["operation"] = CSGShape3D.OPERATION_UNION
	info["transform"] = xform
	info["brush_id"] = _generate_extrude_id()
	if source_brush.material_override:
		info["material"] = source_brush.material_override
	return info


func _generate_extrude_id() -> String:
	var dir_str := "up" if direction == Direction.UP else "down"
	return "extrude_%s_%d" % [dir_str, Time.get_ticks_msec()]


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------


func _extrude_axis() -> Vector3:
	# Use the face normal direction, with direction sign
	return source_face_normal * float(direction)


func _compute_face_center(brush: DraftBrush, face: FaceData) -> Vector3:
	if face.local_verts.is_empty():
		return brush.global_position
	var sum := Vector3.ZERO
	for v in face.local_verts:
		sum += v
	var local_center := sum / float(face.local_verts.size())
	return brush.global_transform * local_center


func _compute_face_extents(face: FaceData) -> Vector3:
	if face.local_verts.size() < 2:
		return Vector3.ONE
	var min_pt := face.local_verts[0]
	var max_pt := face.local_verts[0]
	for v in face.local_verts:
		min_pt.x = minf(min_pt.x, v.x)
		min_pt.y = minf(min_pt.y, v.y)
		min_pt.z = minf(min_pt.z, v.z)
		max_pt.x = maxf(max_pt.x, v.x)
		max_pt.y = maxf(max_pt.y, v.y)
		max_pt.z = maxf(max_pt.z, v.z)
	return max_pt - min_pt


func _compute_preview_size(height: float, extrude_axis_world: Vector3) -> Vector3:
	# Transform extrude axis into source brush local space to determine which dimension gets height
	var local_axis := source_brush.global_transform.basis.inverse() * extrude_axis_world
	local_axis = local_axis.normalized()

	# Use source face extents for the two non-extrude dimensions
	var face_size := source_face_size
	var result := Vector3(
		maxf(face_size.x, _snap), maxf(face_size.y, _snap), maxf(face_size.z, _snap)
	)

	# Set the extrude dimension to the height
	var abs_axis := Vector3(absf(local_axis.x), absf(local_axis.y), absf(local_axis.z))
	if abs_axis.x >= abs_axis.y and abs_axis.x >= abs_axis.z:
		result.x = height
	elif abs_axis.y >= abs_axis.x and abs_axis.y >= abs_axis.z:
		result.y = height
	else:
		result.z = height
	return result


func _snap_value(value: float) -> float:
	if _snap <= 0.0:
		return value
	return snapped(value, _snap)
