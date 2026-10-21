extends GutTest

const HFPolygonTool = preload("res://addons/hammerforge/hf_polygon_tool.gd")
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
	var tool = HFPolygonTool.new()
	var root := PlacementRoot.new()
	var camera := Camera3D.new()
	tool.root = root
	root.raycast_result = {"position": Vector3(3, 7, 9)}
	assert_eq(tool.snap_point(Vector3(3, 7, 9)), Vector3(4, 8, 8))
	assert_eq(tool._handle_click(camera, Vector2(20, 30)), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(root.raycast_calls, 1, "LevelRoot owns visual and physics picking")
	assert_eq(tool._polygon_points.size(), 1, "The picked point becomes the first point")
	assert_eq(tool._polygon_points[0], Vector3(4, 8, 8), "and it is snapped by LevelRoot")
	root.free()
	camera.free()


func test_a_raycast_miss_places_nothing():
	var tool = HFPolygonTool.new()
	var root := PlacementRoot.new()
	var camera := Camera3D.new()
	tool.root = root
	root.raycast_result = {}
	assert_eq(tool._handle_click(camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	assert_eq(root.raycast_calls, 1, "a shared raycast miss stays a miss")
	assert_eq(tool._polygon_points.size(), 0, "and nothing is placed")
	root.free()
	camera.free()


func test_later_points_come_off_the_shared_y_plane_projection():
	var tool = HFPolygonTool.new()
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
# Convexity validation
# ===========================================================================


func test_convex_square():
	var pts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4)]
	)
	assert_true(HFPolygonTool._is_convex_xz(pts), "Square should be convex")


func test_convex_triangle():
	var pts = PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(2, 0, 3)])
	assert_true(HFPolygonTool._is_convex_xz(pts), "Triangle is always convex")


func test_concave_l_shape():
	var pts = PackedVector3Array(
		[
			Vector3(0, 0, 0),
			Vector3(4, 0, 0),
			Vector3(4, 0, 2),
			Vector3(2, 0, 2),
			Vector3(2, 0, 4),
			Vector3(0, 0, 4)
		]
	)
	assert_false(HFPolygonTool._is_convex_xz(pts), "L-shape should be concave")


func test_convex_pentagon():
	# Regular pentagon centered at origin
	var pts = PackedVector3Array()
	for i in range(5):
		var angle = i * TAU / 5.0
		pts.append(Vector3(cos(angle) * 4, 0, sin(angle) * 4))
	assert_true(HFPolygonTool._is_convex_xz(pts), "Regular pentagon should be convex")


func test_degenerate_two_points():
	var pts = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)])
	assert_true(HFPolygonTool._is_convex_xz(pts), "Two points should pass (degenerate)")


func test_collinear_points_pass_the_convexity_gate_but_not_the_area_gate():
	# The convexity gate skips every cross product under its degenerate
	# threshold, and for points on one line that is all of them, so it never
	# disagrees with itself. That is why a polygon on one line has to be caught
	# on the area it encloses instead: it used to extrude to a five-faced brush
	# with an extent of zero that saved, baked and blocked every pick.
	var pts = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(4, 0, 0)])
	assert_true(HFPolygonTool._is_convex_xz(pts), "Convexity alone cannot see collinear points")
	assert_almost_eq(HFPolygonTool._polygon_area_xz(pts), 0.0, 0.0001, "They enclose nothing")


# ===========================================================================
# Face data construction
# ===========================================================================


func test_face_data_construction():
	var tool = HFPolygonTool.new()
	tool._polygon_points = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 8), Vector3(0, 0, 8)]
	)
	tool._ground_y = 0.0
	tool._height = 4.0
	var faces = tool._build_face_data()
	# Square extruded: 1 top + 1 bottom + 4 sides = 6 faces
	assert_eq(faces.size(), 6, "Extruded square should have 6 face dicts")


func test_face_data_triangle():
	var tool = HFPolygonTool.new()
	tool._polygon_points = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(6, 0, 0), Vector3(3, 0, 5)]
	)
	tool._ground_y = 0.0
	tool._height = 3.0
	var faces = tool._build_face_data()
	# Triangle extruded: 1 top + 1 bottom + 3 sides = 5 faces
	assert_eq(faces.size(), 5, "Extruded triangle should have 5 face dicts")


