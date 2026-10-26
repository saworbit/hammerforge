extends GutTest

## The floor grid turned about up, for a part of a level set at an angle (#1893):
## its points, a draw square to it, a resize and Snap to Grid on it, the nudges,
## the Grid Angle field and the HUD, and Reset Grid back to the world's.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFGridSystemScript = preload("res://addons/hammerforge/systems/hf_grid_system.gd")
const HFViewAxesScript = preload("res://addons/hammerforge/hf_view_axes.gd")
const BrushGizmoPlugin = preload("res://addons/hammerforge/brush_gizmo_plugin.gd")

const UNION := CSGShape3D.OPERATION_UNION

var rig := PluginRig.new()
var _grid := 1.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _level() -> Node:
	var level = await rig.make_level()
	rig.undo().clear()
	_grid = rig.plugin.dock.grid_snap.value
	rig.plugin.dock.grid_snap.value = 1.0
	level.grid_snap = 1.0
	return level


func _leave(level) -> void:
	if is_instance_valid(level):
		level.grid_system.run_command("grid_reset")
	rig.plugin.dock.grid_snap.value = _grid
	await rig.leave_level(level)


func _screen(world: Vector3) -> Vector2:
	return rig.camera.unproject_position(world)


## A 2 by 2 by 2 box turned `degrees` about up, standing on the floor at `at`.
func _turned_box(level, id: String, degrees: float, at: Vector3) -> Node:
	var turn := Basis(Vector3.UP, deg_to_rad(degrees))
	return (
		level
		. create_brush_from_info(
			{
				"size": Vector3(2, 2, 2),
				"center": at + Vector3(0, 1, 0),
				"brush_id": id,
				"transform": Transform3D(turn, at + Vector3(0, 1, 0)),
			}
		)
	)


## Whether `point` is a whole number of steps of 1 along each of `frame`'s axes.
static func _on_steps(frame: Transform3D, point: Vector3) -> bool:
	var local := frame.affine_inverse() * point
	return local.is_equal_approx(local.round())


## The brush's corners in the world.
static func _corners(brush: Node) -> Array:
	var out: Array = []
	for face in brush.faces:
		for corner in face.local_verts:
			out.append(brush.global_transform * corner)
	return out


## Pick the bottom edge of `brush` that runs along its own X, in Vertex mode.
func _pick_bottom_edge(level, brush: Node) -> Array:
	var corners: PackedVector3Array = level.vertex_system.get_brush_vertices(brush)
	for a in corners.size():
		for b in corners.size():
			var run: Vector3 = corners[b] - corners[a]
			if corners[a].y < 0.0 and run.x > 1.9 and absf(run.y) + absf(run.z) < 0.001:
				level.vertex_system.select_edge(str(brush.brush_id), [a, b])
				return [brush.global_transform * corners[a], brush.global_transform * corners[b]]
	return []


func test_a_point_on_a_grid_turned_45_lands_on_whole_steps_along_its_axes():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var grid = level.grid_system
	grid.set_turn(45.0, Vector3.ZERO)
	assert_true(grid.is_turned())
	var landed: Vector3 = grid.grid_point(Vector3(0.9, 0.3, 0.2), 1.0)
	var frame: Transform3D = grid.grid_frame()
	assert_true(_on_steps(frame, landed), "on whole steps along the turned axes: %s" % landed)
	assert_false(landed.is_equal_approx(Vector3(1, 0, 0)), "not the world's point")
	assert_almost_eq(landed.y, 0.0, 0.0001, "heights stay the world's steps")
	assert_true(level._snap_point(Vector3(0.9, 0.3, 0.2)).is_equal_approx(landed), "a draw's too")
	var moved: Vector3 = grid.grid_offset(Vector3(1.2, 0.0, 0.3), 1.0)
	assert_true(_on_steps(Transform3D(frame.basis), moved), "a vertex drag moves by its steps")
	await _leave(level)


