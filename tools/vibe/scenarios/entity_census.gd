@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether the Entity Census counts what is there and writes a CSV that reads
## back as the same table.
##
## The Console's Entities tab and Export Entities both read `HFEntityCensus`, and
## the guide promises one row per entity, a decimal point whatever the locale,
## colours as `#rrggbb`, vectors as `x y z`, and quoting that makes the file open
## cleanly in any spreadsheet. So each check here is made independently: the
## entities are counted off the scene tree, the file is read back with Godot's
## own CSV reader and compared cell by cell, and each entity's inputs are counted
## by resolving every wire with `find_entities_by_name()`, which is how a wire is
## resolved when the level runs.
##
## A brush entity of several brushes counted per brush is #1958, so every brush
## entity here is one brush.

const HFEntityCensus = preload("res://addons/hammerforge/hf_entity_census.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const HFFormatCensus = preload("res://addons/hammerforge/hf_format_census.gd")

const CSV_PATH := "user://vibe_entity_census.csv"


func id() -> String:
	return "entity-census"


func summary() -> String:
	return "the census's counts, inputs and CSV quoting against the level and Godot's CSV reader"


func expected_issues() -> Array[int]:
	return [1958, 1984, 1988]


func run() -> void:
	var root: Node3D = await fresh_root("CensusLevel")
	root.hflevel_autosave_enabled = false
	var lamp := _entity(root, "light_point", "lamp", Vector3(0, 2, 0))
	var named := _entity(root, "light_point", "hall_light", Vector3(4, 2, 0))
	named.set_meta("entity_name", 'hall, "east"')
	var button := _entity(root, "func_button", "button", Vector3(2, 1, 0))
	var note := _entity(root, "note", "todo_note", Vector3(-2, 0, 0))
	box(root, Vector3(1, 2, 0.2), Vector3(-4, 1, 0))
	var door_id := str(root.draft_brushes_node.get_child(0).brush_id)
	root.tie_brushes_to_entity([door_id], "func_door", "door_1")
	await frame()

	# Values with every character the guide says is quoted, and some it does not.
	root.set_entity_property(lamp, "color", Color(1.0, 0.5, 0.25))
	root.set_entity_property(lamp, "energy", 2.5)
	root.set_entity_property(note, "title", 'Fix, then "ship"')
	root.set_entity_property(note, "body", "line one\nline two, with a comma\r\nline three")
	root.set_entity_property(note, "kind", "To Do")
	root.set_entity_property(named, "projector", "res://tex/a b,c.png")
	# A wire aimed at an entity by its node name, as the wiring panel's own
	# picker names a point entity with no authored name, and one by authored name.
	root.add_entity_output(button, "OnPressed", "lamp", "Toggle")
	root.add_entity_output(button, "OnPressed", 'hall, "east"', "TurnOn")
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	await frame()

	_counts(root)
	_inputs(root)
	_header(root)
	_round_trip(root)
	await _scopes(root, lamp)

	if FileAccess.file_exists(CSV_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CSV_PATH))
	await drop_root(root)
	await _format_census_wires()


## The other census: what an export says it left out (`HFFormatCensus`). A
## two leaf door is one entity with one wire, held on both of its brushes.
func _format_census_wires() -> void:
	var root: Node3D = await fresh_root("FormatCensusLevel")
	root.hflevel_autosave_enabled = false
	var lamp := _entity(root, "light_point", "lamp", Vector3(0, 2, 3))
	var left = root.create_brush_from_info(
		{
			"shape": 0,
			"size": Vector3(1, 2, 0.2),
			"center": Vector3(-0.5, 1, 0),
			"brush_id": "leaf_l"
		}
	)
	root.create_brush_from_info(
		{"shape": 0, "size": Vector3(1, 2, 0.2), "center": Vector3(0.5, 1, 0), "brush_id": "leaf_r"}
	)
	root.tie_brushes_to_entity(["leaf_l", "leaf_r"], "func_door", "double_door")
	root.add_entity_output(left, "OnOpen", "lamp", "TurnOn")
	await frame()
	var holders := 0
	for brush in root.draft_brushes_node.get_children():
		if not (brush.get_meta("entity_io_outputs", []) as Array).is_empty():
			holders += 1
	var said: String = HFFormatCensus.left_out(root, ".glb")
	var wired: int = HFFormatCensus.count(root, "wires")
	note("brushes holding the door's one wire", holders)
	note(".glb export would say", said)
	if wired != 1:
		known(
			1958,
			"an export says it left out the wires of %d entities for one wired door" % wired,
			(
				"HFFormatCensus.count('wires') counts every brush that holds the wire, and a brush entity's wires are held on each of its brushes (the shape of #1958, in hf_format_census.gd): '%s'"
				% said
			)
		)
	await drop_root(root)


func _entity(root: Node3D, type_id: String, node_name: String, at: Vector3) -> Node3D:
	return (
		root
		. entity_system
		. restore_entity_from_info(
			{
				"name": node_name,
				"entity_type": type_id,
				"properties": {},
				"transform": Transform3D(Basis.IDENTITY, at),
			}
		)
	)


