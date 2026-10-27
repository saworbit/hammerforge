extends GutTest

## Change the last command's settings after running it, and let a key pass
## settings to a command (#1867).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginAdjustLast = preload("res://addons/hammerforge/plugin_adjust_last.gd")
const HFPluginRun = preload("res://addons/hammerforge/plugin_run.gd")
const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")
const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const McpDispatcher = preload("res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd")
const McpHost = preload("res://tests/mcp/mcp_test_host.gd")
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


func _said(text: String) -> bool:
	return Array(rig.toasts()).any(func(t): return str(t).contains(text))


## A thickness Hollow refuses is asked about before the hollow is undone: the
## room stays hollow, no empty step takes its place, the panel goes back to the
## thickness the walls have, and the refusal says why. The hollow was undone and
## a Hollow that changed nothing took its place (#1995).
func test_a_thickness_hollow_refuses_leaves_the_hollow_and_says_why():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	rig.plugin.dock.hollow_thickness.value = 0.25
	rig.plugin._hollow_selected(level)
	await rig.accept_dialogs()
	var walls: int = level._iter_managed_brush_nodes().size()
	var steps: int = rig.undo().step_count()
	rig.clear_toasts()
	# As the panel asks, from its spin box: 3.0 is in its range, and no 4 m box
	# holds a room with 3 m walls.
	(_panel().control_for("thickness") as SpinBox).value = 3.0
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), walls, "the walls are still there")
	assert_almost_eq(_thinnest_wall(level), 0.25, 0.01, "at the thickness they had")
	assert_eq(rig.undo().step_count(), steps, "no step was added or taken away")
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Hollow")
	assert_almost_eq(float(_panel().value_of("thickness")), 0.25, 0.001, "the panel goes back")
	assert_almost_eq(float(rig.plugin.last_run["settings"]["thickness"]), 0.25, 0.001)
	assert_almost_eq(rig.plugin.dock.get_hollow_thickness(), 0.25, 0.001, "the dock keeps 0.25")
	assert_true(_said("leaves no room"), "and says why: %s" % [rig.toasts()])
	assert_false(await HFPluginAdjustLast.adjust(rig.plugin, "thickness", 3.0), "refused")
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "thickness", 0.5), "a fit is taken")
	await rig.frame()
	assert_almost_eq(_thinnest_wall(level), 0.5, 0.01)
	rig.undo().press_undo()
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 1, "one Ctrl+Z still gives the solid")
	await rig.leave_level(level)


## A grid array the cap of 256 copies refuses is asked about before the array is
## undone: the array stays and the refusal names the cap. It was undone, nothing
## replaced it, and nothing was said (#1995).
func test_an_array_past_the_cap_leaves_the_array_and_names_the_cap():
	var level = await rig.make_level()
	rig.undo().clear()
	var tile: DraftBrush = rig.box(level, "tile", Vector3(0, 0.5, 0), Vector3(1, 1, 1))
	rig.select([tile])
	await rig.frame()
	var dock = rig.plugin.dock
	dock.dup_mode_opt.selected = 2
	dock.dup_grid_x.value = 2
	dock.dup_grid_y.value = 1
	dock.dup_grid_z.value = 2
	HFDockBrushHandler.on_create_duplicate_array(dock)
	await rig.frame()
	assert_eq(str(rig.plugin.last_run.get("id")), "grid_array", "fixture: a grid")
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "count_x", 20), "20 x 1 x 2 is 39")
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 40)
	var steps: int = rig.undo().step_count()
	rig.clear_toasts()
	assert_false(await HFPluginAdjustLast.adjust(rig.plugin, "count_z", 20), "20 x 1 x 20 is 399")
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 40, "the 20 x 1 x 2 array stays")
	assert_eq(rig.undo().step_count(), steps, "and no empty step takes its place")
	assert_eq(int(rig.plugin.last_run["settings"]["count_z"]), 2)
	assert_true(_said("256"), "the refusal names the cap: %s" % [rig.toasts()])
	await rig.leave_level(level)


## The same for a line of copies of two brushes: 150 copies is in the panel's
## range, and 300 brushes is past the cap.
func test_a_line_of_copies_past_the_cap_is_refused_before_the_undo():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	var other: DraftBrush = rig.box(level, "other", Vector3(6, 2, 0))
	rig.select([made[1], other])
	await rig.frame()
	var dock = rig.plugin.dock
	dock.dup_mode_opt.selected = 0
	dock.dup_count_spin.value = 2
	HFDockBrushHandler.on_create_duplicate_array(dock)
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 6, "fixture: two brushes, twice")
	var steps: int = rig.undo().step_count()
	rig.clear_toasts()
	assert_false(await HFPluginAdjustLast.adjust(rig.plugin, "count", 150))
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 6, "the array stays")
	assert_eq(rig.undo().step_count(), steps)
	assert_true(_said("256"), "%s" % [rig.toasts()])
	await rig.leave_level(level)


