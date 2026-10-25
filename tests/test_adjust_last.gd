extends GutTest

## Change the last command's settings after running it, and let a key pass
## settings to a command (#1867).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginAdjustLast = preload("res://addons/hammerforge/plugin_adjust_last.gd")
const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const HFSolidMeasure = preload("res://addons/hammerforge/hf_solid_measure.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

const KEYMAP_FILE := "user://test_adjust_last_keymap.json"

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func after_each():
	if FileAccess.file_exists(KEYMAP_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(KEYMAP_FILE))
	HFPluginAdjustLast.close(rig.plugin)


func _panel():
	return rig.plugin._adjust_last_panel


func _level_with_box() -> Array:
	var level = await rig.make_level()
	rig.undo().clear()
	var box: DraftBrush = rig.box(level, "box", Vector3(0, 2, 0), Vector3(4, 4, 4))
	rig.select([box])
	await rig.frame()
	return [level, box]


## The thinnest wall of the shell, as its smallest size across.
func _thinnest_wall(level: Node) -> float:
	var thinnest := INF
	for brush in level._iter_managed_brush_nodes():
		var box := HFSolidMeasure.bounds(HFSolidMeasure.world_faces(brush))
		thinnest = minf(thinnest, minf(box.size.x, minf(box.size.y, box.size.z)))
	return thinnest


func test_hollow_then_a_new_thickness_rebuilds_the_walls_and_one_undo_gives_the_solid():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	rig.plugin._hollow_selected(level)
	assert_eq(await rig.accept_dialogs(), 1, "the hollow's question")
	var walls: int = level._iter_managed_brush_nodes().size()
	assert_gt(walls, 1, "walls")
	assert_true(_panel() != null and _panel().visible, "Adjust Last shows the hollow")
	assert_eq(str(rig.plugin.last_run.get("id")), "hollow")
	var steps: int = rig.undo().step_count()
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "thickness", 0.5), "adjusted")
	await rig.frame()
	assert_almost_eq(_thinnest_wall(level), 0.5, 0.01, "walls at the new thickness")
	assert_eq(rig.undo().step_count(), steps, "one step, in place of the first")
	assert_true(_panel().visible, "and the panel stays for the next change")
	assert_almost_eq(float(_panel().value_of("thickness")), 0.5, 0.001)
	rig.undo().press_undo()
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 1, "one Ctrl+Z: the solid")
	assert_false(_panel().visible, "and the panel goes with its step")
	await rig.leave_level(level)


func test_clip_shows_its_axis_and_place():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	rig.plugin._clip_selected(level)
	await rig.accept_dialogs()
	assert_eq(str(rig.plugin.last_run.get("id")), "clip")
	assert_not_null(_panel().control_for("axis"), "the axis")
	assert_not_null(_panel().control_for("position"), "and the place")
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "position", 3.0))
	await rig.frame()
	var lowest := INF
	for brush in level._iter_managed_brush_nodes():
		var box := HFSolidMeasure.bounds(HFSolidMeasure.world_faces(brush))
		lowest = minf(lowest, box.size.y)
	assert_almost_eq(lowest, 1.0, 0.01, "the cut moved to y = 3, a metre from the top")
	await rig.leave_level(level)


func test_nudge_and_rotate_show_their_settings():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	var box: DraftBrush = made[1]
	var home := box.global_position
	rig.plugin._nudge_selected(level, Vector3.RIGHT)
	assert_eq(str(rig.plugin.last_run.get("id")), "nudge")
	assert_not_null(_panel().control_for("offset"))
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "offset", Vector3(0, 0, 3)))
	assert_almost_eq(box.global_position, home + Vector3(0, 0, 3), Vector3.ONE * 0.001)
	rig.plugin._rotate_selected(level, 1)
	assert_eq(str(rig.plugin.last_run.get("id")), "rotate_ccw")
	assert_not_null(_panel().control_for("angle"))
	assert_not_null(_panel().control_for("axis"))
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "angle", 90.0))
	var turned: Node3D = level.find_brush_by_id("box")
	assert_almost_eq(absf(turned.global_basis.get_euler().y), PI / 2.0, 0.01, "a quarter turn")
	await rig.leave_level(level)


