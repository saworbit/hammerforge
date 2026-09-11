extends GutTest

## `can_merge_brushes()` is where the merge rules are written and
## `merge_brushes_by_ids()` enforced neither of them (#383). The pre-check in
## plugin_edit_actions.gd runs before the undo action is opened, and the undo
## entry stores the method and the ids — so a redo calls the operation directly,
## against a level that has moved on since the check ran.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _brush(brush_id: String, operation: int, position: Vector3) -> DraftBrush:
	var brush: DraftBrush = (
		root
		. create_brush_from_info(
			{
				"size": Vector3(64, 64, 64),
				"brush_id": brush_id,
				"operation": operation,
				"transform": Transform3D(Basis.IDENTITY, position),
			}
		)
	)
	return brush


func _brush_count() -> int:
	return root.draft_brushes_node.get_child_count()


func test_a_mixed_operation_merge_is_refused_by_the_operation():
	_brush("add", CSGShape3D.OPERATION_UNION, Vector3.ZERO)
	_brush("cut", CSGShape3D.OPERATION_SUBTRACTION, Vector3(32, 0, 0))
	var before := _brush_count()

	var result: HFOpResult = root.merge_brushes_by_ids(["add", "cut"])
	assert_false(result.ok, "a hole does not merge into a wall")
	assert_string_contains(result.message, "same operation type")
	assert_eq(_brush_count(), before, "nothing was merged")


func test_a_stale_id_refuses_the_whole_selection_rather_than_merging_a_subset():
	_brush("a", CSGShape3D.OPERATION_UNION, Vector3.ZERO)
	_brush("b", CSGShape3D.OPERATION_UNION, Vector3(32, 0, 0))
	var before := _brush_count()

	var result: HFOpResult = root.merge_brushes_by_ids(["a", "b", "no_such_brush"])
	assert_false(result.ok, "the selection is not quietly narrowed")
	assert_string_contains(result.message, "no_such_brush")
	assert_eq(_brush_count(), before, "the two real brushes are untouched")


func test_the_operation_and_the_check_now_agree():
	_brush("a", CSGShape3D.OPERATION_UNION, Vector3.ZERO)
	_brush("cut", CSGShape3D.OPERATION_SUBTRACTION, Vector3(32, 0, 0))
	for ids in [["a"], ["a", "cut"], ["a", "gone"]]:
		var check: HFOpResult = root.can_merge_brushes(ids)
		var done: HFOpResult = root.merge_brushes_by_ids(ids)
		assert_eq(done.ok, check.ok, "%s: the check and the operation agree" % [ids])


func test_an_ordinary_merge_still_works():
	_brush("a", CSGShape3D.OPERATION_UNION, Vector3.ZERO)
	_brush("b", CSGShape3D.OPERATION_UNION, Vector3(32, 0, 0))
	var before := _brush_count()
	var result: HFOpResult = root.merge_brushes_by_ids(["a", "b"])
	assert_true(result.ok, result.message)
	assert_eq(_brush_count(), before - 1, "two brushes became one")
