extends GutTest

## Repeat Last Command runs the last command that changed the level or the
## selection again, on the selection there is now (#1694). The palette lifts it
## to its top as "Repeat: Hollow" and lists the commands run lately under it.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginCommandsScript = preload("res://addons/hammerforge/plugin_commands.gd")
const HFPluginAdjustLast = preload("res://addons/hammerforge/plugin_adjust_last.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func before_each():
	if rig.plugin:
		rig.plugin.last_repeatable_command = ""
		rig.plugin.recent_commands.clear()


func _run(action: String) -> void:
	rig.plugin._on_hotkey_palette_action(action)


func _key(action: String) -> InputEventKey:
	var binding: Dictionary = rig.plugin._keymap.get_all_bindings()[action]
	var event := InputEventKey.new()
	event.keycode = int(binding.get("keycode", 0))
	event.ctrl_pressed = bool(binding.get("ctrl", false))
	event.shift_pressed = bool(binding.get("shift", false))
	event.alt_pressed = bool(binding.get("alt", false))
	event.pressed = true
	return event


## The thinnest side of the brushes made since `before`.
func _thinnest_new(level, before: Array) -> float:
	var thinnest := INF
	for brush in level._iter_managed_brush_nodes():
		if before.has(brush):
			continue
		for axis in 3:
			thinnest = minf(thinnest, brush.size[axis])
	return thinnest


func test_hollow_then_repeat_hollows_the_next_brush_as_thick():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	var b = rig.box(level, "b", Vector3(10, 2, 0))
	var thickness: float = rig.plugin.dock.hollow_thickness.value
	rig.plugin.dock.hollow_thickness.value = 0.5
	rig.select([a])
	_run("hollow")
	assert_eq(await rig.accept_dialogs(), 1, "Hollow asks")
	assert_eq(rig.plugin.last_repeatable_command, "hollow")
	var steps: int = rig.undo().step_count()
	var before: Array = level._iter_managed_brush_nodes()
	rig.select([b])
	rig.clear_toasts()
	_run("repeat_last_command")
	assert_true(rig.toasts().has("Repeat: Hollow (0.5 m)"), "says what it runs")
	assert_eq(await rig.accept_dialogs(), 1, "the same question as Hollow")
	assert_null(level.find_brush_by_id("b"), "the second brush is hollowed")
	assert_almost_eq(_thinnest_new(level, before), 0.5, 0.001, "with the same walls")
	assert_eq(rig.undo().step_count(), steps + 1, "one undo step")
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Hollow", "named after Hollow")
	rig.plugin.dock.hollow_thickness.value = thickness
	await rig.leave_level(level)


## Repeat Last Command runs with the dock's settings, and Adjust Last puts what it
## changed there, so the two agree with Repeat Run (#1896): after a Hollow and a
## change to 0.5 m in the Adjust panel, the next Hollow and the repeat are 0.5 m.
func test_repeat_after_adjust_last_hollows_at_the_adjusted_thickness():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await rig.make_level()
	rig.undo().clear()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	var b = rig.box(level, "b", Vector3(10, 2, 0))
	var thickness: float = rig.plugin.dock.hollow_thickness.value
	rig.plugin.dock.hollow_thickness.value = 0.25
	rig.select([a])
	_run("hollow")
	assert_eq(await rig.accept_dialogs(), 1, "Hollow asks")
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "thickness", 0.5), "adjusted")
	await rig.frame()
	assert_almost_eq(
		float(rig.plugin.dock.hollow_thickness.value), 0.5, 0.001, "the dock takes it too"
	)
	var before: Array = level._iter_managed_brush_nodes()
	rig.select([b])
	_run("repeat_last_command")
	assert_eq(await rig.accept_dialogs(), 1, "the same question as Hollow")
	assert_almost_eq(_thinnest_new(level, before), 0.5, 0.001, "hollowed at 0.5 m")
	HFPluginAdjustLast.close(rig.plugin)
	rig.plugin.dock.hollow_thickness.value = thickness
	await rig.leave_level(level)


func test_a_toggle_or_a_view_never_becomes_what_repeat_runs():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	rig.select([a])
	_run("move_to_floor")
	# Each toggle twice, so the editor is left as it was.
	for action in ["toggle_operation", "toggle_face_xray", "toggle_selection_size"]:
		_run(action)
		_run(action)
	_run("select_all")
	assert_eq(rig.plugin.last_repeatable_command, "move_to_floor")
	assert_eq(rig.plugin.recent_commands[0], "select_all", "they are still recent")
	await rig.leave_level(level)


func test_repeat_on_a_selection_the_command_refuses_says_its_refusal():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	var b = rig.box(level, "b", Vector3(4, 2, 0))
	rig.select([a, b])
	_run("merge")
	assert_eq(rig.plugin.last_repeatable_command, "merge")
	var c = rig.box(level, "c", Vector3(20, 2, 0))
	rig.select([c])
	rig.clear_toasts()
	_run("merge")
	var refusal := rig.toasts()
	assert_false(refusal.is_empty(), "fixture: Merge refuses one brush")
	rig.clear_toasts()
	_run("repeat_last_command")
	assert_eq(rig.toasts(), refusal, "Merge's own words, and nothing run")
	assert_not_null(level.find_brush_by_id("c"))
	await rig.leave_level(level)


func test_nothing_to_repeat_says_so():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await rig.make_level()
	rig.clear_toasts()
	_run("repeat_last_command")
	assert_eq(rig.toasts(), ["Nothing to repeat yet"])
	await rig.leave_level(level)


func test_a_key_counts_as_the_palette_does():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3(0, 2, 6))
	rig.select([a])
	assert_eq(rig.forward(_key("move_to_floor")), STOP)
	assert_eq(rig.plugin.last_repeatable_command, "move_to_floor", "a key is noted")
	assert_eq(rig.plugin.recent_commands, ["move_to_floor"])
	await rig.leave_level(level)


func test_the_empty_palette_lists_repeat_and_recent_commands_newest_first():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	rig.select([a])
	for action in ["move_to_floor", "snap_to_grid", "toggle_face_xray", "move_to_floor"]:
		_run(action)
	var palette = rig.plugin._hotkey_palette
	palette.update_state(HFPluginCommandsScript.build_command_state(rig.plugin, level, 0))
	palette._on_search_changed("")
	var top: Array = []
	for child in palette._list.get_children():
		if child.visible:
			top.append(child.text)
		if top.size() == 5:
			break
	assert_eq(
		top,
		["Repeat: Move to Floor", "Recent", "Move to Floor", "Toggle Face X-ray", "Snap to Grid"]
	)
	assert_false(palette._entry_of("repeat_last_command")["button"].disabled)
	palette._on_search_changed("again")
	assert_eq(palette._shown[0]["action"], "repeat_last_command", "an alias finds it")
	palette._on_search_changed("")
	await rig.leave_level(level)


func test_recent_commands_keep_eight():
	var plugin := RecentHolder.new()
	for i in 12:
		HFPluginCommandsScript.note_command(plugin, ["hollow", "clip", "merge"][i % 3])
	assert_eq(plugin.recent_commands, ["merge", "clip", "hollow"], "each once, newest first")
	for action in HFCommandRegistry.dispatched_ids():
		HFPluginCommandsScript.note_command(plugin, action)
	assert_eq(plugin.recent_commands.size(), 8)
	assert_false(plugin.recent_commands.has("repeat_last_command"), "never itself")


class RecentHolder:
	extends RefCounted
	var recent_commands: Array = []
	var last_repeatable_command := ""
