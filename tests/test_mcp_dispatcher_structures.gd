extends "res://tests/mcp/mcp_dispatcher_case.gd"

## update_structure and detach_structure through hf_run_command, the structure an
## agent reads on every brush, and `$N.generator_id` in a batch (#1302).

const HFGeneratorSystem = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFGeneratorSchema = preload("res://addons/hammerforge/hf_generator_schema.gd")
const HFMcpCommands = preload("res://addons/hammerforge/mcp/hf_mcp_commands.gd")


func run(command: String, args = null, brush_ids = null) -> Dictionary:
	var params := {"command": command}
	if brush_ids != null:
		params["brush_ids"] = brush_ids
	if args != null:
		params["params"] = args
	return await call_tool("hf_run_command", params)


## A flight of stairs built through the bridge. Gives back its answer.
func build_stairs(settings := {"steps": 4, "width": 3.0, "fill": "open"}) -> Dictionary:
	var r := await run(
		"create_arch", {"type": "stairs", "position": [0, 0, 0], "settings": settings}
	)
	assert_true(r.get("ok", false), "built: %s" % str(r))
	return r.get("result", {})


func top_step() -> String:
	return undo.scene_history.get_current_action_name()


func pieces(level: LevelRoot, generator_id: String) -> Array:
	var out: Array = []
	var record = level.generator_for_id(generator_id)
	for brush_id in record.brush_ids if record else []:
		out.append(brush_node(level, str(brush_id)))
	return out


## The structure hf_get_brushes gives a brush.
func listed_structure(brush_id: String):
	var r := await call_tool("hf_get_brushes", {"brush_ids": [brush_id], "include_faces": false})
	assert_true(r.get("ok", false), str(r))
	return r["result"]["brushes"][0]["structure"]


func assert_checked_refusal(response: Dictionary, code: String, before: Dictionary, note: String):
	assert_refused(response, code, note)
	if response.get("ok", true):
		return
	assert_false(response["error"]["details"].has("rolled_back"), "%s: refused in the check" % note)
	assert_eq(snapshot(host.level_root_in(host.scene)), before, "%s: nothing changed" % note)


# ===========================================================================
# Update
# ===========================================================================


func test_an_update_changes_only_the_settings_it_is_given():
	var level := make_level()
	var built := await build_stairs()
	var generator_id: String = built["generator_id"]
	var r := await run("update_structure", {"generator_id": generator_id, "settings": {"steps": 6}})
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: update structure")
	var settings: Dictionary = r["result"]["settings"]
	assert_eq(settings["steps"], 6, "the setting it was given")
	assert_almost_eq(float(settings["width"]), 3.0, 0.0001, "the width it was built with")
	assert_eq(settings["fill"], 1, "and the fill it was built with, not the default")
	assert_eq(level.generator_for_id(generator_id).settings, settings, "the record agrees")
	assert_eq(r["result"]["generator_id"], generator_id, "the same structure")
	assert_eq(r["result"]["made"].size(), 6, "one brush per step")
	assert_eq(r["result"]["removed"].size(), 4, "the old pieces are gone")
	for brush in r["result"]["made"]:
		assert_eq(brush["structure"]["generator_id"], generator_id, "each new piece says whose")
	await call_tool("hf_undo")
	assert_eq(level.generator_for_id(generator_id).settings["steps"], 4, "undo puts it back")
	assert_eq(pieces(level, generator_id).size(), 4)


func test_two_updates_in_a_row_name_the_same_structure():
	var level := make_level()
	var generator_id: String = (await build_stairs())["generator_id"]
	var first := await run(
		"update_structure", {"generator_id": generator_id, "settings": {"rise": 0.25}}
	)
	assert_true(first.get("ok", false), str(first))
	var second := await run(
		"update_structure", {"generator_id": generator_id, "settings": {"tread": 0.4}}
	)
	assert_true(second.get("ok", false), "the id outlives the pieces: %s" % str(second))
	var settings: Dictionary = level.generator_for_id(generator_id).settings
	assert_almost_eq(float(settings["rise"]), 0.25, 0.0001, "the first change stays")
	assert_almost_eq(float(settings["tread"]), 0.4, 0.0001, "beside the second")


func test_an_update_with_no_settings_rebuilds_what_was_edited():
	var level := make_level()
	var generator_id: String = (await build_stairs())["generator_id"]
	var moved: DraftBrush = pieces(level, generator_id)[1]
	var moved_id := moved.brush_id
	var built_at := moved.global_position
	moved.global_position += Vector3(0, 0, 5)
	var r := await run("update_structure", {"generator_id": generator_id})
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["edits_replaced"], [moved_id], "the piece moved by hand is named")
	assert_eq(r["result"]["warnings"].size(), 1, str(r["result"]["warnings"]))
	assert_string_contains(r["result"]["warnings"][0], "by hand")
	var back: DraftBrush = pieces(level, generator_id)[1]
	assert_almost_eq(back.global_position, built_at, Vector3.ONE * 0.001, "back in the row")


