extends "res://tests/mcp/mcp_dispatcher_case.gd"

## Floor paint through hf_run_command (#1299): a rectangle painted or erased,
## its walls raised, a room stamped and a connector confirmed, each one
## `MCP: ...` step that hf_undo takes back, refusals that change nothing, and
## the listing that tells an agent which layers there are.

const HFPaintTool = preload("res://addons/hammerforge/paint/hf_paint_tool.gd")


func run(command: String, args = null) -> Dictionary:
	var params := {"command": command}
	if args != null:
		params["params"] = args
	return await call_tool("hf_run_command", params)


func top_step() -> String:
	return undo.scene_history.get_current_action_name()


func level_of() -> LevelRoot:
	return host.level_root_in(host.scene) as LevelRoot


func layer(level: LevelRoot, index := 0) -> HFPaintLayer:
	return level.paint_layers.layers[index]


func cell(x: int, z: int) -> Vector2i:
	return Vector2i(x, z)


## How many of the rectangle's cells are painted on the layer.
func painted(level: LevelRoot, index: int, from: Vector2i, to: Vector2i) -> int:
	var count := 0
	for c in HFPaintTool.rect_cells(from, to):
		if layer(level, index).get_cell(c):
			count += 1
	return count


func assert_checked_refusal(response: Dictionary, code: String, before: Dictionary, note: String):
	assert_refused(response, code, note)
	if response.get("ok", true):
		return
	assert_false(response["error"]["details"].has("rolled_back"), "%s: refused in the check" % note)
	assert_eq(snapshot(level_of()), before, "%s: nothing changed" % note)


# ===========================================================================
# Painting
# ===========================================================================


func test_a_rectangle_is_one_step_that_undo_empties_and_redo_refills():
	var level := make_level()
	var r := await run("paint_ramp", {"from": [0, 0], "to": [3, 1]})
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: ramp / rect")
	var result: Dictionary = r["result"]
	assert_eq(result["cells"], 8)
	assert_eq(result["cells_changed"], 8)
	assert_true(result["filled"])
	assert_eq(result["layer"], {"index": 0, "id": "layer_0", "name": "layer_0"})
	assert_eq(result["from"], [0, 0])
	assert_eq(result["to"], [3, 1])
	assert_eq(result["material"], null)
	assert_eq(result["made"], [], "generated floors are not brushes")
	assert_eq(result["removed"], [])
	assert_eq(result["changed"], [], "the brush list every answer carries")
	var bounds: Dictionary = result["bounds"]
	assert_almost_eq(
		Vector3(bounds["min"][0], bounds["min"][1], bounds["min"][2]),
		Vector3(0, 0.2, 0),
		Vector3.ONE * 0.001,
		"on the floor's top"
	)
	assert_almost_eq(
		Vector3(bounds["max"][0], bounds["max"][1], bounds["max"][2]),
		Vector3(4, 0.2, 2),
		Vector3.ONE * 0.001,
		"the far edge of the far cells"
	)
	assert_eq(painted(level, 0, cell(0, 0), cell(3, 1)), 8)
	assert_gt(level.generated_floors.get_child_count(), 0, "built before the answer")

	var undone := await call_tool("hf_undo")
	assert_true(undone.get("ok", false), str(undone))
	assert_eq(layer(level).filled_cell_count(), 0, "undo takes the paint away")
	assert_eq(level.generated_floors.get_child_count(), 0, "and the floor")

	var redone := await call_tool("hf_redo")
	assert_true(redone.get("ok", false), str(redone))
	assert_eq(painted(level, 0, cell(0, 0), cell(3, 1)), 8, "redo paints it again")
	assert_gt(level.generated_floors.get_child_count(), 0)


