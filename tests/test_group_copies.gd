extends GutTest

## Every way to copy a grouped selection groups the copies the way Duplicate
## does (#1897): a group copied whole is a group of its own, nested as the
## original is, and a copy of a member of an open group joins that group. Paste
## dropped every group, Mirror Copy's copies joined the original's group, and a
## prefab lost its inner groups.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginGroups = preload("res://addons/hammerforge/plugin_groups.gd")
const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")
const HFPrefabSystem = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const HFPrefab = preload("res://addons/hammerforge/hf_prefab.gd")

const SAVE_PATH := "user://test_group_copies.hflevel"

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func before_each():
	HFPrefabSystem.system_clipboard_stand_in = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HFPrefabSystem.map_text_path()))


func after_each():
	HFPrefabSystem.system_clipboard_stand_in = null
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _level() -> Node:
	var level = await rig.make_level()
	level.grid_snap = 1.0
	rig.undo().clear()
	return level


func _select(nodes: Array) -> void:
	rig.select(nodes)
	await rig.frame()


func _selected() -> Array:
	return rig.plugin._current_selection_nodes()


## Group `nodes`, named `group_name`.
func _group(level: Node, nodes: Array, group_name: String) -> void:
	await _select(nodes)
	assert_true(HFPluginGroups.group_selected(rig.plugin, level), "fixture: it asks")
	var dialogs: Array = rig.open_dialogs()
	var field: LineEdit = (
		dialogs[0].find_child("GroupName", true, false) if dialogs.size() == 1 else null
	)
	assert_not_null(field, "fixture: the name question")
	if field:
		field.text = group_name
	await rig.accept_dialogs()


## A house: a roof group and a wall group, in a house group, out at x = 20 so a
## mirror across x = 0 lands clear of it.
func _house(level: Node) -> Array:
	var roof_a = rig.box(level, "roof_a", Vector3(20, 6, 0))
	var roof_b = rig.box(level, "roof_b", Vector3(24, 6, 0))
	var wall_a = rig.box(level, "wall_a", Vector3(20, 2, 0))
	var wall_b = rig.box(level, "wall_b", Vector3(24, 2, 0))
	await _group(level, [roof_a, roof_b], "Roof")
	await _group(level, [wall_a, wall_b], "Walls")
	await _group(level, [roof_a, wall_a], "House")
	return [roof_a, roof_b, wall_a, wall_b]


func _made_since(level: Node, before: Array) -> Array:
	var out: Array = []
	for brush in level._iter_managed_brush_nodes():
		if not before.has(brush):
			out.append(brush)
	return out


## Each of `nodes` with the groups it is in, inner first, as one string, sorted.
func _chains(level: Node, nodes: Array) -> Array:
	var out: Array = []
	for node in nodes:
		out.append(" < ".join(level.visgroup_system.group_chain_of(node)))
	out.sort()
	return out


func _assert_house_copy(level: Node, copies: Array, top: String, roof: String, walls: String):
	var system = level.visgroup_system
	assert_eq(copies.size(), 4, "four copies")
	assert_eq(system.parent_of_group(roof), top, "the roof's copy is inside the house's")
	assert_eq(system.parent_of_group(walls), top, "and so is the walls'")
	assert_eq(system.parent_of_group(top), "", "the house's copy is at the top")
	assert_eq(
		_chains(level, copies),
		[
			"%s < %s" % [roof, top],
			"%s < %s" % [roof, top],
			"%s < %s" % [walls, top],
			"%s < %s" % [walls, top],
		],
		"each copy in the copy of its group"
	)
	assert_eq(system.group_members_deep("House").size(), 4, "the house keeps its own four")


