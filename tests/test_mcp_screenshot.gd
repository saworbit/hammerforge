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


## How far across the frame each corner lands, as a fraction of the way from the
## centre to the edge: 1 is on the edge. The frame is a rectangle, fov tall.
func _reach(box: AABB, place: Dictionary, fov: float, aspect: float) -> float:
	var position: Vector3 = place["position"]
	var forward: Vector3 = (Vector3(place["target"]) - position).normalized()
	var up_hint := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var basis := Basis.looking_at(forward, up_hint)
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var tan_h := tan_v * aspect
	var worst := 0.0
	for corner in _corners(box):
		var local: Vector3 = basis.inverse() * (corner - position)
		var depth := -local.z
		if depth <= 0.0:
			return INF
		worst = maxf(worst, maxf(absf(local.x) / (depth * tan_h), absf(local.y) / (depth * tan_v)))
	return worst


func _all_in_view(box: AABB, place: Dictionary, fov: float, aspect: float) -> bool:
	return _reach(box, place, fov, aspect) <= 1.0001


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


func test_the_framing_fills_the_frame():
	# It backed off until a sphere round the box was in view, so a castle filled
	# about 40 percent of a 16:9 frame (#1040).
	var cases := [
		[AABB(Vector3(-20, 0, -10), Vector3(40, 12, 20)), Vector3(-1, -0.6, -1), 70.0, 16.0 / 9.0],
		[AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)), Vector3(0, 0, -1), 60.0, 1.0],
	]
	for case in cases:
		var place: Dictionary = HFMcpTools.frame_bounds(case[0], case[1], case[2], case[3])
		assert_between(_reach(case[0], place, case[2], case[3]), 0.85, 1.0001, str(case))


func test_a_view_says_where_the_camera_looks_from():
	var view := HFMcpTools.view_direction
	assert_eq(view.call("+x")["direction"], Vector3(-1, 0, 0), "from +x it looks toward -x")
	assert_eq(view.call("top")["direction"], Vector3(0, -1, 0), "from above, down")
	assert_eq(view.call("-z")["direction"], Vector3(0, 0, 1))
	assert_true(
		(view.call([0, 3, 4])["direction"] as Vector3).is_equal_approx(Vector3(0, -0.6, -0.8))
	)
	assert_false(view.call("sideways")["ok"])
	assert_false(view.call([0, 0, 0])["ok"], "no direction at all")


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
	var box := {"min": [0, 0, 0], "max": [1, 1, 1]}
	assert_refused(
		await call_tool(
			"hf_viewport_screenshot", {"focus": {"bounds": box, "look_from": "sideways"}}
		),
		"invalid_argument",
		"a side that is not one"
	)
	assert_refused(
		await call_tool(
			"hf_viewport_screenshot",
			{"focus": {"bounds": box}, "camera": {"position": [0, 2, 5], "look_at": [0, 0, 0]}}
		),
		"invalid_argument",
		"a focus and a camera both"
	)
	assert_refused(
		await call_tool(
			"hf_viewport_screenshot", {"camera": {"position": [1, 2, 3], "look_at": [1, 2, 3]}}
		),
		"invalid_argument",
		"a camera looking at itself"
	)
	assert_refused(
		await call_tool("hf_viewport_screenshot", {"hide": ["nope"], "focus": {"bounds": box}}),
		"brush_not_found"
	)
	assert_refused(
		await call_tool("hf_viewport_screenshot", {"hide_cuts": true}),
		"invalid_argument",
		"hiding needs a shot of its own: the editor's view is the editor's"
	)


func test_a_screenshot_is_a_read_that_runs_in_the_queue():
	assert_true("hf_viewport_screenshot" in HFMcpDispatcher.READ_ONLY)
	assert_false(dispatcher.runs_while_busy("hf_viewport_screenshot"))


## A host with a viewport, in a run that cannot draw: the real frame_drawn().
class ViewportHost:
	extends "res://tests/mcp/mcp_test_host.gd"

	var viewport: Viewport = null

	func viewport_3d() -> Viewport:
		return viewport