func test_an_erase_takes_one_cell_when_to_is_absent():
	var level := make_level()
	await run("paint_ramp", {"from": [0, 0], "to": [2, 2]})
	var r := await run("paint_ramp", {"from": [1, 1], "filled": false})
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["to"], [1, 1], "to is from")
	assert_eq(r["result"]["cells_changed"], 1)
	assert_false(r["result"]["filled"])
	assert_false(layer(level).get_cell(cell(1, 1)))
	assert_eq(painted(level, 0, cell(0, 0), cell(2, 2)), 8, "the rest stays")
	var again := await run("paint_ramp", {"from": [0, 0], "to": [2, 2]})
	assert_true(again.get("ok", false))
	assert_eq(again["result"]["cells_changed"], 1, "only the erased cell was painted again")


func test_a_material_rides_on_painted_cells_and_an_erase_refuses_one():
	var level := make_level()
	var r := await run("paint_ramp", {"from": [0, 0], "to": [1, 0], "material": 3})
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["material"], 3)
	assert_eq(layer(level).get_cell_material(cell(1, 0)), 3)
	var before := snapshot(level)
	var refused := await run("paint_ramp", {"from": [0, 0], "filled": false, "material": 1})
	assert_checked_refusal(refused, "invalid_argument", before, "no material on an erase")
	assert_eq(refused["error"]["details"]["param"], "params.material")


func test_material_only_repaint_and_default_height_pinning_report_their_changes():
	var level := make_level()
	await run("paint_ramp", {"from": [0, 0], "to": [1, 0]})
	var repainted := await run("paint_ramp", {"from": [0, 0], "to": [1, 0], "material": 3})
	assert_true(repainted["ok"], str(repainted))
	assert_eq(repainted["result"]["cells_changed"], 0)
	assert_eq(repainted["result"].get("materials_changed", -1), 2)
	assert_false(repainted["result"].get("no_change", false))
	var height: float = level.paint_tool.synth_settings.wall_height
	var raised := await run("paint_raise", {"from": [0, 0], "to": [1, 0], "height": height})
	assert_eq(raised["result"]["heights_changed"], 2)
	assert_false(raised["result"].get("no_change", false))
	var again := await run("paint_raise", {"from": [0, 0], "to": [1, 0], "height": height})
	assert_eq(again["result"]["heights_changed"], 0)
	assert_true(again["result"].get("no_change", false))
	assert_eq(again["revision"], raised["revision"], "an unchanged pin records no step")


func test_bridge_and_system_use_the_same_stroke_and_raise_refusals():
	var level := make_level()
	level.paint_tool._painting = true
	var direct: Dictionary = level.paint_system.paint_cells(0, Vector2i.ZERO, Vector2i.ZERO, true)
	var refused := await run("paint_ramp", {"from": [0, 0]})
	assert_refused(refused, "operation_failed")
	assert_eq(refused["error"]["message"], direct["error"])
	level.paint_tool._painting = false
	direct = level.paint_system.confirm_connectors(0, Vector2i.ZERO, Vector2i.ZERO, 0)
	refused = await run("paint_confirm_connector", {"from": [0, 0], "to_layer": 0})
	assert_refused(refused, "invalid_argument")
	assert_eq(refused["error"]["details"]["param"], "params.to_layer")
	assert_eq(refused["error"]["message"], direct["error"])
	direct = level.paint_system.raise_cells(0, Vector2i.ZERO, Vector2i.ZERO, 4.0)
	refused = await run("paint_raise", {"from": [0, 0], "height": 4.0})
	assert_refused(refused, "operation_failed")
	assert_eq(refused["error"]["message"], direct["error"])


