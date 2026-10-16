extends GutTest

## An arrow-key nudge is a float32 add whose rounding leans the same way every
## press, so on a 0.1 grid a run of them drifted off the grid line, and Check
## Issues called a brush drawn against it later a micro-gap (#1203).

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	root.grid_snap = 0.1
	add_child_autofree(root)


func after_each():
	root = null


func _box(min_corner: Vector3, size: Vector3) -> DraftBrush:
	return root.brush_system.create_brush_from_info(
		{"shape": 0, "size": size, "center": min_corner + size * 0.5}
	)


func _bid(brush: DraftBrush) -> String:
	return str(brush.brush_id)


func _micro_gaps() -> Array:
	return root.validation_system.check_bake_issues().filter(
		func(issue): return issue is Dictionary and str(issue.get("type", "")) == "micro_gap"
	)


func test_a_thousand_nudges_there_and_back_leave_a_brush_where_it_was():
	var brush := _box(Vector3(0.1, 0, 0), Vector3(0.4, 0.3, 0.4))
	var start := brush.global_position
	for i in 1000:
		root.nudge_brushes_by_id([_bid(brush)], Vector3(0.1, 0, 0))
	for i in 1000:
		root.nudge_brushes_by_id([_bid(brush)], Vector3(-0.1, 0, 0))
	assert_eq(brush.global_position, start, "exactly where it started")


func test_a_brush_nudged_a_hundred_times_meets_one_drawn_against_it():
	var size := Vector3(0.4, 0.3, 0.4)
	var brush := _box(Vector3(60, 0, 0), size)
	for i in 100:
		root.nudge_brushes_by_id([_bid(brush)], Vector3(0.1, 0, 0))
	_box(Vector3(70.4, 0, 0), size)
	assert_almost_eq(brush.global_position.x - size.x * 0.5, 70.0, 1e-5, "its face is on the grid")
	assert_eq(_micro_gaps(), [], "and Check Issues finds no gap")


func test_a_brush_off_the_grid_moves_by_exactly_the_step():
	var brush := _box(Vector3(0.137, 0, 0), Vector3(0.4, 0.3, 0.4))
	var start := brush.global_position
	root.nudge_brushes_by_id([_bid(brush)], Vector3(0.1, 0, 0))
	assert_eq(brush.global_position, start + Vector3(0.1, 0, 0), "plain addition, no snap")


func test_a_brush_with_its_far_face_on_the_grid_keeps_that_face_there():
	# 0.35 wide from x 0.05: the low face is off the grid and the high face on it.
	var size := Vector3(0.35, 0.3, 0.4)
	var brush := _box(Vector3(0.05, 0, 0), size)
	for i in 300:
		root.nudge_brushes_by_id([_bid(brush)], Vector3(0.1, 0, 0))
	assert_almost_eq(
		brush.global_position.x + size.x * 0.5, 30.4, 1e-5, "the high face stays on a grid line"
	)


func test_a_step_that_is_not_a_whole_number_of_grid_steps_is_added_as_it_is():
	var brush := _box(Vector3(1, 0, 0), Vector3(0.4, 0.3, 0.4))
	var start := brush.global_position
	root.nudge_brushes_by_id([_bid(brush)], Vector3(0.033, 0, 0))
	assert_eq(brush.global_position, start + Vector3(0.033, 0, 0))
