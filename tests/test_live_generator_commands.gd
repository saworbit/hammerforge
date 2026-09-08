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
	for method_name in ['"create_arch"', '"regenerate_generator"', '"detach_generator"']:
		assert_true(
			source.contains(method_name), "the dock must reach %s through undo" % method_name
		)
	assert_false(
		source.contains("level_root.generator_system.regenerate"),
		"a change that skipped undo would be unrecoverable"
	)


func test_the_arch_section_becomes_an_editor_when_a_piece_is_selected():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	var start := source.find("static func refresh_arch_section")
	assert_gt(start, -1, "the section must refresh with the selection")
	var body := source.substr(start, 1400)
	assert_true(body.contains("generator_for_selection"), "it asks the record what is selected")
	assert_true(body.contains('"Update Arch"'), "and says so on the button")
	assert_true(body.contains('"Create Arch"'), "and switches back when nothing is selected")
	assert_true(body.contains("arch_detach_btn"), "a way out is offered beside the way in")


func test_the_section_refreshes_from_the_docks_one_selection_hook():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var start := source.find("func set_selection_nodes")
	assert_gt(start, -1)
	var body := source.substr(start, 1600)
	assert_true(
		body.contains("refresh_arch_section()"),
		"the Arch section must follow the selection like the other contextual UI"
	)


func test_update_and_create_are_the_same_button_taking_different_paths():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	var start := source.find("static func on_create_arch")
	var body := source.substr(start, 1600)
	assert_lt(
		body.find("_active_generator_id"),
		body.find('"create_arch"'),
		"an existing structure is updated rather than duplicated"
	)


func test_settings_load_without_firing_the_controls_they_land_in():
	# Writing a value back into a SpinBox must not read as the user changing it.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	var start := source.find("static func _load_arch_settings")
	assert_gt(start, -1)
	var body := source.substr(start, 800)
	assert_true(body.contains("set_value_no_signal"), body)


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
	# The type table is the seam. If a second generator arrives it should need a
	# branch in these three and nothing else.
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_generator_system.gd"
	)
	for name in ["func known_types", "func default_settings", "func build_faces", "func validate"]:
		assert_true(source.contains(name), "%s must stay the seam" % name)
	assert_eq(
		Array(HFGeneratorSystemScript.known_types()),
		["arch"],
		"update this test deliberately when a second generator lands"
	)
