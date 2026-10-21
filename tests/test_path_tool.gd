extends GutTest

const HFPathTool = preload("res://addons/hammerforge/hf_path_tool.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")


class PlacementRoot:
	extends Node3D

	var raycast_result: Dictionary = {}
	var snap_calls := 0
	var raycast_calls := 0
	var y_plane_calls := 0

	func _snap_point(point: Vector3, _exclude_ids: Array = []) -> Vector3:
		snap_calls += 1
		return point.snapped(Vector3(4, 4, 4))

	func _raycast(_camera: Camera3D, _mouse_pos: Vector2) -> Dictionary:
		raycast_calls += 1
		return raycast_result

	func screen_ray_to_y_plane(_camera: Camera3D, _mouse_pos: Vector2, y: float) -> Vector3:
		y_plane_calls += 1
		return Vector3(0, y, 0)


func test_placement_uses_level_root_snap_and_raycast():
	# The tool has no raycast of its own any more. A click has to reach
	# LevelRoot for picking, and LevelRoot for snapping.
	var tool = HFPathTool.new()
	var root := PlacementRoot.new()
	var camera := Camera3D.new()
	tool.root = root
	root.raycast_result = {"position": Vector3(3, 7, 9)}
	assert_eq(tool.snap_point(Vector3(3, 7, 9)), Vector3(4, 8, 8))
	assert_eq(tool._handle_click(camera, Vector2(20, 30)), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(root.raycast_calls, 1, "LevelRoot owns visual and physics picking")
	assert_eq(tool._waypoints.size(), 1, "The picked point becomes the first point")
	assert_eq(tool._waypoints[0], Vector3(4, 8, 8), "and it is snapped by LevelRoot")
	root.free()
	camera.free()


func test_a_raycast_miss_places_nothing():
	var tool = HFPathTool.new()
	var root := PlacementRoot.new()
	var camera := Camera3D.new()
	tool.root = root
	root.raycast_result = {}
	assert_eq(tool._handle_click(camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	assert_eq(root.raycast_calls, 1, "a shared raycast miss stays a miss")
	assert_eq(tool._waypoints.size(), 0, "and nothing is placed")
	root.free()
	camera.free()


func test_later_points_come_off_the_shared_y_plane_projection():
	var tool = HFPathTool.new()
	var root := PlacementRoot.new()
	var camera := Camera3D.new()
	tool.root = root
	root.raycast_result = {"position": Vector3(3, 7, 9)}
	tool._handle_click(camera, Vector2(20, 30))
	tool._handle_click(camera, Vector2(40, 50))
	assert_eq(root.raycast_calls, 1, "Only the first point is picked against geometry")
	assert_eq(root.y_plane_calls, 1, "The rest come off LevelRoot's y plane projection")
	root.free()
	camera.free()


# ===========================================================================
# Tool metadata
# ===========================================================================


func test_tool_id():
	var tool = HFPathTool.new()
	assert_eq(tool.tool_id(), 103)


func test_tool_name():
	var tool = HFPathTool.new()
	assert_eq(tool.tool_name(), "Path")


func test_shortcut_key():
	var tool = HFPathTool.new()
	assert_eq(tool.tool_shortcut_key(), KEY_SEMICOLON)


func test_settings_schema():
	var tool = HFPathTool.new()
	var schema = tool.get_settings_schema()
	assert_gte(schema.size(), 3, "Should have width, height, miter + extra settings")
	var names = []
	for s in schema:
		names.append(s.name)
	assert_has(names, "path_width")
	assert_has(names, "path_height")
	assert_has(names, "miter_joints")


# ===========================================================================
# Segment brush construction
# ===========================================================================


func test_build_segment_brush_straight():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(10, 0, 0), 4.0, 4.0, "grp1")
	assert_false(info.is_empty(), "Should produce a brush info dict")
	assert_eq(info.group_id, "grp1")
	assert_true(info.has("faces"), "Should have face data")
	assert_eq(info.faces.size(), 6, "Segment brush should have 6 faces (box)")


func test_build_segment_brush_diagonal():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(10, 0, 10), 4.0, 4.0, "grp2")
	assert_false(info.is_empty(), "Diagonal segment should produce a brush")
	assert_eq(info.faces.size(), 6)


func test_build_segment_brush_zero_length():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(0, 0, 0), 4.0, 4.0, "grp3")
	assert_true(info.is_empty(), "Zero-length segment should return empty")


func test_segment_center_is_midpoint():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(20, 0, 0), 4.0, 8.0, "grp4")
	assert_almost_eq(info.center.x, 10.0, 0.01, "Center X should be midpoint")
	assert_almost_eq(info.center.y, 4.0, 0.01, "Center Y should be ground + half_h")
	assert_almost_eq(info.center.z, 0.0, 0.01, "Center Z should be midpoint")


