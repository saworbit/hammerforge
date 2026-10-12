extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_set_brush_entity, and brushes as the source of a wire (#1098).
##
## An agent could wire one point entity to another, but could not make a
## trigger, a door or a button, so the wiring most levels need first (walk into
## a room and the lights come on) could not be built over the bridge.
##
## Then untie, several brushes tied as one, and a brush entity's own properties
## (#1105). A brush made a trigger by mistake stayed one, a two leaf door made
## from two calls exported as two doors, and a door's speed could not be set.

const MapIO = preload("res://addons/hammerforge/map_io.gd")
const QuakeAdapter = preload("res://addons/hammerforge/map_adapters/hf_map_quake.gd")


func _last_step() -> String:
	return undo.scene_history.get_current_action_name()


func _lamp() -> String:
	var r := await call_tool(
		"hf_place_entity", {"entity_class": "light_point", "position": [0, 3, 0], "name": "lamp_1"}
	)
	assert_true(r.get("ok", false), "fixture: lamp: %s" % str(r))
	return str(r["result"]["entity"]["entity"]) if r.get("ok", false) else ""


func _tie(brush_ids: Array, entity_class: String, entity_name := "") -> Dictionary:
	var params := {"brush_ids": brush_ids, "entity_class": entity_class}
	if entity_name != "":
		params["name"] = entity_name
	return await call_tool("hf_set_brush_entity", params)


func _make(brush_id: String, entity_class: String, entity_name := "") -> Dictionary:
	return await _tie([brush_id], entity_class, entity_name)


func _wire_from(brush_id: String) -> Dictionary:
	return await call_tool(
		"hf_add_entity_output",
		{
			"brush_id": brush_id,
			"output_name": "OnStartTouch",
			"target_name": "lamp_1",
			"input_name": "TurnOn",
		}
	)


func _listed(brush_id: String) -> Dictionary:
	var r := await call_tool("hf_get_brushes", {"brush_ids": [brush_id], "include_faces": false})
	assert_true(r.get("ok", false), str(r))
	return r["result"]["brushes"][0] if r.get("ok", false) else {}


## Two door leaves side by side, as a two leaf door is drawn.
func _leaves() -> Array:
	return [await place_box([-1, 1, 0], [2, 2, 1]), await place_box([1, 1, 0], [2, 2, 1])]


func _doors_in_map(level: LevelRoot) -> int:
	var text: String = MapIO.export_map_from_level(level, QuakeAdapter.new())
	return text.count('"classname" "func_door"')


func _group(level: LevelRoot, brush_id: String) -> String:
	return str(brush_node(level, brush_id).get_meta("brush_entity_group", ""))


func _set_props(params: Dictionary) -> Dictionary:
	return await call_tool("hf_set_entity_properties", params)


func test_a_box_made_a_trigger_and_wired_to_a_lamp_turns_it_on_in_the_game_scene():
	var level := make_level()
	await place_box([0, -0.5, 0], [8, 1, 8])
	var hall := await place_box([0, 1, 0], [2, 2, 2])
	await _lamp()
	var r := await _make(hall, "trigger_once", "hall_trigger")
	assert_true(r["ok"], str(r))
	assert_eq(_last_step(), "MCP: set brush entity")
	var brush := brush_node(level, hall)
	assert_eq(str(brush.get_meta("brush_entity_class", "")), "trigger_once")
	assert_eq(str(brush.get_meta("entity_name", "")), "hall_trigger")
	assert_eq(
		r["result"]["brushes"][0]["brush_entity"],
		{
			"entity_class": "trigger_once",
			"name": "hall_trigger",
			"properties": {"target": ""},
			"outputs": []
		},
		"the answer says what it is now"
	)
	r = await _wire_from(hall)
	assert_true(r["ok"], str(r))
	assert_eq(_last_step(), "MCP: add entity output")
	var wire := {
		"output_name": "OnStartTouch",
		"target_name": "lamp_1",
		"input_name": "TurnOn",
		"parameter": "",
		"delay": 0.0,
		"fire_once": false,
	}
	assert_eq(r["result"]["brush"]["brush_entity"]["outputs"], [wire])
	assert_eq(
		(await _listed(hall))["brush_entity"],
		{
			"entity_class": "trigger_once",
			"name": "hall_trigger",
			"properties": {"target": ""},
			"outputs": [wire]
		},
		"hf_get_brushes lists its class, name, properties and wiring"
	)
	assert_true(await level.bake(true, false), "fixture: the level bakes")
	var path := "user://hf_mcp_brush_entity_export.tscn"
	assert_true(level.export_game_scene(path))
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var scene: Node = packed.instantiate()
	add_child_autoqfree(scene)
	var io := scene.get_node_or_null("HFIODispatcher") as HFIORuntime
	var volume := scene.find_child("hall_trigger", true, false) as Area3D
	assert_not_null(io, "a wired level gets a dispatcher")
	if io == null or volume == null:
		fail_test("no dispatcher, or no hall_trigger volume in the game scene")
		return
	var fired: Array = []
	io.io_fired.connect(
		func(src, output, target, input, _param): fired.append([src, output, target, input])
	)
	volume.body_entered.emit(autofree(CharacterBody3D.new()))
	assert_eq(fired, [["hall_trigger", "OnStartTouch", "lamp_1", "TurnOn"]], "walking in")


func test_a_class_that_is_not_a_brush_class_is_refused_with_the_ones_that_are():
	var level := make_level()
	var box := await place_box()
	var before := snapshot(level)
	for wrong in ["light_point", "player_start", "trigger_sometimes", ""]:
		var r := await _make(box, wrong)
		assert_refused(r, "invalid_argument", "'%s'" % wrong)
		if wrong != "" and not r.get("ok", true):
			var message := str(r["error"]["message"])
			for offered in ["trigger_once", "func_door", "func_button", "func_wall", "none"]:
				assert_string_contains(message, offered, "it names %s" % offered)
	assert_refused(await _make("nope", "trigger_once"), "brush_not_found", "no such brush")
	assert_eq_deep(snapshot(level), before)


func test_a_cut_is_not_made_an_entity():
	var level := make_level()
	var r := await call_tool(
		"hf_place_brush", {"size": [1, 2, 1], "position": [0, 1, 0], "operation": "subtract"}
	)
	assert_true(r["ok"], str(r))
	var before := snapshot(level)
	assert_refused(
		await _make(str(r["result"]["brush"]["brush_id"]), "func_door"), "invalid_argument"
	)
	assert_eq_deep(snapshot(level), before)


func test_a_new_class_keeps_the_name_and_undo_makes_it_plain_again():
	var level := make_level()
	var box := await place_box()
	await _make(box, "trigger_once", "hall_trigger")
	var r := await _make(box, "trigger_multiple")
	assert_true(r["ok"], str(r))
	var brush := brush_node(level, box)
	assert_eq(str(brush.get_meta("entity_name", "")), "hall_trigger", "wires to it still land")
	assert_eq(str(brush.get_meta("brush_entity_class", "")), "trigger_multiple")
	await call_tool("hf_undo")
	await call_tool("hf_undo")
	brush = brush_node(level, box)
	assert_eq(str(brush.get_meta("brush_entity_class", "")), "", "a plain brush again")
	assert_null((await _listed(box))["brush_entity"], "and listed as one")


func test_a_wire_source_is_an_entity_or_a_brush_entity_and_never_both():
	var level := make_level()
	var plain := await place_box()
	var path := await _lamp()
	var before := snapshot(level)
	var r := await _wire_from(plain)
	assert_refused(r, "invalid_argument", "a brush that is no entity")
	if not r.get("ok", true):
		assert_string_contains(str(r["error"]["message"]), "hf_set_brush_entity")
	assert_refused(
		await call_tool(
			"hf_add_entity_output",
			{
				"entity": path,
				"brush_id": plain,
				"output_name": "OnStartTouch",
				"target_name": "lamp_1",
				"input_name": "TurnOn",
			}
		),
		"invalid_argument",
		"both"
	)
	assert_refused(
		await call_tool(
			"hf_add_entity_output",
			{"output_name": "OnStartTouch", "target_name": "lamp_1", "input_name": "TurnOn"}
		),
		"invalid_argument",
		"neither"
	)
	await _make(plain, "func_button", "button_1")
	before = snapshot(level)
	r = await _wire_from(plain)
	assert_refused(r, "invalid_argument", "an output a button does not have")
	if not r.get("ok", true):
		assert_string_contains(str(r["error"]["message"]), "OnPressed", "it names the real one")
	assert_eq_deep(snapshot(level), before)


func test_a_brush_entity_s_wire_is_removed_by_its_index():
	var level := make_level()
	var hall := await place_box()
	await _lamp()
	await _make(hall, "trigger_multiple", "hall_trigger")
	await _wire_from(hall)
	var r := await call_tool("hf_remove_entity_output", {"brush_id": hall, "index": 0})
	assert_true(r["ok"], str(r))
	assert_eq(_last_step(), "MCP: remove entity output")
	assert_eq(level.get_entity_outputs(brush_node(level, hall)), [])
	assert_eq(r["result"]["brush"]["brush_entity"]["outputs"], [])


func test_a_batch_places_a_box_makes_it_a_trigger_and_wires_it_by_reference():
	var level := make_level()
	await _lamp()
	var before: int = undo.scene_history.get_history_count()
	var r := await call_tool(
		"hf_batch",
		{
			"ops":
			[
				{"tool": "hf_place_brush", "params": {"size": [2, 2, 2], "position": [0, 1, 0]}},
				{
					"tool": "hf_set_brush_entity",
					"params":
					{"brush_ids": ["$0.brush_id"], "entity_class": "trigger_once", "name": "hall"}
				},
				{
					"tool": "hf_add_entity_output",
					"params":
					{
						"brush_id": "$0.brush_id",
						"output_name": "OnStartTouch",
						"target_name": "lamp_1",
						"input_name": "TurnOn"
					}
				},
			]
		}
	)
	assert_true(r["ok"], str(r))
	assert_eq(undo.scene_history.get_history_count(), before + 1, "one step")
	var hall := str(r["result"]["results"][0]["result"]["brush"]["brush_id"])
	var brush := brush_node(level, hall)
	assert_eq(str(brush.get_meta("brush_entity_class", "")), "trigger_once")
	assert_eq(level.get_entity_outputs(brush).size(), 1)


func test_a_plain_brush_lists_no_entity():
	make_level()
	var box := await place_box()
	assert_true((await _listed(box)).has("brush_entity"), "the key is always there")
	assert_null((await _listed(box))["brush_entity"])


# -- Untie (#1105) -------------------------------------------------------------


func test_a_brush_tied_steps_ago_is_untied_and_listed_as_plain():
	var level := make_level()
	var hall := await place_box()
	await _make(hall, "trigger_once", "hall_trigger")
	var group := _group(level, hall)
	# Something else in between, so hf_undo can no longer take the tie back.
	await place_box([6, 1, 0])
	await _lamp()
	var before: int = undo.scene_history.get_history_count()
	var r := await _make(hall, "none")
	assert_true(r["ok"], str(r))
	assert_eq(undo.scene_history.get_history_count(), before + 1, "one step")
	assert_eq(_last_step(), "MCP: set brush entity")
	assert_null(r["result"]["brushes"][0]["brush_entity"], "the answer says it is plain")
	assert_null((await _listed(hall))["brush_entity"], "hf_get_brushes lists it as plain")
	var brush := brush_node(level, hall)
	assert_eq(str(brush.get_meta("brush_entity_class", "")), "")
	assert_false(brush.has_meta("entity_name"), "nothing answers to its name now")
	assert_false(brush.has_meta("brush_entity_group"))
	assert_eq(level.find_entities_by_name("hall_trigger"), [])
	r = await call_tool("hf_undo")
	assert_true(r["ok"], str(r))
	brush = brush_node(level, hall)
	assert_eq(str(brush.get_meta("brush_entity_class", "")), "trigger_once", "undo ties it again")
	assert_eq(str(brush.get_meta("entity_name", "")), "hall_trigger", "with its name")
	assert_eq(_group(level, hall), group, "and its identity")


func test_several_brushes_are_untied_in_one_step():
	var level := make_level()
	var leaves := await _leaves()
	await _tie(leaves, "func_door", "gate")
	var r := await _tie(leaves, "none")
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["brushes"].size(), 2, "the answer lists both")
	for leaf in leaves:
		assert_eq(str(brush_node(level, leaf).get_meta("brush_entity_class", "")), "")
	await call_tool("hf_undo")
	for leaf in leaves:
		assert_eq(str(brush_node(level, leaf).get_meta("brush_entity_class", "")), "func_door")
		assert_eq(str(brush_node(level, leaf).get_meta("entity_name", "")), "gate")


