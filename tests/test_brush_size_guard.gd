extends GutTest

## create_brush_from_info() is the single door into the level for undo restore,
## duplication, prefab instancing, .map import and .hflevel load. A size it
## cannot build has to be refused there rather than becoming a brush that looks
## fine in the tree and bakes to nothing.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFBrushSystemType = preload("res://addons/hammerforge/systems/hf_brush_system.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _make(size) -> DraftBrush:
	return root.create_brush_from_info({"size": size, "center": Vector3.ZERO}) as DraftBrush


func test_a_negative_size_is_built_the_right_way_out():
	var brush := _make(Vector3(-32, 32, 32))

	assert_not_null(brush, "The brush is still created")
	assert_eq(brush.size, Vector3(32, 32, 32), "at the size it asked for, the right way round")
	assert_gt(brush.global_transform.basis.determinant(), 0.0, "with a basis that does not invert")


func test_every_face_normal_agrees_with_its_own_vertices():
	var brush := _make(Vector3(-32, 32, 32))

	for face in brush.faces:
		# FaceData winds clockwise seen from outside, so (c - a) x (b - a) is the
		# outward normal. A negative determinant used to flip one and not the
		# other.
		var a: Vector3 = face.local_verts[0]
		var b: Vector3 = face.local_verts[1]
		var c: Vector3 = face.local_verts[2]
		var from_verts: Vector3 = (c - a).cross(b - a).normalized()
		assert_gt(from_verts.dot(face.normal), 0.9, "The stored normal should match the winding")


func test_a_zero_size_becomes_a_brush_with_volume():
	var brush := _make(Vector3.ZERO)

	assert_not_null(brush, "The brush is still created")
	assert_gt(brush.size.x, 0.0, "with an x extent")
	assert_gt(brush.size.y, 0.0, "a y extent")
	assert_gt(brush.size.z, 0.0, "and a z extent")


func test_a_partly_zero_size_only_moves_the_axis_that_was_wrong():
	var brush := _make(Vector3(64, 0, 16))

	assert_eq(brush.size.x, 64.0, "A good axis is left alone")
	assert_eq(brush.size.z, 16.0, "and so is the other one")
	assert_gt(brush.size.y, 0.0, "while the bad one gets the floor")


func test_a_good_size_is_untouched():
	var brush := _make(Vector3(48, 16, 8))

	assert_eq(brush.size, Vector3(48, 16, 8), "A usable size passes straight through")


func test_a_size_that_is_not_a_vector3_still_builds_something():
	var brush := root.create_brush_from_info({"size": "not a size"}) as DraftBrush

	assert_not_null(brush, "A junk size should not produce a null brush")
	assert_gt(brush.size.x, 0.0, "and the brush should have volume")


func test_the_validator_finds_nothing_to_fix_after_a_bad_size():
	_make(Vector3(-32, 32, 32))
	_make(Vector3.ZERO)

	var report: Dictionary = root.validate_level(false)

	var brush_issues: Array = []
	for issue in report["issues"]:
		if str(issue).contains("brush"):
			brush_issues.append(str(issue))
	assert_eq(brush_issues, [], "Validate should have nothing to say about a brush now")


func test_the_validator_calls_an_inverted_brush_inverted():
	var brush := _make(Vector3(32, 32, 32))
	# Reach past the guard, the way a brush that predates it would look.
	brush.size = Vector3(-32, 32, 32)

	var report: Dictionary = root.validate_level(false)

	var found := false
	for issue in report["issues"]:
		if str(issue).begins_with("Inverted brush"):
			found = true
	assert_true(found, "A negative size is inverted, not zero-size")


func test_the_validator_still_calls_a_zero_brush_zero_size():
	var brush := _make(Vector3(32, 32, 32))
	brush.size = Vector3(0, 32, 32)

	var report: Dictionary = root.validate_level(false)

	var found := false
	for issue in report["issues"]:
		if str(issue).begins_with("Zero-size brush"):
			found = true
	assert_true(found, "A zero extent is still zero-size")