## A cut moved out of the brush is asked about before the clip is undone.
func test_a_cut_moved_out_of_the_brush_leaves_the_clip():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	rig.plugin._clip_selected(level)
	await rig.accept_dialogs()
	assert_eq(level._iter_managed_brush_nodes().size(), 2, "fixture: two pieces")
	var steps: int = rig.undo().step_count()
	rig.clear_toasts()
	assert_false(await HFPluginAdjustLast.adjust(rig.plugin, "position", 10.0))
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 2, "the pieces stay")
	assert_eq(rig.undo().step_count(), steps)
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Clip Brush")
	assert_true(_said("outside brush bounds"), "%s" % [rig.toasts()])
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


## A count past 100 reaches the dock as it is, and the next array makes it. The
## dock's count stopped at 100, so the next array made 100 (#1996).
func test_a_count_of_150_reaches_the_dock_and_the_next_array():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	var dock = rig.plugin.dock
	dock.dup_mode_opt.selected = 0
	dock.dup_count_spin.value = 2
	HFDockBrushHandler.on_create_duplicate_array(dock)
	await rig.frame()
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "count", 150))
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 151, "the box and 150 copies")
	assert_eq(int(dock.dup_count_spin.value), 150, "the dock holds 150")
	var post: DraftBrush = rig.box(level, "post", Vector3(0, 2, 40))
	rig.select([post])
	await rig.frame()
	HFDockBrushHandler.on_create_duplicate_array(dock)
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), 302, "and the next array makes 150")
	await rig.leave_level(level)


## An offset of 2.5 and a rise of 0.5 reach the dock as they are. Its offset and
## rise spins stepped by 1 and held 3 and 1, so the next array was not this one
## (#1996).
func test_an_offset_and_a_rise_between_whole_metres_reach_the_dock_as_they_are():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	var dock = rig.plugin.dock
	dock.dup_mode_opt.selected = 0
	dock.dup_count_spin.value = 2
	HFDockBrushHandler.on_create_duplicate_array(dock)
	await rig.frame()
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "offset", Vector3(2.5, 0, 0)))
	await rig.frame()
	assert_almost_eq(float(dock.dup_offset_x.value), 2.5, 0.0001, "the dock's offset is 2.5")
	var post: DraftBrush = rig.box(level, "post", Vector3(0, 2, 40))
	rig.select([post])
	await rig.frame()
	dock.dup_mode_opt.selected = 1
	dock.dup_count_spin.value = 3
	HFDockBrushHandler.on_create_duplicate_array(dock)
	await rig.frame()
	assert_eq(str(rig.plugin.last_run.get("id")), "radial_array", "fixture: a ring")
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "rise", 0.5))
	await rig.frame()
	assert_almost_eq(float(dock.dup_rise_spin.value), 0.5, 0.0001, "the dock's rise is 0.5")
	await rig.leave_level(level)


## A ring's new step from Adjust Last reaches the dock as the step, with Fill 360
## off, even when Fill 360 was ticked again for the next ring. Fill 360 stayed
## ticked and the next ring threw the step away (#1931).
func test_a_ring_s_new_step_reaches_the_dock_with_fill_360_off():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	var dock = rig.plugin.dock
	dock.dup_mode_opt.selected = 1
	dock.dup_count_spin.value = 3
	dock.dup_fill_check.button_pressed = true
	HFDockBrushHandler.on_create_duplicate_array(dock)
	await rig.frame()
	assert_eq(str(rig.plugin.last_run.get("id")), "radial_array", "fixture: a ring")
	rig.select([])
	await rig.frame()
	dock.dup_fill_check.button_pressed = true
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "step", 30.0))
	await rig.frame()
	assert_false(dock.dup_fill_check.button_pressed, "Fill 360 is off")
	var params: Dictionary = HFDockBrushHandler.array_params(dock, PackedStringArray())
	assert_almost_eq(float(params["step_degrees"]), 30.0, 0.001, "and the dock's step is 30")
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


