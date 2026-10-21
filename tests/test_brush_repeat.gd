extends GutTest

## Repeat the last brush with one click or key (#1407).
##
## Pillars, crates and fence posts are one brush many times over, and each was a
## fresh two stage drag that had to hit the same size again, or a Duplicate and a
## move. After each Draw the drag system keeps the brush it made; the context
## toolbar's Repeat button, or Shift+D, arms a stamp of it whose ghost follows the
## cursor standing where a Draw would start, and each left click places a copy as
## one Place Brush step until Esc, a right click or another tool lets go.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

const BrushShape = LevelRootScript.BrushShape
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const UNION := CSGShape3D.OPERATION_UNION
const SUBTRACTION := CSGShape3D.OPERATION_SUBTRACTION
## The cylinder the acceptance asks for: 2 across, 3 high.
const CYLINDER_SIZE := Vector3(2, 3, 2)

var rig := PluginRig.new()
var brick := StandardMaterial3D.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func after_each():
	if rig.plugin:
		rig.plugin._ensure_brush_stamp().disarm()


func _brushes(level) -> Array:
	return level._iter_managed_brush_nodes()


func _made_since(level, before: Array) -> Array:
	var out: Array = []
	for brush in _brushes(level):
		if not before.has(brush):
			out.append(brush)
	return out


func _screen(world: Vector3) -> Vector2:
	return rig.camera.unproject_position(world)


## A Draw through the drag system, as the viewport's press, base, height and
## release make one, of a `size` brush of `shape` standing on `at`, committed as
## the plugin commits a Draw. The info the Draw gave.
func _draw(level, shape: int, size: Vector3, operation := UNION, at := Vector3.ZERO) -> Dictionary:
	assert_true(level.begin_drag(rig.camera, _screen(at), operation, size, shape, 12))
	# Corner to corner across the base, then up to the height, as typed.
	level.input_state.drag_origin = at - Vector3(size.x, 0, size.z) * 0.5
	level.input_state.drag_end = at + Vector3(size.x, 0, size.z) * 0.5
	level.input_state.advance_to_height(_screen(at))
	level.input_state.drag_height = size.y
	var result: Dictionary = level.end_drag_info(rig.camera, _screen(at), size)
	assert_true(result.get("placed", false), "the draw places a brush")
	rig.plugin._commit_brush_placement(level, result["info"])
	return result["info"]


func _drawing_level() -> Node:
	var level = await rig.make_level()
	rig.plugin.dock.tool_draw.button_pressed = true
	level.active_material = brick
	return level


func _toolbar_repeat(level) -> Button:
	rig.plugin._update_context_toolbar_state(level, 0)
	var toolbar = rig.plugin._context_toolbar
	return toolbar.find_child("RepeatBtn", true, false) as Button


func _stamp():
	return rig.plugin._ensure_brush_stamp()


func _arm() -> int:
	return rig.forward(PluginRig.key_for("repeat_brush"))


func _move_to(world: Vector3) -> void:
	rig.forward(PluginRig.motion(_screen(world)))


func _click(world: Vector3) -> void:
	var at := _screen(world)
	rig.forward(PluginRig.motion(at))
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, at)), STOP, "a click places")
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, at)), STOP, "and lets go")


func _ghost(level) -> MeshInstance3D:
	return level.get_node_or_null("RepeatGhost") as MeshInstance3D


# ===========================================================================
# What a Draw leaves behind
# ===========================================================================


func test_a_draw_remembers_the_brush_it_made():
	var level = await _drawing_level()
	assert_eq(level.drag_system.last_drawn, {}, "nothing before the first Draw")
	_draw(level, BrushShape.CYLINDER, CYLINDER_SIZE)
	var kept: Dictionary = level.drag_system.last_drawn
	assert_eq(kept["shape"], BrushShape.CYLINDER, "its shape")
	assert_eq(kept["size"], CYLINDER_SIZE, "its size")
	assert_eq(kept["sides"], 12, "its Sides")
	assert_eq(kept["operation"], UNION, "Solid or Cutout")
	assert_eq(kept["material"], brick, "and the Active Material it got")
	assert_false(kept.has("center"), "but not where it went")
	assert_false(kept.has("brush_id"))
	await rig.leave_level(level)