func test_face_data_vertices_are_local():
	var tool = HFPolygonTool.new()
	tool._polygon_points = PackedVector3Array(
		[Vector3(10, 0, 10), Vector3(14, 0, 10), Vector3(14, 0, 14), Vector3(10, 0, 14)]
	)
	tool._ground_y = 0.0
	tool._height = 4.0
	var faces = tool._build_face_data()
	assert_true(faces.size() > 0, "Should have face data")
	# Deserialize and check that vertices are centered (local space)
	for face_dict in faces:
		var face = FaceData.from_dict(face_dict)
		for v in face.local_verts:
			# Vertices should be relative to center (12, 2, 12) so within [-2, 2] on XZ
			assert_true(absf(v.x) <= 2.1, "Local X should be within half-extent, got %f" % v.x)
			assert_true(absf(v.z) <= 2.1, "Local Z should be within half-extent, got %f" % v.z)


func test_face_data_top_face_normal_points_up():
	var tool = HFPolygonTool.new()
	tool._polygon_points = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4)]
	)
	tool._ground_y = 0.0
	tool._height = 4.0
	var faces = tool._build_face_data()
	# First face is top face
	var top = FaceData.from_dict(faces[0])
	top.ensure_geometry()
	# Normal should point upward
	assert_true(top.normal.y > 0.5, "Top face normal should point up, got: %s" % top.normal)


func test_empty_polygon_returns_empty():
	var tool = HFPolygonTool.new()
	tool._polygon_points = PackedVector3Array()
	tool._ground_y = 0.0
	tool._height = 4.0
	var faces = tool._build_face_data()
	assert_eq(faces.size(), 0, "Empty polygon should produce no faces")


func test_two_points_returns_empty():
	var tool = HFPolygonTool.new()
	tool._polygon_points = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)])
	tool._ground_y = 0.0
	tool._height = 4.0
	var faces = tool._build_face_data()
	assert_eq(faces.size(), 0, "Two-point polygon should produce no faces")


# ===========================================================================
# Tool metadata
# ===========================================================================


func test_tool_id():
	var tool = HFPolygonTool.new()
	assert_eq(tool.tool_id(), 102)


func test_tool_name():
	var tool = HFPolygonTool.new()
	assert_eq(tool.tool_name(), "Polygon")


func test_shortcut_key():
	var tool = HFPolygonTool.new()
	assert_eq(tool.tool_shortcut_key(), KEY_P)


func test_settings_schema():
	var tool = HFPolygonTool.new()
	var schema = tool.get_settings_schema()
	assert_true(schema.size() > 0, "Should have settings")
	assert_eq(schema[0].name, "auto_close_threshold")


