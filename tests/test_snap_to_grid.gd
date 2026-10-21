extends GutTest
## Snap to Grid (#1398), through the real plugin. Ctrl+B moves each selected brush
## the least distance that puts the lowest corner of its world bounds on a grid
## point, and a selected entity's origin onto the nearest one, keeping size and
## rotation. In vertex mode the same chord moves each selected vertex to its
## nearest grid point, under the check a drag takes on release. One press is one
## undo step, and a selection already on the grid adds none.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()
## The dock's grid before a test set its own.
var _grid_before := 0.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


## A level with the grid at `step`, set the way the dock sets it, and an empty
## history. Leave it with `_leave()`.
func _level(step: float) -> Node:
	var level = await rig.make_level()
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(step)
	rig.undo().clear()
	return level


func _leave(level: Node) -> void:
	if rig.plugin._vertex_mode:
		rig.plugin._toggle_vertex_mode(level)
	await rig.leave_level(level)
	rig.plugin.dock._apply_grid_snap(_grid_before)


func _press(action: String) -> int:
	return rig.forward(PluginRig.key_for(action))


func _steps() -> int:
	return rig.undo().step_count()


func _corner(level: Node, brush: Node) -> Vector3:
	return level.brush_system.world_bounds_of(brush).position


static func _on_grid(point: Vector3, step: float) -> bool:
	for axis in 3:
		var steps: float = point[axis] / step
		if absf(steps - roundf(steps)) > 0.0001:
			return false
	return true


func _said(text: String) -> bool:
	for toast in rig.toasts():
		if str(toast).contains(text):
			return true
	return false


func _lamp(level: Node, position: Vector3) -> Node3D:
	var lamp = DraftEntityScript.new()
	lamp.entity_type = "light_point"
	level.add_entity(lamp)
	lamp.global_position = position
	return lamp


func _only_lamp(level: Node) -> Node3D:
	for child in level.entities_node.get_children():
		if child is DraftEntityScript:
			return child
	return null


# ===========================================================================
# Brushes and entities
# ===========================================================================


func test_ctrl_b_puts_a_box_corner_on_the_grid_and_keeps_its_size():
	assert_not_null(rig.plugin, rig.error())
	var level = await _level(0.5)
	var box = rig.box(level, "a", Vector3(0.3, 0, 0.1), Vector3.ONE)
	rig.select([box])
	assert_eq(_press("snap_to_grid"), STOP, "Ctrl+B is HammerForge's with a brush selected")
	assert_true(
		box.global_position.is_equal_approx(Vector3(0.5, 0, 0)),
		"the corner went to the nearest grid point: %s" % box.global_position
	)
	assert_eq(box.size, Vector3.ONE, "the same size")
	assert_eq(_steps(), 1, "one step")
	await _leave(level)


func test_a_turned_brush_lands_with_its_bounds_corner_on_the_grid_and_keeps_its_rotation():
	var level = await _level(0.5)
	var brush = rig.box(level, "t", Vector3(1.13, 0.27, -0.61), Vector3(2, 1, 3))
	level.set_brush_rotation_by_id("t", Vector3(0, 30, 0))
	var basis_before: Basis = brush.global_transform.basis
	var corner_before := _corner(level, brush)
	assert_false(_on_grid(corner_before, 0.5), "it starts off the grid")
	rig.select([brush])
	_press("snap_to_grid")
	var corner := _corner(level, brush)
	assert_true(_on_grid(corner, 0.5), "its bounds corner is on the grid: %s" % corner)
	var moved: Vector3 = (corner - corner_before).abs()
	assert_lte(maxf(moved.x, maxf(moved.y, moved.z)), 0.2501, "the nearest grid point")
	assert_true(brush.global_transform.basis.is_equal_approx(basis_before), "the same rotation")
	assert_eq(brush.size, Vector3(2, 1, 3), "the same size")
	await _leave(level)


func test_one_undo_step_puts_back_every_brush_and_entity_it_moved():
	var level = await _level(0.5)
	var box = rig.box(level, "a", Vector3(0.3, 0, 0.1), Vector3.ONE)
	var other = rig.box(level, "b", Vector3(5.2, 1.4, 3.3), Vector3(2, 2, 2))
	var lamp := _lamp(level, Vector3(1.2, 2.9, -0.4))
	rig.select([box, other, lamp])
	_press("snap_to_grid")
	assert_true(box.global_position.is_equal_approx(Vector3(0.5, 0, 0)), "the box snapped")
	assert_true(_on_grid(_corner(level, other), 0.5), "the other brush snapped")
	assert_true(lamp.global_position.is_equal_approx(Vector3(1, 3, -0.5)), "the lamp's origin")
	assert_eq(_steps(), 1, "all of it one step")
	assert_eq(
		rig.undo().scene_history.get_current_action_name(), "Snap to Grid", "named for the command"
	)
	rig.undo().press_undo()
	await rig.frame()
	assert_true(
		level.find_brush_by_id("a").global_position.is_equal_approx(Vector3(0.3, 0, 0.1)),
		"undo puts the box back"
	)
	assert_true(
		level.find_brush_by_id("b").global_position.is_equal_approx(Vector3(5.2, 1.4, 3.3)),
		"and the other brush"
	)
	assert_true(
		_only_lamp(level).global_position.is_equal_approx(Vector3(1.2, 2.9, -0.4)), "and the lamp"
	)
	rig.undo().press_redo()
	await rig.frame()
	assert_true(
		level.find_brush_by_id("a").global_position.is_equal_approx(Vector3(0.5, 0, 0)),
		"redo snaps it again"
	)
	assert_true(_only_lamp(level).global_position.is_equal_approx(Vector3(1, 3, -0.5)))
	await _leave(level)


