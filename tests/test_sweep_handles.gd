extends GutTest

## The Sweep dialog's handles in the viewport (#1885): the pivot sets Radius and
## Toward, the end handle sets Angle, and the fields and handles follow each
## other.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFFaceSweep = preload("res://addons/hammerforge/hf_face_sweep.gd")
const HFPluginFaceSweep = preload("res://addons/hammerforge/plugin_face_sweep.gd")
const HFSweepBuilderScript = preload("res://addons/hammerforge/hf_sweep_builder.gd")
const HFPluginSweepHandlesScript = preload("res://addons/hammerforge/plugin_sweep_handles.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
## The picked face's middle. Along the face, right is +X and up is +Y.
const MIDDLE := Vector3(0, 0.5, 0.5)

var rig := PluginRig.new()
var _grid := 1.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


## A level with a 1 by 1 by 1 box whose +Z face, the one the rig's camera looks
## at, is picked, the grid at 1, and the Sweep dialog open on it with its
## defaults: an Arc of 90 degrees, Radius 4, Toward 0.
func _open() -> Array:
	var level = await rig.make_level()
	rig.undo().clear()
	var box = rig.box(level, "source", Vector3(0, 0.5, 0), Vector3(1, 1, 1))
	var index := -1
	for i in box.faces.size():
		if (box.global_basis * box.faces[i].normal).normalized().is_equal_approx(Vector3.BACK):
			index = i
	level.face_selection = {"source": [index]}
	_grid = rig.plugin.dock.grid_snap.value
	rig.plugin.dock.grid_snap.value = 1.0
	assert_true(HFPluginFaceSweep.open(rig.plugin, level), "fixture: the dialog opens")
	var dialogs: Array = rig.open_dialogs()
	assert_eq(dialogs.size(), 1, "fixture: one dialog")
	return [level, dialogs[0] if dialogs.size() == 1 else null]


func _close(level, dialog) -> void:
	if is_instance_valid(dialog) and dialog.visible:
		dialog.get_cancel_button().pressed.emit()
		await rig.frame()
	rig.plugin.dock.grid_snap.value = _grid
	await rig.leave_level(level)


func _handles():
	return rig.plugin._sweep_handles


func _field(dialog, label: String) -> SpinBox:
	for spin in dialog.find_children("*", "SpinBox", true, false):
		if (spin as SpinBox).accessibility_name == label:
			return spin
	return null


func _screen(world: Vector3) -> Vector2:
	return rig.camera.unproject_position(world)


## Press at `from`, move through `path`, and let go at its last point. Every
## event's answer, in order.
func _drag(from: Vector3, path: Array, release := true) -> Array:
	var out: Array = []
	out.append(rig.forward(PluginRig.motion(_screen(from))))
	out.append(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, _screen(from))))
	for point in path:
		out.append(rig.forward(PluginRig.motion(_screen(point), MOUSE_BUTTON_MASK_LEFT)))
	if release:
		out.append(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, _screen(path.back()))))
	return out


## Where an arc of Radius 4 toward 0 from the face's middle stands after
## `degrees`: it turns about +Y through (4, 0.5, 0.5), out of the face.
static func _on_arc(degrees: float) -> Vector3:
	var turn := deg_to_rad(degrees)
	return Vector3(4.0 - 4.0 * cos(turn), 0.5, 0.5 + 4.0 * sin(turn))


func test_the_pivot_stands_where_the_values_say_and_turns_about_an_axis_along_the_face():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var opened: Array = await _open()
	var level = opened[0]
	assert_true(_handles().shown(), "an Arc shows its handles")
	assert_true(_handles().pivot_point().is_equal_approx(Vector3(4, 0.5, 0.5)), "Radius 4 right")
	assert_true(_handles().axis().is_equal_approx(Vector3.UP), "turning about a line up the face")
	assert_true(_handles().end_point().is_equal_approx(_on_arc(90.0)), "and ending a quarter on")
	var pivot_mesh: Node = level.find_child("SweepPivotHandle", true, false)
	var end_mesh: Node = level.find_child("SweepEndHandle", true, false)
	assert_true(pivot_mesh != null and pivot_mesh.visible, "the pivot handle is drawn")
	assert_true(end_mesh != null and end_mesh.visible, "and so is the end handle")
	await _close(level, opened[1])


