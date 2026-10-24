extends GutTest

## The Clip tool: a cut along a plane placed with two or three points (#1711).

const HFClipTool = preload("res://addons/hammerforge/hf_clip_tool.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")

var root: LevelRoot
var tool: HFClipTool
var selected: Array = []


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	tool = HFClipTool.new()
	tool.root = root
	tool.selection_source = func() -> Array: return selected
	selected = []


func after_each() -> void:
	tool.deactivate()
	tool = null


## A 4 x 4 x 4 box standing on the floor, centred on `x`.
func _box(brush_id: String, x := 0.0) -> Node:
	var brush = root.create_brush_from_info(
		{"brush_id": brush_id, "size": Vector3(4, 4, 4), "center": Vector3(x, 2, 0)}
	)
	selected.append(brush)
	return brush


func _brushes() -> Array:
	return root.draft_brushes_node.get_children()


func _volume(brush: Node) -> float:
	var six := 0.0
	for face in brush.get_faces():
		var verts: PackedVector3Array = face.local_verts
		for i in range(1, verts.size() - 1):
			six += verts[0].dot(verts[i].cross(verts[i + 1]))
	return absf(six) / 6.0


func _z_range(brush: Node) -> Vector2:
	var lo := INF
	var hi := -INF
	for face in brush.get_faces():
		for v in face.local_verts:
			var world: Vector3 = brush.global_transform * v
			lo = minf(lo, world.z)
			hi = maxf(hi, world.z)
	return Vector2(snappedf(lo, 0.001), snappedf(hi, 0.001))


## Two points along X at z = 1, in a top view.
func _cut_at_z_one() -> void:
	tool.set_view_axis(Vector3.UP)
	tool.add_point(Vector3(-4, 4, 1))
	tool.add_point(Vector3(4, 4, 1))


func test_a_top_view_looks_down_y():
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.look_at_from_position(Vector3(0.5, 20, 0.5), Vector3.ZERO)
	assert_eq(HFClipTool.view_axis_of(camera), Vector3.UP)
	camera.look_at_from_position(Vector3(0, 1, 20), Vector3.ZERO)
	assert_eq(HFClipTool.view_axis_of(camera), Vector3.BACK, "a front view looks down Z")


func test_two_points_in_a_top_view_cut_upright_through_them():
	_box("b")
	_cut_at_z_one()
	var cut: Plane = tool.plane()
	assert_almost_eq(absf(cut.normal.z), 1.0, 0.0001, "an upright cut across Z")
	assert_true(tool.apply())
	var ranges := _brushes().map(func(brush): return _z_range(brush))
	ranges.sort()
	assert_eq(ranges, [Vector2(-2, 1), Vector2(1, 2)])


func test_three_points_cut_along_the_plane_through_them():
	_box("b")
	tool.set_setting("keep", HFClipTool.KEEP_BACK)
	# One on each of the three edges round the top front right corner.
	tool.add_point(Vector3(1, 4, 2))
	tool.add_point(Vector3(2, 3, 2))
	tool.add_point(Vector3(2, 4, 1))
	assert_true(tool.apply())
	assert_eq(_brushes().size(), 1, "the corner goes")
	assert_almost_eq(_volume(_brushes()[0]), 64.0 - 1.0 / 6.0, 0.001)


func test_front_back_and_both_keep_the_right_pieces():
	for case in [
		[HFClipTool.KEEP_FRONT, [Vector2(1, 2)]],
		[HFClipTool.KEEP_BACK, [Vector2(-2, 1)]],
		[HFClipTool.KEEP_BOTH, [Vector2(-2, 1), Vector2(1, 2)]],
	]:
		for brush in _brushes():
			root.delete_brushes_by_id([str(brush.brush_id)])
		selected = []
		_box("b")
		tool.set_setting("keep", case[0])
		_cut_at_z_one()
		var shown: Array = tool.preview_pieces().map(func(piece): return piece["kept"])
		assert_eq(shown.count(true), (case[1] as Array).size(), "the preview keeps the same")
		assert_true(tool.apply())
		var ranges := _brushes().map(func(brush): return _z_range(brush))
		ranges.sort()
		assert_eq(ranges, case[1], "keep %s" % HFClipTool.KEEP_OPTIONS[case[0]])


func test_tab_steps_the_side_and_backspace_takes_a_point_off():
	_cut_at_z_one()
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	tool.handle_keyboard(tab)
	assert_eq(tool.keep(), HFClipTool.KEEP_FRONT)
	var back := InputEventKey.new()
	back.keycode = KEY_BACKSPACE
	back.pressed = true
	tool.handle_keyboard(back)
	assert_eq(tool.points().size(), 1)
	assert_null(tool.plane(), "one point is no cut")


func test_moving_a_point_moves_the_cut():
	_box("b")
	_cut_at_z_one()
	tool.move_point(1, Vector3(4, 4, -1))
	var cut: Plane = tool.plane()
	assert_true(cut.has_point(Vector3(4, 4, -1)), "through the moved point")
	assert_true(cut.has_point(Vector3(-4, 4, 1)), "and the one that stayed")
	assert_true(tool.apply())
	assert_eq(_brushes().size(), 2)


