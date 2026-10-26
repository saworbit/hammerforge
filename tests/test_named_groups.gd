extends GutTest

## Groups you can name, nest, list and open (#1723).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginGroups = preload("res://addons/hammerforge/plugin_groups.gd")
const HFVisgroupSystem = preload("res://addons/hammerforge/systems/hf_visgroup_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

const SAVE_PATH := "user://test_named_groups.hflevel"

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func after_each():
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


func _system(level: Node) -> HFVisgroupSystem:
	return level.visgroup_system


## The name field of the one dialog on screen.
func _name_field() -> LineEdit:
	var dialogs: Array = rig.open_dialogs()
	if dialogs.size() != 1:
		return null
	return dialogs[0].find_child("GroupName", true, false)


## Group what is selected, answering the name question with `group_name`, or
## with the name it offers when that is "".
func _group(level: Node, nodes: Array, group_name := "") -> void:
	await _select(nodes)
	assert_true(HFPluginGroups.group_selected(rig.plugin, level), "fixture: it asks")
	var field := _name_field()
	assert_not_null(field, "fixture: the name question")
	if field and group_name != "":
		field.text = group_name
	await rig.accept_dialogs()


## A house: a roof group and a wall group, in a house group.
func _house(level: Node) -> Dictionary:
	var parts := {
		"roof_a": rig.box(level, "roof_a", Vector3(0, 6, 0)),
		"roof_b": rig.box(level, "roof_b", Vector3(4, 6, 0)),
		"wall_a": rig.box(level, "wall_a", Vector3(0, 2, 0)),
		"wall_b": rig.box(level, "wall_b", Vector3(4, 2, 0)),
	}
	await _group(level, [parts["roof_a"], parts["roof_b"]], "Roof")
	await _group(level, [parts["wall_a"], parts["wall_b"]], "Walls")
	await _group(level, [parts["roof_a"], parts["wall_a"]], "House")
	return parts


func test_a_new_group_takes_the_name_it_offers_or_the_one_typed():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	var b = rig.box(level, "b", Vector3(6, 2, 0))
	var c = rig.box(level, "c", Vector3(12, 2, 0))
	await _select([a, b])
	HFPluginGroups.group_selected(rig.plugin, level)
	assert_eq(_name_field().text, "Group of 2 brushes", "a name from what is selected")
	await rig.accept_dialogs()
	assert_eq(_system(level).get_group_of(a), "Group of 2 brushes")
	await _group(level, [c, a], "Bridge")
	assert_eq(_system(level).get_group_of(c), "Bridge", "the name typed")
	assert_eq(
		_system(level).parent_of_group("Group of 2 brushes"), "Bridge", "a whole group goes in"
	)
	await rig.leave_level(level)


func test_a_group_can_be_renamed_and_the_list_shows_it_with_its_count():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	await _house(level)
	assert_true(HFPluginGroups.rename(rig.plugin, level, "House", "Cottage"))
	var system := _system(level)
	assert_eq(system.parent_of_group("Roof"), "Cottage", "the groups inside follow")
	var dock = rig.plugin.dock
	dock.refresh_visgroup_ui()
	var rows: Array = []
	for i in dock.group_list.item_count:
		rows.append(dock.group_list.get_item_text(i))
	assert_eq(rows, ["Cottage (4)", "    Roof (2)", "    Walls (2)"])
	rig.undo().press_undo()
	await rig.frame()
	assert_true(system.groups.has("House"), "one Ctrl+Z gives the old name back")
	assert_false(HFPluginGroups.rename(rig.plugin, level, "House", "Roof"), "a name taken")
	await rig.leave_level(level)


func test_a_group_of_two_groups_selects_as_one_and_opens_one_level_at_a_time():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var parts: Dictionary = await _house(level)
	await _select([parts["roof_a"]])
	assert_eq(_selected().size(), 4, "a click picks the whole house")
	assert_true(HFPluginGroups.open_selected_group(rig.plugin, level))
	await _select([parts["roof_a"]])
	assert_eq(_selected().size(), 2, "inside the house, the roof")
	assert_true(HFPluginGroups.open_selected_group(rig.plugin, level))
	await _select([parts["roof_a"]])
	assert_eq(_selected(), [parts["roof_a"]], "inside the roof, one piece")
	assert_true(rig.plugin._cancel_escape_step(level), "Escape closes the roof")
	assert_eq(_system(level).open_group, "House", "back in the house")
	assert_eq(_selected().size(), 2, "with the roof selected")
	assert_true(rig.plugin._cancel_escape_step(level))
	assert_eq(_system(level).open_group, "", "and out")
	await rig.leave_level(level)


func test_one_member_of_an_open_group_moves_alone_and_stays_in_it():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	var b = rig.box(level, "b", Vector3(6, 2, 0))
	var outside = rig.box(level, "outside", Vector3(20, 2, 0))
	await _group(level, [a, b], "Pair")
	await _select([a])
	HFPluginGroups.open_selected_group(rig.plugin, level)
	await _select([a])
	assert_almost_eq(
		outside.mesh_instance.transparency, HFVisgroupSystem.LOCKED_FADE, 0.001, "the rest fades"
	)
	assert_eq(a.mesh_instance.transparency, 0.0)
	var home: Vector3 = b.global_position
	rig.plugin._nudge_selected(level, Vector3.UP)
	assert_almost_eq(a.global_position, Vector3(0, 3, 0), Vector3.ONE * 0.001, "a moves")
	assert_eq(b.global_position, home, "b stays")
	assert_eq(_system(level).get_group_of(a), "Pair", "and a is still in the group")
	await _select([outside])
	assert_eq(_system(level).open_group, "", "a pick outside closes it")
	assert_eq(outside.mesh_instance.transparency, 0.0, "and nothing is faded")
	await rig.leave_level(level)


func test_a_double_click_opens_the_group_under_it():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 0, 0))
	var b = rig.box(level, "b", Vector3(-6, 0, 0))
	await _group(level, [a, b], "Pair")
	var at: Vector2 = rig.camera.unproject_position(a.global_position)
	assert_true(HFPluginGroups.open_at(rig.plugin, level, rig.camera, at))
	assert_eq(_system(level).open_group, "Pair")
	assert_eq(_selected(), [a], "and the brush clicked is the selection")
	await rig.leave_level(level)


