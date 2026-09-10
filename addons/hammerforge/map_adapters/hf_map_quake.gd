@tool
class_name HFMapQuake
extends HFMapAdapter

## Classic Quake .map format adapter.
## Face line format: ( x y z ) ( x y z ) ( x y z ) texture xoff yoff rot xscale yscale

const FaceData = preload("../face_data.gd")


func format_name() -> String:
	return "Classic Quake"


## The UV tail carries the face's own numbers rather than a fixed 0 0 0 1 1.
## Classic Quake has no texture axes, so only the offset, rotation and scale
## survive; the projection axis itself is a Valve 220 field.
func format_face_line(
	a: Vector3, b: Vector3, c: Vector3, texture: String, face_data: Variant
) -> String:
	var u_offset := 0.0
	var v_offset := 0.0
	var rotation := 0.0
	var u_scale := 1.0
	var v_scale := 1.0
	if face_data is FaceData:
		var fd := face_data as FaceData
		u_offset = fd.uv_offset.x
		v_offset = fd.uv_offset.y
		rotation = fd.uv_rotation
		u_scale = fd.uv_scale.x
		v_scale = fd.uv_scale.y
	return (
		"( %s ) ( %s ) ( %s ) %s %s %s %s %s %s"
		% [
			_format_vec3(a),
			_format_vec3(b),
			_format_vec3(c),
			texture,
			_fmt_float(u_offset),
			_fmt_float(v_offset),
			_fmt_float(rotation),
			_fmt_float(u_scale),
			_fmt_float(v_scale),
		]
	)


static func _fmt_float(f: float) -> String:
	if absf(f - roundf(f)) < 0.001:
		return str(int(roundf(f)))
	return String.num(f, 4)
