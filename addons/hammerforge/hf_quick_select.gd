@tool
extends RefCounted
## Select by a typed rule (#1698): `class is light_point and energy > 2`.
##
## Nothing could pick "every cut brush" or "every light brighter than 2" short
## of clicking each one. A rule is conditions joined by "and" or a comma, each a
## property, a test and a value. The properties are the tests the bridge's
## `hf_get_brushes` and `hf_get_entities` filter by, read through
## `HFObjectFilter`, so a person and an agent pick the same set for the same
## rule. An entity takes any of its own properties by name as well, and those
## compare as numbers when both sides are numbers.
##
## The tests are `is`, `is not`, `>`, `>=`, `<`, `<=` and `matches`, which takes
## `*` for any run of characters. Names and classes match case ignored.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
const HFBrushEntity = preload("hf_brush_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFObjectFilterType = preload("hf_object_filter.gd")
const HFSimilarType = preload("hf_similar.gd")

## How a rule's matches change the selection.
enum Mode { REPLACE, ADD, TAKE_AWAY }

## The tests as they are written, longest first, so `is not` is read before `is`
## and `>=` before `>`, with what each one means.
const TESTS := [
	["is not", "!="],
	["matches", "matches"],
	[">=", ">="],
	["<=", "<="],
	["!=", "!="],
	["is", "="],
	["=", "="],
	[">", ">"],
	["<", "<"],
]
## The tests a named property takes. The comparisons are for an entity's own
## numbers.
const NAMED_TESTS := ["=", "!=", "matches"]
const EXAMPLES := {
	"brush": "operation is cut and visgroup is upper",
	"entity": "class is light_point and energy > 2",
}
## A selection's kinds, in the order the Selection Info row lists them.
const KINDS := ["solid", "cut", "brush_entity", "entity"]
const KIND_LABELS := {
	"solid": "Brushes", "cut": "Cuts", "brush_entity": "Brush entities", "entity": "Entities"
}


## The properties `kind` takes by name, "brush" or "entity". An entity takes any
## of its own properties as well.
static func properties(kind: String) -> Array:
	if kind == "brush":
		return HFObjectFilterType.BRUSH_TESTS.duplicate()
	var out: Array = HFObjectFilterType.ENTITY_TESTS.duplicate()
	out.erase("property")
	return out


## `text` read as a rule for `kind`: `{"ok": true, "conditions": [...]}`, or
## `{"ok": false, "error": why}` in words for the toast.
static func parse(kind: String, text: String) -> Dictionary:
	var parts := _split(text)
	if parts.is_empty():
		return _error("Type a rule, such as %s" % EXAMPLES.get(kind, ""))
	var conditions: Array = []
	for part in parts:
		var read := _read_condition(kind, part)
		if not read["ok"]:
			return read
		conditions.append(read["condition"])
	return {"ok": true, "conditions": conditions}


## The visible brushes or entities of `kind` the rule's `conditions` pick, from
## `pool`, or from the whole level when `pool` is null. `{"ok": false, "error"}`
## for a material no palette slot is named.
static func pick(root: Node, kind: String, conditions: Array, pool: Variant = null) -> Dictionary:
	var resolved := _resolve(root, conditions)
	if not resolved["ok"]:
		return resolved
	var targeted: Dictionary = HFObjectFilterType.targeted_names(root) if kind == "entity" else {}
	var nodes: Array = pool if pool is Array else root._iter_pick_nodes()
	var out: Array = []
	for node in nodes:
		if not is_instance_valid(node) or not _is_kind(node, kind):
			continue
		if not (node as Node3D).is_visible_in_tree():
			continue
		if passes(root, node, kind, resolved["conditions"], targeted):
			out.append(node)
	return {"ok": true, "nodes": out}


## Whether `node` passes every condition.
static func passes(
	root: Node, node: Node, kind: String, conditions: Array, targeted: Dictionary
) -> bool:
	for condition in conditions:
		if not _condition_passes(root, node, kind, condition, targeted):
			return false
	return true


## The selection `matched` leaves of `current` in `mode`.
static func combine(current: Array, matched: Array, mode: int) -> Array:
	match mode:
		Mode.ADD:
			var out := current.duplicate()
			for node in matched:
				if not out.has(node):
					out.append(node)
			return out
		Mode.TAKE_AWAY:
			var out: Array = []
			for node in current:
				if not matched.has(node):
					out.append(node)
			return out
	return matched.duplicate()


## Which of `KINDS` `node` is, or "" for a node of none.
static func kind_of(root: Node, node: Node) -> String:
	if node is DraftEntity:
		return "entity"
	if not (node is DraftBrush):
		return ""
	if HFBrushEntity.entity_class(node) != "":
		return "brush_entity"
	return "cut" if HFSimilarType.cuts(root, node) else "solid"


## How many of `nodes` are of each kind, for the kinds there are.
static func kind_counts(root: Node, nodes: Array) -> Dictionary:
	var out: Dictionary = {}
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var kind := kind_of(root, node)
		if kind != "":
			out[kind] = int(out.get(kind, 0)) + 1
	return out


## The nodes of `nodes` that are of `kind`.
static func of_kind(root: Node, nodes: Array, kind: String) -> Array:
	var out: Array = []
	for node in nodes:
		if is_instance_valid(node) and kind_of(root, node) == kind:
			out.append(node)
	return out


static func _is_kind(node: Node, kind: String) -> bool:
	return node is DraftBrush if kind == "brush" else node is DraftEntity


static func _condition_passes(
	root: Node, node: Node, kind: String, condition: Dictionary, targeted: Dictionary
) -> bool:
	var property: String = condition["property"]
	var test: String = condition["test"]
	var value: Variant = condition["value"]
	if condition["own"]:
		var data: Variant = node.get("entity_data")
		if not (data is Dictionary) or not (data as Dictionary).has(property):
			return false
		if test == "matches":
			return str(data[property]).matchn(str(value))
		return HFObjectFilterType.entity_passes(
			root, node, {"property": {property: {test: value}}}, targeted
		)
	var rule := {property: value}
	var held: bool = (
		HFObjectFilterType.brush_passes(root, node, rule)
		if kind == "brush"
		else HFObjectFilterType.entity_passes(root, node, rule, targeted)
	)
	return not held if test == "!=" else held


static func _read_condition(kind: String, text: String) -> Dictionary:
	var words := RegEx.create_from_string("^([A-Za-z_][A-Za-z0-9_]*)\\s*(.*)$")
	var found := words.search(text)
	if found == null:
		return _error('"%s" is not a property and a test' % text)
	var property := found.get_string(1).to_lower()
	var rest := found.get_string(2)
	var test := ""
	var value_text := ""
	for written in TESTS:
		var word: String = written[0]
		if not rest.to_lower().begins_with(word):
			continue
		var after := rest.substr(word.length())
		# A word test stands apart: "isnt" is no test.
		if word[0].is_valid_identifier() and after != "" and not after.begins_with(" "):
			continue
		test = written[1]
		value_text = after.strip_edges()
		break
	if test == "":
		return _error('"%s" has no test: is, is not, >, <, or matches' % text)
	if value_text.length() >= 2 and value_text.begins_with('"') and value_text.ends_with('"'):
		value_text = value_text.substr(1, value_text.length() - 2)
	if value_text == "":
		return _error("Give %s a value" % property)
	var own := not properties(kind).has(property)
	if own and kind == "brush":
		return _error("A brush has no %s; it takes %s" % [property, ", ".join(properties("brush"))])
	if not own and not NAMED_TESTS.has(test):
		return _error("%s takes is, is not or matches" % property)
	var value: Variant = _value_of(property, value_text, own)
	if value == null:
		return _error(_value_problem(property))
	return {
		"ok": true,
		"condition": {"property": property, "test": test, "value": value, "own": own},
	}


## The value a condition compares, as the filter takes it, or null for one it
## cannot take.
static func _value_of(property: String, text: String, own: bool) -> Variant:
	var lower := text.to_lower()
	if own:
		if text.is_valid_float():
			return float(text)
		if lower in ["true", "false"]:
			return lower == "true"
		return text
	match property:
		"operation":
			if lower in ["add", "solid", "union"]:
				return "union"
			if lower in ["cut", "subtract"]:
				return "subtract"
			return null
		"has_outputs", "has_inputs":
			if lower in ["true", "yes"]:
				return true
			if lower in ["false", "no"]:
				return false
			return null
		"brush_entity":
			if lower in ["true", "yes", "any"]:
				return true
			if lower in ["false", "no", "none"]:
				return false
			return text
		"shape":
			return lower
	return text


static func _value_problem(property: String) -> String:
	match property:
		"operation":
			return "operation is add or cut"
		"has_outputs", "has_inputs":
			return "%s is true or false" % property
	return "%s takes a value" % property


## The conditions with a material named by its palette name, file or slot read
## to the slot the filter compares.
static func _resolve(root: Node, conditions: Array) -> Dictionary:
	var out: Array = []
	for condition in conditions:
		var copy: Dictionary = (condition as Dictionary).duplicate()
		if not copy["own"] and copy["property"] == "material":
			var slot := material_slot(root, str(copy["value"]))
			if slot < 0:
				return _error("No material in the palette is named %s" % copy["value"])
			copy["value"] = slot
		out.append(copy)
	return {"ok": true, "conditions": out}


## The palette slot `text` names: a slot number, a material's palette name or
## its file, with or without the folder and extension, case ignored. -1 for none.
static func material_slot(root: Node, text: String) -> int:
	var materials: Array = root.get_materials() if root.has_method("get_materials") else []
	var names: Array = root.get_material_names() if root.has_method("get_material_names") else []
	if text.is_valid_int() and int(text) >= 0 and int(text) < materials.size():
		return int(text)
	var wanted := text.to_lower()
	for slot in materials.size():
		var material: Material = materials[slot]
		var path := material.resource_path.to_lower() if material != null else ""
		var named := str(names[slot]).to_lower() if slot < names.size() else ""
		if (
			wanted == named
			or (path != "" and wanted in [path, path.get_file(), path.get_file().get_basename()])
		):
			return slot
	return -1


## `text` cut at each "and" and comma outside double quotes.
static func _split(text: String) -> Array:
	var parts: Array = []
	var current := ""
	var quoted := false
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == '"':
			quoted = not quoted
		elif not quoted and c == ",":
			parts.append(current)
			current = ""
			i += 1
			continue
		elif not quoted and text.substr(i, 5).to_lower() == " and ":
			parts.append(current)
			current = ""
			i += 5
			continue
		current += c
		i += 1
	parts.append(current)
	var out: Array = []
	for part in parts:
		if str(part).strip_edges() != "":
			out.append(str(part).strip_edges())
	return out


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
