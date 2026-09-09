extends GutTest

## An array you made is an array you can change your mind about.
##
## A structure could be reselected, retuned and rebuilt; an array could only be
## created and deleted. The numbers that laid it out were already recorded and
## already serialized — nothing read them back. Selecting any piece of an array
## now turns the Duplicate Array section into an editor for it, Create becomes
## Update, and Detach keeps the copies while forgetting the array.

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


func _brush_count() -> int:
	return root.draft_brushes_node.get_child_count()


## Make an array the way the section makes one, from the selected brush.
func _make_linear_array(source: Node3D, count: int = 3) -> HFDuplicator:
	_select([source])
	dock.dup_mode_opt.selected = 0
	HFDockBrushHandler.on_duplicate_array_mode_changed(dock, 0)
	dock.dup_count_spin.set_value_no_signal(float(count))
	dock.dup_offset_x.set_value_no_signal(64.0)
	dock.dup_offset_y.set_value_no_signal(0.0)
	dock.dup_offset_z.set_value_no_signal(0.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	var record = root.duplicator_for_selection([_id_of(source)])
	assert_not_null(record, "the fixture needs an array to edit")
	return record


func _id_of(brush: Node3D) -> String:
	return str(root.get_brush_info_from_node(brush).get("brush_id", ""))


func _a_copy(record: HFDuplicator) -> Node3D:
	var ids := record.get_all_instance_ids()
	assert_gt(ids.size(), 0, "the array has copies to click on")
	var copy = root.brush_system.find_brush_by_id(ids[0])
	assert_not_null(copy, "a recorded copy is a brush that exists")
	return copy


func _button_text() -> String:
	return dock.dup_create_btn.text if dock.dup_create_btn else ""


func _detach_shown() -> bool:
	return dock.dup_detach_btn.visible if dock.dup_detach_btn else false


# ===========================================================================
# The record answers a selection
# ===========================================================================


func test_the_settings_of_an_array_are_the_numbers_it_was_laid_out_from():
	var dup := HFDuplicator.new()
	dup.count = 5
	dup.offset = Vector3(8, 0, 16)
	dup.axis_index = 2
	dup.step_degrees = 45.0
	dup.rise = 12.0
	dup.pivot = Vector3(100, 0, 100)
	dup.grid_counts = Vector3i(3, 2, 4)
	dup.grid_spacing = Vector3(64, 32, 64)
	var settings := dup.settings()
	assert_eq(int(settings["count"]), 5)
	assert_eq(settings["offset"], Vector3(8, 0, 16))
	assert_eq(int(settings["axis_index"]), 2)
	assert_almost_eq(float(settings["step_degrees"]), 45.0, 0.001)
	assert_almost_eq(float(settings["rise"]), 12.0, 0.001)
	assert_eq(settings["pivot"], Vector3(100, 0, 100))
	assert_eq(settings["counts"], Vector3i(3, 2, 4))
	assert_eq(settings["spacing"], Vector3(64, 32, 64))


func test_a_source_brush_finds_its_array():
	var source := _a_brush()
	var record := _make_linear_array(source)
	assert_eq(
		str(root.duplicator_for_selection([_id_of(source)]).duplicator_id),
		str(record.duplicator_id)
	)


func test_a_copy_finds_its_array_too():
	# The case that never worked. The sources are usually buried under the copies
	# they seeded, so the copy is the piece you can actually click on.
	var source := _a_brush()
	var record := _make_linear_array(source)
	var copy := _a_copy(record)
	var found = root.duplicator_for_selection([_id_of(copy)])
	assert_not_null(found, "clicking a copy has to reach the array it belongs to")
	assert_eq(str(found.duplicator_id), str(record.duplicator_id))


func test_a_brush_belonging_to_no_array_finds_nothing():
	var loose := _a_brush(Vector3(500, 0, 500))
	assert_null(root.duplicator_for_selection([_id_of(loose)]))


func test_an_unknown_array_id_resolves_to_nothing():
	assert_null(root.duplicator_for_id("dup_that_never_existed"))


# ===========================================================================
# The section becomes an editor
# ===========================================================================


func test_selecting_a_copy_turns_create_into_update():
	var source := _a_brush()
	var record := _make_linear_array(source)
	_select([_a_copy(record)])
	assert_eq(_button_text(), "Update Array")
	assert_true(_detach_shown(), "Detach is the way out, and belongs beside Update")


func test_creating_an_array_leaves_the_section_editing_it():
	# Discoverability: the same button says Update one press after it said Create,
	# with the same brush still selected.
	var source := _a_brush()
	_make_linear_array(source)
	assert_eq(_button_text(), "Update Array")
	assert_true(_detach_shown())


func test_selecting_an_unrelated_brush_puts_the_section_back():
	var source := _a_brush()
	var record := _make_linear_array(source)
	_select([_a_copy(record)])
	_select([_a_brush(Vector3(500, 0, 500))])
	assert_eq(_button_text(), "Create Array")
	assert_false(_detach_shown())
	assert_eq(dock._active_duplicator_id, "")


func test_selecting_a_copy_loads_the_arrays_own_numbers():
	var source := _a_brush()
	var record := _make_linear_array(source, 4)
	# Turn the controls to something else, then come back to the array.
	dock.dup_count_spin.set_value_no_signal(1.0)
	dock.dup_offset_x.set_value_no_signal(1.0)
	_select([_a_copy(record)])
	assert_eq(int(dock.dup_count_spin.value), 4)
	assert_almost_eq(float(dock.dup_offset_x.value), 64.0, 0.001)
	assert_eq(int(dock.dup_mode_opt.selected), 0)


func test_a_radial_array_loads_its_layout_and_shows_its_own_row():
	var source := _a_brush()
	_select([source])
	dock.dup_mode_opt.selected = 1
	HFDockBrushHandler.on_duplicate_array_mode_changed(dock, 1)
	dock.dup_count_spin.set_value_no_signal(3.0)
	dock.dup_step_spin.set_value_no_signal(90.0)
	dock.dup_rise_spin.set_value_no_signal(8.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	var record = root.duplicator_for_selection([_id_of(source)])
	assert_not_null(record)
	# Come back to it from a control set to the linear layout.
	dock.dup_mode_opt.selected = 0
	HFDockBrushHandler.on_duplicate_array_mode_changed(dock, 0)
	_select([_a_copy(record)])
	assert_eq(int(dock.dup_mode_opt.selected), 1)
	assert_almost_eq(float(dock.dup_step_spin.value), 90.0, 0.001)
	assert_almost_eq(float(dock.dup_rise_spin.value), 8.0, 0.001)
	assert_true(dock.dup_radial_row.visible, "the radial row belongs to the radial layout")


func test_a_grid_array_loads_its_spacing_into_the_offset_controls():
	var source := _a_brush()
	_select([source])
	dock.dup_mode_opt.selected = 2
	HFDockBrushHandler.on_duplicate_array_mode_changed(dock, 2)
	dock.dup_grid_x.set_value_no_signal(2.0)
	dock.dup_grid_y.set_value_no_signal(1.0)
	dock.dup_grid_z.set_value_no_signal(2.0)
	dock.dup_offset_x.set_value_no_signal(96.0)
	dock.dup_offset_y.set_value_no_signal(0.0)
	dock.dup_offset_z.set_value_no_signal(96.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	var record = root.duplicator_for_selection([_id_of(source)])
	assert_not_null(record)
	dock.dup_offset_x.set_value_no_signal(0.0)
	_select([_a_copy(record)])
	assert_eq(int(dock.dup_mode_opt.selected), 2)
	assert_almost_eq(
		float(dock.dup_offset_x.value), 96.0, 0.001, "grid spacing shares the offset row"
	)
	assert_eq(int(dock.dup_grid_z.value), 2)


func test_loading_an_array_clears_the_fill_360_box():
	# Fill 360 is a way of arriving at a step, not something the array remembers.
	# Leaving it ticked would recompute the step from the count on the next Update
	# and quietly move every copy.
	var source := _a_brush()
	var record := _make_linear_array(source)
	dock.dup_fill_check.set_pressed_no_signal(true)
	_select([_a_copy(record)])
	assert_false(dock.dup_fill_check.button_pressed)


func test_refreshing_the_section_with_nothing_selected_is_quiet():
	_select([])
	HFDockBrushHandler.refresh_array_section(dock)
	assert_eq(_button_text(), "Create Array")
	assert_false(_detach_shown())


# ===========================================================================
# Update
# ===========================================================================


func test_update_rebuilds_the_copies_at_the_new_count():
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	assert_eq(_brush_count(), 4, "one source and three copies")
	_select([_a_copy(record)])
	dock.dup_count_spin.set_value_no_signal(6.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(_brush_count(), 7, "one source and six copies")


func test_update_keeps_the_same_array():
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	var before := str(record.duplicator_id)
	_select([_a_copy(record)])
	dock.dup_count_spin.set_value_no_signal(5.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(dock._active_duplicator_id, before, "an update is not a second array")
	var after = root.duplicator_for_id(before)
	assert_not_null(after, "the record survives its own rebuild")
	assert_eq(after.count, 5)
	assert_eq(after.get_all_instance_ids().size(), 5)


func test_update_can_be_pressed_twice_without_reselecting():
	# The first Update frees the copy that was selected, so the second press is
	# the one that used to find nothing to update and quietly make a second array.
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	_select([_a_copy(record)])
	dock.dup_count_spin.set_value_no_signal(5.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(_button_text(), "Update Array", "the section is still editing the same array")
	dock.dup_count_spin.set_value_no_signal(2.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(_brush_count(), 3, "one source and two copies")
	assert_eq(dock._active_duplicator_id, str(record.duplicator_id))


func test_update_can_change_the_layout():
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	_select([_a_copy(record)])
	dock.dup_mode_opt.selected = 1
	HFDockBrushHandler.on_duplicate_array_mode_changed(dock, 1)
	dock.dup_count_spin.set_value_no_signal(3.0)
	dock.dup_step_spin.set_value_no_signal(90.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	var after = root.duplicator_for_id(str(record.duplicator_id))
	assert_not_null(after)
	assert_eq(after.mode, HFDuplicator.ArrayMode.RADIAL)
	assert_eq(_brush_count(), 4)


func test_the_copies_of_a_rebuilt_array_still_say_what_they_belong_to():
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	_select([_a_copy(record)])
	dock.dup_count_spin.set_value_no_signal(5.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	var after = root.duplicator_for_id(str(record.duplicator_id))
	var found = root.duplicator_for_selection([after.get_all_instance_ids()[0]])
	assert_not_null(found, "a second Update has to be reachable from the new copies")
	assert_eq(str(found.duplicator_id), str(record.duplicator_id))


func test_a_ring_being_rebuilt_turns_about_the_point_it_already_turns_about():
	# The selected piece is a copy off to one side. Taking the pivot from the
	# selection would send the whole ring over there.
	var source := _a_brush(Vector3(128, 0, 0))
	_select([source])
	dock.dup_mode_opt.selected = 1
	HFDockBrushHandler.on_duplicate_array_mode_changed(dock, 1)
	dock.dup_count_spin.set_value_no_signal(3.0)
	dock.dup_step_spin.set_value_no_signal(90.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	var record = root.duplicator_for_selection([_id_of(source)])
	var pivot_before: Vector3 = record.pivot
	_select([_a_copy(record)])
	var params := HFDockBrushHandler.array_params(dock, HFDockBrushHandler.array_source_ids(dock))
	assert_eq(params["pivot"], pivot_before, "the ring keeps its own centre")


func test_an_update_that_would_blow_the_budget_leaves_the_array_alone():
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	var before := _brush_count()
	_select([_a_copy(record)])
	dock.dup_mode_opt.selected = 2
	HFDockBrushHandler.on_duplicate_array_mode_changed(dock, 2)
	dock.dup_grid_x.set_value_no_signal(32.0)
	dock.dup_grid_y.set_value_no_signal(32.0)
	dock.dup_grid_z.set_value_no_signal(32.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_eq(_brush_count(), before, "a refusal must not have deleted the copies first")
	assert_not_null(root.duplicator_for_id(str(record.duplicator_id)))


func test_an_array_whose_sources_are_gone_is_dropped_rather_than_rebuilt_empty():
	# Nothing cleans a duplicator record when a brush is deleted, and the layout
	# calls answer "yes" to having run rather than to having produced anything.
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	var copy := _a_copy(record)
	root.brush_system.delete_brush_by_id(_id_of(source))
	_select([copy])
	dock.dup_count_spin.set_value_no_signal(4.0)
	HFDockBrushHandler.on_create_duplicate_array(dock)
	assert_null(
		root.duplicator_for_id(str(record.duplicator_id)),
		"an array of no copies is not an array to keep offering Update on"
	)
	assert_eq(dock._active_duplicator_id, "")
	assert_eq(_button_text(), "Create Array")


func test_updating_an_array_whose_id_is_unknown_answers_no():
	assert_false(root.update_duplicate_array("dup_nothing", 0, {"count": 2}))


func test_an_array_with_no_sources_cannot_be_rebuilt():
	var dup := HFDuplicator.new()
	assert_false(dup.regenerate(root.brush_system, 0, {"count": 3}))


# ===========================================================================
# Detach and remove
# ===========================================================================


func test_detach_keeps_every_brush():
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	var before := _brush_count()
	_select([_a_copy(record)])
	HFDockBrushHandler.on_detach_duplicate_array(dock)
	assert_eq(_brush_count(), before, "detach is the option that deletes nothing")


func test_detach_forgets_the_array():
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	var copy := _a_copy(record)
	_select([copy])
	HFDockBrushHandler.on_detach_duplicate_array(dock)
	assert_null(root.duplicator_for_id(str(record.duplicator_id)))
	assert_null(
		root.duplicator_for_selection([_id_of(copy)]),
		"a detached copy is ordinary geometry and says so"
	)
	assert_eq(dock._active_duplicator_id, "")
	assert_eq(_button_text(), "Create Array")
	assert_false(_detach_shown())


func test_detaching_an_unknown_array_answers_no():
	assert_false(root.detach_duplicate_array("dup_nothing"))


func test_remove_array_works_from_a_copy():
	# It used to insist on the source brush, and told you the piece you had
	# clicked was "not a duplicator source", which is not a fault the user made.
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	_select([_a_copy(record)])
	HFDockBrushHandler.on_remove_duplicate_array(dock)
	assert_eq(_brush_count(), 1, "the copies go and the source stays")
	assert_null(root.duplicator_for_id(str(record.duplicator_id)))
	assert_eq(dock._active_duplicator_id, "")


func test_removing_an_array_from_a_brush_that_has_none_says_so():
	var loose := _a_brush(Vector3(500, 0, 500))
	_select([loose])
	HFDockBrushHandler.on_remove_duplicate_array(dock)
	assert_eq(_brush_count(), 1)


# ===========================================================================
# Undo, and what survives a state restore
# ===========================================================================


func test_an_update_can_be_undone():
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	var before: Dictionary = root.capture_state()
	root.update_duplicate_array(
		str(record.duplicator_id), 0, {"count": 6, "offset": Vector3(64, 0, 0)}
	)
	assert_eq(_brush_count(), 7)
	root.restore_state(before)
	assert_eq(_brush_count(), 4, "undo puts the three-copy array back")
	var after = root.duplicator_for_id(str(record.duplicator_id))
	assert_not_null(after, "and the array with it")
	assert_eq(after.count, 3)


func test_a_restored_array_is_still_reachable_from_its_copies():
	# A brush info carries neither duplicator tag, so a restore has to put them
	# back or an undo leaves an array whose pieces no longer say what they are.
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	var snapshot: Dictionary = root.capture_state()
	root.restore_state(snapshot)
	var restored = root.duplicator_for_id(str(record.duplicator_id))
	assert_not_null(restored)
	var copy_id: String = restored.get_all_instance_ids()[0]
	var found = root.duplicator_for_selection([copy_id])
	assert_not_null(found, "clicking a copy after an undo still reaches the array")
	assert_eq(str(found.duplicator_id), str(record.duplicator_id))


func test_a_detached_array_stays_detached_through_a_restore():
	var source := _a_brush()
	var record := _make_linear_array(source, 3)
	var copy := _a_copy(record)
	var copy_id := _id_of(copy)
	_select([copy])
	HFDockBrushHandler.on_detach_duplicate_array(dock)
	var snapshot: Dictionary = root.capture_state()
	root.restore_state(snapshot)
	assert_null(root.duplicator_for_id(str(record.duplicator_id)))
	assert_null(root.duplicator_for_selection([copy_id]))
	assert_eq(_brush_count(), 4, "and its brushes are all still there")