func test_a_layer_is_named_by_index_or_name_and_the_active_one_if_not():
	var level := make_level()
	layer(level).display_name = "Ground"
	level.paint_layers.create_layer(&"upper", 3.0)
	level.paint_layers.active_layer_index = 1
	var by_name := await run("paint_ramp", {"from": [0, 0], "layer": "Ground"})
	assert_true(by_name.get("ok", false), str(by_name))
	assert_eq(by_name["result"]["layer"], {"index": 0, "id": "layer_0", "name": "Ground"})
	var by_index := await run("paint_ramp", {"from": [1, 0], "layer": 1})
	assert_true(by_index.get("ok", false), str(by_index))
	assert_eq(by_index["result"]["layer"]["id"], "upper")
	var active := await run("paint_ramp", {"from": [2, 0]})
	assert_true(active.get("ok", false), str(active))
	assert_eq(active["result"]["layer"]["index"], 1, "the Paint tab's active layer")
	assert_true(layer(level, 0).get_cell(cell(0, 0)))
	assert_true(layer(level, 1).get_cell(cell(1, 0)))
	assert_true(layer(level, 1).get_cell(cell(2, 0)))
	var bounds: Dictionary = by_index["result"]["bounds"]
	assert_almost_eq(float(bounds["min"][1]), 3.2, 0.001, "on the upper layer's floor")


# ===========================================================================
# Raising
# ===========================================================================


func test_raise_sets_the_walls_height_and_undo_takes_it_back():
	var level := make_level()
	await run("paint_ramp", {"from": [0, 0], "to": [2, 0]})
	var r := await run("paint_raise", {"from": [0, 0], "to": [1, 0], "height": 4.0})
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: raise painted walls")
	assert_eq(r["result"]["raised"], 2)
	assert_eq(r["result"]["heights_changed"], 2)
	assert_almost_eq(float(r["result"]["height"]), 4.0, 0.001)
	assert_almost_eq(layer(level).get_wall_height(cell(1, 0), 3.0), 4.0, 0.001)
	assert_almost_eq(
		layer(level).get_wall_height(cell(2, 0), 3.0), 3.0, 0.001, "outside the rectangle"
	)
	await call_tool("hf_undo")
	assert_almost_eq(layer(level).get_wall_height(cell(1, 0), 3.0), 3.0, 0.001, "undone")
	assert_true(layer(level).get_cell(cell(1, 0)), "the paint stays: it was the step before")
	await call_tool("hf_redo")
	assert_almost_eq(layer(level).get_wall_height(cell(1, 0), 3.0), 4.0, 0.001, "redone")


func test_a_raise_over_nothing_painted_is_refused_before_anything_is_captured():
	var level := make_level()
	await run("paint_ramp", {"from": [0, 0]})
	var before := snapshot(level)
	var r := await run("paint_raise", {"from": [5, 5], "to": [6, 6], "height": 2.0})
	assert_checked_refusal(r, "operation_failed", before, "no painted cells there")
	assert_string_contains(r["error"]["message"], "paint_ramp")


# ===========================================================================
# Stamping a room
# ===========================================================================


func test_stamp_room_paints_and_raises_in_one_step():
	var level := make_level()
	var r := await run("paint_room", {"at": [5, 5], "width": 3, "depth": 2, "height": 2.5})
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: stamp painted room")
	var result: Dictionary = r["result"]
	assert_eq(result["at"], [5, 5])
	assert_eq(result["from"], [5, 5])
	assert_eq(result["to"], [7, 6])
	assert_eq(result["width"], 3)
	assert_eq(result["depth"], 2)
	assert_eq(result["cells"], 6)
	assert_eq(result["cells_changed"], 6)
	assert_eq(result["raised"], 6)
	assert_almost_eq(float(result["height"]), 2.5, 0.001)
	assert_eq(painted(level, 0, cell(5, 5), cell(7, 6)), 6)
	assert_almost_eq(layer(level).get_wall_height(cell(7, 6), 3.0), 2.5, 0.001)
	assert_eq(undo.scene_history.get_history_count(), 1, "the paint and the raise are one step")
	await call_tool("hf_undo")
	assert_eq(layer(level).filled_cell_count(), 0, "undo takes the room")
	assert_eq(layer(level).get_wall_height_entries().size(), 0, "and its heights, together")


