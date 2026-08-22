extends GutTest

const HFDockEntityHandler = preload("res://addons/hammerforge/dock_entity_handler.gd")


func test_handlers_are_noop_without_dock():
	HFDockEntityHandler.on_create_entity(null)
	HFDockEntityHandler.on_io_add(null)
	HFDockEntityHandler.on_io_remove(null)
	HFDockEntityHandler.clear_entity_props(null)
	assert_eq(HFDockEntityHandler.get_default_entity_definition(null), {})


func test_dock_wrappers_delegate_to_entity_handler():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	for method_name in [
		"_rebuild_entity_props",
		"_on_entity_prop_changed",
		"_can_edit_selected_entity",
		"_on_create_entity",
		"_on_io_add",
		"_on_io_remove",
		"_refresh_io_list",
	]:
		var block := _function_source(source, method_name)
		assert_true(
			block.contains("HFDockEntityHandler."),
			"%s must delegate to HFDockEntityHandler" % method_name
		)
		assert_false(
			block.contains("_guard_selection_action("),
			"%s must keep selection guards in the handler" % method_name
		)


func test_entity_handler_keeps_entities_only_guards():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_entity_handler.gd")
	assert_false(source.is_empty(), "dock_entity_handler.gd must be readable")
	for method_name in ["can_edit_selected_entity", "on_io_add", "on_io_remove"]:
		var block := _function_source(source, method_name)
		assert_true(
			block.contains("DockSelectionRequirement.ENTITIES_ONLY"),
			"%s must reject brushes instead of filtering them out" % method_name
		)


func _function_source(source: String, function_name: String) -> String:
	var start := source.find("func %s(" % function_name)
	if start < 0:
		return ""
	var next_function := source.find("\nstatic func ", start + 1)
	if next_function < 0:
		next_function = source.find("\nfunc ", start + 1)
	return (
		source.substr(start) if next_function < 0 else source.substr(start, next_function - start)
	)
