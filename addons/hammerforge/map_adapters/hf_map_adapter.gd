@tool
class_name HFMapAdapter
extends RefCounted

## Base class for .map format adapters. Subclass to support different map formats.


func format_name() -> String:
	return "Base"


func format_face_line(
	a: Vector3, b: Vector3, c: Vector3, texture: String, face_data: Variant
) -> String:
	return ""


## Format entity properties as .map key-value lines (one per property).
func format_entity_properties(properties: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key in properties:
		lines.append('"%s" "%s"' % [str(key), str(properties[key])])
	return lines


## Snap a float to 3 decimal places, matching MapIO._snapped().
## Outputs clean integers when the value has no fractional part (e.g. "64" not "64.000").
static func _snapped(value: float) -> String:
	if absf(value - roundf(value)) < 0.001:
		return str(int(roundf(value)))
	return String.num(value, 3)


## Format a Vector3 as space-separated snapped components.
static func _format_vec3(v: Vector3) -> String:
	return "%s %s %s" % [_snapped(v.x), _snapped(v.y), _snapped(v.z)]
