extends GutTest
## The brush pick asks each brush's world box first, and runs the exact tests
## only on the brushes whose box the ray meets (#1387). Every move over the
## viewport picks, and the exact tests cost several script calls a brush, so a
## hover pick walking them all took 16 ms at 3,000 brushes. The box is read off
## the brush when the pick runs, so a change is seen by the next pick however it
## was made. The entity pass after it steps over plain brushes the same way.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

## Straight down onto the top faces of the grid below.
const DOWN := Vector3(0, -1, 0)


## Counts the exact box tests a pick runs, and the nodes it asks whether they
## are entities.
class CountingRoot:
	extends LevelRoot

	var exact_tests := 0
	var entity_checks := 0

	func _visual_pick_distance(
		visual: VisualInstance3D, ray_origin: Vector3, ray_dir: Vector3
	) -> float:
		exact_tests += 1
		return super._visual_pick_distance(visual, ray_origin, ray_dir)

	func is_entity_node(node: Node) -> bool:
		entity_checks += 1
		return super.is_entity_node(node)


var root: CountingRoot


func before_each() -> void:
	root = CountingRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	root = null


func _box(brush_id: String, center: Vector3, size: Vector3 = Vector3(2, 2, 2)) -> DraftBrush:
	var brush := (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRootType.BrushShape.BOX,
					"size": size,
					"center": center,
					"operation": CSGShape3D.OPERATION_UNION,
					"brush_id": brush_id,
				}
			)
		)
		as DraftBrush
	)
	assert_not_null(brush, "made %s" % brush_id)
	return brush


## A 7 by 7 grid of 2 m boxes, 4 m apart, centred on the origin.
func _grid() -> void:
	for i in 7:
		for j in 7:
			_box("g_%d_%d" % [i, j], Vector3(i * 4.0 - 12.0, 0, j * 4.0 - 12.0))


func _picked_from_above(at: Vector3) -> Node:
	return root.brush_system.pick_face_from_ray(at + Vector3(0, 20, 0), DOWN).get("brush")


func _picked_id_from_above(at: Vector3) -> String:
	var brush := _picked_from_above(at) as DraftBrush
	return brush.brush_id if brush else ""


func test_a_pick_runs_the_exact_test_only_where_the_ray_meets_a_box() -> void:
	_grid()
	root.exact_tests = 0

	assert_eq(_picked_id_from_above(Vector3(4, 0, 4)), "g_4_4", "the box under the ray")
	assert_eq(root.exact_tests, 1, "and only that one of the 49 was tested exactly")


func test_a_ray_between_the_boxes_tests_none_and_picks_none() -> void:
	_grid()
	root.exact_tests = 0

	var hit := root.brush_system.pick_face_from_ray(Vector3(2, 20, 2), DOWN)

	assert_true(hit.is_empty(), "nothing under a gap")
	assert_eq(root.exact_tests, 0, "and nothing was tested exactly")


func test_the_entity_pass_asks_only_what_could_be_an_entity() -> void:
	_grid()
	var entity := DraftEntity.new()
	entity.name = "Lamp"
	root.add_entity(entity)
	entity.global_position = Vector3(4, 4, 4)
	root.entity_checks = 0

	var picked := root.brush_system.pick_node_past_face({}, Vector3(4, 20, 4), DOWN)

	assert_same(picked, entity, "the lamp under the ray")
	assert_eq(root.entity_checks, 1, "and none of the 49 brushes was asked")


func test_a_brush_tagged_as_an_entity_is_still_picked_as_one() -> void:
	_box("plain", Vector3(0, -4, 0))
	var tagged := _box("tagged", Vector3.ZERO)
	tagged.set_meta("is_entity", true)

	assert_same(root.brush_system.pick_node_from_ray(Vector3(0, 20, 0), DOWN, true), tagged)


