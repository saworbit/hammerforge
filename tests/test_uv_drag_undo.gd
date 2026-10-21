extends GutTest
## A corner dragged on the UV Editor canvas changed the face's `custom_uvs` and
## recorded no undo step, so Ctrl+Z skipped the drag and undid the step before it
## (#1544). A drag, press to release, is now one step that undo takes back,
## including the layout it gave a face that had none. A press that moves nothing
## records none, and neither does a drag called off with right click or Escape.
##
## Through the real plugin and dock, whose undo stand-in runs real `UndoRedo`
## histories and tells the dock of each undo and redo as the editor's manager
## does.

const PluginRig = preload("res://tests/support/plugin_rig.gd")

const CANVAS := Vector2(240, 240)
const SNAP := 0.125
const EPS := 0.0001

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


## The face looking down +Z, on which U runs along X and V down Y.
func _front(brush: Node) -> int:
	for i in brush.faces.size():
		if (brush.faces[i] as FaceData).normal.is_equal_approx(Vector3.BACK):
			return i
	return -1


## The front face of brush "a" as the level holds it now. An undo puts a brush
## back from its record, which gives it new faces, so it is looked up each time.
func _face(level: Node) -> FaceData:
	var brush: Node = level.brush_system.find_brush_by_id("a")
	return brush.faces[_front(brush)]


## A level with brush "a" at the origin and its front face picked, so the UV
## Editor shows it, and an empty history.
func _level() -> Node:
	var level = await rig.make_level()
	var brush = rig.box(level, "a", Vector3.ZERO, Vector3(4, 2, 1))
	rig.box(level, "b", Vector3(10, 0, 0))
	level.toggle_face_selection(brush, _front(brush), true, false)
	_canvas().set_snap(true, SNAP)
	rig.undo().clear()
	return level


func _canvas() -> UVEditor:
	var canvas: UVEditor = rig.plugin.dock.uv_editor
	# The section it sits in is folded, and a test drives it directly.
	canvas.size = CANVAS
	return canvas


