extends GutTest

const HFPathTool = preload("res://addons/hammerforge/hf_path_tool.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")


# ===========================================================================
# Extended settings schema
# ===========================================================================


func test_settings_schema_includes_extras():
	var tool = HFPathTool.new()
	var schema = tool.get_settings_schema()
	var names: Array = []
	for s in schema:
		names.append(s.name)
	assert_has(names, "path_extra")
	assert_has(names, "stair_step_height")
	assert_has(names, "railing_height")
	assert_has(names, "railing_thickness")
	assert_has(names, "railing_post_spacing")
	assert_has(names, "trim_width")
	assert_has(names, "trim_height")
	assert_has(names, "trim_material_idx")


func test_path_extra_default_is_none():
	var tool = HFPathTool.new()
	assert_eq(tool.get_setting("path_extra"), 0)


func test_path_extra_enum_options():
	var tool = HFPathTool.new()
	var schema = tool.get_settings_schema()
	var extra_schema: Dictionary = {}
	for s in schema:
		if s.name == "path_extra":
			extra_schema = s
			break
	assert_eq(extra_schema.get("type", ""), "enum")
	var options: Array = extra_schema.get("options", [])
	assert_eq(options.size(), 4)
	assert_eq(options[0], "None")
	assert_eq(options[1], "Stairs")
	assert_eq(options[2], "Railings")
	assert_eq(options[3], "Trim")


# ===========================================================================
# Stair generation
# ===========================================================================


func test_build_stairs_flat_segment():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0)  # Flat — no height diff
	])
	tool.set_setting("stair_step_height", 0.25)
	var result = tool._build_stairs(4.0, 4.0, "grp", 99)
	assert_eq(result.size(), 0, "Flat segment should produce no stairs")


func test_build_stairs_slope_segment():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 2, 0)  # 2m height diff
	])
	tool.set_setting("stair_step_height", 0.25)
	tool._ground_y = 0.0
	var result = tool._build_stairs(4.0, 4.0, "grp", 99)
	assert_gt(result.size(), 0, "Sloped segment should produce stairs")
	# With 2m height and 0.25 step = 8 steps
	assert_eq(result.size(), 8, "Should produce 8 steps for 2m / 0.25")


func test_build_stairs_step_count():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(5, 1, 0)
	])
	tool.set_setting("stair_step_height", 0.5)
	tool._ground_y = 0.0
	var result = tool._build_stairs(4.0, 4.0, "grp", 99)
	# 1m / 0.5 = 2 steps
	assert_eq(result.size(), 2)


func test_build_stairs_group_id():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 2, 0)
	])
	tool.set_setting("stair_step_height", 0.5)
	tool._ground_y = 0.0
	var result = tool._build_stairs(4.0, 4.0, "mygroup", 99)
	for info in result:
		assert_eq(info.get("group_id", ""), "mygroup")


func test_build_stairs_has_faces():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 3, 0)
	])
	tool.set_setting("stair_step_height", 1.0)
	tool._ground_y = 0.0
	var result = tool._build_stairs(4.0, 4.0, "grp", 99)
	for info in result:
		assert_true(info.has("faces"), "Each stair brush should have faces")
		assert_gt(info["faces"].size(), 0)


# ===========================================================================
# Railing generation
# ===========================================================================


func test_build_railings_basic():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0)
	])
	tool.set_setting("railing_height", 1.0)
	tool.set_setting("railing_thickness", 0.1)
	tool.set_setting("railing_post_spacing", 2.0)
	tool._ground_y = 0.0
	var result = tool._build_railings(4.0, "grp", 99)
	assert_gt(result.size(), 0, "Should produce railing brushes")


func test_build_railings_both_sides():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0)
	])
	tool.set_setting("railing_height", 1.0)
	tool.set_setting("railing_thickness", 0.1)
	tool.set_setting("railing_post_spacing", 100.0)  # Large spacing = fewer posts
	tool._ground_y = 0.0
	var result = tool._build_railings(4.0, "grp", 99)
	# At minimum: 2 top rails + 2 posts per side (endpoints) = 2 + 4 = 6
	assert_gte(result.size(), 2, "Should have at least 2 top rails")


func test_build_railings_post_count():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0)
	])
	tool.set_setting("railing_height", 1.0)
	tool.set_setting("railing_thickness", 0.1)
	tool.set_setting("railing_post_spacing", 5.0)
	tool._ground_y = 0.0
	var result = tool._build_railings(4.0, "grp", 99)
	# 10m length / 5m spacing + 1 = 3 posts per side = 6 posts + 2 rails = 8
	var post_count := result.size() - 2  # subtract 2 top rails
	assert_gte(post_count, 4, "Should have posts on both sides")