func test_rmb_passes_when_idle_and_only_cancels_active_polygon_work():
	var tool = HFPolygonTool.new()
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

	tool._phase = tool.Phase.PLACING_VERTS
	tool._polygon_points = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])
	assert_eq(tool.handle_input(press, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(tool._polygon_points.size(), 1, "Active RMB should remove exactly one vertex")
	assert_eq(tool.handle_input(release, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	root.free()
	camera.free()


func test_downward_height_drag_stays_positive():
	var tool = HFPolygonTool.new()
	var root := Node3D.new()
	var camera := Camera3D.new()
	tool.root = root
	tool._polygon_points = PackedVector3Array(
		[Vector3.ZERO, Vector3.RIGHT * 4.0, Vector3(4, 0, 4), Vector3.BACK * 4.0]
	)
	tool._ground_y = 0.0
	tool._height = 32.0
	tool._height_start_value = 32.0
	tool._height_start_mouse = Vector2.ZERO
	tool._phase = tool.Phase.SETTING_HEIGHT
	tool._height_pointer_capture = true
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	assert_eq(
		tool.handle_input(motion, camera, Vector2(0, 400)),
		EditorPlugin.AFTER_GUI_INPUT_STOP,
	)
	assert_true(tool._height >= 0.1, "Downward drag must not invert extrusion")
	var faces = tool._build_face_data()
	assert_gt(faces.size(), 0)
	var top = FaceData.from_dict(faces[0])
	top.ensure_geometry()
	assert_true(top.normal.y > 0.5, "Top face must still point up")
	root.free()
	camera.free()


func test_lost_height_release_finalizes_once_before_buttonless_motion_mutates_height():
	var tool = HFPolygonTool.new()
	var root := Node3D.new()
	var camera := Camera3D.new()
	tool.root = root
	tool._polygon_points = PackedVector3Array(
		[Vector3.ZERO, Vector3.RIGHT * 4.0, Vector3(4, 0, 4), Vector3.BACK * 4.0]
	)
	tool._ground_y = 0.0
	tool._height = 8.0
	tool._height_start_value = 8.0
	tool._height_start_mouse = Vector2.ZERO
	tool._phase = tool.Phase.SETTING_HEIGHT
	tool._height_pointer_capture = true
	var motion := InputEventMouseMotion.new()
	motion.button_mask = 0
	assert_eq(
		tool.handle_input(motion, camera, Vector2(0, 100)),
		EditorPlugin.AFTER_GUI_INPUT_STOP,
	)
	assert_eq(tool._phase, tool.Phase.IDLE)
	assert_false(tool._height_pointer_capture)
	# The reset used to land on a literal 32.0. It lands on the height the shape
	# was finished at now, because the tool remembers what the mapper set rather
	# than throwing it away every polygon (#658). Either way the point of the
	# assertion is the same: a 100 pixel motion arriving with the finalisation
	# must not be added to the height on the way out.
	assert_eq(tool._height, 8.0, "Finalization resets instead of applying stale motion")
	assert_eq(tool._remembered_height, 8.0, "and the next polygon starts where this one was built")
	root.free()
	camera.free()


func test_focus_loss_cancels_height_pointer_capture_but_keeps_polygon_editable():
	var tool = HFPolygonTool.new()
	tool._polygon_points = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3(1, 0, 1)])
	tool._phase = tool.Phase.SETTING_HEIGHT
	tool._height_pointer_capture = true
	assert_true(tool.cancel_pointer_capture())
	assert_eq(tool._phase, tool.Phase.PLACING_VERTS)
	assert_false(tool._height_pointer_capture)
	assert_eq(tool._polygon_points.size(), 3)
	assert_false(tool.cancel_pointer_capture(), "A settled polygon should not be cancelled twice")


# ===========================================================================
# Degenerate input
# ===========================================================================


func test_a_polygon_on_one_line_does_not_extrude():
	var tool = HFPolygonTool.new()
	var root := PlacementRoot.new()
	tool.root = root
	tool._polygon_points = PackedVector3Array(
		[Vector3(-64, 0, 0), Vector3(0, 0, 0), Vector3(64, 0, 0)]
	)
	tool._phase = tool.Phase.PLACING_VERTS
	assert_false(tool._begin_height_stage(Vector2.ZERO), "A polygon with no area is refused")
	assert_eq(tool._phase, tool.Phase.PLACING_VERTS, "and the tool stays where it was")
	root.free()


func test_a_polygon_with_area_still_extrudes():
	var tool = HFPolygonTool.new()
	var root := PlacementRoot.new()
	tool.root = root
	tool._polygon_points = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(64, 0, 0), Vector3(64, 0, 64), Vector3(0, 0, 64)]
	)
	tool._phase = tool.Phase.PLACING_VERTS
	assert_true(tool._begin_height_stage(Vector2.ZERO), "A square is fine")
	assert_eq(tool._phase, tool.Phase.SETTING_HEIGHT, "and the height stage opens")
	root.free()


func test_a_point_on_top_of_one_already_placed_is_rejected():
	var existing = PackedVector3Array([Vector3(0, 0, 0), Vector3(64, 0, 0)])
	assert_true(
		HFPolygonTool._is_repeat_point(existing, Vector3(0, 0, 0)), "The same point is a repeat"
	)
	assert_true(
		HFPolygonTool._is_repeat_point(existing, Vector3(64, 0, 0.001)),
		"and so is one inside the epsilon"
	)
	assert_false(
		HFPolygonTool._is_repeat_point(existing, Vector3(64, 0, 64)), "A new corner is not"
	)


func test_a_repeat_click_places_no_second_vertex():
	# A repeated vertex used to build a side quad spanning no area, which still
	# took a normal, a UV projection, a snap target and a place in the bake.
	var tool = HFPolygonTool.new()
	var root := PlacementRoot.new()
	var camera := Camera3D.new()
	tool.root = root
	root.raycast_result = {"position": Vector3(0, 0, 0)}
	tool._handle_click(camera, Vector2.ZERO)
	assert_eq(tool._polygon_points.size(), 1, "First click places a vertex")
	assert_eq(
		tool._handle_click(camera, Vector2.ZERO),
		EditorPlugin.AFTER_GUI_INPUT_STOP,
		"The repeat is swallowed"
	)
	assert_eq(tool._polygon_points.size(), 1, "and places nothing")
	root.free()
	camera.free()


# ===========================================================================
# Segment lengths and the Shift axis lock (#1408)
# ===========================================================================


## A level stand-in that answers every pick with `aim` and snaps to half a metre.
class AimRoot:
	extends Node3D

	signal user_message(text: String, level: int)

	var aim := Vector3.ZERO

	func _snap_point(point: Vector3, _exclude_ids: Array = []) -> Vector3:
		return point.snapped(Vector3(0.5, 0.5, 0.5))

	func _raycast(_camera: Camera3D, _mouse_pos: Vector2) -> Dictionary:
		return {"position": aim}

	func screen_ray_to_y_plane(_camera: Camera3D, _mouse_pos: Vector2, y: float) -> Vector3:
		return Vector3(aim.x, y, aim.z)


