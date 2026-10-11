extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_set_brush_entity, and brushes as the source of a wire (#1098).
##
## An agent could wire one point entity to another, but could not make a
## trigger, a door or a button, so the wiring most levels need first (walk into
## a room and the lights come on) could not be built over the bridge.


func _last_step() -> String:
	return undo.scene_history.get_current_action_name()


func _lamp() -> String:
	var r := await call_tool(
		"hf_place_entity", {"entity_class": "light_point", "position": [0, 3, 0], "name": "lamp_1"}
	)
	assert_true(r.get("ok", false), "fixture: lamp: %s" % str(r))
	return str(r["result"]["entity"]["entity"]) if r.get("ok", false) else ""


func _make(brush_id: String, entity_class: String, entity_name := "") -> Dictionary:
	var params := {"brush_id": brush_id, "entity_class": entity_class}
	if entity_name != "":
		params["name"] = entity_name
	return await call_tool("hf_set_brush_entity", params)


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
		r["result"]["brush"]["brush_entity"],
		{"entity_class": "trigger_once", "name": "hall_trigger", "outputs": []},
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
		{"entity_class": "trigger_once", "name": "hall_trigger", "outputs": [wire]},
		"hf_get_brushes lists its class, name and wiring"
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
			for offered in ["trigger_once", "func_door", "func_button", "func_wall"]:
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
					{"brush_id": "$0.brush_id", "entity_class": "trigger_once", "name": "hall"}
				},
				{
					"tool": "hf_add_entity_output",
					"params":
					{
						"brush_id": "$1.brush_id",
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