func test_dragging_the_pivot_sets_radius_and_toward_and_the_fields_follow():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var opened: Array = await _open()
	var level = opened[0]
	var dialog = opened[1]
	var radius := _field(dialog, "Radius (m)")
	var toward := _field(dialog, "Toward (degrees)")
	var answers := _drag(Vector3(4, 0.5, 0.5), [Vector3(3, 0.5, 0.5), Vector3(2, 0.5, 0.5)])
	for answer in answers.slice(1):
		assert_eq(answer, STOP, "the drag is the handle's, not the viewport's")
	assert_almost_eq(radius.value, 2.0, 0.001, "2 right of the middle is Radius 2")
	assert_almost_eq(toward.value, 0.0, 0.001, "toward 0")
	_drag(Vector3(2, 0.5, 0.5), [MIDDLE + Vector3(0, 3, 0)])
	assert_almost_eq(radius.value, 3.0, 0.001, "3 up is Radius 3")
	assert_almost_eq(toward.value, 90.0, 0.001, "toward 90")
	_drag(MIDDLE + Vector3(0, 3, 0), [MIDDLE + Vector3(3, 3, 0)])
	assert_almost_eq(radius.value, 4.0, 0.001, "a diagonal's 4.24 lands on the grid's 4")
	assert_almost_eq(toward.value, 45.0, 0.001, "toward 45")
	var expected := MIDDLE + Vector3(1, 1, 0).normalized() * 4.0
	assert_true(_handles().pivot_point().is_equal_approx(expected), "and the handle stands there")
	# A quarter turn about that pivot ends 4 out of the face, as far right as up.
	var values: Dictionary = HFPluginFaceSweep.DEFAULTS.duplicate()
	values.merge({"radius": radius.value, "toward": toward.value}, true)
	var frames: Array = HFPluginFaceSweep.plan(HFPluginFaceSweep.section(level), values)["frames"]
	var reached: Vector3 = (frames.back() as Transform3D).origin - MIDDLE
	assert_almost_eq(reached.x, reached.y, 0.001, "the run turns along the diagonal")
	assert_almost_eq(reached.x, 4.0 * sqrt(0.5), 0.001)
	assert_almost_eq(reached.z, 4.0, 0.001, "out of the face")
	await _close(level, dialog)


func test_the_end_handle_turns_about_the_pivot_in_the_rotate_snaps_steps():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var opened: Array = await _open()
	var level = opened[0]
	var dialog = opened[1]
	var angle := _field(dialog, "Angle (degrees)")
	assert_almost_eq(float(level.rotate_snap_degrees), 15.0, 0.001, "fixture: 15 degree steps")
	_drag(_on_arc(90.0), [_on_arc(70.0), _on_arc(50.0)])
	assert_almost_eq(angle.value, 45.0, 0.001, "50 degrees lands on 45")
	_drag(_on_arc(45.0), [_on_arc(70.0)])
	assert_almost_eq(angle.value, 75.0, 0.001, "70 lands on 75")
	assert_true(_handles().end_point().is_equal_approx(_on_arc(75.0)), "the handle follows")
	await _close(level, dialog)


func test_the_end_handle_turns_on_past_a_half_turn():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var opened: Array = await _open()
	var level = opened[0]
	var dialog = opened[1]
	_drag(_on_arc(90.0), [_on_arc(135.0), _on_arc(180.0), _on_arc(225.0), _on_arc(270.0)])
	assert_almost_eq(_field(dialog, "Angle (degrees)").value, 270.0, 0.001, "three quarters")
	await _close(level, dialog)


func test_a_right_click_mid_drag_puts_the_values_back():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var opened: Array = await _open()
	var level = opened[0]
	var dialog = opened[1]
	_drag(Vector3(4, 0.5, 0.5), [Vector3(2, 0.5, 0.5)], false)
	assert_almost_eq(_field(dialog, "Radius (m)").value, 2.0, 0.001, "fixture: mid drag")
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true, _screen(Vector3.ZERO))), STOP)
	assert_almost_eq(_field(dialog, "Radius (m)").value, 4.0, 0.001, "Radius is back")
	assert_false(_handles().dragging(), "and the drag is over")
	var release := PluginRig.click(MOUSE_BUTTON_LEFT, false, _screen(Vector3(2, 0.5, 0.5)))
	assert_eq(rig.forward(release), STOP, "the release that follows is not a click")
	assert_true(_handles().pivot_point().is_equal_approx(Vector3(4, 0.5, 0.5)), "nor moves it")
	await _close(level, dialog)


func test_escape_mid_drag_puts_the_values_back():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var opened: Array = await _open()
	var level = opened[0]
	var dialog = opened[1]
	_drag(_on_arc(90.0), [_on_arc(30.0)], false)
	assert_almost_eq(_field(dialog, "Angle (degrees)").value, 30.0, 0.001, "fixture: mid drag")
	rig.forward(PluginRig.key(KEY_ESCAPE))
	assert_almost_eq(_field(dialog, "Angle (degrees)").value, 90.0, 0.001, "Angle is back")
	assert_false(_handles().dragging())
	assert_true(dialog.visible, "and the dialog stays open")
	await _close(level, dialog)


