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
## Two edges that turn by less than this, the sine of the angle between them, are
## one straight edge; two that meet this far off a right angle are not square.
const STRAIGHT := 0.0001


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


## How far the extrusion in progress reaches out of its face, 0 with none.
func get_height() -> float:
	return _current_height if active else 0.0


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

	var made := _source_shape(height)
	if made.is_empty():
		return

	_preview_brush = DraftBrush.new()
	_preview_brush.name = "_ExtrudePreview"
	_preview_brush.shape = made["shape"]
	_preview_brush.operation = CSGShape3D.OPERATION_UNION
	_preview_brush.size = made["size"]

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
	_preview_brush.global_transform = made["transform"]
	# A prism's faces go on once it is in the tree, as `create_brush_from_info()`
	# puts them on the brush the extrusion ends with.
	if made.has("faces"):
		_preview_brush.apply_serialized_faces(made["faces"])


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
	return extrude_info(source_brush, face, direction, height, _next_brush_id())


## The face being extruded, or null once it is gone.
func _source_face() -> FaceData:
	if not is_instance_valid(source_brush):
		return null
	if source_face_idx < 0 or source_face_idx >= source_brush.faces.size():
		return null
	return source_brush.faces[source_face_idx]


## The brush this extrusion makes at `height`, as `extrude_shape()` gives it.
func _source_shape(height: float) -> Dictionary:
	var face := _source_face()
	if face == null:
		return {}
	return extrude_shape(source_brush, face, direction, height)


## The brush an extrusion of face `face_index` by `height` makes, without a
## pointer or a drag: what `extrude_shape()` puts on the face, `height` deep along
## its normal, `extrude_direction` (UP or DOWN) choosing which way. The source
## brush is left alone. `LevelRoot.extrude_face_info()` calls this, and the tool's
## own `_build_brush_info()` reaches the same `extrude_info()`, so a drag and a
## call build the same brush. Empty for a face the brush does not have.
static func build_extrude_info(
	brush: DraftBrush, face_index: int, height: float, extrude_direction: int, brush_id: String
) -> Dictionary:
	if brush == null or face_index < 0 or face_index >= brush.faces.size():
		return {}
	var face: FaceData = brush.faces[face_index]
	if face == null:
		return {}
	return extrude_info(brush, face, extrude_direction, height, brush_id)


## The create dictionary for the brush `extrude_shape()` puts on `face`.
static func extrude_info(
	brush: DraftBrush, face: FaceData, extrude_direction: int, height: float, brush_id: String
) -> Dictionary:
	var made := extrude_shape(brush, face, extrude_direction, height)
	if made.is_empty():
		return {}
	var info := made.duplicate()
	info["operation"] = CSGShape3D.OPERATION_UNION
	info["faces"] = _faces_with_texture_of(made, face)
	if brush_id != "":
		info["brush_id"] = brush_id
	if brush.material_override:
		info["material"] = brush.material_override
	return info


## The faces of the brush `extrude_shape()` made, each with the texture of the
## face it came from, as Hammer and TrenchBroom give an extruded brush (#1135).
## They go in the create dictionary, so a redo, which makes the brush again from
## it, keeps them. A box comes with no faces, so its are the ones a box builds.
static func _faces_with_texture_of(made: Dictionary, source: FaceData) -> Array:
	var faces: Array[FaceData] = []
	if made.has("faces"):
		for entry in made["faces"]:
			faces.append(FaceData.from_dict(entry))
	else:
		for corners in DraftBrush.box_corners(made["size"]):
			var face := FaceData.new()
			face.local_verts = corners
			face.ensure_geometry()
			faces.append(face)
	var out: Array = []
	for face in faces:
		face.copy_texture_from(source)
		out.append(face.to_dict())
	return out


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


