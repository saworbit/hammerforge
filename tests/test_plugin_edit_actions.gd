extends GutTest
## The edit actions plugin.gd offers, run through the real plugin: each reaches
## its command, acts on what is selected, and goes into the history. The history
## shows here through the operation replay overlay, which `_record_history()`
## feeds once the power-user overlays are on.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")
const HFBrushEntityScript = preload("res://addons/hammerforge/hf_brush_entity.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self)
	rig.plugin._install_power_user_overlays()


func after_all():
	await rig.take_down()


func _history_size() -> int:
	return rig.plugin._operation_replay._entries.size()


## The history names recorded since `since`.
func _history_since(since: int) -> Array:
	var names: Array = []
	for entry in rig.plugin._operation_replay._entries.slice(since):
		names.append(entry["name"])
	return names


func _brushes(level: Node) -> int:
	return level.draft_brushes_node.get_child_count()


func _id_of(level: Node, brush: Node) -> String:
	return str(level.get_brush_info_from_node(brush).get("brush_id", ""))


func _showing(preview: Object) -> bool:
	var container: Node3D = preview._preview_container
	return is_instance_valid(container) and container.visible


func test_duplicate_and_delete_act_on_the_selection():
	assert_not_null(rig.plugin, rig.error())
	var level = await rig.make_level()
	var original = rig.box(level, "a", Vector3.ZERO)
	rig.select([original])
	var mark := _history_size()
	assert_true(rig.plugin._duplicate_selected(level), "Duplicate ran")
	assert_eq(_brushes(level), 2, "and made a copy")
	var selected: Array = rig.plugin._current_selection_nodes()
	assert_eq(selected.size(), 1)
	assert_ne(selected[0], original, "the copy is what is selected afterwards")
	var copy_id := _id_of(level, selected[0])
	assert_true(rig.plugin._delete_selected(level), "Delete ran")
	assert_null(level.find_brush_by_id(copy_id), "on the copy")
	assert_not_null(level.find_brush_by_id("a"), "and not on the original")
	assert_eq(_history_since(mark), ["Duplicate Brushes", "Delete Brushes"])
	await rig.leave_level(level)


func test_a_duplicated_entity_brush_is_an_entity_of_its_own():
	var level = await rig.make_level()
	rig.box(level, "a", Vector3.ZERO)
	level.tie_brushes_to_entity(["a"], "func_door", "door_1")
	var original = level.find_brush_by_id("a")
	rig.select([original])
	assert_true(rig.plugin._duplicate_selected(level))
	var copy = rig.plugin._current_selection_nodes()[0]
	assert_eq(HFBrushEntityScript.entity_class(copy), "func_door", "the copy is a door")
	assert_ne(
		HFBrushEntityScript.identity(copy),
		HFBrushEntityScript.identity(original),
		"but not the same door"
	)
	await rig.leave_level(level)


func test_duplicate_and_delete_take_entities_too():
	var level = await rig.make_level()
	var entity = DraftEntityScript.new()
	entity.entity_type = "light_point"
	level.add_entity(entity)
	rig.select([entity])
	var mark := _history_size()
	assert_true(rig.plugin._duplicate_selected(level))
	assert_eq(level.entities_node.get_child_count(), 2, "the entity was copied")
	rig.select([entity])
	assert_true(rig.plugin._delete_selected(level))
	assert_false(is_instance_valid(entity) and entity.is_inside_tree(), "and deleted")
	assert_eq(_history_since(mark), ["Duplicate Entities", "Delete Entities"])
	await rig.leave_level(level)


func test_move_to_floor_ceiling_and_nudge_move_the_selection():
	var level = await rig.make_level()
	# A floor whose top is at 0 and a ceiling whose underside is at 20.
	rig.box(level, "floor", Vector3(0, -1, 0), Vector3(400, 2, 400))
	rig.box(level, "ceiling", Vector3(0, 21, 0), Vector3(400, 2, 400))
	var box = rig.box(level, "a", Vector3(0, 10, 0))
	rig.select([box])
	var mark := _history_size()
	assert_true(rig.plugin._move_selected_to_floor(level))
	assert_almost_eq(box.global_position.y, 2.0, 0.01, "Move to Floor sets it on the floor")
	assert_true(rig.plugin._move_selected_to_ceiling(level))
	assert_almost_eq(box.global_position.y, 18.0, 0.01, "Move to Ceiling puts it up against it")
	assert_true(rig.plugin._nudge_selected(level, Vector3.RIGHT))
	assert_gt(box.global_position.x, 0.0, "Nudge moves it along")
	assert_eq(
		_history_since(mark), ["Move to Floor", "Move to Ceiling", "Nudge HammerForge Objects"]
	)
	await rig.leave_level(level)


func test_a_move_or_reset_that_changes_nothing_leaves_no_step():
	# Move to Floor on a brush already on the floor used to add a "Move to
	# Floor" step, which Ctrl+Z then appeared to do nothing for (#1303).
	var level = await rig.make_level()
	rig.box(level, "floor", Vector3(0, -1, 0), Vector3(400, 2, 400))
	rig.box(level, "ceiling", Vector3(0, 21, 0), Vector3(400, 2, 400))
	var box = rig.box(level, "a", Vector3(0, 10, 0))
	rig.select([box])
	var mark := _history_size()
	assert_true(rig.plugin._move_selected_to_floor(level))
	assert_true(rig.plugin._move_selected_to_floor(level), "the command still runs")
	assert_almost_eq(box.global_position.y, 2.0, 0.01, "and the brush stays on the floor")
	assert_true(rig.plugin._move_selected_to_ceiling(level))
	assert_true(rig.plugin._move_selected_to_ceiling(level))
	assert_true(rig.plugin._reset_rotation_selected(level), "a square brush has nothing to reset")
	assert_eq(
		_history_since(mark),
		["Move to Floor", "Move to Ceiling"],
		"only the presses that moved something are steps"
	)
	level.set_brush_rotation_by_id("a", Vector3(0, 30, 0))
	assert_true(rig.plugin._reset_rotation_selected(level))
	assert_eq(_history_since(mark).back(), "Reset HammerForge Rotation", "a turned one is a step")
	await rig.leave_level(level)


func test_group_ungroup_and_merge_act_on_the_selection():
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(4, 0, 0))
	rig.select([a, b])
	var mark := _history_size()
	assert_true(rig.plugin._group_selected(level))
	var group := str(level.visgroup_system.get_group_of(a))
	assert_ne(group, "", "Group made a group")
	assert_eq(str(level.visgroup_system.get_group_of(b)), group, "of both")
	assert_true(rig.plugin._ungroup_selected(level))
	assert_eq(str(level.visgroup_system.get_group_of(a)), "", "Ungroup took it apart")
	assert_true(rig.plugin._merge_selected(level))
	assert_eq(_brushes(level), 1, "Merge made the two side by side into one")
	assert_eq(_history_since(mark), ["Group Selection", "Ungroup Selection", "Merge Brushes"])
	await rig.leave_level(level)