func test_an_update_keeps_paint_and_names_where_the_pieces_line_up():
	var level := make_level_with_palette()
	var generator_id: String = (await build_stairs())["generator_id"]
	var first: DraftBrush = pieces(level, generator_id)[0]
	first.name = "bottom_step"
	level.assign_material_to_faces_by_id(first.brush_id, [0], 1)
	assert_eq(first.faces[0].material_idx, 1, "painted")
	var r := await run(
		"update_structure", {"generator_id": generator_id, "settings": {"rise": 0.3}}
	)
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["appearance_dropped"], [], "nothing lost")
	assert_eq(r["result"]["warnings"], [])
	var again: DraftBrush = pieces(level, generator_id)[0]
	assert_eq(str(again.name), "bottom_step", "the name came across")
	assert_eq(again.faces[0].material_idx, 1, "and so did the paint")
	assert_eq(r["result"]["made"][0]["name"], "bottom_step", "and the answer says so")


func test_an_update_says_which_paint_it_could_not_keep():
	var level := make_level_with_palette()
	var generator_id: String = (await build_stairs())["generator_id"]
	var last: DraftBrush = pieces(level, generator_id)[3]
	var last_id := last.brush_id
	level.assign_material_to_faces_by_id(last_id, [0], 1)
	assert_eq(last.faces[0].material_idx, 1, "painted")
	var r := await run("update_structure", {"generator_id": generator_id, "settings": {"steps": 3}})
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["appearance_dropped"], [last_id], "the step that went is named")
	assert_eq(r["result"]["warnings"].size(), 1, str(r["result"]["warnings"]))
	assert_string_contains(r["result"]["warnings"][0], "painted faces")


func test_an_update_of_pieces_moved_apart_says_where_it_went():
	var level := make_level()
	var generator_id: String = (await build_stairs())["generator_id"]
	var all := pieces(level, generator_id)
	(all[0] as DraftBrush).global_position += Vector3(5, 0, 0)
	(all[1] as DraftBrush).global_position += Vector3(9, 0, 0)
	assert_true(level.generator_pieces_disagree(generator_id), "the setup splits the vote")
	var r := await run("update_structure", {"generator_id": generator_id})
	assert_true(r.get("ok", false), str(r))
	assert_has(r["result"]["warnings"], HFMcpCommands.LOST_PLACE)


func test_a_refused_update_changes_nothing_and_says_what_the_dock_says():
	var level := make_level()
	var built := await run(
		"create_arch", {"type": "arch", "position": [0, 0, 0], "settings": {"radius": 4.0}}
	)
	assert_true(built.get("ok", false), str(built))
	var generator_id: String = built["result"]["generator_id"]
	var before := snapshot(level)
	var r := await run(
		"update_structure", {"generator_id": generator_id, "settings": {"wall_thickness": 6.0}}
	)
	assert_checked_refusal(r, "operation_failed", before, "a wall thicker than the radius")
	var record = level.generator_for_id(generator_id)
	var asked := record.settings.duplicate(true) as Dictionary
	asked["wall_thickness"] = 6.0
	var merged := HFGeneratorSchema.merge(HFGeneratorSystem.settings_schema("arch"), asked)
	assert_eq(
		r["error"]["message"],
		HFGeneratorSystem.not_changed_text("arch", level.can_build_generator("arch", merged)),
		"the dock's words"
	)
	assert_string_starts_with(r["error"]["message"], "Arch not changed.")


func test_an_update_is_checked_before_anything_changes():
	var level := make_level()
	var generator_id: String = (await build_stairs())["generator_id"]
	var cases := [
		[{"settings": {"steps": 4}}, "params.generator_id"],
		[{"generator_id": "gen_nope"}, "params.generator_id"],
		[{"generator_id": ""}, "params.generator_id"],
		[{"generator_id": generator_id, "settings": {"radius": 2.0}}, "params.settings.radius"],
		[{"generator_id": generator_id, "settings": {"steps": 2.5}}, "params.settings.steps"],
		[{"generator_id": generator_id, "settings": {"fill": "Glass"}}, "params.settings.fill"],
		[{"generator_id": generator_id, "settings": "tall"}, "params.settings"],
	]
	for case in cases:
		var before := snapshot(level)
		var r := await run("update_structure", case[0])
		assert_checked_refusal(r, "invalid_argument", before, str(case[0]))
		if not r.get("ok", true):
			assert_eq(r["error"]["details"]["param"], case[1], str(case[0]))
	var before := snapshot(level)
	var on_brush := await run(
		"update_structure",
		{"generator_id": generator_id},
		[pieces(level, generator_id)[0].brush_id]
	)
	assert_checked_refusal(on_brush, "invalid_argument", before, "it takes no brushes")


# ===========================================================================
# Detach
# ===========================================================================