func test_copy_and_paste_of_a_whole_nested_group_makes_its_own_group_as_duplicate_does():
	var level = await _level()
	var parts: Array = await _house(level)
	await _select([parts[0]])
	assert_eq(_selected().size(), 4, "fixture: a click takes the whole house")
	assert_true(HFPluginEditActions.copy_selection(rig.plugin, level))
	var steps: int = rig.undo().step_count()
	assert_true(HFPluginEditActions.paste_clipboard(rig.plugin, level))
	assert_eq(rig.undo().step_count(), steps + 1, "one undo step")
	var copies := _made_since(level, parts)
	_assert_house_copy(level, copies, "House copy", "Roof copy", "Walls copy")
	await _select([copies[0]])
	assert_eq(_selected().size(), 4, "a click on a copy picks the copies")
	for node in _selected():
		assert_false(parts.has(node), "and none of the originals")
	rig.undo().press_undo()
	await rig.frame()
	assert_false(level.visgroup_system.groups.has("House copy"), "undo takes the groups away")
	assert_false(level.visgroup_system.groups.has("Roof copy"))
	rig.undo().press_redo()
	await rig.frame()
	_assert_house_copy(level, _made_since(level, parts), "House copy", "Roof copy", "Walls copy")
	await rig.leave_level(level)


func test_paste_of_one_member_of_an_open_group_joins_it_in_its_own_level_only():
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	var b = rig.box(level, "b", Vector3(6, 2, 0))
	await _group(level, [a, b], "Pair")
	await _select([a])
	HFPluginGroups.open_selected_group(rig.plugin, level)
	await _select([a])
	assert_eq(_selected(), [a], "fixture: the open group gives one member")
	assert_true(HFPluginEditActions.copy_selection(rig.plugin, level))
	assert_true(HFPluginEditActions.paste_clipboard(rig.plugin, level))
	var copy: Node = _made_since(level, [a, b])[0]
	assert_eq(level.visgroup_system.get_group_of(copy), "Pair", "the copy joins the group")
	assert_eq(
		level.visgroup_system.get_group_names(), PackedStringArray(["Pair"]), "and makes none"
	)
	var uid: String = level.level_uid
	await rig.leave_level(level)

	# Another level with a group of the same name is not the same group.
	var other = await _level()
	assert_ne(other.level_uid, uid, "fixture: another level")
	var c = rig.box(other, "c", Vector3(0, 2, 0))
	var d = rig.box(other, "d", Vector3(6, 2, 0))
	await _group(other, [c, d], "Pair")
	assert_true(HFPluginEditActions.paste_clipboard(rig.plugin, other))
	var pasted: Node = _made_since(other, [c, d])[0]
	assert_eq(other.visgroup_system.get_group_of(pasted), "", "in no group in another level")
	assert_eq(other.visgroup_system.group_members_deep("Pair").size(), 2, "Pair keeps its own two")
	await rig.leave_level(other)


func test_paste_in_another_level_brings_the_whole_groups_it_took():
	var level = await _level()
	var parts: Array = await _house(level)
	await _select([parts[0]])
	assert_true(HFPluginEditActions.copy_selection(rig.plugin, level))
	await rig.leave_level(level)
	var other = await _level()
	assert_true(HFPluginEditActions.paste_clipboard(rig.plugin, other))
	var copies: Array = other._iter_managed_brush_nodes()
	assert_eq(copies.size(), 4)
	var system = other.visgroup_system
	assert_eq(system.parent_of_group("Roof copy"), "House copy", "nested as they were")
	assert_eq(system.group_members_deep("House copy").size(), 4)
	await rig.leave_level(other)


func test_mirror_copy_of_a_whole_group_makes_a_group_of_its_own():
	var level = await _level()
	var parts: Array = await _house(level)
	level.mirror_copy_axes = 1
	level.mirror_copy_at_edge = false
	await _select([parts[0]])
	var steps: int = rig.undo().step_count()
	assert_true(HFPluginEditActions.mirror_copy_selected(rig.plugin, level))
	assert_eq(rig.undo().step_count(), steps + 1, "one undo step")
	var copies := _made_since(level, parts)
	_assert_house_copy(level, copies, "House copy", "Roof copy", "Walls copy")
	await _select([parts[0]])
	assert_eq(_selected().size(), 4, "a click on the original picks the original")
	for node in _selected():
		assert_true(parts.has(node), "and none of the mirrored half")
	rig.undo().press_undo()
	await rig.frame()
	assert_false(level.visgroup_system.groups.has("House copy"), "undo takes the group away")
	await rig.leave_level(level)