func _press(shift := false) -> InputEventMouseButton:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.shift_pressed = shift
	return press


func _click_at(tool, root: AimRoot, camera: Camera3D, at: Vector3, shift := false) -> int:
	root.aim = at
	return tool.handle_input(_press(shift), camera, Vector2.ZERO)


func _move_to(tool, root: AimRoot, camera: Camera3D, at: Vector3, shift := false) -> void:
	root.aim = at
	var motion := InputEventMouseMotion.new()
	motion.shift_pressed = shift
	tool.handle_input(motion, camera, Vector2.ZERO)


## [tool, root, camera], the root and camera freed with the test.
func _aimed_tool() -> Array:
	var tool = HFPolygonTool.new()
	var root := AimRoot.new()
	add_child_autofree(root)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	tool.root = root
	return [tool, root, camera]


func test_shift_locks_a_click_to_the_axis_nearer_its_direction():
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_click_at(tool, parts[1], parts[2], Vector3(3, 0, 0.4), true)
	assert_eq(tool._polygon_points[1], Vector3(3, 0, 0), "X is nearer, so Z stays the last point's")
	_click_at(tool, parts[1], parts[2], Vector3(3.4, 0, -2.2), true)
	assert_eq(tool._polygon_points[2], Vector3(3, 0, -2), "Z is nearer, and it snaps along Z")
	tool.deactivate()
	await get_tree().process_frame


func test_without_shift_a_click_lands_where_it_snaps():
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_click_at(tool, parts[1], parts[2], Vector3(3, 0, 0.4))
	assert_eq(tool._polygon_points[1], Vector3(3, 0, 0.5), "placement is unchanged")
	tool.deactivate()
	await get_tree().process_frame


func test_shift_locks_the_live_segment_while_the_mouse_moves():
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(1, 0, 1))
	_move_to(tool, parts[1], parts[2], Vector3(1.6, 0, 5.1), true)
	assert_eq(tool._cursor_pos, Vector3(1, 0, 5), "the cursor runs along Z from the last point")
	_move_to(tool, parts[1], parts[2], Vector3(1.6, 0, 5.1))
	assert_eq(tool._cursor_pos, Vector3(1.5, 0, 5), "and goes free when Shift is let go")
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


func _label_texts(tool) -> Array:
	var texts: Array = []
	for label: Label3D in tool._length_labels:
		texts.append(label.text)
	texts.sort()
	return texts


func _labels_in(level: Node) -> Array:
	return level.find_children("SegmentLength*", "Label3D", true, false)


func test_placed_live_and_closing_segments_show_their_lengths():
	var level := _fresh_level()
	level.grid_snap = 1.0
	var tool = HFPolygonTool.new()
	tool.root = level
	tool._phase = tool.Phase.PLACING_VERTS
	tool._polygon_points = PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0)])
	tool._cursor_pos = Vector3(4, 0, 3)
	tool._update_preview()
	assert_eq(_label_texts(tool), ["3", "4", "5"], "placed 4, live 3, closing 5, on a 1 m grid")
	var placed: Label3D = tool._length_labels[0]
	assert_eq(placed.position, Vector3(2, 0.5, 0), "at its edge's middle, lifted as a ruler's is")
	assert_eq(_labels_in(level).size(), 3, "under the level")
	tool.deactivate()
	await get_tree().process_frame


func test_lengths_carry_the_decimals_the_grid_needs():
	assert_eq(HFPolygonTool.length_text(12.0, 1.0), "12")
	assert_eq(HFPolygonTool.length_text(4.5, 0.5), "4.5")
	assert_eq(HFPolygonTool.length_text(3.25, 0.25), "3.25")
	assert_eq(HFPolygonTool.length_text(3.0, 0.25), "3.00", "the same places on every label")
	assert_eq(HFPolygonTool.length_text(0.125, 0.125), "0.125")
	assert_eq(HFPolygonTool.length_text(2.0, 0.0), "2.00", "with no grid, two")
	var level := _fresh_level()
	level.grid_snap = 0.25
	var tool = HFPolygonTool.new()
	tool.root = level
	tool._phase = tool.Phase.PLACING_VERTS
	tool._polygon_points = PackedVector3Array([Vector3(0, 0, 0), Vector3(3.25, 0, 0)])
	tool._cursor_pos = Vector3(3.25, 0, 0)
	tool._update_preview()
	assert_eq(_label_texts(tool), ["3.25", "3.25"], "a cursor still on the last point adds none")
	tool.deactivate()
	await get_tree().process_frame


