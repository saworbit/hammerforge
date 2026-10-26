extends GutTest

## The entity census (#1709): counts by class in the Console's Entities tab, a
## click that selects a class, a CSV with one row per entity and one column per
## property, the same CSV from `tools/export_entities.gd`, and `count_by_class`
## over the bridge.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFEntityCensus = preload("res://addons/hammerforge/hf_entity_census.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const ExportTool = preload("res://tools/export_entities.gd")
const HFConsolePanelType = preload("res://addons/hammerforge/ui/hf_console_panel.gd")

const DIR := "user://test_entity_census"

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self)
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all():
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))
	DirAccess.remove_absolute(DIR)
	await rig.take_down()


func _entity(level, entity_class: String, entity_name: String, at: Vector3) -> Node:
	var entity: Node = level._create_entity_from_map({"classname": entity_class, "origin": at})
	entity.set_meta("entity_name", entity_name)
	return entity


## A point entity placed with a node name and no authored name.
func _placed(level, entity_class: String, node_name: String, at: Vector3) -> Node:
	return (
		level
		. entity_system
		. restore_entity_from_info(
			{
				"name": node_name,
				"entity_type": entity_class,
				"properties": {},
				"transform": Transform3D(Basis.IDENTITY, at),
			}
		)
	)


## The rows after the header, by their name column.
static func _rows_by_name(rows: Array) -> Dictionary:
	var header: PackedStringArray = rows[0]
	var out := {}
	for row in rows.slice(1):
		out[row[header.find("name")]] = row
	return out


## One cell of the row named `entity_name`, or "" when there is no such row.
static func _cell(by_name: Dictionary, entity_name: String, column: int) -> String:
	var row: PackedStringArray = by_name.get(entity_name, PackedStringArray())
	return row[column] if column < row.size() else ""


## Three lights, a sound, and a brush made a trigger.
func _furnish(level) -> Dictionary:
	var lamp_a := _entity(level, "light_point", "lamp_a", Vector3(0, 2, 0))
	var lamp_b := _entity(level, "light_point", "lamp_b", Vector3(4, 2, 0))
	var lamp_c := _entity(level, "light_point", "lamp_c", Vector3(40, 2, 0))
	_entity(level, "ambient_generic", "hum", Vector3(1, 1, 1))
	lamp_a.entity_data["energy"] = 1.5
	lamp_b.entity_data["note"] = 'says "hello, there"'
	var volume = rig.box(level, "volume", Vector3(0, 1, 4), Vector3(2, 2, 2))
	level.tie_brushes_to_entity(["volume"], "trigger_once")
	level.add_entity_output(volume, "OnTrigger", "lamp_a", "TurnOn")
	return {"lamp_a": lamp_a, "lamp_b": lamp_b, "lamp_c": lamp_c, "volume": volume}


func test_counts_by_class_point_and_brush_entities_both():
	var level = await rig.make_level()
	var made := _furnish(level)
	assert_eq(HFEntityCensus.counts(level).get("light_point"), 3)
	assert_eq(HFEntityCensus.counts(level).get("ambient_generic"), 1)
	assert_eq(HFEntityCensus.counts(level).get("trigger_once"), 1)
	assert_eq(HFEntityCensus.table(level)[0], ["light_point", 3], "most first")
	level.visgroup_system.add_to_visgroup(made["lamp_c"], "far")
	assert_eq(HFEntityCensus.counts(level, "visgroup:far"), {"light_point": 1})
	await rig.leave_level(level)