func test_a_quarter_turn_is_the_worlds_grid_and_a_turn_is_kept_between_45s():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var grid = level.grid_system
	grid.set_turn(90.0, Vector3(3, 0, 1))
	assert_false(grid.is_turned(), "a quarter turn looks the same")
	grid.set_turn(60.0, Vector3(3, 2, 1))
	assert_almost_eq(grid.turn_degrees, -30.0, 0.0001, "60 is -30 on a square grid")
	assert_true(grid.turn_origin.is_equal_approx(Vector3(3, 0, 1)), "through the point, on 0")
	assert_eq(HFGridSystemScript.turn_along(Vector3.UP), null, "straight up gives no turn")
	await _leave(level)


func test_an_edge_of_a_brush_turned_30_turns_the_grid_and_a_draw_lies_square_to_it():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var source := _turned_box(level, "wing", 30.0, Vector3(-6, 0, 0))
	var edge := _pick_bottom_edge(level, source)
	assert_eq(edge.size(), 2, "fixture: an edge picked")
	level.grid_system.run_command("grid_align", [source])
	level.vertex_system.clear_edge_selection()
	var grid = level.grid_system
	assert_almost_eq(grid.turn_degrees, 30.0, 0.001, "the grid takes the edge's turn")
	var frame: Transform3D = grid.grid_frame()
	for corner in _corners(source):
		assert_true(_on_steps(frame, Vector3(corner.x, 0, corner.z)), "the wing is on its lines")
	# Pointer near two grid points, off them, as a hand puts it.
	var near := Vector3(0.2, 0, -0.15)
	var from := frame * Vector3(5, 0, 1) + near
	var to := frame * Vector3(8, 0, 3) + near
	assert_true(level.begin_drag(rig.camera, _screen(from), UNION, Vector3(1, 1, 1), 0, 4))
	level.update_drag(rig.camera, _screen(to))
	level.end_drag_info(rig.camera, _screen(to), Vector3(1, 1, 1))
	level.input_state.drag_height = 2.0
	var result: Dictionary = level.end_drag_info(rig.camera, _screen(to), Vector3(1, 1, 1))
	assert_true(result.get("placed", false), "the draw places a brush")
	var info: Dictionary = result.get("info", {})
	assert_true(info.has("transform"), "turned as the grid is")
	if info.has("transform"):
		var placed: Transform3D = info["transform"]
		assert_true(placed.basis.is_equal_approx(frame.basis), "square to the wing")
		assert_true((info["size"] as Vector3).is_equal_approx(Vector3(3, 2, 2)), str(info["size"]))
		rig.plugin._commit_brush_placement(level, info)
		var drawn = level.find_brush_by_id(str(info["brush_id"]))
		assert_not_null(drawn)
		if drawn:
			for corner in _corners(drawn):
				assert_true(_on_steps(frame, corner), "a corner on the turned grid: %s" % corner)
	await _leave(level)


func test_a_resize_keeps_a_box_square_to_the_turned_grid_on_its_lines():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	level.grid_system.set_turn(30.0, Vector3.ZERO)
	var frame: Transform3D = level.grid_system.grid_frame()
	var box := _turned_box(level, "room", 30.0, frame * Vector3(1, 0, 1))
	var resize := BrushGizmoPlugin.calculate_axis_resize(
		box.global_basis, box.size, box.global_position, Vector3.RIGHT, 1, 3.3, 1.0
	)
	assert_false(resize.is_empty())
	box.size = resize["size"]
	box.global_position = resize["position"]
	assert_almost_eq(box.size.x, 3.0, 0.0001, "3.3 lands on 3 steps")
	for corner in _corners(box):
		assert_true(_on_steps(frame, corner), "every face on a line: %s" % corner)
	await _leave(level)


func test_snap_to_grid_puts_a_box_square_to_the_turned_grid_on_its_points():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	level.grid_system.set_turn(30.0, Vector3.ZERO)
	var frame: Transform3D = level.grid_system.grid_frame()
	var box := _turned_box(level, "room", 30.0, frame * Vector3(1.3, 0, 0.8))
	level.brush_system.snap_brushes_to_grid(["room"], 1.0)
	box = level.find_brush_by_id("room")
	for corner in _corners(box):
		assert_true(_on_steps(frame, corner), "a corner on a point: %s" % corner)
	await _leave(level)