func test_segment_size():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(20, 0, 0), 6.0, 8.0, "grp5")
	assert_almost_eq(info.size.x, 20.0, 0.01, "Size X should be segment length")
	assert_almost_eq(info.size.y, 8.0, 0.01, "Size Y should be height")
	assert_almost_eq(info.size.z, 6.0, 0.01, "Size Z should be width")


# ===========================================================================
# Miter joint construction
# ===========================================================================


func test_miter_joint_right_angle():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_miter_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10), 4.0, 4.0, "grp_m"
	)
	assert_false(info.is_empty(), "90-degree turn should produce a miter brush")
	assert_true(info.has("faces"), "Miter should have face data")
	assert_true(info.faces.size() >= 5, "Miter should have at least 5 faces (3 sides + top + bot)")


func test_miter_joint_straight_skipped():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_miter_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0), 4.0, 4.0, "grp_m2"
	)
	assert_true(info.is_empty(), "Straight path should skip miter (dot > 0.98)")


func test_miter_joint_acute_skipped():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	# 180 degree turn (doubling back)
	var info = tool._build_miter_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 0, 0.01), 4.0, 4.0, "grp_m3"
	)
	assert_true(info.is_empty(), "Acute reversal should skip miter")


func test_miter_joint_has_group_id():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_miter_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10), 4.0, 4.0, "mygroup"
	)
	if not info.is_empty():
		assert_eq(info.group_id, "mygroup")


# ===========================================================================
# Face data validation
# ===========================================================================


func test_segment_faces_are_valid_dicts():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(10, 0, 0), 4.0, 4.0, "test")
	for face_dict in info.faces:
		assert_true(face_dict is Dictionary, "Each face should be a dict")
		assert_true(face_dict.has("local_verts"), "Face should have local_verts")
		assert_true(face_dict.has("normal"), "Face should have normal")


func test_segment_faces_reconstruct_as_face_data():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(10, 0, 0), 4.0, 4.0, "test")
	for face_dict in info.faces:
		var face = FaceData.from_dict(face_dict)
		assert_not_null(face, "Face should deserialize")
		assert_true(face.local_verts.size() >= 3, "Face should have 3+ verts")


