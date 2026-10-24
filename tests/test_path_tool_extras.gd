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


# ===========================================================================
# Trim profiles (#1413)
# ===========================================================================

const TrimProfile = preload("res://addons/hammerforge/hf_trim_profile.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")

## The trim every profile test builds: 0.3 out by 0.15 up, as the defaults are.
const TRIM_W := 0.3
const TRIM_H := 0.15

## How far apart two section corners may be and count as the one point.
const SECTION_EPS := 0.00001

## Every profile, and the strips a side a segment gets at the default 4 segments
## and 0.3 by 0.15. Flat, Chamfer and Round are convex, so one strip. Cove is a
## strip a piece. Ogee's round upper half is one strip, which the last hollow
## piece below runs straight on into, and the hollow's foot, too thin to stand
## alone, goes into the piece above it. Stepped is a strip a step.
const STRIPS_A_SIDE := {
	TrimProfile.Profile.FLAT: 1,
	TrimProfile.Profile.CHAMFER: 1,
	TrimProfile.Profile.ROUND: 1,
	TrimProfile.Profile.COVE: 4,
	TrimProfile.Profile.OGEE: 3,
	TrimProfile.Profile.STEPPED: 3,
}


## A tool building `profile` trim along `points`, the trim 0.3 by 0.15.
func _profile_tool(points: Array, profile: int, segments := 4, flipped := false) -> Object:
	var tool = _trim_tool(points)
	tool.set_setting("trim_width", TRIM_W)
	tool.set_setting("trim_height", TRIM_H)
	tool.set_setting("trim_profile", profile)
	tool.set_setting("trim_segments", segments)
	tool.set_setting("trim_flip", flipped)
	return tool


## The strips right of a path running along +X from the origin, 4 wide and
## centred, as (out, up) rings: each strip's face on the plane X = 0, its corners
## measured out from the path's right edge at Z = 2 and up from Y = 0.
func _right_sections(infos: Array) -> Array:
	var sections: Array = []
	for info in infos:
		if info["center"].z < 0.0:
			continue
		for face: FaceData in _world_faces(info):
			var on_start := true
			for v in face.local_verts:
				on_start = on_start and absf(v.x) < SECTION_EPS
			if not on_start:
				continue
			var ring := PackedVector2Array()
			for v in face.local_verts:
				ring.append(Vector2(v.z - 2.0, v.y))
			sections.append(ring)
	return sections


static func _distance_to_ring(point: Vector2, ring: PackedVector2Array) -> float:
	var best := INF
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return best


func _assert_bands(bands: Array, expected: Array, note: String) -> void:
	assert_eq(bands.size(), expected.size(), "%s: band count" % note)
	for b in mini(bands.size(), expected.size()):
		var ring: PackedVector2Array = bands[b]
		assert_eq(ring.size(), expected[b].size(), "%s band %d: corners %s" % [note, b, ring])
		for c in mini(ring.size(), expected[b].size()):
			var near := Vector2(SECTION_EPS, SECTION_EPS)
			assert_almost_eq(ring[c], expected[b][c], near, "%s band %d" % [note, b])


func test_each_profile_builds_its_strips_on_both_sides_of_every_segment():
	var path := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)]
	for profile in STRIPS_A_SIDE:
		var tool = _profile_tool(path, profile)
		var expected: int = STRIPS_A_SIDE[profile] * 2 * 2
		var strips: Array = tool._build_trim(4.0, "grp", 99)
		assert_eq(
			strips.size(), expected, "%s: both sides of both segments" % TrimProfile.NAMES[profile]
		)


func test_cove_and_ogee_bands_are_pinned():
	# Cove: a quarter of the ellipse centred on the outer top corner, from all the
	# way out at the base to in at the top, cut every eighth of a turn.
	var cove: Array = []
	for k in 5:
		var turn := PI * 0.125 * k
		cove.append(Vector2(TRIM_W - TRIM_W * sin(turn), TRIM_H - TRIM_H * cos(turn)))
	var expected_cove := [
		[Vector2(0, 0), cove[0], cove[1], Vector2(0, cove[1].y)],
		[Vector2(0, cove[1].y), cove[1], cove[2], Vector2(0, cove[2].y)],
		[Vector2(0, cove[2].y), cove[2], cove[3], Vector2(0, cove[3].y)],
		[Vector2(0, cove[3].y), cove[3], cove[4]],
	]
	var cove_bands := TrimProfile.bands(TrimProfile.Profile.COVE, TRIM_W, TRIM_H, 4)
	_assert_bands(cove_bands, expected_cove, "cove")

	# Ogee: hollow below and round above, each a quarter of an ellipse half the size.
	var low: Array = []
	var high: Array = []
	for k in 5:
		var turn := PI * 0.125 * k
		low.append(Vector2(TRIM_W - TRIM_W * 0.5 * sin(turn), TRIM_H * 0.5 * (1.0 - cos(turn))))
		high.append(Vector2(TRIM_W * 0.5 * cos(turn), TRIM_H * 0.5 * (1.0 + sin(turn))))
	# The hollow's first piece rises 6 mm, so it goes into the next; its last runs
	# straight on into the round half through the point where the two meet upright.
	var expected_ogee := [
		[Vector2(0, 0), low[0], low[2], Vector2(0, low[2].y)],
		[Vector2(0, low[2].y), low[2], low[3], Vector2(0, low[3].y)],
		[Vector2(0, low[3].y), low[3], high[1], high[2], high[3], high[4]],
	]
	var ogee_bands := TrimProfile.bands(TrimProfile.Profile.OGEE, TRIM_W, TRIM_H, 4)
	_assert_bands(ogee_bands, expected_ogee, "ogee")
	assert_almost_eq(low[4], high[0], Vector2(SECTION_EPS, SECTION_EPS), "the halves meet")
	assert_lt(low[1].y, TrimProfile.MIN_BAND, "the foot left out is thinner than a band may be")


