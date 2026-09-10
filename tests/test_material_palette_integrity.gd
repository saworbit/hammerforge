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
