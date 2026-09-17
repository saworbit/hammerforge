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


# --- what a library load says about what it dropped ------------------------


func _write_library(path: String, paths: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"materials": paths}))
	file.close()


func _library_path() -> String:
	return "user://hf_missing_material_library_test.hfmaterials"


func test_a_library_of_paths_that_moved_names_every_one_of_them():
	# Preserving the slots is right: `material_idx` indexes this array and
	# compacting it would repaint the level. Saying nothing about them is what
	# was wrong - the load reported success and the user heard nothing, while
	# the validator on the same level reported an issue per slot.
	var path := _library_path()
	_write_library(path, ["res://gone_a.tres", "res://gone_b.tres", "res://gone_c.tres"])
	assert_true(root.material_manager.load_library(path), "The library file itself loads")
	assert_eq(root.material_manager.materials.size(), 3, "The slots are kept")
	assert_eq(root.material_manager.get_missing_count(), 3, "and all three are empty")
	var missing := root.material_manager.get_missing_library_paths()
	assert_eq(missing.size(), 3, "The load says which paths it could not find")
	assert_true(missing.has("res://gone_b.tres"), "naming each one: %s" % str(missing))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_library_that_resolves_reports_nothing_missing():
	var path := _library_path()
	var mat_path := "user://hf_present_material_test.tres"
	ResourceSaver.save(_make_material("Present"), mat_path)
	_write_library(path, [mat_path])
	assert_true(root.material_manager.load_library(path))
	assert_eq(root.material_manager.get_missing_count(), 0, "Nothing is missing")
	assert_eq(root.material_manager.get_missing_library_paths().size(), 0, "so there is no list")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mat_path))