## Counts by class against the scene tree.
func _counts(root: Node3D) -> void:
	var mine := {}
	for child in root.entities_node.get_children():
		if child is DraftEntity:
			var entity_class := str(child.entity_class)
			mine[entity_class] = int(mine.get(entity_class, 0)) + 1
	for brush in root.draft_brushes_node.get_children():
		var entity_class := str(brush.get_meta("brush_entity_class", ""))
		if entity_class != "":
			mine[entity_class] = int(mine.get(entity_class, 0)) + 1
	var theirs: Dictionary = HFEntityCensus.counts(root)
	note("counted off the tree", mine)
	note("the census", theirs)
	if HFVibe.canonical(mine) != HFVibe.canonical(theirs):
		flag("the census counts differ from the tree", "%s against %s" % [theirs, mine])


## Each row's inputs against the wires that resolve to that entity.
func _inputs(root: Node3D) -> void:
	var rows: Array = HFEntityCensus.csv_rows(root)
	var header: PackedStringArray = rows[0]
	var name_col := header.find("name")
	var inputs_col := header.find("inputs")
	var nodes: Array = HFEntityCensus.entities(root)
	var resolved := {}
	for connection in root.get_all_entity_connections():
		for target in root.find_entities_by_name(str(connection.get("target_name", ""))):
			resolved[target] = int(resolved.get(target, 0)) + 1
	for i in nodes.size():
		var node: Node = nodes[i]
		var row: PackedStringArray = rows[i + 1]
		var said := int(row[inputs_col])
		var real := int(resolved.get(node, 0))
		note(
			"inputs of %s" % node.name,
			"census %d, wires that resolve to it %d, name column '%s'" % [said, real, row[name_col]]
		)
		if said != real:
			known(
				1984,
				(
					"the census gives %s %d inputs where %d wires resolve to it"
					% [node.name, said, real]
				),
				(
					"_input_counts() keys the wires by target_name and _fixed() looks them up by the authored name alone (blank here: '%s'), while find_entities_by_name() resolves a wire by the node name too"
					% row[name_col]
				)
			)


## Every column name once.
func _header(root: Node3D) -> void:
	var header: PackedStringArray = HFEntityCensus.csv_rows(root)[0]
	note("header", ",".join(header))
	var seen := {}
	for column in header:
		if seen.has(column):
			known(
				1988,
				"the CSV header names '%s' twice" % column,
				"a class property of that name is appended after the fixed columns of the same name (note's Kind against the census's own kind), so a reader by header gets one and loses the other"
			)
		seen[column] = true


## Written, read back with FileAccess.get_csv_line, and compared cell by cell.
func _round_trip(root: Node3D) -> void:
	var rows: Array = HFEntityCensus.csv_rows(root)
	var err: int = HFEntityCensus.write_csv(root, CSV_PATH)
	if err != OK:
		flag("the census CSV does not write", error_string(err))
		return
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	var back: Array = []
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() == 1 and line[0] == "":
			continue
		back.append(line)
	file.close()
	note("rows written / read back", "%d / %d" % [rows.size(), back.size()])
	if back.size() != rows.size():
		flag(
			"the CSV reads back as a different number of rows",
			"%d against %d" % [back.size(), rows.size()]
		)
		return
	for r in rows.size():
		var want: PackedStringArray = rows[r]
		var got: PackedStringArray = back[r]
		if want.size() != got.size():
			flag("row %d reads back with %d cells, not %d" % [r, got.size(), want.size()], got)
			continue
		for c in want.size():
			# Godot's reader takes a CR LF inside a quoted cell as LF; the file
			# itself holds the CR, so that difference is the reader's.
			if want[c].replace("\r\n", "\n") != got[c]:
				flag(
					"row %d column %s reads back changed" % [r, rows[0][c]],
					"%s -> %s" % [want[c].c_escape(), got[c].c_escape()]
				)
	note("cells compared", "commas, quotes and newlines in names and properties")
	# An unturned entity's rotation_x reads -0.0: get_euler() gives a negative
	# zero and String.num() keeps the sign. A spreadsheet reads it as 0.
	for row in rows.slice(1):
		note("  row", ",".join(PackedStringArray(row).slice(0, 14)).c_escape())


## The cordon and visgroup scopes against the same questions asked by hand.
func _scopes(root: Node3D, lamp: Node3D) -> void:
	root.create_visgroup("upstairs")
	root.add_selection_to_visgroup("upstairs", [lamp])
	var in_group: Array = HFEntityCensus.entities(root, HFEntityCensus.VISGROUP_SCOPE + "upstairs")
	note("entities in visgroup upstairs", in_group.map(func(n): return str(n.name)))
	if in_group.size() != 1 or in_group[0] != lamp:
		flag("the visgroup scope does not hold just the lamp", in_group)
	root.cordon_enabled = true
	root.cordon_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 4, 2))
	await frame()
	var inside: Array = HFEntityCensus.entities(root, HFEntityCensus.SCOPE_CORDONS)
	note("entities inside the cordon", inside.map(func(n): return str(n.name)))
	root.cordon_enabled = false