func test_every_selected_brush_the_plane_crosses_is_cut_in_one_step():
	var undo := UndoStandIn.new()
	tool.undo_redo = undo
	_box("a", -10.0)
	_box("b", 10.0)
	var far = _box("far", 0.0)
	far.global_position = Vector3(0, 2, 40)
	_cut_at_z_one()
	assert_eq(tool.targets(), ["a", "b"], "the one it misses is no target")
	assert_true(tool.apply())
	assert_eq(_brushes().size(), 5, "two cut in two, one left")
	assert_not_null(root.find_brush_by_id("far"), "the missed one is the same brush")
	assert_eq(undo.scene_history.get_history_count(), 1, "one step")
	assert_eq(undo.scene_history.get_current_action_name(), "Clip")
	undo.scene_history.undo()
	assert_eq(_brushes().size(), 3)
	for brush_id in ["a", "b", "far"]:
		assert_not_null(root.find_brush_by_id(brush_id), "%s is back" % brush_id)
	undo.free_histories()


func test_every_piece_is_a_closed_solid_turned_out():
	_box("b")
	tool.add_point(Vector3(1, 4, 2))
	tool.add_point(Vector3(2, 0.5, 2))
	tool.add_point(Vector3(-1, 4, -2))
	assert_true(tool.apply())
	assert_eq(_brushes().size(), 2)
	for brush in _brushes():
		var faces: Array = brush.get_faces()
		assert_eq(SolidChecks.open_edge_count(faces), 0, "closed")
		assert_eq(SolidChecks.outward_ratio(faces), 1.0, "turned out")


func test_the_new_faces_take_the_first_point_s_material():
	_box("b")
	tool.set_view_axis(Vector3.UP)
	tool.add_point(Vector3(-4, 4, 1), 2)
	tool.add_point(Vector3(4, 4, 1))
	assert_true(tool.apply())
	for brush in _brushes():
		var on_cut: Array = brush.get_faces().filter(func(face): return _on_z(brush, face, 1.0))
		assert_eq(on_cut.size(), 1, "one cap a piece")
		if not on_cut.is_empty():
			assert_eq(on_cut[0].material_idx, 2)


func _on_z(brush: Node, face, z: float) -> bool:
	for v in face.local_verts:
		if absf((brush.global_transform * v).z - z) > 0.001:
			return false
	return true


func _mouse(camera: Camera3D, at: Vector3, pressed: Variant = null) -> int:
	var screen := camera.unproject_position(at)
	if pressed == null:
		var motion := InputEventMouseMotion.new()
		motion.position = screen
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		return tool.handle_input(motion, camera, screen)
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = screen
	return tool.handle_input(button, camera, screen)


func test_a_drag_places_two_points_and_a_point_can_be_picked_up():
	root.grid_snap = 1.0
	_box("b")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0, 9, 0.001), Vector3.ZERO)
	await get_tree().process_frame
	assert_eq(_mouse(camera, Vector3(-1, 4, 1), true), EditorPlugin.AFTER_GUI_INPUT_STOP)
	_mouse(camera, Vector3(0, 4, 1))
	_mouse(camera, Vector3(1, 4, 1))
	_mouse(camera, Vector3(1, 4, 1), false)
	var placed := tool.points()
	assert_eq(placed.size(), 2, "the press and the release")
	if placed.size() == 2:
		assert_almost_eq(placed[0], Vector3(-1, 4, 1), Vector3.ONE * 0.01)
		assert_almost_eq(placed[1], Vector3(1, 4, 1), Vector3.ONE * 0.01)
	# Pick the second point up and carry it, and the cut follows.
	_mouse(camera, Vector3(1, 4, 1), true)
	_mouse(camera, Vector3(1, 4, -1))
	_mouse(camera, Vector3(1, 4, -1), false)
	assert_eq(tool.points().size(), 2, "a picked up point is moved, not added")
	assert_almost_eq(tool.points()[1], Vector3(1, 4, -1), Vector3.ONE * 0.01)
	var cut: Plane = tool.plane()
	assert_true(cut.has_point(Vector3(1, 4, -1)))
	camera.free()


func test_c_in_the_editor_starts_the_tool_on_the_selection():
	var rig = load("res://tests/support/plugin_rig.gd").new()
	await rig.bring_up(self)
	assert_not_null(rig.plugin, rig.error())
	if rig.plugin == null:
		return
	var level = await rig.make_level()
	var box = rig.box(level, "pick", Vector3(0, 2, 0))
	rig.select([box])
	assert_eq(rig.forward(rig.key(KEY_C)), EditorPlugin.AFTER_GUI_INPUT_STOP)
	var active = rig.plugin._tool_registry.get_active_tool()
	assert_true(active is HFClipTool, "C is the Clip tool")
	if active is HFClipTool:
		assert_true(active.selection_source.is_valid(), "it reads the editor's selection")
		assert_eq(active.selection_source.call(), [box])
	await rig.take_down()


func test_a_locked_brush_is_not_cut():
	var brush = _box("b")
	root.visgroup_system.create_visgroup("Walls")
	root.visgroup_system.add_to_visgroup(brush, "Walls")
	root.visgroup_system.set_visgroup_locked("Walls", true)
	_cut_at_z_one()
	assert_eq(tool.targets(), [])
	assert_false(tool.apply())
	assert_eq(_brushes().size(), 1)


func test_nothing_selected_cuts_nothing_and_says_so():
	_box("b")
	selected = []
	_cut_at_z_one()
	watch_signals(root)
	assert_false(tool.apply())
	assert_signal_emitted(root, "user_message")
	assert_eq(_brushes().size(), 1)
