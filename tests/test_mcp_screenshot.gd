extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_viewport_screenshot. A headless run has no picture to give, so here the
## tool has to say so cleanly; the framing that decides where the camera goes is
## plain geometry and is tested as that.

const HFMcpTools = preload("res://addons/hammerforge/mcp/hf_mcp_tools.gd")


func _corners(box: AABB) -> Array:
	var out: Array = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


func _all_in_view(box: AABB, place: Dictionary, fov: float, aspect: float) -> bool:
	var position: Vector3 = place["position"]
	var forward: Vector3 = (Vector3(place["target"]) - position).normalized()
	var half_v := deg_to_rad(fov) * 0.5
	var half_h := atan(tan(half_v) * aspect)
	var limit := minf(half_v, half_h)
	for corner in _corners(box):
		if forward.angle_to(corner - position) > limit + 0.0001:
			return false
	return true


func test_the_framing_keeps_the_whole_box_in_view():
	var cases := [
		[AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)), Vector3(0, 0, -1), 90.0, 1.0],
		[
			AABB(Vector3(10, 0, 4), Vector3(12, 4, 1)),
			Vector3(-1, -1, -1).normalized(),
			70.0,
			16.0 / 9.0
		],
		[AABB(Vector3(0, 0, 0), Vector3(1, 30, 1)), Vector3(1, 0, 0), 50.0, 0.5],
	]
	for case in cases:
		var place: Dictionary = HFMcpTools.frame_bounds(case[0], case[1], case[2], case[3])
		assert_true(_all_in_view(case[0], place, case[2], case[3]), "in view: %s" % str(case))
		assert_eq(place["target"], (case[0] as AABB).get_center())


func test_the_camera_looks_the_way_it_was_asked():
	var box := AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var place: Dictionary = HFMcpTools.frame_bounds(box, Vector3(0, 0, -1), 60.0, 1.0)
	var looking: Vector3 = (Vector3(place["target"]) - Vector3(place["position"])).normalized()
	assert_true(looking.is_equal_approx(Vector3(0, 0, -1)), str(looking))


func test_no_viewport_is_screenshot_unavailable():
	make_level()
	assert_refused(await call_tool("hf_viewport_screenshot"), "screenshot_unavailable")


func test_bad_sizes_and_focus_are_refused():
	make_level()
	assert_refused(
		await call_tool("hf_viewport_screenshot", {"width": 10}), "invalid_argument", "too narrow"
	)
	assert_refused(
		await call_tool("hf_viewport_screenshot", {"height": 5000}), "invalid_argument", "too tall"
	)
	assert_refused(
		await call_tool("hf_viewport_screenshot", {"focus": {"nothing": true}}),
		"invalid_argument",
		"a focus that names nothing"
	)
	assert_refused(
		await call_tool("hf_viewport_screenshot", {"focus": {"brush_ids": ["nope"]}}),
		"brush_not_found"
	)


func test_a_screenshot_is_a_read_that_runs_in_the_queue():
	assert_true("hf_viewport_screenshot" in HFMcpDispatcher.READ_ONLY)
	assert_false(dispatcher.runs_while_busy("hf_viewport_screenshot"))
