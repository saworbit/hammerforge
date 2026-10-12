extends GutTest

## How smooth a round brush is, chosen by the mapper (#1085).
##
## A sphere, ellipsoid, capsule and torus were built from a fixed 16 segments by
## 8 bands (#1057) whatever their `sides` said, so there was no way to get a
## smoother one. They take their segments from `sides` now, as a cylinder does,
## and the bands follow. The count also has to come back with the brush: the
## record a brush is undone, reopened and duplicated from left `sides` out for
## every round shape, a cylinder included, and the faces it did carry hid that
## until the first resize built them again at the default.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const ROUND := {
	DraftBrush.BrushShape.SPHERE: "sphere",
	DraftBrush.BrushShape.ELLIPSOID: "ellipsoid",
	DraftBrush.BrushShape.CAPSULE: "capsule",
	DraftBrush.BrushShape.TORUS: "torus",
}

const LEVEL_PATH := "user://test_round_brush_sides.hflevel"


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _place(root: LevelRoot, shape: int, sides := -1, size := Vector3(2, 2, 2)) -> DraftBrush:
	var info := {
		"shape": shape,
		"size": size,
		"center": Vector3.ZERO,
		"operation": CSGShape3D.OPERATION_UNION,
	}
	if sides >= 0:
		info["sides"] = sides
	return root.create_brush_from_info(info) as DraftBrush


## How many segments go round a brush: the directions its corners lie in about
## its Y axis, which every round shape stands along. A pole is on the axis and
## has no direction. Directions closer than a twentieth of a degree are one, and
## so are the two ends of the circle.
func _segments(brush: DraftBrush) -> int:
	var degrees: Array[float] = []
	for face in brush.get_faces():
		for corner: Vector3 in face.local_verts:
			if Vector2(corner.x, corner.z).length() > 0.001:
				degrees.append(fposmod(rad_to_deg(atan2(corner.z, corner.x)), 360.0))
	degrees.sort()
	var count := 0
	var last := -INF
	for angle in degrees:
		if angle - last > 0.05:
			count += 1
		last = angle
	if count > 1 and degrees[-1] - degrees[0] > 360.0 - 0.05:
		count -= 1
	return count


func test_a_round_brush_takes_its_segments_from_its_sides():
	for shape in ROUND:
		var root := _fresh_root()
		# The default first, so faces kept per shape rather than per count would
		# hand the second brush the first one's.
		var as_default := _place(root, shape)
		var doubled := _place(root, shape, 32)
		assert_eq(
			_segments(as_default), DraftBrush.DEFAULT_ROUND_SIDES, "%s as it comes" % ROUND[shape]
		)
		assert_eq(_segments(doubled), 32, "%s with sides 32 has twice the segments" % ROUND[shape])


func test_the_default_sphere_is_still_128_faces():
	var root := _fresh_root()
	assert_eq(_place(root, DraftBrush.BrushShape.SPHERE).get_faces().size(), 128)
	assert_eq(
		_place(root, DraftBrush.BrushShape.SPHERE, 32).get_faces().size(),
		512,
		"32 segments by 16 bands"
	)


func test_the_bands_are_even_so_a_sphere_keeps_its_equator():
	# 18 segments would be 9 bands at half, and an odd count puts a band across
	# the equator rather than a ring on it, so the sphere is narrower than its size.
	for sides in [6, 10, 18, 32]:
		var root := _fresh_root()
		var sphere := _place(root, DraftBrush.BrushShape.SPHERE, sides)
		var on_equator := 0
		for face in sphere.get_faces():
			for corner: Vector3 in face.local_verts:
				var out := Vector2(corner.x, corner.z).length()
				if absf(corner.y) < 0.001 and absf(out - 1.0) < 0.001:
					on_equator += 1
		assert_gt(on_equator, 0, "%d sides: a ring on the equator" % sides)


func test_a_resize_keeps_a_round_brush_s_own_count():
	for shape in ROUND:
		var root := _fresh_root()
		var brush := _place(root, shape, 24)
		var faces := brush.get_faces().size()
		brush.size = Vector3(3, 3, 3)
		assert_eq(_segments(brush), 24, "%s resized" % ROUND[shape])
		assert_eq(brush.get_faces().size(), faces, "%s keeps its faces" % ROUND[shape])
	# A capsule longer than it is wide is built from other faces, the same way round.
	var root := _fresh_root()
	var capsule := _place(root, DraftBrush.BrushShape.CAPSULE, 24)
	capsule.size = Vector3(2, 6, 2)
	assert_eq(_segments(capsule), 24, "a capsule given a middle")


func test_a_change_of_sides_rebuilds_a_placed_round_brush():
	var root := _fresh_root()
	var sphere := _place(root, DraftBrush.BrushShape.SPHERE)
	sphere.sides = 32
	assert_eq(_segments(sphere), 32)
	sphere.sides = 16
	assert_eq(_segments(sphere), 16, "and back")
	assert_eq(sphere.get_faces().size(), 128)


