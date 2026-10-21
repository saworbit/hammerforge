extends GutTest

## The UV editor panel maps a face onto its canvas.
##
## A HammerForge UV is a world coordinate, not a 0..1 fraction, so a 64 unit box
## face spans 64. The panel treated a UV as a fraction of the control: every
## point landed far outside it, nothing was drawn and nothing was selectable, and
## the one interaction it had clamped a dragged point into 0..1 and left the
## face's UV quad no longer a quad.

const UVEditorScript = preload("res://addons/hammerforge/uv_editor.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")

const CANVAS := Vector2(240, 240)

var editor: Control


func before_each():
	editor = UVEditorScript.new()
	add_child_autoqfree(editor)
	editor.size = CANVAS


## One face of a 64 unit box, UVs projected the way FaceData projects them.
func _box_face(span: float = 64.0) -> FaceData:
	var face := FaceDataScript.new()
	face.normal = Vector3.BACK
	face.local_verts = PackedVector3Array(
		[
			Vector3(0, 0, 0),
			Vector3(span, 0, 0),
			Vector3(span, span, 0),
			Vector3(0, span, 0),
		]
	)
	face.ensure_custom_uvs()
	return face


func _inside_control(point: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 and point.x <= CANVAS.x and point.y <= CANVAS.y


func test_every_point_of_a_box_face_lands_inside_the_control():
	var face := _box_face()
	editor.set_face(face)

	for uv in face.custom_uvs:
		var point: Vector2 = editor._uv_to_screen(uv)
		assert_true(_inside_control(point), "UV %s drew at %s, outside the panel" % [uv, point])


func test_a_face_at_any_size_fills_the_same_canvas():
	for span in [8.0, 64.0, 512.0]:
		var face := _box_face(span)
		editor.set_face(face)
		for uv in face.custom_uvs:
			assert_true(
				_inside_control(editor._uv_to_screen(uv)),
				"a %s unit face has to fit the canvas too" % span
			)


func test_every_point_of_a_box_face_can_be_reached():
	var face := _box_face()
	editor.set_face(face)

	for i in face.custom_uvs.size():
		var point: Vector2 = editor._uv_to_screen(face.custom_uvs[i])
		assert_eq(
			editor._find_nearest_uv_index(point),
			i,
			"point %d was not selectable at %s" % [i, point]
		)


func test_screen_and_uv_are_inverses():
	var face := _box_face()
	editor.set_face(face)

	for uv in face.custom_uvs:
		var round_tripped: Vector2 = editor._screen_to_uv(editor._uv_to_screen(uv))
		assert_almost_eq(round_tripped.x, uv.x, 0.01, "u did not survive the round trip")
		assert_almost_eq(round_tripped.y, uv.y, 0.01, "v did not survive the round trip")


func test_a_drag_produces_the_uv_the_cursor_is_over():
	var face := _box_face()
	editor.set_face(face)
	var target := Vector2(120, 120)
	var expected: Vector2 = editor._screen_to_uv(target)
	editor._drag_index = 0

	var motion := InputEventMouseMotion.new()
	motion.position = target
	editor._gui_input(motion)

	assert_almost_eq(face.custom_uvs[0].x, expected.x, 0.01)
	assert_almost_eq(face.custom_uvs[0].y, expected.y, 0.01)


## The old clamp collapsed a 32 unit UV into 0..1, which moved one corner 45 UV
## units away from the other three and left the quad bent.
func test_a_drag_keeps_the_point_in_the_face_s_own_range():
	var face := _box_face()
	editor.set_face(face)
	editor._drag_index = 0

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(120, 120)
	editor._gui_input(motion)

	assert_gt(face.custom_uvs[0].x, 1.0, "a world scale UV does not belong in 0..1")
	assert_lt(face.custom_uvs[0].x, 64.0)


func test_a_drag_outside_the_control_is_held_to_the_canvas():
	var face := _box_face()
	editor.set_face(face)
	editor._drag_index = 0

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(-4000, 9000)
	editor._gui_input(motion)

	assert_true(
		_inside_control(editor._uv_to_screen(face.custom_uvs[0])),
		"a point dragged off the panel still has to be on it"
	)


## A CYLINDRICAL projection, or any face with a zero UV span, would otherwise be
## a division by zero.
func test_a_face_with_no_span_in_one_axis_still_maps():
	var face := FaceDataScript.new()
	face.normal = Vector3.UP
	face.custom_uvs = PackedVector2Array(
		[Vector2(4, 8), Vector2(4, 8), Vector2(4, 8), Vector2(4, 8)]
	)
	face.local_verts = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])

	editor.set_face(face)

	for uv in face.custom_uvs:
		var point: Vector2 = editor._uv_to_screen(uv)
		assert_true(is_finite(point.x) and is_finite(point.y), "degenerate bounds divided by zero")
		assert_true(_inside_control(point))


func test_no_face_is_not_a_crash():
	editor.set_face(null)
	assert_true(is_finite(editor._uv_to_screen(Vector2.ZERO).x))


