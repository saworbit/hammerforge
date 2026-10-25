extends GutTest
## Hide things by kind (#1720), on the real plugin and dock. Hiding the triggers
## over a doorway took a visgroup kept up to date by hand, and a trigger made the
## next day was not in it.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFViewFilters = preload("res://addons/hammerforge/hf_view_filters.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _trigger(level: Node, id: String, at: Vector3) -> Node:
	return (
		level
		. create_brush_from_info(
			{
				"size": Vector3(2, 2, 2),
				"center": at,
				"brush_id": id,
				"brush_entity_class": "trigger_once",
			}
		)
	)


func _row(key: String) -> CheckBox:
	return rig.plugin.dock.view_filters_box.get_node_or_null(key.replace(":", "_")) as CheckBox


func _leave(level: Node) -> void:
	level.clear_view_filters()
	await rig.leave_level(level)


func test_unticking_triggers_hides_every_trigger_and_one_made_later():
	var level = await rig.make_level()
	var wall = rig.box(level, "wall", Vector3.ZERO)
	var door_trigger = _trigger(level, "t1", Vector3(6, 1, 0))
	rig.plugin.dock._on_root_view_filters_changed()
	assert_not_null(_row("trigger"), "a row for triggers")
	assert_true(_row("trigger").button_pressed, "ticked while shown")
	_row("trigger").button_pressed = false
	assert_false(door_trigger.visible, "the trigger is hidden")
	assert_true(wall.visible, "the wall is not")
	var later = _trigger(level, "t2", Vector3(10, 1, 0))
	assert_false(later.visible, "and so is a trigger made afterwards")
	assert_true(level.is_view_filtered("trigger"))
	assert_not_null(_row("brush_entity:trigger_once"), "its class has a row of its own")
	_row("trigger").button_pressed = true
	assert_true(door_trigger.visible and later.visible, "ticked again, both show")
	await _leave(level)


func test_a_visgroup_still_decides_on_top_of_a_filter():
	var level = await rig.make_level()
	var wall = rig.box(level, "wall", Vector3.ZERO)
	level.create_visgroup("upper")
	level.add_selection_to_visgroup("upper", [wall])
	level.visgroup_system.set_visgroup_visible("upper", false)
	level.set_view_filter("trigger", true)
	assert_false(wall.visible, "the hidden visgroup keeps it hidden")
	level.clear_view_filters()
	assert_false(wall.visible, "clearing filters does not show what a visgroup hides")
	await _leave(level)


func test_a_hidden_kind_cannot_be_clicked_or_box_selected():
	var level = await rig.make_level()
	var wall = rig.box(level, "wall", Vector3.ZERO, Vector3(4, 4, 4))
	rig.plugin._hotkey_palette.action_invoked.emit("tool_select")
	level.set_view_filter("world", true)
	var at := rig.camera.unproject_position(Vector3(0, 2, 2))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, at))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, at))
	assert_false(rig.plugin.hf_selection.has(wall), "a click does not pick it")
	var from := rig.camera.unproject_position(Vector3(-6, 0, 6))
	var to := rig.camera.unproject_position(Vector3(6, 4, -6))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, from))
	rig.forward(PluginRig.motion(to, MOUSE_BUTTON_MASK_LEFT))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, to))
	assert_false(rig.plugin.hf_selection.has(wall), "nor does a box round it")
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await _leave(level)


func test_filters_are_not_saved_and_the_chip_says_so():
	var level = await rig.make_level()
	rig.box(level, "wall", Vector3.ZERO)
	var dock = rig.plugin.dock
	assert_eq(dock.view_filter_chip_text(), "", "no chip with nothing hidden")
	level.set_view_filter("decal", true)
	level.set_view_filter("entity", true)
	assert_eq(dock.view_filter_chip_text(), "Filtered: 2 kinds")
	assert_false(level.decals_node.visible, "decals are hidden")
	assert_false(var_to_str(level.capture_full_state()).contains("view_filters"))
	level.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	assert_true(level.decals_node.visible, "the scene saves them shown")
	level.notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	assert_false(level.decals_node.visible, "and they hide again after")
	dock._on_view_filters_show_all()
	assert_eq(dock.view_filter_chip_text(), "")
	assert_true(level.decals_node.visible)
	await _leave(level)


func test_a_bound_key_toggles_a_kind():
	var level = await rig.make_level()
	var door_trigger = _trigger(level, "t1", Vector3(6, 1, 0))
	var keymap = rig.plugin._keymap
	keymap.set_chord("view_filter_trigger", {"keycode": KEY_F12})
	assert_eq(rig.forward(PluginRig.key(KEY_F12)), STOP, "F12 runs it")
	assert_false(door_trigger.visible, "and hides the triggers")
	rig.forward(PluginRig.key(KEY_F12))
	assert_true(door_trigger.visible, "a second press shows them")
	keymap.clear_chord("view_filter_trigger")
	await _leave(level)


func test_bake_visible_only_ignores_a_view_filter():
	var level = await rig.make_level()
	var wall = rig.box(level, "wall", Vector3.ZERO)
	var hidden_one = rig.box(level, "hid", Vector3(8, 0, 0))
	level.create_visgroup("off")
	level.add_selection_to_visgroup("off", [hidden_one])
	level.visgroup_system.set_visgroup_visible("off", false)
	level.bake_visible_only = true
	level.set_view_filter("world", true)
	assert_false(wall.visible, "the filter hides the wall in the editor")
	assert_true(level.bake_system.brush_bakes(wall), "and the bake still takes it")
	assert_false(level.bake_system.brush_bakes(hidden_one), "a hidden visgroup still leaves out")
	level.bake_visible_only = false
	await _leave(level)


func test_a_tick_that_changes_no_row_keeps_the_same_rows():
	var level = await rig.make_level()
	_trigger(level, "t1", Vector3(6, 1, 0))
	rig.plugin.dock._on_root_view_filters_changed()
	var row := _row("trigger")
	var class_row := _row("brush_entity:trigger_once")
	row.button_pressed = false
	assert_same(_row("trigger"), row, "the row ticked is the row still there")
	assert_same(_row("brush_entity:trigger_once"), class_row, "and so is every other")
	assert_false(_row("trigger").button_pressed, "showing what was ticked")
	level.set_view_filter("trigger", false)
	assert_true(row.button_pressed, "a filter set elsewhere ticks the same row")
	assert_no_new_orphans("no rows queued for freeing (#1901)")
	await _leave(level)


func test_ticking_back_a_class_with_none_left_takes_its_row_away_from_inside_its_own_tick():
	var level = await rig.make_level()
	var trigger = _trigger(level, "t1", Vector3(6, 1, 0))
	rig.plugin.dock._on_root_view_filters_changed()
	_row("brush_entity:trigger_once").button_pressed = false
	level.delete_brushes_by_id(["t1"])
	await rig.frame()
	assert_false(is_instance_valid(trigger), "fixture: the trigger is gone")
	rig.plugin.dock._on_root_view_filters_changed()
	var row := _row("brush_entity:trigger_once")
	assert_not_null(row, "a hidden class with none left keeps its row")
	row.button_pressed = true
	assert_null(_row("brush_entity:trigger_once"), "shown again, its row goes")
	assert_true(row.is_queued_for_deletion(), "queued, since its own signal was running")
	await rig.frame()
	assert_false(is_instance_valid(row), "and freed when the frame ends")
	assert_false(level.is_view_filtered("brush_entity:trigger_once"))
	await _leave(level)
