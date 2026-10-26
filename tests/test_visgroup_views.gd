extends GutTest

## What is shown in a busy level (#1697): isolate and end it, hide the selection
## and show it again, step back through the last visibilities, and named views
## kept with the level.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


## Two rooms in visgroups, a crate in none, and a third visgroup hidden.
func _level() -> Dictionary:
	var level = await rig.make_level()
	var vg = level.visgroup_system
	var a = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var b = rig.box(level, "b", Vector3(6, 1, 0), Vector3(2, 2, 2))
	var off = rig.box(level, "off", Vector3(12, 1, 0), Vector3(2, 2, 2))
	var crate = rig.box(level, "crate", Vector3(18, 1, 0), Vector3(2, 2, 2))
	vg.add_to_visgroup(a, "Ground")
	vg.add_to_visgroup(b, "Upper")
	vg.add_to_visgroup(off, "Props")
	vg.set_visgroup_visible("Props", false)
	vg.refresh_visibility()
	return {"level": level, "vg": vg, "a": a, "b": b, "off": off, "crate": crate}


func _shown(nodes: Array) -> Array:
	var out: Array = []
	for node in nodes:
		out.append((node as Node3D).visible)
	return out


func test_isolate_shows_only_the_visgroup_and_end_isolate_puts_back_exactly_what_was():
	var s: Dictionary = await _level()
	var all := [s.a, s.b, s.off, s.crate]
	var before := _shown(all)
	assert_true(s.vg.isolate_visgroups(["Ground"]))
	assert_eq(_shown(all), [true, false, false, false], "only Ground, and nothing in no visgroup")
	assert_true(s.vg.is_isolating())
	assert_true(s.vg.end_isolate())
	assert_eq(_shown(all), before, "Props still hidden, the crate shown again")
	assert_false(s.vg.end_isolate(), "nothing left to end")
	await rig.leave_level(s.level)


func test_isolate_selection_shows_only_it_even_from_a_hidden_visgroup():
	var s: Dictionary = await _level()
	var all := [s.a, s.b, s.off, s.crate]
	assert_true(s.vg.isolate_nodes([s.off, s.crate]))
	assert_eq(_shown(all), [false, false, true, true])
	s.vg.end_isolate()
	assert_eq(_shown(all), [true, true, false, true])
	await rig.leave_level(s.level)


func test_hide_selection_is_view_state_and_never_saved():
	var s: Dictionary = await _level()
	assert_eq(s.vg.hide_from_view([s.a, s.crate]), 2)
	assert_false(s.a.visible)
	assert_false(s.crate.visible)
	assert_eq(s.vg.view_hidden_nodes().size(), 2)
	var saved: Dictionary = s.level.capture_state()
	assert_false(JSON.stringify(saved).contains("hidden"), "nothing about it in the state")
	var again := LevelRoot.new()
	again.auto_spawn_player = false
	again.hflevel_autosave_enabled = false
	add_child_autoqfree(again)
	again.restore_state(saved)
	for brush in again._iter_managed_brush_nodes():
		if str(brush.name) in ["a", "crate"]:
			assert_true(brush.visible, "%s is shown in a level made from the state" % brush.name)
	assert_eq(s.vg.show_hidden(), 2)
	assert_true(s.a.visible and s.crate.visible)
	await rig.leave_level(s.level)


func test_previous_visibility_steps_back_twenty_times_and_undoes_no_edit():
	var s: Dictionary = await _level()
	var steps: int = rig.undo().step_count()
	for i in 25:
		s.vg.set_visgroup_visible("Upper", i % 2 == 1)
	assert_eq(s.vg.view_history_size(), 20, "twenty kept")
	assert_false(s.b.visible, "the 25th left Upper hidden")
	assert_true(s.vg.previous_view())
	assert_true(s.b.visible, "one back")
	var back := 1
	while s.vg.previous_view():
		back += 1
	assert_eq(back, 20)
	assert_eq(rig.undo().step_count(), steps, "the undo history never moved")
	await rig.leave_level(s.level)


func test_isolate_and_hide_are_steps_previous_visibility_takes_back():
	var s: Dictionary = await _level()
	s.vg.hide_from_view([s.crate])
	s.vg.isolate_visgroups(["Upper"])
	assert_true(s.vg.previous_view(), "back from the isolate")
	assert_eq(_shown([s.a, s.b, s.crate]), [true, true, false])
	assert_true(s.vg.previous_view(), "back from the hide")
	assert_true(s.crate.visible)
	await rig.leave_level(s.level)


