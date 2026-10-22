extends GutTest

const HFPluginInputRouter = preload("res://addons/hammerforge/plugin_input_router.gd")
const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self)


func after_all():
	await rig.take_down()


func test_router_passes_on_null_inputs():
	assert_eq(
		HFPluginInputRouter.handle_keyboard(null, null, null, 0, false),
		EditorPlugin.AFTER_GUI_INPUT_PASS
	)


## A key over the viewport reaches the router through the plugin: ] doubles the
## grid, [ halves it, and both are consumed.
func test_plugin_wrapper_delegates_to_router():
	assert_not_null(rig.plugin, rig.error())
	var level = await rig.make_level()
	var dock = rig.plugin.dock
	var grid: float = dock.get_grid_snap()
	assert_eq(rig.forward(PluginRig.key_for("grid_increase")), STOP, "] is consumed")
	assert_eq(dock.get_grid_snap(), grid * 2.0, "and doubles the grid")
	assert_eq(rig.forward(PluginRig.key_for("grid_decrease")), STOP)
	assert_eq(dock.get_grid_snap(), grid, "[ halves it again")
	await rig.leave_level(level)


func test_the_guards_stay_in_the_router():
	# A grep on purpose: it keeps plugin.gd's keyboard callback thin, a boundary
	# the behaviour around it cannot see.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var start := source.find("func _handle_keyboard_input")
	var finish := source.find("func has_cancelable_rmb_gesture", start)
	var block := source.substr(start, finish - start)
	assert_false(block.contains("delete_guard"), "Guards live in the router, not the wrapper")


## An arrow key nudges only what HammerForge owns. A Godot selection gets the key
## back untouched; a mixed one is refused and the key consumed.
func test_router_keeps_nudge_ownership_guard():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO)
	var lamp = rig.native_node()
	rig.select([lamp])
	assert_eq(rig.forward(PluginRig.key(KEY_UP)), PASS, "a Godot selection is Godot's")
	rig.select([box, lamp])
	assert_eq(rig.forward(PluginRig.key(KEY_UP)), STOP, "a mixed one is refused")
	assert_eq(box.global_position, Vector3.ZERO, "and nothing moves")
	assert_eq(lamp.global_position, Vector3.ZERO)
	rig.select([box])
	assert_eq(rig.forward(PluginRig.key(KEY_UP)), STOP)
	assert_eq(box.global_position, Vector3(0, 0, -level.grid_snap), "a brush alone is nudged")
	await rig.leave_level(level)


## Operation Replay's timeline answers its binding, where the router used to
## spell Ctrl+Shift+T out ahead of every binding (#1608). Moved to another chord
## it follows, and the chord it left runs what is bound there now.
func test_operation_replay_follows_its_binding():
	var level = await rig.make_level()
	var plugin: Node = rig.plugin
	var keymap = plugin._keymap
	var saved: Dictionary = keymap.get_all_bindings()
	plugin._on_dock_power_user_overlays_changed(true)
	var replay: Control = plugin._operation_replay
	var ctrl_shift_t := PluginRig.key(KEY_T, true, true)
	assert_eq(rig.forward(ctrl_shift_t), STOP, "Ctrl+Shift+T is consumed")
	assert_true(replay.visible, "and shows the timeline")
	assert_eq(rig.forward(ctrl_shift_t), STOP)
	assert_false(replay.visible, "and hides it again")

	keymap.set_binding("toggle_operation_replay", KEY_O, true, true)
	keymap.set_binding("run_trim_along_faces", KEY_T, true, true)
	rig.clear_toasts()
	assert_eq(rig.forward(ctrl_shift_t), STOP, "the chord it left is still consumed")
	assert_false(replay.visible, "but not by the timeline")
	assert_true(_has_toast_starting("Run Trim Along Faces"), "Run Trim Along Faces answers it")
	assert_eq(rig.forward(PluginRig.key(KEY_O, true, true)), STOP)
	assert_true(replay.visible, "the new chord shows the timeline")
	assert_eq(rig.forward(PluginRig.key(KEY_O, true, true)), STOP)
	assert_false(replay.visible, "and hides it")

	keymap._bindings = saved
	plugin._on_dock_power_user_overlays_changed(false)
	rig.clear_toasts()
	await rig.leave_level(level)


## With the overlays off there is no timeline to show, so its key and its
## palette row both say where to turn them on.
func test_operation_replay_with_the_overlays_off_says_where_to_turn_them_on():
	var level = await rig.make_level()
	var plugin: Node = rig.plugin
	assert_null(plugin._operation_replay, "the overlays start off")
	var hint: String = HammerForgePlugin.power_user_overlay_unavailable_message()
	rig.clear_toasts()
	assert_eq(rig.forward(PluginRig.key_for("toggle_operation_replay")), STOP)
	assert_has(rig.toasts(), hint, "the key says where")
	rig.clear_toasts()
	plugin._on_hotkey_palette_action("toggle_operation_replay")
	assert_has(rig.toasts(), hint, "and so does the palette")
	rig.clear_toasts()
	await rig.leave_level(level)


func _has_toast_starting(prefix: String) -> bool:
	for text in rig.toasts():
		if str(text).begins_with(prefix):
			return true
	return false


## The radial menu takes every key while it is open, so the router, which reads
## its binding, never sees the key that would put it away. That key is still the
## binding, not a backtick spelt out in the menu.
func test_the_radial_menus_own_binding_puts_it_away():
	var level = await rig.make_level()
	var plugin: Node = rig.plugin
	var keymap = plugin._keymap
	var saved: Dictionary = keymap.get_all_bindings()
	plugin._on_dock_power_user_overlays_changed(true)
	var radial = plugin._radial_menu
	var backtick := PluginRig.key_for("radial_menu")
	assert_eq(rig.forward(backtick), STOP)
	assert_true(radial.is_active(), "a backtick opens it")
	assert_eq(rig.forward(backtick), STOP)
	assert_false(radial.is_active(), "and puts it away")

	keymap.set_binding("radial_menu", KEY_Q, false, false, true)
	var alt_q := PluginRig.key(KEY_Q, false, false, true)
	assert_eq(rig.forward(alt_q), STOP)
	assert_true(radial.is_active(), "rebound to Alt+Q, Alt+Q opens it")
	assert_eq(rig.forward(alt_q), STOP)
	assert_false(radial.is_active(), "and puts it away")
	assert_eq(rig.forward(alt_q), STOP)
	assert_eq(rig.forward(backtick), STOP, "a backtick while it is open is the menu's")
	assert_true(radial.is_active(), "and no longer closes it")

	radial.hide_menu()
	keymap._bindings = saved
	plugin._on_dock_power_user_overlays_changed(false)
	await rig.leave_level(level)
