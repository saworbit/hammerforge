extends GutTest

## Setting a brush to an angle, rather than turning it by one. The MCP bridge
## takes rotation as absolute Euler XYZ degrees and reads it back the same way,
## so the two have to agree, and texture lock has to treat it like any turn.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(brush_id: String, size := Vector3(4, 2, 2)) -> DraftBrush:
	var info := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": size,
		"transform": Transform3D(Basis(), Vector3(1, 2, 3)),
		"brush_id": brush_id,
	}
	return root.create_brush_from_info(info) as DraftBrush


func _degrees(brush: DraftBrush) -> Vector3:
	var euler := brush.global_transform.basis.orthonormalized().get_euler(EULER_ORDER_XYZ)
	return Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))


func test_an_angle_reads_back_as_set():
	var brush := _box("r1")
	var result: HFOpResult = root.set_brush_rotation_by_id("r1", Vector3(10, 20, 30))
	assert_true(result.ok, result.message)
	var got := _degrees(brush)
	assert_almost_eq(got.x, 10.0, 0.001)
	assert_almost_eq(got.y, 20.0, 0.001)
	assert_almost_eq(got.z, 30.0, 0.001)
	assert_eq(brush.global_position, Vector3(1, 2, 3), "turned about its own centre")


func test_it_is_absolute_not_a_turn():
	var brush := _box("r2")
	root.set_brush_rotation_by_id("r2", Vector3(0, 45, 0))
	root.set_brush_rotation_by_id("r2", Vector3(0, 45, 0))
	assert_almost_eq(_degrees(brush).y, 45.0, 0.001, "twice is still 45")
	root.set_brush_rotation_by_id("r2", Vector3.ZERO)
	assert_true(brush.global_transform.basis.is_equal_approx(Basis()), "back to square")


func test_a_quarter_turn_swaps_the_footprint():
	var brush := _box("r3", Vector3(4, 2, 2))
	root.set_brush_rotation_by_id("r3", Vector3(0, 90, 0))
	var bounds: AABB = root.brush_system.world_bounds_of(brush)
	assert_almost_eq(bounds.size.x, 2.0, 0.001)
	assert_almost_eq(bounds.size.z, 4.0, 0.001)


func test_with_texture_lock_it_matches_turning_by_the_same_angle():
	root.texture_lock = true
	var set_brush := _box("set")
	var turned := _box("turned")
	root.set_brush_rotation_by_id("set", Vector3(0, 90, 0))
	root.rotate_managed_nodes(["turned"], [], 1, 90.0, turned.global_position)
	assert_true(
		set_brush.global_transform.basis.is_equal_approx(turned.global_transform.basis),
		"same basis"
	)
	var a: Array = set_brush.serialize_faces()
	var b: Array = turned.serialize_faces()
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_almost_eq(float(a[i]["uv_rotation"]), float(b[i]["uv_rotation"]), 0.001)
		assert_eq(a[i]["uv_offset"], b[i]["uv_offset"], "face %d offset" % i)


func test_from_an_angle_it_still_matches_turning():
	# Starting square makes any two ways of turning agree. Start at 30 degrees.
	root.texture_lock = true
	var set_brush := _box("set30")
	var turned := _box("turned30")
	root.set_brush_rotation_by_id("set30", Vector3(0, 30, 0))
	root.set_brush_rotation_by_id("turned30", Vector3(0, 30, 0))
	root.set_brush_rotation_by_id("set30", Vector3(0, 90, 0))
	root.rotate_managed_nodes(["turned30"], [], 1, 60.0, turned.global_position)
	assert_true(
		set_brush.global_transform.basis.is_equal_approx(turned.global_transform.basis),
		"same basis"
	)
	var a: Array = set_brush.serialize_faces()
	var b: Array = turned.serialize_faces()
	for i in a.size():
		assert_almost_eq(float(a[i]["uv_rotation"]), float(b[i]["uv_rotation"]), 0.001)


func test_refusals_change_nothing():
	var brush := _box("r4")
	var before := brush.global_transform
	assert_false(root.set_brush_rotation_by_id("", Vector3(0, 90, 0)).ok)
	assert_false(root.set_brush_rotation_by_id("nope", Vector3(0, 90, 0)).ok)
	assert_false(root.set_brush_rotation_by_id("r4", Vector3(NAN, 0, 0)).ok)
	assert_false(root.set_brush_rotation_by_id("r4", Vector3(INF, 0, 0)).ok)
	assert_eq(brush.global_transform, before)


func test_the_same_angle_is_not_a_change():
	_box("r5")
	root.set_brush_rotation_by_id("r5", Vector3(0, 30, 0))
	assert_eq(
		root.transform_system.set_rotation(
			["r5"], Basis.from_euler(Vector3(0, deg_to_rad(30.0), 0), EULER_ORDER_XYZ)
		),
		0
	)
