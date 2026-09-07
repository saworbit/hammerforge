@tool
extends RefCounted
class_name HFTransformSystem

## Rigid transforms for a HammerForge selection: rotate, flip, and reset rotation.
##
## Rotation is a determinant +1 change to each object's basis, so local face data
## is left alone — the baker's world-space `origin + basis * vert` already produces
## the rotated geometry, and so do the snap system, the gizmos, and the .hflevel
## writer.
##
## Flip is a reflection, determinant -1, and a negative determinant inverts
## triangle winding at bake time. Rather than patch normals afterwards, the
## reflection is folded back through a reflection along one *local* axis, which
## restores a right-handed basis while leaving every world vertex exactly where
## the mirror puts it. See
## `docs/superpowers/specs/2026-09-07-free-transform-design.md`.

const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")
const FaceData = preload("../face_data.gd")
const HFOpResult = preload("../hf_op_result.gd")

enum PivotMode { SELECTION_CENTER, WORLD_ORIGIN, ACTIVE, CUSTOM }

## Local-space grid used to decide whether a mirror maps a primitive onto itself.
## Coarse enough to absorb float error, fine enough that no two brush vertices
## share a cell. Misjudging falls to the exact path, never to wrong geometry.
const MIRROR_EPSILON := 0.001

var root: Node3D


func _init(level_root: Node3D = null) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# Pure geometry
# ---------------------------------------------------------------------------


## World axis for an index: 0 = X, 1 = Y, anything else = Z.
static func axis_vector(axis_index: int) -> Vector3:
	match axis_index:
		0:
			return Vector3.RIGHT
		1:
			return Vector3.UP
		_:
			return Vector3.BACK


static func rotation_basis(axis_index: int, angle_rad: float) -> Basis:
	return Basis(axis_vector(axis_index), angle_rad)


## Linear reflection through the plane whose normal is the given axis.
static func reflection_basis(axis_index: int) -> Basis:
	var scale := Vector3.ONE
	scale[clampi(axis_index, 0, 2)] = -1.0
	return Basis.IDENTITY.scaled(scale)


## Column `index` of a basis, which is the world direction of that local axis.
static func basis_axis(basis: Basis, index: int) -> Vector3:
	match index:
		0:
			return basis.x
		1:
			return basis.y
		_:
			return basis.z


## `xform` rotated by `rot` about `pivot`.
##
## The rotation part is re-orthonormalised because a brush accumulates one of
## these per key press. Each composition carries a little float error, and left
## alone that error compounds into a basis that is no longer a pure rotation —
## a sheared brush, with scale creeping into the bake. Any scale the node already
## carried is taken off first and put back afterwards, so orthonormalising cleans
## up drift without quietly resizing a brush somebody scaled with Godot's own
## gizmo.
static func rotated_transform(xform: Transform3D, rot: Basis, pivot: Vector3) -> Transform3D:
	var scale := xform.basis.get_scale()
	var out := Transform3D()
	out.basis = with_scale((rot * xform.basis).orthonormalized(), scale)
	out.origin = pivot + rot * (xform.origin - pivot)
	return out


## Apply a per-local-axis scale to an orthonormal basis.
##
## `Basis.scaled()` scales the rows, which is a world-space scale; a brush's scale
## belongs to its own axes, so each column is scaled instead.
static func with_scale(rotation: Basis, scale: Vector3) -> Basis:
	var out := rotation
	out.x = rotation.x * scale.x
	out.y = rotation.y * scale.y
	out.z = rotation.z * scale.z
	return out


## `xform` mirrored across the plane through `pivot` with normal `axis_index`,
## with the handedness folded back through the local axis `local_axis`.
##
## `basis'' = R * basis * H` has determinant +1 because both reflections
## contribute -1, and pairing it with local vertices reflected by `H` reproduces
## the mirrored world position exactly, since `H * H` is the identity.
static func flipped_transform(
	xform: Transform3D, axis_index: int, pivot: Vector3, local_axis: int
) -> Transform3D:
	var world_reflection := reflection_basis(axis_index)
	var out := Transform3D()
	out.basis = world_reflection * xform.basis * reflection_basis(local_axis)
	out.origin = pivot + world_reflection * (xform.origin - pivot)
	return out


