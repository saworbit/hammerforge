extends GutTest
## Intersect through the real plugin (#1426). Ctrl+Shift+I asks the same check the
## bridge asks before anything is shown, so brushes that share nothing say why and
## leave no step. Otherwise the brush that would be kept is shown in Carve's green
## and the press asks first; OK commits one step, and one Ctrl+Z takes it back and
## brings every source back under its own id.

const PluginRig = preload("res://tests/support/plugin_rig.gd")

var rig := PluginRig.new()
var said: Array = []


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _showing(preview: Object) -> bool:
	var container: Node3D = preview._preview_container
	return is_instance_valid(container) and container.visible


func _ids(level: Node) -> Array:
	var out: Array = []
	for child in level.draft_brushes_node.get_children():
		out.append(str(child.brush_id))
	out.sort()
	return out


func _enter() -> Node:
	var level = await rig.make_level()
	said = []
	level.user_message.connect(func(text, _level): said.append(text))
	rig.undo().clear()
	return level


func _leave(level: Node) -> void:
	rig.undo().clear()
	await rig.leave_level(level)


func test_the_key_shows_what_is_kept_asks_and_one_undo_brings_every_source_back():
	assert_not_null(rig.plugin, rig.error())
	var level = await _enter()
	var undo = rig.undo()
	var a = rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	var b = rig.box(level, "b", Vector3(4, 4, 4), Vector3(8, 8, 8))
	var c = rig.box(level, "c", Vector3(2, 2, 2), Vector3(8, 8, 8))
	rig.select([a, b, c])

	assert_eq(rig.forward(PluginRig.key_for("intersect")), EditorPlugin.AFTER_GUI_INPUT_STOP)
	var dialogs: Array = rig.open_dialogs()
	assert_eq(dialogs.size(), 1, "the intersect is asked about")
	if dialogs.size() == 1:
		assert_string_contains(dialogs[0].dialog_text, "3 brushes share")
	assert_true(_showing(level.carve_preview), "with the brush kept on show in green")
	assert_eq(level.carve_preview._active_count, 1, "one brush")
	assert_eq(_ids(level), ["a", "b", "c"], "and nothing cut yet")

	assert_eq(await rig.accept_dialogs(), 1)
	assert_false(_showing(level.carve_preview), "OK puts the preview away")
	var kept := _ids(level)
	assert_eq(kept.size(), 1, "OK keeps one brush")
	assert_false(kept.has("a") or kept.has("b") or kept.has("c"), "in place of the three")
	assert_eq(undo.step_count(), 1, "as one step")
	assert_eq(undo.scene_history.get_current_action_name(), "Intersect")
	assert_eq(said, [], "and nothing was refused")

	assert_true(undo.press_undo(), "one Ctrl+Z")
	await rig.frame()
	assert_eq(_ids(level), ["a", "b", "c"], "brings every source back under its id")
	for pair in [["a", Vector3.ZERO], ["b", Vector3(4, 4, 4)], ["c", Vector3(2, 2, 2)]]:
		var brush = level.find_brush_by_id(pair[0])
		if brush:
			assert_almost_eq(brush.global_position, pair[1], Vector3(0.001, 0.001, 0.001))
	assert_true(undo.press_redo(), "Ctrl+Shift+Z")
	await rig.frame()
	assert_eq(_ids(level), kept, "puts back the same brush")
	await _leave(level)


func test_brushes_that_share_nothing_say_so_without_asking():
	var level = await _enter()
	var a = rig.box(level, "a", Vector3.ZERO)
	var far = rig.box(level, "far", Vector3(50, 0, 0))
	rig.select([a, far])
	var before := var_to_str(level.capture_state())

	assert_true(rig.plugin._intersect_selected(level), "the press is handled")
	assert_eq(rig.open_dialogs().size(), 0, "nothing is asked")
	assert_false(_showing(level.carve_preview), "nothing is shown")
	assert_eq(said, [level.can_intersect_brushes(["a", "far"]).user_text()], "the reason is given")
	assert_eq(rig.undo().step_count(), 0, "no step")
	assert_eq(var_to_str(level.capture_state()), before, "and nothing in the level changed")
	await _leave(level)


func test_cancel_puts_the_preview_away_and_changes_nothing():
	var level = await _enter()
	var a = rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	var b = rig.box(level, "b", Vector3(4, 4, 4), Vector3(8, 8, 8))
	rig.select([a, b])
	var before := var_to_str(level.capture_state())
	rig.plugin._intersect_selected(level)
	var dialogs: Array = rig.open_dialogs()
	assert_eq(dialogs.size(), 1)
	if dialogs.size() == 1:
		dialogs[0].get_cancel_button().pressed.emit()
	await rig.frame()
	assert_false(_showing(level.carve_preview), "Cancel puts the preview away")
	assert_eq(rig.undo().step_count(), 0, "no step")
	assert_eq(var_to_str(level.capture_state()), before, "and nothing changed")
	await _leave(level)


## The first brush selected is the one cut down, so what is kept is a piece of it.
func test_the_first_brush_selected_is_the_one_kept():
	var level = await _enter()
	var a = rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	var b = rig.box(level, "b", Vector3(4, 4, 4), Vector3(8, 8, 8))
	a.set_meta("visgroups", PackedStringArray(["walls"]))
	b.set_meta("visgroups", PackedStringArray(["props"]))
	rig.select([b, a])
	rig.plugin._intersect_selected(level)
	assert_eq(await rig.accept_dialogs(), 1)
	var left: Array = level.draft_brushes_node.get_children()
	assert_eq(left.size(), 1)
	if left.size() == 1:
		assert_eq(Array(left[0].get_meta("visgroups", PackedStringArray())), ["props"])
	await _leave(level)