func test_untying_a_plain_brush_or_with_a_name_is_refused():
	var level := make_level()
	var plain := await place_box()
	var door := await place_box([4, 1, 0])
	await _make(door, "func_door", "gate")
	var before := snapshot(level)
	var r := await _make(plain, "none")
	assert_refused(r, "invalid_argument", "a plain brush")
	if not r.get("ok", true):
		assert_string_contains(str(r["error"]["message"]), plain, "it names the brush")
		assert_string_contains(str(r["error"]["message"]), "not an entity")
	assert_refused(await _tie([door, plain], "none"), "invalid_argument", "one of them plain")
	assert_refused(await _make(door, "none", "gate"), "invalid_argument", "none and a name")
	assert_eq_deep(snapshot(level), before)
	assert_eq(str(brush_node(level, door).get_meta("brush_entity_class", "")), "func_door")


# -- Several brushes as one (#1105) --------------------------------------------


func test_two_brushes_tied_in_one_call_are_one_door_in_the_map():
	var level := make_level()
	var leaves := await _leaves()
	var before: int = undo.scene_history.get_history_count()
	var r := await _tie(leaves, "func_door")
	assert_true(r["ok"], str(r))
	assert_eq(undo.scene_history.get_history_count(), before + 1, "one step")
	assert_eq(r["result"]["brushes"].size(), 2, "the answer lists both")
	var group := _group(level, leaves[0])
	assert_ne(group, "", "the tie gave them an identity")
	assert_eq(_group(level, leaves[1]), group, "one identity for both")
	assert_eq(_doors_in_map(level), 1, "one func_door in the .map")
	await call_tool("hf_undo")
	for leaf in leaves:
		assert_eq(str(brush_node(level, leaf).get_meta("brush_entity_class", "")), "")
		assert_eq(_group(level, leaf), "", "undo takes the identity too")
	# Two calls are two ties, and two doors, as the dock's two ties are.
	await _make(leaves[0], "func_door")
	await _make(leaves[1], "func_door")
	assert_eq(_doors_in_map(level), 2)


