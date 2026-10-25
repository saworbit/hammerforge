@tool
extends RefCounted
class_name HFBakeSplit

## What a baked mesh carries as a whole and a brush can ask for: how it casts
## shadows (#1444) and how fine its lightmap is (#1438). Both are settings of the
## `MeshInstance3D`, not of a surface, so one mesh holds one of each. The bake
## splits its brushes by them before it merges anything, and a brush that asks
## for something else gets a mesh of its own. Every bake path splits through
## `partition()`, sets each part's meshes through `apply()` and puts the parts
## back into one node through `Baker.gather_parts()`, so they cannot disagree.
##
## A brush's choices are metadata on it, as its visgroups are, so a `.tscn` keeps
## them as well as the brush record. A visgroup can choose how its brushes cast
## shadows too; the brush's own choice beats it, and the level's default is what
## is left. The lightmap scale is the brush's alone.

## The brush's own Cast Shadows, one of `GeometryInstance3D.ShadowCastingSetting`.
## Not there means the brush leaves it to its visgroups and the level.
const CAST_SHADOW_META := "bake_cast_shadow"
## The brush's own Lightmap Scale. Not there means 1.0.
const LIGHTMAP_SCALE_META := "bake_lightmap_scale"
## What a brush or a visgroup holds when the choice is not its own.
const LEVEL_DEFAULT := -1
const MIN_LIGHTMAP_SCALE := 0.125
const MAX_LIGHTMAP_SCALE := 8.0
const DEFAULT_LIGHTMAP_SCALE := 1.0
## The four settings in the order the dock lists them, after Level Default where
## the control offers it.
const CAST_SHADOW_CHOICES: Array[int] = [
	GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
	GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
	GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,
	GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
]
const CAST_SHADOW_NAMES := {
	GeometryInstance3D.SHADOW_CASTING_SETTING_ON: "On",
	GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: "Off",
	GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED: "Double Sided",
	GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: "Shadows Only",
}
## The bake option keys `apply()` reads, beside the bake's other options.
const CAST_SHADOW_OPTION := "cast_shadow"
const LIGHTMAP_SCALE_OPTION := "lightmap_scale"
## A part whose brushes give no collision of their own, because a ramp the bake
## lays over them stands in for it (#1416). The bake asks this of a brush, not
## the brush of itself: it is only true for the length of the bake that lays one.
const NO_COLLISION_OPTION := "no_collision"


static func is_cast_shadow(value: Variant) -> bool:
	return (value is int or value is float) and CAST_SHADOW_NAMES.has(int(value))


static func cast_shadow_name(value: int) -> String:
	return str(CAST_SHADOW_NAMES.get(value, "Level Default"))


## The brush's own Cast Shadows, or `LEVEL_DEFAULT`.
static func brush_cast_shadow(brush: Node) -> int:
	var value: Variant = brush.get_meta(CAST_SHADOW_META, LEVEL_DEFAULT)
	return int(value) if is_cast_shadow(value) else LEVEL_DEFAULT


static func brush_lightmap_scale(brush: Node) -> float:
	var value: Variant = brush.get_meta(LIGHTMAP_SCALE_META, DEFAULT_LIGHTMAP_SCALE)
	if not (value is float or value is int) or not is_finite(float(value)):
		return DEFAULT_LIGHTMAP_SCALE
	return clampf(float(value), MIN_LIGHTMAP_SCALE, MAX_LIGHTMAP_SCALE)


## Give the brush its own Cast Shadows, or hand it back to the level with
## `LEVEL_DEFAULT`. False when nothing changed or the value is not a setting.
static func set_brush_cast_shadow(brush: Node, value: int) -> bool:
	if value != LEVEL_DEFAULT and not is_cast_shadow(value):
		return false
	if value == brush_cast_shadow(brush):
		return false
	if value == LEVEL_DEFAULT:
		brush.remove_meta(CAST_SHADOW_META)
	else:
		brush.set_meta(CAST_SHADOW_META, value)
	return true


## Held to the range the dock offers. 1.0 is no choice at all, so it leaves no
## metadata behind. False when nothing changed or the value is not a number.
static func set_brush_lightmap_scale(brush: Node, value: float) -> bool:
	if not is_finite(value):
		return false
	var held := clampf(value, MIN_LIGHTMAP_SCALE, MAX_LIGHTMAP_SCALE)
	if is_equal_approx(held, brush_lightmap_scale(brush)):
		return false
	if is_equal_approx(held, DEFAULT_LIGHTMAP_SCALE):
		brush.remove_meta(LIGHTMAP_SCALE_META)
	else:
		brush.set_meta(LIGHTMAP_SCALE_META, held)
	return true


