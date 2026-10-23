@tool
extends RefCounted
## The Entity panel's view of several entities at once, and of class defaults
## (#1729).
##
## A selection of lights, doors or triggers is edited as one: the panel lists the
## union of their properties, a property only some have says how many, one whose
## values differ shows a dash, and a value typed goes on every entity that has the
## property. A value at its class default reads lighter than one set on purpose,
## and can be put back.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFEntityPropUtils = preload("hf_entity_prop_utils.gd")
@warning_ignore_restore("shadowed_global_identifier")


## The entities `nodes` names, once each: point entities, and one brush of each
## brush entity, whose properties are on all of its brushes.
static func subjects(root: Node, nodes: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for node in nodes:
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var point: bool = root.is_entity_node(node)
		if not point and not HFEntityPropUtils.is_brush_entity(node):
			continue
		if HFEntityPropUtils.get_entity_type(node) == "":
			continue
		var members: Array = [node] if point else root.entity_property_nodes(node)
		var key: Node = members[0] if not members.is_empty() else node
		if seen.has(key):
			continue
		seen[key] = true
		out.append(node)
	return out


## The properties of `entities`, the union of their classes', in the order they
## first appear. Each row: `name`, `type`, `label`, `tooltip`, `prop` (the first
## definition's), `holders` (the entities whose class has it), `values` (each
## holder's, at its class default when it has none), `defaults` (each holder's
## class default), `same` (every value alike), and `at_default` (every holder at
## its class default).
static func rows(entity_defs: Array, entities: Array) -> Array:
	var by_name: Dictionary = {}
	var order: Array = []
	for entity in entities:
		var definition := HFEntityPropUtils.find_definition(
			entity_defs, HFEntityPropUtils.get_entity_type(entity)
		)
		var data := HFEntityPropUtils.get_entity_data(entity)
		for prop in definition.get("properties", []):
			if not (prop is Dictionary) or str(prop.get("name", "")) == "":
				continue
			var prop_name := str(prop["name"])
			if not by_name.has(prop_name):
				by_name[prop_name] = {
					"name": prop_name,
					"type": str(prop.get("type", "string")),
					"label": str(prop.get("label", prop_name)),
					"tooltip": str(prop.get("tooltip", "")),
					"prop": prop,
					"holders": [],
					"values": [],
					"defaults": [],
				}
				order.append(prop_name)
			var row: Dictionary = by_name[prop_name]
			var type_name: String = row["type"]
			var default_value: Variant = HFEntityPropUtils.coerce_default(
				type_name, prop.get("default", null)
			)
			row["holders"].append(entity)
			row["defaults"].append(default_value)
			row["values"].append(
				HFEntityPropUtils.coerce_default(type_name, data.get(prop_name, default_value))
			)
	var out: Array = []
	for prop_name in order:
		var row: Dictionary = by_name[prop_name]
		var values: Array = row["values"]
		row["same"] = true
		row["at_default"] = true
		for i in values.size():
			if not same_value(row["type"], values[i], values[0]):
				row["same"] = false
			if not same_value(row["type"], values[i], row["defaults"][i]):
				row["at_default"] = false
		out.append(row)
	return out


## Whether two values of a property's type are the same, near enough for floats.
static func same_value(type_name: String, a: Variant, b: Variant) -> bool:
	match type_name:
		"float":
			return is_equal_approx(float(a), float(b))
		"color":
			return a is Color and b is Color and (a as Color).is_equal_approx(b)
		"vector3":
			return a is Vector3 and b is Vector3 and (a as Vector3).is_equal_approx(b)
	return typeof(a) == typeof(b) and a == b


## Each of `entities`' class defaults for `prop_names`, or for every property of
## its class with none named: `[[entity, {name: default}], ...]`, leaving out an
## entity whose class has none of them.
static func defaults_for(entity_defs: Array, entities: Array, prop_names: Array = []) -> Array:
	var out: Array = []
	for entity in entities:
		var values := _class_defaults(entity_defs, entity)
		if not prop_names.is_empty():
			for prop_name in values.keys():
				if not prop_names.has(prop_name):
					values.erase(prop_name)
		if not values.is_empty():
			out.append([entity, values])
	return out


## The defaults of the properties each of `entities` does not hold, so a class
## that gained a property in its definition file gives it to entities made
## before: `[[entity, {name: default}], ...]`. A property an entity holds is left
## alone.
static func missing_defaults(entity_defs: Array, entities: Array) -> Array:
	var out: Array = []
	for entity in entities:
		var data := HFEntityPropUtils.get_entity_data(entity)
		var values: Dictionary = {}
		var defaults := _class_defaults(entity_defs, entity)
		for prop_name in defaults:
			if not data.has(prop_name):
				values[prop_name] = defaults[prop_name]
		if not values.is_empty():
			out.append([entity, values])
	return out


static func _class_defaults(entity_defs: Array, entity: Node) -> Dictionary:
	var definition := HFEntityPropUtils.find_definition(
		entity_defs, HFEntityPropUtils.get_entity_type(entity)
	)
	var out: Dictionary = {}
	for prop in definition.get("properties", []):
		if prop is Dictionary and str(prop.get("name", "")) != "":
			out[str(prop["name"])] = HFEntityPropUtils.coerce_default(
				str(prop.get("type", "string")), prop.get("default", null)
			)
	return out
