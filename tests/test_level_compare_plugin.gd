extends GutTest

## Compare With on the real plugin (#1701): what changed since a file is outlined
## in the viewport and listed in the Console, a row selects what it names, the
## open level and its undo history are left as they were, and the headless tool
## prints the same changes.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFLevelCompare = preload("res://addons/hammerforge/hf_level_compare.gd")

const PATH := "user://test_level_compare_plugin.hflevel"
const NEWER := "user://test_level_compare_plugin_newer.hflevel"

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func after_each():
	for path in [PATH, NEWER]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish_saving(level: Node) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return
		await get_tree().process_frame


func _save(level: Node, path: String) -> void:
	assert_eq(level.save_hflevel(path, true), OK, "fixture: the level saves")
	await _finish_saving(level)


func _box(level: Node, centre: Vector3, brush_id: String) -> Node:
	return level.create_brush_from_info(
		{"shape": 0, "size": Vector3(2, 2, 2), "center": centre, "brush_id": brush_id}
	)


## A level saved to `PATH`, then changed: one brush moved, one deleted, one
## added, and an entity placed.
func _changed_level() -> Node:
	var level = await rig.make_level()
	_box(level, Vector3(0, 1, 0), "stays_moved")
	_box(level, Vector3(5, 1, 0), "goes")
	await _save(level, PATH)
	level.find_brush_by_id("stays_moved").global_position += Vector3(0, 0.5, 0)
	level.delete_brush_by_id("goes")
	_box(level, Vector3(10, 1, 0), "new_one")
	(
		level
		. entity_system
		. restore_entity_from_info(
			{
				"name": "lamp",
				"entity_type": "light_point",
				"properties": {},
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)),
			}
		)
	)
	await get_tree().process_frame
	return level


func test_a_compare_draws_lists_and_leaves_the_level_alone():
	var level = await _changed_level()
	rig.undo().clear()
	var before: Dictionary = level.state_system.capture_hflevel_payload()
	rig.plugin._on_compare_requested(PATH)
	var overlay = rig.plugin._compare_overlay
	assert_not_null(overlay, "the compare is drawn")
	if overlay == null:
		return
	var drawn: Dictionary = overlay.segments()
	assert_gt(drawn["added"], 0, "the added brush and entity, solid")
	assert_gt(drawn["changed"], 0, "the moved brush, twice")
	assert_gt(drawn["removed"], 0, "the deleted brush, dashed where the file has it")
	var rows: PackedStringArray = rig.plugin.console_panel.compare_rows()
	assert_true(Array(rows).any(func(r): return r.ends_with("moved 0.5 m up")), "\n".join(rows))
	assert_true(Array(rows).any(func(r): return r.ends_with(": removed")), "\n".join(rows))
	assert_has(rows, "entity 'lamp' (light_point): added")
	assert_eq(
		HFLevelCompare.compare(before, level.state_system.capture_hflevel_payload())["lines"],
		PackedStringArray(["No changes"]),
		"the open level is as it was"
	)
	assert_eq(rig.undo().step_count(), 0, "and its history has no new step")
	rig.plugin._on_console_action("compare_end")
	assert_false(overlay.is_showing(), "End Compare takes the outlines off")
	assert_eq(rig.plugin.console_panel.compare_rows(), PackedStringArray(), "and the list")
	await rig.leave_level(level)


func test_a_row_selects_what_it_names():
	var level = await _changed_level()
	rig.plugin._on_compare_requested(PATH)
	rig.plugin._on_console_action("compare_pick:brush:stays_moved")
	var picked: Array = rig.plugin.get_editor_interface().get_selection().get_selected_nodes()
	assert_eq(picked, [level.find_brush_by_id("stays_moved")])
	rig.plugin._on_console_action("compare_end")
	await rig.leave_level(level)


func test_the_headless_tool_prints_the_same_changes():
	var level = await _changed_level()
	await _save(level, NEWER)
	var older: Dictionary = level.file_system.read_hflevel(PATH)["bundle"]
	var newer: Dictionary = level.file_system.read_hflevel(NEWER)["bundle"]
	var expected: PackedStringArray = HFLevelCompare.compare(older, newer)["lines"]
	var output: Array = []
	var code := (
		OS
		. execute(
			OS.get_executable_path(),
			[
				"--headless",
				"-s",
				"res://tools/compare_levels.gd",
				"--path",
				ProjectSettings.globalize_path("res://"),
				"--",
				ProjectSettings.globalize_path(PATH),
				ProjectSettings.globalize_path(NEWER),
			],
			output,
			true
		)
	)
	assert_eq(code, 1, "1 for a change, as diff has it")
	var printed: PackedStringArray = "".join(output).replace("\r", "").split("\n")
	var at := 0
	for line in expected:
		var found := printed.find(line, at)
		assert_gt(found, -1, "the tool prints '%s'" % line)
		if found >= 0:
			at = found + 1
	await rig.leave_level(level)
