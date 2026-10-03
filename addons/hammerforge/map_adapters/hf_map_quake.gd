@tool
class_name HFMapQuake
extends HFMapAdapter

## Classic Quake .map format adapter.
## Face line format: ( x y z ) ( x y z ) ( x y z ) texture xoff yoff rot xscale yscale

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("../face_data.gd")
@warning_ignore_restore("shadowed_global_identifier")


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
	var u_scale := map_texture_scale_in_units(1.0, DEFAULT_TEXTURE_SIZE.x)
	var v_scale := map_texture_scale_in_units(1.0, DEFAULT_TEXTURE_SIZE.y)
	if face_data is FaceData:
		var fd := face_data as FaceData
		var size := texture_size_for(fd)
		u_offset = map_texture_offset(fd.uv_offset.x, size.x)
		v_offset = map_texture_offset(fd.uv_offset.y, size.y)
		rotation = map_rotation_degrees(fd.uv_rotation)
		u_scale = map_texture_scale_in_units(fd.uv_scale.x, size.x)
		v_scale = map_texture_scale_in_units(fd.uv_scale.y, size.y)
	return (
		"( %s ) ( %s ) ( %s ) %s %s %s %s %s %s"
		% [
			_format_vec3(map_point(a)),
			_format_vec3(map_point(b)),
			_format_vec3(map_point(c)),
			texture,
			_fmt_float(u_offset),
			_fmt_float(v_offset),
			_fmt_float(rotation),
			format_texture_scale(u_scale),
			format_texture_scale(v_scale),
		]
	)