func test_a_viewport_that_cannot_draw_answers_at_once_and_frees_the_queue():
	make_level()
	var drawing_host := ViewportHost.new()
	drawing_host.undo = undo
	drawing_host.tree = get_tree()
	drawing_host.scene = host.scene
	drawing_host.viewport = get_tree().root
	dispatcher.shutdown()
	dispatcher = HFMcpDispatcher.new(drawing_host)
	var started := Time.get_ticks_msec()
	var plain := await call_tool("hf_viewport_screenshot")
	var framed := await call_tool(
		"hf_viewport_screenshot", {"focus": {"bounds": {"min": [0, 0, 0], "max": [1, 1, 1]}}}
	)
	assert_refused(plain, "screenshot_unavailable", "headless, plain")
	assert_refused(framed, "screenshot_unavailable", "headless, framed")
	assert_lt(Time.get_ticks_msec() - started, 5000, "no wait for a frame that never comes")
	var after := await call_tool("hf_get_status")
	assert_true(after["ok"])


func test_a_plain_shot_shrinks_to_fit_and_never_grows():
	var fit := HFMcpDispatcher.fit_size
	assert_eq(fit.call(Vector2i(1920, 1080), 1280, 720), Vector2i(1280, 720))
	assert_eq(fit.call(Vector2i(1920, 1080), 640, 640), Vector2i(640, 360), "its own shape")
	assert_eq(fit.call(Vector2i(800, 600), 1280, 720), Vector2i(800, 600), "not upscaled")
	assert_eq(fit.call(Vector2i(4000, 10), 64, 64), Vector2i(64, 1), "never zero")


func test_hiding_for_a_shot_moves_only_the_drawing_and_puts_it_back():
	var level := make_level()
	var id := await place_box()
	var brush := brush_node(level, id)
	var before: int = brush.mesh_instance.layers
	var saved: Array = HFMcpTools.hide_from_shot([brush])
	assert_eq(
		brush.mesh_instance.layers, HFMcpTools.SHOT_HIDDEN_LAYERS, "on a layer the shot skips"
	)
	assert_true(brush.visible, "the brush itself is untouched")
	HFMcpTools.unhide(saved)
	assert_eq(brush.mesh_instance.layers, before)


## A host that cannot draw either, but notes what the brush drew on when asked to.
class RecordingHost:
	extends ViewportHost

	var watched: Array = []
	var seen: Array = []

	func frame_drawn() -> bool:
		for drawing in watched:
			seen.append((drawing as VisualInstance3D).layers)
		return false


func test_a_hiding_camera_shot_hides_while_it_draws_and_puts_everything_back():
	# A camera with no focus fell through to the plain shot, which is the editor's
	# own view; the hide never happened, and the picture had the grid in it.
	var level := make_level()
	var id := await place_box()
	var brush := brush_node(level, id)
	var before: int = brush.mesh_instance.layers
	var recording := RecordingHost.new()
	recording.undo = undo
	recording.tree = get_tree()
	recording.scene = host.scene
	recording.viewport = get_tree().root
	recording.watched = [brush.mesh_instance]
	dispatcher.shutdown()
	dispatcher = HFMcpDispatcher.new(recording)
	var shot := await call_tool(
		"hf_viewport_screenshot",
		{"camera": {"position": [0, 2, 6], "look_at": [0, 1, 0]}, "hide": [id]}
	)
	assert_refused(shot, "screenshot_unavailable", "headless")
	assert_eq(recording.seen, [HFMcpTools.SHOT_HIDDEN_LAYERS], "left out while it drew")
	assert_eq(brush.mesh_instance.layers, before, "and drawn again after")


func test_hiding_a_cut_hides_its_outline_too():
	var level := make_level()
	var r := await call_tool(
		"hf_place_brush", {"size": [1, 2, 1], "position": [0, 1, 0], "operation": "subtract"}
	)
	var cut := brush_node(level, r["result"]["brush"]["brush_id"])
	var drawings: Array = []
	for child in cut.get_children(true):
		if child is VisualInstance3D:
			drawings.append(child)
	assert_gt(drawings.size(), 1, "fixture: a cut draws a mesh and an overlay")
	var saved: Array = HFMcpTools.hide_from_shot([cut])
	for drawing in drawings:
		assert_eq((drawing as VisualInstance3D).layers, HFMcpTools.SHOT_HIDDEN_LAYERS, str(drawing))
	HFMcpTools.unhide(saved)
	for drawing in drawings:
		assert_ne((drawing as VisualInstance3D).layers, HFMcpTools.SHOT_HIDDEN_LAYERS)