func test_a_tie_over_an_entity_and_a_plain_brush_is_undone_brush_by_brush():
	var level := make_level()
	var leaves := await _leaves()
	await _make(leaves[0], "trigger_once", "hall")
	var first_group := _group(level, leaves[0])
	var r := await _tie(leaves, "func_door")
	assert_true(r["ok"], str(r))
	for leaf in leaves:
		var brush := brush_node(level, leaf)
		assert_eq(str(brush.get_meta("brush_entity_class", "")), "func_door")
		assert_eq(str(brush.get_meta("entity_name", "")), "hall", "both take the one name")
	assert_eq(_group(level, leaves[0]), _group(level, leaves[1]))
	await call_tool("hf_undo")
	var first := brush_node(level, leaves[0])
	assert_eq(str(first.get_meta("brush_entity_class", "")), "trigger_once", "back as it was")
	assert_eq(str(first.get_meta("entity_name", "")), "hall")
	assert_eq(_group(level, leaves[0]), first_group)
	var second := brush_node(level, leaves[1])
	assert_eq(str(second.get_meta("brush_entity_class", "")), "", "and the other plain")
	assert_false(second.has_meta("entity_name"))


func test_a_tie_of_brushes_that_answer_to_different_names_needs_a_name():
	var level := make_level()
	var leaves := await _leaves()
	await _make(leaves[0], "func_door", "west")
	await _make(leaves[1], "func_door", "east")
	var before := snapshot(level)
	var r := await _tie(leaves, "func_door")
	assert_refused(r, "invalid_argument", "two names and none given")
	if not r.get("ok", true):
		assert_eq(r["error"]["details"]["param"], "name")
		assert_string_contains(str(r["error"]["message"]), "west")
		assert_string_contains(str(r["error"]["message"]), "east")
	assert_eq_deep(snapshot(level), before)
	r = await _tie(leaves, "func_door", "gate")
	assert_true(r["ok"], str(r))
	assert_eq(level.find_entities_by_name("gate").size(), 2)


