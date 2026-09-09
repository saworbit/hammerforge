extends GutTest

## What an Update to an array would undo, said before it undoes it.
##
## Live arrays gave the section an Update button. Nothing said that pressing it
## throws away a copy you had dragged somewhere on purpose — Detach sat beside it
## as the way out, but a choice you do not know you are making is not a choice.
##
## The reading is a vote, for the same reason the structure records are: a source
## that has been dragged leaves every copy needing the same move, and calling that
## twelve hand edits would be a lie.

const DockScene = preload("res://addons/hammerforge/dock.tscn")

var dock: HammerForgeDock
var root: LevelRoot


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root


func after_each() -> void:
	dock = null
	root = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _a_brush(at: Vector3 = Vector3.ZERO) -> Node3D:
	var brush_id: String = root.brush_system._next_brush_id()
	var made = (
		root
		. brush_system
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(32, 32, 32),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": brush_id,
				"transform": Transform3D(Basis.IDENTITY, at),
			}
		)
	)
	assert_not_null(made, "the fixture needs a brush to copy")
	return made


func _select(nodes: Array) -> void:
	dock.set_selection_nodes(nodes)


func _id_of(brush: Node3D) -> String:
	return str(root.get_brush_info_from_node(brush).get("brush_id", ""))


func _make_array(source: Node3D, count: int = 3) -> HFDuplicator:
	_select([source])
	dock.dup_mode_opt.selected = 0
	HFDockBrushHandler.on_duplicate_array_mode_changed(dock, 0)
	dock.dup_count_spin.set_value_no_signal(float(count))
	dock.dup_offset_x.set_value_no_signal(64.0)
	dock.dup_offset_y.set_value_no_signal(0.0)
	dock.dup_offset_z.set_value_no_signal(0.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	var record = root.duplicator_for_selection([_id_of(source)])
	assert_not_null(record, "the fixture needs an array to warn about")
	return record


func _copies(record: HFDuplicator) -> Array:
	var out: Array = []
	for brush_id in record.get_all_instance_ids():
		var brush = root.brush_system.find_brush_by_id(brush_id)
		if is_instance_valid(brush):
			out.append(brush)
	return out


func _drag(brush: Node3D, by: Vector3) -> void:
	brush.global_position += by


func _warning() -> String:
	return dock.dup_warning.text if (dock.dup_warning and dock.dup_warning.visible) else ""


func _brush_count() -> int:
	return root.draft_brushes_node.get_child_count()


# ===========================================================================
# Reading what has happened to the copies
# ===========================================================================


func test_an_untouched_array_has_nothing_to_say():
	var source := _a_brush()
	var record := _make_array(source)
	assert_eq(record.displaced_copy_ids(root.brush_system).size(), 0)
	assert_false(record.copies_follow_a_moved_source(root.brush_system))


func test_a_dragged_copy_is_counted():
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(_copies(record)[0], Vector3(0, 96, 0))
	var strays := record.displaced_copy_ids(root.brush_system)
	assert_eq(strays.size(), 1, "one copy was dragged, and only one")
	assert_eq(str(strays[0]), str(record.get_all_instance_ids()[0]))


func test_two_dragged_copies_are_both_counted():
	var source := _a_brush()
	var record := _make_array(source, 4)
	var copies := _copies(record)
	_drag(copies[0], Vector3(0, 96, 0))
	_drag(copies[1], Vector3(0, 0, 96))
	assert_eq(record.displaced_copy_ids(root.brush_system).size(), 2)


func test_a_copy_moved_a_hair_is_not_a_hand_edit():
	# Float noise in the placement arithmetic must not read as somebody dragging.
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(_copies(record)[0], Vector3(0.0001, 0, 0))
	assert_eq(record.displaced_copy_ids(root.brush_system).size(), 0)


func test_a_moved_source_is_not_twelve_hand_edits():
	# Every copy needs the same move, which is the original having been dragged
	# out from under them rather than anybody editing copies.
	var source := _a_brush()
	var record := _make_array(source, 4)
	_drag(source, Vector3(0, 128, 0))
	assert_eq(
		record.displaced_copy_ids(root.brush_system).size(),
		0,
		"a source that moved is one move, not one per copy"
	)
	assert_true(record.copies_follow_a_moved_source(root.brush_system))


func test_a_moved_source_and_one_dragged_copy_counts_only_the_copy():
	var source := _a_brush()
	var record := _make_array(source, 4)
	_drag(source, Vector3(0, 128, 0))
	_drag(_copies(record)[0], Vector3(0, 0, 256))
	var strays := record.displaced_copy_ids(root.brush_system)
	assert_eq(strays.size(), 1, "the majority carries the array; the odd one out is the edit")
	assert_true(record.copies_follow_a_moved_source(root.brush_system))


func test_an_array_whose_sources_are_gone_says_nothing():
	# The copies and the sources no longer pair up, and guessing the pairing would
	# report every copy in the level as moved.
	var source := _a_brush()
	var record := _make_array(source, 3)
	root.brush_system.delete_brush_by_id(_id_of(source))
	assert_eq(record.displaced_copy_ids(root.brush_system).size(), 0)
	assert_false(record.copies_follow_a_moved_source(root.brush_system))


func test_the_level_root_reports_the_same_counts():
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(_copies(record)[0], Vector3(0, 96, 0))
	assert_eq(root.displaced_array_copies(str(record.duplicator_id)), 1)


func test_an_unknown_array_reports_nothing():
	assert_eq(root.displaced_array_copies("dup_nothing"), 0)
	assert_false(root.array_copies_follow_a_moved_source("dup_nothing"))


# ===========================================================================
# What the section says
# ===========================================================================


func test_the_section_is_quiet_about_an_untouched_array():
	var source := _a_brush()
	var record := _make_array(source, 3)
	_select([_copies(record)[0]])
	assert_eq(_warning(), "")


func test_the_section_names_the_number_of_moved_copies():
	var source := _a_brush()
	var record := _make_array(source, 4)
	_drag(_copies(record)[0], Vector3(0, 96, 0))
	_drag(_copies(record)[1], Vector3(0, 0, 96))
	_select([_copies(record)[2]])
	var text := _warning()
	assert_true(text.contains("2 copies"), "got '%s'" % text)
	assert_true(text.contains("Detach"), "the way out belongs in the sentence: got '%s'" % text)


func test_one_moved_copy_reads_as_one():
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(_copies(record)[0], Vector3(0, 96, 0))
	_select([_copies(record)[1]])
	assert_true(_warning().contains("1 copy has"), "got '%s'" % _warning())


func test_a_moved_source_is_said_differently():
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(source, Vector3(0, 128, 0))
	_select([_copies(record)[0]])
	var text := _warning()
	assert_true(text.contains("original has moved"), "got '%s'" % text)
	assert_false(text.contains("Detach"), "nothing of the user's is lost here: got '%s'" % text)


func test_the_warning_goes_when_the_selection_leaves_the_array():
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(_copies(record)[0], Vector3(0, 96, 0))
	_select([_copies(record)[1]])
	assert_ne(_warning(), "")
	_select([_a_brush(Vector3(500, 0, 500))])
	assert_eq(_warning(), "")


# ===========================================================================
# The second press
# ===========================================================================


func test_the_first_press_of_update_over_a_moved_copy_does_nothing():
	var source := _a_brush()
	var record := _make_array(source, 3)
	var moved: Node3D = _copies(record)[0]
	_drag(moved, Vector3(0, 96, 0))
	var where: Vector3 = moved.global_position
	_select([_copies(record)[1]])
	dock.dup_count_spin.set_value_no_signal(5.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(_brush_count(), 4, "nothing was rebuilt on the first press")
	assert_eq(moved.global_position, where, "and the copy the user placed is still there")


func test_the_second_press_goes_ahead():
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(_copies(record)[0], Vector3(0, 96, 0))
	_select([_copies(record)[1]])
	dock.dup_count_spin.set_value_no_signal(5.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(_brush_count(), 6, "one source and five copies")
	assert_eq(root.duplicator_for_id(str(record.duplicator_id)).count, 5)


func test_changing_the_numbers_after_the_warning_earns_it_again():
	# The second press agrees to one particular rebuild, not to every rebuild from
	# here on.
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(_copies(record)[0], Vector3(0, 96, 0))
	_select([_copies(record)[1]])
	dock.dup_count_spin.set_value_no_signal(5.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	dock.dup_count_spin.set_value_no_signal(6.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(_brush_count(), 4, "the changed numbers have not been agreed to yet")


func test_an_untouched_array_updates_on_the_first_press():
	var source := _a_brush()
	var record := _make_array(source, 3)
	_select([_copies(record)[0]])
	dock.dup_count_spin.set_value_no_signal(5.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(_brush_count(), 6, "there was nothing to warn about")


func test_a_moved_source_updates_on_the_first_press():
	# Following the original is what an array is for, not something to agree to.
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(source, Vector3(0, 128, 0))
	_select([_copies(record)[0]])
	dock.dup_count_spin.set_value_no_signal(4.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(_brush_count(), 5, "one source and four copies")


func test_a_rebuild_puts_the_warning_away():
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(_copies(record)[0], Vector3(0, 96, 0))
	_select([_copies(record)[1]])
	dock.dup_count_spin.set_value_no_signal(5.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(_warning(), "", "the copies are all back in the layout")


func test_detaching_after_the_warning_forgets_the_agreement():
	var source := _a_brush()
	var record := _make_array(source, 3)
	_drag(_copies(record)[0], Vector3(0, 96, 0))
	_select([_copies(record)[1]])
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_ne(dock._array_overwrite_ack, "")
	HFDockBrushHandler.on_detach_duplicate_array(dock)
	assert_eq(dock._array_overwrite_ack, "")
	assert_eq(_warning(), "")
	assert_eq(_brush_count(), 4, "detach deletes nothing")
