extends GutTest

## The ghost of copies that do not exist yet, and the budget that stops the
## controls describing a hang.
##
## The array section had three layouts, nine numbers between them, and a button
## that turned them into as many brushes as the numbers asked for. A grid of
## thirty-two cells a side asks for thirty-two thousand, and nothing said so
## until they existed.

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


func _a_brush() -> Node3D:
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
				"transform": Transform3D.IDENTITY,
			}
		)
	)
	assert_not_null(made, "the fixture needs a brush to copy")
	return made


func _select(nodes: Array) -> void:
	dock.set_selection_nodes(nodes)


## Ask for the ghost, the way turning any array control does.
func _arm() -> void:
	dock._on_array_setting_changed()


func _copies() -> int:
	return root.array_preview_copies()


func _mode(index: int) -> void:
	dock.dup_mode_opt.selected = index
	HFDockBrushHandler.on_duplicate_array_mode_changed(dock, index)


func _turn(control: SpinBox, value: float) -> void:
	assert_not_null(control, "the section has this control")
	control.value = value


func _message() -> String:
	return dock.dup_summary_label.text if dock.dup_summary_label else ""


func _brush_count() -> int:
	return root.draft_brushes_node.get_child_count()


# ===========================================================================
# The budget
# ===========================================================================


func test_an_ordinary_array_is_allowed():
	assert_true(HFDuplicator.can_generate(8, 1).ok)


func test_nothing_to_copy_is_refused():
	var check: HFOpResult = HFDuplicator.can_generate(8, 0)
	assert_false(check.ok)
	assert_true(check.message.contains("nothing selected"), "got '%s'" % check.message)


func test_a_layout_making_no_copies_is_refused():
	assert_false(HFDuplicator.can_generate(0, 1).ok)


func test_the_budget_is_the_total_brushes_not_the_copy_count():
	# Two hundred copies of one brush is inside it; the same array of two brushes
	# is four hundred brushes and is not.
	assert_true(HFDuplicator.can_generate(200, 1).ok)
	assert_false(HFDuplicator.can_generate(200, 2).ok)


func test_a_refusal_names_the_number_that_was_asked_for():
	var check: HFOpResult = HFDuplicator.can_generate(32767, 1)
	assert_false(check.ok)
	assert_true(
		check.message.contains("32767"),
		(
			"'too many' without a number leaves the user guessing which control to turn: got '%s'"
			% check.message
		)
	)
	assert_ne(check.fix_hint, "")


# ===========================================================================
# Where the copies go
# ===========================================================================


func test_linear_placements_step_further_each_time():
	var placements := HFDuplicator.linear_placements(3, Vector3(10, 0, 0))

	assert_eq(placements.size(), 3)
	for index in placements.size():
		var where: Transform3D = placements[index].applied_to(Transform3D.IDENTITY)
		assert_almost_eq(where.origin.x, 10.0 * float(index + 1), 0.001)


func test_grid_placements_leave_out_the_cell_the_source_is_in():
	var placements := HFDuplicator.grid_placements(Vector3i(2, 2, 2), Vector3(64, 64, 64))

	assert_eq(placements.size(), 7, "a two-cube lattice is eight cells, one of them the original")
	for placement in placements:
		var where: Transform3D = placement.applied_to(Transform3D.IDENTITY)
		assert_gt(where.origin.length(), 0.001, "no copy may land on the source")


func test_radial_placements_turn_further_each_time():
	var placements := HFDuplicator.radial_placements(3, 1, 90.0, Vector3.ZERO, 0.0)

	assert_eq(placements.size(), 3)
	var quarter: Transform3D = placements[0].applied_to(
		Transform3D(Basis.IDENTITY, Vector3(100, 0, 0))
	)
	assert_almost_eq(quarter.origin.z, -100.0, 0.01, "a quarter turn about Y takes +X to -Z")


func test_a_radial_rise_lifts_each_copy_further():
	var placements := HFDuplicator.radial_placements(3, 1, 30.0, Vector3.ZERO, 16.0)

	for index in placements.size():
		var where: Transform3D = placements[index].applied_to(Transform3D.IDENTITY)
		assert_almost_eq(where.origin.y, 16.0 * float(index + 1), 0.001)


func test_a_grid_of_one_cell_makes_no_placements():
	assert_eq(HFDuplicator.grid_placements(Vector3i(1, 1, 1), Vector3(64, 64, 64)).size(), 0)


# ===========================================================================
# The ghost
# ===========================================================================


func test_selecting_a_brush_shows_what_the_array_would_make():
	_select([_a_brush()])
	_arm()

	assert_eq(_copies(), 3, "the default linear array is three copies")
	assert_true(root.array_preview._mesh_instance.visible, "and it is on screen")


func test_the_ghost_says_how_many_copies_of_how_many_brushes():
	_select([_a_brush()])
	_arm()

	assert_eq(_message(), "3 copies of 1 brush", "got '%s'" % _message())


