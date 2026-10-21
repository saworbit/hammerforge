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
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])  # Flat — no height diff
	tool.set_setting("stair_step_height", 0.25)
	var result = tool._build_stairs(4.0, 4.0, "grp", 99)
	assert_eq(result.size(), 0, "Flat segment should produce no stairs")


func test_build_stairs_slope_segment():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 2, 0)])  # 2m height diff
	tool.set_setting("stair_step_height", 0.25)
	tool._ground_y = 0.0
	var result = tool._build_stairs(4.0, 4.0, "grp", 99)
	assert_gt(result.size(), 0, "Sloped segment should produce stairs")
	# With 2m height and 0.25 step = 8 steps
	assert_eq(result.size(), 8, "Should produce 8 steps for 2m / 0.25")


func test_build_stairs_step_count():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 1, 0)])
	tool.set_setting("stair_step_height", 0.5)
	tool._ground_y = 0.0
	var result = tool._build_stairs(4.0, 4.0, "grp", 99)
	# 1m / 0.5 = 2 steps
	assert_eq(result.size(), 2)


func test_build_stairs_group_id():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 2, 0)])
	tool.set_setting("stair_step_height", 0.5)
	tool._ground_y = 0.0
	var result = tool._build_stairs(4.0, 4.0, "mygroup", 99)
	for info in result:
		assert_eq(info.get("group_id", ""), "mygroup")


func test_build_stairs_has_faces():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 3, 0)])
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
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	tool.set_setting("railing_height", 1.0)
	tool.set_setting("railing_thickness", 0.1)
	tool.set_setting("railing_post_spacing", 2.0)
	tool._ground_y = 0.0
	var result = tool._build_railings(4.0, "grp", 99)
	assert_gt(result.size(), 0, "Should produce railing brushes")


func test_build_railings_both_sides():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	tool.set_setting("railing_height", 1.0)
	tool.set_setting("railing_thickness", 0.1)
	tool.set_setting("railing_post_spacing", 100.0)  # Large spacing = fewer posts
	tool._ground_y = 0.0
	var result = tool._build_railings(4.0, "grp", 99)
	# At minimum: 2 top rails + 2 posts per side (endpoints) = 2 + 4 = 6
	assert_gte(result.size(), 2, "Should have at least 2 top rails")


func test_build_railings_post_count():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
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
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0)])
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
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 0)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	assert_eq(result.size(), 2, "Should produce 2 trim strips (left + right)")


func test_build_trim_material_assignment():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 5)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	for info in result:
		for face_dict in info["faces"]:
			assert_eq(face_dict.get("material_idx", 0), 5, "Trim faces should have material 5")


func test_build_trim_material_slot_zero():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 0)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	assert_gt(result.size(), 0)
	for info in result:
		for face_dict in info["faces"]:
			assert_eq(
				face_dict.get("material_idx", -1),
				0,
				"Palette slot 0 must be written, not left unassigned",
			)


func test_build_trim_both_sides():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 5)])
	tool.set_setting("trim_width", 0.5)
	tool.set_setting("trim_height", 0.1)
	tool.set_setting("trim_material_idx", 0)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	assert_eq(result.size(), 2, "Should always produce pairs (left + right)")


func test_build_trim_multi_segment():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(5, 0, 5)])
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 0)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	assert_eq(result.size(), 4, "2 segments * 2 sides = 4 trim strips")


func test_build_trim_group_id():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
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
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 5, 0)])
	tool.set_setting("stair_step_height", 0.0)
	tool._ground_y = 0.0
	# Should not crash; step_h clamped
	var result = tool._build_stairs(4.0, 4.0, "grp", 99)
	# With 0.0 clamped to 0.01, should produce stairs
	assert_true(result is Array)


func test_stairs_preserve_vertical_placement():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 4, 0)])  # 4m rise
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
		assert_gt(
			centers_y[i],
			centers_y[i - 1],
			(
				"Step %d center Y (%.2f) should be above step %d (%.2f)"
				% [i, centers_y[i], i - 1, centers_y[i - 1]]
			)
		)


func test_railings_preserve_slope():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 5, 0)])  # 5m rise
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
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(0.005, 0, 0)])  # Too short
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 0)
	tool._ground_y = 0.0
	var result = tool._build_trim(4.0, "grp", 99)
	assert_eq(result.size(), 0, "Degenerate segment should produce no trim")


# ===========================================================================
# Extras on mitred, closed and one-sided paths (#1412)
# ===========================================================================


## An info's faces with their corners in world space.
func _world_faces(info: Dictionary) -> Array:
	var out: Array = []
	for face_dict in info["faces"]:
		var face = FaceData.from_dict(face_dict)
		var verts := PackedVector3Array()
		for v in face.local_verts:
			verts.append(v + info["center"])
		face.local_verts = verts
		face.ensure_geometry()
		out.append(face)
	return out


