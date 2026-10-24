extends GutTest
## Shear the selection (#1718), on the real plugin and level. Each brush of a
## leaning wall was leaned by hand, and the pieces drifted apart where they met.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFConvexClip = preload("res://addons/hammerforge/hf_convex_clip.gd")
const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")
const HFTransformSystemType = preload("res://addons/hammerforge/systems/hf_transform_system.gd")

var rig := PluginRig.new()
var said: Array = []
var _grid_before := 0.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _enter() -> Node:
	var level = await rig.make_level()
	said = []
	level.user_message.connect(func(text, _level): said.append(text))
	rig.undo().clear()
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(0.5)
	return level


func _leave(level: Node) -> void:
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	rig.undo().clear()
	rig.plugin.dock._apply_grid_snap(_grid_before)
	await rig.leave_level(level)


## Every corner of `brush` in the world, rounded so two brushes' can be compared.
func _corners(brush: Node) -> Array:
	var out: Array = []
	for face in brush.faces:
		for corner in face.local_verts:
			var point: Vector3 = (brush.global_transform * corner).snapped(Vector3.ONE * 0.0001)
			if not out.has(point):
				out.append(point)
	out.sort()
	return out


func _convex(brush: Node) -> bool:
	return HFConvexClip.is_convex_solid(brush.faces, HFConvexClip.interior_point(brush.faces))


func test_a_wall_of_three_brushes_leans_with_no_gap_where_they_meet():
	var level = await _enter()
	var wall: Array = []
	for i in 3:
		wall.append(rig.box(level, "w%d" % i, Vector3(-2 + 2 * i, 1.5, 0), Vector3(2, 3, 0.5)))
	rig.select(wall)
	assert_true(HFPluginEditActions.shear_selected(rig.plugin, level, 0, 1, 0.5 / 3.0))
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Shear", "one step")
	assert_eq(rig.undo().step_count(), 1)
	var leaned: Array = []
	for i in 3:
		leaned.append(level.find_brush_by_id("w%d" % i))
	for brush in leaned:
		assert_true(_convex(brush), "%s stays convex" % brush.name)
	var top: float = level.brush_system.world_bounds_of(leaned[2]).end.x
	assert_almost_eq(top, 3.5, 0.001, "the top moved 0.5 m over 3 m")
	for i in 2:
		var a: Array = _corners(leaned[i])
		var b: Array = _corners(leaned[i + 1])
		var shared := 0
		for point in a:
			if b.has(point):
				shared += 1
		assert_eq(shared, 4, "w%d and w%d meet on one face, with no gap" % [i, i + 1])
	await _leave(level)


func test_a_typed_ten_degrees_is_the_drag_that_matches_it():
	var level = await _enter()
	var brush = rig.box(level, "p", Vector3(0, 1.5, 0), Vector3(2, 3, 2))
	rig.select([brush])
	rig.plugin._hotkey_palette.action_invoked.emit("tool_shear")
	var tool = rig.plugin._tool_registry.get_active_tool()
	assert_eq(tool.tool_name(), "Shear")
	var lean := HFTransformSystemType.shear_amount_for_degrees(10.0)
	var handle := Vector3(0, 3, 0)
	var press := PluginRig.click(MOUSE_BUTTON_LEFT, true, rig.camera.unproject_position(handle))
	assert_eq(rig.forward(press), EditorPlugin.AFTER_GUI_INPUT_STOP, "the top handle is taken")
	var to := rig.camera.unproject_position(handle + Vector3(lean * 3.0, 0, 0))
	var motion := PluginRig.motion(to, MOUSE_BUTTON_MASK_LEFT)
	motion.ctrl_pressed = true
	rig.forward(motion)
	assert_almost_eq(tool._amount, lean, 0.002, "Ctrl drags off the grid")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, to))
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Shear")
	var dragged := _corners(level.find_brush_by_id("p"))
	assert_true(rig.undo().press_undo())
	await rig.frame()
	rig.select([level.find_brush_by_id("p")])
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	HFPluginEditActions.shear_selected(rig.plugin, level, 0, 1, lean)
	var typed := _corners(level.find_brush_by_id("p"))
	assert_eq(typed.size(), dragged.size())
	for i in mini(typed.size(), dragged.size()):
		assert_true(
			(typed[i] as Vector3).distance_to(dragged[i]) < 0.01,
			"%s by %s" % [typed[i], dragged[i]]
		)
	await _leave(level)


