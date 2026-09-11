extends GutTest

## The validator is the backstop, and it was blind to the worst cases (#371,
## #372). Fixing the setters that create these states does nothing for a
## `.hflevel` saved last week, a `.map` imported from another editor, or a file
## that was hand-edited, and that is the ground the validator covers.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info({"size": Vector3(64, 64, 64), "brush_id": brush_id})
		as DraftBrush
	)


func _report() -> Array:
	return root.validate_level().get("issues", [])


func _mentions(report: Array, fragment: String) -> bool:
	for issue in report:
		if str(issue).contains(fragment):
			return true
	return false


# ===========================================================================
# A size that is not a number (#371)
# ===========================================================================


func test_a_clean_level_still_reports_nothing_about_geometry():
	_box("b")
	var report := _report()
	assert_false(_mentions(report, "Brush"), "an ordinary box is not an issue: %s" % [report])


func test_a_non_finite_brush_size_is_reported():
	for size in [Vector3(NAN, 64, 64), Vector3(64, INF, 64), Vector3(NAN, NAN, NAN)]:
		var brush := _box("b")
		brush.size = size
		assert_true(_mentions(_report(), "size is not a number"), "%s was reported" % size)
		root.brush_system.delete_brush(brush)


func test_auto_fix_gives_a_non_finite_size_the_default_back():
	var brush := _box("b")
	brush.size = Vector3(NAN, 64, 64)
	var result: Dictionary = root.validate_level(true)
	assert_gt(int(result.get("fixed", 0)), 0, "something was repaired")
	assert_true(brush.size.is_finite(), "the size is a size again: %s" % brush.size)


func test_a_non_finite_brush_position_is_reported():
	var brush := _box("b")
	brush.global_position = Vector3(NAN, 0, 0)
	assert_true(_mentions(_report(), "position is not a number"))


# ===========================================================================
# Geometry the validator checked nothing about (#372)
# ===========================================================================


func test_a_brush_with_no_faces_is_reported():
	var brush := _box("b")
	brush.faces = []
	assert_true(_mentions(_report(), "no faces"), "a faceless brush is an issue")


func test_auto_fix_removes_a_brush_with_no_faces():
	var brush := _box("b")
	brush.faces = []
	var before := root.draft_brushes_node.get_child_count()
	root.validate_level(true)
	assert_lt(
		root.draft_brushes_node.get_child_count(), before, "there is nothing to repair, so it goes"
	)


func test_a_non_finite_vertex_is_reported():
	var brush := _box("b")
	var verts: PackedVector3Array = brush.faces[0].local_verts
	verts[0] = Vector3(NAN, 0, 0)
	brush.faces[0].local_verts = verts
	assert_true(_mentions(_report(), "vertices that are not numbers"))


func test_a_face_bowed_out_of_plane_is_reported_and_repaired():
	var brush := _box("b")
	var verts: PackedVector3Array = brush.faces[0].local_verts
	verts[3] = verts[3] + brush.faces[0].normal * 32.0
	brush.faces[0].local_verts = verts
	brush.faces[0].ensure_geometry()
	assert_true(_mentions(_report(), "not a plane"), "the bow is reported")

	var result: Dictionary = root.validate_level(true)
	assert_gt(int(result.get("fixed", 0)), 0, "the repair that already existed was called")
	assert_false(_mentions(_report(), "not a plane"), "and the bow is gone")


func test_vertices_a_weld_apart_are_reported_and_welded():
	var brush := _box("b")
	var verts: PackedVector3Array = brush.faces[0].local_verts
	verts[1] = verts[0] + Vector3(0.0001, 0.0, 0.0)
	brush.faces[0].local_verts = verts
	brush.faces[0].ensure_geometry()
	assert_true(_mentions(_report(), "a weld apart"))
	root.validate_level(true)
	assert_false(_mentions(_report(), "a weld apart"), "welded")
