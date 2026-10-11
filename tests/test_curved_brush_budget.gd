extends GutTest

## Round brushes as they come (#1035, #1057).
##
## A sphere was built from Godot's SphereMesh defaults, 64 segments by 32 rings,
## and stored 2,240 faces; a torus stored 2,048 and a capsule 2,432. Two such
## brushes were 83 percent of a 121-brush level's faces and made Validate seven
## times slower. The pole rows of a sphere and a capsule, and the apex of a cone,
## also came through as faces with two corners on one point, which Validate
## counted as non-manifold edges on a shape the mapper had only placed.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const CURVED := {
	DraftBrush.BrushShape.SPHERE: "sphere",
	DraftBrush.BrushShape.ELLIPSOID: "ellipsoid",
	DraftBrush.BrushShape.CAPSULE: "capsule",
	DraftBrush.BrushShape.TORUS: "torus",
	DraftBrush.BrushShape.CONE: "cone",
}

## A few hundred at most: a cylinder has 18.
const FACE_BUDGET := 300


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _place(root: LevelRoot, shape: int, size := Vector3(2, 2, 2)) -> DraftBrush:
	var info := {
		"shape": shape,
		"size": size,
		"center": Vector3.ZERO,
		"operation": CSGShape3D.OPERATION_UNION,
	}
	return root.create_brush_from_info(info) as DraftBrush


func _types_found(root: LevelRoot) -> Array:
	var found: Array = []
	for issue in root.validation_system.check_bake_issues():
		found.append(str(issue.get("type", "")))
	return found


func test_round_brushes_keep_to_a_face_budget():
	for shape in [
		DraftBrush.BrushShape.SPHERE,
		DraftBrush.BrushShape.ELLIPSOID,
		DraftBrush.BrushShape.CAPSULE,
		DraftBrush.BrushShape.TORUS,
	]:
		var root := _fresh_root()
		var brush := _place(root, shape)
		assert_between(brush.get_faces().size(), 24, FACE_BUDGET, "%s as it comes" % CURVED[shape])


func test_a_stretched_capsule_keeps_to_the_budget_too():
	var root := _fresh_root()
	var brush := _place(root, DraftBrush.BrushShape.CAPSULE, Vector3(2, 6, 2))
	assert_lte(brush.get_faces().size(), FACE_BUDGET)


func test_no_face_has_two_corners_on_one_point():
	for shape in CURVED:
		var root := _fresh_root()
		var brush := _place(root, shape)
		var collapsed := 0
		for face in brush.get_faces():
			var seen := {}
			for corner in face.local_verts:
				var key := Vector3i((corner * 1000.0).round())
				if seen.has(key):
					collapsed += 1
					break
				seen[key] = true
		assert_eq(collapsed, 0, "%s: a pole or an apex is a corner, not a face" % CURVED[shape])


func test_round_brushes_pass_their_own_checks_as_placed():
	for shape in CURVED:
		var root := _fresh_root()
		_place(root, shape)
		var found := _types_found(root)
		assert_false(found.has("non_manifold"), "%s: %s" % [CURVED[shape], found])
		assert_false(found.has("open_edge"), "%s: %s" % [CURVED[shape], found])


func test_a_torus_warning_says_what_a_bent_brush_costs():
	# A torus is not convex and cannot be. The warning stays, and says what that
	# means for the mapper rather than only that it is so.
	var root := _fresh_root()
	_place(root, DraftBrush.BrushShape.TORUS, Vector3(6, 1, 6))
	var warning := ""
	for issue in root.validate_level(false).get("issues", []):
		if str(issue).contains("convex"):
			warning = str(issue)
	assert_string_contains(warning, "vertex tools")
	assert_string_contains(warning, "hull")