func _button(button: MouseButton, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	return event


func _escape() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event


## Where corner 0 of the face on show is on the canvas.
func _corner() -> Vector2:
	var canvas := _canvas()
	return canvas._uv_to_screen(canvas._face.shown_uvs()[0])


## Press on corner 0 and move it through `path`, points on the canvas.
func _drag(path: Array) -> void:
	var canvas := _canvas()
	canvas._gui_input(_button(MOUSE_BUTTON_LEFT, true, _corner()))
	for point in path:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		canvas._gui_input(motion)


func _release(at: Vector2 = Vector2(120, 100)) -> void:
	_canvas()._gui_input(_button(MOUSE_BUTTON_LEFT, false, at))


func _steps() -> int:
	return rig.undo().step_count()


func _assert_uvs_near(got: PackedVector2Array, want: PackedVector2Array, message: String) -> void:
	assert_eq(got.size(), want.size(), "%s: corner count" % message)
	for i in mini(got.size(), want.size()):
		assert_almost_eq(got[i].x, want[i].x, EPS, "%s: u of corner %d" % [message, i])
		assert_almost_eq(got[i].y, want[i].y, EPS, "%s: v of corner %d" % [message, i])


func _on_snap_step(value: float) -> bool:
	return absf(value / SNAP - roundf(value / SNAP)) < EPS


# ---------------------------------------------------------------------------
# One drag, one step
# ---------------------------------------------------------------------------


func test_a_drag_is_one_step_that_undo_takes_back_with_the_layout_it_made() -> void:
	var level = await _level()
	var was := _face(level).shown_uvs()
	assert_false(_face(level).has_uv_layout(), "the face starts on its projection")

	_drag([Vector2(100, 90), Vector2(110, 95), Vector2(117, 103)])
	assert_eq(_steps(), 0, "nothing is recorded while the corner is held")
	_release()

	assert_eq(_steps(), 1, "three moves and a release are one step")
	var dragged: Vector2 = _face(level).custom_uvs[0]
	assert_ne(dragged, was[0], "the corner moved")
	assert_true(
		_on_snap_step(dragged.x) and _on_snap_step(dragged.y),
		"and landed on the UV Snap step: %s" % dragged
	)

	rig.undo().press_undo()
	assert_false(_face(level).has_uv_layout(), "undo takes away the layout the drag made")
	_assert_uvs_near(_face(level).shown_uvs(), was, "undone")
	assert_eq(rig.plugin.dock._uv_active_face, _face(level), "the UV Editor shows the face undone")
	assert_eq(_canvas()._face, _face(level), "and its canvas draws it")

	rig.undo().press_redo()
	assert_true(_face(level).has_uv_layout(), "redo gives the layout back")
	assert_eq(_face(level).custom_uvs[0], dragged, "with the snapped corner")
	assert_eq(_canvas()._face, _face(level), "and the canvas draws the face redone")
	await rig.leave_level(level)


## A face with a layout of its own gets that layout back from an undo, not its
## projection.
func test_undo_of_a_drag_on_a_hand_layout_puts_that_layout_back() -> void:
	var level = await _level()
	var face := _face(level)
	face.ensure_custom_uvs()
	var laid := face.custom_uvs.duplicate()
	laid[2] += Vector2(0.25, -0.5)
	face.custom_uvs = laid.duplicate()
	_canvas().set_face(face)

	_drag([Vector2(60, 140)])
	_release()
	assert_eq(_steps(), 1, "one step")
	assert_ne(_face(level).custom_uvs[0], laid[0])

	rig.undo().press_undo()
	assert_eq(_face(level).custom_uvs, laid, "the hand layout as it was before the drag")
	await rig.leave_level(level)


## The canvas held the face it was given, and an undo hands the brush new faces,
## so a drag after an undo moved a face no brush held, and recorded nothing.
func test_a_drag_after_an_undo_moves_the_face_the_level_holds() -> void:
	var level = await _level()
	_drag([Vector2(100, 90)])
	_release()
	rig.undo().press_undo()

	_drag([Vector2(150, 60)])
	_release(Vector2(150, 60))
	assert_true(_face(level).has_uv_layout(), "the level's face took the second drag")
	assert_eq(_steps(), 1, "as the one step, the undone one gone")
	rig.undo().press_undo()
	assert_false(_face(level).has_uv_layout(), "and undo takes it back")
	await rig.leave_level(level)


# ---------------------------------------------------------------------------
# No step
# ---------------------------------------------------------------------------


func test_a_press_and_release_that_moves_nothing_records_no_step() -> void:
	var level = await _level()
	var was := _face(level).shown_uvs()

	_drag([])
	_release(_corner())
	assert_eq(_steps(), 0, "a click on a corner is no step")

	# A hand that wanders and comes back to where it began.
	var start := _corner()
	_drag([start + Vector2(30, 20), start])
	_release(start)
	assert_eq(_steps(), 0, "a corner let go where it began is no step")
	assert_false(_face(level).has_uv_layout(), "and gives the face no layout")
	_assert_uvs_near(_face(level).shown_uvs(), was, "still")
	await rig.leave_level(level)


func test_right_click_escape_or_a_lost_pointer_calls_the_drag_off() -> void:
	var level = await _level()
	var was := _face(level).shown_uvs()
	var cancels := {
		"right click": _button(MOUSE_BUTTON_RIGHT, true, Vector2(117, 103)),
		"Escape": _escape(),
		"a canceled release": _button(MOUSE_BUTTON_LEFT, false, Vector2(117, 103)),
	}
	(cancels["a canceled release"] as InputEventMouseButton).canceled = true
	for label in cancels:
		_drag([Vector2(100, 90), Vector2(117, 103)])
		assert_true(_face(level).has_uv_layout(), "%s: the corner is held away" % label)

		_canvas()._gui_input(cancels[label])
		assert_false(
			_face(level).has_uv_layout(), "%s puts the face back on its projection" % label
		)
		_assert_uvs_near(_face(level).shown_uvs(), was, label)
		assert_eq(_canvas()._drag_index, -1, "%s lets go of the corner" % label)

		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(60, 60)
		_canvas()._gui_input(motion)
		_release()
		assert_false(
			_face(level).has_uv_layout(), "%s: the button still down moves nothing" % label
		)
		assert_eq(_steps(), 0, "%s records no step" % label)
	await rig.leave_level(level)


## Ctrl+Z with the corner still held: what the press recorded may no longer
## describe the level, so the drag is called off rather than recorded over it,
## and the step undone can still be redone. The nudge is of the other brush, so
## the undo leaves the face on show where it is.
func test_an_undo_during_a_drag_calls_the_drag_off() -> void:
	var level = await _level()
	HFUndoHelper.commit(
		rig.plugin.undo_redo_manager,
		level,
		"Nudge",
		"nudge_brushes_by_id",
		[["b"], Vector3(0, 0, 2)],
		false,
		Callable(),
		"",
		false,
		["b"]
	)
	var face := _face(level)
	_drag([Vector2(100, 90)])

	rig.undo().press_undo()
	assert_eq(_face(level), face, "the undo did not touch the face on show")
	_release()
	assert_false(_face(level).has_uv_layout(), "the drag was called off")
	assert_eq(_steps(), 1, "and only the nudge is in the history")
	assert_true(rig.undo().press_redo(), "which can still be redone")
	await rig.leave_level(level)
