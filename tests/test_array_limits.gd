extends GutTest

## The 256 copy cap and the refusal path around it. Both are about the same
## thing: an array that cannot be built has to be refused before anything is
## torn down, and refused wherever it is asked for rather than only at the
## button the dock happens to use.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFDuplicatorType = preload("res://addons/hammerforge/hf_duplicator.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _make_brush(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info({"size": Vector3(8, 8, 8), "brush_id": brush_id}) as DraftBrush
	)


func _ids(brush_id: String) -> PackedStringArray:
	return PackedStringArray([brush_id])


# -- A bad count is a no-op, not a demolition --------------------------------


func test_updating_to_a_zero_count_leaves_the_copies_and_the_record_alone():
	_make_brush("b1")
	var dup = root.create_duplicate_array(_ids("b1"), 3, Vector3(64, 0, 0))
	assert_not_null(dup, "The array should have been created")
	var did: String = dup.duplicator_id
	var live_before := root.get_live_brush_count()

	var ok = root.update_duplicate_array(did, 0, {"count": 0, "offset": Vector3(64, 0, 0)})

	assert_false(ok, "A zero count should be refused")
	assert_eq(root.get_live_brush_count(), live_before, "The copies should still be there")
	assert_not_null(root.duplicator_for_id(did), "and the record should still be reachable")


func test_a_refused_update_can_be_corrected():
	_make_brush("b1")
	var did: String = root.create_duplicate_array(_ids("b1"), 3, Vector3(64, 0, 0)).duplicator_id

	root.update_duplicate_array(did, 0, {"count": 0, "offset": Vector3(64, 0, 0)})
	var ok = root.update_duplicate_array(did, 0, {"count": 5, "offset": Vector3(64, 0, 0)})

	assert_true(ok, "A good count after a refused one should rebuild")
	assert_eq(root.get_live_brush_count(), 6, "one source plus five copies")


func test_a_refused_update_leaves_the_array_detachable():
	_make_brush("b1")
	var did: String = root.create_duplicate_array(_ids("b1"), 3, Vector3(64, 0, 0)).duplicator_id
	root.update_duplicate_array(did, 0, {"count": 0, "offset": Vector3(64, 0, 0)})

	assert_true(root.detach_duplicate_array(did), "The record should still be there to detach")


# -- The cap holds on every path ---------------------------------------------


func test_update_cannot_raise_an_array_past_the_cap():
	_make_brush("b1")
	var did: String = root.create_duplicate_array(_ids("b1"), 3, Vector3(64, 0, 0)).duplicator_id

	var ok = root.update_duplicate_array(
		did, 0, {"count": HFDuplicatorType.MAX_COPY_BRUSHES + 1, "offset": Vector3(64, 0, 0)}
	)

	assert_false(ok, "An update past the cap should be refused")
	assert_eq(root.get_live_brush_count(), 4, "and the array should be as it was")


func test_a_grid_over_the_cap_is_refused():
	_make_brush("b1")
	var dup = root.create_grid_array(_ids("b1"), Vector3i(12, 12, 12), Vector3(64, 64, 64))

	assert_null(dup, "1727 copies is over the cap and should be refused")
	assert_eq(root.get_live_brush_count(), 1, "and nothing should have been built")


func test_a_grid_within_the_cap_still_builds():
	_make_brush("b1")
	var dup = root.create_grid_array(_ids("b1"), Vector3i(2, 1, 2), Vector3(64, 64, 64))

	assert_not_null(dup, "Three copies is well inside the cap")
	assert_eq(root.get_live_brush_count(), 4, "one source plus three copies")


func test_a_radial_array_over_the_cap_is_refused():
	_make_brush("b1")
	var dup = root.create_radial_array(
		_ids("b1"), HFDuplicatorType.MAX_COPY_BRUSHES + 1, 1, 5.0, Vector3.ZERO
	)

	assert_null(dup, "A radial array past the cap should be refused")
	assert_eq(root.get_live_brush_count(), 1, "and nothing should have been built")


func test_a_refused_create_does_not_take_the_existing_array_with_it():
	_make_brush("b1")
	root.create_duplicate_array(_ids("b1"), 3, Vector3(64, 0, 0))
	assert_eq(root.get_live_brush_count(), 4, "The first array should be standing")

	var second = root.create_duplicate_array(
		_ids("b1"), HFDuplicatorType.MAX_COPY_BRUSHES + 1, Vector3(64, 0, 0)
	)

	assert_null(second, "The oversized array should be refused")
	assert_eq(root.get_live_brush_count(), 4, "and the first one should be untouched")


# -- grid_copy_count agrees with what a grid builds ---------------------------


func test_grid_copy_count_matches_the_placements():
	assert_eq(HFDuplicatorType.grid_copy_count(Vector3i(2, 1, 2)), 3, "2x1x2 makes three copies")
	assert_eq(
		HFDuplicatorType.grid_copy_count(Vector3i(2, 1, 2)),
		HFDuplicatorType.grid_placements(Vector3i(2, 1, 2), Vector3.ONE).size(),
		"and that is how many placements there are"
	)
	assert_eq(HFDuplicatorType.grid_copy_count(Vector3i(1, 1, 1)), 0, "1x1x1 makes none")
	# A count below one is not a grid that makes no copies, it is not a grid.
	# -1 is what `can_generate()` already refuses, so the grid path gets the same
	# message as the linear and radial ones rather than a clamp.
	assert_eq(HFDuplicatorType.grid_copy_count(Vector3i(0, -4, 1)), -1, "and a bad count is not")
