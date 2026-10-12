@tool
extends RefCounted
class_name HFExtrudeTool

## Extrude tool for selecting a brush face and extruding upward or downward.
## Click a face to begin, drag mouse vertically to set extrude height, release to commit.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
@warning_ignore_restore("shadowed_global_identifier")

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
var _preview_container: Node3D = null
var _snap: float = 1.0

const HEIGHT_SENSITIVITY := 0.02  # world units per screen pixel
const MAX_EXTRUDE_HEIGHT := 256.0
const MIN_EXTRUDE_HEIGHT := 0.0
## A face whose normal is this close to one of its brush's axes is square to it.
const SQUARE_FACE := 0.9999


func _init(level_root: Node3D) -> void:
	root = level_root


func begin_extrude(camera: Camera3D, mouse_pos: Vector2, extrude_direction: int) -> bool:
	if not camera or not root:
		return false

	# Use LevelRoot's canonical visible-face picker so a hidden visgroup can
	# never start an extrusion through geometry the user cannot see.
	var hit: Dictionary = root.pick_face(camera, mouse_pos)
	if hit.is_empty():
		return false
	var picked := hit.get("brush", null) as DraftBrush
	if not begin_on_face(picked, int(hit.get("face_idx", -1)), extrude_direction):
		return false
	_start_mouse_y = mouse_pos.y
	return true


## Start an extrusion on a face named outright: what `begin_extrude()` does once
## it has picked one with the pointer.
func begin_on_face(brush: DraftBrush, face_idx: int, extrude_direction: int) -> bool:
	if not root or brush == null or face_idx < 0 or face_idx >= brush.faces.size():
		return false
	var face: FaceData = brush.faces[face_idx]
	if not face:
		return false

	direction = extrude_direction
	_snap = root.grid_snap if root.grid_snap > 0.0 else 1.0
	source_brush = brush
	source_face_idx = face_idx

	# Compute face center and normal in world space
	face.ensure_geometry()
	source_face_normal = face.normal_through(brush.global_transform.basis)
	source_face_center = face_center(brush, face)
	source_face_size = face_extents(face)

	_current_height = 0.0
	active = true
	_update_preview(0.0)
	return true


func update_extrude(_camera: Camera3D, mouse_pos: Vector2) -> void:
	if not active:
		return
	if not is_instance_valid(source_brush):
		cancel_extrude()
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
	if not is_instance_valid(source_brush):
		cancel_extrude()
		return {}

	var info := _build_brush_info(_current_height)
	_teardown_preview()
	active = false
	return info


func cancel_extrude() -> void:
	_teardown_preview()
	active = false
	_current_height = 0.0
	source_brush = null
	source_face_idx = -1


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------


func _update_preview(height: float) -> void:
	_clear_preview()
	if height <= 0.0:
		return
	if not is_instance_valid(source_brush) or not is_instance_valid(root):
		active = false
		return

	var box := _source_box(height)
	if box.is_empty():
		return

	_preview_brush = DraftBrush.new()
	_preview_brush.name = "_ExtrudePreview"
	_preview_brush.shape = DraftBrush.BrushShape.BOX
	_preview_brush.operation = CSGShape3D.OPERATION_UNION
	_preview_brush.size = box["size"]

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

	var container := _ensure_preview_container()
	if not container:
		_preview_brush.free()
		_preview_brush = null
		return
	# In the tree first. `global_position` and `global_transform` are both
	# tree-relative, and a node that is not in the tree yet answers them with an
	# engine error and an identity transform, which left the ghost at the origin
	# instead of on the face being extruded.
	container.add_child(_preview_brush)
	_preview_brush.global_transform = box["transform"]


## The ghost gets a container of its own, the way every other preview in the
## editor does. It used to go into `draft_brushes_node`, which is what
## `_iter_managed_brush_nodes()`, `_iter_pick_nodes()`, `capture_state()` and the
## save all walk: mid-drag the level had a brush in it that nobody made, an
## autosave stored it, and the snap system offered its corners.
func _ensure_preview_container() -> Node3D:
	if is_instance_valid(_preview_container):
		return _preview_container
	if not is_instance_valid(root):
		return null
	_preview_container = Node3D.new()
	_preview_container.name = "ExtrudePreview"
	root.add_child(_preview_container)
	return _preview_container