func test_a_list_that_is_empty_repeats_or_names_a_missing_brush_or_a_cut_is_refused():
	var level := make_level()
	var box := await place_box()
	var cut := await call_tool(
		"hf_place_brush", {"size": [1, 2, 1], "position": [4, 1, 0], "operation": "subtract"}
	)
	assert_true(cut["ok"], str(cut))
	var cut_id := str(cut["result"]["brush"]["brush_id"])
	var before := snapshot(level)
	assert_refused(await _tie([], "func_door"), "invalid_argument", "an empty list")
	assert_refused(await _tie([box, box], "func_door"), "invalid_argument", "a repeat")
	assert_refused(await _tie([box, "nope"], "func_door"), "brush_not_found", "a missing brush")
	assert_refused(await _tie([box, ""], "func_door"), "invalid_argument", "an empty id")
	assert_refused(await _tie([box, cut_id], "func_door"), "invalid_argument", "a cut")
	assert_refused(
		await call_tool("hf_set_brush_entity", {"brush_ids": box, "entity_class": "func_door"}),
		"invalid_argument",
		"one id, not a list"
	)
	assert_refused(
		await call_tool("hf_set_brush_entity", {"brush_id": box, "entity_class": "func_door"}),
		"invalid_argument",
		"the old brush_id"
	)
	var r := await _tie([box, box], "func_door")
	if not r.get("ok", true):
		assert_string_contains(str(r["error"]["message"]), box, "it names the repeat")
	assert_eq_deep(snapshot(level), before)


