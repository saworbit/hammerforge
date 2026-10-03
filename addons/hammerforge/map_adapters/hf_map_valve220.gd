@tool
class_name HFMapValve220
extends HFMapAdapter

## Valve 220 .map format adapter.
## Face line format:
## ( x y z ) ( x y z ) ( x y z ) texture [ ux uy uz uoff ] [ vx vy vz voff ] rot uscale vscale

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("../face_data.gd")
@warning_ignore_restore("shadowed_global_identifier")

## How close to parallel a texture axis and a face normal have to be before the
## axis counts as lying along the normal rather than in the face.
const AXIS_PARALLEL := 0.99
## The projections a pair of texture axes can say. Cylindrical has none.
const PLANAR_PROJECTIONS := [
	FaceData.UVProjection.PLANAR_X,
	FaceData.UVProjection.PLANAR_Y,
	FaceData.UVProjection.PLANAR_Z,
]


func format_name() -> String:
	return "Valve 220"


func format_face_line(
	a: Vector3, b: Vector3, c: Vector3, texture: String, face_data: Variant
) -> String:
	var u_axis := Vector3.RIGHT
	var v_axis := Vector3.BACK
	var u_offset := 0.0
	var v_offset := 0.0
	var rotation := 0.0
	var u_scale := 1.0
	var v_scale := 1.0

	var normal := (b - a).cross(c - a).normalized()

	if face_data is FaceData:
		var axes := _turned(
			_compute_axes_from_projection(normal, face_data as FaceData), face_data.uv_rotation
		)
		u_axis = axes[0]
		v_axis = axes[1]
		var size := texture_size_for(face_data)
		u_offset = map_texture_offset(face_data.uv_offset.x, size.x)
		v_offset = map_texture_offset(face_data.uv_offset.y, size.y)
		u_scale = map_texture_scale_in_units(face_data.uv_scale.x, size.x)
		v_scale = map_texture_scale_in_units(face_data.uv_scale.y, size.y)
		rotation = map_rotation_degrees(face_data.uv_rotation)
	else:
		var axes := _auto_axes(normal)
		u_axis = axes[0]
		v_axis = axes[1]
		u_scale = map_texture_scale_in_units(1.0, DEFAULT_TEXTURE_SIZE.x)
		v_scale = map_texture_scale_in_units(1.0, DEFAULT_TEXTURE_SIZE.y)

	return (
		"( %s ) ( %s ) ( %s ) %s [ %s %s ] [ %s %s ] %s %s %s"
		% [
			_format_vec3(map_point(a)),
			_format_vec3(map_point(b)),
			_format_vec3(map_point(c)),
			texture,
			_fmt_axis(map_direction(u_axis)),
			_fmt_float(u_offset),
			_fmt_axis(map_direction(v_axis)),
			_fmt_float(v_offset),
			_fmt_float(rotation),
			format_texture_scale(u_scale),
			format_texture_scale(v_scale),
		]
	)


func _compute_axes_from_projection(normal: Vector3, fd: FaceData) -> Array:
	var projection := fd.uv_projection
	if projection == FaceData.UVProjection.BOX_UV:
		# The axis the viewport draws, asked of the face. Worked out again from
		# `normal`, a face at exactly 45 degrees could take the other axis: away
		# from the origin the plane normal built from the written points sits a
		# rounding error past the tie, and the file textured it differently from
		# the screen (#895). `normal` is still what the check below needs.
		projection = fd._box_projection_axis_in(fd.world_transform)

	if not projection in PLANAR_PROJECTIONS:
		return _auto_axes(normal)
	var axes: Array = FaceData.projection_axes(projection)
	# Valve 220 needs both axes to lie in the face plane. The stored projection
	# knows nothing about which way the face points, and PLANAR_Z is the default
	# on every FaceData, so a +/-X or +/-Y face was handed an axis parallel to
	# its own normal. That is a degenerate projection: the editors this format
	# exists to feed either reject the face or stretch the texture across it.
	# Resolve against the normal instead, the way BOX_UV already is.
	if _axis_lies_along(axes[0], normal) or _axis_lies_along(axes[1], normal):
		return _auto_axes(normal)
	return axes


## The texture axes turned by `rotation`, the way `_apply_uv_transform()` turns
## a projected point before it scales it.
##
## A Valve 220 reader projects with the axes as written and never applies the
## rotation field, which only records how the axes got there. Written unturned,
## every rotated face opened unrotated in another editor (#899). The rotation is
## still written, because the import reads it back onto the face's own axes.
static func _turned(axes: Array, rotation: float) -> Array:
	if rotation == 0.0:
		return axes
	var c := cos(rotation)
	var s := sin(rotation)
	return [axes[0] * c - axes[1] * s, axes[0] * s + axes[1] * c]


## True when a candidate texture axis is close enough to the face normal that it
## does not lie in the face.
func _axis_lies_along(axis: Vector3, normal: Vector3) -> bool:
	return absf(axis.dot(normal)) > AXIS_PARALLEL


## The planar axes the face points along most, from the one definition of them.
func _auto_axes(normal: Vector3) -> Array:
	var abs_n := normal.abs()
	if abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
		return FaceData.projection_axes(FaceData.UVProjection.PLANAR_Y)  # floor/ceiling
	if abs_n.x >= abs_n.z:
		return FaceData.projection_axes(FaceData.UVProjection.PLANAR_X)  # east/west wall
	return FaceData.projection_axes(FaceData.UVProjection.PLANAR_Z)  # north/south wall


static func _fmt_axis(v: Vector3) -> String:
	return "%s %s %s" % [_fmt_float(v.x), _fmt_float(v.y), _fmt_float(v.z)]