func test_a_named_view_is_kept_with_the_level_and_restored():
	var s: Dictionary = await _level()
	s.vg.set_visgroup_visible("Upper", false)
	assert_true(s.level.save_visibility_view("Ground only"))
	s.vg.set_visgroup_visible("Upper", true)
	s.vg.set_visgroup_visible("Props", true)
	var registries: Dictionary = s.level.state_system.capture_registries()
	assert_true(registries.get("visibility_views", {}).has("Ground only"), "in the saved level")
	s.vg.restore_saved_views({})
	s.level.state_system.restore_registries(registries)
	assert_eq(Array(s.vg.get_saved_view_names()), ["Ground only"], "read back")
	assert_true(s.vg.restore_saved_view("Ground only"))
	assert_eq(_shown([s.a, s.b, s.off]), [true, false, false])
	assert_true(s.level.remove_visibility_view("Ground only"))
	assert_eq(s.vg.get_saved_view_names().size(), 0)
	await rig.leave_level(s.level)


## A rename moved the members and the current visgroup and left the saved views
## on the old name, so Show left the renamed visgroup as it was (#1979).
func test_a_renamed_visgroup_keeps_its_place_in_the_saved_views():
	var s: Dictionary = await _level()
	s.vg.set_visgroup_visible("Upper", false)
	assert_true(s.level.save_visibility_view("Ground only"))
	s.vg.set_visgroup_visible("Upper", true)
	assert_true(s.vg.rename_visgroup("Upper", "Loft"))
	assert_true(s.vg.restore_saved_view("Ground only"))
	assert_eq(_shown([s.a, s.b]), [true, false], "the view hides the renamed visgroup")
	assert_true(s.vg.previous_view(), "and Previous steps back")
	assert_eq(_shown([s.a, s.b]), [true, true], "to the visgroup shown, under its new name")
	await rig.leave_level(s.level)


## Ctrl+Z never undoes a visibility change. A whole level undo put back each
## visgroup's eye and lock as the step found them, and lost Hide Selection on a
## brush it rebuilt (#1981).
func test_an_undo_keeps_the_eyes_the_locks_and_the_hides_of_now():
	var s: Dictionary = await _level()
	var before: Dictionary = s.level.capture_undo_state()
	s.level.nudge_brushes_by_id([str(s.crate.brush_id)], Vector3(0, 0, 2))
	var after: Dictionary = s.level.capture_undo_state()
	s.vg.set_visgroup_locked("Ground", true)
	s.vg.set_visgroup_visible("Upper", false)
	s.vg.hide_from_view([s.crate])
	for state in [before, after]:
		s.level.restore_state(state)
		var crate: Node3D = s.level.find_brush_by_id(str(s.crate.brush_id))
		assert_true(s.vg.is_visgroup_locked("Ground"), "Ground stays locked")
		assert_false(s.vg.is_visgroup_visible("Upper"), "Upper stays hidden")
		assert_false(crate.visible, "the crate stays hidden, rebuilt or not")
	await rig.leave_level(s.level)


## A load is not an undo: the level's own file says what is shown.
func test_a_load_takes_the_visibility_of_the_file():
	var s: Dictionary = await _level()
	s.vg.set_visgroup_visible("Upper", false)
	var saved: Dictionary = s.level.capture_state(false)
	s.vg.set_visgroup_visible("Upper", true)
	s.level.restore_state(saved)
	assert_false(s.vg.is_visgroup_visible("Upper"), "the file's Upper is hidden")
	await rig.leave_level(s.level)


func test_alt_h_hides_the_selection_and_alt_shift_h_shows_it():
	var s: Dictionary = await _level()
	rig.select([s.a])
	rig.forward(PluginRig.key(KEY_H, false, false, true))
	assert_false(s.a.visible, "hidden")
	assert_false(
		rig.plugin.stand_in_editor.selection.get_selected_nodes().has(s.a), "and not selected"
	)
	rig.forward(PluginRig.key(KEY_H, false, true, true))
	assert_true(s.a.visible, "shown again")
	await rig.leave_level(s.level)


func test_the_palette_isolates_the_selection_s_visgroups():
	var s: Dictionary = await _level()
	rig.select([s.b])
	rig.plugin._on_hotkey_palette_action("isolate_visgroups")
	assert_eq(_shown([s.a, s.b, s.crate]), [false, true, false])
	rig.plugin._on_hotkey_palette_action("end_isolate")
	assert_eq(_shown([s.a, s.b, s.crate]), [true, true, true])
	rig.select([])
	await rig.leave_level(s.level)


func test_the_dock_shows_a_hidden_chip_and_the_saved_views():
	var s: Dictionary = await _level()
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = s.level
	await get_tree().process_frame
	dock.refresh_visgroup_ui()
	assert_false(dock.view_hidden_label.visible, "nothing hidden yet")
	s.vg.hide_from_view([s.a, s.crate])
	dock.refresh_visgroup_ui()
	assert_true(dock.view_hidden_label.visible)
	assert_string_contains(dock.view_hidden_label.text, "2")
	s.vg.show_hidden()
	s.level.save_visibility_view("Lighting pass")
	dock.refresh_visgroup_ui()
	assert_false(dock.view_hidden_label.visible, "gone once shown")
	assert_eq(dock.view_saved_opt.item_count, 1)
	assert_eq(dock.view_saved_opt.get_item_text(0), "Lighting pass")
	await rig.leave_level(s.level)
