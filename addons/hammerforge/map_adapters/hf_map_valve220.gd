@tool
class_name HFMapValve220
extends HFMapAdapter

## Valve 220 .map format adapter.
## Face line format:
## ( x y z ) ( x y z ) ( x y z ) texture [ ux uy uz uoff ] [ vx vy vz voff ] rot uscale vscale

const FaceData = preload("../face_data.gd")


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

	match projection:
		FaceData.UVProjection.PLANAR_X:
			return [Vector3.BACK, Vector3.UP]
		FaceData.UVProjection.PLANAR_Y:
			return [Vector3.RIGHT, Vector3.BACK]
		FaceData.UVProjection.PLANAR_Z:
			return [Vector3.RIGHT, Vector3.UP]
		_:
			return _auto_axes(normal)


func _auto_axes(normal: Vector3) -> Array:
	var abs_n := normal.abs()
	if abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
		return [Vector3.RIGHT, Vector3.BACK]  # floor/ceiling
	elif abs_n.x >= abs_n.z:
		return [Vector3.BACK, Vector3.UP]  # east/west wall
	else:
		return [Vector3.RIGHT, Vector3.UP]  # north/south wall


static func _fmt_axis(v: Vector3) -> String:
	return "%s %s %s" % [_fmt_float(v.x), _fmt_float(v.y), _fmt_float(v.z)]


static func _fmt_float(f: float) -> String:
	if absf(f - roundf(f)) < 0.001:
		return str(int(f))
	return "%.4g" % f
