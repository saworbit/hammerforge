extends GutTest

const HFPluginInputRouter = preload("res://addons/hammerforge/plugin_input_router.gd")
const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
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

	keymap.set_binding("toggle_operation_replay", KEY_J, true, true)
	keymap.set_binding("run_trim_along_faces", KEY_T, true, true)
	rig.clear_toasts()
	assert_eq(rig.forward(ctrl_shift_t), STOP, "the chord it left is still consumed")
	assert_false(replay.visible, "but not by the timeline")
	assert_true(_has_toast_starting("Run Trim Along Faces"), "Run Trim Along Faces answers it")
	assert_eq(rig.forward(PluginRig.key(KEY_J, true, true)), STOP)
	assert_true(replay.visible, "the new chord shows the timeline")
	assert_eq(rig.forward(PluginRig.key(KEY_J, true, true)), STOP)
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


# -- keys the router takes ahead of a binding (#1614) --------------------------


## The palette's chords open it whatever is bound there, so the keymap reports a
## binding on one as taken.
func test_the_palette_chords_open_it_ahead_of_a_binding_on_them():
	var level = await rig.make_level()
	var plugin: Node = rig.plugin
	var keymap = plugin._keymap
	var saved: Dictionary = keymap.get_all_bindings()
	var palette: Control = plugin._hotkey_palette
	keymap.set_binding("hollow", KEY_K, true)
	assert_eq(Array(keymap.conflicts_for("hollow")), ["command_palette"], "Ctrl+K is taken")
	for press in [
		PluginRig.key(KEY_K, true),
		PluginRig.key(KEY_K, true, true, true),
		PluginRig.key(KEY_F1, true),
		PluginRig.key(KEY_SLASH, false, true, true),
	]:
		assert_eq(rig.forward(press), STOP, "%s is consumed" % press.as_text())
		assert_true(palette.visible, "%s opens the palette" % press.as_text())
		assert_eq(rig.forward(press), STOP)
		assert_false(palette.visible, "and %s puts it away" % press.as_text())
	keymap._bindings = saved
	await rig.leave_level(level)


## Shift+Left nudges whatever is bound there, so the keymap reports a binding on
## it as taken. Alt+PgUp alone is the drawing plane's, so with Grid Up moved off
## it, it nudges nothing.
func test_a_nudge_key_moves_the_selection_ahead_of_a_binding_on_it():
	var level = await rig.make_level()
	var keymap = rig.plugin._keymap
	var saved: Dictionary = keymap.get_all_bindings()
	var box = rig.box(level, "a", Vector3.ZERO)
	rig.select([box])
	keymap.set_binding("select_all", KEY_LEFT, false, true)
	assert_eq(Array(keymap.conflicts_for("select_all")), ["nudge"], "Shift+Left is taken")
	assert_eq(rig.forward(PluginRig.key(KEY_LEFT, false, true)), STOP)
	assert_eq(box.global_position, Vector3(-level.grid_snap, 0, 0), "Shift+Left nudged the box")
	keymap.set_binding("grid_up", KEY_F12)
	rig.forward(PluginRig.key(KEY_PAGEUP, false, false, true))
	assert_eq(box.global_position, Vector3(-level.grid_snap, 0, 0), "Alt+PgUp is no nudge")
	keymap._bindings = saved
	await rig.leave_level(level)


## The issue's case: Paint Bucket moved onto Q. Toggle Add / Cut answers Q in
## every mode, so in paint mode Q still flips the operation and the paint tool
## stays Line, and the keymap says so.
func test_a_paint_key_on_q_loses_to_add_cut_and_is_reported():
	var level = await rig.make_level()
	var plugin: Node = rig.plugin
	var dock = plugin.dock
	var keymap = plugin._keymap
	var saved: Dictionary = keymap.get_all_bindings()
	keymap.set_binding("paint_bucket", KEY_Q)
	assert_eq(Array(keymap.conflicts_for("paint_bucket")), ["toggle_operation"], "Q is taken")
	assert_eq(rig.forward(PluginRig.key_for("toggle_paint_mode")), STOP)
	assert_true(dock.is_paint_mode_enabled(), "paint mode is on")
	dock.set_paint_tool(3)
	var operation: int = dock.get_operation()
	assert_eq(rig.forward(PluginRig.key(KEY_Q)), STOP)
	assert_ne(dock.get_operation(), operation, "Q toggled Add / Cut")
	assert_eq(dock.get_paint_tool_id(), 3, "and the paint tool is still Line")
	rig.forward(PluginRig.key(KEY_Q))
	assert_eq(dock.get_operation(), operation, "the operation is back")
	keymap._bindings = saved
	assert_eq(rig.forward(PluginRig.key_for("toggle_paint_mode")), STOP)
	assert_false(dock.is_paint_mode_enabled(), "paint mode is off again")
	await rig.leave_level(level)


## In paint mode the paint keys are asked before every general action but the
## workflow switches and the viewport menus (`HFKeymap.EVERY_MODE`), so a general
## action sharing a chord with one waits for paint mode to end. Each general
## action's chord is given to Blend in turn and pressed in paint mode, and the
## keymap's report has to agree with what the router did.
func test_in_paint_mode_a_paint_key_is_asked_before_the_general_actions():
	var level = await rig.make_level()
	var plugin: Node = rig.plugin
	var dock = plugin.dock
	var keymap = plugin._keymap
	var saved: Dictionary = keymap.get_all_bindings()
	assert_eq(rig.forward(PluginRig.key_for("toggle_paint_mode")), STOP)
	assert_true(dock.is_paint_mode_enabled(), "paint mode is on")
	var checked := 0
	for action in saved:
		var name := str(action)
		if HFKeymapType.action_mode(name) != "general" or HFKeymapType.EVERY_MODE.has(name):
			continue
		var chord: Dictionary = saved[name]
		var bindings: Dictionary = saved.duplicate()
		# A paint key already on the chord would answer it before Blend.
		for other in saved:
			if HFKeymapType.action_mode(str(other)) == "paint" and other != "paint_blend":
				if HFKeymapType._same_chord(saved[other], chord):
					bindings.erase(other)
		bindings["paint_blend"] = chord
		keymap._bindings = bindings
		var shown: String = keymap.get_display_string("paint_blend")
		dock.set_paint_tool(0)
		plugin._last_tap_keycode = 0
		var press := PluginRig.key(
			int(chord["keycode"]),
			bool(chord.get("ctrl", false)),
			bool(chord.get("shift", false)),
			bool(chord.get("alt", false))
		)
		assert_eq(rig.forward(press), STOP, "%s is consumed in paint mode" % shown)
		assert_eq(dock.get_paint_tool_id(), 5, "Blend answers %s, not %s" % [shown, name])
		assert_false(
			keymap.conflicts_for("paint_blend").has(name), "and %s is not reported on it" % name
		)
		checked += 1
	assert_gt(checked, 50, "every general action's chord was pressed")
	keymap._bindings = saved
	assert_eq(rig.forward(PluginRig.key_for("toggle_paint_mode")), STOP)
	assert_false(dock.is_paint_mode_enabled(), "paint mode is off again")
	await rig.leave_level(level)