func test_rmb_passes_when_idle_and_only_steps_back_active_path_work():
	var tool = HFPathTool.new()
	var root := Node3D.new()
	var camera := Camera3D.new()
	tool.root = root
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	assert_eq(tool.handle_input(press, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	assert_eq(tool.handle_input(motion, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	assert_eq(tool.handle_input(release, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)

	tool._phase = tool.Phase.PLACING_WAYPOINTS
	tool._waypoints = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])
	assert_eq(tool.handle_input(press, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(tool._waypoints.size(), 1, "Active RMB should remove exactly one waypoint")
	assert_eq(tool.handle_input(release, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	root.free()
	camera.free()


func _outward_face_count(info: Dictionary) -> int:
	# Face verts are local to the brush centre, so a face points outward when
	# its normal agrees with the direction from the centre to the face.
	var outward := 0
	for face_dict in info.faces:
		var face = FaceData.from_dict(face_dict)
		var centroid := Vector3.ZERO
		for v in face.local_verts:
			centroid += v
		centroid /= float(face.local_verts.size())
		if face.normal.dot(centroid) > 0.0:
			outward += 1
	return outward


func test_segment_brush_faces_point_outward():
	# Every face of a path segment used to point at the brush centre, so a
	# corridor baked inside out.
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(256, 0, 0), 4.0, 4.0, "test")
	assert_eq(info.faces.size(), 6, "A segment is a box")
	assert_eq(_outward_face_count(info), 6, "Every face of a segment points out of the solid")


func test_diagonal_segment_brush_faces_point_outward():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(64, 0, 64), 8.0, 6.0, "test")
	assert_eq(_outward_face_count(info), 6, "Winding does not depend on the segment direction")


func test_miter_brush_faces_point_outward():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_miter_brush(
		Vector3(-64, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 64), 8.0, 8.0, "test"
	)
	assert_false(info.is_empty(), "A right-angle bend gets a miter")
	assert_eq(
		_outward_face_count(info), info.faces.size(), "Every miter face points out of the solid"
	)


# ===========================================================================
# Segment lengths and the Shift axis lock (#1408)
# ===========================================================================


## A level stand-in that answers every pick with `aim` and snaps to half a metre.
class AimRoot:
	extends Node3D

	var aim := Vector3.ZERO

	func _snap_point(point: Vector3, _exclude_ids: Array = []) -> Vector3:
		return point.snapped(Vector3(0.5, 0.5, 0.5))

	func _raycast(_camera: Camera3D, _mouse_pos: Vector2) -> Dictionary:
		return {"position": aim}

	func screen_ray_to_y_plane(_camera: Camera3D, _mouse_pos: Vector2, y: float) -> Vector3:
		return Vector3(aim.x, y, aim.z)


func _click_at(tool, root: AimRoot, camera: Camera3D, at: Vector3, shift := false) -> int:
	root.aim = at
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.shift_pressed = shift
	return tool.handle_input(press, camera, Vector2.ZERO)


func _move_to(tool, root: AimRoot, camera: Camera3D, at: Vector3, shift := false) -> void:
	root.aim = at
	var motion := InputEventMouseMotion.new()
	motion.shift_pressed = shift
	tool.handle_input(motion, camera, Vector2.ZERO)


## [tool, root, camera], the root and camera freed with the test.
func _aimed_tool() -> Array:
	var tool = HFPathTool.new()
	var root := AimRoot.new()
	add_child_autofree(root)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	tool.root = root
	return [tool, root, camera]


func _labels_in(level: Node) -> Array:
	return level.find_children("SegmentLength*", "Label3D", true, false)


func _label_texts(tool) -> Array:
	var texts: Array = []
	for label: Label3D in tool._length_labels:
		texts.append(label.text)
	texts.sort()
	return texts


func test_shift_locks_a_waypoint_to_the_axis_nearer_its_direction():
	# A corridor meant to run along X used to pick up a step of Z when a click
	# landed a cell off, and the path then built a joint nobody asked for.
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_click_at(tool, parts[1], parts[2], Vector3(3, 0, 0.4), true)
	assert_eq(tool._waypoints[1], Vector3(3, 0, 0), "X is nearer, so Z stays the last point's")
	_click_at(tool, parts[1], parts[2], Vector3(2.7, 0, 6.2), true)
	assert_eq(tool._waypoints[2], Vector3(3, 0, 6), "Z is nearer, and it snaps along Z")
	tool.deactivate()
	await get_tree().process_frame


func test_without_shift_a_waypoint_lands_where_it_snaps():
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_click_at(tool, parts[1], parts[2], Vector3(3, 0, 0.4))
	assert_eq(tool._waypoints[1], Vector3(3, 0, 0.5), "placement is unchanged")
	tool.deactivate()
	await get_tree().process_frame


func test_shift_locks_the_live_segment_while_the_mouse_moves():
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(2, 0, 2))
	_move_to(tool, parts[1], parts[2], Vector3(-6.2, 0, 2.6), true)
	assert_eq(tool._cursor_pos, Vector3(-6, 0, 2), "the cursor runs along X from the last point")
	tool.deactivate()
	await get_tree().process_frame


func test_the_hud_names_the_axis_lock_while_placing():
	var parts := _aimed_tool()
	var tool = parts[0]
	assert_false(tool.get_shortcut_hud_lines().has("Shift: Lock to axis"), "not before a point")
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	assert_true(tool.get_shortcut_hud_lines().has("Shift: Lock to axis"))
	tool.deactivate()
	await get_tree().process_frame


func _fresh_level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


func test_placed_and_live_segments_show_their_lengths():
	var level := _fresh_level()
	level.grid_snap = 0.5
	var tool = HFPathTool.new()
	tool.root = level
	tool._phase = tool.Phase.PLACING_WAYPOINTS
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(12, 0, 0)])
	tool._cursor_pos = Vector3(12, 0, 5)
	tool._update_preview()
	assert_eq(_label_texts(tool), ["12", "5"], "placed 12, live 5, whole lengths as whole numbers")
	var placed: Label3D = tool._length_labels[0]
	assert_eq(
		placed.position, Vector3(6, 0.5, 0), "at its segment's middle, lifted as a ruler's is"
	)
	level.grid_snap = 1.0
	tool._update_preview()
	assert_eq(_label_texts(tool), ["12", "5"], "the places follow the grid")
	assert_eq(_labels_in(level).size(), 2, "and the labels are reused, not added to")
	tool.deactivate()
	await get_tree().process_frame


func test_building_the_path_takes_the_labels_away():
	var level := _fresh_level()
	var tool = HFPathTool.new()
	tool.root = level
	tool._phase = tool.Phase.PLACING_WAYPOINTS
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(8, 0, 0)])
	tool._cursor_pos = Vector3(8, 0, 8)
	tool._update_preview()
	assert_eq(_labels_in(level).size(), 2)
	tool._build_path()
	assert_true(tool._length_labels.is_empty(), "the tool lets them go")
	assert_eq(_labels_in(level).size(), 0, "and none stays in the scene tree")
	await get_tree().process_frame


func test_cancelling_takes_the_labels_away():
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_click_at(tool, parts[1], parts[2], Vector3(4, 0, 0))
	_move_to(tool, parts[1], parts[2], Vector3(4, 0, 4))
	assert_eq(_labels_in(parts[1]).size(), 2, "the placed and live segments are labelled")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	tool.handle_input(escape, parts[2], Vector2.ZERO)
	tool.handle_input(escape, parts[2], Vector2.ZERO)
	assert_eq(_labels_in(parts[1]).size(), 0, "Esc down to nothing takes them all")
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_move_to(tool, parts[1], parts[2], Vector3(4, 0, 0))
	tool.deactivate()
	assert_eq(_labels_in(parts[1]).size(), 0, "and so does leaving the tool")
	await get_tree().process_frame
