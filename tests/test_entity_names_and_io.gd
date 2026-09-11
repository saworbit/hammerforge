extends GutTest

## An entity has two addresses: the node name Godot gave it, and the authored
## `entity_name` that every connection is aimed at. These tests cover the places
## the two were being mixed up, and the `.map` export that carried neither.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const MapIOType = preload("res://addons/hammerforge/map_io.gd")
const QuakeAdapter = preload("res://addons/hammerforge/map_adapters/hf_map_quake.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info(
			{"size": Vector3(32, 32, 32), "center": Vector3.ZERO, "brush_id": brush_id}
		)
		as DraftBrush
	)


## A point entity in the level.
func _point_entity(entity_class: String) -> DraftEntity:
	return root._create_entity_from_map({"classname": entity_class, "origin": Vector3.ZERO})


## A brush entity with an authored name whose node name is something else.
func _wired_button() -> DraftBrush:
	var brush := _box("b1")
	root.tie_brushes_to_entity(["b1"], "func_button")
	brush.set_meta("entity_name", "btn")
	root.add_entity_output(brush, "OnPressed", "door", "Open", "", 0.0, false)
	return brush


# -- Connection records use one namespace -------------------------------------


func test_a_connection_reports_its_source_under_the_authored_name():
	var brush := _wired_button()

	var connections: Array = root.get_all_entity_connections()

	assert_eq(connections.size(), 1, "One output means one connection")
	assert_eq(connections[0]["source_name"], "btn", "The source is the name it is addressed by")
	assert_eq(
		connections[0]["source_node_name"], str(brush.name), "with the node name still available"
	)


func test_the_summary_counts_a_brush_entity_as_triggering():
	_wired_button()

	var summary: Dictionary = root.get_connection_summary("btn")

	assert_eq(summary["triggers"], 1, "The button triggers one thing")
	assert_eq(summary["target_names"], ["door"], "and it is the door")


func test_the_summary_also_answers_to_the_node_name():
	var brush := _wired_button()

	var summary: Dictionary = root.get_connection_summary(str(brush.name))

	assert_eq(summary["triggers"], 1, "An entity answers to both of its addresses")


func test_an_entity_with_no_authored_name_still_reports_its_node_name():
	var brush := _box("b1")
	root.tie_brushes_to_entity(["b1"], "func_button")
	root.add_entity_output(brush, "OnPressed", "door", "Open", "", 0.0, false)

	var connections: Array = root.get_all_entity_connections()

	assert_eq(connections[0]["source_name"], str(brush.name), "The node name is the fallback")


func test_the_target_side_is_unchanged():
	_wired_button()

	var summary: Dictionary = root.get_connection_summary("door")

	assert_eq(summary["triggered_by"], 1, "The door is triggered by one thing")
	assert_eq(summary["source_names"], ["btn"], "named the way it is addressed")


# -- The .map value shape -----------------------------------------------------


func test_a_connection_round_trips_through_its_map_value():
	var value := MapIOType.format_connection(
		{
			"target_name": "lamp",
			"input_name": "TurnOn",
			"parameter": "bright",
			"delay": 1.5,
			"fire_once": true
		}
	)
	assert_eq(value, "lamp,TurnOn,bright,1.5,1", "Target, input, parameter, delay, once")

	var parsed := MapIOType.parse_connection("OnOpen", value)

	assert_eq(parsed["output_name"], "OnOpen", "The key is the output name")
	assert_eq(parsed["target_name"], "lamp", "target")
	assert_eq(parsed["input_name"], "TurnOn", "input")
	assert_eq(parsed["parameter"], "bright", "parameter")
	assert_eq(parsed["delay"], 1.5, "delay")
	assert_true(parsed["fire_once"], "fire once")


func test_an_ordinary_property_is_not_read_as_a_connection():
	assert_true(MapIOType.parse_connection("angle", "90").is_empty(), "One field is not wiring")
	assert_true(MapIOType.parse_connection("color", "1,0,0").is_empty(), "and nor are three")
	assert_true(
		MapIOType.parse_connection("x", "a,b,c,not_a_number,0").is_empty(),
		"The delay field has to be a number"
	)
	assert_true(
		MapIOType.parse_connection("x", ",Open,,0.0,0").is_empty(), "and a target has to be there"
	)