func test_a_batch_places_two_leaves_and_ties_them_as_one_door_by_reference():
	var level := make_level()
	var r := await call_tool(
		"hf_batch",
		{
			"ops":
			[
				{"tool": "hf_place_brush", "params": {"size": [2, 2, 1], "position": [-1, 1, 0]}},
				{"tool": "hf_place_brush", "params": {"size": [2, 2, 1], "position": [1, 1, 0]}},
				{
					"tool": "hf_set_brush_entity",
					"params":
					{
						"brush_ids": ["$0.brush_id", "$1.brush_id"],
						"entity_class": "func_door",
						"name": "gate"
					}
				},
				{
					"tool": "hf_set_entity_properties",
					"params": {"brush_id": "$1.brush_id", "properties": {"speed": 5}}
				},
			]
		}
	)
	assert_true(r["ok"], str(r))
	var leaf := str(r["result"]["results"][0]["result"]["brush"]["brush_id"])
	assert_eq(_doors_in_map(level), 1)
	var data: Dictionary = brush_node(level, leaf).get_meta("brush_entity_data", {})
	assert_almost_eq(float(data.get("speed", 0.0)), 5.0, 0.0001, "the other leaf has it too")


# -- A brush entity's properties (#1105) ---------------------------------------


func test_a_trigger_s_properties_are_set_by_its_brush_id_and_checked_by_its_class():
	var level := make_level()
	var hall := await place_box()
	await _make(hall, "trigger_once", "hall_trigger")
	await place_box([6, 1, 0])
	var r := await _set_props({"brush_id": hall, "properties": {"target": "lamp_1"}})
	assert_true(r["ok"], str(r))
	assert_eq(_last_step(), "MCP: set entity properties")
	var brush := brush_node(level, hall)
	assert_eq(brush.get_meta("brush_entity_data", {}), {"target": "lamp_1"}, "where the bake reads")
	assert_eq(r["result"]["brush"]["brush_entity"]["properties"], {"target": "lamp_1"})
	assert_eq((await _listed(hall))["brush_entity"]["properties"], {"target": "lamp_1"})
	var before := snapshot(level)
	# The shipped trigger_once declares target and nothing else.
	r = await _set_props({"brush_id": hall, "properties": {"start_disabled": true}})
	assert_refused(r, "invalid_argument", "a property the class does not declare")
	if not r.get("ok", true):
		assert_string_contains(str(r["error"]["message"]), "start_disabled", "it names it")
		assert_string_contains(str(r["error"]["message"]), "target", "and the ones it has")
	assert_refused(
		await _set_props({"brush_id": hall, "properties": {"target": 3}}),
		"invalid_argument",
		"a number for a name"
	)
	assert_refused(await _set_props({"brush_id": hall}), "invalid_argument", "nothing to set")
	assert_eq_deep(snapshot(level), before)
	await call_tool("hf_undo")
	assert_false(
		brush_node(level, hall).has_meta("brush_entity_data"), "undo takes the property back"
	)


