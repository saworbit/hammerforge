extends GutTest

## Three places where one path clamped or accepted what its sibling paths
## refused outright. Each is the odd one out rather than a new rule.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFDuplicatorType = preload("res://addons/hammerforge/hf_duplicator.gd")
const SurfacePaintType = preload("res://addons/hammerforge/surface_paint.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info({"size": Vector3(32, 32, 32), "brush_id": brush_id})
		as DraftBrush
	)


func _brush_count() -> int:
	return root.draft_brushes_node.get_child_count()


# ===========================================================================
# A grid count below one is refused, like the linear and radial counts (#346)
# ===========================================================================


func test_a_grid_with_a_negative_axis_count_is_refused():
	_box("src")
	var ids := PackedStringArray(["src"])
	var before := _brush_count()
	for counts in [Vector3i(-2, 2, 2), Vector3i(2, -2, 2), Vector3i(2, 2, -2), Vector3i(0, 2, 2)]:
		assert_null(
			root.brush_system.create_grid_array(ids, counts, Vector3(64, 0, 0)),
			"%s is not a grid" % counts
		)
	assert_eq(_brush_count(), before, "nothing was built")


func test_the_linear_and_radial_paths_still_refuse_the_same_way():
	_box("src")
	var ids := PackedStringArray(["src"])
	assert_null(root.brush_system.create_duplicate_array(ids, -4, Vector3(64, 0, 0)))
	assert_null(root.brush_system.create_radial_array(ids, -4, 1, 30.0, Vector3.ZERO))


func test_an_ordinary_grid_is_still_built():
	_box("src")
	var dup = root.brush_system.create_grid_array(
		PackedStringArray(["src"]), Vector3i(2, 2, 2), Vector3(64, 64, 64)
	)
	assert_not_null(dup, "2x2x2 is seven copies")
	assert_eq(HFDuplicatorType.grid_copy_count(Vector3i(2, 2, 2)), 7)


func test_a_single_cell_grid_makes_no_copies_and_is_refused():
	assert_eq(HFDuplicatorType.grid_copy_count(Vector3i(1, 1, 1)), 0)
	assert_false(HFDuplicatorType.can_generate(0, 1).ok, "no copies is not an array")


# ===========================================================================
# A visgroup name has to render as something (#349)
# ===========================================================================


func test_a_name_of_only_whitespace_is_not_a_name():
	root.create_visgroup("   ")
	root.create_visgroup("\t")
	root.create_visgroup("")
	assert_eq(root.visgroup_system.visgroups.size(), 0, "none of those is a name")


func test_a_name_is_stored_stripped_so_one_keystroke_is_not_two_visgroups():
	root.create_visgroup("lights")
	root.create_visgroup("lights ")
	root.create_visgroup(" lights")
	assert_eq(root.visgroup_system.visgroups.size(), 1, "one visgroup, not three")
	assert_true(root.visgroup_system.visgroups.has("lights"))


func test_renaming_to_whitespace_is_refused():
	root.create_visgroup("lights")
	assert_false(root.visgroup_system.rename_visgroup("lights", "   "))
	assert_true(root.visgroup_system.visgroups.has("lights"), "still there under its own name")


# ===========================================================================
# Surface paint layers have a ceiling (#351)
# ===========================================================================


func test_surface_paint_layers_stop_at_the_cap():
	var brush := _box("b1")
	var added := 0
	for _i in 64:
		if root.add_surface_paint_layer("b1", 0):
			added += 1
	assert_eq(added, root.MAX_SURFACE_PAINT_LAYERS, "Add stops saying yes at the cap")
	assert_eq(
		brush.faces[0].paint_layers.size(), root.MAX_SURFACE_PAINT_LAYERS, "and stops adding them"
	)


func test_removing_a_layer_says_whether_it_removed_one():
	var brush := _box("b1")
	root.add_surface_paint_layer("b1", 0)
	assert_false(root.remove_surface_paint_layer("b1", 0, -1), "-1 is not a layer")
	assert_false(root.remove_surface_paint_layer("b1", 0, 9999), "nor is 9999")
	assert_eq(brush.faces[0].paint_layers.size(), 1, "and neither removed anything")
	assert_true(root.remove_surface_paint_layer("b1", 0, 0), "0 is")
	assert_eq(brush.faces[0].paint_layers.size(), 0)


func test_painting_into_a_layer_past_the_cap_does_not_create_it():
	var brush := _box("b1")
	var painter := SurfacePaintType.new()
	add_child_autoqfree(painter)
	painter.paint_at_uv(brush.faces[0], 999, Vector2(0.5, 0.5), 0.1, 1.0)
	assert_lte(
		brush.faces[0].paint_layers.size(),
		root.MAX_SURFACE_PAINT_LAYERS,
		"painting into an index creates the layers below it"
	)