# -- Export and import --------------------------------------------------------


func test_a_brush_entity_writes_its_name_and_its_outputs():
	_wired_button()

	var text: String = MapIOType.export_map_from_level(root, QuakeAdapter.new())

	assert_string_contains(text, '"classname" "func_button"')
	assert_string_contains(text, '"targetname" "btn"')
	assert_string_contains(text, '"OnPressed" "door,Open,,0.0,0"')


func test_a_point_entity_writes_its_name_and_its_outputs():
	var entity = _point_entity("light_point")
	entity.set_meta("entity_name", "lamp")
	root.add_entity_output(entity, "OnLit", "btn", "Lock", "", 0.0, false)

	var text: String = MapIOType.export_map_from_level(root, QuakeAdapter.new())

	assert_string_contains(text, '"targetname" "lamp"')
	assert_string_contains(text, '"OnLit" "btn,Lock,,0.0,0"')


func test_two_outputs_on_the_same_event_both_reach_the_file():
	var brush := _box("b1")
	root.tie_brushes_to_entity(["b1"], "func_button")
	brush.set_meta("entity_name", "btn")
	root.add_entity_output(brush, "OnPressed", "door_a", "Open", "", 0.0, false)
	root.add_entity_output(brush, "OnPressed", "door_b", "Open", "", 0.0, false)

	var text: String = MapIOType.export_map_from_level(root, QuakeAdapter.new())

	assert_string_contains(text, '"OnPressed" "door_a,Open,,0.0,0"')
	assert_string_contains(text, '"OnPressed" "door_b,Open,,0.0,0"')


func test_an_unwired_entity_block_gains_nothing():
	_box("b1")
	root.tie_brushes_to_entity(["b1"], "func_detail")

	var text: String = MapIOType.export_map_from_level(root, QuakeAdapter.new())

	assert_false(text.contains("targetname"), "An entity with no name writes no targetname")


func test_a_wired_brush_entity_survives_an_export_and_import():
	_wired_button()
	var path := "user://hf_test_entity_io.map"
	assert_eq(root.export_map(path), OK, "Export should succeed")

	assert_eq(root.import_map(path), OK, "Import should succeed")

	var connections: Array = root.get_all_entity_connections()
	assert_eq(connections.size(), 1, "The connection should come back")
	assert_eq(connections[0]["source_name"], "btn", "under its authored name")
	assert_eq(connections[0]["target_name"], "door", "aimed where it was aimed")
	assert_eq(connections[0]["input_name"], "Open", "at the input it named")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_wired_point_entity_survives_an_export_and_import():
	var entity = _point_entity("light_point")
	entity.set_meta("entity_name", "lamp")
	root.add_entity_output(entity, "OnLit", "btn", "Lock", "", 2.0, true)
	var path := "user://hf_test_entity_io_point.map"
	root.export_map(path)

	root.import_map(path)

	var connections: Array = root.get_all_entity_connections()
	assert_eq(connections.size(), 1, "The connection should come back")
	assert_eq(connections[0]["source_name"], "lamp", "under its authored name")
	assert_eq(connections[0]["delay"], 2.0, "with its delay")
	assert_true(connections[0]["fire_once"], "and its fire once flag")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_an_imported_output_is_not_also_an_entity_property():
	var entity = _point_entity("light_point")
	entity.set_meta("entity_name", "lamp")
	root.add_entity_output(entity, "OnLit", "btn", "Lock", "", 0.0, false)
	var path := "user://hf_test_entity_io_props.map"
	root.export_map(path)

	root.import_map(path)

	for node in root.entities_node.get_children():
		assert_false(node.entity_data.has("OnLit"), "Wiring should not land in entity_data")
		assert_false(node.entity_data.has("targetname"), "and nor should the name")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
