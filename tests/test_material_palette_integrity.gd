extends GutTest

## FaceData.material_idx is a plain index into MaterialManager.materials, so
## anything that changes the shape of that array has to answer for the faces
## pointing into it. These tests cover removal and the prototype batch load.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFPrototypeTexturesType = preload("res://addons/hammerforge/hf_prototype_textures.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	# The editor seeds a fresh root with the prototype set. Start from empty so
	# each test names its own palette slots.
	root.material_manager.clear()


func _make_material(mat_name: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = mat_name
	return mat


func _make_brush(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info({"size": Vector3(8, 8, 8), "brush_id": brush_id}) as DraftBrush
	)


# -- Removal remaps the faces above the removed slot --------------------------


func test_removing_a_slot_keeps_faces_on_the_material_they_had():
	root.add_material_to_palette(_make_material("A"))
	root.add_material_to_palette(_make_material("B"))
	var brush := _make_brush("b1")
	root.assign_material_to_whole_brushes(1, ["b1"])

	root.remove_material_from_palette(0)

	assert_eq(root.get_material_names(), ["B"], "B should be the only slot left")
	for face in brush.faces:
		assert_eq(face.material_idx, 0, "Faces on B should follow it down to slot 0")


func test_removing_the_slot_a_face_uses_leaves_the_face_unset():
	root.add_material_to_palette(_make_material("A"))
	var brush := _make_brush("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])

	root.remove_material_from_palette(0)

	for face in brush.faces:
		assert_eq(face.material_idx, -1, "A face whose material is gone should be unset")


func test_removing_a_slot_leaves_faces_below_it_alone():
	root.add_material_to_palette(_make_material("A"))
	root.add_material_to_palette(_make_material("B"))
	root.add_material_to_palette(_make_material("C"))
	var brush := _make_brush("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])

	root.remove_material_from_palette(2)

	for face in brush.faces:
		assert_eq(face.material_idx, 0, "A face below the removed slot should not move")


func test_removing_an_out_of_range_index_changes_nothing():
	root.add_material_to_palette(_make_material("A"))
	var brush := _make_brush("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])

	root.remove_material_from_palette(5)
	root.remove_material_from_palette(-1)

	assert_eq(root.get_materials().size(), 1, "The palette should be untouched")
	assert_eq(brush.faces[0].material_idx, 0, "and so should the face index")


# -- The prototype batch is not additive --------------------------------------


func test_loading_the_prototypes_twice_does_not_double_the_palette():
	var first := root.add_prototype_materials()
	var after_first := root.get_materials().size()
	assert_gt(first, 0, "The first load should add the prototype set")
	assert_eq(after_first, first, "and nothing else should be in the palette")

	var second := root.add_prototype_materials()

	assert_eq(second, 0, "The second load should add nothing")
	assert_eq(root.get_materials().size(), after_first, "and the palette should not grow")


func test_prototype_names_are_unique_after_two_loads():
	root.add_prototype_materials()
	root.add_prototype_materials()

	var names := root.get_material_names()
	var seen: Dictionary = {}
	for n in names:
		assert_false(seen.has(n), "Duplicate palette name after a second load: %s" % n)
		seen[n] = true


func test_load_all_into_keeps_materials_that_were_already_there():
	root.add_material_to_palette(_make_material("hand_made"))
	var added := HFPrototypeTexturesType.load_all_into(root.material_manager)

	assert_gt(added, 0, "The prototypes should still load alongside a hand made material")
	assert_eq(root.get_material_names()[0], "hand_made", "and the existing slot 0 should not move")


# -- A slot has to name something in the palette (#343) ------------------------


func test_a_slot_outside_the_palette_is_refused():
	root.add_material_to_palette(_make_material("A"))
	root.add_material_to_palette(_make_material("B"))
	var brush := _make_brush("b1")
	root.assign_material_to_faces_by_id("b1", [0], 1)
	for slot in [-2, 2, 999999]:
		root.assign_material_to_faces_by_id("b1", [0], slot)
		assert_eq(brush.faces[0].material_idx, 1, "slot %d must not stick" % slot)


func test_the_default_slot_is_still_allowed():
	root.add_material_to_palette(_make_material("A"))
	var brush := _make_brush("b1")
	root.assign_material_to_faces_by_id("b1", [0], 0)
	root.assign_material_to_faces_by_id("b1", [0], -1)
	assert_eq(brush.faces[0].material_idx, -1, "-1 means no material")


func test_assigning_a_bad_slot_to_whole_brushes_changes_nothing():
	root.add_material_to_palette(_make_material("A"))
	var brush := _make_brush("b1")
	assert_eq(root.assign_material_to_whole_brushes(7, ["b1"]), 0)
	for face in brush.faces:
		assert_eq(face.material_idx, -1)


func test_validate_reports_and_fixes_a_slot_below_the_default():
	root.add_material_to_palette(_make_material("A"))
	var brush := _make_brush("b1")
	brush.faces[0].material_idx = -5
	var report: Dictionary = root.validate_level(false)
	assert_gt(_issues_mentioning(report, "missing materials").size(), 0, "reported")
	root.validate_level(true)
	assert_eq(brush.faces[0].material_idx, -1, "reset to the default slot")


func _issues_mentioning(report: Dictionary, text: String) -> Array:
	var out: Array = []
	for issue in report.get("issues", []):
		if str(issue).findn(text) >= 0:
			out.append(issue)
	return out


# -- A UV projection has to be one of the projections (#345) -------------------


func test_reprojecting_to_an_integer_that_is_not_a_projection_is_refused():
	var brush := _make_brush("b1")
	root.reproject_face_uvs("b1", 0, FaceData.UVProjection.PLANAR_X)
	for bad in [-1, 99]:
		root.reproject_face_uvs("b1", 0, bad)
		assert_eq(
			brush.faces[0].uv_projection,
			FaceData.UVProjection.PLANAR_X,
			"projection %d must not stick" % bad
		)


func test_a_projection_out_of_range_does_not_survive_a_load():
	var face := FaceData.new()
	face.local_verts = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 1, 0)])
	face.uv_projection = 99
	var restored := FaceData.from_dict(face.to_dict())
	assert_true(
		FaceData.is_valid_projection(restored.uv_projection), "a file cannot smuggle one in"
	)


func test_validate_reports_and_fixes_a_projection_that_is_not_one():
	var brush := _make_brush("b1")
	brush.faces[0].uv_projection = 99
	var report: Dictionary = root.validate_level(false)
	assert_gt(_issues_mentioning(report, "UV projection").size(), 0, "reported")
	root.validate_level(true)
	assert_true(FaceData.is_valid_projection(brush.faces[0].uv_projection))


# -- A UV transform has to be usable (#344) -----------------------------------


func test_a_uv_transform_that_is_not_numbers_is_refused():
	var brush := _make_brush("b1")
	root.set_face_uv_params("b1", 0, Vector2(2, 2), Vector2(1, 1), 0.5)
	var kept := brush.faces[0].to_dict()
	var bad := [
		[Vector2(NAN, 1), Vector2.ZERO, 0.0],
		[Vector2.ONE, Vector2(INF, 0), 0.0],
		[Vector2.ONE, Vector2.ZERO, NAN],
	]
	for entry in bad:
		root.set_face_uv_params("b1", 0, entry[0], entry[1], entry[2])
		assert_eq(brush.faces[0].to_dict(), kept, "%s must not stick" % str(entry))
	for uv in brush.faces[0].custom_uvs:
		assert_true(uv.is_finite(), "no non-finite UV reached the mesh")


func test_a_uv_scale_of_zero_is_refused():
	var brush := _make_brush("b1")
	root.set_face_uv_params("b1", 0, Vector2(2, 2), Vector2.ZERO, 0.0)
	root.set_face_uv_params("b1", 0, Vector2(0, 2), Vector2.ZERO, 0.0)
	assert_almost_eq(brush.faces[0].uv_scale.x, 2.0, 0.0001, "zero collapses the face")
	root.set_face_uv_params("b1", 0, Vector2(2, 0), Vector2.ZERO, 0.0)
	assert_almost_eq(brush.faces[0].uv_scale.y, 2.0, 0.0001)


func test_a_negative_uv_scale_is_allowed_because_it_mirrors():
	var brush := _make_brush("b1")
	root.set_face_uv_params("b1", 0, Vector2(-1, 1), Vector2.ZERO, 0.0)
	assert_almost_eq(brush.faces[0].uv_scale.x, -1.0, 0.0001)