func test_every_strip_is_convex_for_every_profile_and_segment_count():
	# A right angle, and a corner sharp enough that its outside tip is cut flat.
	var turn := deg_to_rad(160.0)
	var sharp := Vector3(10, 0, 0) + Vector3(cos(turn), 0, sin(turn)) * 10.0
	var paths := [
		[Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)],
		[Vector3(0, 0, 0), Vector3(10, 0, 0), sharp],
	]
	var checked := 0
	var bent := 0
	for profile in STRIPS_A_SIDE:
		for segments in range(1, 17):
			for flipped in [false, true]:
				for path in paths:
					var tool = _profile_tool(path, profile, segments, flipped)
					tool.set_setting("path_width", 1.0)
					var strips: Array = tool._build_trim(1.0, "grp", 99)
					var note := (
						"%s, %d segments, flipped %s"
						% [TrimProfile.NAMES[profile], segments, flipped]
					)
					if strips.is_empty():
						fail_test("%s: no strips" % note)
					for info in strips:
						var faces := _world_faces(info)
						var inside := HFConvexClip.interior_point(faces)
						if not HFConvexClip.is_convex_solid(faces, inside, 0.0001):
							fail_test("%s: a strip is not convex" % note)
						if faces.size() > 6:
							bent += 1
						checked += 1
	assert_gt(checked, 2000, "every combination built its strips")
	assert_gt(bent, 0, "and some were cut flat at the sharp corner's tip, or shaped")


func test_the_strips_together_match_the_profile_within_a_millimetre():
	for profile in STRIPS_A_SIDE:
		for segments in [1, 4, 16]:
			var note := "%s, %d segments" % [TrimProfile.NAMES[profile], segments]
			var tool = _profile_tool([Vector3(0, 0, 0), Vector3(10, 0, 0)], profile, segments)
			var sections := _right_sections(tool._build_trim(4.0, "grp", 99))
			var outline := TrimProfile.outline(profile, TRIM_W, TRIM_H, segments)
			# Every sample point of the profile lies on the strips' outline.
			for point in outline:
				var nearest := INF
				for ring: PackedVector2Array in sections:
					nearest = minf(nearest, _distance_to_ring(point, ring))
				assert_lt(nearest, 0.001, "%s: %s is on a strip" % [note, point])
			# And between them the strips fill the profile, once over.
			var filled := 0.0
			for ring: PackedVector2Array in sections:
				filled += TrimProfile.area(ring)
			var profile_ring := PackedVector2Array([Vector2.ZERO])
			profile_ring.append_array(outline)
			assert_almost_eq(filled, TrimProfile.area(profile_ring), 0.000001, "%s: area" % note)
			var overlap := 0.0
			for i in sections.size():
				for j in range(i + 1, sections.size()):
					for piece in Geometry2D.intersect_polygons(sections[i], sections[j]):
						overlap += TrimProfile.area(piece)
			assert_almost_eq(overlap, 0.0, 0.000001, "%s: no two strips overlap" % note)


## How far out `profile`'s outline reaches at height `up`, cut fine.
func _reach_at(profile: int, up: float) -> float:
	var outline := TrimProfile.outline(profile, TRIM_W, TRIM_H, 16)
	for i in range(outline.size() - 1):
		var a := outline[i]
		var b := outline[i + 1]
		if up >= a.y and up <= b.y and b.y > a.y:
			return lerpf(a.x, b.x, (up - a.y) / (b.y - a.y))
	return 0.0


