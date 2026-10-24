@tool
extends Resource
class_name FaceData

## FACE is taken in the face's own plane: U runs level along the face and V down
## its slope, so a ramp or a chamfer repeats over the same length a wall does where
## Box UV stretched it along the slope (#1419). A floor or a ceiling has no slope
## and reads Planar Y's axes. Positions are still the level's, so coplanar faces on
## separate brushes line up. It is the last value, so an older build reads it as a
## projection it does not know: Box UV from an `.hflevel`, Planar Z in a scene.
enum UVProjection { PLANAR_X, PLANAR_Y, PLANAR_Z, BOX_UV, CYLINDRICAL, FACE }

## How far a rotated projection plane may lean off a local axis and still be
## treated as that axis. Rotations arrive as exact quarter turns or as a turn
## about the projection axis itself, so anything past this is a genuine tilt.
const UV_AXIS_EPSILON := 0.0001
## How far a change of UV axes may stray from a turn, or a turn and a mirror,
## before it counts as a stretch, which no stored field can hold.
const UV_TURN_TOLERANCE := 0.001
## How far off a face's plane a `.map` texture axis may lean and still lie in it.
## The axes are written to four places.
const MAP_AXIS_IN_PLANE := 0.01
## How far apart two `.map` texture axes may be and still be the same one.
const MAP_AXIS_MATCH := 0.01
## How square on a face a planar projection has to read it to lay a texture on
## it, as the cosine between the face and the projection's plane: past about 84
## degrees a texture is smeared into lines.
const PROJECTION_ACROSS_FACE := 0.1
enum PaintBlend { OVERLAY, MULTIPLY, ADD }
## What a face is for (#1719). See `face_type`.
enum FaceType { NORMAL, HIDDEN }
## The highest smoothing group a face holds. Far more than a level uses; the cap
## only keeps a hand-edited file from handing the bake a number it cannot key by.
const MAX_SMOOTHING_GROUP := 65535

## Kept as a name on `FaceData` because every call site spells it
## `FaceData.PaintLayer`, and as a file of its own because an inner class has no
## type a `.tscn` can name: the scene wrote the layers and refused them on load,
## so a painted face reopened unpainted (#665). See `hf_face_paint_layer.gd`.
const PaintLayer = preload("res://addons/hammerforge/paint/hf_face_paint_layer.gd")
const HFHiddenFaces = preload("res://addons/hammerforge/hf_hidden_faces.gd")

@export var material_idx: int = -1
## The texture this face was named in the `.map` it came from.
##
## In this lineage the texture name *is* the surface's behaviour -- `AAATRIGGER`
## is a trigger volume, `*water1` is water, `sky1` is sky -- so dropping it drops
## the classification, not just the decoration. The importer parsed the name and
## nothing stored it, and the exporter wrote `__default` on all sixty faces of a
## ten brush map (#662). Kept whether or not the palette has a slot for it, so a
## round trip is lossless with no materials loaded at all.
@export var map_texture: String = ""
## A Hidden face is one nobody will see: the underside of a floor, the outside of
## a sealed room, the back of a wall built against another (#1719). It still
## bounds its brush, so the brush collides as it did, but the bake leaves it out
## of the mesh and the lightmap. It goes with the texture, so Alt+T, a resize, a
## clip and a duplicate carry it, and the slot under it is kept for when the face
## is shown again.
@export var face_type: int = FaceType.NORMAL
## PLANAR_Z maps (x, -y) -> (u, v), so on a face whose plane contains the Z axis,
## or one lying flat in Y, one UV axis is constant across the whole face and every
## point on it samples the same line of the texture: four of a box's six faces.
## BOX_UV resolves to the dominant normal axis per face, which is the answer the
## dock's "Apply + Re-project (Box UV)" button already applies by hand.
## `_transfer_face_data()` carries this across a rebuild, so a saved level keeps
## whatever it was saved with.
@export var uv_projection: int = UVProjection.BOX_UV
## True for a face laid on before #907, which keeps the axes it was laid on with.
##
## A wall's V used to run up the wall, and Godot reads V = 0 as the top row of the
## image, so every wall and every Cylindrical side was drawn upside down. An X
## wall's U also ran along +Z where every Quake family editor runs it along -Z.
## The axes now match qbsp's, but a face somebody had already aligned, painted or
## hand edited was tuned against the old ones, and its paint masks and the
## records that watch it for edits hold those numbers. Such a face is marked and
## keeps drawing exactly as it did. A face nobody laid on takes the new axes.
## Re-projecting a face clears the mark.
@export var legacy_wall_axes: bool = false
@export var uv_scale: Vector2 = Vector2.ONE
@export var uv_offset: Vector2 = Vector2.ZERO
@export var uv_rotation: float = 0.0
## How this face shades (#1429). 0 is flat: the face lights with its own normal,
## as every face did before. Faces in the same group above 0 that meet at a corner
## share the average of their normals there, across brushes and materials, so a
## ring of flat faces reads as round. Shading only: the corners stay where they
## are, so collision and every tool see the same convex brush. `HFSmoothing` does
## the averaging for the bake and the preview alike.
@export_range(0, 32, 1, "or_greater") var smoothing_group: int = 0
@export var custom_uvs: PackedVector2Array = PackedVector2Array()
@export var paint_layers: Array[PaintLayer] = []
@export var bounds: AABB = AABB()
@export var local_verts: PackedVector3Array = PackedVector3Array()
## Where this face's brush sits in the level, so a planar projection can be taken
## in world space rather than in the brush's own space.
##
## Two brushes of the same size used to get identical UVs wherever they were, so
## a wall built out of three panels was three copies of the same patch of texture
## with a hard restart at every seam -- and building a surface out of several
## brushes is the fundamental move in this style of editor (#652). Every other
## editor in this lineage projects from world space for that reason, and the
## `.map` formats already mean it: `hf_map_valve220.gd` writes world texture axes.
##
## Not persisted. It is the brush's transform, kept in step by `DraftBrush`, and
## a face that has never been told is at the origin -- which is what a face with
## no brush (a test, a raw `from_dict`) should assume.
var world_transform: Transform3D = Transform3D.IDENTITY
## The `uv_format_version` this face was loaded from, so a brush that has just
## been given its transform can migrate offsets tuned against the old projection.
## Back to -1 once the brush has done it, and -1 for a face that was built
## rather than loaded.
var pending_uv_migration: int = -1
## The brush orientation these UVs were laid out against, so a face that swings
## onto a different Box UV axis can keep the handedness it had (#684).
##
## Not persisted, and not a default anyone should read as meaningful: the first
## time a brush tells a face where it is, whatever it says is the layout. That
## is what makes a saved level safe -- it reopens with the orientation it was
## saved at, so nothing is reconciled and nothing moves.
var _uv_layout_basis: Basis = Basis.IDENTITY
var _uv_layout_known: bool = false
@export var normal: Vector3 = Vector3.UP
## The texture group this face is in, or 0 for none (#1437). A group is faces that
## read as one surface: they share one mapping, the projection, scale, rotation and
## offset, and an edit that moves or reshapes one of them lays that mapping on it
## again rather than Texture Lock's shift. Ids are drawn at random, so a face
## pasted into another level is unlikely to land in a group there.
##
## Not part of the look. `copy_appearance_from()` is how Apply Picked Look, Align,
## a bevel, an inset and a cut's cap lay one face's look on another, and none of
## those means the two are one surface. The places that build the same face again
## carry it with `copy_texture_group_from()`.
@export var uv_group: int = 0
## The Justify mode last used on this face's group, so a group last fitted can be
## fitted again across its new bounds after an edit. Empty for none.
@export var uv_group_justify: String = ""

## Optional displacement data. When non-null the face is a displacement surface
## and triangulate() produces a subdivided grid mesh instead of a flat fan.
## Stored so the sculpt is saved with the scene, not only in the .hflevel (#854).
## Kept out of the Inspector: the dock resamples the grid when its power changes,
## and a raw edit would not.
@export_storage var displacement: Resource = null  # HFDisplacementData (avoid preload cycle)

## Memoised result of `get_painted_albedo()`, keyed by the paint inputs.
##
## Every `rebuild_preview()` (27 call sites, including one per surface-paint
## sample) recomposites every painted face of the brush, even the faces that did
## not change. Building the key hashes each weight image, which on Godot 4.7
## measures 0.077 ms for 256x256 against 61.7 ms for the composite itself — see
## `tools/benchmark_paint_hot_paths.gd`.
##
## The cost is one retained image per painted face, sized like that face's weight
## image (256x256 by default). Faces with no paint layers cache nothing.
var _albedo_cache: Image = null
var _albedo_cache_key: String = ""


func ensure_geometry() -> void:
	_compute_normal()
	_compute_bounds()


## This face's normal once its brush is placed by [param basis]. Ask this rather
## than writing [code]basis * normal[/code]: that is a normal only while the brush
## is turned or scaled evenly, and a brush stretched with Godot's scale gizmo has
## its slopes lean towards the stretched axis (#884).
func normal_through(basis: Basis) -> Vector3:
	return (normal_basis(basis) * normal).normalized()


