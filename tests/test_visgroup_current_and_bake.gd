extends GutTest

## A current visgroup new work goes into, and a visgroup left out of the bake
## (#1732).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const MapIO = preload("res://addons/hammerforge/map_io.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _box_info(center: Vector3) -> Dictionary:
	return {"size": Vector3(2, 2, 2), "center": center}


func test_a_drawn_brush_joins_the_current_visgroup_and_a_redo_keeps_it_there():
	var level = await rig.make_level()
	level.visgroup_system.create_visgroup("Upper floor")
	level.current_visgroup = "Upper floor"
	var before: Array = level._iter_managed_brush_nodes()
	rig.plugin._commit_brush_placement(level, _box_info(Vector3(0, 1, 0)))
	var made: Array = level._iter_managed_brush_nodes().filter(func(b): return not before.has(b))
	assert_eq(made.size(), 1)
	assert_eq(level.visgroup_system.get_visgroups_of(made[0]), PackedStringArray(["Upper floor"]))
	rig.undo().press_undo()
	rig.undo().press_redo()
	var again: Array = level._iter_managed_brush_nodes().filter(func(b): return not before.has(b))
	assert_eq(level.visgroup_system.get_visgroups_of(again[0]), PackedStringArray(["Upper floor"]))
	level.current_visgroup = ""
	var plain_before: Array = level._iter_managed_brush_nodes()
	rig.plugin._commit_brush_placement(level, _box_info(Vector3(5, 1, 0)))
	var plain: Array = level._iter_managed_brush_nodes().filter(
		func(b): return not plain_before.has(b)
	)
	assert_eq(level.visgroup_system.get_visgroups_of(plain[0]), PackedStringArray(), "none")
	await rig.leave_level(level)


func test_a_structure_and_a_pasted_piece_join_it_too():
	var level = await rig.make_level()
	level.visgroup_system.create_visgroup("Upper floor")
	level.current_visgroup = "Upper floor"
	var made = level.create_generator(
		"stairs", HFGeneratorSystem.default_settings("stairs"), Transform3D()
	)
	assert_true(made.ok)
	var pieces: Array = level._iter_managed_brush_nodes()
	assert_gt(pieces.size(), 0)
	for piece in pieces:
		assert_true(level.visgroup_system.get_visgroups_of(piece).has("Upper floor"))
	await rig.leave_level(level)


func test_a_left_out_visgroup_is_visible_and_in_no_bake_or_export():
	var level = await rig.make_level()
	level.bake_use_face_materials = true
	var kept = level.create_brush_from_info(_box_info(Vector3(0, 1, 0)))
	var guide = level.create_brush_from_info(_box_info(Vector3(60, 1, 0)))
	level.visgroup_system.add_to_visgroup(guide, "Guides")
	rig.plugin.dock.undo_redo = rig.undo()
	rig.plugin.dock._commit_state_action_if_changed(
		"Leave Visgroup Out of Bake", "set_visgroup_bakes", ["Guides", false]
	)
	assert_false(level.visgroup_system.visgroup_bakes("Guides"))
	assert_true(guide.visible, "still visible")
	assert_false(level.bake_system.brush_bakes(guide), "not baked")
	assert_true(level.bake_system.brush_bakes(kept))
	assert_true(await level.bake(), "full bake")
	var box := _baked_bounds(level)
	assert_lt(box.end.x, 30.0, "the full bake left the guide out: %s" % box)
	assert_true(await level.bake_dirty(), "partial bake")
	assert_lt(_baked_bounds(level).end.x, 30.0, "and Bake Changed did too")
	var text := MapIO.export_map_from_level(level)
	assert_false(text.contains("( 61"), "the .map has no brush at the guide")
	assert_eq(level.visgroup_system.left_out_count(), 1, "an export says one was left out")
	rig.undo().press_undo()
	assert_true(level.visgroup_system.visgroup_bakes("Guides"), "one undo step puts it back")
	await rig.leave_level(level)


func _baked_bounds(level) -> AABB:
	var box := AABB()
	var seeded := false
	for mesh in level.baked_container.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = (
			(mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		)
		box = part if not seeded else box.merge(part)
		seeded = true
	return box


func test_both_settings_survive_a_save_and_a_reload():
	var level = await rig.make_level()
	var brush = level.create_brush_from_info(_box_info(Vector3(0, 1, 0)))
	level.visgroup_system.add_to_visgroup(brush, "Guides")
	level.visgroup_system.create_visgroup("Upper floor")
	level.set_visgroup_bakes("Guides", false)
	level.current_visgroup = "Upper floor"
	var payload: Dictionary = HFLevelIO.decode_variant(
		JSON.parse_string(JSON.stringify(level.state_system.capture_hflevel_state()))
	)
	var again := LevelRootType.new()
	again.auto_spawn_player = false
	again.hflevel_autosave_enabled = false
	add_child_autofree(again)
	again._apply_hflevel_settings(payload["settings"])
	again.restore_state(payload["state"])
	assert_eq(again.current_visgroup, "Upper floor")
	assert_false(again.visgroup_system.visgroup_bakes("Guides"))
	assert_true(again.visgroup_system.visgroup_bakes("Upper floor"))
	await rig.leave_level(level)


func test_renaming_or_removing_the_current_visgroup_follows_it():
	var level = await rig.make_level()
	level.visgroup_system.create_visgroup("Upper floor")
	level.current_visgroup = "Upper floor"
	level.visgroup_system.rename_visgroup("Upper floor", "Floor 2")
	assert_eq(level.current_visgroup, "Floor 2")
	level.visgroup_system.remove_visgroup("Floor 2")
	assert_eq(level.current_visgroup, "")
	await rig.leave_level(level)


func test_the_hud_names_the_visgroup_a_new_brush_joins():
	var hud_script = load("res://addons/hammerforge/shortcut_hud.gd")
	assert_eq(
		hud_script.into_visgroup("Click + Drag: Draw Base\nShift: Square", ""),
		"Click + Drag: Draw Base\nShift: Square"
	)
	assert_eq(
		hud_script.into_visgroup("Click + Drag: Draw Base\nShift: Square", "Upper floor"),
		"Click + Drag: Draw Base  (into Upper floor)\nShift: Square"
	)
