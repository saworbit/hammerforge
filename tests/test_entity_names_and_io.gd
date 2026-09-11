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


# ===========================================================================
# A duplicate must not answer to the original's address (#341)
# ===========================================================================


func test_duplicating_a_named_entity_gives_the_copy_its_own_name():
	var door := _point_entity("func_door")
	door.set_meta("entity_name", "door_1")
	var info: Dictionary = root.build_duplicate_entity_info(door, Vector3(64, 0, 0))
	root.create_entities_from_infos([info])
	assert_eq(root.find_entities_by_name("door_1").size(), 1, "only the original answers to door_1")
	assert_eq(root.find_entities_by_name("door_2").size(), 1, "the copy took the next number")


func test_a_run_of_duplicates_keeps_taking_the_next_free_number():
	var door := _point_entity("func_door")
	door.set_meta("entity_name", "door_1")
	for _i in 3:
		root.create_entities_from_infos([root.build_duplicate_entity_info(door, Vector3(64, 0, 0))])
	for expected in ["door_1", "door_2", "door_3", "door_4"]:
		assert_eq(root.find_entities_by_name(expected).size(), 1, "%s is one entity" % expected)


func test_a_name_without_a_number_gets_one():
	var door := _point_entity("func_door")
	door.set_meta("entity_name", "door")
	root.create_entities_from_infos([root.build_duplicate_entity_info(door, Vector3.ZERO)])
	assert_eq(root.find_entities_by_name("door").size(), 1)
	assert_eq(root.find_entities_by_name("door_2").size(), 1)


func test_a_copy_keeps_firing_at_what_the_original_fired_at():
	var door := _point_entity("func_door")
	door.set_meta("entity_name", "door_1")
	var button := _point_entity("func_button")
	button.set_meta("entity_name", "button_1")
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	root.create_entities_from_infos([root.build_duplicate_entity_info(button, Vector3.ZERO)])
	var copies: Array = root.find_entities_by_name("button_2")
	assert_eq(copies.size(), 1, "the copy got its own address")
	var outputs: Array = root.get_entity_outputs(copies[0])
	assert_eq(outputs.size(), 1, "and kept its wiring")
	assert_eq(str(outputs[0]["target_name"]), "door_1", "still aimed at the same door")


func test_validate_reports_two_entities_on_one_authored_name():
	var a := _point_entity("func_door")
	a.set_meta("entity_name", "door_1")
	var b := _point_entity("func_door")
	b.set_meta("entity_name", "door_1")
	var report: Dictionary = root.validate_level(false)
	var found := false
	for issue in report.get("issues", []):
		if str(issue).findn("door_1") >= 0:
			found = true
	assert_true(found, "a shared address is a level defect")


# ===========================================================================
# An output has to be wiring (#342)
# ===========================================================================


func test_an_output_with_a_missing_field_is_refused():
	var button := _point_entity("func_button")
	root.add_entity_output(button, "", "door_1", "Open")
	root.add_entity_output(button, "OnPressed", "", "Open")
	root.add_entity_output(button, "OnPressed", "door_1", "")
	root.add_entity_output(button, "OnPressed", "   ", "Open")
	assert_eq(root.get_entity_outputs(button).size(), 0, "none of those is a connection")


func test_an_output_with_a_delay_that_is_not_one_is_refused():
	var button := _point_entity("func_button")
	for delay in [NAN, INF, -INF, -5.0]:
		root.add_entity_output(button, "OnPressed", "door_1", "Open", "", delay)
	assert_eq(root.get_entity_outputs(button).size(), 0)
	root.add_entity_output(button, "OnPressed", "door_1", "Open", "", 0.5)
	assert_eq(root.get_entity_outputs(button).size(), 1, "a real delay still goes through")


func test_wiring_that_survives_export_survives_the_import_back():
	var button := _point_entity("func_button")
	button.set_meta("entity_name", "button_1")
	root.add_entity_output(button, "OnPressed", "door_1", "Open", "", 0.25)
	_box("solid")
	var text: String = MapIOType.export_map_from_level(root, QuakeAdapter.new())
	var parsed: Dictionary = MapIOType.parse_map_text(text)
	var total := 0
	for entity in parsed.get("entities", []):
		total += (entity.get("entity_io_outputs", []) as Array).size()
	assert_eq(total, 1, "the round trip keeps the connection the editor showed")
	assert_eq(parsed.get("errors", []).size(), 0, "and drops nothing on the way")


func test_the_importer_says_when_it_drops_a_connection():
	var text := (
		'{\n"classname" "func_button"\n"origin" "0 0 0"\n"targetname" "button_1"\n'
		+ '"OnPressed" "door_1,Open,,0.0,0"\n"OnPressed" "door_1,,,0.0,0"\n}\n'
	)
	var parsed: Dictionary = MapIOType.parse_map_text(text)
	var errors: Array = parsed.get("errors", [])
	var mentioned := false
	for err in errors:
		if str(err).findn("dropped") >= 0:
			mentioned = true
	assert_true(mentioned, "a line that looks like wiring and is not must be reported")
