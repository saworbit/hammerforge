extends GutTest
## Vertex editing on many corners at once (#1713): a corner shared by several
## selected brushes moves as one, a box selects corners, Delete and Alt+click
## remove and add corners, and the arrows and the turn keys move the selected
## corners rather than whole brushes.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFConvexClip = preload("res://addons/hammerforge/hf_convex_clip.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()
var _grid_before := 0.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


## A level with `brushes` selected and vertex mode on.
func _vertex_mode(level: Node, brushes: Array) -> void:
	rig.select(brushes)
	await rig.frame()
	rig.plugin._toggle_vertex_mode(level)
	await rig.frame()
	assert_true(rig.plugin._vertex_mode, "fixture: vertex mode is on")


func _leave(level: Node) -> void:
	if rig.plugin._vertex_mode:
		rig.plugin._toggle_vertex_mode(level)
	await rig.leave_level(level)
	rig.plugin.dock._apply_grid_snap(_grid_before)


func _level() -> Node:
	var level = await rig.make_level()
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(1.0)
	return level


func _corner_index(brush: DraftBrush, world: Vector3) -> int:
	var verts: PackedVector3Array = (
		brush.get_parent().get_parent().vertex_system.get_brush_vertices(brush)
	)
	for i in verts.size():
		if (brush.global_transform * verts[i]).distance_to(world) < 0.001:
			return i
	return -1


func _press_at(world: Vector3, modifiers := {}) -> int:
	var event := PluginRig.click(MOUSE_BUTTON_LEFT, true, rig.camera.unproject_position(world))
	event.shift_pressed = modifiers.get("shift", false)
	event.ctrl_pressed = modifiers.get("ctrl", false)
	event.alt_pressed = modifiers.get("alt", false)
	return rig.forward(event)


func _release_at(world: Vector3) -> int:
	return rig.forward(
		PluginRig.click(MOUSE_BUTTON_LEFT, false, rig.camera.unproject_position(world))
	)


func _corners_of(brush: DraftBrush) -> Array:
	var out: Array = []
	var vs = rig.plugin.active_root.vertex_system
	for v in vs.get_brush_vertices(brush):
		out.append(brush.global_transform * v)
	return out


func _has_corner(brush: DraftBrush, world: Vector3) -> bool:
	for corner in _corners_of(brush):
		if corner.distance_to(world) < 0.001:
			return true
	return false


func test_the_corner_four_floor_brushes_share_moves_as_one() -> void:
	var level = await _level()
	var floors: Array = []
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			floors.append(
				rig.box(level, "f%d%d" % [int(x), int(z)], Vector3(x, -0.25, z), Vector3(2, 0.5, 2))
			)
	await _vertex_mode(level, floors)
	var vs = level.vertex_system
	var shared := Vector3(0, 0, 0)
	var picked: int = _corner_index(floors[0], shared)
	assert_gt(picked, -1, "fixture: the corner is there")
	var count: int = vs.select_shared_corner(str(floors[0].brush_id), picked)
	assert_eq(count, 4, "the four brushes share it")
	assert_eq(vs.get_selection_count(), 4, "one corner of each is selected")
	assert_false(vs.offset_selected(Vector3(0, 0.5, 0)).is_empty(), "the move holds")
	for brush in floors:
		assert_true(_has_corner(brush, Vector3(0, 0.5, 0)), "%s has the raised corner" % brush.name)
	await _leave(level)


func test_a_click_on_a_shared_corner_picks_them_all_and_alt_picks_one() -> void:
	var level = await _level()
	var a: DraftBrush = rig.box(level, "a", Vector3(-1, 1, 0), Vector3(2, 2, 2))
	var b: DraftBrush = rig.box(level, "b", Vector3(1, 1, 0), Vector3(2, 2, 2))
	await _vertex_mode(level, [a, b])
	var vs = level.vertex_system
	var shared := Vector3(0, 2, 1)
	_press_at(shared)
	_release_at(shared)
	assert_eq(vs.get_selection_count(), 2, "a click takes both brushes' corner")
	assert_eq(rig.plugin._vertex_shared_count, 2, "and says two share it")
	vs.clear_selection()
	_press_at(shared, {"alt": true})
	_release_at(shared)
	assert_eq(vs.get_selection_count(), 1, "Alt takes the one brush's corner")
	await _leave(level)