func test_stamp_room_defaults_to_the_tool_s_first_rectangle():
	var level := make_level()
	var r := await run("paint_room", {"at": [20, 20]})
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["width"], 4)
	assert_eq(r["result"]["depth"], 4)
	assert_eq(r["result"]["cells"], 16)
	assert_eq(r["result"]["raised"], 0)
	assert_eq(r["result"]["height"], null)
	assert_eq(painted(level, 0, cell(20, 20), cell(23, 23)), 16)
	assert_eq(layer(level).get_wall_height_entries().size(), 0, "the default walls")


# ===========================================================================
# Connectors
# ===========================================================================


func test_confirm_connector_keeps_a_ramp_between_two_layers():
	var level := make_level()
	level.paint_layers.create_layer(&"upper", 3.0)
	await run("paint_ramp", {"layer": 0, "from": [0, 0]})
	await run("paint_ramp", {"layer": "upper", "from": [1, 0]})
	var r := await run("paint_confirm_connector", {"layer": 0, "from": [0, 0]})
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: confirm paint connector")
	var result: Dictionary = r["result"]
	assert_eq(result["added"], 1)
	assert_eq(result["already"], 0)
	assert_eq(result["to_layer"], null)
	assert_false(result.has("bounds"), "a connector is an edge, not a floor")
	assert_eq(
		result["connectors"],
		[
			{
				"from_layer": 0,
				"to_layer": 1,
				"from_cell": [0, 0],
				"to_cell": [1, 0],
				"type": "ramp",
				"width_cells": level.bake_connector_width,
			}
		]
	)
	assert_eq(level.paint_tool.connector_defs.size(), 1)

	var before := snapshot(level)
	var again := await run("paint_confirm_connector", {"layer": 0, "from": [0, 0]})
	assert_checked_refusal(again, "operation_failed", before, "already confirmed")
	assert_string_contains(again["error"]["message"], "already")

	await call_tool("hf_undo")
	assert_eq(level.paint_tool.connector_defs.size(), 0, "undo takes the connector")
	await call_tool("hf_redo")
	assert_eq(level.paint_tool.connector_defs.size(), 1, "redo keeps it again")

	await call_tool("hf_undo")
	# The layer made last is the active one; from the ground, held to the upper.
	level.paint_layers.active_layer_index = 0
	var held := await run("paint_confirm_connector", {"from": [0, 0], "to_layer": "upper"})
	assert_true(
		held.get("ok", false), "held to the upper layer, from the active one: %s" % str(held)
	)
	assert_eq(held["result"]["to_layer"], 1)


func test_confirm_connector_refusals_change_nothing():
	var level := make_level()
	await run("paint_ramp", {"from": [0, 0]})
	var before := snapshot(level)
	var alone := await run("paint_confirm_connector", {"from": [0, 0]})
	assert_checked_refusal(alone, "operation_failed", before, "one layer")
	level.paint_layers.create_layer(&"upper", 3.0)
	before = snapshot(level)
	var apart := await run("paint_confirm_connector", {"layer": 0, "from": [0, 0]})
	assert_checked_refusal(apart, "operation_failed", before, "no neighbour on the other layer")
	var itself := await run("paint_confirm_connector", {"layer": 0, "from": [0, 0], "to_layer": 0})
	assert_checked_refusal(itself, "invalid_argument", before, "to_layer is the layer itself")
	assert_eq(itself["error"]["details"]["param"], "params.to_layer")
	var nowhere := await run(
		"paint_confirm_connector", {"layer": 0, "from": [0, 0], "to_layer": "nope"}
	)
	assert_checked_refusal(nowhere, "invalid_argument", before, "no such layer")
	assert_eq(nowhere["error"]["details"]["param"], "params.to_layer")


# ===========================================================================
# Refusals that name the param
# ===========================================================================


