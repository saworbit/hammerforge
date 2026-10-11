extends "res://tests/mcp/mcp_dispatcher_case.gd"

## The bridge's read tools: hf_get_brushes and hf_get_materials. Neither may
## change the level or the undo history.


func test_brushes_lists_what_was_placed_in_order_with_faces():
	var level := make_level()
	var first := await place_box([0, 1, 0])
	var second := await place_box([6, 1, 0])
	var before := snapshot(level)
	var r := await call_tool("hf_get_brushes")
	assert_true(r["ok"], str(r))
	var listed: Array = r["result"]["brushes"]
	assert_eq(listed.size(), 2)
	assert_eq(listed[0]["brush_id"], first)
	assert_eq(listed[1]["brush_id"], second)
	assert_eq((listed[0]["faces"] as Array).size(), 6)
	assert_eq(int(r["result"]["total"]), 2)
	assert_false(r["result"]["truncated"])
	assert_eq_deep(snapshot(level), before)


func test_limit_truncates_and_says_so():
	make_level()
	await place_box([0, 1, 0])
	await place_box([6, 1, 0])
	var r := await call_tool("hf_get_brushes", {"limit": 1})
	assert_eq((r["result"]["brushes"] as Array).size(), 1)
	assert_eq(int(r["result"]["total"]), 2)
	assert_true(r["result"]["truncated"])


func test_faces_can_be_left_out():
	make_level()
	await place_box()
	var r := await call_tool("hf_get_brushes", {"include_faces": false})
	assert_false((r["result"]["brushes"][0] as Dictionary).has("faces"))


func test_bounds_keep_only_brushes_that_overlap():
	make_level()
	var near := await place_box([0, 1, 0])
	await place_box([50, 1, 0])
	var r := await call_tool("hf_get_brushes", {"bounds": {"min": [-5, -5, -5], "max": [5, 5, 5]}})
	var listed: Array = r["result"]["brushes"]
	assert_eq(listed.size(), 1)
	assert_eq(listed[0]["brush_id"], near)


func test_brush_ids_pick_and_name_the_missing():
	make_level()
	var kept := await place_box()
	await place_box([6, 1, 0])
	var r := await call_tool("hf_get_brushes", {"brush_ids": [kept, "made_up"]})
	var listed: Array = r["result"]["brushes"]
	assert_eq(listed.size(), 1)
	assert_eq(listed[0]["brush_id"], kept)
	assert_eq(r["result"]["missing"], ["made_up"])


func test_brush_filters_refuse_bad_values():
	make_level()
	assert_refused(await call_tool("hf_get_brushes", {"limit": 0}), "invalid_argument", "limit 0")
	assert_refused(
		await call_tool("hf_get_brushes", {"limit": 5000}), "invalid_argument", "limit 5000"
	)
	assert_refused(await call_tool("hf_get_brushes", {"brush_ids": "x"}), "invalid_argument", "ids")
	assert_refused(
		await call_tool("hf_get_brushes", {"bounds": {"min": [0, 0, 0]}}),
		"invalid_argument",
		"bounds"
	)


func test_reads_need_a_level():
	make_scene()
	assert_refused(await call_tool("hf_get_brushes"), "no_level")
	assert_refused(await call_tool("hf_get_materials"), "no_level")


func test_reads_check_the_target_too():
	make_level()
	assert_refused(
		await call_tool("hf_get_brushes", {}, {"expect_target": "1:2:3"}), "target_changed"
	)


func test_materials_lists_the_palette_by_path():
	var level := make_level_with_palette()
	var before := snapshot(level)
	var r := await call_tool("hf_get_materials")
	assert_true(r["ok"], str(r))
	var listed: Array = r["result"]["materials"]
	assert_eq(listed.size(), level.get_materials().size())
	assert_gt(listed.size(), 0, "the prototypes are in it")
	var first: Dictionary = listed[0]
	assert_eq(int(first["slot"]), 0)
	assert_true(
		str(first["id"]).begins_with("res://addons/hammerforge/textures/prototypes/materials/"),
		str(first)
	)
	assert_ne(str(first["name"]), "")
	assert_eq_deep(snapshot(level), before)


func test_reads_ignore_an_operation_id():
	make_level()
	var a := await call_tool("hf_get_materials", {}, {"operation_id": "same"})
	var b := await call_tool("hf_get_brushes", {}, {"operation_id": "same"})
	assert_true(a["ok"])
	assert_true(b["ok"], "a read never meets the change cache: %s" % str(b))
