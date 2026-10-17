extends GutTest

## Merge planned twice a press: the command asked `can_merge_brushes()` before it
## opened the undo action and then committed `merge_brushes_by_ids()`, which
## planned again. Planning is the costly half, a quarter of a second for two
## 64-sided cylinders, so the check now holds its plan for the merge (#1257). A
## held plan must never be applied to brushes that changed after it was made, and
## most of what is here says so. Refusing two round brushes side by side took the
## carve as well, and no longer does.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")

var root: LevelRoot
var plugin: FakePlugin
var messages: Array = []


## Just enough of the plugin for the merge command to check and commit.
class FakePlugin:
	extends Node

	var dock = null
	var selection: Array = []
	var history: Array = []

	func _current_selection_nodes() -> Array:
		return selection

	func _get_undo_redo() -> EditorUndoRedoManager:
		return null

	func _record_history(action_name: String) -> void:
		history.append(action_name)


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	plugin = FakePlugin.new()
	add_child_autofree(plugin)
	messages = []
	root.user_message.connect(func(text: String, _level: int): messages.append(text))


func after_each():
	root = null
	plugin = null


func _box(brush_id: String, centre: Vector3, size: Vector3 = Vector3(32, 32, 32)) -> DraftBrush:
	return root.create_brush_from_info({"size": size, "center": centre, "brush_id": brush_id})


func _cylinder(brush_id: String, centre: Vector3) -> DraftBrush:
	return (
		root
		. create_brush_from_info(
			{
				"shape": LevelRootType.BrushShape.CYLINDER,
				"sides": 64,
				"size": Vector3(32, 64, 32),
				"center": centre,
				"brush_id": brush_id,
			}
		)
	)


func _plans() -> int:
	return root.brush_system.merge_plans_made


func _brush_count() -> int:
	return root.draft_brushes_node.get_child_count()


## The fastest of three plans of `ids`, in milliseconds, and whether they merge.
func _plan_time(ids: Array) -> Dictionary:
	var best := INF
	var ok := false
	for _i in 3:
		var started := Time.get_ticks_usec()
		ok = root.can_merge_brushes(ids).ok
		best = minf(best, (Time.get_ticks_usec() - started) / 1000.0)
	return {"ms": best, "ok": ok}


# -- One plan a press ----------------------------------------------------------


func test_a_merge_press_plans_once():
	plugin.selection = [_box("a", Vector3.ZERO), _box("b", Vector3(32, 0, 0))]
	var before := _plans()

	HFPluginEditActions.merge_selected(plugin, root)

	assert_eq(_plans() - before, 1, "the check's plan is the one the merge used")
	assert_eq(plugin.history, ["Merge Brushes"])
	assert_eq(_brush_count(), 1, "the two boxes became one")


func test_a_refused_press_plans_once_and_records_nothing():
	plugin.selection = [_cylinder("a", Vector3.ZERO), _cylinder("b", Vector3(32, 0, 0))]
	var before := _plans()

	HFPluginEditActions.merge_selected(plugin, root)

	assert_eq(_plans() - before, 1)
	assert_eq(plugin.history, [], "no undo step")
	assert_eq(messages.size(), 1, "the reason is given")
	if messages.size() == 1:
		assert_string_contains(messages[0], "would not be convex")
	assert_eq(_brush_count(), 2)


## The undo entry stores the method and the ids, so a redo calls the merge with
## no check in front of it. The press let go of its plan, so the redo plans
## against the level the undo put back.
func test_a_redo_plans_for_itself():
	var a := _box("a", Vector3.ZERO)
	var b := _box("b", Vector3(32, 0, 0))
	var before_state: Dictionary = root.capture_state()
	plugin.selection = [a, b]
	HFPluginEditActions.merge_selected(plugin, root)
	assert_eq(_brush_count(), 1)

	root.restore_state(before_state)
	var plans := _plans()
	var redone: HFOpResult = root.merge_brushes_by_ids(["a", "b"])

	assert_true(redone.ok, redone.message)
	assert_eq(_plans() - plans, 1, "the redo planned")
	assert_eq(_brush_count(), 1, "and merged the brushes the undo put back")


# -- A held plan is used only on the brushes it was made for -------------------


## An undo between the check and the merge: the plan was made with the second box
## on top of the first, and the undo puts it back beside it.
func test_a_held_plan_is_not_used_after_an_undo():
	_box("a", Vector3.ZERO)
	var b := _box("b", Vector3(32, 0, 0))
	var beside: Dictionary = root.capture_state()
	b.global_position = Vector3(0, 32, 0)
	assert_true(root.can_merge_brushes(["a", "b"], true).ok)

	root.restore_state(beside)
	var plans := _plans()
	var result: HFOpResult = root.merge_brushes_by_ids(["a", "b"])

	assert_true(result.ok, result.message)
	assert_eq(_plans() - plans, 1, "the merge planned again")
	assert_eq(_brush_count(), 1)
	var merged: DraftBrush = root.draft_brushes_node.get_child(0)
	var bounds: AABB = root.brush_system.world_bounds_of(merged)
	assert_almost_eq(
		bounds.size, Vector3(64, 32, 32), Vector3.ONE * 0.001, "the boxes side by side"
	)