func test_a_drag_on_the_grid_and_escape():
	var level = await _enter()
	var brush = rig.box(level, "g", Vector3(0, 1, 0), Vector3(2, 2, 2))
	rig.select([brush])
	rig.plugin._hotkey_palette.action_invoked.emit("tool_shear")
	var tool = rig.plugin._tool_registry.get_active_tool()
	var handle := Vector3(0, 2, 0)
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, rig.camera.unproject_position(handle)))
	var to := rig.camera.unproject_position(handle + Vector3(0.62, 0, 0))
	rig.forward(PluginRig.motion(to, MOUSE_BUTTON_MASK_LEFT))
	assert_almost_eq(tool._amount, 0.25, 0.0001, "0.62 m held to the 0.5 grid, over 2 m")
	assert_eq(rig.forward(PluginRig.key(KEY_ESCAPE)), EditorPlugin.AFTER_GUI_INPUT_STOP)
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, to))
	assert_eq(rig.undo().step_count(), 0, "Escape let it go")
	await _leave(level)


func test_entities_move_with_the_shear_and_are_not_turned():
	var level = await _enter()
	var brush = rig.box(level, "b", Vector3(0, 1.5, 0), Vector3(2, 3, 2))
	var lamp: Node = level._create_entity_from_map(
		{"classname": "light_point", "origin": Vector3(0, 3, 0)}
	)
	lamp.rotation_degrees = Vector3(0, 30, 0)
	rig.select([brush, lamp])
	HFPluginEditActions.shear_selected(rig.plugin, level, 0, 1, 0.5)
	assert_true(lamp.global_position.is_equal_approx(Vector3(1.5, 3, 0)), str(lamp.global_position))
	assert_true(lamp.rotation_degrees.is_equal_approx(Vector3(0, 30, 0)), "not turned")
	assert_string_contains(said.back(), "moved 1 entity")
	await _leave(level)


func test_texture_lock_keeps_the_texture_on_the_faces():
	var level = await _enter()
	level.texture_lock = true
	var brush = rig.box(level, "t", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var shown: Array = []
	for face in brush.faces:
		shown.append(face.shown_uvs())
	rig.select([brush])
	HFPluginEditActions.shear_selected(rig.plugin, level, 2, 1, 0.5)
	var leaned = level.find_brush_by_id("t")
	for i in leaned.faces.size():
		assert_eq(leaned.faces[i].shown_uvs(), shown[i], "face %d shows the texture as it did" % i)
	level.texture_lock = false
	await _leave(level)


func test_what_cannot_be_sheared_says_why():
	var level = await _enter()
	var brush = rig.box(level, "s", Vector3(0, 1, 0), Vector3(2, 2, 2))
	rig.select([brush])
	assert_false(HFPluginEditActions.shear_selected(rig.plugin, level, 1, 1, 0.5))
	assert_eq(said.back(), "Shear: the axis that moves and the axis it leans over must differ")
	for i in brush.faces.size():
		if brush.faces[i].normal.y > 0.9:
			level.create_displacement("s", i, 2)
	HFPluginEditActions.shear_selected(rig.plugin, level, 0, 1, 0.5)
	assert_string_contains(said.back(), "a lean would stretch its sculpt")
	assert_eq(rig.undo().step_count(), 0, "and nothing changed")
	rig.select([])
	assert_false(HFPluginEditActions.shear_selected(rig.plugin, level, 0, 1, 0.5))
	assert_eq(said.back(), "Shear: select brushes or entities first")
	await _leave(level)
