@tool
class_name HFEntityPropUtils
extends RefCounted
## Static helpers for the entity property panel.  Extracted from dock.gd.
##
## Entities can be `DraftEntity` (with `entity_data` property) or any Node3D
## with `entity_data` set as meta. These helpers paper over the difference so
## the dock doesn't need duck-typed branches in every handler.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftEntity = preload("../draft_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The meta a brush entity's properties live under. Not `entity_data`: that name
## belongs to a point entity, and the two were never the same key.
const BRUSH_ENTITY_DATA := "brush_entity_data"


## Read entity_data from either DraftEntity.entity_data or the
## "entity_data" meta on a generic Node3D. Returns {} when the entity is
## neither.
static func get_entity_data(entity: Node3D) -> Dictionary:
	if not is_instance_valid(entity):
		return {}
	if entity is DraftEntity:
		return entity.entity_data
	# A brush tied to an entity class keeps its properties under their own key.
	# That key already round trips through the `.hflevel` and the `.map`, and was
	# only ever written by a `.map` import, because nothing here could read or
	# write it: the panel never opened and the setter wrote to `entity_data`,
	# which a brush does not have (#728).
	if entity.has_meta(BRUSH_ENTITY_DATA):
		return entity.get_meta(BRUSH_ENTITY_DATA)
	if entity.has_meta("entity_data"):
		return entity.get_meta("entity_data")
	return {}


## Whether this node is a brush tied to an entity class rather than a point
## entity. Asked by metadata rather than by type, so this file stays free of the
## brush class.
static func is_brush_entity(entity: Node3D) -> bool:
	return (
		is_instance_valid(entity)
		and not (entity is DraftEntity)
		and str(entity.get_meta("brush_entity_class", "")) != ""
	)


## Read the entity type key (definition id). Empty string if missing.
static func get_entity_type(entity: Node3D) -> String:
	if not is_instance_valid(entity):
		return ""
	if entity is DraftEntity:
		return entity.entity_type
	if entity.has_meta("brush_entity_class"):
		return str(entity.get_meta("brush_entity_class"))
	if entity.has_meta("entity_type"):
		return str(entity.get_meta("entity_type"))
	return ""


## Set a single property on either DraftEntity.entity_data or the meta dict.
## Triggers `notify_property_list_changed` for DraftEntity to refresh
## inspector views.
static func set_entity_property(entity: Node3D, prop_name: String, value: Variant) -> void:
	if not is_instance_valid(entity):
		return
	if entity is DraftEntity:
		entity.entity_data[prop_name] = value
		entity.notify_property_list_changed()
		# A class whose instances name their own model draws that model, so the
		# viewport has to follow the field. Only that one property, because
		# rebuilding the preview on every edit would do it per keystroke.
		if prop_name == entity.authored_scene_property():
			entity.refresh_preview()
	elif is_brush_entity(entity):
		var brush_data: Dictionary = entity.get_meta(BRUSH_ENTITY_DATA, {}).duplicate()
		brush_data[prop_name] = value
		entity.set_meta(BRUSH_ENTITY_DATA, brush_data)
	elif entity.has_meta("entity_data"):
		var d: Dictionary = entity.get_meta("entity_data")
		d[prop_name] = value
		entity.set_meta("entity_data", d)


## A Vector3 property with one axis replaced. Reads the existing value
## (defaulting to ZERO) and changes nothing; the panel writes the result as one
## undo step (#931).
static func vec3_with_axis(
	entity: Node3D, prop_name: String, axis_index: int, value: float
) -> Vector3:
	var vec: Vector3 = Vector3.ZERO
	var cur = get_entity_data(entity).get(prop_name, Vector3.ZERO)
	if cur is Vector3:
		vec = cur
	vec[axis_index] = value
	return vec


## Coerce a raw default from an entity definition into a typed value matching
## the property's declared type. Mirrors the legacy dock helper.
static func coerce_default(type_name: String, value: Variant) -> Variant:
	match type_name:
		"float":
			return float(value) if value != null else 0.0
		"int":
			return int(value) if value != null else 0
		"bool":
			return bool(value) if value != null else false
		"color":
			if value is Color:
				return value
			if value is String:
				return Color(value)
			return Color.WHITE
		"vector3":
			if value is Vector3:
				return value
			if value is Array and value.size() == 3:
				return Vector3(value[0], value[1], value[2])
			return Vector3.ZERO
		"string":
			return str(value) if value != null else ""
		_:
			return value


## Look up the definition entry matching `type_key` in a list of entity
## definitions. Returns {} if not found.
## The presets a definition offers, in the order it lists them. A preset is a
## name and some property values, such as a light's Warm Ceiling (#990).
static func preset_names(definition: Dictionary) -> PackedStringArray:
	var presets: Variant = definition.get("presets", {})
	var names := PackedStringArray()
	if presets is Dictionary:
		for preset_name in presets:
			names.append(str(preset_name))
	return names


## A preset's values, each in the form its property's type takes. A value for a
## property the class does not declare is left out and said, so a preset can
## only ever set what the Entity panel could.
static func preset_values(definition: Dictionary, preset_name: String) -> Dictionary:
	var presets: Variant = definition.get("presets", {})
	if not (presets is Dictionary) or not (presets as Dictionary).has(preset_name):
		return {}
	var raw: Variant = presets[preset_name]
	if not (raw is Dictionary):
		return {}
	var types := {}
	for prop in definition.get("properties", []):
		if prop is Dictionary:
			types[str(prop.get("name", ""))] = str(prop.get("type", "string"))
	var values := {}
	for key in raw:
		var prop_name := str(key)
		if not types.has(prop_name):
			HFLog.warn("Preset %s sets %s, which the class does not have" % [preset_name, prop_name])
			continue
		values[prop_name] = coerce_default(types[prop_name], raw[key])
	return values


static func find_definition(entity_defs: Array, type_key: String) -> Dictionary:
	for entry in entity_defs:
		if not (entry is Dictionary):
			continue
		var eid = str(entry.get("id", entry.get("class", "")))
		if eid == type_key:
			return entry
	return {}