## The local axis whose world direction is most parallel to the mirror normal.
##
## Folding the reflection through this axis keeps an axis-aligned brush axis
## aligned. Any local axis would give the same world geometry; this choice is
## what stops a mirrored box from arriving with a spurious 90-degree turn.
static func local_mirror_axis(basis: Basis, axis_index: int) -> int:
	var world_normal := axis_vector(axis_index)
	var best := 0
	var best_dot := -1.0
	for i in 3:
		var alignment := absf(basis_axis(basis, i).normalized().dot(world_normal))
		if alignment > best_dot:
			best_dot = alignment
			best = i
	return best


## Reflect one face's vertices through a local axis and reverse their order.
##
## Reflecting reverses winding, so the reversal restores the clockwise-from-
## outside order the whole codebase depends on. Applying this twice is exactly
## the identity: two negations and two reversals.
static func mirror_face(face: FaceData, local_axis: int) -> void:
	if face == null:
		return
	var verts: PackedVector3Array = face.local_verts
	var count := verts.size()
	if count == 0:
		return
	var axis := clampi(local_axis, 0, 2)
	var uvs: PackedVector2Array = face.custom_uvs
	var carry_uvs := uvs.size() == count
	var mirrored := PackedVector3Array()
	mirrored.resize(count)
	var mirrored_uvs := PackedVector2Array()
	if carry_uvs:
		mirrored_uvs.resize(count)
	for i in count:
		var source := count - 1 - i
		var vertex: Vector3 = verts[source]
		vertex[axis] = -vertex[axis]
		mirrored[i] = vertex
		if carry_uvs:
			mirrored_uvs[i] = uvs[source]
	face.local_verts = mirrored
	face.custom_uvs = mirrored_uvs if carry_uvs else PackedVector2Array()
	face.ensure_geometry()


static func mirror_faces(faces: Array, local_axis: int) -> void:
	for face in faces:
		mirror_face(face as FaceData, local_axis)


## Advance a stored yaw, in degrees, by a rotation about the world Y axis.
static func rotated_angle(angle_degrees: float, rotation_degrees: float) -> float:
	return fposmod(angle_degrees + rotation_degrees, 360.0)


## A stored yaw, in degrees, after mirroring across the given world axis.
##
## Godot's forward is -Z, so a yaw of θ points along `(-sin θ, 0, -cos θ)`.
## Mirroring that direction and solving for the new yaw gives -θ across X,
## θ across Y (the entity turns upside down, not around), and 180 - θ across Z.
static func mirrored_angle(angle_degrees: float, axis_index: int) -> float:
	match axis_index:
		0:
			return fposmod(-angle_degrees, 360.0)
		1:
			return fposmod(angle_degrees, 360.0)
		_:
			return fposmod(180.0 - angle_degrees, 360.0)


# ---------------------------------------------------------------------------
# Pre-validation
# ---------------------------------------------------------------------------


## Flip cannot mirror a sculpted displacement: the displacement grid is indexed
## against its face's corner order, and mirroring reverses that order.
func can_flip_brushes(brush_ids: Array) -> HFOpResult:
	for brush_id in brush_ids:
		var draft := _brush_at_id(str(brush_id))
		if draft == null:
			continue
		if _has_displacement(draft):
			return (
				HFOpResult
				. fail(
					"Flip: brush '%s' has displacement faces" % str(brush_id),
					"Mirroring a sculpted displacement is not supported — destroy the displacement first"
				)
			)
	return HFOpResult.success()


# ---------------------------------------------------------------------------
# Selection operations
# ---------------------------------------------------------------------------


