extends GutTest
## A depth typed during an Extrude places the extrusion at that depth, as a typed
## size does for a Draw (#1560). Enter used to end the extrude with nothing placed:
## the number went into the Draw's height and the Extrude read only the mouse.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFExtrudeTool = preload("res://addons/hammerforge/hf_extrude_tool.gd")
const HFPluginNumericInput = preload("res://addons/hammerforge/plugin_numeric_input.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()
var _grid_before := 0.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


## A level with an 8 unit box "a" at the origin, the grid at 1, and `tool` in hand.
func _level(tool: String) -> Node:
	var level = await rig.make_level()
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(1.0)
	rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	rig.plugin._hotkey_palette.action_invoked.emit(tool)
	return level


func _leave(level: Node) -> void:
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await rig.leave_level(level)
	rig.plugin.dock._apply_grid_snap(_grid_before)


func _left(pressed: bool, point: Vector3) -> int:
	var at := rig.camera.unproject_position(point)
	return rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, pressed, at))


## Type `text` over the viewport a key at a time, then `finish` (Enter by default).
func _type(text: String, finish := KEY_ENTER) -> int:
	for ch in text:
		rig.forward(PluginRig.key(KEY_PERIOD if ch == "." else KEY_0 + int(ch)))
	return rig.forward(PluginRig.key(finish)) if finish != KEY_NONE else STOP


## The brushes in the level besides the box the test began with.
func _made(level: Node) -> Array:
	var out: Array = []
	for child in level.draft_brushes_node.get_children():
		if str(child.get("brush_id")) != "a":
			out.append(child)
	return out


func _face_facing(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.dot(normal) > 0.99:
			return i
	return -1


func test_a_typed_depth_extrudes_the_top_face_that_far() -> void:
	var level = await _level("tool_extrude_up")
	assert_eq(_left(true, Vector3(0, 4, 0)), STOP, "a press on the top face starts the extrude")
	assert_eq(_type("3"), STOP, "Enter is taken")
	await rig.frame()
	var made := _made(level)
	assert_eq(made.size(), 1, "and places the block")
	if made.size() == 1:
		assert_eq(made[0].size, Vector3(8, 3, 8), "3 deep")
		assert_eq(made[0].global_position, Vector3(0, 5.5, 0), "standing on the face")
	assert_true(level.input_state.is_idle(), "the extrude is over")
	assert_eq(rig.plugin.numeric_buffer, "", "and the number used")
	_left(false, Vector3(0, 4, 0))
	await rig.frame()
	assert_eq(_made(level).size(), 1, "the release that follows places nothing more")
	await _leave(level)


## The issue's own steps: a number put in the buffer with no key typed, so no
## preview has run, then `apply_value()` as Enter calls it.
func test_apply_value_alone_places_the_buffered_depth() -> void:
	var level = await _level("tool_extrude_up")
	_left(true, Vector3(0, 4, 0))
	rig.plugin.numeric_buffer = "3"
	HFPluginNumericInput.apply_value(rig.plugin, level)
	await rig.frame()
	var made := _made(level)
	assert_eq(made.size(), 1, "the block is placed")
	if made.size() == 1:
		assert_eq(made[0].size, Vector3(8, 3, 8), "3 deep")
		assert_eq(made[0].global_position, Vector3(0, 5.5, 0))
	_left(false, Vector3(0, 4, 0))
	await _leave(level)


func test_a_typed_depth_extrudes_a_side_face_along_its_normal() -> void:
	var level = await _level("tool_extrude_up")
	assert_eq(_left(true, Vector3(0, 0, 4)), STOP, "a press on the +Z face starts the extrude")
	# Off the grid on purpose: a typed number is taken as it is, where the mouse
	# would round to the grid step.
	_type("2.5", KEY_TAB)
	await rig.frame()
	var made := _made(level)
	assert_eq(made.size(), 1, "Tab places the block as Enter does")
	if made.size() == 1:
		assert_eq(made[0].size, Vector3(8, 8, 2.5), "2.5 out along Z")
		assert_eq(made[0].global_position, Vector3(0, 0, 5.25), "against the face")
	_left(false, Vector3(0, 0, 4))
	await _leave(level)


func test_a_typed_depth_on_extrude_down_goes_into_the_brush() -> void:
	var level = await _level("tool_extrude_down")
	assert_eq(_left(true, Vector3(0, 4, 0)), STOP)
	_type("3")
	await rig.frame()
	var made := _made(level)
	assert_eq(made.size(), 1, "the block is placed")
	if made.size() == 1:
		assert_eq(made[0].size, Vector3(8, 3, 8), "3 deep")
		assert_eq(made[0].global_position, Vector3(0, 2.5, 0), "down from the face, not up")
	_left(false, Vector3(0, 4, 0))
	await _leave(level)


## What `_made()` found, as text to compare: size, place and every face.
func _described(brush: Node) -> String:
	var faces: Array = []
	for face in brush.faces:
		faces.append(face.to_dict())
	return var_to_str([brush.size, brush.global_transform, faces])


## The typed block is one undo step that undo takes away and redo puts back, and
## it is the block a mouse drag to the same depth makes, texture and all.
func test_a_typed_extrusion_is_one_step_and_the_drag_block() -> void:
	var level = await _level("tool_extrude_up")
	var box = level.find_brush_by_id("a")
	box.faces[_face_facing(box, Vector3.UP)].map_texture = "brick"
	var steps: int = rig.undo().step_count()
	_left(true, Vector3(0, 4, 0))
	_type("3")
	_left(false, Vector3(0, 4, 0))
	await rig.frame()
	assert_eq(rig.undo().step_count(), steps + 1, "one undo step")
	var made := _made(level)
	assert_eq(made.size(), 1)
	var typed := _described(made[0]) if made.size() == 1 else ""
	if made.size() == 1:
		assert_eq(made[0].faces[0].map_texture, "brick", "with the face's texture carried")
	assert_true(rig.undo().press_undo(), "undo")
	await rig.frame()
	assert_eq(_made(level).size(), 0, "takes the block away")
	assert_true(rig.undo().press_redo(), "redo")
	await rig.frame()
	made = _made(level)
	assert_eq(made.size(), 1, "puts it back")
	if made.size() == 1:
		assert_eq(_described(made[0]), typed, "as it was")
	assert_true(rig.undo().press_undo())
	await rig.frame()

	var on_top := rig.camera.unproject_position(Vector3(0, 4, 0))
	# 150 pixels up is 3 units at a grid of 1.
	var pulled := on_top + Vector2(0, -3.0 / HFExtrudeTool.HEIGHT_SENSITIVITY)
	_left(true, Vector3(0, 4, 0))
	rig.forward(PluginRig.motion(pulled, MOUSE_BUTTON_MASK_LEFT))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, pulled))
	await rig.frame()
	made = _made(level)
	assert_eq(made.size(), 1, "a drag to 3 places a block")
	if made.size() == 1:
		assert_eq(made[0].size, Vector3(8, 3, 8))
		assert_eq(_described(made[0]), typed, "the same block the typed depth made")
	await _leave(level)