func test_a_selection_already_on_the_grid_adds_no_step():
	var level = await _level(0.5)
	var box = rig.box(level, "a", Vector3(0.3, 0, 0.1), Vector3.ONE)
	rig.select([box])
	_press("snap_to_grid")
	assert_eq(_steps(), 1, "the first press moved it")
	var snapped_to: Vector3 = box.global_position
	assert_eq(_press("snap_to_grid"), STOP, "the second press is still taken")
	assert_eq(_steps(), 1, "and adds no step")
	assert_eq(box.global_position, snapped_to, "nor moves it")
	var lamp := _lamp(level, Vector3(1, 3, -0.5))
	rig.select([box, lamp])
	_press("snap_to_grid")
	assert_eq(_steps(), 1, "an entity on the grid adds none either")
	await _leave(level)


func test_texture_lock_treats_the_snap_as_it_treats_a_nudge():
	for lock in [true, false]:
		var level = await _level(0.5)
		level.texture_lock = lock
		var snapped = rig.box(level, "s", Vector3(0.3, 0.2, 0.1), Vector3(2, 2, 2))
		var nudged = rig.box(level, "n", Vector3(10.3, 0.2, 0.1), Vector3(2, 2, 2))
		var offsets_before: Array = []
		for face in snapped.get_faces():
			offsets_before.append(face.uv_offset)
		rig.select([snapped])
		_press("snap_to_grid")
		var offset: Vector3 = snapped.global_position - Vector3(0.3, 0.2, 0.1)
		assert_false(offset.is_zero_approx(), "the snap moved it")
		level.nudge_brushes_by_id(["n"], offset)
		var snapped_faces: Array = snapped.get_faces()
		var nudged_faces: Array = nudged.get_faces()
		assert_eq(snapped_faces.size(), nudged_faces.size())
		var moved_any := false
		for i in snapped_faces.size():
			var got: Vector2 = snapped_faces[i].uv_offset
			assert_true(
				got.is_equal_approx(nudged_faces[i].uv_offset),
				(
					"lock %s, face %d: %s as the nudge left %s"
					% [lock, i, got, nudged_faces[i].uv_offset]
				)
			)
			if not got.is_equal_approx(offsets_before[i]):
				moved_any = true
		assert_eq(moved_any, lock, "texture lock %s: the texture moved with the brush" % lock)
		await _leave(level)


func test_the_palette_toolbar_and_dock_run_the_same_snap():
	var level = await _level(0.5)
	var box = rig.box(level, "a", Vector3(0.3, 0, 0.1), Vector3.ONE)
	rig.select([box])
	rig.plugin._on_hotkey_palette_action("snap_to_grid")
	assert_true(box.global_position.is_equal_approx(Vector3(0.5, 0, 0)), "from the palette")
	box.global_position = Vector3(0.3, 0, 0.1)
	rig.plugin._context_toolbar.action_requested.emit("snap_to_grid", [])
	assert_true(box.global_position.is_equal_approx(Vector3(0.5, 0, 0)), "from the toolbar")
	box.global_position = Vector3(0.3, 0, 0.1)
	await rig.frame()
	rig.plugin.dock.snap_to_grid_btn.pressed.emit()
	assert_true(box.global_position.is_equal_approx(Vector3(0.5, 0, 0)), "from the dock")
	assert_eq(_steps(), 3, "a step each")
	await _leave(level)


func test_with_the_grid_off_it_says_so_and_moves_nothing():
	var level = await _level(0.5)
	var box = rig.box(level, "a", Vector3(0.3, 0, 0.1), Vector3.ONE)
	level.grid_snap = 0.0
	rig.select([box])
	rig.clear_toasts()
	assert_eq(_press("snap_to_grid"), STOP)
	assert_eq(box.global_position, Vector3(0.3, 0, 0.1), "nothing moved")
	assert_eq(_steps(), 0, "no step")
	assert_true(_said("grid snap is off"), "and it said why: %s" % str(rig.toasts()))
	await _leave(level)


# ===========================================================================
# Vertex mode
# ===========================================================================


## Vertex mode on `brush`, with the vertices `wanted` picks out of its local
## vertices selected.
func _select_vertices(level: Node, brush: Node, wanted: Callable) -> void:
	rig.select([brush])
	_press("vertex_edit")
	assert_true(rig.plugin._vertex_mode, "vertex mode is on")
	var vs = level.vertex_system
	var verts: PackedVector3Array = vs.get_brush_vertices(brush)
	for i in verts.size():
		if wanted.call(verts[i]):
			vs.select_vertex(str(brush.brush_id), i, true)