## Rotate brushes and entities about `pivot`. Returns the number changed.
func rotate(
	brush_ids: Array, entity_paths: Array, axis_index: int, angle_rad: float, pivot: Vector3
) -> int:
	if is_zero_approx(angle_rad):
		return 0
	var rot := rotation_basis(axis_index, angle_rad)
	var lock_textures := _texture_lock_enabled()
	var angle_degrees := rad_to_deg(angle_rad)
	var changed := 0
	for brush_id in brush_ids:
		var draft := _brush_at_id(str(brush_id))
		if draft == null:
			continue
		draft.global_transform = rotated_transform(draft.global_transform, rot, pivot)
		if lock_textures:
			adjust_face_uvs_for_rotation(draft, angle_rad)
			draft.rebuild_preview()
		_tag_dirty(draft)
		changed += 1
	for entity_path in entity_paths:
		var entity := _entity_at_path(entity_path)
		if entity == null:
			continue
		entity.global_transform = rotated_transform(entity.global_transform, rot, pivot)
		if axis_index == 1:
			_set_entity_angle(entity, rotated_angle(_entity_angle(entity), angle_degrees))
		changed += 1
	return changed


## Mirror brushes and entities across the plane through `pivot` whose normal is
## `axis_index`. Brushes carrying displacement faces are skipped; call
## `can_flip_brushes()` first to report that to the user. Returns the number
## changed.
func flip(brush_ids: Array, entity_paths: Array, axis_index: int, pivot: Vector3) -> int:
	var changed := 0
	for brush_id in brush_ids:
		var draft := _brush_at_id(str(brush_id))
		if draft == null or _has_displacement(draft):
			continue
		_flip_brush(draft, axis_index, pivot)
		changed += 1
	for entity_path in entity_paths:
		var entity := _entity_at_path(entity_path)
		if entity == null:
			continue
		var local_axis := local_mirror_axis(entity.global_transform.basis, axis_index)
		entity.global_transform = flipped_transform(
			entity.global_transform, axis_index, pivot, local_axis
		)
		_set_entity_angle(entity, mirrored_angle(_entity_angle(entity), axis_index))
		changed += 1
	return changed


## Clear each brush's rotation, keeping its position. This is what makes hollow,
## clip, and carve reachable again after a rotation — all three refuse a rotated
## brush through `HFBrushSystem._check_axis_aligned_box()`.
func reset_rotation(brush_ids: Array) -> int:
	var changed := 0
	for brush_id in brush_ids:
		var draft := _brush_at_id(str(brush_id))
		if draft == null:
			continue
		var xform := draft.global_transform
		if xform.basis.is_equal_approx(Basis.IDENTITY):
			continue
		# A basis that only swaps and flips whole axes is describing a box that is
		# already axis-aligned, just bookkept oddly. Fold the swap into `size` so
		# clearing the basis leaves the geometry exactly where it was — otherwise a
		# quarter turn would snap a non-cube box back to its old footprint.
		var permutation := axis_permutation(xform.basis)
		if not permutation.is_empty() and draft.shape == DraftBrush.BrushShape.BOX:
			draft.size = permuted_size(draft.size, permutation)
		draft.global_transform = Transform3D(Basis.IDENTITY, xform.origin)
		_tag_dirty(draft)
		changed += 1
	return changed


## For a basis whose columns each lie along a distinct world axis, the world axis
## that each local axis maps to. Empty for a general rotation.
static func axis_permutation(basis: Basis) -> PackedInt32Array:
	const TOLERANCE := 0.9999
	var mapping := PackedInt32Array()
	var used := {}
	for local_axis in 3:
		var direction := basis_axis(basis, local_axis).normalized()
		var matched := -1
		for world_axis in 3:
			if absf(direction.dot(axis_vector(world_axis))) >= TOLERANCE:
				matched = world_axis
				break
		if matched < 0 or used.has(matched):
			return PackedInt32Array()
		used[matched] = true
		mapping.append(matched)
	return mapping