func _left_button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = at
	return button


## Showing a face leaves it on its projection, and only a dragged corner gives it
## UVs of its own (#1539). A face given them for being shown kept them through
## every typed value and Justify after, so the face and its boxes stopped agreeing.
func test_a_face_takes_a_layout_from_a_drag_and_not_from_being_shown():
	var face := _box_face()
	face.custom_uvs = PackedVector2Array()
	editor.set_face(face)
	assert_false(face.has_uv_layout(), "on show, and still drawn from its projection")
	var shown := face.shown_uvs()
	var corner: Vector2 = editor._uv_to_screen(shown[0])
	assert_true(_inside_control(corner), "the projection is what the canvas shows")
	assert_eq(editor._find_nearest_uv_index(corner), 0, "and its corners can be grabbed")

	editor._gui_input(_left_button(corner, true))
	editor._gui_input(_left_button(corner, false))
	assert_false(face.has_uv_layout(), "a click on a corner is not a drag")

	editor._gui_input(_left_button(corner, true))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(120, 120)
	editor._gui_input(motion)
	assert_true(face.has_uv_layout(), "a drag gives the face a layout of its own")
	assert_ne(face.custom_uvs[0], shown[0], "with the dragged corner moved")
	for i in range(1, shown.size()):
		assert_eq(face.custom_uvs[i], shown[i], "and corner %d where it was" % i)


# ---------------------------------------------------------------------------
# UV Snap (#1445)
#
# A free drag lands on whatever float is under the cursor, so two corners meant
# to share a U value ended a few thousandths apart: a slanted edge on a trim
# texture. A drag now lands on the nearest multiple of the step, Ctrl places it
# freely, and a grid at the step is drawn behind the outline.
# ---------------------------------------------------------------------------


## A face whose UVs are the unit square, so the canvas shows 0..1 on both axes.
func _unit_face() -> FaceData:
	var face := FaceDataScript.new()
	face.normal = Vector3.BACK
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]
	)
	face.custom_uvs = PackedVector2Array(
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	)
	return face


func _drag_corner_to(uv: Vector2, ctrl: bool = false) -> void:
	editor._drag_index = 0
	var motion := InputEventMouseMotion.new()
	motion.position = editor._uv_to_screen(uv)
	motion.ctrl_pressed = ctrl
	editor._gui_input(motion)


func test_snapping_is_on_at_an_eighth_by_default():
	assert_true(editor.snap_enabled)
	assert_eq(editor.snap_step, 0.125)
	assert_eq(UVEditorScript.SNAP_PRESETS.size(), UVEditorScript.SNAP_PRESET_LABELS.size())


func test_a_drag_lands_on_the_nearest_step():
	var face := _unit_face()
	editor.set_face(face)
	editor.set_snap(true, 0.125)

	_drag_corner_to(Vector2(0.37, 0.61))

	assert_almost_eq(face.custom_uvs[0].x, 0.375, 0.000001)
	assert_almost_eq(face.custom_uvs[0].y, 0.625, 0.000001)


func test_ctrl_places_the_corner_freely():
	var face := _unit_face()
	editor.set_face(face)
	editor.set_snap(true, 0.125)

	_drag_corner_to(Vector2(0.37, 0.61), true)

	assert_almost_eq(face.custom_uvs[0].x, 0.37, 0.001, "the cursor's own value")
	assert_almost_eq(face.custom_uvs[0].y, 0.61, 0.001)


func test_with_snapping_off_a_drag_writes_the_cursor_value():
	var face := _unit_face()
	editor.set_face(face)
	editor.set_snap(false, 0.125)

	_drag_corner_to(Vector2(0.37, 0.61))

	assert_almost_eq(face.custom_uvs[0].x, 0.37, 0.001)
	assert_almost_eq(face.custom_uvs[0].y, 0.61, 0.001)


## The drag is held to the canvas, and so is where it snaps to. The nearest
## multiple past the edge gives way to the one inside it, and an axis with none
## inside keeps the cursor's value.
func test_a_snap_never_takes_a_corner_off_the_canvas():
	var face := _unit_face()
	face.custom_uvs = PackedVector2Array(
		[Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.9, 0.4), Vector2(0.1, 0.4)]
	)
	editor.set_face(face)
	editor.set_snap(true, 0.25)

	_drag_corner_to(Vector2(0.9, 0.35))
	assert_almost_eq(face.custom_uvs[0].x, 0.75, 0.000001, "1.0 is off the canvas, 0.75 is not")
	assert_almost_eq(face.custom_uvs[0].y, 0.25, 0.000001)

	editor.set_snap(true, 1.0)
	_drag_corner_to(Vector2(0.5, 0.3))
	assert_almost_eq(face.custom_uvs[0].y, 0.3, 0.001, "no whole repeat between 0.1 and 0.4")
	assert_almost_eq(face.custom_uvs[0].x, 0.5, 0.001)


func _ats(lines: Array) -> Array:
	var out: Array = []
	for line in lines:
		out.append(snappedf(line["at"], 0.000001))
	return out