## The brush's choices for its record, which undo, duplicate, prefabs and the
## `.hflevel` all go through. Only the ones it made.
static func fields(brush: Node) -> Dictionary:
	var out: Dictionary = {}
	add_fields(brush, out)
	return out


## `fields()` written into `info`, for a record built in place. A brush that sets
## neither, as most do, is answered without reading either (#1866).
static func add_fields(brush: Node, info: Dictionary) -> void:
	var has_cast := brush.has_meta(CAST_SHADOW_META)
	var has_scale := brush.has_meta(LIGHTMAP_SCALE_META)
	if not (has_cast or has_scale):
		return
	var cast := brush_cast_shadow(brush) if has_cast else LEVEL_DEFAULT
	if cast != LEVEL_DEFAULT:
		info[CAST_SHADOW_META] = cast
	var scale := brush_lightmap_scale(brush) if has_scale else DEFAULT_LIGHTMAP_SCALE
	if not is_equal_approx(scale, DEFAULT_LIGHTMAP_SCALE):
		info[LIGHTMAP_SCALE_META] = scale


## Put a record's choices on `brush`. A `.hflevel` is JSON, so a whole number
## comes back as a float; anything that is not a setting is left out.
static func give(brush: Node, info: Dictionary) -> void:
	var cast: Variant = info.get(CAST_SHADOW_META, LEVEL_DEFAULT)
	if is_cast_shadow(cast):
		set_brush_cast_shadow(brush, int(cast))
	var scale: Variant = info.get(LIGHTMAP_SCALE_META, DEFAULT_LIGHTMAP_SCALE)
	if (scale is float or scale is int) and is_finite(float(scale)):
		set_brush_lightmap_scale(brush, float(scale))


## How `brush` bakes: `{"cast_shadow": int, "lightmap_scale": float}`. Its own
## Cast Shadows, else that of the first of its visgroups in the visgroup list
## that sets one, else `level_default`.
static func settings_of(brush: Node, level_default: int, visgroups: Object) -> Dictionary:
	var cast := brush_cast_shadow(brush)
	# A stand-in visgroup system with no say over shadows is no visgroup override.
	if (
		cast == LEVEL_DEFAULT
		and visgroups != null
		and visgroups.has_method("cast_shadow_overrides_of")
	):
		var overrides: Array = visgroups.cast_shadow_overrides_of(brush)
		if not overrides.is_empty():
			cast = int(overrides[0][1])
	if cast == LEVEL_DEFAULT:
		cast = level_default
	return {CAST_SHADOW_OPTION: cast, LIGHTMAP_SCALE_OPTION: brush_lightmap_scale(brush)}


## `items` in parts that share their settings, `settings` being each item's from
## `settings_of()`. Parts and their members keep the order the items came in, so
## two bakes of one level make the same meshes in the same order.
##
## `[{"settings": Dictionary, "members": Array}]`.
static func partition(items: Array, settings: Array) -> Array:
	var parts: Array = []
	var by_key: Dictionary = {}
	for i in items.size():
		var these: Dictionary = settings[i]
		var key := key_of(these)
		if not by_key.has(key):
			by_key[key] = parts.size()
			parts.append({"settings": these, "members": []})
		parts[by_key[key]]["members"].append(items[i])
	return parts


## What tells two sets of settings apart. Empty settings are the level's own.
static func key_of(settings: Dictionary) -> Array:
	return [
		int(settings.get(CAST_SHADOW_OPTION, LEVEL_DEFAULT)),
		float(settings.get(LIGHTMAP_SCALE_OPTION, DEFAULT_LIGHTMAP_SCALE)),
		bool(settings.get(NO_COLLISION_OPTION, false)),
	]


## A copy of the bake `options` that bakes with `settings`.
static func with_settings(options: Dictionary, settings: Dictionary) -> Dictionary:
	var out := options.duplicate()
	out.merge(settings, true)
	return out


## Give a mesh the settings in bake `options`: the level default when nothing
## split it, or the settings of the part it was baked from.
static func apply(instance: GeometryInstance3D, options: Dictionary) -> void:
	var cast: Variant = options.get(CAST_SHADOW_OPTION, LEVEL_DEFAULT)
	var setting := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if is_cast_shadow(cast):
		setting = int(cast) as GeometryInstance3D.ShadowCastingSetting
	instance.cast_shadow = setting
	# LightmapGI sizes each mesh's lightmap as its `lightmap_size_hint`, which the
	# UV2 unwrap writes from the texel size, times this. So one unwrap at the
	# level's texel size and this scale give the part its own density; unwrapping
	# at a scaled texel size as well would apply the scale twice.
	instance.gi_lightmap_texel_scale = float(
		options.get(LIGHTMAP_SCALE_OPTION, DEFAULT_LIGHTMAP_SCALE)
	)