## A number on the HUD holds the depth while the mouse moves, as it holds a Draw's
## height, and the release then places that depth.
func test_a_typed_depth_stands_while_the_mouse_moves() -> void:
	var level = await _level("tool_extrude_up")
	_left(true, Vector3(0, 4, 0))
	_type("3", KEY_NONE)
	assert_eq(level.extrude_tool._current_height, 3.0, "the ghost takes the number at once")
	var far := rig.camera.unproject_position(Vector3(0, 4, 0)) + Vector2(0, -200)
	rig.forward(PluginRig.motion(far, MOUSE_BUTTON_MASK_LEFT))
	assert_eq(level.extrude_tool._current_height, 3.0, "and the mouse does not take it back")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, far))
	await rig.frame()
	var made := _made(level)
	assert_eq(made.size(), 1, "the release places the block")
	if made.size() == 1:
		assert_eq(made[0].size, Vector3(8, 3, 8), "at the typed depth")
	assert_eq(rig.plugin.numeric_buffer, "", "and the number is used up")
	# The next extrusion is the mouse's again.
	_left(true, Vector3(0, 4, 0))
	assert_eq(level.extrude_tool._current_height, 0.0, "a new extrude starts from nothing")
	rig.forward(PluginRig.motion(far, MOUSE_BUTTON_MASK_LEFT))
	assert_gt(level.extrude_tool._current_height, 3.0, "and follows the mouse")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, far))
	await _leave(level)


## A typed 0, or a depth past the tool's limit, places nothing, says why, and
## leaves the extrude running for the mouse or another number, as a refused Draw
## size leaves the Draw running.
func test_a_depth_the_tool_cannot_take_is_refused() -> void:
	var level = await _level("tool_extrude_up")
	_left(true, Vector3(0, 4, 0))
	rig.clear_toasts()
	assert_eq(_type("0"), STOP, "Enter is taken")
	await rig.frame()
	assert_eq(_made(level).size(), 0, "nothing is placed for 0")
	assert_true(level.input_state.is_extruding(), "the extrude keeps going")
	assert_eq(rig.plugin.numeric_buffer, "", "the number is cleared")
	assert_eq(rig.toasts().size(), 1, "and the refusal is said")
	var limit := int(HFExtrudeTool.MAX_EXTRUDE_HEIGHT)
	rig.clear_toasts()
	_type(str(limit + 1))
	await rig.frame()
	assert_eq(_made(level).size(), 0, "nothing is placed past the limit")
	assert_true(level.input_state.is_extruding(), "the extrude keeps going")
	assert_eq(rig.toasts().size(), 1, "and that is said too")
	if rig.toasts().size() == 1:
		assert_true(str(rig.toasts()[0]).contains(str(limit)), "with the limit")
	_type("2")
	await rig.frame()
	var made := _made(level)
	assert_eq(made.size(), 1, "a good number after a refused one still places")
	if made.size() == 1:
		assert_eq(made[0].size, Vector3(8, 2, 8))
	_left(false, Vector3(0, 4, 0))
	await _leave(level)