## The brush an extrusion of `face` by `height` makes: its `shape`, `size` and
## world `transform`, and for a prism its `sides` and `faces`. `extrude_direction`
## (UP or DOWN) chooses out of the brush or into it.
##
## A face that is a rectangle gets a box. One square to its brush gets a box
## square to the brush, as wide as the face. Any other, a slope or a round side,
## gets a box turned to lie on it (#1107). A face of any other outline, a round cap
## or a triangle, gets a prism of that outline, the way Hammer and TrenchBroom
## extrude: the rectangle round it hung a cap's box past the rim and put half a
## triangle's over nothing (#1123). Empty for a face with no area.
static func extrude_shape(
	brush: DraftBrush, face: FaceData, extrude_direction: int, height: float
) -> Dictionary:
	face.ensure_geometry()
	var corners := _corners(face)
	if corners.size() < 3:
		return {}
	var xform := brush.global_transform
	var axis := face.normal_through(xform.basis) * float(extrude_direction)
	if not _is_rectangle(corners, xform):
		return _prism_on(brush, face, corners, axis, height)
	if _along_axes(corners):
		var middle := Vector3.ZERO
		for corner in corners:
			middle += corner
		var centre := xform * (middle / 4.0) + axis * (height * 0.5)
		return {
			"shape": DraftBrush.BrushShape.BOX,
			"size": extruded_size(brush, face_extents(face), height, axis),
			"transform": Transform3D(xform.basis, centre),
		}
	return _box_on(brush, face, corners, axis, height)


## The face's corners, in its brush's space: its vertices less any on a straight
## run between two others, as an edge split leaves, and any on top of the one
## before. Fewer than three for a face with no area.
static func _corners(face: FaceData) -> PackedVector3Array:
	var points := PackedVector3Array()
	for v in face.local_verts:
		if points.is_empty() or not points[points.size() - 1].is_equal_approx(v):
			points.append(v)
	if points.size() > 1 and points[0].is_equal_approx(points[points.size() - 1]):
		points.remove_at(points.size() - 1)
	var out := PackedVector3Array()
	var count := points.size()
	for i in count:
		var into := points[i] - points[(i + count - 1) % count]
		var out_of := points[(i + 1) % count] - points[i]
		if into.cross(out_of).length() > STRAIGHT * into.length() * out_of.length():
			out.append(points[i])
	return out


## Whether four corners make a rectangle once the brush is placed by `xform`:
## every corner a right angle in the world.
static func _is_rectangle(corners: PackedVector3Array, xform: Transform3D) -> bool:
	if corners.size() != 4:
		return false
	for i in 4:
		var before: Vector3 = xform * corners[i]
		var at: Vector3 = xform * corners[(i + 1) % 4]
		var after: Vector3 = xform * corners[(i + 2) % 4]
		if absf((at - before).normalized().dot((after - at).normalized())) > STRAIGHT:
			return false
	return true


## Whether every edge runs along one of the brush's own axes.
static func _along_axes(corners: PackedVector3Array) -> bool:
	var count := corners.size()
	for i in count:
		var edge := (corners[(i + 1) % count] - corners[i]).normalized()
		if maxf(absf(edge.x), maxf(absf(edge.y), absf(edge.z))) < SQUARE_FACE:
			return false
	return true


## The brush axis that lies most nearly in a face with this `normal`, laid in it.
## A slope's comes out along its level edge and a round side's upright.
static func _most_in_face(basis: Basis, normal: Vector3) -> Vector3:
	var along := Vector3.ZERO
	var least := INF
	for column in [basis.x, basis.y, basis.z]:
		var unit: Vector3 = column.normalized()
		if absf(unit.dot(normal)) < least:
			least = absf(unit.dot(normal))
			along = unit
	return (along - normal * along.dot(normal)).normalized()


