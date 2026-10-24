@tool
extends RefCounted
## Which brushes and entities a rule picks (#1704).
##
## A rule is a Dictionary of tests, every one of which must hold. The bridge's
## `hf_get_brushes` and `hf_get_entities` filter through this, so the rules live
## in one place for the editor's own selection commands to read too (#1698), and
## an agent and a person get the same set for the same rule.
##
## Brush tests: `operation` ("union" or "subtract"), `material` (a palette slot
## any face wears; the caller resolves a name or an id to one), `shape`,
## `visgroup`, `group`, `structure` (a generator id, for its pieces), `prefab` (a
## placed copy's instance id), `brush_entity` (a class, or true for any, false for
## none) and `name`.
##
## Entity tests: `class`, `name`, `visgroup`, `has_outputs`, `has_inputs` and
## `property`, a Dictionary of property name to a value it must equal or to
## `{comparison: value}`, as `{"energy": {">": 2}}`.
##
## `name` and `class` take `*` for any run of characters and `?` for one, case
## ignored. A brush's `name` test is passed by its node name or its brush id.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFBrushEntity = preload("hf_brush_entity.gd")
const HFGeneratorSystem = preload("systems/hf_generator_system.gd")
@warning_ignore_restore("shadowed_global_identifier")
const LevelRootScript = preload("level_root.gd")

const BRUSH_TESTS := [
	"operation",
	"material",
	"shape",
	"visgroup",
	"group",
	"structure",
	"prefab",
	"brush_entity",
	"name",
]
const ENTITY_TESTS := ["class", "name", "visgroup", "has_outputs", "has_inputs", "property"]
const COMPARISONS := ["=", "!=", ">", ">=", "<", "<="]


## The first key of `rule` that is not one of `tests`, or "".
static func unknown_test(rule: Dictionary, tests: Array) -> String:
	for key in rule:
		if not tests.has(str(key)):
			return str(key)
	return ""


## A brush's shape as the bridge names it: "box", "cylinder", ... or "custom".
static func shape_name(brush: Node) -> String:
	var key: Variant = LevelRootScript.BrushShape.find_key(int(brush.get("shape")))
	return str(key).to_lower() if key != null else "custom"


static func name_matches(pattern: String, text: String) -> bool:
	return text.matchn(pattern)


## Whether `brush` passes every test in `rule`.
static func brush_passes(root: Node, brush: Node, rule: Dictionary) -> bool:
	for test in rule:
		var want: Variant = rule[test]
		match str(test):
			"operation":
				var cuts: bool = brush.get("operation") == CSGShape3D.OPERATION_SUBTRACTION
				if cuts != (str(want) == "subtract"):
					return false
			"material":
				if not _wears(brush, int(want)):
					return false
			"shape":
				if shape_name(brush) != str(want):
					return false
			"visgroup":
				if not _visgroups(root, brush).has(str(want)):
					return false
			"group":
				if (
					root.visgroup_system == null
					or root.visgroup_system.get_group_of(brush) != str(want)
				):
					return false
			"structure":
				if str(brush.get_meta(HFGeneratorSystem.GENERATOR_META, "")) != str(want):
					return false
			"prefab":
				if _prefab_id(root, brush) != str(want):
					return false
			"brush_entity":
				var entity_class := HFBrushEntity.entity_class(brush)
				if want is bool:
					if (entity_class != "") != bool(want):
						return false
				elif not name_matches(str(want), entity_class):
					return false
			"name":
				var named := name_matches(str(want), str(brush.name))
				if not named and not name_matches(str(want), str(brush.get("brush_id"))):
					return false
			_:
				return false
	return true


## Whether `entity` passes every test in `rule`. `targeted` is the entity names
## some output aims at, from `targeted_names()`, read once for a whole listing.
static func entity_passes(root: Node, entity: Node, rule: Dictionary, targeted: Dictionary) -> bool:
	for test in rule:
		var want: Variant = rule[test]
		match str(test):
			"class":
				if not name_matches(str(want), str(entity.get("entity_class"))):
					return false
			"name":
				if not name_matches(str(want), str(entity.get_meta("entity_name", ""))):
					return false
			"visgroup":
				if not _visgroups(root, entity).has(str(want)):
					return false
			"has_outputs":
				if root.get_entity_outputs(entity).is_empty() == bool(want):
					return false
			"has_inputs":
				var named := str(entity.get_meta("entity_name", ""))
				if (named != "" and targeted.has(named)) != bool(want):
					return false
			"property":
				if not _properties_pass(entity.get("entity_data"), want):
					return false
			_:
				return false
	return true


## The entity names some entity's or brush entity's output aims at.
static func targeted_names(root: Node) -> Dictionary:
	var names: Dictionary = {}
	var sources: Array = []
	if root.entities_node:
		sources.append_array(root.entities_node.get_children())
	sources.append_array(root._iter_managed_brush_nodes())
	for source in sources:
		for connection in root.get_entity_outputs(source):
			if connection is Dictionary:
				names[str(connection.get("target_name", ""))] = true
	return names


## Whether `test`, a property test as `property` takes one, is one this reads: a
## Dictionary of names to a value or to one `{comparison: value}`.
static func property_test_problem(test: Variant) -> String:
	if not (test is Dictionary):
		return 'property is {"name": value} or {"name": {">": value}}'
	for key in test:
		var want: Variant = test[key]
		if want is Dictionary:
			if (want as Dictionary).size() != 1 or not COMPARISONS.has(str(want.keys()[0])):
				return "property %s takes one of %s" % [key, ", ".join(COMPARISONS)]
	return ""


static func _properties_pass(data: Variant, test: Dictionary) -> bool:
	var values: Dictionary = data if data is Dictionary else {}
	for key in test:
		if not values.has(key):
			return false
		var want: Variant = test[key]
		var comparison := "="
		if want is Dictionary:
			comparison = str(want.keys()[0])
			want = want.values()[0]
		if not _compare(values[key], comparison, want):
			return false
	return true


## A number against a number as numbers; anything else as text.
static func _compare(have: Variant, comparison: String, want: Variant) -> bool:
	var numbers := (have is int or have is float) and (want is int or want is float)
	if numbers:
		var a := float(have)
		var b := float(want)
		match comparison:
			"=":
				return is_equal_approx(a, b)
			"!=":
				return not is_equal_approx(a, b)
			">":
				return a > b
			">=":
				return a >= b
			"<":
				return a < b
			"<=":
				return a <= b
		return false
	var left := str(have)
	var right := str(want)
	match comparison:
		"=":
			return left == right
		"!=":
			return left != right
		">":
			return left > right
		">=":
			return left >= right
		"<":
			return left < right
		"<=":
			return left <= right
	return false


static func _wears(brush: Node, slot: int) -> bool:
	for face in brush.get("faces"):
		if face != null and int(face.material_idx) == slot:
			return true
	return false


static func _visgroups(root: Node, node: Node) -> PackedStringArray:
	if root.visgroup_system == null:
		return PackedStringArray()
	return root.visgroup_system.get_visgroups_of(node)


static func _prefab_id(root: Node, node: Node) -> String:
	if root.prefab_system == null:
		return ""
	var record = root.prefab_system.instance_of(node)
	return str(record.instance_id) if record != null else ""
