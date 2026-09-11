extends GutTest

## The resize, nudge and array paths take numbers a user typed and turn them into
## a position. Each used to take a value that is not a number and build from it
## anyway, so the brush ended up somewhere nothing could reach again (#378, #379,
## #382). The create path already refused all three, which is the behaviour these
## three now match.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFDuplicatorType = preload("res://addons/hammerforge/hf_duplicator.gd")

var root: LevelRoot

var non_finite := [
	Vector3(NAN, 0.0, 0.0),
	Vector3(0.0, INF, 0.0),
	Vector3(-INF, NAN, INF),
	Vector3(NAN, NAN, NAN),
]


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info(
			{"size": Vector3(64, 64, 64), "brush_id": brush_id, "drag_size_default": Vector3.ONE}
		)
		as DraftBrush
	)


func _brush_count() -> int:
	return root.draft_brushes_node.get_child_count()


# ===========================================================================
# Resize (#378)
# ===========================================================================


func test_a_non_finite_resize_leaves_the_brush_where_it_was():
	var brush := _box("b")
	for size in non_finite:
		root.set_brush_transform_by_id("b", size, brush.global_position)
		assert_true(brush.size.is_finite(), "size %s was refused" % size)
		assert_eq(brush.size, Vector3(64, 64, 64))


func test_a_non_finite_position_leaves_the_brush_where_it_was():
	var brush := _box("b")
	for position in non_finite:
		root.set_brush_transform_by_id("b", brush.size, position)
		assert_true(brush.global_position.is_finite(), "position %s was refused" % position)


func test_the_resize_path_floors_a_zero_or_negative_size_like_the_create_path():
	var brush := _box("b")
	root.set_brush_transform_by_id("b", Vector3(0.0, 64.0, 64.0), brush.global_position)
	assert_almost_eq(brush.size.x, 0.1, 0.001, "a zero extent is floored, not written")

	root.set_brush_transform_by_id("b", Vector3(-64.0, 64.0, 64.0), brush.global_position)
	assert_almost_eq(brush.size.x, 64.0, 0.001, "a negative extent is made positive")


func test_an_ordinary_resize_still_lands():
	var brush := _box("b")
	root.set_brush_transform_by_id("b", Vector3(32, 16, 8), Vector3(10, 0, 0))
	assert_eq(brush.size, Vector3(32, 16, 8))
	assert_eq(brush.global_position, Vector3(10, 0, 0))


# ===========================================================================
# Nudge (#379)
# ===========================================================================


func test_a_non_finite_nudge_offset_is_refused():
	var brush := _box("b")
	for offset in non_finite:
		root.nudge_brushes_by_id(["b"], offset)
		assert_true(brush.global_position.is_finite(), "offset %s was refused" % offset)
		assert_eq(brush.global_position, Vector3.ZERO)


func test_an_ordinary_nudge_still_moves_the_brush():
	var brush := _box("b")
	root.nudge_brushes_by_id(["b"], Vector3(64, 0, 0))
	assert_eq(brush.global_position, Vector3(64, 0, 0))


func test_a_non_finite_nudge_offset_is_refused_for_entities():
	var entity := root.entity_system.place_entity_at_screen(null, Vector2.ZERO, "info_player_start")
	if entity == null:
		entity = DraftEntity.new()
		entity.entity_type = "info_player_start"
		root.entity_system.add_entity(entity)
	entity.global_position = Vector3(8, 0, 0)
	var path := str(root.get_path_to(entity))
	root.nudge_entities_by_paths([path], Vector3(NAN, 0, 0))
	assert_eq(entity.global_position, Vector3(8, 0, 0), "the entity did not move")


# ===========================================================================
# Array (#382)
# ===========================================================================


func test_a_non_finite_layout_number_lays_out_no_copies():
	assert_eq(HFDuplicatorType.linear_placements(5, Vector3(NAN, 0, 0)).size(), 0)
	assert_eq(HFDuplicatorType.grid_placements(Vector3i(2, 2, 2), Vector3(0, INF, 0)).size(), 0)
	assert_eq(HFDuplicatorType.radial_placements(5, 1, NAN, Vector3.ZERO, 0.0).size(), 0)
	assert_eq(HFDuplicatorType.radial_placements(5, 1, 30.0, Vector3.ZERO, INF).size(), 0)
	assert_eq(HFDuplicatorType.radial_placements(5, 1, 30.0, Vector3(NAN, 0, 0), 0.0).size(), 0)


func test_can_generate_refuses_a_layout_number_that_is_not_a_number():
	var check: HFOpResult = HFDuplicatorType.can_generate(5, 1, {"offset": Vector3(NAN, 0, 0)})
	assert_false(check.ok, "the offset is checked where the count is")
	assert_true(check.message.contains("not a number"), check.message)
	assert_true(HFDuplicatorType.can_generate(5, 1, {"offset": Vector3(64, 0, 0)}).ok)


func test_an_array_with_a_non_finite_offset_builds_nothing():
	_box("src")
	var before := _brush_count()
	assert_null(
		root.brush_system.create_duplicate_array(PackedStringArray(["src"]), 5, Vector3(NAN, 0, 0))
	)
	assert_eq(_brush_count(), before, "no copies were made")


func test_an_ordinary_array_is_still_built():
	_box("src")
	var before := _brush_count()
	assert_not_null(
		root.brush_system.create_duplicate_array(PackedStringArray(["src"]), 3, Vector3(64, 0, 0))
	)
	assert_eq(_brush_count(), before + 3, "three copies")