## Hollow, Clip and Carve show what they would do and ask first; OK commits.
func test_hollow_clip_and_carve_ask_first_and_cut_on_ok():
	var level = await rig.make_level()
	var mark := _history_size()

	rig.select([rig.box(level, "h", Vector3.ZERO, Vector3(8, 8, 8))])
	assert_true(rig.plugin._hollow_selected(level))
	assert_eq(rig.open_dialogs().size(), 1, "Hollow asks first")
	assert_true(_showing(level.hollow_preview), "with the walls on show")
	assert_eq(_brushes(level), 1, "and has cut nothing yet")
	assert_eq(await rig.accept_dialogs(), 1)
	assert_eq(_brushes(level), 6, "OK hollows the box into six walls")
	assert_false(_showing(level.hollow_preview), "and the preview goes")

	var before := _brushes(level)
	rig.select([rig.box(level, "c", Vector3(40, 0, 0), Vector3(8, 8, 8))])
	assert_true(rig.plugin._clip_selected(level))
	assert_true(_showing(level.clip_preview), "Clip shows its pieces")
	assert_eq(await rig.accept_dialogs(), 1, "and asks first")
	assert_eq(_brushes(level), before + 2, "OK splits the box in two")
	assert_false(_showing(level.clip_preview))

	rig.box(level, "target", Vector3(80, 0, 0), Vector3(8, 8, 8))
	rig.select([rig.box(level, "carver", Vector3(84, 0, 0), Vector3(8, 8, 8))])
	assert_true(rig.plugin._carve_selected(level))
	assert_true(_showing(level.carve_preview), "Carve shows its pieces")
	assert_eq(await rig.accept_dialogs(), 1, "and asks first")
	assert_null(level.find_brush_by_id("target"), "OK carves the target into pieces")
	assert_null(level.find_brush_by_id("carver"), "and uses up the carver")
	assert_false(_showing(level.carve_preview))

	assert_eq(_history_since(mark), ["Hollow", "Clip Brush", "Carve"])
	await rig.leave_level(level)