func test_a_closed_outline_labels_every_edge_and_building_it_takes_them_away():
	var level := _fresh_level()
	level.grid_snap = 1.0
	var tool = HFPolygonTool.new()
	tool.root = level
	tool._phase = tool.Phase.PLACING_VERTS
	tool._polygon_points = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 2), Vector3(0, 0, 2)]
	)
	assert_true(tool._begin_height_stage(Vector2.ZERO))
	assert_eq(_label_texts(tool), ["2", "2", "4", "4"], "the closing edge is one of them")
	tool._finalize_brush()
	assert_true(tool._length_labels.is_empty(), "the tool lets them go")
	assert_eq(_labels_in(level).size(), 0, "and none stays in the scene tree")
	await get_tree().process_frame


func test_cancelling_takes_the_labels_away():
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_move_to(tool, parts[1], parts[2], Vector3(4, 0, 0))
	assert_eq(_labels_in(parts[1]).size(), 1, "the live segment is labelled")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	tool.handle_input(escape, parts[2], Vector2.ZERO)
	assert_eq(_labels_in(parts[1]).size(), 0, "Esc on the only point cancels, and the label goes")
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_move_to(tool, parts[1], parts[2], Vector3(4, 0, 0))
	tool.deactivate()
	assert_eq(_labels_in(parts[1]).size(), 0, "and so does leaving the tool")
	await get_tree().process_frame


func test_no_label_is_saved_with_the_scene():
	var level := _fresh_level()
	var tool = HFPolygonTool.new()
	tool.root = level
	tool._phase = tool.Phase.PLACING_VERTS
	tool._polygon_points = PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0)])
	tool._cursor_pos = Vector3(4, 0, 3)
	tool._update_preview()
	assert_eq(_labels_in(level).size(), 3, "labels are up")
	var packed := PackedScene.new()
	assert_eq(packed.pack(level), OK)
	var state := packed.get_state()
	for i in state.get_node_count():
		assert_ne(str(state.get_node_type(i)), "Label3D", "%s is saved" % state.get_node_name(i))
	tool.deactivate()
	await get_tree().process_frame


# ===========================================================================
# Concave outlines split into convex brushes (#1430)
# ===========================================================================

const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const PolygonSplit = preload("res://addons/hammerforge/hf_polygon_split.gd")


