extends GutTest

## What a generator record owns, and for how long.
##
## Painting goes in through `assign_material_to_faces_by_id()`, which is the
## method the Paint tab actually calls, rather than through `material_override`.
## Setting the override exercises a different path and would not have caught the
## defect this covers.

const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	root = null


func _arch(overrides: Dictionary = {}) -> Dictionary:
	var settings: Dictionary = HFGeneratorSystemScript.default_settings("arch")
	for key in overrides:
		settings[key] = overrides[key]
	return settings


func _create_arch(overrides: Dictionary = {}) -> String:
	var before: Array = root.generator_system.generators.keys()
	assert_true(root.create_generator("arch", _arch(overrides), Transform3D.IDENTITY).ok)
	for generator_id in root.generator_system.generators:
		if not (generator_id in before):
			return str(generator_id)
	return ""


func _record(generator_id: String):
	return root.generator_system.generators[generator_id]


func _piece(generator_id: String, index: int) -> DraftBrush:
	return root.brush_system.find_brush_by_id(str(_record(generator_id).brush_ids[index]))


## Paint one face the way the Paint tab does.
func _paint_face(generator_id: String, piece_index: int, face_index: int, material: int) -> void:
	var brush_id := str(_record(generator_id).brush_ids[piece_index])
	root.assign_material_to_faces_by_id(brush_id, [face_index], material)
	assert_eq(
		root.brush_system.find_brush_by_id(brush_id).faces[face_index].material_idx,
		material,
		"the fixture has to actually paint something"
	)


# ===========================================================================
# Appearance survives a rebuild (#190)
# ===========================================================================


func test_a_painted_face_survives_a_radius_change():
	var generator_id := _create_arch()
	_paint_face(generator_id, 0, 0, 7)

	assert_true(root.regenerate_generator(generator_id, _arch({"radius": 192.0})).ok)

	assert_eq(
		_piece(generator_id, 0).faces[0].material_idx,
		7,
		"changing a setting must not reset the paint the feature promises to keep"
	)


func test_uv_edits_survive_a_rebuild():
	var generator_id := _create_arch()
	var face = _piece(generator_id, 1).faces[2]
	face.uv_offset = Vector2(9, 4)
	face.uv_scale = Vector2(2, 3)
	face.uv_rotation = 0.75
	face.uv_projection = FaceData.UVProjection.PLANAR_X

	assert_true(root.regenerate_generator(generator_id, _arch({"radius": 160.0})).ok)

	var rebuilt = _piece(generator_id, 1).faces[2]
	assert_almost_eq(rebuilt.uv_offset.x, 9.0, 0.001)
	assert_almost_eq(rebuilt.uv_scale.y, 3.0, 0.001)
	assert_almost_eq(rebuilt.uv_rotation, 0.75, 0.001)
	assert_eq(rebuilt.uv_projection, FaceData.UVProjection.PLANAR_X)


func test_every_painted_face_keeps_its_own_material():
	var generator_id := _create_arch()
	_paint_face(generator_id, 0, 0, 3)
	_paint_face(generator_id, 0, 2, 8)

	assert_true(root.regenerate_generator(generator_id, _arch({"depth": 96.0})).ok)

	var faces = _piece(generator_id, 0).faces
	assert_eq(faces[0].material_idx, 3, "faces are put back one for one, not all the same")
	assert_eq(faces[2].material_idx, 8)
	assert_eq(faces[1].material_idx, -1, "and an unpainted face stays unpainted")


func test_the_whole_brush_material_still_survives():
	var generator_id := _create_arch()
	var material := StandardMaterial3D.new()
	_piece(generator_id, 0).material_override = material

	assert_true(root.regenerate_generator(generator_id, _arch({"radius": 160.0})).ok)

	assert_same(_piece(generator_id, 0).material_override, material)


