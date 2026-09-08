extends GutTest

## The dock surface live generators are edited through, and the contracts that
## keep it wired.
##
## Regeneration deletes brushes to replace them, so the ordering contracts here —
## validate before deleting, ask the record before switching the button — are the
## ones that stop a bad edit destroying a structure it then fails to rebuild.

const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")


func test_level_root_exposes_the_methods_undo_dispatches_by_name():
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	for method_name in [
		"create_generator", "regenerate_generator", "detach_generator", "generator_for_selection"
	]:
		assert_true(root.has_method(method_name), "LevelRoot must expose %s" % method_name)


func test_the_undo_methods_stay_within_the_helper_argument_limit():
	# HFUndoHelper falls back to a direct, non-undoable call past five arguments.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/level_root.gd")
	for method_name in ["create_generator", "regenerate_generator", "detach_generator"]:
		var start := source.find("func %s(" % method_name)
		assert_gt(start, -1, "%s must exist" % method_name)
		var finish := source.find(")", start)
		var signature := source.substr(start, finish - start)
		assert_lt(signature.count(",") + 1, 6, "%s would drop off the undoable path" % method_name)


func test_the_dock_commits_every_generator_change_through_undo():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	for method_name in ['"create_generator"', '"regenerate_generator"', '"detach_generator"']:
		assert_true(
			source.contains(method_name), "the dock must reach %s through undo" % method_name
		)
	assert_false(
		source.contains("level_root.generator_system.regenerate"),
		"a change that skipped undo would be unrecoverable"
	)


func test_the_structure_section_becomes_an_editor_when_a_piece_is_selected():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	var start := source.find("static func refresh_structure_section")
	assert_gt(start, -1, "the section must refresh with the selection")
	var body := source.substr(start, 1600)
	assert_true(body.contains("generator_for_selection"), "it asks the record what is selected")
	assert_true(body.contains('"Update %s"'), "and says so on the button")
	assert_true(body.contains('"Create %s"'), "and switches back when nothing is selected")
	assert_true(body.contains("structure_detach_btn"), "a way out is offered beside the way in")
	assert_true(
		body.contains("_select_type"), "selecting a dome must not leave the dropdown on arch"
	)


func test_the_section_refreshes_from_the_docks_one_selection_hook():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var start := source.find("func set_selection_nodes")
	assert_gt(start, -1)
	var body := source.substr(start, 1600)
	assert_true(
		body.contains("refresh_structure_section()"),
		"the Structure section must follow the selection like the other contextual UI"
	)


func test_update_and_create_are_the_same_button_taking_different_paths():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	var start := source.find("static func on_create_structure")
	var body := source.substr(start, 1600)
	assert_lt(
		body.find("_active_generator_id"),
		body.find('"create_generator"'),
		"an existing structure is updated rather than duplicated"
	)


func test_settings_load_without_firing_the_controls_they_land_in():
	# Writing a value back into a control must not read as the user changing it.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	var start := source.find("static func _load_structure_settings")
	assert_gt(start, -1)
	var body := source.substr(start, 900)
	assert_true(body.contains("set_value_no_signal"), body)
	assert_true(body.contains("set_pressed_no_signal"), "a checkbox has the same problem")


func test_the_dock_names_no_generator_setting_of_its_own():
	# The whole point of the schema: adding a generator adds no dock code. If the
	# dock knows a setting by name, the next generator will need dock work.
	var dock := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var handler := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	var section := dock.substr(dock.find("func _build_structure_section"), 2600)
	for setting in [
		"radius", "wall_thickness", "arc_degrees", "segments", "tread", "rise", "sweep_degrees"
	]:
		assert_false(section.contains('"%s"' % setting), "the section hard-codes %s" % setting)
		assert_false(handler.contains('"%s"' % setting), "the handler hard-codes %s" % setting)


func test_the_controls_come_from_the_builders_own_description():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	var start := source.find("static func rebuild_structure_fields")
	assert_gt(start, -1, "the fields must be built rather than written")
	var body := source.substr(start, 1600)
	assert_true(body.contains("settings_schema"), "from the schema, not from a list here")
	assert_true(body.contains("structure_fields"), "keyed by setting name")


func test_switching_type_stops_editing_the_selected_structure():
	# Otherwise choosing Dome while an arch is selected would rebuild the arch as
	# a dome, which is not what changing the dropdown means.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	var start := source.find("static func on_structure_type_changed")
	assert_gt(start, -1)
	var finish := source.find("\nstatic func ", start + 1)
	var body := source.substr(start, finish - start)
	assert_lt(
		body.find("_active_generator_id"),
		body.find("rebuild_structure_fields"),
		"the edit target must be dropped before the controls change under it"
	)
	# And it must not go back through the selection, which still holds a piece of
	# the old structure and would put the dropdown straight back where it was.
	assert_eq(
		body.find("refresh_structure_section"),
		-1,
		"picking a type must not be answered by re-deriving it from the selection"
	)
	assert_true(body.contains("Create %s"), "the button follows the choice immediately")


