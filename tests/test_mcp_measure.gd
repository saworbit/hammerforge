extends "res://tests/mcp/mcp_dispatcher_case.gd"
## hf_measure (#1649): the small questions an agent needs answered, such as
## whether the ramp touches the floor or how wide the doorway is, in one answer
## rather than face lists and sums.

const HFSolidMeasureType = preload("res://addons/hammerforge/hf_solid_measure.gd")


func measure(items: Array) -> Dictionary:
	return await call_tool("hf_measure", {"items": items})


func _box(position: Array, size: Array, rotation := [0, 0, 0]) -> String:
	var r := await call_tool(
		"hf_place_brush",
		{"size": size, "position": position, "rotation_degrees": rotation, "snap": false}
	)
	assert_true(r.get("ok", false), "place: %s" % str(r))
	return str(r["result"]["brush"]["brush_id"]) if r.get("ok", false) else ""


func _pair(items: Array) -> Dictionary:
	var r := await measure(items)
	assert_true(r.get("ok", false), str(r))
	return r.get("result", {}).get("pair", {})


func test_two_boxes_that_share_a_face_have_a_gap_of_nothing():
	make_level()
	var a := await _box([0, 1, 0], [2, 2, 2])
	var b := await _box([2, 1, 0], [2, 2, 2])
	var pair := await _pair([a, b])
	assert_almost_eq(float(pair.get("gap", 1.0)), 0.0, 0.0001)
	assert_almost_eq(float(pair.get("centre_distance", 0.0)), 2.0, 0.0001)
	assert_eq(pair.get("axis_gaps"), [0.0, -2.0, -2.0], "touching on x, overlapping on y and z")


func test_two_boxes_that_overlap_by_a_quarter_have_a_gap_of_minus_a_quarter():
	make_level()
	var a := await _box([0, 1, 0], [2, 2, 2])
	var b := await _box([1.75, 1, 0], [2, 2, 2])
	assert_almost_eq(float((await _pair([a, b])).get("gap", 0.0)), -0.25, 0.0001)


func test_two_boxes_corner_to_corner_measure_the_diagonal_between_corners():
	make_level()
	var a := await _box([0, 1, 0], [2, 2, 2])
	var b := await _box([3, 4, 3], [2, 2, 2])
	assert_almost_eq(float((await _pair([a, b])).get("gap", 0.0)), sqrt(3.0), 0.0001)


func test_volumes_match_the_formula():
	make_level()
	var box := await _box([0, 1, 0], [2, 3, 4])
	var turned := await _box([10, 2, 0], [2, 3, 4], [0, 30, 15])
	var r := await call_tool(
		"hf_place_brush",
		{
			"shape": "cylinder",
			"size": [2, 3, 2],
			"position": [20, 1.5, 0],
			"sides": 16,
			"snap": false
		}
	)
	assert_true(r.get("ok", false), str(r))
	var cylinder := str(r["result"]["brush"]["brush_id"])
	var m := await measure([box, turned, cylinder])
	assert_true(m.get("ok", false), str(m))
	var items: Array = m.get("result", {}).get("items", [])
	assert_almost_eq(float(items[0]["volume"]), 24.0, 0.0001, "a box")
	assert_almost_eq(float(items[1]["volume"]), 24.0, 0.0001, "the same box turned")
	# A 16 sided prism round a circle of radius 1, 3 tall, as the brush builds it.
	var faces: Array = HFSolidMeasureType.world_faces(brush_node(level_of(), cylinder))
	var corner_radius := 0.0
	for face in faces:
		for point in face:
			corner_radius = maxf(corner_radius, Vector2(point.x - 20.0, point.z).length())
	var prism := 8.0 * corner_radius * corner_radius * sin(TAU / 16.0) * 3.0
	assert_almost_eq(float(items[2]["volume"]), prism, 0.0001, "a 16 sided cylinder")
	assert_almost_eq(float(items[2]["face_count"]), 18.0, 0.0, "16 sides, a top and a bottom")
	var together: Dictionary = m["result"].get("together", {})
	assert_almost_eq(float(together.get("volume", 0.0)), 48.0 + prism, 0.0001, "all three")


func test_two_faces_at_right_angles_measure_ninety_degrees():
	make_level()
	var a := await _box([0, 1, 0], [2, 2, 2])
	var pair := await _pair([{"brush_id": a, "face": "+y"}, {"brush_id": a, "face": "+x"}])
	assert_almost_eq(float(pair.get("angle_degrees", 0.0)), 90.0, 0.0001)
	assert_false(pair.get("coplanar", true))
	assert_almost_eq(float(pair.get("gap", 1.0)), 0.0, 0.0001, "they share an edge")
	var b := await _box([2, 1, 0], [2, 2, 2])
	pair = await _pair([{"brush_id": a, "face": "+y"}, {"brush_id": b, "face": "+y"}])
	assert_almost_eq(float(pair.get("angle_degrees", 1.0)), 0.0, 0.0001)
	assert_true(pair.get("coplanar", false), "two tops level with each other")


func test_a_face_is_described_by_its_area_centre_and_normal():
	make_level()
	var a := await _box([0, 1, 0], [2, 2, 4])
	var r := await measure([{"brush_id": a, "face": "+y"}])
	assert_true(r.get("ok", false), str(r))
	var face: Dictionary = r["result"]["items"][0]
	assert_almost_eq(float(face["area"]), 8.0, 0.0001)
	assert_eq(face["centre"], [0.0, 2.0, 0.0])
	assert_eq(face["normal"], [0.0, 1.0, 0.0])


func test_a_point_inside_a_brush_has_a_negative_gap_and_one_outside_its_distance():
	make_level()
	var a := await _box([0, 1, 0], [2, 2, 2])
	assert_almost_eq(float((await _pair([a, [0, 1.5, 0]])).get("gap", 0.0)), -0.5, 0.0001)
	assert_almost_eq(float((await _pair([[0, 5, 0], a])).get("gap", 0.0)), 3.0, 0.0001)
	assert_almost_eq(float((await _pair([[0, 0, 0], [3, 4, 0]])).get("gap", 0.0)), 5.0, 0.0001)


func test_the_answer_for_two_brushes_is_small():
	make_level()
	var a := await _box([0, 1, 0], [2, 2, 2])
	var b := await _box([5, 1, 0], [2, 2, 2])
	var r := await measure([a, b])
	assert_lt(JSON.stringify(r).length(), 1500, "under 1,500 bytes")


func test_bad_items_are_refused_with_the_field_named():
	make_level()
	var a := await _box([0, 1, 0], [2, 2, 2])
	var cases := [
		[[], "items"],
		[[a, "no_such_brush"], "items[1]"],
		[[a, {"brush_id": a, "face": 99}], "items[1]"],
		[[a, [1, 2]], "items[1].point"],
		[[a, {"entity": "Entities/nobody"}], "items[1]"],
		[[a, 7], "items[1].item"],
	]
	for case in cases:
		var r := await measure(case[0])
		assert_false(r.get("ok", true), "refused: %s" % str(case[0]))
		var param := str(r.get("error", {}).get("details", {}).get("param", ""))
		assert_true(param.begins_with(case[1]), "%s names %s, not %s" % [case[0], case[1], param])


func test_it_changes_nothing():
	var level := make_level()
	var a := await _box([0, 1, 0], [2, 2, 2])
	var before := snapshot(level)
	await measure([a, [0, 0, 0]])
	assert_eq(snapshot(level), before)


func level_of() -> LevelRoot:
	return host.scene.get_node("LevelRoot") as LevelRoot