func test_a_drawn_cutout_is_remembered_without_a_material():
	var level = await _drawing_level()
	_draw(level, BrushShape.BOX, Vector3(1, 1, 1), SUBTRACTION)
	assert_eq(level.drag_system.last_drawn["operation"], SUBTRACTION)
	assert_false(level.drag_system.last_drawn.has("material"), "a cut keeps the cut look")
	await rig.leave_level(level)


# ===========================================================================
# The button and the key
# ===========================================================================


func test_the_repeat_button_waits_for_the_first_draw_and_then_shows_it():
	var level = await _drawing_level()
	var button := _toolbar_repeat(level)
	assert_not_null(button, "the Draw section has a Repeat button")
	assert_true(button.disabled, "disabled before the first Draw")
	_draw(level, BrushShape.CYLINDER, CYLINDER_SIZE)
	button = _toolbar_repeat(level)
	assert_false(button.disabled, "and ready after it")
	assert_eq(button.text, "Cyl 2 x 3 x 2", "naming the brush it would place")
	assert_not_null(button.icon, "beside the shape's icon")
	button.pressed.emit()
	assert_true(_stamp().armed, "pressing it arms the stamp")
	await rig.leave_level(level)


func test_shift_d_before_the_first_draw_arms_nothing_and_says_why():
	var level = await _drawing_level()
	assert_eq(_arm(), STOP, "Shift+D is HammerForge's")
	assert_false(_stamp().armed, "there is nothing to repeat")
	assert_true("Nothing to repeat yet: draw a brush first" in rig.toasts(), str(rig.toasts()))
	await rig.leave_level(level)


func test_shift_d_arms_a_stamp_whose_ghost_stands_where_a_draw_would_start():
	var level = await _drawing_level()
	_draw(level, BrushShape.CYLINDER, CYLINDER_SIZE)
	rig.plugin.dock.tool_select.button_pressed = true
	assert_eq(_arm(), STOP)
	assert_true(_stamp().armed, "Shift+D arms a stamp of the last brush")
	assert_eq(rig.plugin.dock.get_tool(), 0, "with Draw taking the pointer")
	_move_to(Vector3(4, 0, 2))
	var ghost := _ghost(level)
	assert_not_null(ghost, "a ghost follows the cursor")
	assert_true(ghost.visible)
	var start: Vector3 = (
		level.drag_system.draw_start(rig.camera, _screen(Vector3(4, 0, 2)))["point"]
	)
	assert_almost_eq(
		ghost.global_position,
		start + Vector3(0, 1.5, 0),
		Vector3.ONE * 0.001,
		"standing where a Draw would start"
	)
	assert_null(ghost.owner, "and it is never saved with the scene")
	await rig.leave_level(level)


# ===========================================================================
# Placing
# ===========================================================================


func test_each_click_places_one_copy_and_stays_armed():
	var level = await _drawing_level()
	_draw(level, BrushShape.CYLINDER, CYLINDER_SIZE)
	_arm()
	for spot in [Vector3(4, 0, 0), Vector3(-4, 0, 0)]:
		var before := _brushes(level)
		# Asked first: once the copy is there, the ray meets the copy.
		var start: Vector3 = level.drag_system.draw_start(rig.camera, _screen(spot))["point"]
		_click(spot)
		var made := _made_since(level, before)
		assert_eq(made.size(), 1, "one brush a click")
		var copy = made[0]
		assert_eq(copy.shape, BrushShape.CYLINDER, "of that shape")
		assert_eq(copy.size, CYLINDER_SIZE, "and size")
		assert_eq(copy.sides, 12, "and Sides")
		assert_eq(copy.operation, UNION, "and operation")
		assert_eq(copy.material_override, brick, "and material")
		assert_almost_eq(
			copy.global_position, start + Vector3(0, 1.5, 0), Vector3.ONE * 0.001, "on the grid"
		)
		assert_almost_eq(copy.global_position.y - copy.size.y * 0.5, 0.0, 0.001)
		assert_true(_stamp().armed, "and the stamp stays armed for the next")
	await rig.leave_level(level)


