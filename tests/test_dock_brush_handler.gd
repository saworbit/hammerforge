extends GutTest

const HFDockBrushHandler = preload("res://addons/hammerforge/dock_brush_handler.gd")


func test_handlers_are_noop_without_dock():
	HFDockBrushHandler.on_disp_create(null)
	HFDockBrushHandler.on_hollow(null)
	HFDockBrushHandler.on_clip(null)
	HFDockBrushHandler.on_tie_entity(null)
	assert_eq(HFDockBrushHandler.get_hollow_thickness(null), 4.0)


func test_dock_wrappers_delegate_to_brush_handler():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	for method_name in [
		"_on_disp_create",
		"_on_disp_destroy",
		"_on_hollow",
		"_on_clip",
		"_on_move_to_floor",
		"_on_tie_entity",
		"_on_bevel_edge",
	]:
		var block := _function_source(source, method_name)
		assert_true(
			block.contains("HFDockBrushHandler."),
			"%s must delegate to HFDockBrushHandler" % method_name
		)
		assert_false(
			block.contains("_guard_selection_action("),
			"%s must keep selection guards in the handler" % method_name
		)


func test_brush_handler_keeps_brushes_only_guards():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	assert_false(source.is_empty(), "dock_brush_handler.gd must be readable")
	for method_name in [
		"on_hollow",
		"on_clip",
		"on_move_to_floor",
		"on_move_to_ceiling",
		"on_create_duplicate_array",
		"on_remove_duplicate_array",
		"on_tie_entity",
		"on_untie_entity",
		"on_disp_create",
		"on_bevel_edge",
	]:
		var block := _function_source(source, method_name)
		assert_true(
			block.contains("DockSelectionRequirement.BRUSHES_ONLY"),
			"%s must reject entities instead of filtering them out" % method_name
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
