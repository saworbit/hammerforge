@tool
class_name HFMapAdapter
extends RefCounted

## Base class for .map format adapters. Subclass to support different map formats.

## The size in pixels a face's texture is taken as when nothing gives it one: a
## face with no palette slot, a slot with no material or no texture, and the
## placeholder an import mints for a name the project does not have. 64 is the
## Quake convention.
const DEFAULT_TEXTURE_SIZE := Vector2(64, 64)

## How many `.map` units one HammerForge unit is written as.
##
## The whole unit conversion for an export lives here, because every face line in
## every shape writer goes through `format_face_line()` and nothing else touches
## a coordinate on the way out. 1 writes the level's own numbers, which is what a
## caller that has not asked for a conversion gets. `MapIO.QUAKE_UNITS_PER_METRE`
## is the figure the dialog offers (#713).
var units_per_metre: float = 1.0

## Whether coordinates are turned into the file's own axes on the way out.
##
## Alongside `units_per_metre` for the same reason and at the same place: `.map`
## is Z-up and this project is Y-up, and an export that writes one as the other
## produces a file whose floors are walls (#733). False writes this project's
## axes, which is what a caller that has not asked for a conversion gets.
var convert_axes: bool = false

## The pixel size of each palette slot's texture, by slot, which a face's offset
## and scale are written in texels of (#894). The export fills it from the
## level's palette. A face whose slot is not here is `DEFAULT_TEXTURE_SIZE`.
var texture_sizes: Array = []


func format_name() -> String:
	return "Base"


func format_face_line(
	_a: Vector3, _b: Vector3, _c: Vector3, _texture: String, _face_data: Variant
) -> String:
	return ""


## A point, in the units and the axes the file is being written in.
func map_point(v: Vector3) -> Vector3:
	var scaled := v * units_per_metre
	return MapIO.to_map_axes(scaled) if convert_axes else scaled


## A direction, in the axes the file is being written in.
##
## The Valve 220 texture axes go through this rather than `map_point()`, because
## a unit vector that took the scale factor would say the texture repeats every
## thirty-second of a unit. Turning the points and the axes by the same rotation
## leaves the dot product the reader computes between them unchanged, so the UVs
## come out of the conversion exactly as they went in.
func map_direction(v: Vector3) -> Vector3:
	return MapIO.to_map_axes(v) if convert_axes else v


## The pixel size of the texture `face_data` shows.
func texture_size_for(face_data: Variant) -> Vector2:
	if face_data != null:
		var slot := int(face_data.material_idx)
		if slot >= 0 and slot < texture_sizes.size():
			return texture_sizes[slot]
	return DEFAULT_TEXTURE_SIZE


## The pixel size of a palette material's texture, or `DEFAULT_TEXTURE_SIZE` when
## it has none to measure.
static func texture_size_of(material: Material) -> Vector2:
	if material is BaseMaterial3D:
		var texture: Texture2D = (material as BaseMaterial3D).albedo_texture
		if texture != null:
			var size := texture.get_size()
			if size.x > 0.0 and size.y > 0.0:
				return size
	return DEFAULT_TEXTURE_SIZE


## A face's texture scale, in the units the file is being written in, on a
## texture `texels` pixels across that axis.
##
## A `.map` reader computes `axis . point / scale + offset` and divides that by
## the texture's width, so one repeat spans `texels * scale` units. A face repeats
## `uv_scale` times a metre, which is `units_per_metre` units. Without the
## texture's size, the default face went out as 32 units a texel, and a 64 pixel
## texture repeated every 2,048 units in another editor where it repeats every 32
## here (#894).
func map_texture_scale_in_units(uv_scale: float, texels: float) -> float:
	return map_texture_scale(uv_scale) * units_per_metre / texels


## A face's texture offset, in texels of a texture `texels` pixels across that
## axis. `uv_offset` counts repeats, and is added after the scale on both sides.
static func map_texture_offset(uv_offset: float, texels: float) -> float:
	return uv_offset * texels


## A face's alignment, the way `FaceData` holds it, from the five numbers a face
## line ends on: u offset, v offset, rotation, u scale and v scale.
##
## The export in reverse, for a texture `size` pixels across at the units the
## file was written in. Any editor's file reads the same way, because every
## Quake family editor writes these numbers in texels. A scale of zero cannot be
## one the export wrote, and dividing by it is no scale, so it reads as 1.
static func alignment_from_map(raw: Array, units_per_metre: float, size: Vector2) -> Dictionary:
	return {
		"uv_offset": Vector2(float(raw[0]) / size.x, float(raw[1]) / size.y),
		"uv_rotation": wrapf(deg_to_rad(float(raw[2])), -PI, PI),
		"uv_scale":
		Vector2(
			_uv_scale_from_map(float(raw[3]), units_per_metre, size.x),
			_uv_scale_from_map(float(raw[4]), units_per_metre, size.y)
		),
	}


static func _uv_scale_from_map(scale: float, units_per_metre: float, texels: float) -> float:
	if not scale_is_exportable(scale):
		return 1.0
	return units_per_metre / (scale * texels)


## A texture scale, the way a face line writes it.
##
## To eight places, because a scale in texels is a small number: a 1,024 pixel
## texture at 32 units a metre is 0.03125 at the default, and the four places the
## other numbers get would bring a scale of 3 on it back as 3.005. A whole number
## is snapped to only from a rounding error away, so a small scale is never
## written as 0, which every compiler divides by.
static func format_texture_scale(value: float) -> String:
	if absf(value - roundf(value)) < 0.000001:
		return str(int(roundf(value)))
	return String.num(value, 8)


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


## Snap a float to 3 decimal places for a face line.
## Outputs clean integers when the value has no fractional part (e.g. "64" not "64.000").
##
## Not the same as `MapIO._snapped()`, which this used to claim to match.
## That one always writes the decimals, and it is what an entity `origin` and an
## I/O delay go through. Both forms parse; the delay in particular is a wire
## format other tools read, so they are left as they are rather than unified in
## passing.
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


## The scale field of a `.map` face line, from a `FaceData.uv_scale` component,
## before the units and the texture's size are applied.
##
## The two numbers mean opposite things. `_apply_uv_transform()` multiplies a
## world coordinate by `uv_scale`, so a larger value spans more UV per unit and
## the texture repeats more often. A `.map` scale divides: the reader computes
## `axis / scale`, so a larger value is a larger texture repeating less often.
## The reciprocal is the conversion between them.
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
