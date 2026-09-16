extends GutTest

## Three level-editing operations were implemented, carefully, and had no entry
## point outside the suite (#615). Each was the missing half of a feature whose
## other half was already in the dock, so the mapper's alternative was destructive
## busywork: rebuild the visgroup, live with a variant list that only grows,
## re-sculpt the displacement.
##
## These tests are about reachability, so they go through the dock the way a
## click does rather than calling the subsystem. Calling the subsystem is what the
## old tests did, and it is exactly what kept passing while nothing could get
## there.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _dock(root: LevelRoot) -> Node:
	var dock := DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	return dock


# ===========================================================================
# A visgroup can be renamed
# ===========================================================================


func test_the_dock_has_a_rename_button_beside_the_delete_one():
	var dock := _dock(_fresh_root())
	assert_not_null(dock.visgroup_rename_btn, "there is a Rename button")
	assert_true(
		dock.visgroup_rename_btn.pressed.is_connected(dock._on_visgroup_rename),
		"and pressing it does something"
	)


func test_renaming_a_visgroup_moves_its_members_with_it():
	var root := _fresh_root()
	var brush := (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(2, 2, 2),
				"transform": Transform3D.IDENTITY,
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)
	root.create_visgroup("roof")
	root.add_selection_to_visgroup("roof", [brush])

	assert_true(root.rename_visgroup("roof", "roof_upper"), "the rename is accepted")

	assert_true(Array(root.get_visgroup_names()).has("roof_upper"), "the new name is there")
	assert_false(Array(root.get_visgroup_names()).has("roof"), "and the old one is not")
	var members: PackedStringArray = brush.get_meta("visgroups", PackedStringArray())
	assert_true(Array(members).has("roof_upper"), "the brush went with it")
	assert_false(Array(members).has("roof"), "and is not still in the old one")


func test_a_rename_onto_a_name_that_is_taken_is_refused():
	# Merging two visgroups is a different operation and one somebody should have
	# to ask for by name, so the delegate answers rather than doing it quietly.
	var root := _fresh_root()
	root.create_visgroup("walls")
	root.create_visgroup("detail")

	assert_false(root.rename_visgroup("walls", "detail"), "the name is taken")
	assert_true(Array(root.get_visgroup_names()).has("walls"), "so both survive")
	assert_true(Array(root.get_visgroup_names()).has("detail"))


func test_a_rename_of_a_visgroup_that_is_not_there_is_refused():
	var root := _fresh_root()
	assert_false(root.rename_visgroup("gone", "anything"), "there is nothing to rename")


# ===========================================================================
# A prefab variant can be deleted
# ===========================================================================


func _prefab_with_a_variant() -> String:
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "doorframe"
	prefab.set_variant_data("base", [], [])
	prefab.set_variant_data("ornate", [], [])
	var path := "user://hf_variant_test_%d.hfprefab" % Time.get_ticks_usec()
	prefab.save_to_file(path)
	return path


func test_the_library_can_ask_for_a_variant_to_be_removed():
	var dock := _dock(_fresh_root())
	assert_true(
		dock.has_method("_on_prefab_variant_remove_requested"), "the dock answers a removal request"
	)
	if dock._prefab_library:
		assert_true(
			dock._prefab_library.has_signal("variant_remove_requested"),
			"and the library can make one"
		)


func test_removing_a_variant_takes_it_out_of_the_file():
	var dock := _dock(_fresh_root())
	var path := _prefab_with_a_variant()
	var before = HFPrefabType.load_from_file(path)
	assert_true(Array(before.get_variant_names()).has("ornate"), "the variant is there to start")

	dock._on_prefab_variant_remove_requested(path, "ornate")

	var after = HFPrefabType.load_from_file(path)
	assert_false(Array(after.get_variant_names()).has("ornate"), "and it is gone from the file")
	assert_true(Array(after.get_variant_names()).has("base"), "while base is untouched")
	DirAccess.remove_absolute(path)


func test_the_base_variant_cannot_be_removed():
	# A prefab without a base is not a prefab.
	var dock := _dock(_fresh_root())
	var path := _prefab_with_a_variant()

	dock._on_prefab_variant_remove_requested(path, "base")

	var after = HFPrefabType.load_from_file(path)
	assert_true(Array(after.get_variant_names()).has("base"), "base is still there")
	DirAccess.remove_absolute(path)


# ===========================================================================
# A displacement's power can be changed after it is created
# ===========================================================================


func _brush_with_a_displacement(root: LevelRoot, power: int) -> Node:
	var brush := (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(4, 4, 4),
				"transform": Transform3D.IDENTITY,
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)
	assert_true(root.create_displacement(str(brush.brush_id), 0, power), "the test brush takes one")
	return brush


func test_the_dock_has_a_way_to_apply_the_power_to_an_existing_displacement():
	var dock := _dock(_fresh_root())
	assert_not_null(dock._disp_power_apply_btn, "there is an Apply button beside the Power spin")
	assert_true(
		dock._disp_power_apply_btn.pressed.is_connected(dock._on_disp_set_power),
		"and pressing it does something"
	)


func test_changing_the_power_keeps_the_sculpt():
	# The reason this is not Destroy and Create: the system resamples the old grid
	# into the new one, so a cliff sculpted at 9x9 survives the move to 17x17.
	var root := _fresh_root()
	var brush := _brush_with_a_displacement(root, 2)
	var disp = brush.faces[0].displacement
	assert_eq(disp.power, 2, "starts at 5x5")
	var dim: int = disp.get_dim()
	disp.set_distance(dim / 2, dim / 2, 3.0)

	assert_true(root.set_displacement_power(str(brush.brush_id), 0, 3), "the power changes")

	var after = brush.faces[0].displacement
	assert_eq(after.power, 3, "the face is 9x9 now")
	var peak := 0.0
	for row in after.get_dim():
		for col in after.get_dim():
			peak = maxf(peak, after.get_distance(row, col))
	assert_gt(peak, 0.5, "and the sculpt came with it rather than being flattened")


func test_setting_the_power_of_a_face_with_no_displacement_is_refused():
	var root := _fresh_root()
	var brush := (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(4, 4, 4),
				"transform": Transform3D.IDENTITY,
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)
	assert_false(
		root.set_displacement_power(str(brush.brush_id), 0, 4),
		"there is no displacement to repower"
	)


func test_setting_the_power_of_a_brush_that_is_not_there_is_refused():
	var root := _fresh_root()
	assert_false(root.set_displacement_power("no_such_brush", 0, 3), "nothing to do")