func test_a_round_brush_stops_at_the_most_segments_it_is_built_from():
	var root := _fresh_root()
	var sphere := _place(
		root, DraftBrush.BrushShape.SPHERE, DraftBrush.MAX_ROUND_BRUSH_SEGMENTS + 1
	)
	assert_eq(_segments(sphere), DraftBrush.MAX_ROUND_BRUSH_SEGMENTS)
	# A cylinder costs two faces a side, and stays uncapped.
	var cylinder := _place(root, DraftBrush.BrushShape.CYLINDER, 96)
	assert_eq(_segments(cylinder), 96)


## Undo, reopen or duplicate a brush, and hand back what came back.
func _bring_back(root: LevelRoot, brush: DraftBrush, how: String) -> DraftBrush:
	var brush_id := brush.brush_id
	match how:
		"undo":
			root.restore_state(root.capture_state())
		"reopen":
			assert_eq(HFLevelIO.save_to_path(LEVEL_PATH, root._capture_hflevel_state()), OK)
			assert_true(root.load_hflevel(LEVEL_PATH), "the level loads")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(LEVEL_PATH))
		"duplicate":
			var info: Dictionary = root.brush_system.build_duplicate_info(brush, Vector3(8, 0, 0))
			return root.create_brush_from_info(info) as DraftBrush
	return root.find_brush_by_id(brush_id) as DraftBrush


func test_the_count_comes_back_with_the_brush():
	var cases := {
		DraftBrush.BrushShape.SPHERE: 32,
		DraftBrush.BrushShape.TORUS: 24,
		DraftBrush.BrushShape.CYLINDER: 8,
	}
	for shape in cases:
		var wanted: int = cases[shape]
		for how in ["undo", "reopen", "duplicate"]:
			var root := _fresh_root()
			var back := _bring_back(root, _place(root, shape, wanted), how)
			assert_not_null(back, "%d after %s" % [shape, how])
			if back == null:
				continue
			assert_eq(back.sides, wanted, "shape %d after %s" % [shape, how])
			# The record carries the faces, so only a rebuild shows the count.
			back.size = Vector3(4, 4, 4)
			assert_eq(_segments(back), wanted, "shape %d after %s, then resized" % [shape, how])


func test_a_drawn_round_brush_is_built_from_the_sides_it_was_drawn_with():
	var root := _fresh_root()
	root.drag_sides = 32
	for shape in ROUND:
		var info: Dictionary = root.drag_system._build_brush_info(
			Vector3.ZERO,
			Vector3(4, 0, 4),
			4.0,
			shape,
			Vector3(32, 32, 32),
			CSGShape3D.OPERATION_UNION,
			false,
			false
		)
		assert_eq(info.get("sides"), 32, ROUND[shape])


# ---------------------------------------------------------------------------
# The Inspector shows the count a round brush is built from (#1103)
# ---------------------------------------------------------------------------


func _sides_hint(brush: DraftBrush) -> String:
	for property in brush.get_property_list():
		if property["name"] == "sides":
			return str(property["hint_string"])
	return ""


func test_a_round_brush_s_sides_stop_at_five_in_the_inspector_and_a_pyramid_s_at_three():
	var root := _fresh_root()
	for shape in DraftBrush.ROUND_SHAPES:
		var brush := _place(root, shape, 8)
		assert_true(_sides_hint(brush).begins_with("5,"), "%d: %s" % [shape, _sides_hint(brush)])
	var pyramid := _place(root, DraftBrush.BrushShape.PYRAMID, 3)
	assert_true(_sides_hint(pyramid).begins_with("3,"), _sides_hint(pyramid))
	assert_eq(pyramid.sides, 3, "a pyramid still takes 3")


func test_a_cylinder_saved_with_four_sides_reads_as_the_sixteen_it_is_built_with():
	var root := _fresh_root()
	for shape in DraftBrush.ROUND_SHAPES:
		var brush := _place(root, shape, 4)
		assert_eq(brush.sides, DraftBrush.DEFAULT_ROUND_SIDES, "shape %d" % shape)
		assert_eq(brush.get("sides"), DraftBrush.DEFAULT_ROUND_SIDES, "what the Inspector reads")
	var old := _place(root, DraftBrush.BrushShape.CYLINDER, 4)
	assert_eq(_segments(old), DraftBrush.DEFAULT_ROUND_SIDES, "and what it has")
	# The same geometry, so copies of it still match, whichever count was stored.
	var other := _place(root, DraftBrush.BrushShape.CYLINDER, DraftBrush.DEFAULT_ROUND_SIDES)
	assert_eq(HFDuplicator.shape_signature(old), HFDuplicator.shape_signature(other))


func test_a_change_of_shape_moves_the_floor_and_keeps_a_pyramid_s_count():
	var root := _fresh_root()
	var brush := _place(root, DraftBrush.BrushShape.PYRAMID, 4)
	watch_signals(brush)
	brush.shape = DraftBrush.BrushShape.CYLINDER
	assert_signal_emitted(brush, "property_list_changed", "the Inspector asks again")
	assert_true(_sides_hint(brush).begins_with("5,"), _sides_hint(brush))
	assert_eq(brush.sides, DraftBrush.DEFAULT_ROUND_SIDES)
	brush.shape = DraftBrush.BrushShape.PYRAMID
	assert_eq(brush.sides, 4, "a pyramid made round and back keeps its 4")
