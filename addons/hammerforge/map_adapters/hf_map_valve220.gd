@tool
class_name HFMapValve220
extends HFMapAdapter

## Valve 220 .map format adapter.
## Face line format:
## ( x y z ) ( x y z ) ( x y z ) texture [ ux uy uz uoff ] [ vx vy vz voff ] rot uscale vscale

const FaceData = preload("../face_data.gd")

## How close to parallel a texture axis and a face normal have to be before the
## axis counts as lying along the normal rather than in the face.
const AXIS_PARALLEL := 0.99


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
		var axes := _compute_axes_from_projection(normal, face_data as FaceData)
		u_axis = axes[0]
		v_axis = axes[1]
		u_offset = face_data.uv_offset.x
		v_offset = face_data.uv_offset.y
		u_scale = face_data.uv_scale.x
		v_scale = face_data.uv_scale.y
		rotation = face_data.uv_rotation
	else:
		var axes := _auto_axes(normal)
		u_axis = axes[0]
		v_axis = axes[1]

	return (
		"( %s ) ( %s ) ( %s ) %s [ %s %s ] [ %s %s ] %s %s %s"
		% [
			_format_vec3(a),
			_format_vec3(b),
			_format_vec3(c),
			texture,
			_fmt_axis(u_axis),
			_fmt_float(u_offset),
			_fmt_axis(v_axis),
			_fmt_float(v_offset),
			_fmt_float(rotation),
			_fmt_float(u_scale),
			_fmt_float(v_scale),
		]
	)


func _compute_axes_from_projection(normal: Vector3, fd: FaceData) -> Array:
	var projection := fd.uv_projection
	if projection == FaceData.UVProjection.BOX_UV:
		# Resolve to planar based on dominant normal axis
		var abs_n := normal.abs()
		if abs_n.x >= abs_n.y and abs_n.x >= abs_n.z:
			projection = FaceData.UVProjection.PLANAR_X
		elif abs_n.y >= abs_n.z:
			projection = FaceData.UVProjection.PLANAR_Y
		else:
			projection = FaceData.UVProjection.PLANAR_Z

	var axes: Array = []
	match projection:
		FaceData.UVProjection.PLANAR_X:
			axes = [Vector3.BACK, Vector3.UP]
		FaceData.UVProjection.PLANAR_Y:
			axes = [Vector3.RIGHT, Vector3.BACK]
		FaceData.UVProjection.PLANAR_Z:
			axes = [Vector3.RIGHT, Vector3.UP]
		_:
			return _auto_axes(normal)
	# Valve 220 needs both axes to lie in the face plane. The stored projection
	# knows nothing about which way the face points, and PLANAR_Z is the default
	# on every FaceData, so a +/-X or +/-Y face was handed an axis parallel to
	# its own normal. That is a degenerate projection: the editors this format
	# exists to feed either reject the face or stretch the texture across it.
	# Resolve against the normal instead, the way BOX_UV already is.
	if _axis_lies_along(axes[0], normal) or _axis_lies_along(axes[1], normal):
		return _auto_axes(normal)
	return axes


## True when a candidate texture axis is close enough to the face normal that it
## does not lie in the face.
func _axis_lies_along(axis: Vector3, normal: Vector3) -> bool:
	return absf(axis.dot(normal)) > AXIS_PARALLEL


func _auto_axes(normal: Vector3) -> Array:
	var abs_n := normal.abs()
	if abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
		return [Vector3.RIGHT, Vector3.BACK]  # floor/ceiling
	if abs_n.x >= abs_n.z:
		return [Vector3.BACK, Vector3.UP]  # east/west wall
	return [Vector3.RIGHT, Vector3.UP]  # north/south wall


static func _fmt_axis(v: Vector3) -> String:
	return "%s %s %s" % [_fmt_float(v.x), _fmt_float(v.y), _fmt_float(v.z)]


static func _fmt_float(f: float) -> String:
	if absf(f - roundf(f)) < 0.001:
		return str(int(roundf(f)))
	return String.num(f, 4)