func test_an_array_shows_its_count_and_a_new_count_makes_that_many():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	var dock = rig.plugin.dock
	dock.dup_mode_opt.selected = 0
	dock.dup_count_spin.value = 2
	HFDockBrushHandler.on_create_duplicate_array(dock)
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 3, "the box and two copies")
	assert_eq(str(rig.plugin.last_run.get("id")), "duplicate_array")
	assert_not_null(_panel().control_for("count"))
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "count", 4))
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 5, "and four copies")
	assert_eq(
		int(dock.dup_count_spin.value), 4, "the dock's count follows, for the next one (#1896)"
	)
	await rig.leave_level(level)


## Settings kept by name come back on another run.
func test_settings_kept_by_name_come_back():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	var box: DraftBrush = made[1]
	var home := box.global_position
	rig.plugin._nudge_selected(level, Vector3.RIGHT)
	await HFPluginAdjustLast.adjust(rig.plugin, "offset", Vector3(0, 5, 0))
	HFPluginAdjustLast.save_preset(rig.plugin, "Up five")
	rig.plugin._nudge_selected(level, Vector3.LEFT)
	assert_true(await HFPluginAdjustLast.pick_preset(rig.plugin, "Up five"), "picked by name")
	assert_almost_eq(
		box.global_position, home + Vector3(0, 10, 0), Vector3.ONE * 0.001, "up five, twice"
	)
	var prefs = rig.plugin._user_prefs
	prefs.set_pref(HFPluginAdjustLast.PRESETS_PREF, {})
	await rig.leave_level(level)


## A step Adjust Last did not make closes it, and it says when there is nothing.
func test_another_step_closes_it():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	rig.plugin._nudge_selected(level, Vector3.RIGHT)
	assert_true(_panel().visible)
	rig.plugin._flip_selected(level)
	await rig.frame()
	assert_false(_panel().visible, "a flip is no nudge")
	rig.clear_toasts()
	rig.plugin._hotkey_palette.action_invoked.emit("adjust_last")
	assert_false(_panel().visible, "the command finds nothing to adjust")
	assert_true(
		Array(rig.toasts()).any(func(t): return str(t).begins_with("Nothing to adjust")),
		"and says so"
	)
	await rig.leave_level(level)


## Extrude is one command with a Direction, and a key can pass it.
func test_shift_e_runs_extrude_down_and_an_old_keymap_still_works():
	var level = await rig.make_level()
	var dock = rig.plugin.dock
	dock.tool_draw.button_pressed = true
	rig.forward(PluginRig.key(KEY_E, false, true))
	assert_true(dock.tool_extrude_down.button_pressed, "Shift+E: Extrude pointing down")
	rig.forward(PluginRig.key(KEY_E))
	assert_true(dock.tool_extrude_up.button_pressed, "E: pointing up")
	var file := FileAccess.open(KEYMAP_FILE, FileAccess.WRITE)
	(
		file
		. store_string(
			(
				JSON
				. stringify(
					{
						"tool_extrude_down_alt": {"keycode": "X", "shift": true},
						"tool_extrude": {"keycode": "E", "args": {"direction": 1}},
					}
				)
			)
		)
	)
	file.close()
	var keymap := HFKeymap.load_or_default(KEYMAP_FILE)
	assert_eq(int(keymap.args_for("tool_extrude").get("direction", 0)), 1, "a key with settings")
	assert_eq(keymap.args_for("tool_extrude_down_alt"), {}, "an old id needs none")
	assert_true(keymap.matches("tool_extrude_down_alt", PluginRig.key(KEY_X, false, true)))
	assert_eq(HFCommandRegistry.runs("tool_extrude_down_alt")["id"], "tool_extrude")
	await rig.leave_level(level)