func test_bad_arguments_are_refused_naming_the_param_and_change_nothing():
	var level := make_level()
	var before := snapshot(level)
	var cases := [
		["paint_ramp", {}, "params.from"],
		["paint_ramp", {"from": [0.5, 0]}, "params.from"],
		["paint_ramp", {"from": [0, 0, 0]}, "params.from"],
		["paint_ramp", {"from": [true, 0]}, "params.from"],
		["paint_ramp", {"from": [100001, 0]}, "params.from"],
		["paint_ramp", {"from": [0, 0], "to": [300, 300]}, "params.to"],
		["paint_ramp", {"from": [0, 0], "to": [100000, 0]}, "params.to"],
		["paint_ramp", {"from": [0, 0], "layer": 3}, "params.layer"],
		["paint_ramp", {"from": [0, 0], "layer": "nope"}, "params.layer"],
		["paint_ramp", {"from": [0, 0], "layer": -1}, "params.layer"],
		["paint_ramp", {"from": [0, 0], "layer": 1.5}, "params.layer"],
		["paint_ramp", {"from": [0, 0], "layer": true}, "params.layer"],
		["paint_ramp", {"from": [0, 0], "filled": "yes"}, "params.filled"],
		["paint_ramp", {"from": [0, 0], "material": 256}, "params.material"],
		["paint_ramp", {"from": [0, 0], "radius": 2}, "params.radius"],
		["paint_raise", {"from": [0, 0]}, "params.height"],
		["paint_raise", {"from": [0, 0], "height": 0.1}, "params.height"],
		["paint_raise", {"from": [0, 0], "height": 300}, "params.height"],
		["paint_room", {"at": [0, 0], "width": 0}, "params.width"],
		["paint_room", {"at": [0, 0], "depth": 257}, "params.depth"],
		["paint_room", {"at": [99990, 0], "width": 20}, "params.at"],
		["paint_room", {"at": [0, 0], "height": 0}, "params.height"],
	]
	for case in cases:
		var r := await run(case[0], case[1])
		assert_checked_refusal(r, "invalid_argument", before, str(case))
		if not r.get("ok", true):
			assert_eq(r["error"]["details"]["param"], case[2], str(case))
	var unknown := await run("paint_ramp", {"from": [0, 0], "layer": "nope"})
	assert_string_contains(unknown["error"]["message"], "layer_0 (0)", "the layers it has")
	var with_brush := await call_tool(
		"hf_run_command", {"command": "paint_ramp", "brush_ids": ["a"], "params": {"from": [0, 0]}}
	)
	assert_checked_refusal(with_brush, "invalid_argument", before, "it takes no brushes")


func test_a_call_mid_stroke_is_refused():
	var level := make_level()
	level.paint_tool._painting = true
	var before := snapshot(level)
	var r := await run("paint_ramp", {"from": [0, 0]})
	assert_checked_refusal(r, "operation_failed", before, "mid-stroke")
	assert_string_contains(r["error"]["message"], "stroke")
	level.paint_tool._painting = false


# ===========================================================================
# The listing
# ===========================================================================


func test_the_listing_describes_the_paint_commands_and_the_level_s_layers():
	var level := make_level()
	layer(level).display_name = "Ground"
	await run("paint_ramp", {"from": [0, 0], "to": [1, 0]})
	var r := await call_tool("hf_list_commands")
	assert_true(r.get("ok", false), str(r))
	var by_id := {}
	for entry in r["result"]["commands"]:
		by_id[entry["command"]] = entry
	for command in ["paint_ramp", "paint_raise", "paint_room", "paint_confirm_connector"]:
		assert_true(by_id.has(command), "%s is listed" % command)
		assert_eq(by_id[command]["targets"], {"min": 0, "max": 0, "entities": false})
		assert_eq(
			by_id[command]["paint_layers"],
			[
				{
					"index": 0,
					"id": "layer_0",
					"name": "Ground",
					"layer_y": 0.0,
					"cell_size": 1.0,
					"cells": 2,
				}
			],
			"%s lists the layers" % command
		)
	var rect: Dictionary = by_id["paint_ramp"]["params"]
	assert_eq(rect["required"], ["from"])
	assert_eq(rect["properties"]["from"]["type"], "array")
	assert_eq(rect["properties"]["from"]["minItems"], 2)
	assert_eq(rect["properties"]["from"]["items"], {"type": "integer"})
	assert_true(rect["properties"]["layer"].has("anyOf"), "an index or a name")
	assert_eq(rect["properties"]["filled"]["default"], true)
	assert_eq(rect["properties"]["material"]["maximum"], 255)
	assert_eq(by_id["paint_raise"]["params"]["required"], ["from", "height"])
	assert_eq(by_id["paint_raise"]["params"]["properties"]["height"]["minimum"], 0.25)
	assert_eq(by_id["paint_room"]["params"]["required"], ["at"])
	assert_eq(by_id["paint_room"]["params"]["properties"]["width"]["default"], 4)
	assert_eq(by_id["paint_confirm_connector"]["params"]["required"], ["from"])
	assert_false(by_id["hollow"].has("paint_layers"), "a brush command lists none")