func test_a_prefab_of_a_nested_group_places_with_its_inner_groups():
	var level = await _level()
	var parts: Array = await _house(level)
	var path: String = level.prefab_system.quick_save_prefab(parts, [], "Group Copies House")
	assert_ne(path, "", "fixture: the prefab saved")
	var prefab := HFPrefab.load_from_file(path)
	assert_eq(prefab.groups.size(), 3, "the file holds the three groups")
	var placed: Dictionary = level.prefab_system.place(
		prefab, path, Transform3D(Basis.IDENTITY, Vector3(0, 0, 30))
	)
	assert_false(placed.is_empty(), "placed")
	var copies := _made_since(level, parts)
	# The level has the names already, so the copy's are made unique.
	_assert_house_copy(level, copies, "House 2", "Roof 2", "Walls 2")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await rig.leave_level(level)


func test_a_prefab_places_its_groups_under_their_own_names_in_a_level_without_them():
	var level = await _level()
	var parts: Array = await _house(level)
	var path: String = level.prefab_system.quick_save_prefab(parts, [], "Group Copies Shed")
	await rig.leave_level(level)
	var other = await _level()
	var prefab := HFPrefab.load_from_file(path)
	other.prefab_system.place(prefab, path, Transform3D.IDENTITY)
	var system = other.visgroup_system
	assert_eq(system.parent_of_group("Roof"), "House")
	assert_eq(system.parent_of_group("Walls"), "House")
	assert_eq(system.group_members_deep("House").size(), 4)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await rig.leave_level(other)


func test_a_prefab_of_part_of_a_group_puts_its_pieces_in_no_group():
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	var b = rig.box(level, "b", Vector3(6, 2, 0))
	await _group(level, [a, b], "Pair")
	var path: String = level.prefab_system.quick_save_prefab([a], [], "Group Copies Half")
	var prefab := HFPrefab.load_from_file(path)
	assert_eq(prefab.groups, [], "no group taken whole")
	assert_false(prefab.brush_infos[0].has("group_id"), "and the level's group is not named")
	level.prefab_system.place(prefab, path, Transform3D(Basis.IDENTITY, Vector3(0, 0, 20)))
	var copy: Node = _made_since(level, [a, b])[0]
	assert_eq(level.visgroup_system.get_group_of(copy), "", "the copy is in no group")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await rig.leave_level(level)


func test_pasted_groups_come_back_the_same_after_a_save_and_a_load():
	var level = await _level()
	var parts: Array = await _house(level)
	await _select([parts[0]])
	assert_true(HFPluginEditActions.copy_selection(rig.plugin, level))
	assert_true(HFPluginEditActions.paste_clipboard(rig.plugin, level))
	assert_eq(level.save_hflevel(SAVE_PATH, true), OK)
	await rig.leave_level(level)
	var other = await _level()
	assert_true(other.load_hflevel(SAVE_PATH))
	var system = other.visgroup_system
	assert_eq(system.parent_of_group("Roof copy"), "House copy")
	assert_eq(system.parent_of_group("Walls copy"), "House copy")
	assert_eq(system.group_members_deep("House copy").size(), 4)
	assert_eq(system.group_members_deep("House").size(), 4)
	await rig.leave_level(other)


func test_a_prefab_file_from_before_groups_places_as_it_did():
	var prefab := (
		HFPrefab
		. from_dict(
			{
				"prefab_name": "Old",
				"brush_infos":
				[{"shape": 0, "size": {"__type": "Vector3", "x": 2, "y": 2, "z": 2}}],
				"entity_infos": [],
			}
		)
	)
	assert_eq(prefab.groups, [], "no groups in a file without the key")
	assert_eq(prefab.source_level, "")
	var data := prefab.to_dict()
	assert_false(data.has("groups"), "and none written back")
	assert_false(data.has("source_level"))