func _top_ring(info: Dictionary) -> PackedVector2Array:
	for face: FaceData in _world_faces(info):
		if face.normal.y > 0.9:
			var ring := PackedVector2Array()
			for v in face.local_verts:
				ring.append(Vector2(v.x, v.z))
			return ring
	return PackedVector2Array()


func _overlap(infos: Array) -> float:
	var total := 0.0
	for i in infos.size():
		for j in range(i + 1, infos.size()):
			for piece in Geometry2D.intersect_polygons(_top_ring(infos[i]), _top_ring(infos[j])):
				total += absf(_signed_area(piece))
	return total


static func _signed_area(ring: PackedVector2Array) -> float:
	var twice := 0.0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		twice += a.x * b.y - b.x * a.y
	return twice * 0.5


func _trim_tool(points: Array) -> Object:
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array(points)
	tool.set_setting("trim_width", 0.3)
	tool.set_setting("trim_height", 0.15)
	tool.set_setting("trim_material_idx", 0)
	return tool


func test_trim_turns_a_corner_on_the_walls_planes():
	# Trim used to be a straight strip per segment, overlapping itself on the
	# inside of every corner and leaving a notch on the outside.
	var tool = _trim_tool([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)])
	var trims: Array = tool._build_trim(4.0, "grp", 99)
	assert_eq(trims.size(), 4)
	var bisector := Vector3(1, 0, 1).normalized()
	var ending_on_it := 0
	for info in trims:
		var faces := _world_faces(info)
		var interior := HFConvexClip.interior_point(faces)
		assert_true(HFConvexClip.is_convex_solid(faces, interior), "a strip is convex")
		for face: FaceData in faces:
			var on := true
			for v in face.local_verts:
				on = on and absf(bisector.dot(v - Vector3(10, 0, 0))) < 0.0001
			if on:
				ending_on_it += 1
	assert_eq(ending_on_it, 4, "each strip ends on the corner's bisector plane, as the walls do")
	var walls: Array = tool._band_pieces(tool._band_for(4.0), 4.0, 4.0, "grp")
	assert_almost_eq(_overlap(trims + walls), 0.0, 0.0001, "nothing overlaps")


func test_trim_runs_round_a_closed_loop():
	var square := [Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 8), Vector3(0, 0, 8)]
	var tool = _trim_tool(square)
	tool._closed = true
	assert_eq(tool._build_trim(1.0, "grp", 99).size(), 8, "4 sides * 2 strips")


func test_trim_that_has_no_room_on_a_short_segment_refuses_the_path_by_name():
	# Walls 2 wide fit a middle segment 2.2 long; the trim inside them does not.
	var u_turn := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 2.2), Vector3(0, 0, 2.2)]
	var tool = _trim_tool(u_turn)
	tool.set_setting("path_width", 2.0)
	assert_eq(tool._refusal(), "", "no trim, nothing in the way")
	tool.set_setting("path_extra", HFPathTool.PathExtra.TRIM)
	var refusal: String = tool._refusal()
	assert_string_contains(refusal, "segment 2")
	assert_string_contains(refusal, "the trim's mitred corners")


func test_railings_stand_on_the_edges_of_a_path_to_one_side():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	tool.set_setting("path_side", HFPathTool.PathSide.LEFT)
	tool.set_setting("railing_post_spacing", 100.0)
	var result: Array = tool._build_railings(4.0, "grp", 99)
	assert_gt(result.size(), 0)
	var edges := {}
	for info in result:
		edges[roundi(info["center"].z)] = true
	assert_eq(edges.keys().size(), 2, "two edges")
	assert_true(edges.has(-4) and edges.has(0), "on the left of the line: %s" % [edges.keys()])


func test_stairs_span_a_path_to_one_side():
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 2, 0)])
	tool.set_setting("stair_step_height", 0.5)
	tool.set_setting("path_side", HFPathTool.PathSide.RIGHT)
	var result: Array = tool._build_stairs(4.0, 4.0, "grp", 99)
	assert_eq(result.size(), 4)
	for info in result:
		assert_almost_eq(info["center"].z, 2.0, 0.001, "centred on the band right of the line")


func test_extras_follow_a_closed_loop_round_to_its_first_point():
	var square := [Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 8), Vector3(0, 0, 8)]
	var tool = HFPathTool.new()
	tool._waypoints = PackedVector3Array(square)
	tool._closed = true
	tool.set_setting("railing_post_spacing", 100.0)
	var rails := 0
	for info in tool._build_railings(1.0, "grp", 99):
		if info["size"].y < 0.5:
			rails += 1
	assert_eq(rails, 8, "a rail along both edges of all four sides")