## A box lying on a rectangle that is not square to its brush: its Y along the
## face's normal, and its X along whichever of the rectangle's edges runs most
## nearly with the brush axis that lies most nearly in the face. As wide and as
## long as the rectangle, and not held to a grid step across, which would hang a
## narrow side over its neighbours.
static func _box_on(
	brush: DraftBrush, face: FaceData, corners: PackedVector3Array, axis: Vector3, height: float
) -> Dictionary:
	var xform := brush.global_transform
	var normal := face.normal_through(xform.basis)
	var lean := _most_in_face(xform.basis, normal)
	var along := Vector3.ZERO
	for i in 2:
		var edge := (xform * corners[i + 1] - xform * corners[i]).normalized()
		if absf(edge.dot(lean)) > absf(along.dot(lean)):
			along = edge if edge.dot(lean) >= 0.0 else -edge
	var across := along.cross(normal)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for v in corners:
		var corner := xform * v
		var at := Vector2(along.dot(corner), across.dot(corner))
		low = low.min(at)
		high = high.max(at)
	var spans := high - low
	var middle := (
		along * ((low.x + high.x) * 0.5)
		+ across * ((low.y + high.y) * 0.5)
		+ normal * normal.dot(xform * corners[0])
	)
	return {
		"shape": DraftBrush.BrushShape.BOX,
		"size": Vector3(spans.x, height, spans.y),
		"transform": Transform3D(Basis(along, normal, across), middle + axis * (height * 0.5)),
	}


## A prism of the face's own outline: the outline on the face, the same outline
## `height` along `axis`, and a side on every edge, a CUSTOM brush as the Polygon
## tool makes. It stands on the face the way `_box_on()` lays a box, its Y along
## the face's normal, and its middle is the middle of its corners.
static func _prism_on(
	brush: DraftBrush, face: FaceData, corners: PackedVector3Array, axis: Vector3, height: float
) -> Dictionary:
	var xform := brush.global_transform
	var normal := face.normal_through(xform.basis)
	var along := _most_in_face(xform.basis, normal)
	var middle := Vector3.ZERO
	for corner in corners:
		middle += xform * corner
	middle /= float(corners.size())
	var offset := axis * height
	var place := Transform3D(Basis(along, normal, along.cross(normal)), middle + offset * 0.5)
	var into_prism := place.affine_inverse()
	var near := PackedVector3Array()
	var far := PackedVector3Array()
	for corner in corners:
		near.append(into_prism * (xform * corner))
		far.append(into_prism * (xform * corner + offset))
	var faces: Array = [_face_out(near), _face_out(far)]
	var count := corners.size()
	for i in count:
		var j := (i + 1) % count
		faces.append(_face_out(PackedVector3Array([near[i], near[j], far[j], far[i]])))
	var bounds := AABB(near[0], Vector3.ZERO)
	for v in near + far:
		bounds = bounds.expand(v)
	return {
		"shape": DraftBrush.BrushShape.CUSTOM,
		"size": bounds.size,
		"sides": count,
		"transform": place,
		"faces": faces,
	}


## A face on these corners, wound to face away from the middle of the prism they
## are on, which is its origin. A face of a solid that faces in bakes inside out.
static func _face_out(corners: PackedVector3Array) -> Dictionary:
	var face := FaceData.new()
	face.local_verts = corners
	face.ensure_geometry()
	var centre := Vector3.ZERO
	for v in corners:
		centre += v
	if face.normal.dot(centre) < 0.0:
		var turned := corners.duplicate()
		turned.reverse()
		face.local_verts = turned
		face.ensure_geometry()
	return face.to_dict()


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


## The box's size: the face's own extents across, and `height` along whichever
## local axis the extrusion runs. The extents used to be held to a grid step each,
## which hung the box on a pillar narrower than the grid over every side of it
## (#1122); a face with no area is refused before this. The box takes the brush's
## basis, scale and all, so that axis is divided by the brush's stretch along it:
## a box scaled three times as tall got a box three times the height asked for,
## half of it inside the brush.
static func extruded_size(
	brush: DraftBrush, face_size: Vector3, height: float, extrude_axis_world: Vector3
) -> Vector3:
	# Transform extrude axis into source brush local space to determine which dimension gets height
	var basis := brush.global_transform.basis
	var local_axis := basis.inverse() * extrude_axis_world
	local_axis = local_axis.normalized()

	# Use source face extents for the two non-extrude dimensions
	var result := face_size

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