func test_turning_the_count_redraws_the_ghost():
	_select([_a_brush()])
	_arm()

	_turn(dock.dup_count_spin, 7.0)

	assert_eq(_copies(), 7)


func test_switching_to_a_grid_redraws_the_ghost_as_a_lattice():
	_select([_a_brush()])
	_arm()

	_mode(2)

	assert_eq(_copies(), 3, "the default lattice is two by one by two, less the original")


func test_a_grid_beyond_the_budget_draws_nothing_and_says_why():
	_select([_a_brush()])
	_arm()
	_mode(2)

	_turn(dock.dup_grid_x, 32.0)
	_turn(dock.dup_grid_y, 32.0)
	_turn(dock.dup_grid_z, 32.0)

	assert_eq(_copies(), 0, "a ghost of thirty-two thousand brushes is the hang it prevents")
	assert_true(_message().contains("32767"), "got '%s'" % _message())


func test_coming_back_under_the_budget_draws_again():
	_select([_a_brush()])
	_arm()
	_mode(2)
	_turn(dock.dup_grid_x, 32.0)
	_turn(dock.dup_grid_y, 32.0)
	_turn(dock.dup_grid_z, 32.0)

	_turn(dock.dup_grid_y, 1.0)
	_turn(dock.dup_grid_z, 1.0)

	assert_eq(_copies(), 31, "thirty-two cells along one axis, less the original")


func test_selecting_a_brush_alone_does_not_summon_a_ghost():
	# A ghost of three offset copies beside everything you click would be noise.
	# Selecting a brush is not asking about arrays.
	_select([_a_brush()])

	assert_eq(_copies(), 0, "the ghost waits to be asked for")
	assert_eq(_message(), "")


func test_the_ghost_has_to_be_asked_for_again_after_it_is_put_away():
	_select([_a_brush()])
	_arm()
	assert_gt(_copies(), 0)

	dock._on_create_duplicate_array()
	HFDockBrushHandler.refresh_array_preview(dock)

	assert_eq(_copies(), 0, "creating the array is the end of the question it answered")


func test_deselecting_takes_the_ghost_away():
	_select([_a_brush()])
	_arm()
	assert_gt(_copies(), 0)

	_select([])

	assert_eq(_copies(), 0, "an array ghost is a ghost of the selection")
	assert_eq(_message(), "")


func test_leaving_the_build_tab_takes_the_ghost_with_it():
	_select([_a_brush()])
	_arm()

	dock.main_tabs.current_tab = dock.paint_tab.get_index()

	assert_eq(_copies(), 0)


func test_creating_the_array_puts_the_ghost_away():
	_select([_a_brush()])
	_arm()

	dock._on_create_duplicate_array()

	assert_eq(_brush_count(), 4, "one original and three copies")
	assert_eq(_copies(), 0, "the copies are real now")


# ===========================================================================
# The button refuses what the ghost refused
# ===========================================================================


func test_an_array_beyond_the_budget_is_not_built():
	var brush := _a_brush()
	_select([brush])
	_arm()
	_mode(2)
	_turn(dock.dup_grid_x, 32.0)
	_turn(dock.dup_grid_y, 32.0)
	_turn(dock.dup_grid_z, 32.0)

	dock._on_create_duplicate_array()

	assert_eq(_brush_count(), 1, "the level still holds only the original")
	assert_true(
		dock.status_label.text.contains("32767"),
		"and the refusal names the number: got '%s'" % dock.status_label.text
	)


func test_the_ghost_and_the_button_agree_on_the_copy_count():
	_select([_a_brush()])
	_arm()
	_mode(1)
	_turn(dock.dup_count_spin, 5.0)
	var drawn := _copies()

	dock._on_create_duplicate_array()

	assert_eq(drawn, 5, "the ghost drew five")
	assert_eq(_brush_count(), 6, "and five is what was built")


# ===========================================================================
# Lifecycle
# ===========================================================================


func test_a_destroyed_preview_can_be_used_again():
	# Plugin reload tears the systems down and the dock keeps its controls.
	_select([_a_brush()])
	_arm()
	root.array_preview.destroy()

	HFDockBrushHandler.refresh_array_preview(dock)

	assert_gt(_copies(), 0, "it has to rebuild its own nodes rather than draw into a freed one")


func test_the_ghost_leaves_with_the_level_it_was_drawn_in():
	_select([_a_brush()])
	_arm()
	assert_gt(_copies(), 0, "there is something to lose")

	root.get_parent().remove_child(root)

	assert_null(root.array_preview._container, "the overlay went with the level")


func test_a_dock_with_no_level_draws_nothing_rather_than_erroring():
	_select([_a_brush()])
	_arm()
	root.clear_array_preview()
	dock.level_root = null

	HFDockBrushHandler.refresh_array_preview(dock)

	assert_eq(root.array_preview_copies(), 0)
