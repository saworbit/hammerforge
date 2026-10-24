extends GutTest
## Shift with an Extrude tool moves the face itself, on any brush (#1712): a box
## grows and keeps its handles, a clipped brush's face moves along its normal, the
## faces in its plane of the other selected brushes go with it, and a drag that
## would turn a brush inside out stops where it still holds. One undo step.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFConvexClip = preload("res://addons/hammerforge/hf_convex_clip.gd")
const HFFacePush = preload("res://addons/hammerforge/hf_face_push.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()
var _grid_before := 0.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _level() -> Node:
	var level = await rig.make_level()
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(1.0)
	rig.plugin._hotkey_palette.action_invoked.emit("tool_extrude_up")
	return level


func _leave(level: Node) -> void:
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await rig.leave_level(level)
	rig.plugin.dock._apply_grid_snap(_grid_before)


func _press(point: Vector3, shift := true) -> int:
	var event := PluginRig.click(MOUSE_BUTTON_LEFT, true, rig.camera.unproject_position(point))
	event.shift_pressed = shift
	return rig.forward(event)


func _release(point: Vector3) -> int:
	return rig.forward(
		PluginRig.click(MOUSE_BUTTON_LEFT, false, rig.camera.unproject_position(point))
	)


## Type a depth and Enter, as the HUD takes one.
func _type(text: String) -> void:
	for ch in text:
		rig.forward(PluginRig.key(KEY_PERIOD if ch == "." else KEY_0 + int(ch)))
	rig.forward(PluginRig.key(KEY_ENTER))


func _face_facing(brush: DraftBrush, normal: Vector3) -> int:
	for i in brush.faces.size():
		if HFConvexClip.face_plane(brush.faces[i]).normal.dot(normal) > 0.999:
			return i
	return -1


func test_shift_on_a_box_s_top_grows_it_and_keeps_it_a_box() -> void:
	var level = await _level()
	var box: DraftBrush = rig.box(level, "a", Vector3(0, 0, 0), Vector3(4, 4, 4))
	assert_eq(_press(Vector3(0, 2, 0)), STOP, "Shift and a press on the top face starts it")
	assert_true(level.extrude_tool.pushing, "a push, not a stamp")
	_type("2")
	await rig.frame()
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "no new brush")
	assert_eq(box.shape, DraftBrush.BrushShape.BOX, "a box stays a box")
	assert_almost_eq(box.size, Vector3(4, 6, 4), Vector3.ONE * 0.001, "2 taller")
	assert_almost_eq(box.global_position, Vector3(0, 1, 0), Vector3.ONE * 0.001, "upward")
	assert_true(rig.undo().press_undo(), "one undo step")
	# An undo can put the brush back as a node of its own.
	var undone: DraftBrush = level.brush_system.find_brush_by_id("a")
	assert_not_null(undone)
	if undone:
		assert_almost_eq(undone.size, Vector3(4, 4, 4), Vector3.ONE * 0.001, "and it is undone")
		assert_almost_eq(undone.global_position, Vector3.ZERO, Vector3.ONE * 0.001)
	_release(Vector3(0, 2, 0))
	await _leave(level)


func test_a_clipped_brush_s_top_moves_and_it_stays_one_solid() -> void:
	var level = await _level()
	var brush: DraftBrush = rig.box(level, "a", Vector3(0, 0, 0), Vector3(4, 4, 4))
	var slope := Plane(
		Vector3(1, 1, 0).normalized(), Vector3(1, 1, 0).normalized().dot(Vector3(2, 1, 0))
	)
	var faces: Array[FaceData] = []
	for face in HFConvexClip.split(brush.faces, slope)["back"]:
		faces.append(face)
	brush.shape = DraftBrush.BrushShape.CUSTOM
	brush.faces = faces
	brush.rebuild_preview()
	var count := brush.faces.size()
	var top := _face_facing(brush, Vector3.UP)
	var before := HFFacePush.world_plane(brush, top)
	assert_eq(_press(Vector3(-1, 2, 0)), STOP)
	_type("1")
	await rig.frame()
	assert_eq(brush.shape, DraftBrush.BrushShape.CUSTOM)
	assert_eq(brush.faces.size(), count, "the same faces")
	assert_almost_eq(HFFacePush.world_plane(brush, top).d - before.d, 1.0, 0.001, "the top is 1 up")
	assert_eq(SolidChecks.open_edge_count(brush.faces), 0, "closed")
	assert_true(SolidChecks.is_convex(brush.faces), "convex")
	_release(Vector3(-1, 2, 0))
	await _leave(level)


func test_the_faces_in_its_plane_of_the_selected_wall_move_together() -> void:
	var level = await _level()
	var walls: Array = []
	for i in 3:
		walls.append(
			rig.box(level, "w%d" % i, Vector3(float(i) * 2.0 - 2.0, 0, 0), Vector3(2, 4, 0.5))
		)
	rig.select(walls)
	await rig.frame()
	assert_eq(_press(Vector3(0, 2, 0)), STOP, "the middle wall's top")
	_type("1")
	await rig.frame()
	for wall in walls:
		assert_almost_eq(wall.size.y, 5.0, 0.001, "%s is 1 taller" % wall.name)
	_release(Vector3(0, 2, 0))
	await _leave(level)


func test_a_drag_that_would_turn_it_inside_out_stops_and_says_so() -> void:
	var level = await _level()
	var box: DraftBrush = rig.box(level, "a", Vector3(0, 0, 0), Vector3(4, 4, 4))
	_press(Vector3(0, 2, 0))
	var at := rig.camera.unproject_position(Vector3(0, 2, 0))
	rig.forward(PluginRig.motion(at + Vector2(0, 400), MOUSE_BUTTON_MASK_LEFT))
	assert_gt(box.size.y, 0.0, "it never turns inside out")
	assert_lt(box.size.y, 4.0, "but it went down")
	assert_string_contains(level.extrude_tool.push_note, "Stopped", "and the HUD says why")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, at + Vector2(0, 400)))
	await _leave(level)


func test_escape_puts_the_face_back() -> void:
	var level = await _level()
	var box: DraftBrush = rig.box(level, "a", Vector3(0, 0, 0), Vector3(4, 4, 4))
	_press(Vector3(0, 2, 0))
	var at := rig.camera.unproject_position(Vector3(0, 2, 0))
	rig.forward(PluginRig.motion(at - Vector2(0, 100), MOUSE_BUTTON_MASK_LEFT))
	assert_gt(box.size.y, 4.0, "fixture: the drag moved it")
	await rig.escape_to_idle(level)
	assert_almost_eq(box.size, Vector3(4, 4, 4), Vector3.ONE * 0.001, "back as it was")
	assert_false(level.extrude_tool.pushing)
	await _leave(level)


func test_without_shift_the_tool_still_stamps_a_brush() -> void:
	var level = await _level()
	rig.box(level, "a", Vector3(0, 0, 0), Vector3(4, 4, 4))
	assert_eq(_press(Vector3(0, 2, 0), false), STOP)
	assert_false(level.extrude_tool.pushing)
	_type("2")
	await rig.frame()
	assert_eq(level.draft_brushes_node.get_child_count(), 2, "a stamped brush")
	_release(Vector3(0, 2, 0))
	await _leave(level)