func test_the_section_warns_before_it_rebuilds_over_hand_edits():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	assert_true(
		source.contains("_show_edit_warning"), "a rebuild that loses work must say so first"
	)
	assert_true(
		source.contains("edited_generator_pieces"), "the count comes from the record, not a guess"
	)
	var start := source.find("static func _show_edit_warning")
	var body := source.substr(start, 700)
	assert_true(body.contains("Detach"), "the warning must name the way out")


func test_level_root_answers_how_many_pieces_have_been_edited():
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	assert_true(root.has_method("edited_generator_pieces"))
	assert_eq(root.edited_generator_pieces("nothing"), 0, "an unknown structure has no edits")


func test_regeneration_validates_before_it_deletes_anything():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_generator_system.gd"
	)
	var start := source.find("func regenerate(")
	assert_gt(start, -1)
	var body := source.substr(start, 1600)
	assert_lt(
		body.find("validate(record.type, settings)"),
		body.find("_delete_brushes"),
		"an unbuildable change must be refused before the old structure is gone"
	)
	assert_lt(
		body.find("build_faces"),
		body.find("_delete_brushes"),
		"and the replacement must be known to exist first"
	)


func test_deleting_checks_ownership_rather_than_the_list():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_generator_system.gd"
	)
	var start := source.find("func _delete_brushes")
	assert_gt(start, -1)
	var body := source.substr(start, 700)
	assert_true(
		body.contains("get_meta(GENERATOR_META"),
		"a stale id must not let one structure delete another's geometry"
	)


func test_generator_records_are_persisted_beside_the_duplicators():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_state_system.gd"
	)
	assert_true(source.contains('state["generators"]'), "records must travel in the snapshot")
	assert_true(source.contains("generator_system.restore("), "and come back out of it")


func test_adding_a_generator_type_has_one_place_to_do_it():
	# The seam is now a single dispatch: a builder owns its own settings, its own
	# validation and its own arithmetic, and `builder_for()` is the only thing that
	# has to learn it exists. Everything else asks there.
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_generator_system.gd"
	)
	for name in [
		"func known_types",
		"func builder_for",
		"func default_settings",
		"func settings_schema",
		"func build_faces",
		"func validate"
	]:
		assert_true(source.contains(name), "%s must stay the seam" % name)
	assert_eq(
		Array(HFGeneratorSystemScript.known_types()),
		["arch", "stairs", "spiral_stairs", "dome"],
		"update this test deliberately when another generator lands"
	)


func test_every_known_type_is_completely_wired():
	# The failure this catches is a type named in one dispatcher and forgotten in
	# another, which would put an entry in the dock that refuses everything.
	for type in HFGeneratorSystemScript.known_types():
		var name := str(type)
		assert_not_null(HFGeneratorSystemScript.builder_for(name), "%s has no builder" % name)
		var schema: Array = HFGeneratorSystemScript.settings_schema(name)
		var defaults: Dictionary = HFGeneratorSystemScript.default_settings(name)
		assert_gt(schema.size(), 0, "%s describes no settings" % name)
		assert_eq(schema.size(), defaults.size(), "%s describes settings it does not use" % name)
		assert_true(
			HFGeneratorSystemScript.validate(name, defaults).ok,
			"%s cannot build its own defaults" % name
		)
		assert_gt(
			HFGeneratorSystemScript.build_faces(name, defaults).size(),
			0,
			"%s builds nothing from its own defaults" % name
		)
		assert_true(
			HFGeneratorSystemScript.display_name(name) != "", "%s has no name for the dock" % name
		)


func test_each_type_has_a_readable_name_for_the_dropdown():
	# These are the words in the UI, so they are worth pinning rather than
	# trusting a string transformation to keep being right.
	assert_eq(HFGeneratorSystemScript.display_name("arch"), "Arch")
	assert_eq(HFGeneratorSystemScript.display_name("stairs"), "Stairs")
	assert_eq(HFGeneratorSystemScript.display_name("spiral_stairs"), "Spiral Stairs")
	assert_eq(HFGeneratorSystemScript.display_name("dome"), "Dome")


func test_an_unknown_type_is_refused_and_says_what_is_known():
	var result = HFGeneratorSystemScript.validate("gazebo", {})
	assert_false(result.ok)
	assert_true(str(result.fix_hint).contains("arch"), str(result.fix_hint))
	assert_true(str(result.fix_hint).contains("dome"), "the list must be the real one")
