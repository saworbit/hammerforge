extends "res://tests/mcp/mcp_dispatcher_case.gd"
## Replace Material through hf_run_command (#1726): an agent swaps one material
## for another as the dialog does, by name or id, as one step.


func run(args: Dictionary, brush_ids := []) -> Dictionary:
	var params := {"command": "replace_material", "params": args}
	if not brush_ids.is_empty():
		params["brush_ids"] = brush_ids
	return await call_tool("hf_run_command", params)


## Two boxes, a all slot 1 and b slot 1 on three faces.
func _level() -> LevelRoot:
	var level := make_level_with_palette()
	var a := await place_box([0, 1, 0])
	var b := await place_box([6, 1, 0])
	for face in brush_node(level, a).faces:
		face.material_idx = 1
	for i in 3:
		brush_node(level, b).faces[i].material_idx = 1
	return level


func test_an_agent_replaces_a_material_across_the_level_as_one_step():
	var level := await _level()
	var steps: int = undo.scene_history.get_history_count()
	var r := await run({"from": "palette:1", "to": "palette:2"})
	assert_true(r.get("ok", false), str(r))
	if not r.get("ok", false):
		return
	assert_eq(r["result"]["faces"], 9)
	assert_eq(r["result"]["brushes"].size(), 2)
	assert_eq(undo.scene_history.get_history_count(), steps + 1, "one step")
	for brush in brushes(level):
		assert_false(brush.faces[0].material_idx == 1, "%s replaced" % brush.brush_id)
	var back := await call_tool("hf_undo")
	assert_true(back.get("ok", false), str(back))
	for brush in brushes(level):
		assert_eq(brush.faces[0].material_idx, 1, "%s back" % brush.brush_id)


func test_brush_ids_keep_it_to_those_brushes():
	var level := await _level()
	var b: DraftBrush = brushes(level)[1]
	var r := await run({"from": "palette:1", "to": "palette:2"}, [b.brush_id])
	assert_true(r.get("ok", false), str(r))
	assert_eq(r.get("result", {}).get("faces"), 3)
	assert_eq(brushes(level)[0].faces[0].material_idx, 1, "the other brush kept it")


func test_bad_materials_are_refused_naming_the_field_and_change_nothing():
	var level := await _level()
	var before := snapshot(level)
	var r := await run({"from": "no such stuff", "to": "palette:2"})
	assert_refused(r, HFMcpProtocol.E_UNKNOWN_MATERIAL, "an unknown from")
	r = await run({"from": "palette:1", "to": ""})
	assert_refused(r, HFMcpProtocol.E_INVALID_ARGUMENT, "an empty to")
	assert_eq(r.get("error", {}).get("details", {}).get("param"), "params.to")
	r = await run({"from": "palette:1", "to": "palette:1"})
	assert_refused(r, HFMcpProtocol.E_OPERATION_FAILED, "the same material")
	r = await run({"from": "palette:5", "to": "palette:2"})
	assert_refused(r, HFMcpProtocol.E_OPERATION_FAILED, "a material no face wears")
	assert_eq(snapshot(level), before, "nothing changed")