func test_the_arrows_nudge_along_the_turned_grids_axes():
	var turn := Basis(Vector3.UP, deg_to_rad(30.0))
	var right := HFViewAxesScript.nudge_direction(KEY_RIGHT, null, turn)
	assert_true(right.is_equal_approx(turn * Vector3.RIGHT), "right is the grid's X")
	var up := HFViewAxesScript.nudge_direction(KEY_PAGEUP, null, turn)
	assert_true(up.is_equal_approx(Vector3.UP), "and Page Up is still up")
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	level.grid_system.set_turn(30.0, Vector3.ZERO)
	var followed: Vector3 = rig.plugin._get_nudge_direction(KEY_RIGHT)
	assert_true(followed.is_equal_approx(turn * Vector3.RIGHT), "by the view too: %s" % followed)
	await _leave(level)


func test_the_grid_angle_field_turns_the_grid_and_follows_align_and_the_hud_says_so():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var dock = rig.plugin.dock
	assert_not_null(dock.grid_angle_spin, "a Grid Angle field beside the size")
	dock.grid_angle_spin.value = 60.0
	assert_almost_eq(level.grid_system.turn_degrees, -30.0, 0.0001, "60 turns it to -30")
	assert_almost_eq(dock.grid_angle_spin.value, -30.0, 0.0001, "and the field says -30")
	rig.plugin._update_hud_context()
	var label: Label = rig.plugin.hud.find_child("GridLabel", true, false)
	assert_string_contains(label.text, "Grid: 1 @ -30°")
	var source := _turned_box(level, "wing", 20.0, Vector3(-6, 0, 0))
	level.grid_system.run_command("grid_align", [source])
	assert_almost_eq(dock.grid_angle_spin.value, 20.0, 0.0001, "the field follows Align Grid")
	await _leave(level)


func test_reset_grid_goes_back_to_the_worlds_grid_and_a_draw_is_square_to_the_world():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	level.grid_system.set_turn(30.0, Vector3.ZERO)
	level.grid_system.run_command("grid_reset")
	assert_false(level.grid_system.is_turned())
	assert_almost_eq(rig.plugin.dock.grid_angle_spin.value, 0.0, 0.0001, "the field says 0")
	var at := Vector3(2.2, 0, 3.1)
	assert_true(level._snap_point(at).is_equal_approx(Vector3(2, 0, 3)), "the world's points")
	assert_true(level.begin_drag(rig.camera, _screen(at), UNION, Vector3(1, 1, 1), 0, 4))
	assert_false(level.input_state.drag_on_face, "a plain draw, square to the world")
	level.cancel_drag()
	await _leave(level)


## An edge picked after the grid was laid on a wall turns the floor grid along it.
## The grid kept the wall's plane, so the turn was set and never took (#1933).
func test_an_edge_picked_after_a_wall_turns_the_floor_grid():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var grid = level.grid_system
	var wall = rig.box(level, "wall", Vector3(4, 1, 0), Vector3(2, 2, 2))
	var index := -1
	for i in wall.faces.size():
		wall.faces[i].ensure_geometry()
		if (wall.faces[i].normal as Vector3).is_equal_approx(Vector3.RIGHT):
			index = i
	level.face_selection = {"wall": [index]}
	grid.run_command("grid_align", [])
	assert_eq(grid.effective_grid_axis(), level.AxisLock.X, "fixture: the grid on the wall")
	level.clear_face_selection()
	var source := _turned_box(level, "wing", 30.0, Vector3(-6, 0, 0))
	assert_eq(_pick_bottom_edge(level, source).size(), 2, "fixture: an edge picked")
	grid.run_command("grid_align", [source])
	level.vertex_system.clear_edge_selection()
	assert_eq(grid.effective_grid_axis(), level.AxisLock.Y, "the floor grid")
	assert_true(grid.is_turned(), "turned")
	assert_almost_eq(grid.turn_degrees, 30.0, 0.001, "along the edge")
	await _leave(level)
