extends GutTest

## Move to Floor and Move to Ceiling move the selection as one piece (#1964),
## measure each brush by its faces and leave it touching (#1966), and stop at the
## brushes the mapper sees, not a hidden one or an old bake (#1965).

const HFSolidMeasure = preload("res://addons/hammerforge/hf_solid_measure.gd")

const GRID := 0.5

var root: LevelRoot
var _made := 0


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.grid_snap = GRID


func after_each() -> void:
	root = null


func _box(size: Vector3, center: Vector3, info: Dictionary = {}) -> DraftBrush:
	_made += 1
	var made := {"shape": 0, "size": size, "center": center, "brush_id": "b%d" % _made}
	made.merge(info, true)
	return root.create_brush_from_info(made)


## A box turned `degrees` about `axis`, its middle at `center`.
func _turned(size: Vector3, center: Vector3, axis: Vector3, degrees: float) -> DraftBrush:
	var basis := Basis(axis, deg_to_rad(degrees))
	return _box(size, center, {"transform": Transform3D(basis, center)})


func _id(brush: DraftBrush) -> String:
	return str(brush.brush_id)


func _bounds(brush: DraftBrush) -> AABB:
	return HFSolidMeasure.bounds(HFSolidMeasure.world_faces(brush))


func _bottom(brush: DraftBrush) -> float:
	return _bounds(brush).position.y


func _top(brush: DraftBrush) -> float:
	return _bounds(brush).end.y


func test_a_brush_rests_its_lowest_point_on_the_floor_whatever_its_height():
	# The middle used to be snapped to the grid: a box 1.5 tall floated 0.25 over
	# the floor, and one 0.25 tall sank 0.125 into it (#1966).
	_box(Vector3(40, 1, 4), Vector3(0, -0.5, 0))
	var x := -15.0
	for height in [2.0, 1.5, 0.75, 0.25]:
		var b := _box(Vector3(1, height, 1), Vector3(x, 6, 0))
		x += 4.0
		root.move_brushes_to_floor([_id(b)])
		assert_almost_eq(_bottom(b), 0.0, 0.001, "a box %.2f tall rests on the floor" % height)


func test_a_turned_brush_rests_on_the_floor():
	# A 1 x 4 x 1 box on its side lies 1 tall; the drop used half of the 4.
	_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	var b := _box(Vector3(1, 4, 1), Vector3(0, 6, 0))
	root.rotate_managed_nodes([_id(b)], [], 0, 90.0, b.global_position)
	assert_almost_eq(_bounds(b).size.y, 1.0, 0.001, "fixture: it lies on its side")
	root.move_brushes_to_floor([_id(b)])
	assert_almost_eq(_bottom(b), 0.0, 0.001, "its lowest side is on the floor")
	assert_almost_eq(_bounds(b).size.y, 1.0, 0.001, "and it is still on its side")


func test_move_to_ceiling_puts_the_highest_point_against_the_ceiling():
	_box(Vector3(40, 1, 4), Vector3(0, 10.5, 0))
	var x := -15.0
	for height in [1.5, 0.75]:
		var b := _box(Vector3(1, height, 1), Vector3(x, 2, 0))
		x += 4.0
		root.move_brushes_to_ceiling([_id(b)])
		assert_almost_eq(_top(b), 10.0, 0.001, "a box %.2f tall meets the ceiling" % height)
	var turned := _box(Vector3(1, 4, 1), Vector3(x, 2, 0))
	root.rotate_managed_nodes([_id(turned)], [], 0, 90.0, turned.global_position)
	root.move_brushes_to_ceiling([_id(turned)])
	assert_almost_eq(_top(turned), 10.0, 0.001, "a box on its side meets the ceiling")


func test_a_turned_brush_comes_to_rest_edge_on_edge():
	# A ridge along X and a box turned so its lowest edge runs along Z: they meet
	# where the two edges cross, under no corner of either.
	var ridge := _turned(Vector3(6, 1, 1), Vector3(0, 0, 0), Vector3.RIGHT, 45.0)
	var b := _turned(Vector3(1, 1, 1), Vector3(0, 5, 0), Vector3.BACK, 45.0)
	root.move_brushes_to_floor([_id(b)])
	assert_almost_eq(_bottom(b), _top(ridge), 0.001, "its edge rests on the ridge")


func test_a_table_drops_as_one_piece():
	# Four legs 2 tall under a top, the lot 1 above the floor, all five selected.
	# Each brush used to fall on its own, and the top fell between the legs into
	# them (#1964).
	_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	# The top first, as a mapper may pick it: it already rests on the legs.
	var top := _box(Vector3(4, 0.5, 4), Vector3(0, 3.25, 0))
	var ids: Array = [_id(top)]
	var legs: Array = []
	for corner in [
		Vector3(-1.5, 0, -1.5), Vector3(1.5, 0, -1.5), Vector3(-1.5, 0, 1.5), Vector3(1.5, 0, 1.5)
	]:
		var leg := _box(Vector3(0.5, 2, 0.5), corner + Vector3(0, 2, 0))
		legs.append(leg)
		ids.append(_id(leg))
	root.move_brushes_to_floor(ids)
	for leg in legs:
		assert_almost_eq(_bottom(leg), 0.0, 0.001, "each leg is on the floor")
	assert_almost_eq(_bottom(top), 2.0, 0.001, "and the top is still on the legs")


