extends GutTest

const HFPolygonTool = preload("res://addons/hammerforge/hf_polygon_tool.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")

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