func test_the_profiles_have_the_shapes_their_names_say():
	var half := TRIM_H * 0.5
	var round_mid := _reach_at(TrimProfile.Profile.ROUND, half)
	assert_gt(round_mid, TRIM_W - TRIM_H * 0.5, "Round bulges out past its quarter's chord")
	assert_lt(_reach_at(TrimProfile.Profile.COVE, half), TRIM_W * 0.5, "Cove hollows in")
	var ogee_low := _reach_at(TrimProfile.Profile.OGEE, TRIM_H * 0.25)
	var ogee_high := _reach_at(TrimProfile.Profile.OGEE, TRIM_H * 0.75)
	assert_lt(ogee_low, TRIM_W * 0.75, "Ogee hollows below")
	assert_gt(ogee_high, TRIM_W * 0.25, "and bulges above")
	var step_mid := _reach_at(TrimProfile.Profile.STEPPED, half)
	assert_almost_eq(step_mid, TRIM_W * 2.0 / 3.0, 0.0001, "Stepped's middle step")
	var chamfer_top := _reach_at(TrimProfile.Profile.CHAMFER, TRIM_H)
	assert_almost_eq(chamfer_top, TRIM_W - TRIM_H * 0.5, 0.0001, "Chamfer cuts its top corner")


func test_a_curve_is_never_cut_into_a_band_thinner_than_a_centimetre():
	for profile in [TrimProfile.Profile.COVE, TrimProfile.Profile.OGEE]:
		for segments in range(1, 17):
			var note := "%s, %d segments" % [TrimProfile.NAMES[profile], segments]
			for ring: PackedVector2Array in TrimProfile.bands(profile, TRIM_W, TRIM_H, segments):
				var low := INF
				var high := -INF
				var out := 0.0
				for corner in ring:
					low = minf(low, corner.y)
					high = maxf(high, corner.y)
					out = maxf(out, corner.x)
				assert_gte(high - low, TrimProfile.MIN_BAND - 0.000001, "%s: tall enough" % note)
				assert_gte(out, TrimProfile.MIN_BAND - 0.000001, "%s: deep enough" % note)


func test_trim_flip_hangs_the_profile_upside_down_flush_with_the_top():
	var path := [Vector3(0, 0, 0), Vector3(10, 0, 0)]
	for profile in STRIPS_A_SIDE:
		var note: String = TrimProfile.NAMES[profile]
		var standing := _right_sections(_profile_tool(path, profile)._build_trim(4.0, "g", 99))
		var flipped = _profile_tool(path, profile, 4, true)
		var hanging := _right_sections(flipped._build_trim(4.0, "g", 99))
		var top := -INF
		var bottom := INF
		for ring: PackedVector2Array in hanging:
			for corner in ring:
				top = maxf(top, corner.y)
				bottom = minf(bottom, corner.y)
		assert_almost_eq(top, 4.0, SECTION_EPS, "%s: its top is the path's top" % note)
		assert_almost_eq(bottom, 4.0 - TRIM_H, SECTION_EPS, "%s: hanging the trim's height" % note)
		# Upside down: a corner standing at height h hangs at the top less h.
		for ring: PackedVector2Array in standing:
			for corner in ring:
				var mirrored := Vector2(corner.x, 4.0 - corner.y)
				var found := false
				for other: PackedVector2Array in hanging:
					for hung in other:
						found = found or hung.distance_to(mirrored) < 0.0001
				assert_true(found, "%s: %s hangs at %s" % [note, corner, mirrored])


func test_trim_material_lands_on_every_face_of_every_profile_slot_zero_included():
	var path := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)]
	for profile in STRIPS_A_SIDE:
		for slot in [0, 5]:
			var tool = _profile_tool(path, profile)
			tool.set_setting("trim_material_idx", slot)
			var faces := 0
			for info in tool._build_trim(4.0, "grp", 99):
				for face_dict in info["faces"]:
					faces += 1
					assert_eq(face_dict.get("material_idx", -1), slot, TrimProfile.NAMES[profile])
			assert_gt(faces, 0)


func test_the_hud_counts_the_strips_enter_would_build():
	var path := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)]
	var tool = _profile_tool(path, TrimProfile.Profile.COVE)
	tool.set_setting("path_extra", HFPathTool.PathExtra.TRIM)
	assert_eq(tool._build_trim(4.0, "grp", 99).size(), 16)
	assert_true(tool.get_shortcut_hud_lines().has("Auto: Trim (Cove, 16 strips)"))
	tool._waypoints = PackedVector3Array()
	assert_true(tool.get_shortcut_hud_lines().has("Auto: Trim (Cove, 4 strips a side)"))


func test_a_built_path_makes_every_profiled_strip_in_its_one_undo_step():
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	var undo = UndoStandIn.new()
	var path := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)]
	var tool = _profile_tool(path, TrimProfile.Profile.OGEE)
	tool.root = level
	tool.undo_redo = undo
	tool.set_setting("path_extra", HFPathTool.PathExtra.TRIM)
	tool._phase = tool.Phase.PLACING_WAYPOINTS
	assert_true(tool._build_path())
	var made: Array = level._iter_managed_brush_nodes()
	assert_eq(made.size(), 2 + 12, "two walls and the ogee's twelve strips")
	assert_eq(undo.scene_history.get_history_count(), 1, "in one undo step")
	undo.free_histories()
	tool.deactivate()
	await get_tree().process_frame
