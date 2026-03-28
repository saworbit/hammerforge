extends GutTest

const HFPathTool = preload("res://addons/hammerforge/hf_path_tool.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")


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
	assert_eq(schema.size(), 3, "Should have width, height, miter settings")
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
	var info = tool._build_segment_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 0), 4.0, 4.0, "grp1"
	)
	assert_false(info.is_empty(), "Should produce a brush info dict")
	assert_eq(info.group_id, "grp1")
	assert_true(info.has("faces"), "Should have face data")
	assert_eq(info.faces.size(), 6, "Segment brush should have 6 faces (box)")


func test_build_segment_brush_diagonal():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 10), 4.0, 4.0, "grp2"
	)
	assert_false(info.is_empty(), "Diagonal segment should produce a brush")
	assert_eq(info.faces.size(), 6)


func test_build_segment_brush_zero_length():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(
		Vector3(0, 0, 0), Vector3(0, 0, 0), 4.0, 4.0, "grp3"
	)
	assert_true(info.is_empty(), "Zero-length segment should return empty")


func test_segment_center_is_midpoint():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(
		Vector3(0, 0, 0), Vector3(20, 0, 0), 4.0, 8.0, "grp4"
	)
	assert_almost_eq(info.center.x, 10.0, 0.01, "Center X should be midpoint")
	assert_almost_eq(info.center.y, 4.0, 0.01, "Center Y should be ground + half_h")
	assert_almost_eq(info.center.z, 0.0, 0.01, "Center Z should be midpoint")


func test_segment_size():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(
		Vector3(0, 0, 0), Vector3(20, 0, 0), 6.0, 8.0, "grp5"
	)
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
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10),
		4.0, 4.0, "grp_m"
	)
	assert_false(info.is_empty(), "90-degree turn should produce a miter brush")
	assert_true(info.has("faces"), "Miter should have face data")
	assert_true(info.faces.size() >= 5, "Miter should have at least 5 faces (3 sides + top + bot)")


func test_miter_joint_straight_skipped():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_miter_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0),
		4.0, 4.0, "grp_m2"
	)
	assert_true(info.is_empty(), "Straight path should skip miter (dot > 0.98)")


func test_miter_joint_acute_skipped():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	# 180 degree turn (doubling back)
	var info = tool._build_miter_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 0, 0.01),
		4.0, 4.0, "grp_m3"
	)
	assert_true(info.is_empty(), "Acute reversal should skip miter")


func test_miter_joint_has_group_id():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_miter_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10),
		4.0, 4.0, "mygroup"
	)
	if not info.is_empty():
		assert_eq(info.group_id, "mygroup")


# ===========================================================================
# Face data validation
# ===========================================================================

func test_segment_faces_are_valid_dicts():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 0), 4.0, 4.0, "test"
	)
	for face_dict in info.faces:
		assert_true(face_dict is Dictionary, "Each face should be a dict")
		assert_true(face_dict.has("local_verts"), "Face should have local_verts")
		assert_true(face_dict.has("normal"), "Face should have normal")


func test_segment_faces_reconstruct_as_face_data():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(
		Vector3(0, 0, 0), Vector3(10, 0, 0), 4.0, 4.0, "test"
	)
	for face_dict in info.faces:
		var face = FaceData.from_dict(face_dict)
		assert_not_null(face, "Face should deserialize")
		assert_true(face.local_verts.size() >= 3, "Face should have 3+ verts")
