extends GutTest
## Create Displacement, Inset Face and sculpting each start from a face the
## mapper picks, and none of them could be reached from one (#1527).
##
## Face Select lives on the Paint tab and closes when the mapper leaves it, so
## the Build tab, where Create and Inset Face were, never had a pick to read. A
## sculpt needed Paint mode and a picked face at once, and turning Paint mode on
## closes Face Select, which clears the pick. These drive each one as a mapper
## does, from a click on the face, through the real plugin.

const PluginRig = preload("res://tests/support/plugin_rig.gd")

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func _top_face(brush: Node) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.y > 0.99:
			return i
	return -1


func _left(pressed: bool, at: Vector2) -> int:
	return rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, pressed, at))


func _show_tab(tab: Control) -> void:
	var dock = rig.plugin.dock
	dock.main_tabs.current_tab = tab.get_index()


## The Paint tab with Face Select on, and the face at `at` picked by a click.
func _pick_on_paint_tab(at: Vector2) -> void:
	var dock = rig.plugin.dock
	_show_tab(dock.paint_tab)
	dock.face_select_mode.button_pressed = true
	_left(true, at)
	_left(false, at)


## Open `section` the way a mapper does: Face Tools, then the section in it.
func _open(section: Control) -> void:
	rig.plugin.dock._face_tools_section.set_expanded(true)
	section.set_expanded(true)


## A press the mapper can make: the control is on the tab in front of them, with
## its section open.
func _assert_in_view(control: Control, label: String) -> void:
	assert_true(control.is_visible_in_tree(), "%s is in view beside Face Select" % label)


## The sculpt on a face, short enough to read in a failure.
func _sculpt_of(brush: Node, face_idx: int) -> String:
	return var_to_str(brush.faces[face_idx].displacement.to_dict()).md5_text()


func _sculpt(level: Node, top: int) -> String:
	return _sculpt_of(level.find_brush_by_id("d"), top)


func _leave(level: Node) -> void:
	var dock = rig.plugin.dock
	dock.face_select_mode.button_pressed = false
	dock._disp_section.set_expanded(false)
	dock._inset_section.set_expanded(false)
	dock._face_tools_section.set_expanded(false)
	_show_tab(dock.brush_tab)
	await rig.leave_level(level)


func test_create_displacement_works_on_the_face_just_picked() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "d", Vector3.ZERO, Vector3(16, 16, 16))
	var top := _top_face(box)
	var dock = rig.plugin.dock
	rig.undo().clear()
	_pick_on_paint_tab(rig.camera.unproject_position(Vector3(0, 8, 0)))
	assert_eq(level.face_selection, {"d": [top]}, "the click picks the top face")

	_open(dock._disp_section)
	_assert_in_view(dock._disp_create_btn, "Create")
	dock._disp_create_btn.pressed.emit()
	assert_not_null(box.faces[top].displacement, "Create makes the picked face a displacement")
	assert_eq(level.face_selection, {"d": [top]}, "and the face stays picked")
	assert_eq(rig.undo().step_count(), 1, "in one undo step")
	rig.undo().press_undo()
	assert_null(level.find_brush_by_id("d").faces[top].displacement, "which Ctrl+Z takes back")
	await _leave(level)


func test_inset_face_works_on_the_face_just_picked() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "d", Vector3.ZERO, Vector3(16, 16, 16))
	var top := _top_face(box)
	var faces_before: int = box.faces.size()
	var dock = rig.plugin.dock
	rig.undo().clear()
	_pick_on_paint_tab(rig.camera.unproject_position(Vector3(0, 8, 0)))
	assert_eq(level.face_selection, {"d": [top]}, "the click picks the top face")

	_open(dock._inset_section)
	_assert_in_view(dock._bevel_inset_btn, "Inset Face")
	dock._bevel_inset_btn.pressed.emit()
	var inset: Node = level.find_brush_by_id("d")
	assert_eq(inset.faces.size(), faces_before + 4, "the picked face is inset with a ring of four")
	assert_eq(rig.undo().step_count(), 1, "in one undo step")
	rig.undo().press_undo()
	assert_eq(level.find_brush_by_id("d").faces.size(), faces_before, "which Ctrl+Z takes back")
	await _leave(level)


## Pick, Create, then Paint mode: the pick goes with Face Select, as it always
## has, and the stroke lands on the sculpted face under the cursor.
func test_a_face_picked_and_displaced_can_then_be_sculpted() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "d", Vector3.ZERO, Vector3(16, 16, 16))
	var top := _top_face(box)
	var dock = rig.plugin.dock
	var on_top := rig.camera.unproject_position(Vector3(0, 8, 0))
	_pick_on_paint_tab(on_top)
	_open(dock._disp_section)
	dock._disp_create_btn.pressed.emit()
	assert_not_null(box.faces[top].displacement, "the picked face is a displacement")
	rig.undo().clear()

	dock.paint_mode.button_pressed = true
	assert_true(dock.is_paint_mode_enabled(), "Paint mode is on")
	assert_false(dock.is_face_select_mode_enabled(), "which closes Face Select")
	assert_true(level.face_selection.is_empty(), "and its pick with it")
	var before := _sculpt(level, top)
	_left(true, on_top)
	rig.forward(PluginRig.motion(on_top + Vector2(12, 0), MOUSE_BUTTON_MASK_LEFT))
	_left(false, on_top + Vector2(12, 0))
	var after := _sculpt(level, top)
	assert_ne(after, before, "a drag on the face sculpts it")
	assert_eq(rig.undo().step_count(), 1, "in one undo step")
	rig.undo().press_undo()
	assert_eq(_sculpt(level, top), before, "which Ctrl+Z takes back")
	dock.paint_mode.button_pressed = false
	await _leave(level)