func test_a_box_drag_on_empty_space_selects_the_corners_inside_it() -> void:
	var level = await _level()
	var a: DraftBrush = rig.box(level, "a", Vector3(-3, 1, 0), Vector3(2, 2, 2))
	var b: DraftBrush = rig.box(level, "b", Vector3(3, 1, 0), Vector3(2, 2, 2))
	await _vertex_mode(level, [a, b])
	var vs = level.vertex_system
	# A front view, so the top corners sit in a band above the bottom ones. The
	# box starts in the empty space above both boxes.
	var camera_before: Transform3D = rig.camera.global_transform
	rig.camera.look_at_from_position(Vector3(0, 1, 20), Vector3(0, 1, 0))
	var from := rig.camera.unproject_position(Vector3(-5, 3, 1))
	var to := rig.camera.unproject_position(Vector3(5, 1.5, 1))
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, from)), STOP, "the box begins")
	rig.forward(PluginRig.motion(to, MOUSE_BUTTON_MASK_LEFT))
	assert_true(rig.plugin._marquee_overlay_active, "and is drawn")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, to))
	var picked: PackedVector3Array = vs.get_selected_world_positions()
	var tops := 0
	for point in picked:
		if absf(point.y - 2.0) < 0.001:
			tops += 1
	assert_eq(tops, 8, "every top corner of both boxes")
	assert_eq(picked.size(), 8, "and none of the bottom ones")
	# Ctrl takes away.
	var mid := rig.camera.unproject_position(Vector3(0, 1.5, 1))
	var press := PluginRig.click(MOUSE_BUTTON_LEFT, true, from)
	press.ctrl_pressed = true
	rig.forward(press)
	rig.forward(PluginRig.motion(mid, MOUSE_BUTTON_MASK_LEFT))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, mid))
	rig.camera.global_transform = camera_before
	assert_eq(vs.get_selection_count(), 4, "Ctrl took the left box's away")
	await _leave(level)


func test_deleting_one_top_corner_of_a_box_leaves_a_convex_brush() -> void:
	var level = await _level()
	var box: DraftBrush = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	await _vertex_mode(level, [box])
	var vs = level.vertex_system
	vs.select_vertex(str(box.brush_id), _corner_index(box, Vector3(1, 2, 1)))
	assert_eq(rig.forward(PluginRig.key(KEY_DELETE)), STOP, "Delete is the corner's")
	var brush: DraftBrush = level.brush_system.find_brush_by_id("a")
	assert_not_null(brush, "the brush is still there")
	if brush == null:
		return
	assert_false(_has_corner(brush, Vector3(1, 2, 1)), "without the corner")
	assert_eq(_corners_of(brush).size(), 7, "seven corners left")
	assert_eq(SolidChecks.open_edge_count(brush.faces), 0, "closed")
	assert_true(SolidChecks.is_convex(brush.faces), "convex")
	assert_true(rig.undo().press_undo(), "one undo step")
	brush = level.brush_system.find_brush_by_id("a")
	assert_true(_has_corner(brush, Vector3(1, 2, 1)), "and the corner is back")
	await _leave(level)


func test_deleting_what_would_leave_a_brush_flat_is_refused() -> void:
	var level = await _level()
	var box: DraftBrush = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	await _vertex_mode(level, [box])
	var vs = level.vertex_system
	for corner in [Vector3(-1, 2, -1), Vector3(1, 2, -1), Vector3(-1, 2, 1), Vector3(1, 2, 1)]:
		vs.select_vertex(str(box.brush_id), _corner_index(box, corner), true)
	assert_true(vs.delete_selected().is_empty(), "the bottom four alone are flat")
	assert_eq(_corners_of(box).size(), 8, "and nothing changed")
	await _leave(level)


func test_alt_click_above_a_box_s_top_adds_a_corner_and_makes_a_pyramid_top() -> void:
	var level = await _level()
	var box: DraftBrush = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	await _vertex_mode(level, [box])
	assert_eq(_press_at(Vector3(0, 2, 0), {"alt": true}), STOP, "Alt on the top face")
	_release_at(Vector3(0, 2, 0))
	var brush: DraftBrush = level.brush_system.find_brush_by_id("a")
	assert_true(_has_corner(brush, Vector3(0, 3, 0)), "a corner one step above the top")
	assert_false(
		_has_corner(brush, Vector3(1, 2, 1)) and _faces_facing_up(brush) > 0, "no flat top left"
	)
	assert_true(SolidChecks.is_convex(brush.faces), "convex")
	var vs = level.vertex_system
	assert_true(vs.add_corner("a", Vector3(0, 1, 0)).is_empty(), "a point inside is refused")
	await _leave(level)


func _faces_facing_up(brush: DraftBrush) -> int:
	var count := 0
	for face in brush.faces:
		if HFConvexClip.face_plane(face).normal.dot(Vector3.UP) > 0.999:
			count += 1
	return count


