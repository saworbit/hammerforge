extends GutTest

## An undo snapshot is meant to be a frozen copy of the level. These tests
## mutate the live level after a capture and after a restore and assert the
## snapshot did not move with it, and that a decoded (untyped) payload still
## lands in the typed properties it is meant to fill.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _make_material(mat_name: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = mat_name
	return mat


# -- Snapshot isolation ------------------------------------------------------


func test_palette_edit_after_capture_does_not_reach_the_snapshot():
	root.add_material_to_palette(_make_material("A"))
	var snap = root.capture_state(true)

	root.remove_material_from_palette(0)
	assert_eq(root.get_materials().size(), 0, "Palette should be empty after the removal")

	root.restore_state(snap)
	assert_eq(root.get_materials().size(), 1, "Restore should bring the material back")
	assert_eq(root.get_material_names()[0], "A", "and it should be the one that was captured")


func test_selection_edit_after_restore_does_not_reach_the_snapshot():
	root.face_selection = {"brush_a": [0, 1]}
	var snap = root.capture_state(true)
	root.restore_state(snap)

	root.face_selection["brush_a"] = [3]

	var snapped: Dictionary = snap["face_selection"]
	assert_eq(snapped["brush_a"], [0, 1], "The snapshot should still hold the captured selection")


# -- Typed property restores -------------------------------------------------


func test_set_materials_accepts_an_untyped_array():
	root.add_material_to_palette(_make_material("stale"))

	# What a decoded .hflevel payload actually is: a plain untyped Array.
	var loaded: Array = [_make_material("loaded_a"), _make_material("loaded_b")]
	root.set_materials(loaded)

	assert_eq(root.get_materials().size(), 2, "The loaded palette should replace the live one")
	assert_eq(root.get_material_names(), ["loaded_a", "loaded_b"], "with the loaded names")


func test_set_materials_clears_the_palette_for_an_empty_untyped_array():
	root.add_material_to_palette(_make_material("stale"))
	root.set_materials([])
	assert_eq(root.get_materials().size(), 0, "An empty payload should clear the palette")


func test_set_materials_keeps_a_bad_slot_as_null_rather_than_compacting():
	root.set_materials([_make_material("a"), 7, _make_material("c")])

	var palette := root.get_materials()
	assert_eq(palette.size(), 3, "Slot positions must survive so face indices stay valid")
	assert_null(palette[1], "The junk slot should come back empty")
	assert_eq(palette[2].resource_name, "c", "and the slot above it should keep its index")


func test_restore_paint_layers_keeps_terrain_slot_paths_from_an_untyped_payload():
	assert_not_null(root.paint_system, "LevelRoot should have built its paint system")
	var payload: Array = [
		{
			"id": "layer_0",
			"terrain_slot_paths": ["res://grass.tres", "", "", ""],
			"terrain_slot_uv_scales": [2.0, 1.0, 1.0, 1.0],
			"terrain_slot_tints": [Color.RED, Color.WHITE, Color.WHITE, Color.WHITE],
		}
	]
	root.paint_system.restore_paint_layers(payload, 0)

	var layer = root.paint_layers.get_active_layer()
	assert_eq(layer.terrain_slot_paths[0], "res://grass.tres", "Slot path should survive the load")
	assert_eq(layer.terrain_slot_uv_scales[0], 2.0, "Slot uv scale should survive the load")
	assert_eq(layer.terrain_slot_tints[0], Color.RED, "Slot tint should survive the load")


# ===========================================================================
# A malformed state must not cost the level (#347, #348)
# ===========================================================================


func _level_with_one_brush() -> int:
	root.create_brush_from_info({"size": Vector3(32, 32, 32), "brush_id": "keep"})
	return root.draft_brushes_node.get_child_count()


func test_a_state_of_the_wrong_shape_leaves_the_level_alone():
	var before := _level_with_one_brush()
	for bad in [
		{"brushes": "not a list"},
		{"entities": {"nope": 1}},
		{"materials": 7},
		{"face_selection": []},
		{"visgroups": "nope"},
	]:
		root.restore_state(bad)
		assert_eq(
			root.draft_brushes_node.get_child_count(),
			before,
			"%s must not clear the level" % str(bad)
		)


func test_a_good_state_still_restores():
	_level_with_one_brush()
	var state: Dictionary = root.capture_state()
	root.clear_brushes()
	root.restore_state(state)
	assert_eq(root.draft_brushes_node.get_child_count(), 1, "a real state still loads")


func test_one_unreadable_brush_costs_that_brush_and_not_the_load():
	(
		root
		. restore_state(
			{
				"brushes":
				[
					{"size": Vector3(32, 32, 32), "brush_id": "a"},
					17,
					{"size": Vector3(32, 32, 32), "brush_id": "b"},
				],
				"entities": [],
				"materials": [],
			}
		)
	)
	assert_eq(root.draft_brushes_node.get_child_count(), 2, "the two good ones are here")


func test_a_brush_with_a_size_that_is_not_a_size_is_skipped():
	(
		root
		. restore_state(
			{
				"brushes":
				[
					{"shape": 0, "size": Vector3(NAN, NAN, NAN)},
					{"shape": 0, "size": Vector3(32, 32, 32), "brush_id": "good"},
				],
				"entities": [],
				"materials": [],
			}
		)
	)
	assert_eq(root.draft_brushes_node.get_child_count(), 1, "only the buildable one")
	for child in root.draft_brushes_node.get_children():
		assert_true(child.size.is_finite(), "no NaN size reached the level")


func test_a_zero_size_is_still_coerced_rather_than_skipped():
	# There is a nearest size a user plainly meant. There is no nearest size to
	# a NaN, which is why only that one is refused.
	root.restore_state(
		{"brushes": [{"shape": 0, "size": Vector3.ZERO}], "entities": [], "materials": []}
	)
	assert_eq(root.draft_brushes_node.get_child_count(), 1)


func test_restoring_a_state_does_not_write_back_into_it():
	var state := {
		"brushes": [{"size": Vector3(32, 32, 32)}],
		"pending": [{"size": Vector3(32, 32, 32)}],
		"entities": [],
		"materials": [],
	}
	root.restore_state(state)
	assert_false(
		(state["pending"][0] as Dictionary).has("pending"), "the caller's state is not ours to edit"
	)
