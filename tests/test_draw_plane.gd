extends GutTest

## The plane a new brush lands on is the plane the grid is drawn on.
##
## `record_last_brush()` moves the grid to the last brush you made, and an axis
## lock stands it up on X or Z. Both are visible: the grid mesh goes there. But
## the ray that places a new brush was answered by the horizontal plane through
## the world origin regardless — so drawing a brush at y=128 moved the grid up to
## meet it and then put the next brush back down on zero, a hundred and
## twenty-eight units below the grid being looked at.
##
## At the world origin, in the ordinary way of working. Moving the LevelRoot node
## made it worse rather than causing it.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot
var camera: Camera3D


func before_each() -> void:
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	camera = Camera3D.new()
	add_child_autoqfree(camera)
	camera.global_position = Vector3(0, 600, 0)
	camera.look_at(Vector3.ZERO, Vector3.BACK)
	_stand_in_for_the_editor_grid()


func after_each() -> void:
	root = null
	camera = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## `setup_editor_grid()` only runs in the editor, and `update_grid_transform()`
## bails without a mesh, so the grid plane would never move in a headless test.
## Standing one in exercises the path the editor actually takes.
func _stand_in_for_the_editor_grid() -> void:
	var grid := MeshInstance3D.new()
	grid.name = "EditorGrid"
	root.add_child(grid)
	root.grid_mesh = grid
	root.grid_plane_origin = root.global_position
	root.grid_axis_preference = root.AxisLock.Y


func _screen() -> Vector2:
	return camera.get_viewport().get_visible_rect().size * 0.5


## Where dragging out a brush over empty space would put it.
func _draw_point() -> Vector3:
	var hit: Dictionary = root._raycast(camera, _screen())
	assert_true(hit.has("position"), "a ray over empty space still has to land somewhere")
	return hit["position"]


# ===========================================================================
# The grid follows the last brush, and so does the plane
# ===========================================================================


func test_the_first_brush_lands_on_the_grid_at_the_origin():
	assert_almost_eq(_draw_point().y, 0.0, 0.001, "the control case")


func test_the_next_brush_lands_on_the_grid_the_last_one_moved():
	root.grid_system.record_last_brush(Vector3(0, 128, 0))

	assert_almost_eq(root.grid_plane_origin.y, 128.0, 0.001, "the grid moved up to the brush")
	assert_almost_eq(
		_draw_point().y, 128.0, 0.5, "and the next brush has to land on the grid being looked at"
	)


func test_the_plane_follows_the_grid_back_down_again():
	root.grid_system.record_last_brush(Vector3(0, 128, 0))
	root.grid_system.record_last_brush(Vector3(0, -64, 0))

	assert_almost_eq(_draw_point().y, -64.0, 0.5)


# ===========================================================================
# An axis lock stands the grid up, and the plane with it
# ===========================================================================


func test_an_x_axis_lock_places_on_the_upright_grid():
	root.grid_system.record_last_brush(Vector3(64, 0, 0))
	root.manual_axis_lock = true
	root.axis_lock = root.AxisLock.X
	# Look along X, or the ray runs parallel to the plane it is meant to cross.
	camera.global_position = Vector3(600, 0, 0)
	camera.look_at(Vector3.ZERO, Vector3.UP)

	assert_almost_eq(
		_draw_point().x, 64.0, 0.5, "a grid standing on X places on X, not on the floor"
	)


func test_a_z_axis_lock_places_on_the_upright_grid():
	root.grid_system.record_last_brush(Vector3(0, 0, -96.0))
	root.manual_axis_lock = true
	root.axis_lock = root.AxisLock.Z
	# Look along Z, or the ray runs parallel to the plane it is meant to cross.
	camera.global_position = Vector3(0, 0, 600)
	camera.look_at(Vector3.ZERO, Vector3.UP)

	assert_almost_eq(_draw_point().z, -96.0, 0.5)


func test_releasing_the_lock_puts_the_plane_back_on_the_floor():
	root.grid_system.record_last_brush(Vector3(64, 0, 0))
	root.manual_axis_lock = true
	root.axis_lock = root.AxisLock.X

	root.manual_axis_lock = false

	assert_almost_eq(_draw_point().y, 0.0, 0.5, "back to the horizontal grid")


# ===========================================================================
# A level whose root has been moved
# ===========================================================================


func test_a_moved_root_draws_on_its_own_grid_rather_than_the_world_floor():
	root.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, -250, 0))
	root.grid_plane_origin = root.global_position

	assert_almost_eq(
		_draw_point().y,
		-250.0,
		0.5,
		"the grid is drawn at the root, so that is where a brush belongs"
	)


# ===========================================================================
# Geometry still wins, and the fallback still answers
# ===========================================================================


func test_a_brush_under_the_cursor_still_wins_over_the_plane():
	root.grid_system.record_last_brush(Vector3(0, 128, 0))
	var brush = (
		root
		. brush_system
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(256, 32, 256),
				"operation": 0,
				"brush_id": root.brush_system._next_brush_id(),
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 300, 0)),
			}
		)
	)
	assert_not_null(brush)

	var hit: Dictionary = root._raycast(camera, _screen())

	assert_true(hit.has("brush"), "a face under the cursor is still picked before any plane")


func test_the_world_floor_is_still_the_answer_without_a_grid_system():
	# Exported games never load the editor systems, and the static they fall back
	# to is the behaviour they have always had.
	var hit = LevelRootType.construction_plane_intersection(Vector3(2, 10, 3), Vector3(2, -10, 3))
	var miss = LevelRootType.construction_plane_intersection(Vector3(2, 10, 3), Vector3(2, 20, 3))

	assert_eq(hit, Vector3(2, 0, 3))
	assert_null(miss)
