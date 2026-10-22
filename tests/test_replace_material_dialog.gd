extends GutTest

## Replace Material's dialog (#1726), opened from the dock as the palette, the
## Material Library button and the browser's right-click menu open it.

const PluginRig = preload("res://tests/support/plugin_rig.gd")

const GREY := 1
const PLASTER := 2

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func _dock():
	return rig.plugin.dock


func _dialog():
	return _dock()._replace_material_dialog


func _close_dialog() -> void:
	if _dialog() and _dialog().visible:
		_dialog().hide()


## a wears grey on every face, b on three.
func _level() -> Node:
	var level = await rig.make_level()
	level.add_prototype_materials()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(8, 0, 0))
	for face in a.faces:
		face.material_idx = GREY
	for i in 3:
		b.faces[i].material_idx = GREY
	return level


func _pick_with(slot: int) -> void:
	var row: int = _dialog()._with_slots.find(slot)
	_dialog().with_list.select(row)
	_dialog().with_list.item_selected.emit(row)


func test_the_dialog_counts_and_marks_the_faces_then_replaces_them_as_one_step():
	var level = await _level()
	_dock().open_replace_material(GREY)
	assert_true(_dialog().visible, "open")
	assert_eq(_dialog().from_slot(), GREY, "finding the slot it was opened on")
	_pick_with(PLASTER)
	assert_eq(_dialog().preview_label.text, "Changes 9 faces on 2 brushes.")
	assert_eq(level.face_selection, {"a": [0, 1, 2, 3, 4, 5], "b": [0, 1, 2]}, "marked")
	var steps: int = rig.undo().step_count()
	_dialog().get_ok_button().pressed.emit()
	await rig.frame()
	assert_eq(rig.undo().step_count(), steps + 1, "one step")
	var a = level.find_brush_by_id("a")
	assert_eq(a.faces[0].material_idx, PLASTER)
	assert_eq(level.face_selection, {"a": [0, 1, 2, 3, 4, 5], "b": [0, 1, 2]}, "picked after")
	assert_true(rig.undo().press_undo(), "fixture: a step to undo")
	await rig.frame()
	a = level.find_brush_by_id("a")
	assert_eq(a.faces[0].material_idx, GREY, "and one undo puts it back")
	_close_dialog()
	await rig.leave_level(level)


func test_cancel_puts_the_face_selection_back_and_changes_nothing():
	var level = await _level()
	level.toggle_face_selection(level.find_brush_by_id("b"), 5, true, false)
	var before: Dictionary = level.face_selection.duplicate(true)
	_dock().open_replace_material(GREY)
	_pick_with(PLASTER)
	assert_ne(level.face_selection, before, "fixture: the preview marked other faces")
	_dialog().canceled.emit()
	assert_eq(level.face_selection, before, "back as it was")
	assert_eq(level.find_brush_by_id("a").faces[0].material_idx, GREY, "and nothing replaced")
	_close_dialog()
	await rig.leave_level(level)


func test_a_material_cannot_be_replaced_with_itself():
	var level = await _level()
	_dock().open_replace_material(GREY)
	_pick_with(GREY)
	assert_true(_dialog().get_ok_button().disabled, "Replace is off")
	var steps: int = rig.undo().step_count()
	# As the sweeps press it: the signal, past the disabled button.
	_dialog().get_ok_button().pressed.emit()
	await rig.frame()
	assert_eq(rig.undo().step_count(), steps, "and pressing it anyway adds no step")
	_close_dialog()
	await rig.leave_level(level)


func test_the_scope_starts_on_the_selection_when_there_is_one():
	var level = await _level()
	rig.select([level.find_brush_by_id("b")])
	await rig.frame()
	_dock().open_replace_material(GREY)
	_pick_with(PLASTER)
	assert_eq(_dialog().preview_label.text, "Changes 3 faces on 1 brush.", "b alone")
	_dialog().get_ok_button().pressed.emit()
	await rig.frame()
	assert_eq(level.find_brush_by_id("a").faces[0].material_idx, GREY, "a not selected")
	assert_eq(level.find_brush_by_id("b").faces[0].material_idx, PLASTER)
	rig.select([])
	_close_dialog()
	await rig.leave_level(level)


func test_the_browser_menu_opens_it_finding_the_material_clicked():
	var level = await _level()
	_dock()._material_context_index = GREY
	_dock()._on_material_context_action(6)
	assert_true(_dialog().visible)
	assert_eq(_dialog().from_slot(), GREY)
	_close_dialog()
	await rig.leave_level(level)