## A brush deleted and made again under its id, where it was and as it was, is
## what an undo that rebuilds the level leaves. The plan names the old node.
func test_a_held_plan_is_not_used_once_a_brush_is_another_node():
	_box("a", Vector3.ZERO)
	var b := _box("b", Vector3(32, 0, 0))
	assert_true(root.can_merge_brushes(["a", "b"], true).ok)

	root.delete_brush(b)
	_box("b", Vector3(32, 0, 0))
	var plans := _plans()
	var result: HFOpResult = root.merge_brushes_by_ids(["a", "b"])

	assert_true(result.ok, result.message)
	assert_eq(_plans() - plans, 1, "the merge planned again")
	assert_eq(_brush_count(), 1, "and merged the brush that is there")


func test_a_held_plan_is_not_used_once_a_brush_has_moved():
	_box("a", Vector3.ZERO)
	var b := _box("b", Vector3(32, 0, 0))
	assert_true(root.can_merge_brushes(["a", "b"], true).ok)

	b.global_position = Vector3(200, 0, 0)
	var result: HFOpResult = root.merge_brushes_by_ids(["a", "b"])

	assert_false(result.ok, "the brushes no longer touch")
	assert_string_contains(result.message, "do not touch")
	assert_eq(_brush_count(), 2, "nothing was merged")


func test_a_held_plan_is_not_used_once_a_brush_has_other_faces():
	_box("a", Vector3.ZERO)
	var b := _box("b", Vector3(32, 0, 0))
	assert_true(root.can_merge_brushes(["a", "b"], true).ok)

	b.shape = LevelRootType.BrushShape.CYLINDER
	assert_ne(b.get_faces().size(), 6, "the fixture changed the face count")
	var result: HFOpResult = root.merge_brushes_by_ids(["a", "b"])

	assert_false(result.ok, "a box beside a cylinder is not convex")
	assert_eq(_brush_count(), 2, "nothing was merged")


func test_a_held_plan_is_not_used_once_a_brush_is_reshaped():
	_box("a", Vector3.ZERO)
	var b := _box("b", Vector3(32, 0, 0))
	assert_true(root.can_merge_brushes(["a", "b"], true).ok)

	# The same six faces, twice as tall: the two boxes make an L now.
	b.size = Vector3(32, 64, 32)
	var result: HFOpResult = root.merge_brushes_by_ids(["a", "b"])

	assert_false(result.ok, "an L is not convex")
	assert_eq(_brush_count(), 2, "nothing was merged")


func test_a_held_plan_is_not_used_once_a_brush_turns_into_a_cut():
	_box("a", Vector3.ZERO)
	var b := _box("b", Vector3(32, 0, 0))
	assert_true(root.can_merge_brushes(["a", "b"], true).ok)

	b.operation = CSGShape3D.OPERATION_SUBTRACTION
	var result: HFOpResult = root.merge_brushes_by_ids(["a", "b"])

	assert_false(result.ok, "a hole does not merge into a wall")
	assert_eq(_brush_count(), 2, "nothing was merged")


func test_a_released_plan_is_not_used():
	_box("a", Vector3.ZERO)
	_box("b", Vector3(32, 0, 0))
	assert_true(root.can_merge_brushes(["a", "b"], true).ok)
	root.release_merge_plan()
	var plans := _plans()

	assert_true(root.merge_brushes_by_ids(["a", "b"]).ok)
	assert_eq(_plans() - plans, 1, "the merge planned for itself")


func test_a_plan_is_held_only_when_asked():
	_box("a", Vector3.ZERO)
	_box("b", Vector3(32, 0, 0))
	assert_true(root.can_merge_brushes(["a", "b"], true).ok)
	assert_true(root.can_merge_brushes(["a", "b"]).ok, "a check that does not hold")
	var plans := _plans()

	assert_true(root.merge_brushes_by_ids(["a", "b"]).ok)
	assert_eq(_plans() - plans, 1, "let go of the plan held before it")


# -- Refusing sooner -----------------------------------------------------------


## Side by side, two cylinders hold every corner of the solid round them, so the
## corner test passed them and the carve found the hollow between them, in 370 ms
## where planning two that make one cylinder takes 240. The middle of the face
## bridging the hollow settles it before the carve. Timed against the merge that
## does need the carve, in one run, so a slower machine slows both.
func test_two_round_brushes_side_by_side_are_refused_without_the_carve():
	_cylinder("left", Vector3.ZERO)
	_cylinder("right", Vector3(32, 0, 0))
	_cylinder("lower", Vector3(0, 300, 0))
	_cylinder("upper", Vector3(0, 364, 0))

	var refused := _plan_time(["left", "right"])
	var merged := _plan_time(["lower", "upper"])
	gut.p("Refused in %.1f ms, merged in %.1f ms" % [refused["ms"], merged["ms"]])

	assert_false(refused["ok"], "two cylinders side by side are not convex")
	assert_true(merged["ok"], "two cylinders end to end make one")
	assert_lt(refused["ms"], merged["ms"] * 0.5, "the refusal skips the carve the merge needs")
