extends GutTest

const HFDockManageHandler = preload("res://addons/hammerforge/dock_manage_handler.gd")


func test_handlers_are_noop_without_dock():
	HFDockManageHandler.on_bake_dry_run(null)
	HFDockManageHandler.on_validate_level(null)
	HFDockManageHandler.on_spawn_auto_create(null)
	assert_eq(HFDockManageHandler.get_bake_preview_mode(null), 0)
	assert_false(HFDockManageHandler.can_start_bake(null, "Bake"))


func test_dock_wrappers_delegate_to_manage_handler():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	for method_name in [
		"_on_bake",
		"_on_bake_selected",
		"_on_bake_changed",
		"_on_quick_play",
		"_on_quick_play_selected_area",
		"_on_export_playtest",
		"_on_spawn_validate",
		"_can_start_bake",
		"_run_validation",
	]:
		var block := _function_source(source, method_name)
		assert_true(
			block.contains("HFDockManageHandler."),
			"%s must delegate to HFDockManageHandler" % method_name
		)
		assert_false(
			block.contains("_guard_selection_action("),
			"%s must keep selection guards in the handler" % method_name
		)


func test_manage_handler_keeps_brushes_only_guards():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_manage_handler.gd")
	assert_false(source.is_empty(), "dock_manage_handler.gd must be readable")
	for method_name in ["on_bake_selected", "on_quick_play_selected_area"]:
		var block := _function_source(source, method_name)
		assert_true(
			block.contains("DockSelectionRequirement.BRUSHES_ONLY"),
			"%s must reject entities instead of filtering them out" % method_name
		)


func _function_source(source: String, function_name: String) -> String:
	var start := source.find("func %s(" % function_name)
	if start < 0:
		start = source.find("func %s:" % function_name)
	if start < 0:
		return ""
	var next_function := source.find("\nstatic func ", start + 1)
	if next_function < 0:
		next_function = source.find("\nfunc ", start + 1)
	return (
		source.substr(start) if next_function < 0 else source.substr(start, next_function - start)
	)
