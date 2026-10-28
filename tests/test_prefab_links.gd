extends GutTest

## A placed prefab copy cut loose as ordinary geometry, and every copy of a
## prefab found and selected (#1734).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const DraftEntityType = preload("res://addons/hammerforge/draft_entity.gd")
const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")

const CRATE := "user://hf_test_prefab_links_crate.hfprefab"
const LAMP := "user://hf_test_prefab_links_lamp.hfprefab"

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	for path in [CRATE, LAMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await rig.take_down()


## A prefab saved from a box and a lamp, at `path`.
func _prefab(level, path: String, at: Vector3) -> HFPrefabType:
	var box = rig.box(level, "src_%d" % int(at.x), at, Vector3(2, 2, 2))
	var lamp := DraftEntityType.new()
	lamp.name = "lamp_%d" % int(at.x)
	lamp.entity_type = "light_point"
	level.add_entity(lamp)
	lamp.global_position = at + Vector3(0, 2, 0)
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, [box], [lamp]
	)
	prefab.save_to_file(path)
	level.delete_brush(box)
	lamp.get_parent().remove_child(lamp)
	lamp.queue_free()
	return prefab


func _place(level, prefab: HFPrefabType, path: String, at: Vector3) -> String:
	var placed: Dictionary = prefab.instantiate(level.brush_system, level.entity_system, level, at)
	return level.prefab_system.register_instance(
		path, placed["brush_ids"], placed["entity_nodes"], true
	)


func _selected() -> Array:
	return rig.plugin.stand_in_editor.selection.get_selected_nodes()


func test_unlink_copy_leaves_ordinary_geometry_a_pull_never_touches():
	var level = await rig.make_level()
	var crate := _prefab(level, CRATE, Vector3(-30, 1, 0))
	var kept := _place(level, crate, CRATE, Vector3(0, 1, 0))
	var loose := _place(level, crate, CRATE, Vector3(10, 1, 0))
	var pieces: Array = level.prefab_system.pieces_of(level.prefab_system.get_instance(loose))
	assert_eq(pieces.size(), 2, "fixture: a box and a lamp")
	var steps: int = rig.undo().step_count()
	rig.select([pieces[0]])
	rig.plugin._on_hotkey_palette_action("unlink_prefab_copy")
	assert_null(level.prefab_system.get_instance(loose), "the level forgets the copy")
	for piece in pieces:
		assert_true(is_instance_valid(piece), "%s is still in the level" % piece.name)
		for key in level.prefab_system.LINK_META:
			assert_false(piece.has_meta(key), "%s carries no %s" % [piece.name, key])
	assert_eq(rig.undo().step_count(), steps + 1, "one undo step")
	var box_center: Vector3 = (pieces[0] as Node3D).global_position
	assert_eq(level.prefab_system.propagate_from_source(CRATE), 1, "a Pull reaches the other")
	assert_not_null(level.prefab_system.get_instance(kept))
	assert_true(is_instance_valid(pieces[0]), "and leaves the unlinked box alone")
	assert_eq((pieces[0] as Node3D).global_position, box_center)
	rig.select([])
	await rig.leave_level(level)


func test_unlink_is_undone_back_into_a_linked_copy():
	var level = await rig.make_level()
	var crate := _prefab(level, CRATE, Vector3(-30, 1, 0))
	var iid := _place(level, crate, CRATE, Vector3(0, 1, 0))
	var first = level.prefab_system.pieces_of(level.prefab_system.get_instance(iid))[0]
	rig.select([first])
	rig.plugin._on_hotkey_palette_action("unlink_prefab_copy")
	assert_null(level.prefab_system.get_instance(iid))
	rig.undo().press_undo()
	assert_not_null(level.prefab_system.get_instance(iid), "the copy is back")
	assert_eq(
		level.prefab_system.pieces_of(level.prefab_system.get_instance(iid)).size(),
		2,
		"with both its pieces linked"
	)
	rig.select([])
	await rig.leave_level(level)


