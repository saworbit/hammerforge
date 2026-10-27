@tool
extends RefCounted
## Every entity in a level, counted by class and written out as a table (#1709).
##
## The Console's Entities tab shows the count of each class and selects a class
## on a click, Export Entities writes the CSV, `tools/export_entities.gd` writes
## the same CSV from a `.hflevel` with no editor, and `hf_get_entities` answers
## `count_by_class` from `counts()`. Point entities and brush entities both count:
## a trigger is a brush made an entity, and it is what a designer counts. A brush
## entity of several brushes is one entity, by `HFBrushEntity.entities_in()`
## (#1958).
##
## The CSV has one row per entity and one column per property, the union of every
## class's, blank where a class has none. A property named like a column of its
## own goes under `PROPERTY_PREFIX` (#1988). Numbers use a decimal point whatever
## the system says, a colour is "#rrggbb", a vector "x y z", and a value with a
## comma or a quote in it is quoted, by `FileAccess.store_csv_line()`.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFBrushEntity = preload("hf_brush_entity.gd")
const DraftEntity = preload("draft_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFObjectFilter = preload("hf_object_filter.gd")
const HFBakeSystemType = preload("systems/hf_bake_system.gd")

## The scopes `entities()` takes besides the whole level: a visgroup by name, as
## "visgroup:<name>", or what stands inside the active cordons.
const SCOPE_CORDONS := "cordons"
const VISGROUP_SCOPE := "visgroup:"

## The columns every row has, before the properties.
const FIXED_COLUMNS := [
	"kind",
	"class",
	"name",
	"x",
	"y",
	"z",
	"rotation_x",
	"rotation_y",
	"rotation_z",
	"bounds_min",
	"bounds_max",
	"visgroups",
	"outputs",
	"inputs",
]
## What a property named like one of `FIXED_COLUMNS` goes under in the header,
## as the note's `kind` goes under "property:kind" (#1988).
const PROPERTY_PREFIX := "property:"


## The point entities and brush entities in `scope`: "" for the whole level, a
## `VISGROUP_SCOPE` name, or `SCOPE_CORDONS`. A brush entity is in it when one of
## its brushes is, and is given by the first of those.
static func entities(root: Node, scope: String = "") -> Array:
	return _entity_nodes(root, scope).map(func(nodes: Array): return nodes[0])


## Each entity in `scope` as its nodes: a point entity alone, or every brush of a
## brush entity, the one `entities()` gives first. Each of a trigger's brushes was
## an entity of its own (#1958).
static func _entity_nodes(root: Node, scope: String) -> Array:
	var out: Array = []
	if root.entities_node:
		for node in root.entities_node.get_children():
			if node is DraftEntity and _in_scope(root, node, scope):
				out.append([node])
	for brushes in HFBrushEntity.entities_in(_brushes(root)):
		var inside: Array = brushes.filter(func(brush): return _in_scope(root, brush, scope))
		if not inside.is_empty():
			out.append([inside[0]] + brushes.filter(func(brush): return brush != inside[0]))
	return out


static func _brushes(root: Node) -> Array:
	return root._iter_managed_brush_nodes().filter(
		func(brush): return brush.get_parent() != root.committed_node
	)


## `{class: count}` for the entities in `scope`.
static func counts(root: Node, scope: String = "") -> Dictionary:
	var out: Dictionary = {}
	for node in entities(root, scope):
		var entity_class := class_of(node)
		out[entity_class] = int(out.get(entity_class, 0)) + 1
	return out


## The census as rows for a table, `[class, count]`, most first and then by name.
static func table(root: Node, scope: String = "") -> Array:
	var by_class := counts(root, scope)
	var rows: Array = []
	for entity_class in by_class:
		rows.append([entity_class, by_class[entity_class]])
	rows.sort_custom(
		func(a: Array, b: Array) -> bool: return a[1] > b[1] if a[1] != b[1] else a[0] < b[0]
	)
	return rows


static func class_of(node: Node) -> String:
	if node is DraftEntity:
		return str((node as DraftEntity).entity_class)
	return HFBrushEntity.entity_class(node)


## The entities in `scope` that are of `entity_class`, for the tab's click, a
## brush entity by one of its brushes as `entities()` gives it.
static func of_class(root: Node, entity_class: String, scope: String = "") -> Array:
	return entities(root, scope).filter(func(node): return class_of(node) == entity_class)


## The whole table, header first, each row a PackedStringArray.
static func csv_rows(root: Node, scope: String = "") -> Array:
	var each := _entity_nodes(root, scope)
	var targeted := _input_counts(root)
	var property_names: Dictionary = {}
	for nodes in each:
		for key in _properties(root, nodes[0]):
			property_names[str(key)] = true
	var properties: Array = property_names.keys()
	properties.sort()
	var rows: Array = [_header(properties)]
	for nodes in each:
		var values := _properties(root, nodes[0])
		var row := _fixed(root, nodes, targeted)
		for key in properties:
			row.append(cell(values[key]) if values.has(key) else "")
		rows.append(row)
	return rows


## `FIXED_COLUMNS` and then `properties`, each name once: a property named like a
## column already there goes under `PROPERTY_PREFIX`. The note's `kind` and the
## census's own were both "kind", and a reader by header kept one (#1988).
static func _header(properties: Array) -> PackedStringArray:
	var header := PackedStringArray(FIXED_COLUMNS)
	for key in properties:
		var column := str(key)
		while header.has(column):
			column = PROPERTY_PREFIX + column
		header.append(column)
	return header


## Write the table to `path`. OK, or the error the file gave.
static func write_csv(root: Node, path: String, scope: String = "") -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	for row in csv_rows(root, scope):
		file.store_csv_line(row)
	var err := file.get_error()
	file.close()
	return err


## A value as a cell: numbers with a decimal point whatever the locale, to four
## places so a value read back from a file writes the same, a colour as
## "#rrggbb", a vector as "x y z", a resource as its path.
static func cell(value: Variant) -> String:
	if value is float:
		return String.num(value, 4)
	if value is Color:
		var colour := value as Color
		return "#" + colour.to_html(colour.a < 1.0)
	if value is Vector3:
		var v := value as Vector3
		return "%s %s %s" % [String.num(v.x, 4), String.num(v.y, 4), String.num(v.z, 4)]
	if value is Resource:
		return (value as Resource).resource_path
	if value == null:
		return ""
	return str(value)


## The fixed columns of the entity `nodes` make, as `_entity_nodes()` gives it.
static func _fixed(root: Node, nodes: Array, targeted: Dictionary) -> PackedStringArray:
	var node: Node = nodes[0]
	var spatial := node as Node3D
	var at := spatial.global_position
	# The turn, in the Inspector's order, read off the basis without its scale:
	# angles read off a scaled basis are not the turn it was given (#1938).
	var turn := spatial.global_transform.basis.orthonormalized().get_euler() * (180.0 / PI)
	var bounds_min := ""
	var bounds_max := ""
	var kind := "point"
	var outputs: Array = root.get_entity_outputs(node)
	if not (node is DraftEntity):
		kind = "brush"
		# Every brush of it, and each wire every brush holds once (#1958).
		var box: AABB = root.brush_system.world_bounds_of(node)
		for brush in nodes.slice(1):
			box = box.merge(root.brush_system.world_bounds_of(brush))
		bounds_min = cell(box.position)
		bounds_max = cell(box.end)
		outputs = HFBrushEntity.wires_of(nodes)
	var visgroups := PackedStringArray()
	if root.visgroup_system:
		for each in nodes:
			for visgroup in root.visgroup_system.get_visgroups_of(each):
				if not visgroups.has(visgroup):
					visgroups.append(visgroup)
	return PackedStringArray(
		[
			kind,
			class_of(node),
			_name_of(node),
			cell(at.x),
			cell(at.y),
			cell(at.z),
			cell(turn.x),
			cell(turn.y),
			cell(turn.z),
			bounds_min,
			bounds_max,
			";".join(visgroups),
			str(outputs.size()),
			str(_inputs(nodes, targeted)),
		]
	)


## A point entity's authored name, or its node name when it has none, as the
## wiring panel lists it and `find_entities_by_name()` finds it (#1984). A brush
## entity's authored name.
static func _name_of(node: Node) -> String:
	if node is DraftEntity:
		var authored := str(node.get_meta("entity_name", ""))
		return authored if authored != "" else str(node.name)
	return HFBakeSystemType.authored_entity_name(node)


## How many wires aim at the entity `nodes` make, by any name one of them answers
## to, its node name or its authored name, as `find_entities_by_name()` resolves a
## wire. A name it answers to twice counts once (#1984).
static func _inputs(nodes: Array, targeted: Dictionary) -> int:
	var addresses: Dictionary = {}
	for node in nodes:
		addresses[str(node.name)] = true
		addresses[str(node.get_meta("entity_name", ""))] = true
	addresses.erase("")
	var many := 0
	for address in addresses:
		many += int(targeted.get(address, 0))
	return many


## A point entity's properties as set, or a brush entity's as the bake reads them.
static func _properties(root: Node, node: Node) -> Dictionary:
	if node is DraftEntity:
		var data: Variant = (node as DraftEntity).entity_data
		return data if data is Dictionary else {}
	var entity_class := HFBrushEntity.entity_class(node)
	return HFBrushEntity.properties(root.get_entity_definition(entity_class), node)


## How many wires aim at each name: a point entity's, and a brush entity's once
## however many of its brushes hold them (#1958).
static func _input_counts(root: Node) -> Dictionary:
	var out: Dictionary = {}
	var held: Array = []
	if root.entities_node:
		for node in root.entities_node.get_children():
			held.append(root.get_entity_outputs(node))
	for brushes in HFBrushEntity.entities_in(_brushes(root)):
		held.append(HFBrushEntity.wires_of(brushes))
	for wires in held:
		for connection in wires:
			if connection is Dictionary:
				var target := str(connection.get("target_name", ""))
				out[target] = int(out.get(target, 0)) + 1
	return out


static func _in_scope(root: Node, node: Node, scope: String) -> bool:
	if scope == "":
		return true
	if scope.begins_with(VISGROUP_SCOPE):
		return HFObjectFilter.brush_passes(
			root, node, {"visgroup": scope.trim_prefix(VISGROUP_SCOPE)}
		)
	if scope == SCOPE_CORDONS:
		var at := (node as Node3D).global_position
		for region in root.get_cordon_regions():
			if region.grow(0.0001).has_point(at):
				return true
		return false
	return true