## Every confirmation belongs to the plugin's dialog manager, so a plugin reload
## takes them down; Cancel puts the preview away and changes nothing; and an OK
## pressed after the level has gone does nothing at all.
func test_confirmations_are_owned_and_tidy_up_after_themselves():
	var level = await rig.make_level()
	var hollow_box = rig.box(level, "h", Vector3.ZERO, Vector3(8, 8, 8))
	rig.select([hollow_box])
	rig.plugin._hollow_selected(level)
	var dialog: ConfirmationDialog = rig.open_dialogs()[0]
	dialog.get_cancel_button().pressed.emit()
	assert_false(_showing(level.hollow_preview), "Cancel puts the preview away")
	assert_eq(_brushes(level), 1, "and cuts nothing")
	await rig.frame()

	# One at a time: Godot lets a window hold only one modal child.
	var trio := [
		hollow_box,
		rig.box(level, "b", Vector3(20, 0, 0)),
		rig.box(level, "c", Vector3(40, 0, 0)),
	]
	# Carve asks only when its carver cuts something (#1267), so it gets one that
	# overlaps the first box.
	var carver := rig.box(level, "k", Vector3(3, 0, 0))
	for action in ["hollow", "clip", "carve", "delete"]:
		match action:
			"delete":
				rig.select(trio)
			"carve":
				rig.select([carver])
			_:
				rig.select([hollow_box])
		var managed: int = rig.plugin._dialog_manager.count()
		match action:
			"hollow":
				rig.plugin._hollow_selected(level)
			"clip":
				rig.plugin._clip_selected(level)
			"carve":
				rig.plugin._carve_selected(level)
			"delete":
				rig.plugin._delete_selected(level)
		assert_eq(
			rig.plugin._dialog_manager.count(), managed + 1, "%s's dialog is managed" % action
		)
		rig.plugin._cleanup_pending_dialogs()
		await rig.frame()
		assert_eq(rig.open_dialogs().size(), 0, "and a reload takes %s's down" % action)
	assert_eq(_brushes(level), 4, "having cut and deleted nothing")

	rig.select([hollow_box])
	rig.plugin._hollow_selected(level)
	dialog = rig.open_dialogs()[0]
	rig.select([])
	rig.scene_root.remove_child(level)
	level.free()
	dialog.get_ok_button().pressed.emit()
	await rig.frame()
	assert_eq(rig.open_dialogs().size(), 0, "an OK after the level has gone closes the dialog")
	# The engine says so first, as it hands the closure null for the freed level.
	assert_engine_error("Lambda capture", "the freed level reached the closure as null")
	await rig.leave_level(null)