func test_select_linked_copies_selects_every_copy_and_only_those():
	var level = await rig.make_level()
	var crate := _prefab(level, CRATE, Vector3(-30, 1, 0))
	var lamp := _prefab(level, LAMP, Vector3(-40, 1, 0))
	var copies: Array = []
	for i in 3:
		copies.append(_place(level, crate, CRATE, Vector3(i * 6.0, 1, 0)))
	var other := _place(level, lamp, LAMP, Vector3(0, 1, 20))
	var stray = rig.box(level, "stray", Vector3(0, 1, -20), Vector3(2, 2, 2))
	var first = level.prefab_system.pieces_of(level.prefab_system.get_instance(copies[0]))[0]
	rig.select([first])
	rig.plugin._on_hotkey_palette_action("select_linked_copies")
	var picked := _selected()
	assert_eq(picked.size(), 6, "three copies of a box and a lamp")
	for iid in copies:
		for piece in level.prefab_system.pieces_of(level.prefab_system.get_instance(iid)):
			assert_true(picked.has(piece), "%s of %s" % [piece.name, iid])
	for piece in level.prefab_system.pieces_of(level.prefab_system.get_instance(other)):
		assert_false(picked.has(piece), "not the other prefab's %s" % piece.name)
	assert_false(picked.has(stray), "nor a brush in no copy")
	rig.select([])
	await rig.leave_level(level)


func test_the_badge_counts_the_copies():
	var level = await rig.make_level()
	var crate := _prefab(level, CRATE, Vector3(-30, 1, 0))
	var iids: Array = []
	for i in 4:
		iids.append(_place(level, crate, CRATE, Vector3(i * 6.0, 1, 0)))
	assert_eq(level.prefab_system.copies_like(iids[0]).size(), 4)
	var first = level.prefab_system.pieces_of(level.prefab_system.get_instance(iids[0]))[0]
	rig.select([first])
	var state: Dictionary = HFPluginCommands.build_command_state(rig.plugin, level, 0)
	assert_eq(int(state.get("prefab_copies", 0)), 4, "the toolbar is told how many")
	rig.select([])
	await rig.leave_level(level)


## Clear Kept on a copy with a locked piece leaves the copy as it is, and the
## history too. It recorded an empty "Clear Kept" step (#1977).
func test_clear_kept_on_a_locked_copy_records_no_step():
	var level = await rig.make_level()
	var crate := _prefab(level, CRATE, Vector3(-30, 1, 0))
	var iid := _place(level, crate, CRATE, Vector3(0, 1, 0))
	var pieces: Array = level.prefab_system.pieces_of(level.prefab_system.get_instance(iid))
	var lamp: Node3D = null
	for piece in pieces:
		if level.is_entity_node(piece):
			lamp = piece
	assert_not_null(lamp, "fixture: the copy's lamp")
	assert_true(level.set_prefab_wiring_kept(lamp, true), "fixture: its wiring is kept")
	rig.select([lamp])
	await rig.frame()
	level.create_visgroup("Done")
	level.add_selection_to_visgroup("Done", [lamp])
	level.visgroup_system.set_visgroup_locked("Done", true)
	var steps: int = rig.undo().step_count()
	HFDockEntityHandler.on_entity_clear_kept(rig.plugin.dock, lamp)
	assert_eq(rig.undo().step_count(), steps, "no step")
	assert_true(level.prefab_system.kept_of(lamp).get("wiring", false), "the wiring is still kept")
	level.visgroup_system.set_visgroup_locked("Done", false)
	HFDockEntityHandler.on_entity_clear_kept(rig.plugin.dock, lamp)
	assert_eq(rig.undo().step_count(), steps + 1, "unlocked, Clear Kept is one step")
	rig.select([])
	await rig.leave_level(level)


func test_ctrl_d_of_a_whole_copy_makes_another_linked_copy_when_asked():
	var level = await rig.make_level()
	var crate := _prefab(level, CRATE, Vector3(-30, 1, 0))
	var iid := _place(level, crate, CRATE, Vector3(0, 1, 0))
	var pieces: Array = level.prefab_system.pieces_of(level.prefab_system.get_instance(iid))
	rig.plugin._user_prefs.set_pref("duplicate_keeps_prefab_link", true)
	rig.select(pieces)
	rig.plugin._on_hotkey_palette_action("duplicate")
	var copies: Array = level.prefab_system.copies_like(iid)
	assert_eq(copies.size(), 2, "another copy of the prefab")
	for rec in copies:
		assert_true(rec.linked, "%s is linked" % rec.instance_id)
	var made = _selected()
	assert_eq(made.size(), 2, "the new copy is selected")
	assert_false(made.has(pieces[0]), "and not the old one")
	rig.plugin._user_prefs.set_pref("duplicate_keeps_prefab_link", false)
	rig.select(pieces)
	rig.plugin._on_hotkey_palette_action("duplicate")
	assert_eq(level.prefab_system.copies_like(iid).size(), 2, "off, Ctrl+D makes ordinary geometry")
	rig.select([])
	await rig.leave_level(level)