## The basis that carries a surface normal the way [param basis] carries points:
## its inverse transpose. It points the same way as the basis for a turn, or a
## turn and one scale on every axis. A basis with no inverse has squashed the
## brush flat, and inverting it is an engine error, so that one is kept as it is.
static func normal_basis(basis: Basis) -> Basis:
	if basis.determinant() == 0.0:
		return basis
	return basis.inverse().transposed()


func ensure_custom_uvs() -> void:
	if custom_uvs.size() == local_verts.size():
		return
	custom_uvs = _project_uvs_for_vertices(local_verts)


## Whether this face draws with UVs of its own rather than its projection, as
## `triangulate()` decides it.
func has_uv_layout() -> bool:
	return not custom_uvs.is_empty() and custom_uvs.size() == local_verts.size()


## The UVs this face draws with at its corners. Unlike `ensure_custom_uvs()`, asking
## does not give a face that has no layout one.
func shown_uvs() -> PackedVector2Array:
	if has_uv_layout():
		return custom_uvs
	return _project_uvs_for_vertices(local_verts)


## The UVs this face's projection, scale, offset and rotation give its corners,
## whether or not it has a layout of its own. The Texture Gizmo reads how the
## texture lies on the face from these.
func projected_uvs() -> PackedVector2Array:
	return _project_uvs_for_vertices(local_verts)


## Give this face the texture `source` shows: its palette slot, and the name it had
## in a `.map`, which the exporter falls back to when there is no slot. The two are
## one thing to copy. Copying the slot alone is how an imported trigger came out of
## a resize, a Godot Duplicate or a clip as a plain solid (#859).
func copy_texture_from(source: FaceData) -> void:
	material_idx = source.material_idx
	map_texture = source.map_texture
	face_type = source.face_type


func is_hidden() -> bool:
	return face_type == FaceType.HIDDEN


## A saved face type read as one this build knows, NORMAL for anything else: an
## older build's file has none, and a newer one may name a type this one lacks.
static func read_face_type(value: Variant) -> int:
	var whole := _read_whole(value, FaceType.NORMAL)
	return whole if FaceType.values().has(whole) else FaceType.NORMAL


## Give this face the look of `source`: its texture and how it is laid on. Every
## place that builds a face from another face calls this or `copy_texture_from()`,
## so a field added here reaches all of them.
##
## The corners are left alone, and so is what is laid against them, custom UVs and
## a sculpt: a caller matches corners before it hands those over. Paint is the
## caller's too, since a rebuild hands its layers over and a duplicate needs copies.
func copy_appearance_from(source: FaceData) -> void:
	copy_texture_from(source)
	copy_mapping_from(source)
	# How it shades is part of the look, but not of the mapping a texture group
	# shares (#1429).
	smoothing_group = source.smoothing_group


## Lay this face's texture on the way `source` lays its own: the projection, scale,
## offset and rotation, and the axes it was laid on with. What a texture group
## shares (#1437). Returns true when a field changed.
func copy_mapping_from(source: FaceData) -> bool:
	var differs: bool = (
		uv_projection != source.uv_projection
		or uv_scale != source.uv_scale
		or uv_offset != source.uv_offset
		or uv_rotation != source.uv_rotation
		or legacy_wall_axes != source.legacy_wall_axes
	)
	uv_projection = source.uv_projection
	uv_scale = source.uv_scale
	uv_offset = source.uv_offset
	uv_rotation = source.uv_rotation
	legacy_wall_axes = source.legacy_wall_axes
	return differs


## Put this face in the texture group `source` is in, with the group's last
## Justify. For the places that build the same face again: a resize, a cut's
## pieces, a vertex edit's hull, a native duplicate.
func copy_texture_group_from(source: FaceData) -> void:
	uv_group = source.uv_group
	uv_group_justify = source.uv_group_justify


## Give this face copies of `source`'s paint layers: the same textures, with
## weight masks of its own, so painting either face leaves the other alone.
func copy_paint_from(source: FaceData) -> void:
	var copies: Array[PaintLayer] = []
	for source_layer in source.paint_layers:
		if source_layer == null:
			continue
		var layer_copy := PaintLayer.new()
		layer_copy.texture = source_layer.texture
		layer_copy.weight_image = (
			source_layer.weight_image.duplicate() if source_layer.weight_image != null else null
		)
		layer_copy.blend_mode = source_layer.blend_mode
		layer_copy.opacity = source_layer.opacity
		copies.append(layer_copy)
	paint_layers = copies


## True when `other` has the look `copy_appearance_from()` copies. The two read the
## same fields, so a field added to one belongs in the other.
func appearance_matches(other: FaceData) -> bool:
	return (
		material_idx == other.material_idx
		and map_texture == other.map_texture
		and face_type == other.face_type
		and uv_projection == other.uv_projection
		and uv_scale == other.uv_scale
		and uv_offset == other.uv_offset
		and uv_rotation == other.uv_rotation
		and legacy_wall_axes == other.legacy_wall_axes
		and smoothing_group == other.smoothing_group
	)


## True when this face draws UVs that its projection, scale, offset and rotation
## would not give it: a layout dragged in the UV editor, which is not part of the
## look and does not travel with it. `custom_uvs` alone does not say so, since the
## UV boxes, Reset and the UV editor's canvas store the projected UVs there too.
func has_hand_layout() -> bool:
	if custom_uvs.is_empty() or custom_uvs.size() != local_verts.size():
		return false
	var projected := _project_uvs_for_vertices(local_verts)
	for i in custom_uvs.size():
		if not custom_uvs[i].is_equal_approx(projected[i]):
			return true
	return false


## Relabel the data laid against this face's corners, its custom UVs and its
## displacement grid, so that corner `i` takes what corner `(i + shift)` held.
## The corners themselves are left alone. This is the one definition of that
## relabelling: `start_face_at()` turns a face's corners and calls it to bring
## the data along, and a primitive rebuild calls it on a fresh face whose corners
## start somewhere other than the face it replaces.
##
## A sculpt is replaced rather than edited, because another face or an undo step
## can hold the same resource.
func relabel_corner_data(shift: int) -> void:
	var count := local_verts.size()
	if count == 0:
		return
	shift = posmod(shift, count)
	if shift == 0:
		return
	if custom_uvs.size() == count:
		var turned := PackedVector2Array()
		turned.resize(count)
		for i in count:
			turned[i] = custom_uvs[(i + shift) % count]
		custom_uvs = turned
	if count == 4 and displacement != null:
		var corner_from := PackedInt32Array()
		for i in 4:
			corner_from.append((i + shift) % 4)
		var sculpt: Resource = displacement.remapped(corner_from)
		if sculpt != null:
			displacement = sculpt


func adjust_uvs_for_transform(pos_delta: Vector3, size_ratio: Vector3) -> void:
	var projection = uv_projection
	if projection == UVProjection.BOX_UV:
		# `pos_delta` is a move through the level, so the axis is the one the
		# projection is using there.
		projection = _box_projection_axis_in(world_transform)
	if projection == UVProjection.CYLINDRICAL:
		return
	# The move as the projection reads it, along the face's own axes.
	var axes: Array = axes_for(projection)
	var offset_delta := Vector2(pos_delta.dot(axes[0]), pos_delta.dot(axes[1]))
	var inv_size = Vector2.ONE
	match projection:
		UVProjection.PLANAR_X:
			if size_ratio.z > 0.001 and size_ratio.y > 0.001:
				inv_size = Vector2(1.0 / size_ratio.z, 1.0 / size_ratio.y)
		UVProjection.PLANAR_Y:
			if size_ratio.x > 0.001 and size_ratio.z > 0.001:
				inv_size = Vector2(1.0 / size_ratio.x, 1.0 / size_ratio.z)
		UVProjection.PLANAR_Z:
			if size_ratio.x > 0.001 and size_ratio.y > 0.001:
				inv_size = Vector2(1.0 / size_ratio.x, 1.0 / size_ratio.y)
		UVProjection.FACE:
			inv_size = _face_resize_inverse(axes, size_ratio)
	# Rotation is applied before scale and offset in _apply_uv_transform, so the
	# projected move has to be rotated the same way before it is subtracted.
	var rotated_delta: Vector2 = offset_delta
	if uv_rotation != 0.0:
		rotated_delta = offset_delta.rotated(uv_rotation)
	uv_offset -= rotated_delta * uv_scale
	if not inv_size.is_equal_approx(Vector2.ONE):
		uv_scale *= inv_size


## What a resize by `size_ratio`, along the brush's own axes, does to the length of
## each of the Face projection's `axes`, as the factor Texture Lock scales by. The
## axes are the resized face's. A direction along a slope came from `S^-1 a` before
## a resize `S`, so a unit of it has grown by `1 / |S^-1 a|`, and the scale takes
## the inverse of that. On a wall this is the planar projections' own factor.
func _face_resize_inverse(axes: Array, size_ratio: Vector3) -> Vector2:
	if size_ratio.x <= 0.001 or size_ratio.y <= 0.001 or size_ratio.z <= 0.001:
		return Vector2.ONE
	var to_brush := world_transform.basis.orthonormalized().inverse()
	var out := Vector2.ONE
	for i in 2:
		out[i] = ((to_brush * (axes[i] as Vector3)) / size_ratio).length()
	return out


