extends GutTest

## The ghost of a structure that does not exist yet.
##
## Every other way of making geometry shows you the shape while you are still
## choosing it. A structure had numbers and a button, so these check that the
## numbers draw: that the ghost stands where the button would build, that it
## stops standing there once the real thing does, and that settings the builder
## refuses draw nothing and say why rather than leaving an empty viewport.

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
	_choose("arch")
	_open_section()


func after_each() -> void:
	dock = null
	root = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _choose(type: String) -> void:
	for index in dock.structure_type_option.item_count:
		if str(dock.structure_type_option.get_item_metadata(index)) == type:
			dock.structure_type_option.selected = index
			break
	HFDockBrushHandler.on_structure_type_changed(dock)


func _open_section() -> void:
	dock._structure_section.set_expanded(true)
	HFDockBrushHandler.refresh_structure_preview(dock)


## Turn a control the way the user does, signal and all.
func _turn(key: String, value: float) -> void:
	var control = dock.structure_fields.get(key, null)
	assert_not_null(control, "the section has a %s control" % key)
	control.value = value


func _pieces() -> int:
	return root.structure_preview_pieces()


func _ghost() -> MeshInstance3D:
	return root.structure_preview._mesh_instance


func _message() -> String:
	return dock.structure_warning.text if dock.structure_warning else ""


func _generated_brushes() -> Array:
	var out: Array = []
	for generator_id in root.generator_system.generators:
		for brush_id in root.generator_system.generators[generator_id].brush_ids:
			var brush = root.brush_system.find_brush_by_id(str(brush_id))
			if brush != null:
				out.append(brush)
	return out


# ===========================================================================
# The preview system on its own
# ===========================================================================


func test_a_buildable_structure_draws_one_wireframe_per_piece():
	var settings: Dictionary = HFGeneratorSystem.default_settings("stairs")
	settings["steps"] = 7

	var drawn: int = root.preview_structure("stairs", settings, Transform3D.IDENTITY)

	assert_eq(drawn, 7, "a seven-step flight is seven pieces")
	assert_eq(root.structure_preview_pieces(), 7)
	assert_true(root.structure_preview._mesh_instance.visible, "and it is on screen")


func test_the_ghost_stands_where_the_structure_would_be_built():
	var where := Transform3D(Basis.IDENTITY, Vector3(64.0, 32.0, -16.0))

	root.preview_structure("arch", HFGeneratorSystem.default_settings("arch"), where)

	assert_almost_eq(_ghost().global_transform.origin, where.origin, Vector3.ONE * 0.001)


func test_settings_the_builder_refuses_draw_nothing():
	var settings: Dictionary = HFGeneratorSystem.default_settings("arch")
	# Each field is in its own range. The combination leaves no opening.
	settings["wall_thickness"] = settings["radius"]

	var drawn: int = root.preview_structure("arch", settings, Transform3D.IDENTITY)

	assert_eq(drawn, 0)
	assert_eq(root.structure_preview_pieces(), 0)


func test_an_unknown_type_draws_nothing_rather_than_erroring():
	assert_eq(root.preview_structure("zeppelin", {}, Transform3D.IDENTITY), 0)


func test_clearing_hides_the_ghost_and_forgets_the_count():
	root.preview_structure("arch", HFGeneratorSystem.default_settings("arch"), Transform3D.IDENTITY)

	root.clear_structure_preview()

	assert_eq(root.structure_preview_pieces(), 0)
	assert_false(root.structure_preview._container.visible, "the container goes with it")


func test_a_destroyed_preview_can_be_used_again():
	# Plugin reload tears the systems down and the dock keeps its controls.
	root.preview_structure("arch", HFGeneratorSystem.default_settings("arch"), Transform3D.IDENTITY)
	root.structure_preview.destroy()

	var drawn: int = root.preview_structure(
		"arch", HFGeneratorSystem.default_settings("arch"), Transform3D.IDENTITY
	)

	assert_gt(drawn, 0, "it has to rebuild its own nodes rather than draw into a freed one")


func test_destroy_leaves_no_node_behind_in_the_level():
	root.preview_structure("arch", HFGeneratorSystem.default_settings("arch"), Transform3D.IDENTITY)

	root.structure_preview.destroy()

	for child in root.get_children():
		assert_ne(child.name, "StructurePreview", "the overlay must not outlive the system")


# ===========================================================================
# The section that drives it
# ===========================================================================


func test_opening_the_section_shows_what_create_would_build():
	assert_gt(_pieces(), 0, "the section explains itself by drawing")


func test_collapsing_the_section_takes_the_ghost_with_it():
	dock._structure_section.set_expanded(false)
	HFDockBrushHandler.refresh_structure_preview(dock)

	assert_eq(_pieces(), 0)


func test_turning_a_control_redraws_the_ghost():
	_turn("segments", 9.0)

	assert_eq(_pieces(), 9, "an arch is one piece per segment")


func test_switching_type_redraws_the_ghost_as_the_other_thing():
	_choose("stairs")
	_turn("steps", 5.0)

	assert_eq(_pieces(), 5)


func test_settings_that_cannot_build_clear_the_ghost_and_say_why():
	_turn("arc_degrees", 0.0)

	assert_eq(_pieces(), 0, "an empty viewport is not an answer on its own")
	assert_true(_message().contains("arc angle"), "so the section says it: got '%s'" % _message())


func test_a_buildable_setting_takes_the_refusal_back_down():
	_turn("arc_degrees", 0.0)
	_turn("arc_degrees", 180.0)

	assert_gt(_pieces(), 0)
	assert_eq(_message(), "", "the message goes when the reason for it does")


