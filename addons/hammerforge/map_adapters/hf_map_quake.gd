@tool
class_name HFMapQuake
extends HFMapAdapter

## Classic Quake .map format adapter.
## Face line format: ( x y z ) ( x y z ) ( x y z ) texture xoff yoff rot xscale yscale


func format_name() -> String:
	return "Classic Quake"


func format_face_line(
	a: Vector3, b: Vector3, c: Vector3, texture: String, face_data: Variant
) -> String:
	return (
		"( %s ) ( %s ) ( %s ) %s 0 0 0 1 1"
		% [_format_vec3(a), _format_vec3(b), _format_vec3(c), texture]
	)