func test_extra_pieces_take_the_default():
	var generator_id := _create_arch({"segments": 9})
	_paint_face(generator_id, 0, 0, 5)

	assert_true(root.regenerate_generator(generator_id, _arch({"segments": 11})).ok)

	assert_eq(_record(generator_id).brush_ids.size(), 11)
	assert_eq(_piece(generator_id, 0).faces[0].material_idx, 5, "the matched piece keeps its face")
	assert_eq(_piece(generator_id, 10).faces[0].material_idx, -1, "the new one starts plain")


# ===========================================================================
# Saying so when it cannot be kept (#190)
# ===========================================================================


func test_nothing_is_at_risk_when_the_pieces_line_up():
	var generator_id := _create_arch()
	_paint_face(generator_id, 0, 0, 7)

	var at_risk := root.generator_appearance_at_risk(generator_id, _arch({"radius": 192.0}))

	assert_eq(
		at_risk.size(), 0, "a radius nudge keeps every face, so there is nothing to warn about"
	)


func test_a_painted_piece_that_would_be_dropped_is_named():
	var generator_id := _create_arch({"segments": 9})
	_paint_face(generator_id, 8, 0, 7)

	var at_risk := root.generator_appearance_at_risk(generator_id, _arch({"segments": 5}))

	assert_eq(at_risk.size(), 1, "the painted piece past the new end is at risk")
	assert_eq(str(at_risk[0]), str(_record(generator_id).brush_ids[8]))


func test_an_unpainted_piece_that_would_be_dropped_is_not_named():
	var generator_id := _create_arch({"segments": 9})

	var at_risk := root.generator_appearance_at_risk(generator_id, _arch({"segments": 5}))

	assert_eq(at_risk.size(), 0, "there is nothing on those pieces to lose")


# ===========================================================================
# Whole-level replacement (#191)
# ===========================================================================


func test_clearing_the_brushes_clears_the_records():
	_create_arch()
	assert_eq(root.generator_count(), 1)

	root.clear_brushes()

	assert_eq(root.generator_count(), 0, "a record without geometry is an orphan")


func test_a_replacing_map_import_leaves_no_orphan_record():
	_create_arch()
	var path := "user://hf_test_replacement.map"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_minimal_map_text())
	file.close()

	assert_eq(root.import_map(path), OK)

	assert_eq(root.generator_count(), 0, "the arch is gone, so its record has to be too")
	assert_eq(root.capture_state().get("generators", []).size(), 0, "and it is not saved either")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_undoing_a_replacement_brings_the_records_back():
	var generator_id := _create_arch()
	var before := root.capture_state()

	root.clear_brushes()
	assert_eq(root.generator_count(), 0)

	root.restore_state(before)

	assert_eq(root.generator_count(), 1, "undo restores the records with the geometry")
	assert_true(root.has_generator(generator_id))
	assert_eq(_record(generator_id).brush_ids.size(), before["generators"][0]["brush_ids"].size())


func test_deleting_one_generated_piece_still_keeps_the_record():
	# That record is what warns about the gap and rebuilds it, so this behaviour is
	# deliberate and has to stay.
	var generator_id := _create_arch()

	root.delete_brush_by_id(str(_record(generator_id).brush_ids[0]))

	assert_eq(root.generator_count(), 1)


func _minimal_map_text() -> String:
	return """// replacement
{
"classname" "worldspawn"
{
( -64 -64 -16 ) ( -64 -63 -16 ) ( -64 -64 -15 ) FLOOR 0 0 0 1 1
( -64 -64 -16 ) ( -64 -64 -15 ) ( -63 -64 -16 ) FLOOR 0 0 0 1 1
( -64 -64 -16 ) ( -63 -64 -16 ) ( -64 -63 -16 ) FLOOR 0 0 0 1 1
( 64 64 16 ) ( 64 65 16 ) ( 65 64 16 ) FLOOR 0 0 0 1 1
( 64 64 16 ) ( 65 64 16 ) ( 64 64 17 ) FLOOR 0 0 0 1 1
( 64 64 16 ) ( 64 64 17 ) ( 64 65 16 ) FLOOR 0 0 0 1 1
}
}
"""