func test_a_copy_stands_on_the_face_under_the_cursor():
	var level = await _drawing_level()
	rig.box(level, "plinth", Vector3(0, 2, 0), Vector3(4, 4, 4))
	_draw(level, BrushShape.BOX, Vector3(1, 2, 1), UNION, Vector3(6, 0, 0))
	_arm()
	var before := _brushes(level)
	_click(Vector3(0, 4, 0))
	var made := _made_since(level, before)
	assert_eq(made.size(), 1)
	assert_almost_eq(made[0].global_position.y, 5.0, 0.001, "its bottom on the plinth's top")
	await rig.leave_level(level)


func test_each_placement_is_one_undo_step():
	var level = await _drawing_level()
	_draw(level, BrushShape.CYLINDER, CYLINDER_SIZE)
	_arm()
	var before := _brushes(level)
	_click(Vector3(4, 0, 0))
	_click(Vector3(-4, 0, 0))
	assert_eq(_made_since(level, before).size(), 2)
	assert_true(rig.undo().press_undo(), "the second copy undoes")
	assert_eq(_made_since(level, before).size(), 1, "on its own")
	assert_true(rig.undo().press_undo(), "and then the first")
	assert_eq(_made_since(level, before).size(), 0)
	assert_true(rig.undo().press_redo())
	assert_eq(_made_since(level, before).size(), 1, "and each redoes as one step")
	await rig.leave_level(level)


func test_a_cutout_repeats_as_a_pending_cut():
	var level = await _drawing_level()
	_draw(level, BrushShape.BOX, Vector3(1, 1, 1), SUBTRACTION)
	_arm()
	var before := _brushes(level)
	_click(Vector3(3, 0, 0))
	var made := _made_since(level, before)
	assert_eq(made.size(), 1)
	assert_eq(made[0].operation, SUBTRACTION, "a cut")
	assert_eq(made[0].get_parent(), level.pending_node, "waiting with the other cuts")
	await rig.leave_level(level)


# ===========================================================================
# Letting go
# ===========================================================================


func _armed_with_ghost(level) -> void:
	_draw(level, BrushShape.CYLINDER, CYLINDER_SIZE)
	_arm()
	_move_to(Vector3(4, 0, 0))
	assert_true(_stamp().armed)
	assert_not_null(_ghost(level))


func test_escape_disarms_and_takes_the_ghost_away():
	var level = await _drawing_level()
	_armed_with_ghost(level)
	rig.forward(PluginRig.key(KEY_ESCAPE))
	assert_false(_stamp().armed, "Esc lets go")
	assert_null(_ghost(level), "and the ghost goes with it")
	await rig.leave_level(level)


func test_a_right_click_disarms_and_takes_the_ghost_away():
	var level = await _drawing_level()
	_armed_with_ghost(level)
	var before := _brushes(level)
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true, _screen(Vector3.ZERO))), STOP)
	assert_false(_stamp().armed, "a right click lets go")
	assert_null(_ghost(level))
	assert_eq(_made_since(level, before), [], "and places nothing")
	await rig.leave_level(level)


func test_another_tool_disarms_and_takes_the_ghost_away():
	var level = await _drawing_level()
	_armed_with_ghost(level)
	rig.forward(PluginRig.key_for("tool_select"))
	assert_false(_stamp().armed, "Select lets go")
	assert_null(_ghost(level))
	_armed_with_ghost(level)
	rig.plugin.dock.set_extrude_tool(1)
	rig.forward(PluginRig.motion(_screen(Vector3.ZERO)))
	assert_false(_stamp().armed, "and so does the dock's Extrude")
	assert_null(_ghost(level))
	await rig.leave_level(level)


func test_after_letting_go_a_click_draws_again():
	var level = await _drawing_level()
	_armed_with_ghost(level)
	rig.forward(PluginRig.key(KEY_ESCAPE))
	var at := _screen(Vector3(4, 0, 0))
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, at)), STOP)
	assert_true(level.input_state.is_drag_base(), "the click starts a Draw, not a copy")
	level.cancel_drag()
	await rig.leave_level(level)