## Keep this face's texture on a brush mirrored across the world plane whose
## normal is `axis_index` and which crosses that axis at `plane`, so the face
## shows the mirror image of what it showed: the point the mirror sends `p` to
## reads the UV `p` read. Call it once the face sits where the mirror put it.
## Texture lock on a move holds the texture on the brush the same way.
##
## A planar projection reads two world axes. The mirror reverses the reading
## along its own axis and shifts it by twice the plane, and leaves the other one
## alone. The stored transform takes the reversal in its scale and the rotation
## turned the other way, the fold `adjust_uvs_for_rotation()` makes, and the shift
## in its offset. A projection that reads along neither axis faces the mirror,
## which already lands every point on one that reads the same. Cylindrical is
## taken in the brush's own space and goes with the brush.
##
## Custom UVs are laid on the corners, and the mirror carried those, so they stay.
## Returns true if the stored transform changed.
func adjust_uvs_for_mirror(axis_index: int, plane: float) -> bool:
	var projection = uv_projection
	if projection == UVProjection.BOX_UV:
		projection = _box_projection_axis_in(world_transform)
	if projection == UVProjection.CYLINDRICAL:
		return false
	var axis := clampi(axis_index, 0, 2)
	if projection == UVProjection.FACE:
		return _mirror_face_projection(axis, plane)
	var axes: Array = axes_for(projection)
	# How far each UV axis runs along the mirror's: one of them does, or neither.
	var along := Vector2((axes[0] as Vector3)[axis], (axes[1] as Vector3)[axis])
	if along.is_zero_approx():
		return false
	# The mirror reads `raw' = D * raw + t`, with D reversing the one axis, so the
	# old UV is `(R(r) * D * (raw' - t)) * s + o`. `R(r) * D` is `D * R(-r)`.
	var reversed := Vector2(
		-1.0 if not is_zero_approx(along.x) else 1.0, -1.0 if not is_zero_approx(along.y) else 1.0
	)
	var shift := along * (2.0 * plane)
	if uv_rotation != 0.0:
		shift = shift.rotated(uv_rotation)
		uv_rotation = wrapf(-uv_rotation, -PI, PI)
	uv_offset += shift * uv_scale
	uv_scale *= reversed
	return true


## `adjust_uvs_for_mirror()` for the Face projection, whose axes come off the face
## and so turn over with it. The mirror carries the axes the face read before onto
## its new plane, where they are the axes it reads now turned, or turned and
## mirrored, and that and the mirror's shift go into the stored fields.
func _mirror_face_projection(axis: int, plane: float) -> bool:
	var flip := Vector3.ONE
	flip[axis] = -1.0
	var mirror := Basis.from_scale(flip)
	var n_now := _normal_in(world_transform)
	# Before the mirror the face faced the mirror image of the way it faces now.
	var was: Array = face_axes_for(mirror * n_now)
	var carried: Array = [mirror * (was[0] as Vector3), mirror * (was[1] as Vector3)]
	var shift := Vector3.ZERO
	shift[axis] = 2.0 * plane
	return _keep_texture_through(_reading_between(carried, face_axes_for(n_now), shift))


## How a point's old reading follows from its new one, when it was read along
## `carried`, the axes read before taken to where the point is now, less `shift`
## along each, and is now read along `now`: the old reading is `result * new`.
static func _reading_between(carried: Array, now: Array, shift: Vector3) -> Transform2D:
	var cu: Vector3 = carried[0]
	var cv: Vector3 = carried[1]
	var nu: Vector3 = now[0]
	var nv: Vector3 = now[1]
	return Transform2D(
		Vector2(cu.dot(nu), cv.dot(nu)),
		Vector2(cu.dot(nv), cv.dot(nv)),
		Vector2(-shift.dot(cu), -shift.dot(cv))
	)


## The scale, rotation and offset that show at a point's new reading what `scale`,
## `rotation` and `offset` showed at its old one, when the old reading is
## `reading * new`. The reading has to be a turn, or a turn and a mirror, which the
## rotation and the sign of one scale can hold; anything else is a stretch, and
## the answer is empty. Returns `[scale, rotation, offset]`.
static func uv_fields_read_through(
	reading: Transform2D, scale: Vector2, rotation: float, offset: Vector2
) -> Array:
	var x := reading.x
	var y := reading.y
	if (
		absf(x.length() - 1.0) > UV_TURN_TOLERANCE
		or absf(y.length() - 1.0) > UV_TURN_TOLERANCE
		or absf(x.dot(y)) > UV_TURN_TOLERANCE
	):
		return []
	# The UV is `rotated(r) * s + o` of the reading, so what the old reading adds to
	# the new one lands in the offset, turned and scaled as the reading is.
	var moved := offset + reading.origin.rotated(rotation) * scale
	var turn := atan2(x.y, x.x)
	if reading.determinant() > 0.0:
		return [scale, wrapf(rotation + turn, -PI, PI), moved]
	# A mirror. `rot(t) * flip` is `flip * rot(-t)`, so it lands on the sign of a
	# scale and the rotation turned the other way: on U or on V, whichever leaves
	# the smaller turn, so a face mirrored across its U keeps its rotation.
	var turn_u := atan2(-x.y, -x.x)
	if absf(turn_u) <= absf(turn) + UV_TURN_TOLERANCE:
		return [Vector2(-scale.x, scale.y), wrapf(-(rotation + turn_u), -PI, PI), moved]
	return [Vector2(scale.x, -scale.y), wrapf(-(rotation + turn), -PI, PI), moved]


## Hold this face's texture where it is through a change of the axes it reads,
## `reading` from `_reading_between()`. Returns true when a stored field changed,
## false when none had to or the change is a stretch they cannot hold.
func _keep_texture_through(reading: Transform2D) -> bool:
	var fields := uv_fields_read_through(reading, uv_scale, uv_rotation, uv_offset)
	if fields.is_empty():
		return false
	var differs: bool = (
		not (fields[0] as Vector2).is_equal_approx(uv_scale)
		or absf(angle_difference(float(fields[1]), uv_rotation)) > UV_AXIS_EPSILON
		or not (fields[2] as Vector2).is_equal_approx(uv_offset)
	)
	if differs:
		uv_scale = fields[0]
		uv_rotation = fields[1]
		uv_offset = fields[2]
	return differs


## Whether an integer names one of this enum's projections.
##
## `uv_projection` is a bare `int`, and the projector falls through its `match`
## to the `(x, y)` branch for anything else — so an out of range value is stored,
## saved, reloaded and exported as a projection nobody chose and no dock control
## can show.
static func is_valid_projection(projection: int) -> bool:
	return projection >= 0 and projection <= UVProjection.FACE