## A stroke goes to the face it lands on. A pick nobody can see, as an undo can
## put one back with Face Select closed, does not pull the stroke onto another
## face.
func test_a_sculpt_goes_to_the_face_under_the_cursor_not_a_pick() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3(-10, 0, 0), Vector3(8, 8, 8))
	var b = rig.box(level, "b", Vector3(10, 0, 0), Vector3(8, 8, 8))
	var a_top := _top_face(a)
	var b_top := _top_face(b)
	assert_true(level.create_displacement("a", a_top, 2), "a's top is sculptable")
	assert_true(level.create_displacement("b", b_top, 2), "and so is b's")
	var dock = rig.plugin.dock
	_show_tab(dock.paint_tab)
	_open(dock._disp_section)
	level.face_selection = {"a": [a_top]}
	var a_before := _sculpt_of(a, a_top)
	var b_before := _sculpt_of(b, b_top)

	var on_b := rig.camera.unproject_position(Vector3(10, 4, 0))
	_left(true, on_b)
	_left(false, on_b)
	assert_ne(_sculpt_of(b, b_top), b_before, "b, under the cursor, takes the stroke")
	assert_eq(_sculpt_of(a, a_top), a_before, "a, only picked, does not")
	await _leave(level)


## Leaving the Paint tab still closes Face Select and drops its picks, so nothing
## picked out of sight is acted on later: back on Paint, Create has no face, and a
## press on a flat face is a paint stroke, not a sculpt.
func test_leaving_the_paint_tab_leaves_no_pick_behind() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "d", Vector3.ZERO, Vector3(16, 16, 16))
	var top := _top_face(box)
	var dock = rig.plugin.dock
	var on_top := rig.camera.unproject_position(Vector3(0, 8, 0))
	_pick_on_paint_tab(on_top)
	assert_eq(level.face_selection, {"d": [top]}, "the click picks the top face")

	_show_tab(dock.brush_tab)
	assert_false(dock.is_face_select_mode_enabled(), "the Build tab closes Face Select")
	assert_true(level.face_selection.is_empty(), "and drops the pick")

	_show_tab(dock.paint_tab)
	assert_false(dock.is_face_select_mode_enabled(), "coming back does not reopen it")
	_open(dock._disp_section)
	rig.clear_toasts()
	dock._disp_create_btn.pressed.emit()
	assert_null(box.faces[top].displacement, "so Create has no face to act on")
	assert_has(rig.toasts(), "Select a quad face first", "and says so")
	_left(true, on_top)
	_left(false, on_top)
	assert_null(box.faces[top].displacement, "and a press on the flat face sculpts nothing")
	await _leave(level)


## Sculpting is armed by the Displacement section being open. Folded away inside
## a closed Face Tools, its brush settings are out of sight, so a press on a
## sculpted face is a paint stroke, not a sculpt.
func test_a_displacement_section_folded_out_of_sight_does_not_sculpt() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "d", Vector3.ZERO, Vector3(16, 16, 16))
	var top := _top_face(box)
	assert_true(level.create_displacement("d", top, 2), "the top face is sculptable")
	var dock = rig.plugin.dock
	_show_tab(dock.paint_tab)
	assert_true(dock.is_paint_mode_enabled(), "the Paint tab turns Paint mode on")
	var on_top := rig.camera.unproject_position(Vector3(0, 8, 0))
	var before := _sculpt(level, top)

	dock._disp_section.set_expanded(true)
	dock._face_tools_section.set_expanded(false)
	assert_false(dock.is_displacement_section_open(), "Displacement is open, Face Tools is not")
	_left(true, on_top)
	_left(false, on_top)
	assert_eq(_sculpt(level, top), before, "so the press does not sculpt")

	dock._face_tools_section.set_expanded(true)
	assert_true(dock.is_displacement_section_open(), "with both open")
	_left(true, on_top)
	_left(false, on_top)
	assert_ne(_sculpt(level, top), before, "the same press sculpts")
	await _leave(level)


## Smoothing, in the UV Editor beside Rotate, puts the faces just picked in the
## group typed, as one undo step, and shows the group of the face on show (#1429).
func test_the_smoothing_box_puts_the_faces_just_picked_in_a_group() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "d", Vector3.ZERO, Vector3(16, 16, 16))
	var top := _top_face(box)
	var dock = rig.plugin.dock
	rig.undo().clear()
	_pick_on_paint_tab(rig.camera.unproject_position(Vector3(0, 8, 0)))
	assert_eq(level.face_selection, {"d": [top]}, "the click picks the top face")

	_open(dock._all_sections["UV Editor"])
	_assert_in_view(dock.uv_smoothing_spin, "Smoothing")
	assert_eq(int(dock.uv_smoothing_spin.value), 0, "a box's top shades flat")
	dock.uv_smoothing_spin.value = 2
	assert_eq(box.faces[top].smoothing_group, 2, "the picked face is in group 2")
	for i in box.faces.size():
		if i != top:
			assert_eq(box.faces[i].smoothing_group, 0, "and only the picked face")
	assert_eq(rig.undo().step_count(), 1, "in one undo step")
	rig.undo().press_undo()
	assert_eq(level.find_brush_by_id("d").faces[top].smoothing_group, 0, "which Ctrl+Z takes back")
	dock._all_sections["UV Editor"].set_expanded(false)
	await _leave(level)