func test_creating_the_structure_puts_the_ghost_away():
	dock._on_create_structure()

	assert_eq(root.generator_count(), 1, "the control case has to build")
	assert_eq(_pieces(), 0, "the real thing is there now")


func test_leaving_the_build_tab_takes_the_ghost_with_it():
	dock.main_tabs.current_tab = dock.paint_tab.get_index()

	assert_eq(_pieces(), 0, "nothing on screen would explain a wireframe from another tab")


func test_detaching_puts_the_ghost_away():
	dock._on_create_structure()
	dock.set_selection_nodes([_generated_brushes()[0]])
	assert_ne(str(dock._active_generator_id), "", "selecting a piece switches to Update")

	dock._on_detach_structure()

	assert_eq(_pieces(), 0)


# ===========================================================================
# Previewing a rebuild of a structure that already exists
# ===========================================================================


func test_selecting_a_piece_previews_the_rebuild_over_the_real_one():
	dock._on_create_structure()
	var generator_id: String = root.generator_system.generators.keys()[0]
	var record = root.generator_for_id(generator_id)

	dock.set_selection_nodes([_generated_brushes()[0]])

	assert_gt(_pieces(), 0, "the ghost comes back for the structure being edited")
	assert_almost_eq(_ghost().global_transform.origin, record.placement.origin, Vector3.ONE * 0.001)


func test_the_rebuild_ghost_follows_a_structure_that_was_moved():
	dock._on_create_structure()
	var generator_id: String = root.generator_system.generators.keys()[0]
	var moved := Vector3(0.0, 0.0, 256.0)
	for brush in _generated_brushes():
		brush.global_transform.origin += moved

	dock.set_selection_nodes([_generated_brushes()[0]])

	assert_almost_eq(_ghost().global_transform.origin, moved, Vector3.ONE * 0.001)
	assert_almost_eq(
		root.generator_rebuild_placement(generator_id).origin, moved, Vector3.ONE * 0.001
	)


func test_the_rebuild_ghost_follows_a_structure_that_was_turned():
	dock._on_create_structure()
	var generator_id: String = root.generator_system.generators.keys()[0]
	var brush_ids := Array(root.generator_system.generators[generator_id].brush_ids)
	var pivot: Vector3 = root.resolve_transform_pivot(brush_ids, [])

	root.rotate_managed_nodes(brush_ids, [], 1, 90.0, pivot)
	dock.set_selection_nodes([_generated_brushes()[0]])

	assert_gt(_pieces(), 0, "the ghost is still drawn")
	assert_almost_eq(
		_ghost().global_transform.basis.x,
		Basis(Vector3.UP, deg_to_rad(90.0)).x,
		Vector3.ONE * 0.01,
		"a ghost that stands square over a structure that does not is the wrong answer"
	)


func test_looking_at_a_refused_rebuild_leaves_the_structure_alone():
	dock._on_create_structure()
	dock.set_selection_nodes([_generated_brushes()[0]])
	var ids_before := Array(root.generator_system.generators.values()[0].brush_ids)

	_turn("arc_degrees", 0.0)

	assert_eq(_pieces(), 0)
	assert_eq(
		Array(root.generator_system.generators.values()[0].brush_ids),
		ids_before,
		"nothing is rebuilt by looking at it"
	)


## The paint warning shares a label with the ghost, and a redraw takes it down.
## An acknowledgement that outlives the sentence asking for it is not one.
func test_looking_away_and_back_makes_the_paint_warning_be_earned_again():
	_turn("segments", 9.0)
	dock._on_create_structure()
	dock.set_selection_nodes([_generated_brushes()[0]])
	root.assign_material_to_faces_by_id(
		str(root.generator_system.generators.values()[0].brush_ids[8]), [0], 7
	)
	_turn("segments", 5.0)
	dock._on_create_structure()
	assert_true(dock.structure_warning.text.contains("Detach"), "the first press warns")

	dock._structure_section.set_expanded(false)
	HFDockBrushHandler.refresh_structure_preview(dock)
	dock._structure_section.set_expanded(true)
	HFDockBrushHandler.refresh_structure_preview(dock)
	dock._on_create_structure()

	assert_eq(
		root.generator_system.generators.values()[0].brush_ids.size(),
		9,
		"a warning the user never saw must not count as having been read"
	)
	assert_true(dock.structure_warning.text.contains("Detach"), "it is said again instead")


func test_the_hand_edit_warning_survives_a_redraw():
	dock._on_create_structure()
	var brushes := _generated_brushes()
	brushes[0].global_transform.origin += Vector3(0.0, 48.0, 0.0)
	dock.set_selection_nodes([brushes[1]])

	_turn("radius", 192.0)

	assert_gt(_pieces(), 0, "the ghost is still drawn")
	assert_true(
		_message().contains("edited by hand"),
		"and the warning it shares a label with is still said: got '%s'" % _message()
	)


func test_a_dock_with_no_level_draws_nothing_rather_than_erroring():
	root.clear_structure_preview()
	dock.level_root = null

	HFDockBrushHandler.refresh_structure_preview(dock)

	assert_eq(root.structure_preview_pieces(), 0, "no level, nothing to stand in")


func test_the_ghost_leaves_with_the_level_it_was_drawn_in():
	# Closing the scene or reloading the plugin takes the LevelRoot out of the
	# tree, and an overlay that outlived it would be a wireframe with no owner.
	assert_gt(_pieces(), 0, "there is something to lose")

	root.get_parent().remove_child(root)

	assert_null(root.structure_preview._container, "the overlay went with the level")