func test_build_railings_group_id():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(5, 0, 0)
	])
	tool.set_setting("railing_height", 1.0)
	tool.set_setting("railing_thickness", 0.1)
	tool.set_setting("railing_post_spacing", 2.0)
	tool._ground_y = 0.0
	var result = tool._build_railings(4.0, "rail_grp", 99)
	for info in result:
		assert_eq(info.get("group_id", ""), "rail_grp")


# ===========================================================================
# Trim generation
# ===========================================================================


func test_build_trim_basic():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0)
	])
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 0)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	assert_eq(result.size(), 2, "Should produce 2 trim strips (left + right)")


func test_build_trim_material_assignment():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0)
	])
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 5)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	for info in result:
		for face_dict in info["faces"]:
			assert_eq(face_dict.get("material_idx", 0), 5, "Trim faces should have material 5")


func test_build_trim_both_sides():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(5, 0, 5)
	])
	tool.set_setting("trim_width", 0.5)
	tool.set_setting("trim_height", 0.1)
	tool.set_setting("trim_material_idx", 0)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	assert_eq(result.size(), 2, "Should always produce pairs (left + right)")


func test_build_trim_multi_segment():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(5, 0, 5)
	])
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 0)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	assert_eq(result.size(), 4, "2 segments * 2 sides = 4 trim strips")


func test_build_trim_group_id():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0)
	])
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 0)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "trim_grp", 99)
	for info in result:
		assert_eq(info.get("group_id", ""), "trim_grp")


# ===========================================================================
# HUD lines
# ===========================================================================


func test_hud_lines_show_auto_mode():
	var tool = HFPathTool.new()
	tool.set_setting("path_extra", HFPathTool.PathExtra.STAIRS)
	var lines := tool.get_shortcut_hud_lines()
	var found := false
	for line in lines:
		if "Stairs" in line:
			found = true
			break
	assert_true(found, "HUD should mention Stairs when mode is active")


func test_hud_lines_no_auto_when_none():
	var tool = HFPathTool.new()
	tool.set_setting("path_extra", HFPathTool.PathExtra.NONE)
	var lines := tool.get_shortcut_hud_lines()
	var found := false
	for line in lines:
		if "Auto:" in line:
			found = true
			break
	assert_false(found, "HUD should not show Auto: line when mode is NONE")


# ===========================================================================
# Edge cases
# ===========================================================================


func test_build_stairs_zero_step_height():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 5, 0)
	])
	tool.set_setting("stair_step_height", 0.0)
	tool._ground_y = 0.0
	# Should not crash; step_h clamped
	var result = tool._build_stairs(4.0, 4.0, "grp", 99)
	# With 0.0 clamped to 0.01, should produce stairs
	assert_true(result is Array)


func test_stairs_preserve_vertical_placement():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 4, 0)  # 4m rise
	])
	tool.set_setting("stair_step_height", 1.0)
	tool._ground_y = 0.0
	var result = tool._build_stairs(4.0, 4.0, "grp", 99)
	assert_eq(result.size(), 4, "Should produce 4 steps for 4m / 1.0")
	# Each stair's center Y should increase — not all at _ground_y
	var centers_y: Array = []
	for info in result:
		centers_y.append(info["center"].y)
	# Steps should be at increasing Y values
	for i in range(1, centers_y.size()):
		assert_gt(centers_y[i], centers_y[i - 1],
			"Step %d center Y (%.2f) should be above step %d (%.2f)" % [
				i, centers_y[i], i - 1, centers_y[i - 1]])


func test_railings_preserve_slope():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 5, 0)  # 5m rise
	])
	tool.set_setting("railing_height", 1.0)
	tool.set_setting("railing_thickness", 0.1)
	tool.set_setting("railing_post_spacing", 100.0)  # just top rails
	tool._ground_y = 0.0
	var result = tool._build_railings(4.0, "grp", 99)
	# Find the top rail brushes (thin rail_t x rail_t cross-section)
	var rail_centers_y: Array = []
	for info in result:
		if info["size"].y < 0.5:  # thin top rail, not a post
			rail_centers_y.append(info["center"].y)
	assert_gte(rail_centers_y.size(), 2, "Should have at least 2 top rails")
	# Rail center should be above ground: at (0+5)/2 + 1.0 = 3.5 area
	for cy in rail_centers_y:
		assert_gt(cy, 1.0, "Rail center Y (%.2f) should reflect slope + rail height" % cy)


func test_trim_short_segment():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0.005, 0, 0)  # Too short
	])
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 0)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	assert_eq(result.size(), 0, "Degenerate segment should produce no trim")
