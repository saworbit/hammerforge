@tool
class_name HFEntityPropUtils
extends RefCounted
## Static helpers for the entity property panel.  Extracted from dock.gd.
##
## Entities can be `DraftEntity` (with `entity_data` property) or any Node3D
## with `entity_data` set as meta. These helpers paper over the difference so
## the dock doesn't need duck-typed branches in every handler.

const DraftEntity = preload("../draft_entity.gd")


## Read entity_data from either DraftEntity.entity_data or the
## "entity_data" meta on a generic Node3D. Returns {} when the entity is
## neither.
static func get_entity_data(entity: Node3D) -> Dictionary:
	if not is_instance_valid(entity):
		return {}
	if entity is DraftEntity:
		return entity.entity_data
	if entity.has_meta("entity_data"):
		return entity.get_meta("entity_data")
	return {}


## Read the entity type key (definition id). Empty string if missing.
static func get_entity_type(entity: Node3D) -> String:
	if not is_instance_valid(entity):
		return ""
	if entity is DraftEntity:
		return entity.entity_type
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
	elif entity.has_meta("entity_data"):
		var d: Dictionary = entity.get_meta("entity_data")
		d[prop_name] = value
		entity.set_meta("entity_data", d)


## Update one axis of a Vector3 property. Reads existing value (defaulting
## to ZERO), mutates the named axis, writes back via `set_entity_property`.
static func set_entity_vec3_axis(
	entity: Node3D, prop_name: String, axis_index: int, value: float
) -> void:
	if not is_instance_valid(entity):
		return
	var data := get_entity_data(entity)
	var vec: Vector3 = Vector3.ZERO
	var cur = data.get(prop_name, Vector3.ZERO)
	if cur is Vector3:
		vec = cur
	vec[axis_index] = value
	set_entity_property(entity, prop_name, vec)


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
static func find_definition(entity_defs: Array, type_key: String) -> Dictionary:
	for entry in entity_defs:
		if not (entry is Dictionary):
			continue
		var eid = str(entry.get("id", entry.get("class", "")))
		if eid == type_key:
			return entry
	return {}