## The ghost only. The container stays up for the rest of the drag, because this
## runs once per mouse move.
func _clear_preview() -> void:
	if _preview_brush and is_instance_valid(_preview_brush):
		if _preview_brush.get_parent():
			_preview_brush.get_parent().remove_child(_preview_brush)
		_preview_brush.queue_free()
	_preview_brush = null


## The ghost and its container, for the end of the extrusion either way.
func _teardown_preview() -> void:
	_clear_preview()
	if is_instance_valid(_preview_container):
		if _preview_container.get_parent():
			_preview_container.get_parent().remove_child(_preview_container)
		_preview_container.queue_free()
	_preview_container = null


# ---------------------------------------------------------------------------
# Brush info (for undo/redo compatible commit)
# ---------------------------------------------------------------------------


func _build_brush_info(height: float) -> Dictionary:
	var face := _source_face()
	if face == null:
		return {}
	return extrude_info(source_brush, face, direction, height, _snap, _next_brush_id())


## The face being extruded, or null once it is gone.
func _source_face() -> FaceData:
	if not is_instance_valid(source_brush):
		return null
	if source_face_idx < 0 or source_face_idx >= source_brush.faces.size():
		return null
	return source_brush.faces[source_face_idx]


## The box this extrusion makes at `height`, as `extrude_box()` gives it.
func _source_box(height: float) -> Dictionary:
	var face := _source_face()
	if face == null:
		return {}
	return extrude_box(source_brush, face, direction, height, _snap)


## The brush an extrusion of face `face_index` by `height` makes, without a
## pointer or a drag. A box on the face, as wide as the face and `height` deep
## along its normal, `extrude_direction` (UP or DOWN) choosing which way. The
## source brush is left alone. `LevelRoot.extrude_face_info()` calls this, and the
## tool's own `_build_brush_info()` reaches the same `extrude_info()`, so a drag and
## a call build the same brush. Empty for a face the brush does not have.
static func build_extrude_info(
	brush: DraftBrush,
	face_index: int,
	height: float,
	extrude_direction: int,
	snap: float,
	brush_id: String
) -> Dictionary:
	if brush == null or face_index < 0 or face_index >= brush.faces.size():
		return {}
	var face: FaceData = brush.faces[face_index]
	if face == null:
		return {}
	return extrude_info(brush, face, extrude_direction, height, snap, brush_id)


## The create dictionary for the box `extrude_box()` puts on `face`.
static func extrude_info(
	brush: DraftBrush,
	face: FaceData,
	extrude_direction: int,
	height: float,
	snap: float,
	brush_id: String
) -> Dictionary:
	var box := extrude_box(brush, face, extrude_direction, height, snap)
	if box.is_empty():
		return {}
	var info := {}
	info["shape"] = DraftBrush.BrushShape.BOX
	info["size"] = box["size"]
	info["operation"] = CSGShape3D.OPERATION_UNION
	info["transform"] = box["transform"]
	if brush_id != "":
		info["brush_id"] = brush_id
	if brush.material_override:
		info["material"] = brush.material_override
	return info


## Ids come from the brush system, the way every other created brush's does.
## This tool used to mint its own from the direction and the millisecond clock,
## which is not unique: two extrusions committed in the same millisecond claimed
## the same id, an id minted in one session collided with one from another
## whenever the tick counts lined up, and `id_counter` never advanced, so the
## counter and the ids in the level drifted apart after every extrusion.
##
## The id is minted here rather than left to `create_brush_from_info()` because
## it has to stay the same across a redo, which calls that function again with
## this same dictionary.
func _next_brush_id() -> String:
	if is_instance_valid(root) and root.get("brush_system"):
		var brush_system = root.brush_system
		if brush_system.has_method("next_brush_id"):
			return str(brush_system.next_brush_id())
	return ""


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------


func _compute_face_center(brush: DraftBrush, face: FaceData) -> Vector3:
	return face_center(brush, face)


func _compute_face_extents(face: FaceData) -> Vector3:
	return face_extents(face)