func _units(lines: Array) -> Array:
	var out: Array = []
	for line in lines:
		if line["unit"]:
			out.append(snappedf(line["at"], 0.000001))
	return out


func test_grid_lines_fall_on_the_step_and_whole_repeats_are_marked():
	editor.set_face(_unit_face())
	editor.set_snap(true, 0.125)
	var expected: Array = []
	for i in 9:
		expected.append(i * 0.125)
	for axis in [0, 1]:
		var lines: Array = editor._grid_lines(axis)
		assert_eq(_ats(lines), expected, "a line every eighth on axis %d" % axis)
		assert_eq(_units(lines), [0.0, 1.0], "the whole repeats are the strong ones")


func _pixel_gaps(axis: int) -> Array:
	var gaps: Array = []
	var lines: Array = editor._grid_lines(axis)
	for i in range(1, lines.size()):
		var a: Vector2 = editor._uv_to_screen(Vector2(lines[i - 1]["at"], lines[i - 1]["at"]))
		var b: Vector2 = editor._uv_to_screen(Vector2(lines[i]["at"], lines[i]["at"]))
		gaps.append(absf(b[axis] - a[axis]))
	return gaps


func test_lines_closer_than_four_pixels_are_left_out():
	editor.set_snap(true, 0.125)
	# 216 pixels of canvas: an eighth of an 8 unit face is 3.4 pixels, a whole
	# repeat 27, so only the repeats are drawn.
	editor.set_face(_box_face(8.0))
	var lines: Array = editor._grid_lines(0)
	assert_eq(lines.size(), 9, "the eight repeats' edges")
	assert_eq(_units(lines).size(), lines.size(), "and nothing between them")
	for gap in _pixel_gaps(0):
		assert_gte(gap, UVEditorScript.MIN_GRID_SPACING)

	# A 64 unit face has its repeats 3.4 pixels apart as well: no grid at all.
	editor.set_face(_box_face(64.0))
	assert_eq(editor._grid_lines(0), [], "a large face is not a grey block")
	assert_eq(editor._grid_lines(1), [])

	# Close enough to see, every line at the step is drawn.
	editor.set_face(_box_face(2.0))
	for gap in _pixel_gaps(0):
		assert_gte(gap, UVEditorScript.MIN_GRID_SPACING)
	assert_eq(editor._grid_lines(0).size(), 17)


func test_no_grid_while_snapping_is_off():
	editor.set_face(_unit_face())
	editor.set_snap(false, 0.125)
	assert_eq(editor._grid_lines(0), [])
	assert_eq(editor._grid_lines(1), [])


func _quiet_prefs() -> HFUserPrefs:
	var quiet := HFUserPrefsType.new()
	quiet.persistence_enabled = false
	quiet.data = HFUserPrefsType._defaults()
	quiet.data["show_welcome"] = false
	return quiet


func _dock_with(prefs: HFUserPrefs) -> Node:
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.set_user_prefs(prefs)
	return dock


func test_the_step_and_the_checkbox_survive_a_restart():
	var prefs := _quiet_prefs()
	var dock := _dock_with(prefs)
	assert_true(dock.uv_snap_check.button_pressed, "on by default")
	assert_eq(dock.uv_snap_step_spin.value, 0.125)

	dock.uv_snap_check.button_pressed = false
	assert_false(dock.uv_editor.snap_enabled, "the checkbox reaches the canvas")
	dock.uv_snap_preset_opt.select(0)
	dock.uv_snap_preset_opt.item_selected.emit(0)
	assert_eq(dock.uv_editor.snap_step, 0.03125, "a preset sets the step")
	assert_eq(dock.uv_snap_step_spin.value, 0.03125, "and shows it unrounded")
	dock.uv_snap_step_spin.value = 0.2
	assert_eq(dock.uv_editor.snap_step, 0.2, "a typed step")
	assert_eq(dock.uv_snap_preset_opt.selected, -1, "which is no preset")

	# A restart reads the file back through the schema.
	var reread := HFUserPrefsType.new()
	reread.persistence_enabled = false
	reread.data = HFUserPrefsType._validated(JSON.parse_string(JSON.stringify(prefs.data)))
	var next_dock := _dock_with(reread)
	assert_false(next_dock.uv_snap_check.button_pressed)
	assert_false(next_dock.uv_editor.snap_enabled)
	assert_almost_eq(next_dock.uv_snap_step_spin.value, 0.2, 0.000001)
	assert_almost_eq(next_dock.uv_editor.snap_step, 0.2, 0.000001)


func test_an_unusable_saved_step_is_not_used():
	var loaded := HFUserPrefsType._validated({"uv_snap_step": 0.0, "uv_snap_enabled": "no"})
	assert_almost_eq(float(loaded["uv_snap_step"]), 0.001, 0.000001, "a step of 0 snaps nothing")
	assert_eq(loaded["uv_snap_enabled"], true, "a value that is not a switch falls back to on")