func test_a_later_clean_load_clears_the_missing_list():
	var path := _library_path()
	_write_library(path, ["res://gone_a.tres"])
	root.material_manager.load_library(path)
	assert_eq(root.material_manager.get_missing_library_paths().size(), 1)
	_write_library(path, [])
	root.material_manager.load_library(path)
	assert_eq(
		root.material_manager.get_missing_library_paths().size(),
		0,
		"The second load does not report the first load's misses"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ===========================================================================
# Saving a library says what it could not record (#515)
# ===========================================================================


func _save_path() -> String:
	return "user://hf_test_library_%d.json" % Time.get_ticks_usec()


## A library records each slot's `resource_path`. A material made in the editor
## session has none, so the slot is written empty and comes back null. That is
## every material added through the Materials tab's Add button, and the save used
## to report OK and say nothing.
func test_saving_a_palette_of_pathless_materials_reports_that_it_recorded_nothing():
	var mats: Array = []
	for i in 4:
		mats.append(_make_material("runtime_%d" % i))
	root.set_materials(mats)
	var path := _save_path()

	var result: int = root.material_manager.save_library(path)

	assert_eq(result, ERR_SKIP, "a library that restores nothing is not a successful save")
	assert_eq(root.material_manager.get_dropped_save_slots().size(), 4, "and it names the slots")
	DirAccess.remove_absolute(path)


func test_a_palette_with_paths_saves_clean():
	var mat := _make_material("on_disk")
	mat.resource_path = "res://addons/hammerforge/does_not_need_to_exist.tres"
	root.set_materials([mat])
	var path := _save_path()

	assert_eq(root.material_manager.save_library(path), OK)
	assert_true(root.material_manager.get_dropped_save_slots().is_empty())
	DirAccess.remove_absolute(path)


func test_a_mixed_palette_saves_and_names_only_the_slots_it_dropped():
	var on_disk := _make_material("on_disk")
	on_disk.resource_path = "res://addons/hammerforge/does_not_need_to_exist.tres"
	root.set_materials([on_disk, _make_material("runtime")])
	var path := _save_path()

	assert_eq(root.material_manager.save_library(path), OK, "one slot did record")
	assert_eq(root.material_manager.get_dropped_save_slots(), [1] as Array[int])
	DirAccess.remove_absolute(path)


func test_an_empty_palette_is_not_a_dropped_library():
	var path := _save_path()
	assert_eq(root.material_manager.save_library(path), OK, "nothing to record is not a failure")
	DirAccess.remove_absolute(path)


func test_the_dropped_slots_are_cleared_by_the_next_save():
	root.set_materials([_make_material("runtime")])
	var path := _save_path()
	root.material_manager.save_library(path)
	assert_eq(root.material_manager.get_dropped_save_slots().size(), 1)

	var on_disk := _make_material("on_disk")
	on_disk.resource_path = "res://addons/hammerforge/does_not_need_to_exist.tres"
	root.set_materials([on_disk])
	root.material_manager.save_library(path)

	assert_true(root.material_manager.get_dropped_save_slots().is_empty())
	DirAccess.remove_absolute(path)


# ===========================================================================
# The Paint tab can reach save and load (#498)
# ===========================================================================


## The User Guide has listed Save and Load under Material Library since before
## either had a button, and `MaterialManager` has had both callable from nothing.
func test_the_paint_tab_builds_a_save_and_a_load_button():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/ui/paint_tab_builder.gd")
	assert_true(source.contains('dock.material_save_library.text = "Save Library"'))
	assert_true(source.contains('dock.material_load_library.text = "Load Library"'))
	assert_true(source.contains("dock.material_save_library.pressed.connect"))
	assert_true(source.contains("dock.material_load_library.pressed.connect"))


func test_the_dock_has_a_dialog_for_each():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.tscn")
	assert_true(source.contains('[node name="MaterialLibrarySaveDialog" type="FileDialog"'))
	assert_true(source.contains('[node name="MaterialLibraryLoadDialog" type="FileDialog"'))


func test_a_library_round_trips_through_the_paths_it_recorded():
	var path := _save_path()
	root.add_prototype_materials()
	var before: int = root.material_manager.materials.size()
	assert_gt(before, 0, "the prototypes are .tres files with stable paths")

	assert_eq(root.material_manager.save_library(path), OK)
	root.material_manager.clear()
	assert_true(root.material_manager.load_library(path))

	assert_eq(root.material_manager.materials.size(), before)
	assert_eq(root.material_manager.get_missing_count(), 0)
	DirAccess.remove_absolute(path)


# ===========================================================================
# A file that is not a library (#739)
# ===========================================================================


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_a_materials_key_that_is_not_a_list_is_refused_rather_than_thrown_on():
	# `var mat_paths: Array = parsed.get("materials", [])` is a runtime error when
	# the value is a String, and GDScript has no exception handling: the function
	# unwound and a `-> bool` call handed back null. Callers that tested the
	# result saw a falsy value by luck rather than by design.
	var path := "user://hf_not_a_library.hfmaterials"
	_write_raw(path, '{"version": 1, "materials": "res://a.tres"}')
	var returned = root.material_manager.load_library(path)
	assert_eq(typeof(returned), TYPE_BOOL, "it answers the question it was asked")
	assert_false(returned, "and the answer is no")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_refused_load_leaves_the_palette_it_could_not_replace():
	var path := "user://hf_not_a_library.hfmaterials"
	root.material_manager.add_material(StandardMaterial3D.new())
	_write_raw(path, '{"version": 1, "materials": 7}')
	root.material_manager.load_library(path)
	assert_eq(
		root.material_manager.materials.size(), 1, "the palette that was there is still there"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_pre_flight_refuses_exactly_what_the_load_refuses():
	# `library_is_readable()` is asked before the load is committed as an undo
	# action. A file it clears and the load then rejects is a pre-flight that
	# opened an undo step for a load that never happened.
	var path := "user://hf_not_a_library.hfmaterials"
	for text in ['{"version": 1, "materials": "res://a.tres"}', '{"version": 1, "materials": 7}']:
		_write_raw(path, text)
		assert_eq(
			root.material_manager.library_is_readable(path),
			root.material_manager.load_library(path),
			"the two agree about %s" % text
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_library_with_no_materials_key_at_all_still_loads_as_an_empty_one():
	# Absent is not malformed. It was read as `[]` before and still is.
	var path := "user://hf_keyless_library.hfmaterials"
	_write_raw(path, '{"version": 1}')
	assert_true(root.material_manager.load_library(path))
	assert_eq(root.material_manager.materials.size(), 0)
	assert_true(root.material_manager.library_is_readable(path), "and the pre-flight agrees")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