func test_typing_a_value_moves_the_handle():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var opened: Array = await _open()
	var level = opened[0]
	var dialog = opened[1]
	_field(dialog, "Radius (m)").value = 6.0
	assert_true(_handles().pivot_point().is_equal_approx(Vector3(6, 0.5, 0.5)), "Radius 6")
	_field(dialog, "Toward (degrees)").value = 90.0
	assert_true(_handles().pivot_point().is_equal_approx(MIDDLE + Vector3(0, 6, 0)), "toward 90")
	_field(dialog, "Angle (degrees)").value = 180.0
	assert_true(
		_handles().end_point().is_equal_approx(MIDDLE + Vector3(0, 12, 0)),
		"half a turn ends on the far side of the pivot"
	)
	await _close(level, dialog)


func test_off_an_arc_the_handles_go_and_leave_the_pointer_alone():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var opened: Array = await _open()
	var level = opened[0]
	var dialog = opened[1]
	var path_pick: OptionButton = dialog.find_children("*", "OptionButton", true, false)[0]
	path_pick.select(HFFaceSweep.Path.STRAIGHT)
	path_pick.item_selected.emit(HFFaceSweep.Path.STRAIGHT)
	assert_false(_handles().shown(), "a straight run has no bend to set")
	assert_false(level.find_child("SweepPivotHandle", true, false).visible, "nor a handle drawn")
	var press := PluginRig.click(MOUSE_BUTTON_LEFT, true, _screen(Vector3(4, 0.5, 0.5)))
	assert_eq(
		_handles().handle_input(rig.plugin, press, level, rig.camera, press.position),
		PASS,
		"a press where the pivot stood is the viewport's"
	)
	await _close(level, dialog)


func test_ok_makes_the_sweep_the_handles_set_and_lets_go_of_them():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var opened: Array = await _open()
	var level = opened[0]
	_drag(Vector3(4, 0.5, 0.5), [Vector3(2, 0.5, 0.5)])
	assert_eq(await rig.accept_dialogs(), 1)
	var records: Array = level.generator_system.generators.values().filter(
		func(record): return record.type == HFGeneratorSystemScript.TYPE_SWEEP
	)
	assert_eq(records.size(), 1, "OK makes the sweep")
	if records.size() == 1:
		assert_almost_eq(float(records[0].settings["radius"]), 2.0, 0.001, "with Radius 2")
	assert_false(_handles().active, "and the handles are gone with the dialog")
	assert_null(level.find_child("SweepPivotHandle", true, false))
	await _close(level, null)


func test_cancel_lets_go_of_the_handles():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var opened: Array = await _open()
	var level = opened[0]
	opened[1].get_cancel_button().pressed.emit()
	await rig.frame()
	assert_false(_handles().active)
	var press := PluginRig.click(MOUSE_BUTTON_LEFT, true, _screen(Vector3(4, 0.5, 0.5)))
	assert_eq(_handles().handle_input(rig.plugin, press, level, rig.camera, press.position), PASS)
	await _close(level, null)


func test_a_pivot_lands_on_grid_steps_and_angle_steps_unless_the_snap_is_off():
	var settings := HFSweepBuilderScript.default_settings()
	var snapped := HFSweepBuilderScript.pivot_settings(settings, Vector3(3, 2, 0), 1.0, 15.0)
	assert_almost_eq(float(snapped["radius"]), 4.0, 0.0001, "3.61 on a grid of 1 is 4")
	assert_almost_eq(float(snapped["toward"]), 30.0, 0.0001, "33.7 degrees in 15s is 30")
	var free := HFSweepBuilderScript.pivot_settings(settings, Vector3(3, 2, 0), 0.0, 0.0)
	assert_almost_eq(float(free["radius"]), 3.61, 0.0001, "free, to the field's hundredths")
	assert_almost_eq(float(free["toward"]), 34.0, 0.0001, "and whole degrees")
	var below := HFSweepBuilderScript.pivot_settings(settings, Vector3(0, -2, 0), 1.0, 15.0)
	assert_almost_eq(float(below["toward"]), 270.0, 0.0001, "down is 270, not -90")
	var close := HFSweepBuilderScript.pivot_settings(settings, Vector3(0.2, 0, 0), 1.0, 15.0)
	assert_almost_eq(float(close["radius"]), 1.0, 0.0001, "never nearer than one step")


func test_the_structure_fields_keep_a_value_a_free_drag_gave():
	# A Toward of 34 in a field that stepped in 15s read back as 30 on the next
	# edit of any field.
	var low := {}
	for field in HFSweepBuilderScript.settings_schema():
		low[field["key"]] = field
	for value in [34.0, 33.0, 1.0]:
		assert_almost_eq(fmod(value, float(low["toward"]["step"])), 0.0, 0.0001)
	for value in [3.61, 0.25, 4.24]:
		var steps: float = (value - float(low["radius"]["min"])) / float(low["radius"]["step"])
		assert_almost_eq(steps, roundf(steps), 0.0001, "Radius %s is on a step" % value)