## The box an extrusion of `face` by `height` makes: its `size` and its world
## `transform`, `extrude_direction` (UP or DOWN) choosing out of the brush or into
## it. A face square to its brush gets a box square to the brush, as wide as the
## face. Any other face, a slope or a round side, gets a box turned to lie on it.
## It used to get the square box too, sized by the slope's bounds, which made an
## upright slab half sunk into the brush (#1107). Empty for a face with no area.
static func extrude_box(
	brush: DraftBrush, face: FaceData, extrude_direction: int, height: float, snap: float
) -> Dictionary:
	face.ensure_geometry()
	var axis := face.normal_through(brush.global_transform.basis) * float(extrude_direction)
	var n := face.normal.normalized()
	if maxf(absf(n.x), maxf(absf(n.y), absf(n.z))) >= SQUARE_FACE:
		var centre := face_center(brush, face) + axis * (height * 0.5)
		return {
			"size": extruded_size(brush, face_extents(face), height, axis, snap),
			"transform": Transform3D(brush.global_transform.basis, centre),
		}
	return _box_on(brush, face, axis, height)


## A box lying on a face that is not square to its brush: its Y along the face's
## normal, and its X along the brush axis that lies most nearly in the face, so a
## slope's box runs along its level edge and a round side's stands upright. As
## wide and as long as the face's corners reach across it, so a triangle is
## covered by the rectangle round it, as a round cap is by the square round it.
## Not held to a grid step across, which would hang a narrow side over its
## neighbours.
static func _box_on(brush: DraftBrush, face: FaceData, axis: Vector3, height: float) -> Dictionary:
	if face.local_verts.size() < 3:
		return {}
	var xform := brush.global_transform
	var normal := face.normal_through(xform.basis)
	var along := Vector3.ZERO
	var least := INF
	for column in [xform.basis.x, xform.basis.y, xform.basis.z]:
		var unit: Vector3 = column.normalized()
		if absf(unit.dot(normal)) < least:
			least = absf(unit.dot(normal))
			along = unit
	along = (along - normal * along.dot(normal)).normalized()
	var across := along.cross(normal)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for v in face.local_verts:
		var corner := xform * v
		var at := Vector2(along.dot(corner), across.dot(corner))
		low = low.min(at)
		high = high.max(at)
	var spans := high - low
	if spans.x <= 0.0001 or spans.y <= 0.0001:
		return {}
	var middle := (
		along * ((low.x + high.x) * 0.5)
		+ across * ((low.y + high.y) * 0.5)
		+ normal * normal.dot(face_center(brush, face))
	)
	return {
		"size": Vector3(spans.x, height, spans.y),
		"transform": Transform3D(Basis(along, normal, across), middle + axis * (height * 0.5)),
	}


## A face's middle, in world space: the mean of its vertices.
static func face_center(brush: DraftBrush, face: FaceData) -> Vector3:
	if face.local_verts.is_empty():
		return brush.global_position
	var sum := Vector3.ZERO
	for v in face.local_verts:
		sum += v
	var local_center := sum / float(face.local_verts.size())
	return brush.global_transform * local_center


## A face's local bounding box size.
static func face_extents(face: FaceData) -> Vector3:
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


## The box's size: the face's extents across, at least one grid step each, and
## `height` along whichever local axis the extrusion runs. The box takes the
## brush's basis, scale and all, so that axis is divided by the brush's stretch
## along it: a box scaled three times as tall got a box three times the height
## asked for, half of it inside the brush.
static func extruded_size(
	brush: DraftBrush, face_size: Vector3, height: float, extrude_axis_world: Vector3, snap: float
) -> Vector3:
	# Transform extrude axis into source brush local space to determine which dimension gets height
	var basis := brush.global_transform.basis
	var local_axis := basis.inverse() * extrude_axis_world
	local_axis = local_axis.normalized()

	# Use source face extents for the two non-extrude dimensions
	var result := Vector3(maxf(face_size.x, snap), maxf(face_size.y, snap), maxf(face_size.z, snap))

	# Set the extrude dimension to the height
	var abs_axis := Vector3(absf(local_axis.x), absf(local_axis.y), absf(local_axis.z))
	var index := 2
	if abs_axis.x >= abs_axis.y and abs_axis.x >= abs_axis.z:
		index = 0
	elif abs_axis.y >= abs_axis.x and abs_axis.y >= abs_axis.z:
		index = 1
	var stretch := basis[index].length()
	result[index] = height / stretch if stretch > 0.0 else height
	return result


func _snap_value(value: float) -> float:
	if _snap <= 0.0:
		return value
	return snapped(value, _snap)
