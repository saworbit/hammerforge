extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_transform_entity, hf_set_entity_properties, hf_delete_entity (#1082) and
## hf_add_entity_output (#1083).
##
## An entity could only be taken back with hf_undo, and only while it was the
## agent's last step; after anything else a person had to fix it. And nothing on
## the bridge wired one entity to another, so a timer could not toggle a lamp.


func _entities(level: LevelRoot) -> Array:
	return level.entities_node.get_children()


func _place(params: Dictionary) -> String:
	var r := await call_tool("hf_place_entity", params)
	assert_true(r.get("ok", false), "fixture: placed: %s" % str(r))
	return str(r["result"]["entity"]["entity"]) if r.get("ok", false) else ""


func _lamp(name := "lamp_1") -> String:
	return await _place({"entity_class": "light_point", "position": [0, 3, 0], "name": name})


func _timer() -> String:
	return await _place({"entity_class": "logic_timer", "position": [0, 1, 0], "name": "tick"})


func _last_step() -> String:
	return undo.scene_history.get_current_action_name()


func test_an_entity_placed_steps_ago_is_moved_and_turned_in_one_step():
	var level := make_level()
	var path := await _lamp()
	await place_box()
	var before: int = undo.scene_history.get_history_count()
	var r := await call_tool(
		"hf_transform_entity",
		{"entity": path, "position": [4, 2, -1], "rotation_degrees": [-90, 0, 0]}
	)
	assert_true(r["ok"], str(r))
	assert_eq(undo.scene_history.get_history_count(), before + 1, "one step")
	assert_eq(_last_step(), "MCP: transform entity")
	var lamp: DraftEntity = level.get_node(path)
	assert_eq(lamp.global_position, Vector3(4, 2, -1))
	assert_almost_eq((-lamp.global_transform.basis.z).y, -1.0, 0.001, "aimed down")
	assert_eq(r["result"]["entity"]["position"], [4.0, 2.0, -1.0])
	r = await call_tool("hf_transform_entity", {"entity": path, "position": [1, 1, 1]})
	assert_almost_eq((-lamp.global_transform.basis.z).y, -1.0, 0.001, "a move keeps the aim")
	await call_tool("hf_undo")
	await call_tool("hf_undo")
	var back: DraftEntity = level.get_node(path)
	assert_eq(back.global_position, Vector3(0, 3, 0), "undo puts it back")


func test_properties_are_retuned_as_placing_checks_them():
	var level := make_level()
	var path := await _lamp()
	await place_box()
	var r := await call_tool(
		"hf_set_entity_properties",
		{"entity": path, "properties": {"energy": 4, "color": "#ff0000"}}
	)
	assert_true(r["ok"], str(r))
	assert_eq(_last_step(), "MCP: set entity properties")
	var lamp: DraftEntity = level.get_node(path)
	assert_almost_eq(float(lamp.entity_data["energy"]), 4.0, 0.0001)
	assert_eq(lamp.entity_data["color"], Color("#ff0000"))
	assert_almost_eq(float(lamp.entity_data["range"]), 10.0, 0.0001, "the rest keep theirs")
	assert_eq(r["result"]["entity"]["properties"]["color"], "#ff0000")
	var before := snapshot(level)
	assert_refused(
		await call_tool("hf_set_entity_properties", {"entity": path, "properties": {"glow": 1}}),
		"invalid_argument",
		"a property the class does not have"
	)
	assert_refused(
		await call_tool(
			"hf_set_entity_properties", {"entity": path, "properties": {"energy": "lots"}}
		),
		"invalid_argument",
		"a word for a number"
	)
	assert_refused(
		await call_tool("hf_set_entity_properties", {"entity": path, "preset": "Disco"}),
		"invalid_argument",
		"a preset it does not have"
	)
	assert_refused(
		await call_tool("hf_set_entity_properties", {"entity": path}),
		"invalid_argument",
		"nothing to set"
	)
	assert_eq_deep(snapshot(level), before)


func test_a_preset_is_applied_and_a_property_wins_over_it():
	var level := make_level()
	var path := await _lamp()
	var r := await call_tool(
		"hf_set_entity_properties",
		{"entity": path, "preset": "Warm Ceiling", "properties": {"energy": 7}}
	)
	assert_true(r["ok"], str(r))
	var lamp: DraftEntity = level.get_node(path)
	var preset: Dictionary = HFEntityPropUtils.preset_values(
		level.get_entity_definition("light_point"), "Warm Ceiling"
	)
	assert_eq(lamp.entity_data["color"], preset["color"], "the preset's colour")
	assert_almost_eq(float(lamp.entity_data["energy"]), 7.0, 0.0001, "the given energy")


func test_an_entity_is_deleted_with_the_wires_aimed_at_it_and_undo_brings_both_back():
	var level := make_level()
	var tick := await _timer()
	var lamp := await _lamp()
	await call_tool(
		"hf_add_entity_output",
		{"entity": tick, "output_name": "OnTimer", "target_name": "lamp_1", "input_name": "Toggle"}
	)
	var r := await call_tool("hf_delete_entity", {"entity": lamp})
	assert_true(r["ok"], str(r))
	assert_eq(_last_step(), "MCP: delete entity")
	assert_null(level.get_node_or_null(lamp), "gone")
	assert_eq(level.get_entity_outputs(level.get_node(tick)).size(), 0, "and the wire to it")
	await call_tool("hf_undo")
	assert_not_null(level.get_node_or_null(lamp), "back at the same path")
	assert_eq(level.get_entity_outputs(level.get_node(tick)).size(), 1, "with its wire")


func test_the_spawn_and_paths_that_are_not_entities_are_refused():
	var level := make_level()
	await call_tool("hf_set_spawn", {"position": [0, 0, 0]})
	var box_id := await place_box()
	var spawn_path := ""
	for entity in (await call_tool("hf_get_entities"))["result"]["entities"]:
		if entity["entity_class"] == "player_start":
			spawn_path = entity["entity"]
	assert_ne(spawn_path, "", "fixture: a spawn")
	var before := snapshot(level)
	for tool in ["hf_transform_entity", "hf_delete_entity"]:
		assert_refused(
			await call_tool(tool, {"entity": spawn_path, "position": [1, 0, 0]}),
			"invalid_argument",
			"%s on the spawn" % tool
		)
	var brush_path := str(level.get_path_to(brush_node(level, box_id)))
	for wrong in ["Entities/nope", "..", brush_path, ""]:
		assert_refused(
			await call_tool("hf_delete_entity", {"entity": wrong}),
			"entity_not_found",
			"'%s'" % wrong
		)
	assert_eq_deep(snapshot(level), before)


func test_a_batch_places_an_entity_and_moves_retunes_and_wires_it_by_reference():
	var level := make_level()
	var tick := await _timer()
	var before: int = undo.scene_history.get_history_count()
	var r := await call_tool(
		"hf_batch",
		{
			"ops":
			[
				{
					"tool": "hf_place_entity",
					"params":
					{"entity_class": "light_point", "position": [0, 3, 0], "name": "lamp_1"}
				},
				{
					"tool": "hf_transform_entity",
					"params": {"entity": "$0.entity", "position": [2, 3, 0]}
				},
				{
					"tool": "hf_set_entity_properties",
					"params": {"entity": "$1.entity", "properties": {"energy": 3}}
				},
				{
					"tool": "hf_add_entity_output",
					"params":
					{
						"entity": tick,
						"output_name": "OnTimer",
						"target_name": "lamp_1",
						"input_name": "Toggle"
					}
				},
			]
		}
	)
	assert_true(r["ok"], str(r))
	assert_eq(undo.scene_history.get_history_count(), before + 1, "one step")
	var lamp: DraftEntity = level.get_node(
		str(r["result"]["results"][0]["result"]["entity"]["entity"])
	)
	assert_eq(lamp.global_position, Vector3(2, 3, 0))
	assert_almost_eq(float(lamp.entity_data["energy"]), 3.0, 0.0001)
	assert_eq(level.get_entity_outputs(level.get_node(tick)).size(), 1)
	var bad := await call_tool(
		"hf_batch",
		{
			"ops":
			[
				{"tool": "hf_place_brush", "params": {"size": [1, 1, 1], "position": [0, 0, 0]}},
				{"tool": "hf_delete_entity", "params": {"entity": "$0.entity"}},
			]
		}
	)
	assert_refused(bad, "batch_failed", "op 0 made a brush, not an entity")


func test_a_timer_wired_to_a_lamp_toggles_it_in_the_game_scene():
	var level := make_level()
	await place_box([0, -0.5, 0], [8, 1, 8])
	var tick := await _timer()
	await _lamp()
	var r := await call_tool(
		"hf_add_entity_output",
		{
			"entity": tick,
			"output_name": "OnTimer",
			"target_name": "lamp_1",
			"input_name": "Toggle",
			"delay": 0.25,
		}
	)
	assert_true(r["ok"], str(r))
	assert_eq(_last_step(), "MCP: add entity output")
	assert_eq(
		r["result"]["entity"]["outputs"],
		[
			{
				"output_name": "OnTimer",
				"target_name": "lamp_1",
				"input_name": "Toggle",
				"parameter": "",
				"delay": 0.25,
				"fire_once": false,
			}
		],
		"the answer lists the wire as the tool takes it"
	)
	var listed := await call_tool("hf_get_entities")
	var outputs := {}
	for entity in listed["result"]["entities"]:
		outputs[entity["name"]] = entity["outputs"]
	assert_eq(outputs["tick"].size(), 1, "hf_get_entities lists it")
	assert_eq(outputs["lamp_1"], [], "and an entity with none has an empty list")
	assert_true(await level.bake(true, false), "fixture: the level bakes")
	var path := "user://hf_mcp_entity_wire_export.tscn"
	assert_true(level.export_game_scene(path))
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var scene: Node = packed.instantiate()
	add_child_autoqfree(scene)
	var io := scene.get_node_or_null("HFIODispatcher") as HFIORuntime
	var timer := scene.get_node_or_null("tick")
	assert_not_null(io, "a wired level gets a dispatcher")
	if io == null or not (timer is Timer):
		fail_test("no dispatcher, or the timer did not export as a Timer")
		return
	var fired: Array = []
	io.io_fired.connect(
		func(src, output, target, input, _param): fired.append([src, output, target, input])
	)
	(timer as Timer).timeout.emit()
	assert_eq(fired, [], "not before its delay")
	await get_tree().create_timer(0.5).timeout
	assert_eq(fired, [["tick", "OnTimer", "lamp_1", "Toggle"]], "the timer's tick is the wire")


func test_an_output_or_input_the_classes_do_not_declare_is_refused():
	var level := make_level()
	var tick := await _timer()
	await _lamp()
	var before := snapshot(level)
	var r := await call_tool(
		"hf_add_entity_output",
		{"entity": tick, "output_name": "OnFire", "target_name": "lamp_1", "input_name": "Toggle"}
	)
	assert_refused(r, "invalid_argument", "an output a timer does not have")
	if not r.get("ok", true):
		assert_string_contains(str(r["error"]["message"]), "OnTimer", "it names the real one")
	r = await call_tool(
		"hf_add_entity_output",
		{"entity": tick, "output_name": "OnTimer", "target_name": "lamp_1", "input_name": "Explode"}
	)
	assert_refused(r, "invalid_argument", "an input a light does not have")
	if not r.get("ok", true):
		assert_string_contains(str(r["error"]["message"]), "Toggle", "it names the real ones")
	r = await call_tool(
		"hf_add_entity_output",
		{
			"entity": tick,
			"output_name": "OnTimer",
			"target_name": "lamp_1",
			"input_name": "Toggle",
			"delay": -1,
		}
	)
	assert_refused(r, "invalid_argument", "a delay before the output fires")
	assert_eq_deep(snapshot(level), before)


func test_a_wire_to_a_name_nothing_answers_to_is_kept_and_validate_reports_it():
	make_level()
	var tick := await _timer()
	var r := await call_tool(
		"hf_add_entity_output",
		{"entity": tick, "output_name": "OnTimer", "target_name": "ghost", "input_name": "Toggle"}
	)
	assert_true(r["ok"], "a target may come later: %s" % str(r))
	var report := await call_tool("hf_validate")
	var messages: Array = []
	for issue in report["result"]["issues"]:
		messages.append(str(issue["message"]))
	assert_true(
		messages.any(func(m): return "'ghost'" in m),
		"Validate names the target nothing answers to: %s" % str(messages)
	)