func test_start_disabled_is_set_where_the_level_s_definitions_declare_it():
	# The built in definitions, a level with no entities.json, give trigger_once a
	# start_disabled and a filter_class; the check follows what the level loads.
	var level := LevelRoot.new()
	level.entity_definitions_path = ""
	make_scene(level)
	var hall := await place_box()
	await _make(hall, "trigger_once", "hall_trigger")
	var r := await _set_props(
		{"brush_id": hall, "properties": {"start_disabled": true, "filter_class": "player"}}
	)
	assert_true(r["ok"], str(r))
	var data: Dictionary = brush_node(level, hall).get_meta("brush_entity_data", {})
	assert_eq(data, {"start_disabled": true, "filter_class": "player"})
	assert_refused(
		await _set_props({"brush_id": hall, "properties": {"start_disabled": "yes"}}),
		"invalid_argument",
		"a word for a bool"
	)
	assert_refused(
		await _set_props({"brush_id": hall, "properties": {"target": "x"}}),
		"invalid_argument",
		"a property these definitions do not declare"
	)


func test_a_two_leaf_door_s_speed_is_set_on_both_leaves_and_undone_on_both():
	var level := make_level()
	var leaves := await _leaves()
	await _tie(leaves, "func_door", "gate")
	var r := await _set_props({"brush_id": leaves[1], "properties": {"speed": 5, "locked": true}})
	assert_true(r["ok"], str(r))
	for leaf in leaves:
		var data: Dictionary = brush_node(level, leaf).get_meta("brush_entity_data", {})
		assert_almost_eq(float(data.get("speed", 0.0)), 5.0, 0.0001, "one door, one speed")
		assert_eq(data.get("locked"), true)
	var properties: Dictionary = r["result"]["brush"]["brush_entity"]["properties"]
	assert_almost_eq(float(properties["speed"]), 5.0, 0.0001)
	assert_almost_eq(float(properties["wait"]), 3.0, 0.0001, "the class default for the rest")
	var text: String = MapIO.export_map_from_level(level, QuakeAdapter.new())
	assert_eq(text.count('"classname" "func_door"'), 1)
	assert_eq(text.count('"speed" "5'), 1, "the one door block carries the speed")
	await call_tool("hf_undo")
	for leaf in leaves:
		assert_false(brush_node(level, leaf).has_meta("brush_entity_data"), "undo takes both back")


func test_a_brush_that_is_not_an_entity_or_both_sources_are_refused_for_properties():
	var level := make_level()
	var plain := await place_box()
	var path := await _lamp()
	var before := snapshot(level)
	var r := await _set_props({"brush_id": plain, "properties": {"target": "x"}})
	assert_refused(r, "invalid_argument", "a plain brush")
	if not r.get("ok", true):
		assert_string_contains(str(r["error"]["message"]), "hf_set_brush_entity")
	assert_refused(
		await _set_props({"entity": path, "brush_id": plain, "properties": {"energy": 2}}),
		"invalid_argument",
		"both"
	)
	assert_refused(await _set_props({"properties": {"energy": 2}}), "invalid_argument", "neither")
	assert_refused(
		await _set_props({"brush_id": "nope", "properties": {"target": "x"}}),
		"brush_not_found",
		"no such brush"
	)
	assert_eq_deep(snapshot(level), before)