## Rewrite a size so each local extent lands on the world axis it now points down.
static func permuted_size(size: Vector3, mapping: PackedInt32Array) -> Vector3:
	if mapping.size() < 3:
		return size
	var out := size
	for local_axis in 3:
		out[mapping[local_axis]] = size[local_axis]
	return out


# ---------------------------------------------------------------------------
# Pivots and bounds
# ---------------------------------------------------------------------------


func resolve_pivot(
	brush_ids: Array, entity_paths: Array, mode: int, custom: Vector3 = Vector3.ZERO
) -> Vector3:
	match mode:
		PivotMode.WORLD_ORIGIN:
			return Vector3.ZERO
		PivotMode.CUSTOM:
			return custom
		PivotMode.ACTIVE:
			return _active_origin(brush_ids, entity_paths)
		_:
			return selection_origin_centroid(brush_ids, entity_paths)


## Centroid of the selection's object origins — Blender's "median point".
##
## This is the pivot rotate and flip use by default because it is exactly
## invariant: rotating a point set about its own centroid, or mirroring it about
## a plane through that centroid, leaves the centroid where it was. A bounding-box
## centre does not have that property, so repeated presses of the rotate key would
## walk an asymmetric selection across the level.
func selection_origin_centroid(brush_ids: Array, entity_paths: Array) -> Vector3:
	var total := Vector3.ZERO
	var found := 0
	for brush_id in brush_ids:
		var draft := _brush_at_id(str(brush_id))
		if draft == null:
			continue
		total += draft.global_position
		found += 1
	for entity_path in entity_paths:
		var entity := _entity_at_path(entity_path)
		if entity == null:
			continue
		total += entity.global_position
		found += 1
	return total / float(found) if found > 0 else Vector3.ZERO


## World bounds of a selection, measured through each brush's own transform so
## that an already-rotated brush contributes its real extent.
func selection_bounds(brush_ids: Array, entity_paths: Array) -> AABB:
	var bounds := AABB()
	var seeded := false
	for brush_id in brush_ids:
		var draft := _brush_at_id(str(brush_id))
		if draft == null:
			continue
		var xform := draft.global_transform
		for local_point in _brush_local_points(draft):
			var world_point: Vector3 = xform * local_point
			if seeded:
				bounds = bounds.expand(world_point)
			else:
				bounds = AABB(world_point, Vector3.ZERO)
				seeded = true
	for entity_path in entity_paths:
		var entity := _entity_at_path(entity_path)
		if entity == null:
			continue
		var origin := entity.global_position
		if seeded:
			bounds = bounds.expand(origin)
		else:
			bounds = AABB(origin, Vector3.ZERO)
			seeded = true
	return bounds


# ---------------------------------------------------------------------------
# Texture lock
# ---------------------------------------------------------------------------


## Compensate every face's UV rotation so the texture stays put in world space,
## matching what `texture_lock` already means for moving and resizing a brush.
static func adjust_face_uvs_for_rotation(draft: DraftBrush, angle_rad: float) -> void:
	for face in draft.faces:
		if face == null:
			continue
		face.adjust_uvs_for_rotation(angle_rad)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


func _flip_brush(draft: DraftBrush, axis_index: int, pivot: Vector3) -> void:
	var local_axis := local_mirror_axis(draft.global_transform.basis, axis_index)
	# The symmetry test reads generated face vertices, so they have to exist before
	# it runs — otherwise every brush would look asymmetric and promote to CUSTOM.
	_ensure_faces(draft)
	# A primitive that a local mirror maps onto itself needs no geometry surgery:
	# the fold-back reflection lands every generated vertex on another vertex of
	# the same shape, and the per-face data rides along to where that face went.
	var keeps_primitive := _primitive_survives_mirror(draft, local_axis)
	if not keeps_primitive:
		draft.mark_faces_authoritative()
	draft.global_transform = flipped_transform(
		draft.global_transform, axis_index, pivot, local_axis
	)
	if not keeps_primitive:
		mirror_faces(draft.get_faces(), local_axis)
		draft.rebuild_preview()
	_tag_dirty(draft)