func _world_vertices(level: Node, brush: Node) -> Array:
	var out: Array = []
	for v in level.vertex_system.get_brush_vertices(brush):
		out.append(brush.global_transform * v)
	return out


func _has_point(points: Array, wanted: Vector3) -> bool:
	for point in points:
		if (point as Vector3).is_equal_approx(wanted):
			return true
	return false


func test_ctrl_b_in_vertex_mode_snaps_the_selected_vertices_in_world_space():
	var level = await _level(1.0)
	# Corners at x -0.7 and 1.3, y 0 and 1.3, z -0.9 and 1.1: none on the grid
	# but the bottom's height.
	var brush = rig.box(level, "v", Vector3(0.3, 0.65, 0.1), Vector3(2, 1.3, 2))
	_select_vertices(level, brush, func(v: Vector3): return v.y > 0.0)
	var position_before: Vector3 = brush.global_position
	assert_eq(_press("vertex_snap_to_grid"), STOP, "Ctrl+B is taken in vertex mode")
	var top: Array = Array(level.vertex_system.get_selected_world_positions())
	assert_eq(top.size(), 4, "the four top corners are still selected")
	for corner in [Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		assert_true(_has_point(top, corner), "a top corner went to %s: %s" % [corner, top])
	var all_now := _world_vertices(level, brush)
	for corner in [Vector3(-0.7, 0, -0.9), Vector3(1.3, 0, -0.9), Vector3(1.3, 0, 1.1)]:
		assert_true(_has_point(all_now, corner), "the bottom stays: %s" % corner)
	assert_eq(brush.global_position, position_before, "the vertices moved, not the brush")
	assert_eq(_steps(), 1, "one step")
	rig.undo().press_undo()
	await rig.frame()
	var undone := _world_vertices(level, brush)
	assert_true(
		_has_point(undone, Vector3(1.3, 1.3, 1.1)), "undo puts the top back: %s" % str(undone)
	)
	assert_false(_has_point(undone, Vector3(1, 1, 1)))
	await _leave(level)


func test_in_vertex_mode_ctrl_b_never_snaps_whole_brushes():
	# Even with Snap Vertices to Grid moved to another chord: Snap to Grid is a
	# general action, which the keymap keeps out of vertex mode.
	var level = await _level(0.5)
	var box = rig.box(level, "a", Vector3(0.3, 0, 0.1), Vector3.ONE)
	_select_vertices(level, box, func(_v: Vector3): return false)
	var keymap = rig.plugin._keymap
	keymap.set_binding("vertex_snap_to_grid", KEY_B, true, true)
	_press("snap_to_grid")
	keymap.set_binding("vertex_snap_to_grid", KEY_B, true)
	assert_eq(box.global_position, Vector3(0.3, 0, 0.1), "the brush stayed where it was")
	assert_eq(_steps(), 0, "no step")
	await _leave(level)


func test_vertices_already_on_the_grid_add_no_step():
	var level = await _level(1.0)
	var brush = rig.box(level, "g", Vector3(1, 1, 1), Vector3(2, 2, 2))
	_select_vertices(level, brush, func(v: Vector3): return v.y > 0.0)
	var before := _world_vertices(level, brush)
	assert_eq(_press("vertex_snap_to_grid"), STOP)
	assert_eq(_world_vertices(level, brush), before, "nothing moved")
	assert_eq(_steps(), 0, "no step")
	await _leave(level)


func test_a_vertex_snap_that_would_dent_the_brush_is_refused_and_says_why():
	var level = await _level(1.0)
	# A slab from y 0.3 to 0.45. Its top snaps to 0, below its own bottom.
	var brush = rig.box(level, "d", Vector3(1, 0.375, 1), Vector3(2, 0.15, 2))
	_select_vertices(level, brush, func(v: Vector3): return v.y > 0.0)
	var before := _world_vertices(level, brush)
	rig.clear_toasts()
	_press("vertex_snap_to_grid")
	assert_eq(_world_vertices(level, brush), before, "nothing moved")
	assert_eq(_steps(), 0, "no step")
	assert_true(_said("non-convex"), "and it said why: %s" % str(rig.toasts()))
	await _leave(level)


func test_two_vertices_snapped_onto_one_grid_point_are_refused():
	var level = await _level(1.0)
	# Smaller than a grid step: every corner's nearest grid point is the origin.
	var brush = rig.box(level, "s", Vector3(0.2, 0.2, 0.2), Vector3(0.4, 0.4, 0.4))
	_select_vertices(level, brush, func(_v: Vector3): return true)
	var before := _world_vertices(level, brush)
	rig.clear_toasts()
	_press("vertex_snap_to_grid")
	assert_eq(_world_vertices(level, brush), before, "nothing moved")
	assert_eq(_steps(), 0, "no step")
	assert_true(_said("one grid point"), "and it said why: %s" % str(rig.toasts()))
	await _leave(level)