func test_a_hidden_brush_does_not_stop_the_drop():
	# A hidden draft keeps its pick body, which the physics ray met (#1965).
	_box(Vector3(20, 1, 20), Vector3(0, -4.5, 0))
	var upper := _box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	root.create_visgroup("upper")
	root.add_selection_to_visgroup("upper", [upper])
	root.set_visgroup_visible("upper", false)
	var b := _box(Vector3(1, 1, 1), Vector3(0, 6, 0))
	root.move_brushes_to_floor([_id(b)])
	assert_almost_eq(_bottom(b), -4.0, 0.001, "it lands on the floor that is shown")
	root.set_visgroup_visible("upper", true)
	root.nudge_brushes_by_id([_id(b)], Vector3(0, 10, 0))
	root.move_brushes_to_floor([_id(b)])
	assert_almost_eq(_bottom(b), 0.0, 0.001, "shown again, the upper floor stops it")


func test_the_drop_meets_the_level_as_it_is_not_its_last_bake():
	# A floor baked at 0 and moved to -4: the box landed on the old collision.
	var ground := _box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	assert_true(await root.bake(true, false, 0), "fixture: the level bakes")
	root.nudge_brushes_by_id([_id(ground)], Vector3(0, -4, 0))
	var b := _box(Vector3(1, 1, 1), Vector3(0, 6, 0))
	await get_tree().physics_frame
	root.move_brushes_to_floor([_id(b)])
	assert_almost_eq(_bottom(b), -4.0, 0.001, "it lands on the floor where it is now")


func test_a_cut_or_a_trigger_does_not_stop_the_drop():
	# A cut is a hole and a trigger bakes to an area, so neither is a floor.
	_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	_box(Vector3(2, 2, 2), Vector3(0, 1, 0), {"operation": CSGShape3D.OPERATION_SUBTRACTION})
	var trigger := _box(Vector3(2, 2, 2), Vector3(4, 1, 0))
	trigger.set_meta(HFBrushEntity.CLASS_META, "trigger_once")
	var over_cut := _box(Vector3(1, 1, 1), Vector3(0, 6, 0))
	var over_trigger := _box(Vector3(1, 1, 1), Vector3(4, 6, 0))
	root.move_brushes_to_floor([_id(over_cut)])
	root.move_brushes_to_floor([_id(over_trigger)])
	assert_almost_eq(_bottom(over_cut), 0.0, 0.001, "through the cut to the floor")
	assert_almost_eq(_bottom(over_trigger), 0.0, 0.001, "through the trigger to the floor")


func test_a_brush_beside_another_drops_past_its_edge():
	# Flush against the side of a step: the two only meet along a line seen from
	# above, so the box goes down past the step's edge to the floor. The same for
	# a box and a step both turned about Y, whose bounds overlap.
	_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	_box(Vector3(2, 0.5, 2), Vector3(-5, 0.25, 0))
	var b := _box(Vector3(1, 1, 1), Vector3(-3.5, 6, 0))
	_turned(Vector3(2, 0.5, 2), Vector3(5, 0.25, 0), Vector3.UP, 45.0)
	# Its edge on the step's: x + z = sqrt(2) from the step's middle.
	var along := (sqrt(2.0) + sqrt(0.5)) * 0.5
	var turned := _turned(Vector3(1, 1, 1), Vector3(5 + along, 6, along), Vector3.UP, 45.0)
	root.move_brushes_to_floor([_id(b)])
	root.move_brushes_to_floor([_id(turned)])
	assert_almost_eq(_bottom(b), 0.0, 0.001, "on the floor beside the step")
	assert_almost_eq(_bottom(turned), 0.0, 0.001, "and beside the turned step")


func test_a_brush_already_in_another_stands_on_it_or_passes_it():
	# Sunk into the floor by no more than half its height, as a door frame is, a
	# brush stands where it is, and holds the selection with it. The old drop let
	# it fall through the floor. Drawn into the side of a wall, a brush passes
	# the wall and lands on the floor.
	_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	var sunk := _box(Vector3(1, 1, 1), Vector3(-6, 0.25, 0))
	var above := _box(Vector3(1, 1, 1), Vector3(-4, 3, 0))
	_box(Vector3(1, 4, 6), Vector3(3, 2, 0))
	var in_wall := _box(Vector3(1, 1, 1), Vector3(3.75, 3, 0))
	root.move_brushes_to_floor([_id(sunk), _id(above)])
	root.move_brushes_to_floor([_id(in_wall)])
	assert_almost_eq(_bottom(sunk), -0.25, 0.001, "a sunk box stands where it is")
	assert_almost_eq(_bottom(above), 2.5, 0.001, "and holds the selection with it")
	assert_almost_eq(_bottom(in_wall), 0.0, 0.001, "a box in a wall's side drops to the floor")


func test_a_brush_behind_the_move_does_not_hold_it():
	# A plank just over the shoulder of a box turned on its edge is behind the box
	# on every line through both, so it is not something the box is sunk into.
	_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	var b := _turned(Vector3(1, 1, 1), Vector3(0, 3, 0), Vector3.BACK, 45.0)
	_box(Vector3(0.5, 0.1, 2), Vector3(0.75, 3.3, 0))
	root.move_brushes_to_floor([_id(b)])
	assert_almost_eq(_bottom(b), 0.0, 0.001, "it drops to the floor")


func test_nothing_below_leaves_the_brush_where_it_is():
	var b := _box(Vector3(1, 1, 1), Vector3(0, 6, 0))
	_box(Vector3(4, 1, 4), Vector3(10, -0.5, 0))
	root.move_brushes_to_floor([_id(b)])
	assert_almost_eq(b.global_position, Vector3(0, 6, 0), Vector3.ONE * 0.001)
