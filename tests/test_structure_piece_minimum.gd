extends GutTest

## No structure piece is too thin to build (#1605).
##
## A piece the brush system reads as an axis-aligned box becomes a box brush, which
## rebuilds from its size whenever its scene opens, so a box is held to
## `HFBrushSystem.MIN_BRUSH_EXTENT`. Since #1598 the box test takes no box thinner
## than that; a thinner box-shaped piece is CUSTOM. The Door Frame's posts, flat head
## and cut are boxes, and so is any piece of an Arch, Dome or Ring that comes out
## square to the axes. Every other piece is built from its faces and keeps them at
## any size (#1603), so it is held only against a sliver: under Validate's
## near-zero thickness, the narrowest way across. Stairs and Spiral Stairs have a
## check of their own (#1582).

const HFBrushSystemScript = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFGeneratorSchemaScript = preload("res://addons/hammerforge/hf_generator_schema.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFArchBuilderScript = preload("res://addons/hammerforge/hf_arch_builder.gd")
const HFDomeBuilderScript = preload("res://addons/hammerforge/hf_dome_builder.gd")
const HFRingBuilderScript = preload("res://addons/hammerforge/hf_ring_builder.gd")
const HFDoorFrameBuilderScript = preload("res://addons/hammerforge/hf_door_frame_builder.gd")
const HFConvexClipScript = preload("res://addons/hammerforge/hf_convex_clip.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")

## Settings that drive a size the fields only feed towards its least: segments
## short along the curve, near half a turn or square to an axis, a short ring, a
## thin tube, an arched head of many pieces or an odd count, posts under an arch.
const KINDS := {
	"arch":
	[
		{},
		{"segments": 128},
		{"segments": 128, "radius": 5.0},
		{"segments": 3, "wall_thickness": 0.05},
		{"segments": 1, "arc_degrees": 179.0},
	],
	"dome":
	[
		{},
		{"rings": 32, "segments": 8},
		{"segments": 64, "rings": 4},
		{"sweep_degrees": 1.0, "arc_degrees": 20.0, "segments": 10},
	],
	"ring":
	[
		{},
		{"ring_segments": 128, "radius": 0.2, "tube_radius": 0.05},
		{"ring_segments": 2, "sweep_degrees": 358.0},
		{"tube_segments": 4, "ring_segments": 8, "sweep_degrees": 10.0},
		{"tube_segments": 3},
	],
	"door_frame":
	[
		{},
		{"proud": 0.0},
		{"head": 1},
		{"head": 1, "segments": 64},
		{"head": 1, "segments": 5},
		{"head": 1, "height": 0.6},
		{"head": 1, "segments": 64, "width": 0.1, "height": 0.2},
	],
}


## The values worth trying in a numeric field: its two ends, and one step either
## side of zero where it reaches that far.
func _probes(field: Dictionary) -> Array:
	if str(field["type"]) == HFGeneratorSchemaScript.TYPE_INT:
		return [int(field["min"]), int(field["max"])]
	var low := float(field["min"])
	var high := float(field["max"])
	var out: Array = [low, high]
	for value in [float(field["step"]), -float(field["step"])]:
		if value >= low and value <= high:
			out.append(value)
	return out


## How far a size read off float corners this far from the origin can be out.
func _float_slack(box: AABB) -> float:
	var far := maxf(box.position.abs()[box.position.abs().max_axis_index()], 1.0)
	far = maxf(far, box.end.abs()[box.end.abs().max_axis_index()])
	return far * 0.000001 + 0.00001


## How thin a built piece is the narrowest way across: the least spread of its
## corners along any of its own face normals.
func _thickness(piece: Array) -> float:
	var thinnest := INF
	for face in piece:
		var low := INF
		var high := -INF
		for other in piece:
			for corner: Vector3 in other.local_verts:
				low = minf(low, face.normal.dot(corner))
				high = maxf(high, face.normal.dot(corner))
		thinnest = minf(thinnest, high - low)
	return thinnest


## The first piece too thin to build, or "" when there is none or the settings are
## refused with a reason. A piece the brush system would make a box is held to the
## brush minimum on every side; any other only against a sliver.
func _thinnest_problem(type: String, settings: Dictionary) -> String:
	var check = HFGeneratorSystemScript.can_build(type, settings)
	if not check.ok:
		return "" if str(check.message) != "" else "a refusal that says nothing"
	var smallest: float = HFBrushSystemScript.MIN_BRUSH_EXTENT
	for piece in HFGeneratorSystemScript.build_faces(type, settings):
		var box: AABB = SolidChecks.bounds(piece)
		if not HFConvexClipScript.is_axis_aligned_box(piece).is_empty():
			if box.size[box.size.min_axis_index()] < smallest - _float_slack(box):
				return "a box %s" % box.size
		elif _thickness(piece) < HFConvexClipScript.NEAR_ZERO_THICKNESS:
			return "a sliver %s across" % _thickness(piece)
	return ""


func test_no_setting_the_fields_accept_builds_a_piece_too_thin_to_build():
	for type: String in KINDS:
		var schema := HFGeneratorSystemScript.settings_schema(type)
		for kind: Dictionary in KINDS[type]:
			for field: Dictionary in schema:
				if str(field["type"]) not in ["float", "int"]:
					continue
				for value in _probes(field):
					var settings := HFGeneratorSystemScript.default_settings(type)
					settings.merge(kind, true)
					settings[field["key"]] = value
					var problem := _thinnest_problem(type, settings)
					assert_eq(problem, "", "%s %s = %s, %s" % [type, field["key"], value, kind])
					if problem != "":
						return


func test_every_field_that_sizes_a_box_starts_at_the_brush_minimum():
	var smallest: float = HFBrushSystemScript.MIN_BRUSH_EXTENT
	var schema := HFGeneratorSystemScript.settings_schema("door_frame")
	for key in ["width", "height", "wall", "frame"]:
		var field := HFGeneratorSchemaScript.field(schema, key)
		assert_almost_eq(float(field["min"]), smallest, 0.000001, key)
	for builder in [
		HFArchBuilderScript, HFDomeBuilderScript, HFRingBuilderScript, HFDoorFrameBuilderScript
	]:
		assert_eq(builder.MIN_PIECE, smallest)


func test_a_field_that_sizes_only_pieces_built_from_their_faces_is_not_held_to_it():
	# A wall or depth under 0.1 makes no box unless a piece is square to an axis,
	# which validate() holds on its own.
	var smallest: float = HFBrushSystemScript.MIN_BRUSH_EXTENT
	var custom := {
		"arch": ["radius", "wall_thickness", "depth"],
		"dome": ["radius", "wall_thickness"],
		"ring": ["radius", "tube_radius"],
	}
	for type: String in custom:
		var schema := HFGeneratorSystemScript.settings_schema(type)
		for key: String in custom[type]:
			var field := HFGeneratorSchemaScript.field(schema, key)
			assert_lt(float(field["min"]), smallest, "%s %s" % [type, key])


func test_the_boxes_at_their_smallest_build_in_a_level_with_no_warning_and_reopen_the_same():
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	# Every field that sizes a box at its minimum, and an arch whose end segments
	# are square to the axes, with what the rest need to build.
	var smallest := [
		["door_frame", {"width": 0.1, "height": 0.1, "wall": 0.1, "frame": 0.1, "proud": 0.0}, 4],
		[
			"door_frame",
			{
				"head": 1,
				"segments": 2,
				"width": 0.1,
				"height": 0.15,
				"wall": 0.1,
				"frame": 0.1,
				"proud": 0.0
			},
			2
		],
		["arch", {"segments": 128, "radius": 5.0}, 4],
	]
	HFLog.begin_test_capture(["cannot be built"])
	for i in smallest.size():
		var entry: Array = smallest[i]
		var settings := HFGeneratorSystemScript.default_settings(entry[0])
		settings.merge(entry[1], true)
		var placement := Transform3D(Basis.IDENTITY, Vector3(20.0 * i, 0, 0))
		assert_true(root.generator_system.create(entry[0], settings, placement).ok, str(entry))
	var warned := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(warned, [], "no box is under the brush minimum")
	var records: Array = root.generator_system.generators.values()
	assert_eq(records.size(), smallest.size())
	for i in records.size():
		var boxes := 0
		for brush_id in records[i].brush_ids:
			var brush: DraftBrush = root.brush_system.find_brush_by_id(str(brush_id))
			if brush.shape != LevelRoot.BrushShape.BOX:
				continue
			boxes += 1
			var was := HFBakeSystem.brush_world_aabb(brush, brush.global_transform)
			# What a reopen does to a box.
			brush.size = brush.size
			var now := HFBakeSystem.brush_world_aabb(brush, brush.global_transform)
			assert_true(
				now.size.is_equal_approx(was.size), "%s rebuilt as %s" % [was.size, now.size]
			)
		# The pieces square to the axes are the boxes the level made.
		assert_eq(boxes, smallest[i][2], str(smallest[i]))
