extends GutTest

const HFPolygonTool = preload("res://addons/hammerforge/hf_polygon_tool.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")


class PlacementRoot:
	extends Node3D

	var raycast_result: Dictionary = {}
	var snap_calls := 0
	var raycast_calls := 0

	func _snap_point(point: Vector3, _exclude_ids: Array = []) -> Vector3:
		snap_calls += 1
		return point.snapped(Vector3(4, 4, 4))

	func _raycast(_camera: Camera3D, _mouse_pos: Vector2) -> Dictionary:
		raycast_calls += 1
		return raycast_result


func test_placement_uses_level_root_snap_and_raycast():
	var tool = HFPolygonTool.new()
	var root := PlacementRoot.new()
	var camera := Camera3D.new()
	tool.root = root
	root.raycast_result = {"position": Vector3(3, 7, 9)}
	assert_eq(tool._snap(Vector3(3, 7, 9)), Vector3(4, 8, 8))
	assert_eq(tool._raycast_ground(camera, Vector2(20, 30)), Vector3(3, 7, 9))
	assert_eq(root.snap_calls, 1, "LevelRoot owns the snap settings")
	assert_eq(root.raycast_calls, 1, "LevelRoot owns visual and physics picking")
	root.raycast_result = {}
	assert_null(tool._raycast_ground(camera, Vector2.ZERO), "a shared raycast miss stays a miss")
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


func test_collinear_points():
	var pts = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(4, 0, 0)])
	assert_true(HFPolygonTool._is_convex_xz(pts), "Collinear points should pass")


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
	assert_eq(tool._height, 32.0, "Finalization should reset instead of applying stale motion")
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
