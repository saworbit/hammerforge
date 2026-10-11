extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_place_entity and hf_get_entities: an agent can light a level (#1051).
##
## The bridge placed brushes and the spawn and nothing else, so an agent could not
## finish the inside of anything it built: a keep lit only by the sun through one
## door read as dark brown on dark brown.


func _entities(level: LevelRoot) -> Array:
	return level.entities_node.get_children()


func test_a_light_is_placed_with_its_properties_in_one_step():
	var level := make_level()
	var before: int = undo.scene_history.get_history_count()
	var r := await call_tool(
		"hf_place_entity",
		{
			"entity_class": "light_point",
			"position": [2, 3, -1],
			"properties": {"energy": 2.5, "range": 8, "color": "#ffd6a0", "shadows": true},
		}
	)
	assert_true(r["ok"], str(r))
	assert_eq(undo.scene_history.get_history_count(), before + 1, "one step")
	assert_eq(_last_step(), "MCP: place entity")
	var placed: Array = _entities(level)
	assert_eq(placed.size(), 1)
	if placed.size() != 1:
		return
	var light: DraftEntity = placed[0]
	assert_eq(light.entity_class, "light_point")
	assert_eq(light.global_position, Vector3(2, 3, -1))
	assert_almost_eq(float(light.entity_data["energy"]), 2.5, 0.0001)
	assert_almost_eq(float(light.entity_data["range"]), 8.0, 0.0001)
	assert_eq(light.entity_data["color"], Color("#ffd6a0"), "a colour, as the picker stores it")
	assert_true(bool(light.entity_data["shadows"]))
	assert_eq(r["result"]["entity"]["entity_class"], "light_point")


func test_the_definition_s_defaults_fill_what_was_not_given():
	var level := make_level()
	await call_tool("hf_place_entity", {"entity_class": "light_spot", "position": [0, 4, 0]})
	var spot: DraftEntity = _entities(level)[0]
	assert_almost_eq(float(spot.entity_data["angle"]), 45.0, 0.0001, "the cone's default")
	assert_eq(spot.entity_data["color"], Color.WHITE)


func test_a_preset_is_applied_and_a_property_wins_over_it():
	var level := make_level()
	var r := await call_tool(
		"hf_place_entity",
		{
			"entity_class": "light_point",
			"position": [0, 3, 0],
			"preset": "Warm Ceiling",
			"properties": {"energy": 4},
		}
	)
	assert_true(r["ok"], str(r))
	var light: DraftEntity = _entities(level)[0]
	var preset: Dictionary = HFEntityPropUtils.preset_values(
		level.get_entity_definition("light_point"), "Warm Ceiling"
	)
	assert_eq(light.entity_data["color"], preset["color"], "the preset's colour")
	assert_almost_eq(float(light.entity_data["energy"]), 4.0, 0.0001, "the given energy")


func test_a_spot_is_aimed_by_its_rotation():
	var level := make_level()
	await call_tool(
		"hf_place_entity",
		{"entity_class": "light_spot", "position": [0, 4, 0], "rotation_degrees": [-90, 0, 0]}
	)
	var spot: DraftEntity = _entities(level)[0]
	var forward := -spot.global_transform.basis.z
	assert_almost_eq(forward.y, -1.0, 0.001, "pointing down")


func test_a_name_is_what_wiring_targets():
	var level := make_level()
	var r := await call_tool(
		"hf_place_entity",
		{"entity_class": "light_point", "position": [0, 3, 0], "name": "hall_lamp"}
	)
	var light: DraftEntity = _entities(level)[0]
	assert_eq(str(light.get_meta("entity_name", "")), "hall_lamp")
	assert_eq(r["result"]["entity"]["name"], "hall_lamp")


func test_classes_it_does_not_place_are_refused_and_name_the_ones_it_does():
	var level := make_level()
	var before := snapshot(level)
	for wrong in ["no_such_thing", "func_wall", "player_start"]:
		var r := await call_tool("hf_place_entity", {"entity_class": wrong, "position": [0, 0, 0]})
		assert_refused(r, "invalid_argument", wrong)
		if not r.get("ok", true):
			assert_string_contains(str(r["error"]["message"]), "light_point", wrong)
	assert_eq_deep(snapshot(level), before)


func test_a_property_the_class_does_not_have_is_refused():
	var level := make_level()
	var before := snapshot(level)
	var r := await call_tool(
		"hf_place_entity",
		{"entity_class": "light_point", "position": [0, 3, 0], "properties": {"brightness": 2}}
	)
	assert_refused(r, "invalid_argument")
	assert_string_contains(str(r["error"]["message"]), "energy", "it lists the real ones")
	r = await call_tool(
		"hf_place_entity",
		{"entity_class": "light_point", "position": [0, 3, 0], "properties": {"energy": "bright"}}
	)
	assert_refused(r, "invalid_argument", "a word for a number")
	r = await call_tool(
		"hf_place_entity", {"entity_class": "light_point", "position": [0, 3, 0], "preset": "Disco"}
	)
	assert_refused(r, "invalid_argument", "a preset the class does not have")
	assert_eq_deep(snapshot(level), before)


func test_entities_are_listed_with_what_was_set():
	make_level()
	await call_tool(
		"hf_place_entity",
		{
			"entity_class": "light_point",
			"position": [2, 3, -1],
			"name": "lamp_1",
			"properties": {"color": "#ff0000"},
		}
	)
	await call_tool("hf_set_spawn", {"position": [0, 0, 0]})
	var r := await call_tool("hf_get_entities")
	assert_true(r["ok"], str(r))
	var by_class := {}
	for entity in r["result"]["entities"]:
		by_class[entity["entity_class"]] = entity
	assert_true(by_class.has("player_start"), "the spawn is an entity too")
	assert_true(by_class.has("light_point"))
	if by_class.has("light_point"):
		var lamp: Dictionary = by_class["light_point"]
		assert_eq(lamp["name"], "lamp_1")
		assert_eq(lamp["position"], [2.0, 3.0, -1.0])
		assert_eq(lamp["properties"]["color"], "#ff0000", "a colour as the tool takes one")
		assert_ne(str(lamp["entity"]), "", "and where it is in the level")


func test_a_placed_light_is_a_real_light_in_the_game_scene():
	var level := make_level()
	await place_box([0, -0.5, 0], [8, 1, 8])
	await call_tool(
		"hf_place_entity",
		{"entity_class": "light_point", "position": [0, 3, 0], "properties": {"energy": 2.5}}
	)
	assert_true(await level.bake(true, false), "fixture: the level bakes")
	var path := "user://hf_mcp_entity_export.tscn"
	assert_true(level.export_game_scene(path))
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var scene: Node = packed.instantiate()
	var lights := scene.find_children("*", "OmniLight3D", true, false)
	assert_eq(lights.size(), 1, "the marker became an OmniLight3D")
	if lights.size() == 1:
		assert_almost_eq((lights[0] as OmniLight3D).light_energy, 2.5, 0.0001)
	scene.free()


func test_placing_needs_a_level():
	make_scene()
	assert_refused(
		await call_tool("hf_place_entity", {"entity_class": "light_point", "position": [0, 0, 0]}),
		"no_level"
	)


func _last_step() -> String:
	return undo.scene_history.get_current_action_name()
