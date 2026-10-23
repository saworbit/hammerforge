extends "res://tests/mcp/mcp_dispatcher_case.gd"

## `hf_get_brushes` and `hf_get_entities` find by property and answer a page at a
## time (#1704), so an agent asks for the cut brushes rather than reading every
## brush with its faces and filtering in its own context.


func _brushes(params: Dictionary) -> Dictionary:
	return await call_tool("hf_get_brushes", params)


func _ids(r: Dictionary) -> Array:
	var ids: Array = []
	for brush in r.get("result", {}).get("brushes", []):
		ids.append(brush["brush_id"])
	ids.sort()
	return ids


func _box(level: LevelRoot, id: String, center: Vector3, subtract := false) -> DraftBrush:
	return (
		level
		. create_brush_from_info(
			{
				"brush_id": id,
				"size": Vector3(2, 2, 2),
				"center": center,
				"operation":
				CSGShape3D.OPERATION_SUBTRACTION if subtract else CSGShape3D.OPERATION_UNION,
			}
		)
	)


func test_operation_subtract_gives_only_the_cut_brushes_and_their_count():
	var level := make_level()
	_box(level, "wall", Vector3(0, 1, 0))
	_box(level, "door", Vector3(0, 1, 0), true)
	_box(level, "window", Vector3(4, 1, 0), true)
	var r := await _brushes({"filter": {"operation": "subtract"}, "include_faces": false})
	assert_true(r.get("ok", false), str(r))
	assert_eq(_ids(r), ["door", "window"])
	assert_eq(r["result"]["count"], 2)
	assert_eq(r["result"]["returned"], 2)
	assert_false(r["result"]["truncated"])


func test_paging_returns_every_brush_exactly_once():
	var level := make_level()
	var infos: Array = []
	for i in 5000:
		infos.append(
			{"size": Vector3.ONE, "center": Vector3(i % 100, 0.5, floori(i / 100.0)) * 2.0}
		)
	level.create_brushes_from_infos(infos)
	var seen := {}
	var offset := 0
	var pages := 0
	while true:
		var r := await _brushes({"include_faces": false, "limit": 200, "offset": offset})
		assert_true(r.get("ok", false), str(r).left(300))
		if not r.get("ok", false):
			return
		assert_eq(r["result"]["count"], 5000)
		for brush in r["result"]["brushes"]:
			seen[brush["brush_id"]] = int(seen.get(brush["brush_id"], 0)) + 1
		pages += 1
		offset += int(r["result"]["returned"])
		if not r["result"]["truncated"]:
			break
	assert_eq(pages, 25)
	assert_eq(seen.size(), 5000, "every brush")
	assert_eq(seen.values().filter(func(n): return n != 1), [], "each once")


func test_count_only_answers_in_under_200_bytes():
	var level := make_level()
	for i in 30:
		_box(level, "b%d" % i, Vector3(i * 3, 1, 0))
	var r := await _brushes({"count_only": true})
	assert_eq(r["result"], {"count": 30})
	assert_lt(JSON.stringify(r).length(), 200, JSON.stringify(r))


func test_an_unknown_filter_key_is_refused_by_name():
	make_level()
	var r := await _brushes({"filter": {"colour": "red"}})
	assert_refused(r, HFMcpProtocol.E_INVALID_ARGUMENT)
	if not r.get("ok", true):
		assert_eq(r["error"]["details"]["param"], "filter.colour")
		assert_string_contains(r["error"]["message"], "no filter colour")
	var e := await call_tool("hf_get_entities", {"filter": {"energy": 2}})
	assert_refused(e, HFMcpProtocol.E_INVALID_ARGUMENT)
	if not e.get("ok", true):
		assert_eq(e["error"]["details"]["param"], "filter.energy")


func test_material_name_shape_and_box_filters():
	var level := make_level_with_palette()
	var a := _box(level, "crate_a", Vector3(0, 1, 0))
	_box(level, "crate_b", Vector3(10, 1, 0))
	_box(level, "pillar", Vector3(20, 1, 0))
	for face in a.faces:
		face.material_idx = 2
	var by_material := await _brushes({"filter": {"material": "palette:2"}, "include_faces": false})
	assert_eq(_ids(by_material), ["crate_a"])
	var by_name := await _brushes({"filter": {"name": "crate*"}, "include_faces": false})
	assert_eq(_ids(by_name), ["crate_a", "crate_b"])
	var by_shape := await _brushes({"filter": {"shape": "box"}, "include_faces": false})
	assert_eq(by_shape["result"]["count"], 3)
	var inside := await _brushes(
		{
			"bounds": {"min": [-2, -1, -2], "max": [12, 3, 2]},
			"bounds_test": "inside",
			"include_faces": false
		}
	)
	assert_eq(_ids(inside), ["crate_a", "crate_b"])
	var touching := await _brushes(
		{"bounds": {"min": [10, 0.5, -0.5], "max": [20, 1.5, 0.5]}, "include_faces": false}
	)
	assert_eq(_ids(touching), ["crate_b", "pillar"])


func _entity(level: LevelRoot, entity_class: String, entity_name: String, at: Vector3) -> Node:
	var entity: Node = level._create_entity_from_map({"classname": entity_class, "origin": at})
	entity.set_meta("entity_name", entity_name)
	return entity


func test_entity_property_tests_work_for_numbers_and_strings():
	var level := make_level()
	var dim := _entity(level, "light_point", "dim", Vector3(0, 2, 0))
	var bright := _entity(level, "light_point", "bright", Vector3(4, 2, 0))
	dim.entity_data["energy"] = 1.0
	bright.entity_data["energy"] = 3.0
	dim.entity_data["style"] = "flicker"
	bright.entity_data["style"] = "steady"
	var over := await call_tool(
		"hf_get_entities", {"filter": {"class": "light_*", "property": {"energy": {">": 2}}}}
	)
	assert_true(over.get("ok", false), str(over))
	var names: Array = over["result"]["entities"].map(func(e): return e["name"])
	assert_eq(names, ["bright"])
	var steady := await call_tool("hf_get_entities", {"filter": {"property": {"style": "steady"}}})
	assert_eq(steady["result"]["entities"].map(func(e): return e["name"]), ["bright"])
	var not_steady := await call_tool(
		"hf_get_entities", {"filter": {"property": {"style": {"!=": "steady"}}}}
	)
	assert_eq(not_steady["result"]["entities"].map(func(e): return e["name"]), ["dim"])


func test_entities_with_and_without_wiring():
	var level := make_level()
	var button := _entity(level, "func_button", "button_1", Vector3(0, 1, 0))
	_entity(level, "light_point", "lamp", Vector3(3, 2, 0))
	_entity(level, "light_point", "spare", Vector3(6, 2, 0))
	level.add_entity_output(button, "OnPressed", "lamp", "Toggle")
	var wired := await call_tool("hf_get_entities", {"filter": {"has_outputs": true}})
	assert_eq(wired["result"]["entities"].map(func(e): return e["name"]), ["button_1"])
	var fed := await call_tool("hf_get_entities", {"filter": {"has_inputs": true}})
	assert_eq(fed["result"]["entities"].map(func(e): return e["name"]), ["lamp"])
	var counted := await call_tool(
		"hf_get_entities", {"filter": {"class": "light_point"}, "count_only": true}
	)
	assert_eq(counted["result"], {"count": 2})
	var paged := await call_tool("hf_get_entities", {"limit": 1, "offset": 1})
	assert_eq(paged["result"]["returned"], 1)
	assert_eq(paged["result"]["offset"], 1)
	assert_true(paged["result"]["truncated"])