## True when reflecting the brush's local vertices through `local_axis` leaves
## the generated vertex set unchanged. A CUSTOM brush never qualifies: its faces
## *are* the geometry, so they have to be mirrored rather than regenerated.
func _primitive_survives_mirror(draft: DraftBrush, local_axis: int) -> bool:
	if draft.shape == DraftBrush.BrushShape.CUSTOM:
		return false
	var faces := draft.get_faces()
	if faces.is_empty():
		return false
	var axis := clampi(local_axis, 0, 2)
	var occupied := {}
	for face in faces:
		if face == null:
			continue
		for vertex in face.local_verts:
			occupied[_quantize(vertex)] = true
	if occupied.is_empty():
		return false
	for face in faces:
		if face == null:
			continue
		for vertex in face.local_verts:
			var mirrored: Vector3 = vertex
			mirrored[axis] = -mirrored[axis]
			if not occupied.has(_quantize(mirrored)):
				return false
	return true


static func _quantize(point: Vector3) -> String:
	return (
		"%d,%d,%d"
		% [
			roundi(point.x / MIRROR_EPSILON),
			roundi(point.y / MIRROR_EPSILON),
			roundi(point.z / MIRROR_EPSILON),
		]
	)


static func _has_displacement(draft: DraftBrush) -> bool:
	for face in draft.faces:
		if face != null and face.displacement != null:
			return true
	return false


## Local points that describe a brush's extent: its real face vertices when it
## has them, and its box corners otherwise.
static func _brush_local_points(draft: DraftBrush) -> PackedVector3Array:
	var points := PackedVector3Array()
	for face in draft.faces:
		if face != null:
			points.append_array(face.local_verts)
	if not points.is_empty():
		return points
	var half: Vector3 = draft.size * 0.5
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				points.append(Vector3(half.x * sx, half.y * sy, half.z * sz))
	return points


func _ensure_faces(draft: DraftBrush) -> void:
	if draft.get_faces().is_empty():
		draft.rebuild_preview()


func _active_origin(brush_ids: Array, entity_paths: Array) -> Vector3:
	for brush_id in brush_ids:
		var draft := _brush_at_id(str(brush_id))
		if draft != null:
			return draft.global_position
	for entity_path in entity_paths:
		var entity := _entity_at_path(entity_path)
		if entity != null:
			return entity.global_position
	return Vector3.ZERO


func _brush_at_id(brush_id: String) -> DraftBrush:
	if brush_id == "" or not is_instance_valid(root):
		return null
	var brush_system = root.get("brush_system")
	if brush_system == null:
		return null
	var node = brush_system.find_brush_by_id(brush_id)
	return node as DraftBrush


func _entity_at_path(entity_path: Variant) -> DraftEntity:
	if not is_instance_valid(root):
		return null
	var node := root.get_node_or_null(NodePath(str(entity_path)))
	return node as DraftEntity


static func _entity_angle(entity: DraftEntity) -> float:
	var value = entity.entity_data.get("angle", null)
	if value is float or value is int:
		return float(value)
	return NAN


static func _set_entity_angle(entity: DraftEntity, angle_degrees: float) -> void:
	if is_nan(angle_degrees) or not entity.entity_data.has("angle"):
		return
	entity.entity_data["angle"] = angle_degrees


func _texture_lock_enabled() -> bool:
	if not is_instance_valid(root):
		return false
	var value = root.get("texture_lock")
	return value if value is bool else false


func _tag_dirty(draft: DraftBrush) -> void:
	if not is_instance_valid(root) or not root.has_method("tag_brush_dirty"):
		return
	var brush_id := str(draft.brush_id)
	if brush_id != "":
		root.tag_brush_dirty(brush_id)