func test_the_listing_without_a_level_lists_no_layers():
	make_scene()
	var r := await call_tool("hf_list_commands")
	assert_true(r.get("ok", false), str(r))
	for entry in r["result"]["commands"]:
		if entry["command"] == "paint_ramp":
			assert_eq(entry["paint_layers"], [])


# ===========================================================================
# hf_batch
# ===========================================================================


func test_a_batch_paints_two_floors_raises_one_and_joins_them_as_one_step():
	var level := make_level()
	level.paint_layers.create_layer(&"upper", 3.0)
	var r := await call_tool(
		"hf_batch",
		{
			"ops":
			[
				{
					"tool": "hf_run_command",
					"params":
					{"command": "paint_ramp", "params": {"layer": 0, "from": [0, 0], "to": [2, 2]}}
				},
				{
					"tool": "hf_run_command",
					"params":
					{
						"command": "paint_ramp",
						"params": {"layer": "upper", "from": [3, 0], "to": [4, 2]}
					}
				},
				{
					"tool": "hf_run_command",
					"params":
					{
						"command": "paint_raise",
						"params": {"layer": 0, "from": [0, 0], "to": [2, 2], "height": 4.0}
					}
				},
				{
					"tool": "hf_run_command",
					"params":
					{
						"command": "paint_confirm_connector",
						"params": {"layer": 0, "from": [2, 0], "to": [2, 2]}
					}
				},
			]
		}
	)
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: batch (4 ops)")
	assert_eq(painted(level, 0, cell(0, 0), cell(2, 2)), 9)
	assert_eq(painted(level, 1, cell(3, 0), cell(4, 2)), 6)
	assert_almost_eq(layer(level).get_wall_height(cell(2, 2), 3.0), 4.0, 0.001)
	assert_eq(
		r["result"]["results"][3]["result"]["added"], 1, "one connector along the shared edge"
	)
	assert_eq(level.paint_tool.connector_defs.size(), 1)
	await call_tool("hf_undo")
	assert_eq(layer(level, 0).filled_cell_count(), 0)
	assert_eq(layer(level, 1).filled_cell_count(), 0)
	assert_eq(level.paint_tool.connector_defs.size(), 0, "all of it in one step")


func test_a_batch_that_fails_late_puts_the_paint_back():
	var level := make_level()
	var before := snapshot(level)
	var r := await call_tool(
		"hf_batch",
		{
			"ops":
			[
				{
					"tool": "hf_run_command",
					"params": {"command": "paint_ramp", "params": {"from": [0, 0], "to": [2, 2]}}
				},
				{
					"tool": "hf_run_command",
					"params": {"command": "paint_raise", "params": {"from": [9, 9], "height": 2.0}}
				},
			]
		}
	)
	assert_refused(r, "batch_failed", "the raise finds nothing painted")
	assert_eq(snapshot(level), before, "the paint went back with the batch")
	assert_eq(level.generated_floors.get_child_count(), 0)