func _ring(points: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Vector2 in points:
		out.append(Vector3(p.x, 0, p.y))
	return out


func _l_outline() -> PackedVector3Array:
	return _ring(
		[Vector2(0, 0), Vector2(4, 0), Vector2(4, 2), Vector2(2, 2), Vector2(2, 4), Vector2(0, 4)]
	)


func _u_outline() -> PackedVector3Array:
	return _ring(
		[
			Vector2(0, 0),
			Vector2(6, 0),
			Vector2(6, 6),
			Vector2(4, 6),
			Vector2(4, 2),
			Vector2(2, 2),
			Vector2(2, 6),
			Vector2(0, 6)
		]
	)


func _t_outline() -> PackedVector3Array:
	return _ring(
		[
			Vector2(0, 0),
			Vector2(6, 0),
			Vector2(6, 2),
			Vector2(4, 2),
			Vector2(4, 6),
			Vector2(2, 6),
			Vector2(2, 2),
			Vector2(0, 2)
		]
	)


## A five-pointed star on the half-metre grid.
func _star_outline() -> PackedVector3Array:
	var pts: Array = []
	for i in 10:
		var radius := 4.0 if i % 2 == 0 else 1.6
		var angle := i * TAU / 10.0
		pts.append(Vector2(cos(angle) * radius, sin(angle) * radius).snapped(Vector2(0.5, 0.5)))
	return _ring(pts)


## Close `outline` and build it on a real level with an undo manager. Returns
## [level, brushes made, undo].
func _build(outline: PackedVector3Array) -> Array:
	var level := _fresh_level()
	var undo = UndoStandIn.new()
	var tool = HFPolygonTool.new()
	tool.root = level
	tool.undo_redo = undo
	tool._phase = tool.Phase.PLACING_VERTS
	tool._polygon_points = outline
	tool._ground_y = 0.0
	assert_true(tool._begin_height_stage(Vector2.ZERO), "the outline closes")
	tool._height = 2.0
	tool._finalize_brush()
	return [level, level._iter_managed_brush_nodes(), undo]


static func _area(ring: PackedVector2Array) -> float:
	return absf(PolygonSplit.signed_area(ring))


## A brush's top face in world X and Z.
func _footprint(brush: Node3D) -> PackedVector2Array:
	for face: FaceData in brush.faces:
		if face.normal.y > 0.9:
			var ring := PackedVector2Array()
			for v in face.local_verts:
				var world: Vector3 = brush.global_transform * v
				ring.append(Vector2(world.x, world.z))
			return ring
	return PackedVector2Array()


## Every brush convex, wound clockwise from outside and not mirrored; together
## they cover the outline exactly, with no gap and no overlap.
func _assert_exact_convex_cover(brushes: Array, outline: PackedVector3Array, note: String) -> void:
	var outline_xz := PackedVector2Array()
	for p in outline:
		outline_xz.append(Vector2(p.x, p.z))
	var total := 0.0
	var prints: Array = []
	for brush in brushes:
		var faces: Array = brush.faces
		var interior := HFConvexClip.interior_point(faces)
		assert_true(
			HFConvexClip.is_convex_solid(faces, interior), "%s: %s is convex" % [note, brush.name]
		)
		for face: FaceData in faces:
			var centre := Vector3.ZERO
			for v in face.local_verts:
				centre += v
			centre /= float(face.local_verts.size())
			assert_gt(face.normal.dot(centre - interior), 0.0, "%s: every face points out" % note)
		assert_gt(brush.global_transform.basis.determinant(), 0.0, "%s: not mirrored" % note)
		var footprint := _footprint(brush)
		assert_gte(footprint.size(), 3, "%s: %s has a top" % [note, brush.name])
		total += _area(footprint)
		var outside := 0.0
		for piece in Geometry2D.clip_polygons(footprint, outline_xz):
			outside += _area(piece)
		assert_almost_eq(outside, 0.0, 0.0001, "%s: nothing outside the outline" % note)
		prints.append(footprint)
	assert_almost_eq(total, _area(outline_xz), 0.0001, "%s: the pieces add up to it" % note)
	var overlap := 0.0
	for i in prints.size():
		for j in range(i + 1, prints.size()):
			for piece in Geometry2D.intersect_polygons(prints[i], prints[j]):
				overlap += _area(piece)
	assert_almost_eq(overlap, 0.0, 0.0001, "%s: no two pieces overlap" % note)


func test_a_concave_click_is_placed_rather_than_dropped():
	# The fifth point of an L turns the outline concave. It used to be dropped
	# without a word, which read as a missed click.
	var parts := _aimed_tool()
	var tool = parts[0]
	for p in _l_outline():
		assert_eq(_click_at(tool, parts[1], parts[2], p), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(tool._polygon_points, _l_outline(), "every point of the L is placed")
	tool.deactivate()
	await get_tree().process_frame


func test_an_l_makes_two_convex_brushes_that_cover_it_grouped_in_one_step():
	var built := _build(_l_outline())
	var level: LevelRoot = built[0]
	var brushes: Array = built[1]
	var undo = built[2]
	assert_eq(brushes.size(), 2, "an L is two pieces")
	_assert_exact_convex_cover(brushes, _l_outline(), "L")
	var group := str(brushes[0].get_meta("group_id", ""))
	assert_ne(group, "", "the pieces are grouped")
	assert_eq(str(brushes[1].get_meta("group_id", "")), group, "in one group")
	assert_eq(undo.scene_history.get_history_count(), 1, "one undo step")
	assert_eq(undo.scene_history.get_current_action_name(), "Create Polygon (2 brushes)")
	undo.scene_history.undo()
	assert_eq(level._iter_managed_brush_nodes().size(), 0, "one undo takes both away")
	undo.scene_history.redo()
	assert_eq(level._iter_managed_brush_nodes().size(), 2, "and redo brings both back")
	undo.free_histories()


func test_an_l_is_cut_along_the_line_of_a_wall():
	# Two rectangles, not two trapezoids meeting on the diagonal.
	var built := _build(_l_outline())
	for brush in built[1]:
		var footprint := _footprint(brush)
		assert_eq(footprint.size(), 4, "%s has four corners" % brush.name)
		var box := Rect2(footprint[0], Vector2.ZERO)
		for p in footprint:
			box = box.expand(p)
		assert_almost_eq(box.get_area(), _area(footprint), 0.0001, "and fills its box")
	built[2].free_histories()


func test_a_u_makes_convex_brushes_with_no_gap_or_overlap():
	var built := _build(_u_outline())
	assert_eq(built[1].size(), 3, "a U is three pieces")
	_assert_exact_convex_cover(built[1], _u_outline(), "U")
	built[2].free_histories()


func test_a_star_makes_convex_brushes_with_no_gap_or_overlap():
	var built := _build(_star_outline())
	assert_gt(built[1].size(), 1, "a star is split")
	assert_lte(built[1].size(), 6, "into at most one more piece than its five inner corners")
	_assert_exact_convex_cover(built[1], _star_outline(), "star")
	built[2].free_histories()


func test_a_t_junction_is_the_bar_and_the_stem():
	var built := _build(_t_outline())
	assert_eq(built[1].size(), 2, "the cut joins the two inner corners")
	_assert_exact_convex_cover(built[1], _t_outline(), "T")
	built[2].free_histories()


func test_a_convex_outline_still_makes_one_brush_as_it_did():
	var square := _ring([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	var reference = HFPolygonTool.new()
	reference._polygon_points = square
	reference._ground_y = 0.0
	reference._height = 2.0
	var expected: Array = reference._build_face_data()
	var built := _build(square)
	var brushes: Array = built[1]
	assert_eq(brushes.size(), 1, "one brush")
	assert_eq(str(brushes[0].get_meta("group_id", "")), "", "in no group")
	assert_eq(brushes[0].faces.size(), expected.size(), "with the faces it always had")
	for i in expected.size():
		var want := FaceData.from_dict(expected[i])
		assert_eq(brushes[0].faces[i].local_verts, want.local_verts, "face %d unchanged" % i)
	assert_eq(built[2].scene_history.get_current_action_name(), "Create Polygon Brush")
	built[2].free_histories()


func test_an_outline_that_crosses_itself_is_refused_with_a_toast():
	var level := _fresh_level()
	var toasts: Array = []
	level.user_message.connect(func(text: String, _level: int) -> void: toasts.append(text))
	var tool = HFPolygonTool.new()
	tool.root = level
	tool._phase = tool.Phase.PLACING_VERTS
	tool._polygon_points = _ring([Vector2(0, 0), Vector2(4, 4), Vector2(4, 0), Vector2(0, 4)])
	assert_false(tool._begin_height_stage(Vector2.ZERO), "a bow tie does not close")
	assert_eq(tool._phase, tool.Phase.PLACING_VERTS, "the tool stays where it was")
	assert_eq(tool._polygon_points.size(), 4, "with every point, so one can be taken back")
	assert_eq(toasts.size(), 1, "and the mapper is told")
	assert_string_contains(str(toasts[0]), "crosses itself")
	tool._finalize_brush()
	assert_eq(level._iter_managed_brush_nodes().size(), 0, "finishing it anyway creates nothing")
	assert_eq(toasts.size(), 2, "and says why")
	# A star drawn in one stroke crosses itself without its halves cancelling.
	tool._phase = tool.Phase.PLACING_VERTS
	tool._polygon_points = _ring(
		[Vector2(0, 4), Vector2(2.5, -3), Vector2(-4, 1), Vector2(4, 1), Vector2(-2.5, -3)]
	)
	assert_false(tool._begin_height_stage(Vector2.ZERO), "a pentagram does not close either")
	assert_eq(toasts.size(), 3)
	# Points on one line run back over themselves too, and keep their own warning.
	tool._polygon_points = _ring([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0)])
	assert_false(tool._begin_height_stage(Vector2.ZERO))
	assert_eq(toasts.size(), 3, "they are not said to cross")
	tool.deactivate()
	await get_tree().process_frame


## A tool whose split comes back empty, as `convex_parts()` answers when its own
## checks find the pieces wrong.
class SplitFailsTool:
	extends "res://addons/hammerforge/hf_polygon_tool.gd"

	func _brush_outlines() -> Array:
		return []


func test_an_outline_the_split_cannot_handle_is_refused_and_nothing_is_made():
	var level := _fresh_level()
	var toasts: Array = []
	level.user_message.connect(func(text: String, _level: int) -> void: toasts.append(text))
	var undo = UndoStandIn.new()
	var tool = SplitFailsTool.new()
	tool.root = level
	tool.undo_redo = undo
	tool._phase = tool.Phase.PLACING_VERTS
	tool._polygon_points = _l_outline()
	assert_false(tool._begin_height_stage(Vector2.ZERO), "it does not close")
	assert_eq(tool._phase, tool.Phase.PLACING_VERTS, "the points stay to be taken back")
	assert_eq(toasts.size(), 1, "and the mapper is told")
	assert_string_contains(str(toasts[0]), "could not be split")
	tool._finalize_brush()
	assert_eq(toasts.size(), 2, "finishing it anyway is refused the same way")
	assert_string_contains(str(toasts[1]), "could not be split")
	assert_eq(level._iter_managed_brush_nodes().size(), 0, "nothing is made")
	assert_eq(undo.scene_history.get_history_count(), 0, "and no undo step")
	undo.free_histories()
	tool.deactivate()
	await get_tree().process_frame


func test_the_preview_draws_the_split_before_the_height_stage():
	var parts := _aimed_tool()
	var tool = parts[0]
	for p in _l_outline():
		_click_at(tool, parts[1], parts[2], p)
	assert_eq(tool._phase, tool.Phase.PLACING_VERTS, "still placing points")
	var cuts: Array = tool._current_split().get("cuts", [])
	assert_eq(cuts.size(), 1, "the L shows the one line it will be cut along")
	assert_eq(cuts[0], [Vector2(2, 2), Vector2(0, 2)], "on from the inner corner's wall")
	tool._handle_escape()
	assert_eq(tool._current_split().get("cuts", []).size(), 1, "five points of it are concave too")
	tool._handle_escape()
	assert_true(tool._current_split().get("cuts", []).is_empty(), "four are convex, and uncut")
	tool.deactivate()
	await get_tree().process_frame


## Pieces that are convex, run anticlockwise, and add up to `outline` without
## overlapping. A message for the first that is not, or "".
func _cover_problem(outline: PackedVector2Array, parts: Array) -> String:
	if parts.is_empty():
		return "no pieces"
	var total := 0.0
	for part: PackedVector2Array in parts:
		for i in part.size():
			var a := part[i]
			var b := part[(i + 1) % part.size()]
			var c := part[(i + 2) % part.size()]
			if (b - a).cross(c - b) < -0.00001:
				return "a piece is not convex: %s" % part
		total += PolygonSplit.signed_area(part)
	if absf(total - _area(outline)) > 0.0001:
		return "pieces add up to %f of %f" % [total, _area(outline)]
	for i in parts.size():
		for j in range(i + 1, parts.size()):
			for piece in Geometry2D.intersect_polygons(parts[i], parts[j]):
				if _area(piece) > 0.0001:
					return "two pieces overlap"
	return ""


func test_any_outline_on_the_grid_splits_into_convex_pieces_that_cover_it():
	# Outlines round a centre, at random radii on the half-metre grid, so each is
	# simple and most are concave somewhere.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1430
	var checked := 0
	for trial in 300:
		var corners := rng.randi_range(4, 12)
		var angles: Array = []
		for k in corners:
			angles.append(rng.randf() * TAU)
		angles.sort()
		var outline := PackedVector2Array()
		for angle: float in angles:
			var radius := rng.randf_range(1.0, 10.0)
			outline.append((Vector2(cos(angle), sin(angle)) * radius).snapped(Vector2(0.5, 0.5)))
		var repeated := false
		for a in outline.size():
			for b in range(a + 1, outline.size()):
				repeated = repeated or outline[a].distance_to(outline[b]) < 0.01
		if repeated or PolygonSplit.crosses_itself(outline) or _area(outline) < 0.01:
			continue
		checked += 1
		var split: Dictionary = PolygonSplit.convex_parts(outline)
		var problem := _cover_problem(outline, split["parts"])
		if problem != "":
			fail_test("%s for %s" % [problem, outline])
			return
	assert_gt(checked, 200, "most of the outlines were simple enough to try")


func test_a_plan_drawn_along_the_grid_comes_apart_into_rectangles():
	# Bars of random height above and below a line: every corner square, many of
	# them reflex, some on a straight line.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1408
	for trial in 200:
		var bars := rng.randi_range(2, 8)
		var tops: Array = []
		var bottoms: Array = []
		for b in bars:
			tops.append(float(rng.randi_range(1, 6)))
			bottoms.append(-float(rng.randi_range(0, 5)))
		var outline := PackedVector2Array()
		for b in bars:
			for x in [b, b + 1]:
				var p := Vector2(x, bottoms[b])
				if outline.is_empty() or outline[outline.size() - 1] != p:
					outline.append(p)
		for b in range(bars - 1, -1, -1):
			for x in [b + 1, b]:
				var p := Vector2(x, tops[b])
				if outline[outline.size() - 1] != p:
					outline.append(p)
		if outline[0] == outline[outline.size() - 1]:
			outline.remove_at(outline.size() - 1)
		var split: Dictionary = PolygonSplit.convex_parts(outline)
		var problem := _cover_problem(outline, split["parts"])
		if problem != "":
			fail_test("%s for %s" % [problem, outline])
			return
		for part: PackedVector2Array in split["parts"]:
			var box := Rect2(part[0], Vector2.ZERO)
			for p in part:
				box = box.expand(p)
			if part.size() != 4 or absf(box.get_area() - _area(part)) > 0.0001:
				fail_test("a piece is not a rectangle: %s of %s" % [part, outline])
				return
	pass_test("every piece of every plan is a rectangle")