## The plugin's bridge over the rig's scene and undo, as the editor's is over
## its own, which cannot be asked headless. Gives back the one it replaced.
func _bridge_over_the_rig() -> Variant:
	var kept = rig.plugin.mcp_dispatcher
	var host := McpHost.new()
	host.scene = rig.scene_root
	host.undo = rig.undo()
	host.tree = get_tree()
	rig.plugin.mcp_dispatcher = McpDispatcher.new(host)
	return kept


func _put_back_bridge(kept: Variant) -> void:
	rig.plugin.mcp_dispatcher.shutdown()
	rig.plugin.mcp_dispatcher = kept


## Ctrl+H with a thickness in its keymap entry hollows with it, as the command
## line does: one step named Hollow, with 0.5 m walls and not the dock's 0.25,
## and Repeat Run holds it with them. Only Extrude read a key's settings (#1997).
func test_a_key_with_a_thickness_hollows_with_it():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	var kept = _bridge_over_the_rig()
	rig.plugin.dock.hollow_thickness.value = 0.25
	var file := FileAccess.open(KEYMAP_FILE, FileAccess.WRITE)
	var entry := {"keycode": "H", "ctrl": true, "args": {"thickness": 0.5}}
	file.store_string(JSON.stringify({"hollow": entry}))
	file.close()
	var keymap = rig.plugin._keymap
	assert_true(keymap.import_from(KEYMAP_FILE), "fixture: Ctrl+H carries a thickness")
	HFPluginRun.clear(rig.plugin)
	var steps: int = rig.undo().step_count()
	assert_eq(rig.forward(PluginRig.key(KEY_H, true)), EditorPlugin.AFTER_GUI_INPUT_STOP)
	await rig.frame()
	await rig.frame()
	keymap.reset_all()
	assert_eq(rig.open_dialogs().size(), 0, "nothing to ask: the key gave the thickness")
	assert_almost_eq(_thinnest_wall(level), 0.5, 0.01, "0.5 m walls")
	assert_eq(rig.undo().step_count(), steps + 1, "one step")
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Hollow")
	var run: Array = HFPluginRun.steps_of(rig.plugin)
	assert_eq(run.size(), 1, "the run holds it")
	if run.size() == 1:
		assert_eq(str(run[0]["id"]), "hollow")
		assert_almost_eq(float(run[0]["settings"]["thickness"]), 0.5, 0.001)
	_put_back_bridge(kept)
	await rig.leave_level(level)


## The same through `execute()`, as the palette, a menu and a bound command run.
func test_execute_with_a_thickness_hollows_with_it():
	var made: Array = await _level_with_box()
	var level: Node = made[0]
	var kept = _bridge_over_the_rig()
	rig.plugin.dock.hollow_thickness.value = 0.25
	HFPluginCommands.execute(rig.plugin, "hollow", [], {"thickness": 0.5})
	await rig.frame()
	await rig.frame()
	assert_almost_eq(_thinnest_wall(level), 0.5, 0.01, "0.5 m walls")
	_put_back_bridge(kept)
	await rig.leave_level(level)


## Replace Material on shown brushes, then Whole level in Adjust Last, then one
## Ctrl+Z: the hidden brush the adjust reached goes back too. The step kept only
## the brushes the first scope found, so the undo left the hidden one replaced
## (#1930).
func test_replace_shown_then_adjusted_to_the_whole_level_undoes_the_hidden_brush_too():
	var level = await rig.make_level()
	rig.undo().clear()
	level.add_prototype_materials()
	var shown: DraftBrush = rig.box(level, "shown", Vector3(0, 2, 0))
	var hidden: DraftBrush = rig.box(level, "hidden", Vector3(8, 2, 0))
	for face in shown.faces + hidden.faces:
		face.material_idx = 1
	hidden.visible = false
	rig.plugin.dock._on_replace_material_requested(1, 2, {"visible_only": true}, false)
	assert_eq(str(rig.plugin.last_run.get("id")), "replace_material", "fixture: Adjust Last has it")
	assert_eq(hidden.faces[0].material_idx, 1, "fixture: shown only leaves the hidden brush")
	assert_true(await HFPluginAdjustLast.adjust(rig.plugin, "scope", "level"), "adjusted")
	await rig.frame()
	hidden = level.find_brush_by_id("hidden")
	assert_eq(hidden.faces[0].material_idx, 2, "the whole level reaches the hidden brush")
	rig.undo().press_undo()
	await rig.frame()
	assert_eq(level.find_brush_by_id("hidden").faces[0].material_idx, 1, "one Ctrl+Z puts it back")
	assert_eq(level.find_brush_by_id("shown").faces[0].material_idx, 1, "and the shown one")
	await rig.leave_level(level)