func test_duplicating_a_whole_group_makes_a_group_of_its_own():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var parts: Dictionary = await _house(level)
	await _select([parts["roof_a"]])
	rig.plugin._duplicate_selected(level)
	var copies: Array = _selected()
	assert_eq(copies.size(), 4)
	var system := _system(level)
	assert_eq(system.selection_unit_of(copies[0]), "House copy", "a group of its own")
	assert_eq(system.parent_of_group("Roof copy"), "House copy", "its groups copied inside it")
	assert_eq(system.group_members_deep("House").size(), 4, "the house keeps its own four")
	await _select([copies[0]])
	assert_eq(_selected().size(), 4, "a click on a copy picks only the copies")
	rig.undo().press_undo()
	await rig.frame()
	assert_false(system.groups.has("House copy"), "undo takes the group away")
	rig.undo().press_redo()
	await rig.frame()
	assert_eq(system.parent_of_group("Roof copy"), "House copy", "and redo makes it again")
	await rig.leave_level(level)


func test_duplicating_inside_an_open_group_adds_to_it():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	var b = rig.box(level, "b", Vector3(6, 2, 0))
	await _group(level, [a, b], "Pair")
	await _select([a])
	HFPluginGroups.open_selected_group(rig.plugin, level)
	await _select([a])
	rig.plugin._duplicate_selected(level)
	var copy: Node = _selected()[0]
	assert_eq(_system(level).get_group_of(copy), "Pair", "the copy joins the group")
	assert_eq(_system(level).get_group_names(), PackedStringArray(["Pair"]), "and makes none")
	await rig.leave_level(level)


func test_ungroup_takes_one_level_apart():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var parts: Dictionary = await _house(level)
	await _select([parts["roof_a"]])
	assert_true(HFPluginGroups.ungroup_selected(rig.plugin, level))
	var system := _system(level)
	assert_false(system.groups.has("House"))
	assert_eq(system.parent_of_group("Roof"), "", "the roof is a group of its own again")
	assert_eq(system.get_group_of(parts["roof_a"]), "Roof")
	await rig.leave_level(level)


func test_add_and_remove_go_through_the_group_picked_in_the_list():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var a = rig.box(level, "a", Vector3(0, 2, 0))
	var b = rig.box(level, "b", Vector3(6, 2, 0))
	var c = rig.box(level, "c", Vector3(12, 2, 0))
	await _group(level, [a, b], "Pair")
	var dock = rig.plugin.dock
	dock.refresh_visgroup_ui()
	dock.group_list.select(0)
	await _select([c])
	assert_true(HFPluginGroups.add_selection_to_group(rig.plugin, level))
	assert_eq(_system(level).get_group_of(c), "Pair", "added")
	_system(level).set_open_group("Pair")
	await _select([c])
	assert_true(HFPluginGroups.remove_selection_from_group(rig.plugin, level))
	assert_eq(_system(level).get_group_of(c), "", "taken out")
	assert_eq(_system(level).get_group_of(a), "Pair", "and the rest left")
	await rig.leave_level(level)


