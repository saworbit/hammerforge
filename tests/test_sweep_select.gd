extends GutTest

## Sweep select (#1886): hold the sweep key and drag in the Select tool, and each
## brush the cursor passes over joins the selection, or leaves it when the first
## one passed was selected already. A rectangle took the floor and the wall behind
## as well, so a run of pillars was a Shift+click on each.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginGroups = preload("res://addons/hammerforge/plugin_groups.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	_hold(false)
	await rig.take_down()


func after_each():
	_hold(false)


## The sweep key, as the keymap binds it, pressed or let go.
func _hold(down: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = int(rig.plugin._keymap.get_all_bindings()["sweep_select_hold"]["keycode"])
	key.physical_keycode = key.keycode
	key.pressed = down
	Input.parse_input_event(key)
	Input.flush_buffered_events()


func _level() -> Node:
	var level = await rig.make_level()
	rig.plugin.dock.tool_select.button_pressed = true
	rig.undo().clear()
	return level


## A floor and five pillars side by side along X, touching, so a drag along them
## never crosses the floor between them.
func _pillars(level: Node) -> Array:
	rig.box(level, "floor", Vector3(0, -0.5, 0), Vector3(30, 1, 30))
	var out: Array = []
	for i in 5:
		out.append(rig.box(level, "pillar_%d" % i, Vector3(i - 2, 2, 0), Vector3(1, 4, 1)))
	return out


func _at(brush: Node) -> Vector2:
	return rig.camera.unproject_position((brush as Node3D).global_position + Vector3(0, 1, 0.5))


## A drag from `from` over each of `over` in turn, with the sweep key held.
func _sweep(from: Node, over: Array, release := true) -> void:
	_hold(true)
	var start := _at(from)
	rig.forward(PluginRig.motion(start))
	assert_eq(
		rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, start)),
		STOP,
		"the sweep takes the press"
	)
	var last := start
	for brush in over:
		var to := _at(brush)
		for step in 6:
			var at := last.lerp(to, float(step + 1) / 6.0)
			assert_eq(
				rig.forward(PluginRig.motion(at, MOUSE_BUTTON_MASK_LEFT)), STOP, "and the drag"
			)
		last = to
	if release:
		assert_eq(
			rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, last)), STOP, "and the release"
		)
		_hold(false)


func _selected() -> Array:
	return rig.plugin._current_selection_nodes()


func test_sweeping_across_three_of_five_pillars_selects_those_three_and_not_the_floor():
	var level = await _level()
	var pillars := _pillars(level)
	rig.select([])
	await rig.frame()
	_sweep(pillars[1], [pillars[2], pillars[3]])
	await rig.frame()
	var picked := _selected()
	assert_eq(picked.size(), 3, "three brushes")
	for i in [1, 2, 3]:
		assert_has(picked, pillars[i])
	assert_false(picked.has(level.find_brush_by_id("floor")), "and not the floor under them")
	await rig.leave_level(level)


func test_starting_on_a_selected_brush_takes_out_what_the_sweep_passes():
	var level = await _level()
	var pillars := _pillars(level)
	rig.select([pillars[1], pillars[2], pillars[3], pillars[4]])
	await rig.frame()
	_sweep(pillars[1], [pillars[2], pillars[3]])
	await rig.frame()
	assert_eq(_selected(), [pillars[4]], "the three it passed are out, the fourth stays")
	await rig.leave_level(level)


func test_a_right_click_during_a_sweep_puts_the_selection_back():
	var level = await _level()
	var pillars := _pillars(level)
	rig.select([pillars[0]])
	await rig.frame()
	_sweep(pillars[1], [pillars[2]], false)
	assert_eq(_selected().size(), 3, "fixture: the sweep took two")
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true, _at(pillars[2]))), STOP)
	assert_false(rig.plugin._sweep_select.active, "the sweep is over")
	await rig.frame()
	assert_eq(_selected(), [pillars[0]], "and the selection is as it was")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, _at(pillars[2])))
	await rig.leave_level(level)


func test_escape_during_a_sweep_puts_the_selection_back():
	var level = await _level()
	var pillars := _pillars(level)
	rig.select([])
	await rig.frame()
	_sweep(pillars[1], [pillars[2]], false)
	assert_true(rig.plugin._cancel_escape_step(level), "Escape ends the sweep")
	await rig.frame()
	assert_eq(_selected(), [], "with nothing selected, as before it")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, _at(pillars[2])))
	await rig.leave_level(level)


func test_one_member_of_a_group_takes_the_whole_group():
	var level = await _level()
	var pillars := _pillars(level)
	level.visgroup_system.group_units("Pair", [pillars[3], pillars[4]])
	rig.select([])
	await rig.frame()
	_sweep(pillars[2], [pillars[3]])
	await rig.frame()
	var picked := _selected()
	assert_eq(picked.size(), 3, "pillar 2 and the pair")
	assert_has(picked, pillars[4], "the member the sweep never passed")
	await rig.leave_level(level)


func test_in_face_select_the_sweep_adds_faces():
	var level = await _level()
	var pillars := _pillars(level)
	rig.plugin.dock.face_select_mode.button_pressed = true
	await rig.frame()
	level.face_selection = {}
	_sweep(pillars[1], [pillars[2], pillars[3]])
	await rig.frame()
	var keys: Array = (level.face_selection as Dictionary).keys()
	keys.sort()
	assert_eq(keys, ["pillar_1", "pillar_2", "pillar_3"], "a face of each pillar passed")
	rig.plugin.dock.face_select_mode.button_pressed = false
	await rig.leave_level(level)


func test_the_sweep_key_is_a_hold_in_the_keymap_and_clashes_with_nothing():
	var keymap = rig.plugin._keymap
	assert_false(keymap.get_actions().has("sweep_select_hold"), "a hold runs no command")
	assert_eq(Array(keymap.conflicts_for("sweep_select_hold")), [], "and clashes with nothing")
	assert_eq(keymap.get_display_string("sweep_select_hold"), "I")
	var sweep_key := int(keymap.get_all_bindings()["sweep_select_hold"]["keycode"])
	for action in keymap.get_actions():
		var binding: Dictionary = keymap.get_all_bindings().get(action, {})
		var bare: bool = not (
			binding.get("ctrl", false) or binding.get("shift", false) or binding.get("alt", false)
		)
		assert_false(
			bare and int(binding.get("keycode", 0)) == sweep_key,
			"no command is on the key: %s" % action
		)
	assert_true(
		rig.plugin.hud._build_shortcuts_text({"tool": 1, "mode": 0}).contains(
			"Hold I + Drag: Sweep Select"
		),
		"the HUD names it"
	)
