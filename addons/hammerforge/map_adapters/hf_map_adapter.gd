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
##
## Keys and values are escaped, because either may contain a quote and a raw one
## would end the string early and take the rest of the value with it.
func format_entity_properties(properties: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key in properties:
		(
			lines
			. append(
				(
					'"%s" "%s"'
					% [
						MapIO.escape_property(str(key)),
						MapIO.escape_property(format_property_value(properties[key])),
					]
				)
			)
		)
	return lines


## One property value, the way a `.map` file carries it.
##
## A `.map` exists to be read by something else, and the Objects tab stores typed
## values: the colour picker writes a `Color` and the vector row writes a
## `Vector3`. `str()` on either produces Godot's own notation - a colour comes out
## as "(0.2, 0.4, 0.8, 1.0)" - and no Quake-family compiler or editor parses that.
## The parentheses and the commas make the key unusable rather than merely
## differently scaled.
func format_property_value(value: Variant) -> String:
	match typeof(value):
		TYPE_COLOR:
			return format_color(value)
		TYPE_VECTOR3:
			return _format_vec3(value)
		TYPE_VECTOR2:
			return "%s %s" % [_snapped(value.x), _snapped(value.y)]
		TYPE_BOOL:
			return "1" if value else "0"
		TYPE_FLOAT:
			return _snapped(value)
		TYPE_STRING, TYPE_STRING_NAME:
			# `entities.json` gives a colour property a hex default, so a colour
			# the mapper never opened is still a `String` on the way out.
			var text := str(value)
			if text.begins_with("#") and Color.html_is_valid(text):
				return format_color(Color.html(text))
			return text
		_:
			return str(value)


## A colour as a `.map` file carries one: three numbers, and no alpha.
##
## 0..255 per channel is the convention the Quake family uses for a light colour.
## A format that wants 0..1 overrides this without touching anything else.
func format_color(value: Color) -> String:
	return "%d %d %d" % [roundi(value.r * 255.0), roundi(value.g * 255.0), roundi(value.b * 255.0)]


## Snap a float to 3 decimal places, matching MapIO._snapped().
## Outputs clean integers when the value has no fractional part (e.g. "64" not "64.000").
static func _snapped(value: float) -> String:
	if absf(value - roundf(value)) < 0.001:
		return str(int(roundf(value)))
	return String.num(value, 3)


## Format a Vector3 as space-separated snapped components.
static func _format_vec3(v: Vector3) -> String:
	return "%s %s %s" % [_snapped(v.x), _snapped(v.y), _snapped(v.z)]


## The rotation field of a `.map` face line, in the units that field uses.
##
## `FaceData.uv_rotation` is radians, because `_apply_uv_transform()` calls
## `Vector2.rotated()`. The `.map` field is degrees in both formats. Writing the
## radians straight out turns a 45 degree face by 0.7854 of a degree, which is
## every rotated face arriving effectively unrotated.
static func map_rotation_degrees(uv_rotation: float) -> float:
	return rad_to_deg(uv_rotation)


## The scale field of a `.map` face line, from a `FaceData.uv_scale` component.
##
## The two numbers mean opposite things. `_apply_uv_transform()` multiplies a
## world coordinate by `uv_scale`, so a larger value spans more UV per unit and
## the texture repeats more often. A `.map` scale divides: the reader computes
## `axis / scale`, so a larger value is a larger texture repeating less often.
## The reciprocal is the conversion between them.
##
## `uv_offset` needs no conversion and does not get one. A `.map` reader does
## `axis / scale + offset` and `_apply_uv_transform()` does `world * uv_scale +
## uv_offset`, so once the scale is written as its reciprocal the two offsets
## are the same quantity in the same place.
##
## A negative scale is left negative. `adjust_uvs_for_rotation()` writes one
## deliberately when a turn flips the projection plane, and a negative scale is
## legal in a `.map` - it mirrors the texture.
static func map_texture_scale(uv_scale: float) -> float:
	if not scale_is_exportable(uv_scale):
		return 1.0
	return 1.0 / uv_scale


## True when a UV scale component survives the trip into a `.map`.
##
## Every Quake family compiler divides by the texture scale, so a zero there is a
## divide by zero at load: a crash, a refused map, or a face with non-finite UVs
## depending on the tool. `set_face_uv_params()` has refused a zero on the way in
## since #344; this is the same rule at the last point it is still ours.
static func scale_is_exportable(value: float) -> bool:
	return is_finite(value) and not is_zero_approx(value)