## A smoothing group read from a file or a hand edit: a whole number from 0 to
## `MAX_SMOOTHING_GROUP`. Anything else reads as 0, flat, which is the one value
## that changes nothing.
static func read_smoothing_group(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return 0
	return int(clampf(float(value), 0.0, float(MAX_SMOOTHING_GROUP)))


## The two directions a planar projection reads, in (u, v) order.
##
## These are the axes `_project_uvs_for_vertices()` samples, written out so the
## texture-lock maths and the Valve 220 export can work with the projection
## rather than guess at it. They are qbsp's base axes turned Y-up: V runs down a
## wall, because Godot reads V = 0 as the top row of the image, and an X wall's U
## runs along -Z (#907). A floor reads (x, z), which was always right.
##
## `legacy` gives the axes a face marked `legacy_wall_axes` was laid on with: V
## up every wall and an X wall's U along +Z.
static func projection_axes(projection: int, legacy: bool = false) -> Array:
	match projection:
		UVProjection.PLANAR_X:
			return [Vector3.BACK, Vector3.UP] if legacy else [Vector3.FORWARD, Vector3.DOWN]
		UVProjection.PLANAR_Y:
			return [Vector3.RIGHT, Vector3.BACK]
		_:
			return [Vector3.RIGHT, Vector3.UP] if legacy else [Vector3.RIGHT, Vector3.DOWN]


## The two directions the Face projection reads on a face whose normal in the
## level is `world_normal`, in (u, v) order: U level along the face, V down its
## slope, both in its plane. U is `up x normal`, so seen from outside U runs to the
## right and V down, and no face reads its texture mirrored. A face with no level
## direction, a floor or a ceiling, reads Planar Y's axes.
static func face_axes_for(world_normal: Vector3) -> Array:
	var n := world_normal.normalized()
	var level := Vector3.UP.cross(n)
	if level.length() < UV_AXIS_EPSILON:
		return projection_axes(UVProjection.PLANAR_Y)
	var u := level.normalized()
	return [u, u.cross(n).normalized()]


## `axes` turned by `rotation`, the way `_apply_uv_transform()` turns a projected
## point before it scales it: the axes a reader that never applies a rotation has
## to be given.
##
## A Valve 220 reader projects with the axes as written and never applies the
## rotation field, which only records how the axes got there. Written unturned,
## every rotated face opened unrotated in another editor (#899). The rotation is
## still written, because the import reads it back onto the face's own axes.
static func turned_axes(axes: Array, rotation: float) -> Array:
	if rotation == 0.0:
		return axes
	var c := cos(rotation)
	var s := sin(rotation)
	return [axes[0] * c - axes[1] * s, axes[0] * s + axes[1] * c]


## Take the Face projection when the texture axes on a Valve 220 face line say the
## face was laid on in its own plane: both lie in it, and they are not the pair a
## world projection writes, Box UV's axes turned by the line's rotation as the
## export turns them. The offset, scale and rotation already hold the line's
## numbers. A reader projects with the axes as written, so the turn or mirror
## between them and the face's own goes into the rotation and the sign of a scale.
## Returns true when the face took it.
func read_map_axes(u_axis: Vector3, v_axis: Vector3) -> bool:
	if not u_axis.is_finite() or not v_axis.is_finite():
		return false
	if u_axis.is_zero_approx() or v_axis.is_zero_approx():
		return false
	var u := u_axis.normalized()
	var v := v_axis.normalized()
	var n := _normal_in(world_transform).normalized()
	if absf(u.dot(n)) > MAP_AXIS_IN_PLANE or absf(v.dot(n)) > MAP_AXIS_IN_PLANE:
		return false
	var world := turned_axes(axes_for(_box_projection_axis_in(world_transform)), uv_rotation)
	if (
		u.distance_to(world[0] as Vector3) < MAP_AXIS_MATCH
		and v.distance_to(world[1] as Vector3) < MAP_AXIS_MATCH
	):
		return false
	# The line reads a point along its own axes, unturned: `line = reading * own`.
	var reading := _reading_between([u, v], face_axes_in(world_transform), Vector3.ZERO)
	var fields := uv_fields_read_through(reading, uv_scale, 0.0, uv_offset)
	if fields.is_empty():
		return false
	var rotation: float = fields[1]
	# The rotation field says the same turn as the axes to more places, so it is
	# kept when the two agree.
	if (
		(fields[0] as Vector2).is_equal_approx(uv_scale)
		and absf(angle_difference(rotation, uv_rotation)) < MAP_AXIS_MATCH
	):
		rotation = uv_rotation
	uv_projection = UVProjection.FACE
	uv_scale = fields[0]
	uv_rotation = rotation
	uv_offset = fields[2]
	legacy_wall_axes = false
	custom_uvs = PackedVector2Array()
	return true


## Where `points`, on this face in its brush's space, fall on `projection` before
## the rotation, scale and offset: `(u, v)` along the axes it reads where the brush
## stands. Its own projection when `projection` is -1. Empty for Cylindrical, which
## reads an angle and a height rather than two axes.
func projected_points(points: PackedVector3Array, projection: int = -1) -> PackedVector2Array:
	var out := PackedVector2Array()
	var reading := uv_projection if projection < 0 else projection
	if reading == UVProjection.BOX_UV:
		reading = _box_projection_axis_in(world_transform)
	if reading == UVProjection.CYLINDRICAL:
		return out
	var axes: Array = axes_for(reading)
	for point in points:
		var v: Vector3 = world_transform * point
		out.append(Vector2(v.dot(axes[0]), v.dot(axes[1])))
	return out


## Whether `projection` lays a texture flat on this face: Cylindrical does not, nor
## does a planar axis the face is seen edge on from, whose two axes leave the face.
func projection_lies_on_face(projection: int) -> bool:
	var reading := projection
	if reading == UVProjection.BOX_UV:
		reading = _box_projection_axis_in(world_transform)
	if reading == UVProjection.CYLINDRICAL or not is_valid_projection(reading):
		return false
	var axes: Array = axes_for(reading)
	var across := (axes[0] as Vector3).cross(axes[1] as Vector3)
	return absf(across.dot(_normal_in(world_transform).normalized())) > PROJECTION_ACROSS_FACE


## The Face projection's axes for this face where `space` puts it.
func face_axes_in(space: Transform3D) -> Array:
	return face_axes_for(_normal_in(space))


## The way this face faces where `space` puts it.
func _normal_in(space: Transform3D) -> Vector3:
	return normal if space.basis.is_equal_approx(Basis.IDENTITY) else normal_through(space.basis)


## The world axes this face's texture is laid along, U then V, before its turn and
## scale: the ones its projection reads where its brush stands now. Empty for a
## Cylindrical face, which has no flat pair. The slide keys move a texture along
## these (#1728).
func texture_axes() -> Array:
	var projection := uv_projection
	if projection == UVProjection.BOX_UV:
		projection = _box_projection_axis_in(world_transform)
	if projection == UVProjection.CYLINDRICAL:
		return []
	return axes_for(projection)


## The axes this face reads for `projection`, old or new as the face was laid. The
## Face projection's come off the face where its brush now stands.
func axes_for(projection: int) -> Array:
	if projection == UVProjection.FACE:
		return face_axes_in(world_transform)
	return projection_axes(projection, legacy_wall_axes)


## This face's scale and rotation against the axes a new face reads, for a reader
## that knows no others: Classic Quake takes its axes from the plane. A legacy X
## wall reads both of those axes reversed, which a sign on the whole scale says.
## A legacy Z wall reads V reversed, which is a sign on the V scale and the
## rotation turned the other way. The offset means the same on both. Returns
## `[scale: Vector2, rotation: float]`.
func scale_and_rotation_on_current_axes() -> Array:
	if uv_projection == UVProjection.FACE:
		return _face_scale_and_rotation_on_world_axes()
	if not legacy_wall_axes:
		return [uv_scale, uv_rotation]
	var projection := uv_projection
	if projection == UVProjection.BOX_UV:
		projection = _box_projection_axis_in(world_transform)
	match projection:
		UVProjection.PLANAR_X:
			return [-uv_scale, uv_rotation]
		UVProjection.PLANAR_Z:
			return [Vector2(uv_scale.x, -uv_scale.y), -uv_rotation]
	return [uv_scale, uv_rotation]


## A Face projected face's scale and rotation against the world axes Box UV reads
## on it. On a face that faces along an axis its own axes are those, one perhaps
## reversed, so the look carries over whole. A slope has no such pair, and its own
## numbers go as they are.
func _face_scale_and_rotation_on_world_axes() -> Array:
	var world: Array = projection_axes(_box_projection_axis_in(world_transform))
	var reading := _reading_between(face_axes_in(world_transform), world, Vector3.ZERO)
	var fields := uv_fields_read_through(reading, uv_scale, uv_rotation, uv_offset)
	if fields.is_empty():
		return [uv_scale, uv_rotation]
	return [fields[0], fields[1]]


## Mark this face to keep the axes it was laid on with, when it was laid on by
## hand before #907: aligned, painted, or given UVs of its own. Run once over a
## face from before then. A face still on the defaults takes the new axes.
func keep_legacy_axes_if_laid_by_hand() -> void:
	if (
		not custom_uvs.is_empty()
		or not paint_layers.is_empty()
		or not uv_offset.is_zero_approx()
		or not uv_scale.is_equal_approx(Vector2.ONE)
		or not is_zero_approx(uv_rotation)
	):
		legacy_wall_axes = true


## Keep this face's texture on the brush while the brush turns.
##
## `local_rot` is the brush's rotation expressed in the brush's own space: a
## local point `v` ends up where `local_rot * v` used to be. Since #652 the
## projection is taken in the level, so a turn already moves the projection
## across the face and doing nothing leaves the texture where it was in the
## world. Carrying it round with the brush is the thing that needs saying, and
## it is said by reading the projection at `local_rot.inverse() * v` -- the turn
## cancelled rather than counted twice.
##
## That is the same reading as texture lock on a move, which holds the texture on
## a brush that slides. Before #652 it was the other way round, because a
## projection from a brush's own vertices did not move when the brush did, so the
## compensation was what unstuck the texture. Turn texture lock off and the
## texture stays where it is in the level, which is a projection from the level
## doing nothing at all.
##
## That only stays a projection of the same kind when the turn keeps the
## projection plane where it is — a turn about the projection axis, at any angle.
## Then the whole difference is a turn inside the UV plane, which `uv_rotation`
## can hold. A turn about any other axis swings the face out from under its own
## projection, and nothing the stored fields can say expresses that, so the face
## is left alone and its texture travels with the brush rather than being tipped
## on its side.
##
## Returns true if the UVs were adjusted.
func adjust_uvs_for_rotation(local_rot: Basis) -> bool:
	if uv_projection == UVProjection.CYLINDRICAL:
		return false
	if uv_projection == UVProjection.FACE:
		return _turn_face_projection(local_rot)
	var effective := uv_projection
	if effective == UVProjection.BOX_UV:
		effective = _box_projection_axis()
	var axes: Array = axes_for(effective)
	# The composed map reads the old projection axes pushed through the turn, so
	# these two vectors span the plane the projection would have to be.
	var f_u: Vector3 = local_rot * (axes[0] as Vector3)
	var f_v: Vector3 = local_rot * (axes[1] as Vector3)
	var kept: Vector3 = (axes[0] as Vector3).cross(axes[1] as Vector3)
	if absf(f_u.cross(f_v).dot(kept)) < 1.0 - UV_AXIS_EPSILON:
		return false
	# The change of basis from the projection's own axes to the pulled-back ones.
	# It is orthogonal, so it is a turn in the UV plane, possibly mirrored.
	var a00 := f_u.dot(axes[0])
	var a01 := f_u.dot(axes[1])
	var a10 := f_v.dot(axes[0])
	var a11 := f_v.dot(axes[1])
	var turn := atan2(a10, a00)
	if a00 * a11 - a01 * a10 >= 0.0:
		uv_rotation = wrapf(uv_rotation + turn, -PI, PI)
	else:
		# The turn put the plane back the other way up. `diag(sx, sy) * rot(r) *
		# diag(1, -1)` is the same map as `diag(sx, -sy) * rot(-r)`, which the
		# stored fields can hold, so the flip folds into the V scale.
		uv_rotation = wrapf(-(uv_rotation + turn), -PI, PI)
		uv_scale.y = -uv_scale.y
	custom_uvs = PackedVector2Array()
	return true


## `adjust_uvs_for_rotation()` for the Face projection. Its axes come off the face,
## so a yaw takes them round with the brush and leaves nothing to do, and a tilt
## hangs them afresh from the tilted face: a turn in the UV plane from where the
## brush took them, which the rotation holds. As for the planar projections only
## the turn is held. `world_transform` is where the brush stands after it.
func _turn_face_projection(local_rot: Basis) -> bool:
	if is_zero_approx(local_rot.determinant()):
		return false
	var now := world_transform.basis
	var was := now * local_rot.inverse()
	if is_zero_approx(was.determinant()):
		return false
	# A point read along `a` before the turn is read along this carried `a` after
	# it: the inverse transpose, so a brush stretched out of true reads as the
	# stretch it is and is left alone.
	var carry := normal_basis(now * was.inverse())
	var was_axes: Array = face_axes_for(normal_through(was))
	var carried: Array = [carry * (was_axes[0] as Vector3), carry * (was_axes[1] as Vector3)]
	if not _keep_texture_through(
		_reading_between(carried, face_axes_in(world_transform), Vector3.ZERO)
	):
		return false
	custom_uvs = PackedVector2Array()
	return true


func triangulate() -> Dictionary:
	var tri_verts := PackedVector3Array()
	var tri_uvs := PackedVector2Array()
	var count = local_verts.size()
	if count < 3:
		return {"verts": tri_verts, "uvs": tri_uvs}
	var source_uvs = custom_uvs
	if source_uvs.size() != count:
		source_uvs = _project_uvs_for_vertices(local_verts)
	# Displacement path: delegate to HFDisplacementData for subdivided mesh.
	if displacement != null and count == 4:
		var corners: Array[Vector3] = [
			local_verts[0], local_verts[1], local_verts[3], local_verts[2]
		]
		var uv_corners: Array[Vector2] = [
			source_uvs[0], source_uvs[1], source_uvs[3], source_uvs[2]
		]
		var result: Dictionary = displacement.triangulate_displaced(corners, normal, uv_corners)
		return {
			"verts": result.get("verts", tri_verts),
			"uvs": result.get("uvs", tri_uvs),
			"normals": result.get("normals", PackedVector3Array())
		}
	for i in range(1, count - 1):
		tri_verts.append(local_verts[0])
		tri_verts.append(local_verts[i])
		tri_verts.append(local_verts[i + 1])
		tri_uvs.append(source_uvs[0])
		tri_uvs.append(source_uvs[i])
		tri_uvs.append(source_uvs[i + 1])
	return {"verts": tri_verts, "uvs": tri_uvs}


## Composites the face's paint layers into a single albedo image.
##
## The returned image is cached and shared — treat it as read-only. Both callers
## (`Baker` and `BrushInstance`) hand it to `ImageTexture.create_from_image()`,
## which copies.
func get_painted_albedo(max_size: int = 512) -> Image:
	var layers: Array = paint_layers
	if layers.is_empty():
		_invalidate_albedo_cache()
		return null
	if _albedo_cache != null and _albedo_cache_key_for(max_size) == _albedo_cache_key:
		return _albedo_cache
	var target_w = 0
	var target_h = 0
	for layer in layers:
		if layer == null:
			continue
		if layer.weight_image:
			target_w = max(target_w, layer.weight_image.get_width())
			target_h = max(target_h, layer.weight_image.get_height())
		elif layer.texture and layer.texture is Texture2D:
			var img = layer.texture.get_image()
			target_w = max(target_w, img.get_width())
			target_h = max(target_h, img.get_height())
	if target_w <= 0 or target_h <= 0:
		_invalidate_albedo_cache()
		return null
	if max_size > 0:
		var scale = min(1.0, float(max_size) / float(max(target_w, target_h)))
		target_w = max(1, int(round(target_w * scale)))
		target_h = max(1, int(round(target_h * scale)))
	var out = Image.create(target_w, target_h, false, Image.FORMAT_RGBA8)
	out.fill(Color(1, 1, 1, 1))
	var tex_cache: Dictionary = {}
	for layer in layers:
		if layer == null or layer.opacity <= 0.0:
			continue
		if not layer.texture or not layer.texture is Texture2D:
			continue
		var tex_key = layer.texture.resource_path
		var tex_img: Image
		if tex_key != "" and tex_cache.has(tex_key):
			tex_img = tex_cache[tex_key]
		else:
			var source_img = layer.texture.get_image()
			if source_img == null or source_img.is_empty():
				continue
			# Always copy: get_image() can hand back the texture's live image, and a
			# compressed format has to be expanded before get_pixel() can read it.
			tex_img = source_img.duplicate() as Image
			if tex_img.is_compressed():
				if tex_img.decompress() != OK:
					continue
			if tex_img.get_width() != target_w or tex_img.get_height() != target_h:
				tex_img.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
			if tex_key != "":
				tex_cache[tex_key] = tex_img
		var paint_img = layer.weight_image
		if paint_img == null or paint_img.is_empty():
			layer.ensure_weight_image(Vector2i(target_w, target_h))
			paint_img = layer.weight_image
		if paint_img.get_width() != target_w or paint_img.get_height() != target_h:
			paint_img = paint_img.duplicate() as Image
			paint_img.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
		for y in range(target_h):
			for x in range(target_w):
				var w = clamp(paint_img.get_pixel(x, y).r * layer.opacity, 0.0, 1.0)
				if w <= 0.0:
					continue
				var base = out.get_pixel(x, y)
				var tex = tex_img.get_pixel(x, y)
				var blended = _blend_color(base, tex, w, layer.blend_mode)
				out.set_pixel(x, y, blended)
	_albedo_cache = out
	# Re-key rather than reusing cache_key: the loop above can call
	# ensure_weight_image() on a texture-only layer, which changes the signature.
	_albedo_cache_key = _albedo_cache_key_for(max_size)
	return out


## Drops the memoised composite. Call after mutating paint layers outside
## `get_painted_albedo()`; the key covers the ordinary edits already.
func invalidate_painted_albedo() -> void:
	_invalidate_albedo_cache()


func _invalidate_albedo_cache() -> void:
	_albedo_cache = null
	_albedo_cache_key = ""


## Builds a signature for the current paint inputs.
##
## Weight images are hashed by content, so any paint stroke misses the cache.
## Textures are identified by resource path (falling back to instance id) and
## size rather than content: palette textures are immutable resources, and
## swapping one assigns a different texture instance. A texture edited in place
## under the same path is the gap here — call `invalidate_painted_albedo()`.
func _albedo_cache_key_for(max_size: int) -> String:
	var parts: PackedStringArray = [str(max_size), str(paint_layers.size())]
	for layer in paint_layers:
		if layer == null:
			parts.append("-")
			continue
		var tex_id := "none"
		if layer.texture:
			tex_id = layer.texture.resource_path
			if tex_id == "":
				tex_id = "id%d" % layer.texture.get_instance_id()
			tex_id += "@%s" % layer.texture.get_size()
		var weight_id := "none"
		if layer.weight_image and not layer.weight_image.is_empty():
			weight_id = (
				"%dx%d#%d"
				% [
					layer.weight_image.get_width(),
					layer.weight_image.get_height(),
					hash(layer.weight_image.get_data())
				]
			)
		parts.append("%s|%s|%d|%.4f" % [tex_id, weight_id, layer.blend_mode, layer.opacity])
	return "\n".join(parts)


func to_dict() -> Dictionary:
	var layer_data: Array = []
	for layer in paint_layers:
		if layer == null:
			continue
		var entry: Dictionary = {
			"texture_path": layer.texture.resource_path if layer.texture else "",
			"blend_mode": layer.blend_mode,
			"opacity": layer.opacity
		}
		if layer.weight_image and not layer.weight_image.is_empty():
			var png_bytes = layer.weight_image.save_png_to_buffer()
			entry["weight_png"] = Marshalls.raw_to_base64(png_bytes)
			entry["weight_w"] = layer.weight_image.get_width()
			entry["weight_h"] = layer.weight_image.get_height()
		layer_data.append(entry)
	var out := {
		"material_idx": material_idx,
		"map_texture": map_texture,
		"uv_projection": uv_projection,
		"uv_scale": _encode_vec2(uv_scale),
		"uv_offset": _encode_vec2(uv_offset),
		"uv_rotation": uv_rotation,
		"uv_format_version": 3,
		"legacy_wall_axes": legacy_wall_axes,
		"smoothing_group": smoothing_group,
		"winding_version": 3,
		"custom_uvs": _encode_vec2_array(custom_uvs),
		"local_verts": _encode_vec3_array(local_verts),
		"normal": _encode_vec3(normal),
		"paint_layers": layer_data,
		"displacement": displacement.to_dict() if displacement != null else null
	}
	# Only on a face that is not a plain one, so a level with none writes what it
	# always did.
	if face_type != FaceType.NORMAL:
		out["face_type"] = face_type
	# Only on a face in a group, so a level with none writes what it always did.
	if uv_group != 0:
		out["uv_group"] = uv_group
		out["uv_group_justify"] = uv_group_justify
	return out


## A face out of its saved record. A hand edit, a merge or a sync that cut the
## file short can leave anything where a value was, so each is read as what it
## should be or its default, never cast blind (#1641).
static func from_dict(data: Dictionary) -> FaceData:
	var face = FaceData.new()
	face.material_idx = _read_whole(data.get("material_idx", -1), -1)
	face.map_texture = str(data.get("map_texture", ""))
	face.face_type = read_face_type(data.get("face_type"))
	# A record that does not say reads as Box UV, which is what a new face starts
	# on (#463). PLANAR_Z flattened every floor and every east or west wall of a
	# brush built from such a record, which is every non-box brush a `.map`
	# import makes (#909).
	var stored_projection := _read_whole(data.get("uv_projection"), UVProjection.BOX_UV)
	if not is_valid_projection(stored_projection):
		# An older or newer file, or a hand edit. The enum has to mean something.
		stored_projection = UVProjection.BOX_UV
	face.uv_projection = stored_projection
	face.uv_scale = _decode_vec2(data.get("uv_scale", null), Vector2.ONE)
	face.uv_offset = _decode_vec2(data.get("uv_offset", null), Vector2.ZERO)
	face.uv_rotation = _read_number(data.get("uv_rotation"), 0.0)
	# A record from before #1429 has none, and reads as flat, which is how it baked.
	face.smoothing_group = read_smoothing_group(data.get("smoothing_group", 0))
	face.custom_uvs = _decode_vec2_array(_read_list(data.get("custom_uvs")))
	face.local_verts = _decode_vec3_array(_read_list(data.get("local_verts")))
	face.normal = _decode_vec3(data.get("normal", null), Vector3.UP)
	face.paint_layers.clear()
	var layers: Array = _read_list(data.get("paint_layers"))
	for entry in layers:
		if not (entry is Dictionary):
			continue
		var layer = PaintLayer.new()
		var texture_path = str(entry.get("texture_path", ""))
		if texture_path != "" and ResourceLoader.exists(texture_path):
			var tex = ResourceLoader.load(texture_path)
			if tex is Texture2D:
				layer.texture = tex
		layer.blend_mode = _read_whole(entry.get("blend_mode"), PaintBlend.OVERLAY)
		layer.opacity = _read_number(entry.get("opacity"), 1.0)
		var b64 = str(entry.get("weight_png", ""))
		if b64 != "":
			var raw = Marshalls.base64_to_raw(b64)
			if raw.size() > 0:
				var img = Image.new()
				if img.load_png_from_buffer(raw) == OK:
					layer.weight_image = img
		if layer.weight_image == null or layer.weight_image.is_empty():
			var w := clampi(_read_whole(entry.get("weight_w"), 256), 1, 4096)
			var h := clampi(_read_whole(entry.get("weight_h"), 256), 1, 4096)
			layer.ensure_weight_image(Vector2i(w, h))
		face.paint_layers.append(layer)
	face.ensure_geometry()
	# Migrate v0 UV data: old order was (uv * scale + offset).rotated(R),
	# new order is uv.rotated(R) * scale + offset. Only affects faces with
	# non-zero rotation.
	var uv_fmt: int = _read_whole(data.get("uv_format_version"), 0)
	# v2 moved the planar projection out of the brush's space and into the
	# level's (#652), which changes what `uv_offset` measures from. A face
	# cannot fold that in here, because it does not know where its brush is
	# until the brush tells it. Record the version and let the brush do it.
	if uv_fmt < 2:
		face.pending_uv_migration = uv_fmt
	if uv_fmt < 1 and face.uv_rotation != 0.0:
		if is_equal_approx(face.uv_scale.x, face.uv_scale.y):
			# Uniform scale: rotation commutes with scale, only offset changes.
			# Old: rotate(uv*s + O, R) = rotate(uv,R)*s + rotate(O,R)
			face.uv_offset = face.uv_offset.rotated(face.uv_rotation)
		else:
			# Non-uniform scale: can't represent with same params. Bake UVs
			# using old transform order, then clear parametric transforms.
			if face.local_verts.size() >= 3 and face.custom_uvs.size() != face.local_verts.size():
				face.custom_uvs = face._project_uvs_v0(face.local_verts)
			elif face.custom_uvs.size() == face.local_verts.size():
				# custom_uvs were already baked with old transform — re-apply
				# the old rotation that was previously baked in at save time.
				pass  # custom_uvs are already correct from the old save
			face.uv_rotation = 0.0
			face.uv_scale = Vector2.ONE
			face.uv_offset = Vector2.ZERO
	# v3 turned the wall axes the right way up (#907). A face from before then
	# keeps its old axes if anybody laid it on, read off what it was saved with.
	if uv_fmt < 3:
		face.keep_legacy_axes_if_laid_by_hand()
	else:
		# Only a switch counts: comparing a damaged number with `true` is a script error.
		var legacy: Variant = data.get("legacy_wall_axes")
		face.legacy_wall_axes = legacy is bool and legacy
	# Displacement data
	var disp_data: Variant = data.get("displacement", null)
	if disp_data is Dictionary:
		face.displacement = HFDisplacementData.from_dict(disp_data)
	face.uv_group = _read_whole(data.get("uv_group"), 0)
	face.uv_group_justify = str(data.get("uv_group_justify", "")) if face.uv_group != 0 else ""
	return face


static func _encode_vec2(value: Vector2) -> Array:
	return [value.x, value.y]


static func _encode_vec3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _decode_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2 and _numbers(value, 2):
		return Vector2(float(value[0]), float(value[1]))
	return fallback


static func _decode_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3 and _numbers(value, 3):
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


## A number a record holds, or `fallback` for anything that is not one.
static func _read_number(value: Variant, fallback: float) -> float:
	return float(value) if value is float or value is int else fallback


## A whole number a record holds, or `fallback` for anything that is not a number
## a whole one fits.
static func _read_whole(value: Variant, fallback: int) -> int:
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	if absf(float(value)) > 2147483647.0:
		return fallback
	return int(value)


static func _read_list(value: Variant) -> Array:
	return value if value is Array else []


## Whether the first `count` entries of `values` are numbers.
static func _numbers(values: Array, count: int) -> bool:
	for i in count:
		if not (values[i] is float or values[i] is int):
			return false
	return true


static func _encode_vec2_array(values: PackedVector2Array) -> Array:
	var out: Array = []
	for v in values:
		out.append([v.x, v.y])
	return out


static func _encode_vec3_array(values: PackedVector3Array) -> Array:
	var out: Array = []
	for v in values:
		out.append([v.x, v.y, v.z])
	return out


static func _decode_vec2_array(values: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in values:
		if entry is Array and entry.size() >= 2 and _numbers(entry, 2):
			out.append(Vector2(float(entry[0]), float(entry[1])))
	return out


static func _decode_vec3_array(values: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for entry in values:
		if entry is Array and entry.size() >= 3 and _numbers(entry, 3):
			out.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
	return out


func _project_uvs_for_vertices(verts: PackedVector3Array) -> PackedVector2Array:
	return _project_uvs_in_space(verts, world_transform)


## The UVs this face shows at `points`, which lie on it: read off the triangles it
## draws, as the renderer reads them. A piece of a Cylindrical face has to keep
## these. Projecting the piece afresh would measure the height over the piece
## rather than the face, and its angle exactly rather than as the face's
## triangles spread it, and either one moves the texture (#868).
func shown_uvs_at(points: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := local_verts.size()
	if count < 3:
		return out
	var uvs := custom_uvs
	if uvs.size() != count:
		uvs = _project_uvs_for_vertices(local_verts)
	for point in points:
		# The fan `triangulate()` draws. A point a rounding error outside every
		# triangle takes the one it is least outside of.
		var best := uvs[0]
		var best_outside := INF
		for i in range(1, count - 1):
			var w: Vector3 = Geometry3D.get_triangle_barycentric_coords(
				point, local_verts[0], local_verts[i], local_verts[i + 1]
			)
			if not w.is_finite():
				continue
			var outside := -minf(0.0, minf(w.x, minf(w.y, w.z)))
			if outside < best_outside:
				best_outside = outside
				best = uvs[0] * w.x + uvs[i] * w.y + uvs[i + 1] * w.z
		out.append(best)
	return out


## The projection, in whatever space the caller asks for. `Transform3D.IDENTITY`
## is what the projection did before #652, which is what the migration folds out.
func _project_uvs_in_space(verts: PackedVector3Array, space: Transform3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	var projection = uv_projection
	if projection == UVProjection.BOX_UV:
		projection = _box_projection_axis_in(space)
	var aabb = _compute_bounds_for(verts)
	var height = max(0.001, aabb.size.y)
	# An out of range value reads as PLANAR_Z, which is what `axes_for()` gives it.
	# The Face projection's axes are asked of `space`, as Box UV's axis is.
	var axes: Array = (
		face_axes_in(space) if projection == UVProjection.FACE else axes_for(projection)
	)
	for local in verts:
		# World space, so the same face in two places gets two patches of texture
		# and a run of brushes reads as one surface (#652). Cylindrical keeps its
		# own space: its angle is measured about the brush's own axis, and taking
		# that in world space would spin the texture as the brush moved.
		var v: Vector3 = local if projection == UVProjection.CYLINDRICAL else space * local
		var uv = Vector2.ZERO
		if projection == UVProjection.CYLINDRICAL:
			var angle = atan2(v.z, v.x) / TAU + 0.5
			# From the top down, so the top of the image is at the top (#907).
			var from_top = aabb.end.y - v.y if not legacy_wall_axes else v.y - aabb.position.y
			uv = Vector2(angle, from_top / height)
		else:
			uv = Vector2(v.dot(axes[0]), v.dot(axes[1]))
		uv = _apply_uv_transform(uv)
		out.append(uv)
	return out


## Fold a brush's placement into a hand-tuned `uv_offset`, so an alignment a
## mapper set before #652 survives the move to world-space projection.
##
## Before v2 a planar UV was projected from the brush's own vertices, so an
## offset meant "shift the texture along the brush". It now means "shift it
## along the level", and the two differ by wherever the brush is. Folding that
## in is the same sum texture lock does for a move, because moving a brush and
## changing the space it projects in do the same thing to the result.
##
## Only an offset somebody set is folded in. A face still on zero was never
## positioned by hand, and giving it one would put it back where #652 says it
## should not be, with the panels of a wall on the same patch of texture again.
## Those faces take the new projection, which is the fix arriving.
##
## A rotated brush cannot be corrected by an offset at all: world projection is
## a different map there, not the same one shifted. Those faces keep their old
## look the way the v0 to v1 migration keeps a non-uniform scale, by baking it
## into `custom_uvs`.
func migrate_uvs_to_world_space() -> void:
	var from_version := pending_uv_migration
	pending_uv_migration = -1
	if from_version < 0 or from_version >= 2:
		return
	if uv_offset.is_zero_approx():
		return
	if world_transform.is_equal_approx(Transform3D.IDENTITY):
		return
	var projection = uv_projection
	if projection == UVProjection.BOX_UV:
		projection = _box_projection_axis()
	# Cylindrical never left the brush's space, so it has nothing to fold in.
	if projection == UVProjection.CYLINDRICAL:
		return
	if not world_transform.basis.is_equal_approx(Basis.IDENTITY):
		if local_verts.size() >= 3 and custom_uvs.size() != local_verts.size():
			custom_uvs = _project_uvs_in_space(local_verts, Transform3D.IDENTITY)
		return
	# Along the axes the face was laid on with, which for anything this old with
	# an offset set are the ones from before #907.
	var origin := world_transform.origin
	var axes: Array = axes_for(projection)
	var placement := Vector2(origin.dot(axes[0]), origin.dot(axes[1]))
	# Rotation is applied before the scale and the offset, so the placement has
	# to be rotated the same way before it is taken back out.
	if uv_rotation != 0.0:
		placement = placement.rotated(uv_rotation)
	uv_offset -= placement * uv_scale


## Keep a face's texture the right way round when a turn moves it onto a
## different Box UV axis.
##
## The three planar projections do not share a handedness. That could not matter
## while UVs were projected from a brush's own vertices, because a face's axis
## could not change. Since #652 the axis is resolved in the level, so a wall
## yawed a quarter turn moves from PLANAR_Z to PLANAR_X and could come back
## mirrored (#684). qbsp's axes, which faces use since #907, carry a yaw the one
## way and a roll from the floor without one, and the old ones did not; the
## comparison below finds that out for itself.
##
## The correction is a sign on `uv_scale`, folded in at the moment the axis
## changes. Nothing on disk changes meaning, so no saved level needs migrating:
## a face reloaded after a turn already carries the flip in the scale it saved.
##
## Which of the two axes to flip is not a fixed answer. A yaw that takes a face
## from PLANAR_Z to PLANAR_X reverses U and leaves V; a roll that takes one from
## PLANAR_Y to PLANAR_Z reverses V and leaves U. So the old projection's axes are
## carried through the turn the brush made and compared with the new one's.
## A turn that does not land them on each other is a skew no planar projection
## holds, and is left alone rather than guessed at.
func reconcile_box_uv_axis() -> void:
	var basis := world_transform.basis.orthonormalized()
	# A face on another projection is laid against wherever the brush now is, so
	# one turned while on the Face projection and put back on Box UV with Align to
	# World is not read as a turn made under Box UV and mirrored (#1419).
	if uv_projection != UVProjection.BOX_UV:
		_uv_layout_basis = basis
		_uv_layout_known = true
		return
	if not _uv_layout_known:
		_uv_layout_basis = basis
		_uv_layout_known = true
		return
	if basis.is_equal_approx(_uv_layout_basis):
		return
	var was := _uv_layout_basis
	_uv_layout_basis = basis
	var old_axis := _box_projection_axis_in(Transform3D(was, Vector3.ZERO))
	var new_axis := _box_projection_axis_in(Transform3D(basis, Vector3.ZERO))
	if old_axis == new_axis:
		# The face kept its plane. `adjust_uvs_for_rotation()` is what answers
		# for that case, and it is the caller's business whether to run it.
		return
	var turn := basis * was.inverse()
	var old_axes: Array = axes_for(old_axis)
	var new_axes: Array = axes_for(new_axis)
	var carried_u: Vector3 = (turn * (old_axes[0] as Vector3)).normalized()
	var carried_v: Vector3 = (turn * (old_axes[1] as Vector3)).normalized()
	var u_now: Vector3 = new_axes[0] as Vector3
	var v_now: Vector3 = new_axes[1] as Vector3
	var u_dot := u_now.dot(carried_u)
	var v_dot := v_now.dot(carried_v)
	if absf(u_dot) < 1.0 - UV_AXIS_EPSILON or absf(v_dot) < 1.0 - UV_AXIS_EPSILON:
		return
	if u_dot < 0.0:
		uv_scale.x = -uv_scale.x
	if v_dot < 0.0:
		uv_scale.y = -uv_scale.y


## Take `basis` as the orientation this face's UVs are laid out against, so a
## brush standing in it reads to `reconcile_box_uv_axis()` as no turn at all.
## For a change of basis that turns nothing in the world: Apply Rotation and Scale
## folds the basis into the corners (#1435), so every face still faces the way it
## did and Box UV still picks the axis it picked. Measured against the old basis,
## the folded normal would read as a turn and flip the texture.
func keep_uv_layout_in(basis: Basis) -> void:
	_uv_layout_basis = basis.orthonormalized()
	_uv_layout_known = true


func _apply_uv_transform(uv: Vector2) -> Vector2:
	var out = uv
	if uv_rotation != 0.0:
		out = out.rotated(uv_rotation)
	out = out * uv_scale + uv_offset
	return out


## `_apply_uv_transform()` as one map, so a change of scale, offset or rotation can
## be carried over to UVs laid out by hand.
func uv_transform() -> Transform2D:
	return Transform2D(
		Vector2(1.0, 0.0).rotated(uv_rotation) * uv_scale,
		Vector2(0.0, 1.0).rotated(uv_rotation) * uv_scale,
		uv_offset
	)


## Old (v0) transform order: scale+offset first, then rotate.
## Used only for migrating persisted data from before uv_format_version 1.
func _apply_uv_transform_v0(uv: Vector2) -> Vector2:
	var out = uv * uv_scale + uv_offset
	if uv_rotation != 0.0:
		out = out.rotated(uv_rotation)
	return out


## Project UVs using the old (v0) transform order for migration.
func _project_uvs_v0(verts: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var projection = uv_projection
	if projection == UVProjection.BOX_UV:
		projection = _box_projection_axis()
	var aabb = _compute_bounds_for(verts)
	var height = max(0.001, aabb.size.y)
	for v in verts:
		var uv = Vector2.ZERO
		match projection:
			UVProjection.PLANAR_X:
				uv = Vector2(v.z, v.y)
			UVProjection.PLANAR_Y:
				uv = Vector2(v.x, v.z)
			UVProjection.PLANAR_Z:
				uv = Vector2(v.x, v.y)
			UVProjection.CYLINDRICAL:
				var angle = atan2(v.z, v.x) / TAU + 0.5
				var vcoord = (v.y - aabb.position.y) / height
				uv = Vector2(angle, vcoord)
			_:
				uv = Vector2(v.x, v.y)
		uv = _apply_uv_transform_v0(uv)
		out.append(uv)
	return out


## Which planar axis Box UV resolves to, measured in `space`.
##
## Box UV picks the axis the face most nearly faces, so it has to be asked in
## the same space the projection is taken in. Asking in the brush's space while
## projecting in the level's is how a wall yawed a quarter turn kept `PLANAR_Z`
## and then projected world (x, y) onto a plane of constant x: every vertex got
## the same u and the texture smeared into a line (#652).
##
## Measured by the way the face really faces in `space`. Carried by the basis
## alone, a slope on a stretched brush leans towards the stretched axis and could
## take the other axis, which drew its texture several times too long and put a
## different axis in the viewport from the one the Valve 220 export writes (#887).
func _box_projection_axis_in(space: Transform3D) -> int:
	var n := _normal_in(space)
	var ax = abs(n.x)
	var ay = abs(n.y)
	var az = abs(n.z)
	if ax >= ay and ax >= az:
		return UVProjection.PLANAR_X
	if ay >= ax and ay >= az:
		return UVProjection.PLANAR_Y
	return UVProjection.PLANAR_Z


## The axis as the face's own brush sees it. `adjust_uvs_for_rotation()` reasons
## in that space, and both migrations measure against what the old projection did.
func _box_projection_axis() -> int:
	var n = normal
	var ax = abs(n.x)
	var ay = abs(n.y)
	var az = abs(n.z)
	if ax >= ay and ax >= az:
		return UVProjection.PLANAR_X
	if ay >= ax and ay >= az:
		return UVProjection.PLANAR_Y
	return UVProjection.PLANAR_Z


func _compute_bounds() -> void:
	bounds = _compute_bounds_for(local_verts)


func _compute_bounds_for(verts: PackedVector3Array) -> AABB:
	if verts.is_empty():
		return AABB()
	var aabb = AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	return aabb


func _compute_normal() -> void:
	if local_verts.size() < 3:
		normal = Vector3.UP
		return
	# A face with a vertex that is not a number has no normal, and asking for one
	# is an engine error per call rather than a value. The validator reports the
	# vertex; this just stops the noise.
	for v in local_verts:
		if not v.is_finite():
			normal = Vector3.UP
			return
	# Newell's method over the whole polygon, not the first three vertices.
	# Three consecutive vertices can be collinear without the face being
	# degenerate: `split_edge()` inserts a midpoint *on* an edge, and when the
	# split edge is the one at index 0 the first three vertices are collinear by
	# construction. The first-three cross product then measured zero, the
	# degenerate fallback fired, and a side wall was told it faced up — which is
	# what `validate_convexity()`, the bake and the `.map` export all read.
	#
	# The vertices are made relative to the first one and scaled by the face's
	# own extent before the sum, so what is measured is the shape rather than its
	# area. An absolute floor on the raw sum would call any small face
	# degenerate, which is the bug the previous comment here was about: a
	# 0.01-unit bevel cap came out facing into the solid whatever winding it was
	# built with, and the same is true of every tessellation sliver. Newell's sum
	# is translation invariant, so the shift costs nothing.
	var origin: Vector3 = local_verts[0]
	var extent := 0.0
	for v in local_verts:
		var offset: Vector3 = v - origin
		extent = maxf(extent, maxf(absf(offset.x), maxf(absf(offset.y), absf(offset.z))))
	if extent <= 0.0:
		normal = Vector3.UP
		return
	var inv_extent := 1.0 / extent
	var count := local_verts.size()
	var n := Vector3.ZERO
	for i in count:
		var current: Vector3 = (local_verts[i] - origin) * inv_extent
		var next: Vector3 = (local_verts[(i + 1) % count] - origin) * inv_extent
		n.x += (current.y - next.y) * (current.z + next.z)
		n.y += (current.z - next.z) * (current.x + next.x)
		n.z += (current.x - next.x) * (current.y + next.y)
	# Negated, because HammerForge winds a face clockwise seen from outside and
	# Newell's sum follows the other hand. This is the winding the old
	# `(c - a).cross(b - a)` produced.
	n = -n
	if n.length() > 0.0001:
		normal = n.normalized()
	else:
		normal = Vector3.UP


## The material a painted face renders with: the base with the composited albedo
## on it, and everything else about it kept.
##
## This used to build a bare `StandardMaterial3D` and copy three scalars across -
## `roughness`, `metallic` and `albedo_color` - so painting a face threw away its
## normal map, its roughness and metallic maps, its emission and its UV
## transform. On a tiled wall the UV scale going back to 1 is the visible one:
## the texture on the painted face is suddenly four times the size of the one
## beside it. Duplicating the base keeps all of it, including slots added to
## `StandardMaterial3D` in a future Godot version.
##
## A `ShaderMaterial` is refused rather than substituted. There is no way to
## reproduce one with an albedo texture on it, and building a plain
## `StandardMaterial3D` instead left one baked surface flat beside its
## neighbours with the shader silently gone. `HFMaterialAtlas.build_atlas()`
## already treats a ShaderMaterial this way, putting it in `fallback_keys` rather
## than pretending it can pack it. The base comes back unpainted, with a warning.
## The material this face draws with: its palette slot, else `brush_material`,
## else `fallback`, with its paint laid over whichever that is when
## `include_paint`. Null when it has none of them.
##
## The bake and the brush preview both ask this, so a face cannot bake in another
## material from the one it shows (#902). `material_manager` answers
## `get_material(index)`.
func resolved_material(
	material_manager: Object,
	brush_material: Material,
	fallback: Material,
	include_paint: bool = true
) -> Material:
	# One look for every Hidden face of a level, whatever it is painted with: the
	# preview draws its pattern and the bake knows it by it (#1719).
	if is_hidden():
		return HFHiddenFaces.material_for(material_manager)
	var base: Material = null
	if material_manager and material_idx >= 0:
		base = material_manager.get_material(material_idx)
	if base == null and brush_material:
		base = brush_material
	if base == null and fallback:
		base = fallback
	if include_paint:
		var painted = get_painted_albedo()
		if painted:
			return composite_painted_material(base, painted)
	return base


static func composite_painted_material(base: Material, painted: Image) -> Material:
	if painted == null:
		return base
	var tex := ImageTexture.create_from_image(painted)
	if tex == null:
		return base
	return paint_over(base, tex)


## `base` with `paint` as its albedo, the way `composite_painted_material()` lays
## it. The bake lays paint again this way when the material it was laid over is
## the editor's look, which stays behind (`HFBakeSystem._baked_material()`).
static func paint_over(base: Material, paint: Texture2D) -> Material:
	if base is ShaderMaterial:
		_warn_once_about_shader_paint(base)
		return base
	var mat: StandardMaterial3D
	if base is StandardMaterial3D:
		mat = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		# No palette material, or one this cannot read. The composite is the
		# whole surface.
		mat = StandardMaterial3D.new()
	mat.albedo_texture = paint
	return mat


## Once per material, not once per face per rebuild. `rebuild_preview()` runs on
## every paint sample.
static var _shader_paint_warned: Dictionary = {}


static func _warn_once_about_shader_paint(base: Material) -> void:
	var id := base.get_instance_id()
	if _shader_paint_warned.has(id):
		return
	_shader_paint_warned[id] = true
	(
		HFLog
		. warn(
			(
				"HammerForge: a face painted over a ShaderMaterial keeps the shader and drops the paint."
				+ " A shader cannot be composited over."
			)
		)
	)


func _blend_color(base: Color, tex: Color, weight: float, mode: int) -> Color:
	match mode:
		PaintBlend.MULTIPLY:
			var mult = Color(
				lerp(1.0, tex.r, weight), lerp(1.0, tex.g, weight), lerp(1.0, tex.b, weight), 1.0
			)
			return Color(base.r * mult.r, base.g * mult.g, base.b * mult.b, 1.0)
		PaintBlend.ADD:
			return Color(
				clamp(base.r + tex.r * weight, 0.0, 1.0),
				clamp(base.g + tex.g * weight, 0.0, 1.0),
				clamp(base.b + tex.b * weight, 0.0, 1.0),
				1.0
			)
		_:
			return base.lerp(tex, weight)