func test_the_arrow_keys_move_the_selected_corners_in_vertex_mode() -> void:
	var level = await _level()
	var box: DraftBrush = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	await _vertex_mode(level, [box])
	var vs = level.vertex_system
	for corner in [Vector3(-1, 2, -1), Vector3(1, 2, -1), Vector3(-1, 2, 1), Vector3(1, 2, 1)]:
		vs.select_vertex(str(box.brush_id), _corner_index(box, corner), true)
	var before: Vector3 = box.global_position
	var key := PluginRig.key(KEY_PAGEUP)
	assert_eq(rig.forward(key), STOP, "Page Up is the corners'")
	var brush: DraftBrush = level.brush_system.find_brush_by_id("a")
	assert_true(_has_corner(brush, Vector3(1, 3, 1)), "the top is a step higher")
	assert_true(_has_corner(brush, Vector3(1, 0, 1)), "the bottom stayed")
	assert_almost_eq(brush.global_position, before, Vector3.ONE * 0.001, "the brush did not move")
	await _leave(level)


func test_turning_the_top_corners_twists_the_brush_or_is_refused() -> void:
	var level = await _level()
	var box: DraftBrush = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	await _vertex_mode(level, [box])
	var vs = level.vertex_system
	for corner in [Vector3(-1, 2, -1), Vector3(1, 2, -1), Vector3(-1, 2, 1), Vector3(1, 2, 1)]:
		vs.select_vertex(str(box.brush_id), _corner_index(box, corner), true)
	level.rotate_snap_degrees = 45.0
	assert_eq(rig.forward(PluginRig.key(KEY_R)), STOP, "R is the corners'")
	var brush: DraftBrush = level.brush_system.find_brush_by_id("a")
	var turned := (
		_has_corner(brush, Vector3(0, 2, sqrt(2.0))) or _has_corner(brush, Vector3(sqrt(2.0), 2, 0))
	)
	# The square top turned 45 degrees over the square base: the sides bend, are
	# cut flat into triangles, and the brush is an antiprism, still convex.
	assert_true(turned, "the top corners turned")
	assert_true(SolidChecks.is_convex(brush.faces), "a twisted brush, still convex")
	assert_eq(SolidChecks.open_edge_count(brush.faces), 0, "and closed")
	assert_true(_has_corner(brush, Vector3(1, 0, 1)), "on the base it had")
	await _leave(level)


func test_scale_spreads_the_selected_corners_about_their_middle() -> void:
	var level = await _level()
	var box: DraftBrush = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	await _vertex_mode(level, [box])
	var vs = level.vertex_system
	for corner in [Vector3(-1, 2, -1), Vector3(1, 2, -1), Vector3(-1, 2, 1), Vector3(1, 2, 1)]:
		vs.select_vertex(str(box.brush_id), _corner_index(box, corner), true)
	var plugin_ops = load("res://addons/hammerforge/plugin_vertex_ops.gd")
	assert_true(plugin_ops.scale_selected(rig.plugin, level, Vector3(0.5, 1, 0.5)), "it scales")
	var brush: DraftBrush = level.brush_system.find_brush_by_id("a")
	assert_true(_has_corner(brush, Vector3(0.5, 2, 0.5)), "a tapered top")
	assert_true(_has_corner(brush, Vector3(1, 0, 1)), "on the same base")
	assert_true(SolidChecks.is_convex(brush.faces), "convex")
	assert_false(
		plugin_ops.scale_selected(rig.plugin, level, Vector3(0, 1, 1)), "a zero factor is refused"
	)
	await _leave(level)


func test_scale_vertices_asks_for_three_factors() -> void:
	var level = await _level()
	var box: DraftBrush = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	await _vertex_mode(level, [box])
	var ops = load("res://addons/hammerforge/plugin_vertex_ops.gd")
	assert_null(ops.open_scale_dialog(rig.plugin, level), "nothing selected, nothing to ask")
	var vs = level.vertex_system
	for corner in [Vector3(-1, 2, -1), Vector3(1, 2, -1), Vector3(-1, 2, 1), Vector3(1, 2, 1)]:
		vs.select_vertex(str(box.brush_id), _corner_index(box, corner), true)
	var dialog: ConfirmationDialog = ops.open_scale_dialog(rig.plugin, level)
	assert_not_null(dialog)
	if dialog == null:
		return
	(dialog.find_child("X", true, false) as SpinBox).value = 0.5
	(dialog.find_child("Z", true, false) as SpinBox).value = 0.5
	dialog.confirmed.emit()
	await rig.frame()
	var brush: DraftBrush = level.brush_system.find_brush_by_id("a")
	assert_true(_has_corner(brush, Vector3(0.5, 2, 0.5)), "the top is scaled")
	await _leave(level)