func test_detach_leaves_plain_brushes_that_undo_and_redo_follow():
	var level := make_level()
	var built := await build_stairs()
	var generator_id: String = built["generator_id"]
	var ids: Array = []
	for brush in built["made"]:
		ids.append(brush["brush_id"])
	var r := await run("detach_structure", {"generator_id": generator_id})
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: detach structure")
	assert_eq(r["result"]["detached"], ids, "every piece, in order")
	assert_eq(r["result"]["removed"], [], "nothing was deleted")
	assert_eq(r["result"]["type"], "stairs")
	assert_eq(r["result"]["settings"]["steps"], 4)
	assert_eq(level.generator_count(), 0)
	assert_null(await listed_structure(ids[0]), "a plain brush now")
	var refused := await run("update_structure", {"generator_id": generator_id})
	assert_refused(refused, "invalid_argument", "a detached structure cannot be updated")

	await call_tool("hf_undo")
	var back = await listed_structure(ids[0])
	assert_not_null(back, "undo makes it a structure again")
	if back != null:
		assert_eq(back["generator_id"], generator_id)
		assert_eq(back["piece"], 0)

	await call_tool("hf_redo")
	assert_eq(level.generator_count(), 0)
	assert_null(await listed_structure(ids[1]), "redo detaches it again")
	for brush_id in ids:
		assert_false(brush_node(level, brush_id).has_meta("hf_generator_id"), "and leaves no tag")


func test_detach_of_a_structure_that_is_not_there_is_refused():
	var level := make_level()
	var before := snapshot(level)
	var r := await run("detach_structure", {"generator_id": "gen_nope"})
	assert_checked_refusal(r, "invalid_argument", before, "no such structure")
	assert_string_contains(r["error"]["message"], "hf_get_brushes")


# ===========================================================================
# What an agent reads
# ===========================================================================


func test_every_piece_names_its_structure_and_a_plain_brush_names_none():
	make_level()
	var built := await build_stairs({"steps": 3})
	for i in built["made"].size():
		var structure = await listed_structure(built["made"][i]["brush_id"])
		assert_eq(structure["generator_id"], built["generator_id"])
		assert_eq(structure["type"], "stairs")
		assert_eq(structure["piece"], i, "pieces in build order")
		assert_eq(structure["settings"]["steps"], 3, "with the settings an update starts from")
	var box := await place_box([20, 1, 0])
	assert_null(await listed_structure(box), "a box is no structure")


func test_the_listing_gives_update_the_settings_create_takes():
	var r := await call_tool("hf_list_commands")
	var by_id := {}
	for entry in r["result"]["commands"]:
		by_id[entry["command"]] = entry
	var update: Dictionary = by_id["update_structure"]
	assert_eq(update["params"]["required"], ["generator_id"])
	assert_eq(update["targets"], {"min": 0, "max": 0, "entities": false})
	assert_eq(update["settings_by_type"], by_id["create_arch"]["settings_by_type"])
	assert_eq(by_id["detach_structure"]["params"]["required"], ["generator_id"])
	assert_false(by_id["detach_structure"].has("settings_by_type"), "detach takes no settings")


# ===========================================================================
# hf_batch
# ===========================================================================


func test_a_batch_builds_a_structure_and_detaches_it_by_reference():
	var level := make_level()
	var r := await call_tool(
		"hf_batch",
		{
			"ops":
			[
				{
					"tool": "hf_run_command",
					"params":
					{
						"command": "create_arch",
						"params":
						{"type": "stairs", "position": [0, 0, 0], "settings": {"steps": 2}}
					}
				},
				{
					"tool": "hf_run_command",
					"params":
					{
						"command": "update_structure",
						"params": {"generator_id": "$0.generator_id", "settings": {"steps": 5}}
					}
				},
				{
					"tool": "hf_run_command",
					"params":
					{"command": "detach_structure", "params": {"generator_id": "$1.generator_id"}}
				},
			]
		}
	)
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: batch (3 ops)", "one step")
	assert_eq(level.generator_count(), 0, "built, grown and detached")
	assert_eq(brushes(level).size(), 5, "five plain steps")
	assert_eq(r["result"]["results"][2]["result"]["detached"].size(), 5)


func test_a_generator_reference_to_an_op_that_built_none_is_refused():
	var level := make_level()
	var before := snapshot(level)
	var r := await call_tool(
		"hf_batch",
		{
			"ops":
			[
				{"tool": "hf_place_brush", "params": {"size": [2, 2, 2], "position": [0, 1, 0]}},
				{
					"tool": "hf_run_command",
					"params":
					{"command": "detach_structure", "params": {"generator_id": "$0.generator_id"}}
				},
			]
		}
	)
	assert_refused(r, "batch_failed", "a box is no structure")
	assert_string_contains(str(r["error"]["details"]["error"]["message"]), "made no structure")
	assert_eq(snapshot(level), before, "the box went back too")