func test_names_and_nesting_survive_a_save_and_a_load():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	await _house(level)
	assert_true(level.live_registries.has("group_parents"), "the scene keeps them too")
	assert_eq(level.save_hflevel(SAVE_PATH, true), OK)
	await rig.leave_level(level)
	var other = await rig.make_level()
	assert_true(other.load_hflevel(SAVE_PATH))
	var system := _system(other)
	assert_eq(system.parent_of_group("Roof"), "House")
	assert_eq(system.parent_of_group("Walls"), "House")
	assert_eq(system.group_members_deep("House").size(), 4)
	await rig.leave_level(other)


func test_a_level_from_before_nesting_reads_as_it_was():
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	var system: HFVisgroupSystem = level.visgroup_system
	system.restore_groups({"group_1": true, "group_2": true}, ["group_1", "group_2"])
	system.restore_group_parents(null)
	assert_eq(system.group_parents, {})
	system.restore_group_parents({"group_1": "group_9", "group_2": "group_1"})
	assert_eq(system.group_parents, {"group_2": "group_1"}, "a parent no group has is dropped")


# ===========================================================================
# The fade follows the open group through edits and undo (#1926, #1928)
# ===========================================================================


func _faded(node) -> bool:
	return node.mesh_instance.transparency > 0.0


## A pair grouped and open, and a brush outside it.
func _open_pair(level: Node) -> Dictionary:
	var parts := {
		"a": rig.box(level, "a", Vector3(0, 2, 0)),
		"b": rig.box(level, "b", Vector3(6, 2, 0)),
		"outside": rig.box(level, "outside", Vector3(20, 2, 0)),
	}
	await _group(level, [parts["a"], parts["b"]], "Pair")
	await _select([parts["a"]])
	HFPluginGroups.open_selected_group(rig.plugin, level)
	assert_true(_faded(parts["outside"]), "fixture: the rest fades")
	return parts


## Ungrouping the open group's last members closes it, and the rest of the level
## was left faded with no group open.
func test_ungrouping_the_open_group_unfades_the_level():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var parts: Dictionary = await _open_pair(level)
	await _select([parts["a"], parts["b"]])
	assert_true(HFPluginGroups.ungroup_selected(rig.plugin, level))
	assert_eq(_system(level).open_group, "", "the group is gone, and closed")
	assert_false(_faded(parts["outside"]), "nothing is faded")
	await rig.leave_level(level)


## A brush added to the open group is inside it, and one removed is outside.
func test_a_brush_added_to_or_taken_from_the_open_group_fades_as_it_should():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var parts: Dictionary = await _open_pair(level)
	var c = rig.box(level, "c", Vector3(12, 2, 0))
	level.add_units_to_group([c], "Pair")
	assert_false(_faded(c), "added, it is inside the open group")
	level.remove_units_from_group([parts["b"]], "Pair")
	assert_true(_faded(parts["b"]), "taken out, it is outside")
	await rig.leave_level(level)


## A brush made while a group is open, as an undo makes one again, is outside it.
func test_a_brush_made_while_a_group_is_open_is_faded():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	await _open_pair(level)
	var late = rig.box(level, "late", Vector3(30, 2, 0))
	assert_true(_faded(late), "faded from the start")
	await rig.leave_level(level)


## Undoing the group that is open closes it. The restore faded the level by the
## open group before it put the groups back, and left every brush faded.
func test_undoing_the_open_group_leaves_nothing_faded():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var parts: Dictionary = await _open_pair(level)
	rig.undo().press_undo()
	await rig.frame()
	assert_eq(_system(level).open_group, "", "the group is gone")
	for key in ["a", "b", "outside"]:
		var node = level.find_brush_by_id(key)
		assert_false(_faded(node), "%s is not faded" % key)
	await rig.leave_level(level)


## A structure's pieces stay hidden under the Structures filter through an undo
## of Detach. The restore reuses the pieces and tags them again, and the walk of
## only the brushes it made did not look at them.
func test_an_undone_detach_hides_the_pieces_under_the_structures_filter():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var made: HFOpResult = level.create_generator(
		"stairs", HFGeneratorSystem.default_settings("stairs"), Transform3D.IDENTITY
	)
	assert_true(made.ok, "fixture: stairs")
	var record = level.generator_system.generators.values()[0]
	var pieces: Array = []
	for brush_id in record.brush_ids:
		pieces.append(level.find_brush_by_id(str(brush_id)))
	level.set_view_filter("structure", true)
	assert_false(pieces[0].visible, "fixture: the filter hides them")
	var before: Dictionary = level.capture_state()
	assert_true(level.detach_generator(str(record.generator_id)))
	assert_true(pieces[0].visible, "detached, they are plain brushes and show")
	level.restore_state(before)
	for piece in pieces:
		assert_false(piece.visible, "the undo makes them a structure again, hidden")
	level.set_view_filter("structure", false)
	await rig.leave_level(level)