func _read_csv(path: String) -> Array:
	var rows: Array = []
	var file := FileAccess.open(path, FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 1 or (row.size() == 1 and row[0] != ""):
			rows.append(row)
	file.close()
	return rows


func test_the_csv_has_a_row_per_entity_and_a_column_per_property():
	var level = await rig.make_level()
	_furnish(level)
	var path := DIR.path_join("dock.csv")
	assert_eq(rig.plugin.dock.export_entities_to(path), OK)
	var rows := _read_csv(path)
	assert_eq(rows.size(), 1 + 5, "a header and one row per entity")
	var header: PackedStringArray = rows[0]
	for column in ["kind", "class", "name", "x", "outputs", "inputs", "energy", "note"]:
		assert_true(header.has(column), "a %s column" % column)
	var by_name := {}
	for row in rows.slice(1):
		by_name[row[header.find("name")]] = row
	assert_eq(by_name["lamp_a"][header.find("energy")], "1.5", "a decimal point")
	assert_eq(by_name["lamp_b"][header.find("note")], 'says "hello, there"', "a comma and quotes")
	assert_eq(by_name["lamp_c"][header.find("note")], "", "blank where it has none")
	assert_eq(by_name["lamp_a"][header.find("inputs")], "1", "the trigger aims at it")
	var trigger: PackedStringArray = by_name.values().filter(func(r): return r[1] == "trigger_once")[0]
	assert_eq(trigger[header.find("kind")], "brush")
	assert_eq(trigger[header.find("outputs")], "1")
	assert_ne(trigger[header.find("bounds_min")], "", "a brush entity with its bounds")
	await rig.leave_level(level)


func test_the_headless_tool_writes_the_same_csv_as_the_dock():
	var level = await rig.make_level()
	_furnish(level)
	var level_path := DIR.path_join("level.hflevel")
	assert_eq(HFLevelIO.save_to_path(level_path, level.state_system.capture_hflevel_state()), OK)
	var from_dock := DIR.path_join("from_dock.csv")
	var from_tool := DIR.path_join("from_tool.csv")
	assert_eq(rig.plugin.dock.export_entities_to(from_dock), OK)
	assert_eq(await ExportTool.export_level(level_path, from_tool, "", self), OK)
	assert_eq(FileAccess.get_file_as_string(from_tool), FileAccess.get_file_as_string(from_dock))
	await rig.leave_level(level)


func test_the_entities_tab_counts_and_a_click_selects_a_class():
	var level = await rig.make_level()
	var made := _furnish(level)
	var panel = rig.plugin.console_panel
	panel.show_tab(HFConsolePanelType.Tab.ENTITIES)
	panel.refresh_census()
	var root_item: TreeItem = panel._census_tree.get_root()
	var first := root_item.get_first_child()
	assert_eq([first.get_text(0), first.get_text(1)], ["light_point", "3"])
	first.select(0)
	await rig.frame()
	var selected: Array = rig.plugin.stand_in_editor.selection.get_selected_nodes()
	assert_eq(selected.size(), 3, "every light")
	for key in ["lamp_a", "lamp_b", "lamp_c"]:
		assert_true(selected.has(made[key]), "%s selected" % key)
	rig.select([])
	await rig.leave_level(level)


func test_the_bridge_counts_by_class():
	var level = await rig.make_level()
	_furnish(level)
	var tools = load("res://addons/hammerforge/mcp/hf_mcp_tools.gd").new()
	var r: Dictionary = tools._read_entities(level, {"count_by_class": true})
	assert_true(r.get("ok", false), str(r))
	assert_eq(
		r["result"],
		{"count_by_class": {"light_point": 3, "ambient_generic": 1, "trigger_once": 1}, "count": 5}
	)
	var refused: Dictionary = tools._read_entities(
		level, {"count_by_class": true, "filter": {"class": "light_point"}}
	)
	assert_false(refused.get("ok", true), "with a filter it would count something else")
	await rig.leave_level(level)


## A scaled entity reports the turn it was given, as the Inspector shows it. The
## turn was read off the scaled basis, so a prop scaled up reported angles nobody
## gave it (#1938).
func test_a_scaled_entity_reports_the_turn_it_was_given():
	var level = await rig.make_level()
	var lamp := _entity(level, "light_point", "lamp", Vector3(0, 2, 0)) as Node3D
	lamp.rotation_degrees = Vector3(20, 30, 0)
	lamp.scale = Vector3(2, 2, 2)
	var rows: Array = HFEntityCensus.csv_rows(level)
	var header: PackedStringArray = rows[0]
	var row: PackedStringArray = rows[1]
	assert_almost_eq(float(row[header.find("rotation_x")]), 20.0, 0.01, "its turn about X")
	assert_almost_eq(float(row[header.find("rotation_y")]), 30.0, 0.01, "and about Y")
	assert_almost_eq(float(row[header.find("rotation_z")]), 0.0, 0.01, "and none about Z")
	await rig.leave_level(level)


## A brush entity of several brushes is one entity. A trigger of two brushes
## read as two triggers, each with two outputs, and its one wire gave the lamp two
## inputs (#1958).
func test_a_brush_entity_of_two_brushes_is_one_entity():
	var level = await rig.make_level()
	_entity(level, "light_point", "lamp", Vector3(0, 2, 0))
	var near = rig.box(level, "near", Vector3(0, 1, 4), Vector3(2, 2, 2))
	var far = rig.box(level, "far", Vector3(6, 1, 4), Vector3(2, 2, 2))
	level.tie_brushes_to_entity(["near", "far"], "trigger_once")
	level.add_entity_output(near, "OnTrigger", "lamp", "TurnOn")
	assert_eq((far.get_meta("entity_io_outputs", []) as Array).size(), 1, "both hold the wire")
	assert_eq(HFEntityCensus.counts(level), {"light_point": 1, "trigger_once": 1})
	assert_eq(HFEntityCensus.of_class(level, "trigger_once"), [near], "one trigger")
	var rows: Array = HFEntityCensus.csv_rows(level)
	var header: PackedStringArray = rows[0]
	assert_eq(rows.size(), 1 + 2, "a row for the lamp and one for the trigger")
	var trigger: PackedStringArray = rows.slice(1).filter(func(r): return r[1] == "trigger_once")[0]
	assert_eq(trigger[header.find("outputs")], "1", "its one wire")
	assert_eq(trigger[header.find("bounds_min")], "-1.0 0.0 3.0", "its bounds from the near brush")
	assert_eq(trigger[header.find("bounds_max")], "7.0 2.0 5.0", "to the far one")
	assert_eq(_rows_by_name(rows)["lamp"][header.find("inputs")], "1", "one wire at the lamp")
	# A wire on one of its brushes alone, as a level saved before #1129 holds
	# one, is the trigger's too.
	var own: Dictionary = (far.get_meta("entity_io_outputs")[0] as Dictionary).duplicate()
	own["input_name"] = "TurnOff"
	far.set_meta("entity_io_outputs", far.get_meta("entity_io_outputs") + [own])
	rows = HFEntityCensus.csv_rows(level)
	trigger = rows.slice(1).filter(func(r): return r[1] == "trigger_once")[0]
	assert_eq(trigger[header.find("outputs")], "2", "the far brush's own wire as well")
	assert_eq(_rows_by_name(rows)["lamp"][header.find("inputs")], "2", "both at the lamp")
	# In a visgroup by its far brush alone, it is in that visgroup's census.
	level.visgroup_system.add_to_visgroup(far, "upstairs")
	assert_eq(HFEntityCensus.entities(level, "visgroup:upstairs"), [far], "by its far brush")
	rows = HFEntityCensus.csv_rows(level)
	trigger = rows.slice(1).filter(func(r): return r[1] == "trigger_once")[0]
	assert_eq(trigger[header.find("visgroups")], "upstairs", "the visgroups of every brush")
	# A click on the class still selects the whole trigger.
	var panel = rig.plugin.console_panel
	panel.show_tab(HFConsolePanelType.Tab.ENTITIES)
	panel.refresh_census()
	var item: TreeItem = panel._census_tree.get_root().get_first_child()
	while item and item.get_text(0) != "trigger_once":
		item = item.get_next()
	item.select(0)
	await rig.frame()
	var selected: Array = rig.plugin.stand_in_editor.selection.get_selected_nodes()
	assert_eq(selected.size(), 2, "both brushes")
	assert_true(selected.has(near) and selected.has(far), "the near and the far")
	rig.select([])
	await rig.leave_level(level)


## A point entity with no authored name is wired by its node name, as the wiring
## panel lists it and `find_entities_by_name()` finds it. Its row read a blank
## name and no inputs. An entity with both names goes by its authored name and
## counts a wire at either, and a wire at a name it has twice counts once (#1984).
func test_a_point_entity_is_named_and_aimed_at_as_the_wiring_finds_it():
	var level = await rig.make_level()
	var lamp := _placed(level, "light_point", "lamp", Vector3(0, 2, 0))
	var hall := _placed(level, "light_point", "hall", Vector3(4, 2, 0))
	hall.set_meta("entity_name", "hall_light")
	var porch := _placed(level, "light_point", "porch", Vector3(8, 2, 0))
	porch.set_meta("entity_name", "porch")
	var button := _placed(level, "func_button", "button", Vector3(2, 1, 0))
	for target in ["lamp", "hall", "hall_light", "porch"]:
		level.add_entity_output(button, "OnPressed", target, "Toggle")
	assert_eq(level.find_entities_by_name("lamp"), [lamp], "the wiring finds it by node name")
	var rows: Array = HFEntityCensus.csv_rows(level)
	var inputs: int = (rows[0] as PackedStringArray).find("inputs")
	var by_name := _rows_by_name(rows)
	assert_eq(by_name.keys().size(), 4, "a row each, each named")
	assert_true(by_name.has("lamp"), "the lamp by its node name")
	assert_eq(_cell(by_name, "lamp", inputs), "1", "its wire")
	assert_false(by_name.has("hall"), "the hall light by its authored name")
	assert_eq(_cell(by_name, "hall_light", inputs), "2", "a wire at either of its names")
	assert_eq(_cell(by_name, "porch", inputs), "1", "a wire at a name it has twice, once")
	await rig.leave_level(level)


## A class property named like a column of the census's own goes under
## "property:", so no name is in the header twice. A note's Kind and the
## census's kind, point or brush, were both "kind" (#1988).
func test_a_property_named_like_a_column_keeps_the_header_unique():
	var level = await rig.make_level()
	var note := _placed(level, "note", "todo", Vector3.ZERO)
	level.set_entity_property(note, "kind", "To Do")
	var rows: Array = HFEntityCensus.csv_rows(level)
	var header: PackedStringArray = rows[0]
	var seen := {}
	for column in header:
		assert_false(seen.has(column), "%s is in the header once" % column)
		seen[column] = true
	assert_eq(rows[1][header.find("kind")], "point", "the census's own kind")
	assert_eq(rows[1][header.find("property:kind")], "To Do", "the note's, under property:")
	await rig.leave_level(level)