func test_a_turned_brush_is_picked_on_its_faces_not_its_world_box() -> void:
	var turned := _box("turned", Vector3.ZERO, Vector3(4, 2, 4))
	turned.rotation = Vector3(0, PI / 4.0, 0)

	assert_same(_picked_from_above(Vector3(2.5, 0, 0)), turned, "inside the turned square")
	# The world box of a 4 m square turned 45 degrees reaches 2.83 m out along
	# each axis, and its corner at (2.6, 2.6) is well outside the square.
	assert_null(_picked_from_above(Vector3(2.6, 0, 2.6)), "the world box's empty corner")


func test_a_moved_brush_is_picked_where_it_went_at_once() -> void:
	var brush := _box("mover", Vector3.ZERO)
	assert_same(_picked_from_above(Vector3.ZERO), brush)

	brush.global_position = Vector3(30, 0, 0)

	assert_same(_picked_from_above(Vector3(30, 0, 0)), brush, "where it went")
	assert_null(_picked_from_above(Vector3.ZERO), "and not where it was")


func test_a_resized_brush_is_picked_over_its_new_size_at_once() -> void:
	var brush := _box("grower", Vector3.ZERO)
	assert_null(_picked_from_above(Vector3(5, 0, 0)), "5 m out is past a 2 m box")

	brush.size = Vector3(12, 2, 12)

	assert_same(_picked_from_above(Vector3(5, 0, 0)), brush, "and inside a 12 m one")


func test_a_brush_is_picked_where_its_level_went_at_once() -> void:
	var brush := _box("carried", Vector3.ZERO)

	root.global_position = Vector3(0, 0, 40)

	assert_same(_picked_from_above(Vector3(0, 0, 40)), brush, "where the level took it")
	assert_null(_picked_from_above(Vector3.ZERO), "and not where it was")


func test_an_added_brush_is_picked_at_once() -> void:
	_grid()
	assert_null(_picked_from_above(Vector3(2, 0, 2)), "a gap")

	var added := _box("added", Vector3(2, 0, 2), Vector3(1, 2, 1))

	assert_same(_picked_from_above(Vector3(2, 0, 2)), added)


func test_a_deleted_brush_is_not_picked_and_the_one_below_is() -> void:
	var below := _box("below", Vector3(0, -4, 0))
	var above := _box("above", Vector3.ZERO)
	assert_same(_picked_from_above(Vector3.ZERO), above)

	root.delete_brush(above)

	assert_same(_picked_from_above(Vector3.ZERO), below)


func test_an_undone_and_redone_move_is_picked_where_it_left_the_brush() -> void:
	_box("stepper", Vector3.ZERO)
	var undo = UndoStandIn.new()
	HFUndoHelper.commit(
		undo, root, "Nudge", "nudge_brushes_by_id", [["stepper"], Vector3(20, 0, 0)]
	)
	assert_eq(_picked_id_from_above(Vector3(20, 0, 0)), "stepper", "moved")

	undo.scene_history.undo()

	assert_eq(_picked_id_from_above(Vector3.ZERO), "stepper", "picked where the undo put it")
	assert_null(_picked_from_above(Vector3(20, 0, 0)), "and not where it was moved to")

	undo.scene_history.redo()

	assert_eq(_picked_id_from_above(Vector3(20, 0, 0)), "stepper", "picked where the redo put it")
	assert_null(_picked_from_above(Vector3.ZERO), "and not where the undo had it")
	undo.free_histories()


func test_an_undone_delete_is_picked_at_once() -> void:
	_box("doomed", Vector3.ZERO)
	var undo = UndoStandIn.new()
	HFUndoHelper.commit(undo, root, "Delete", "delete_brushes_by_id", [["doomed"]])
	assert_null(_picked_from_above(Vector3.ZERO), "gone")

	undo.scene_history.undo()

	assert_eq(_picked_id_from_above(Vector3.ZERO), "doomed", "the undo put it back to be picked")
	undo.free_histories()
