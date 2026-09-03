extends GutTest


func test_plugin_managed_edit_callbacks_are_thin_delegates() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for method_name in [
		"delete_selected",
		"duplicate_selected",
		"nudge_selected",
		"group_selected",
		"ungroup_selected",
		"hollow_selected",
		"merge_selected",
		"move_selected_to_floor",
		"move_selected_to_ceiling",
		"move_selected_vertical",
		"clip_selected",
		"carve_selected",
	]:
		assert_true(source.contains("HFPluginEditActions.%s" % method_name))


func test_edit_actions_keep_stable_managed_targets_and_undo_methods() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_edit_actions.gd")
	for contract in [
		"plugin._current_selection_nodes()",
		"plugin._managed_entity_owner(root, node)",
		"root.get_brush_info_from_node(node)",
		"delete_managed_nodes",
		"create_managed_duplicates",
		"nudge_managed_nodes",
		"hollow_brush_by_id",
		"merge_brushes_by_ids",
		"move_brushes_to_floor",
		"move_brushes_to_ceiling",
		"clip_brush_by_id",
		"carve_with_brush",
		'Callable(plugin, "_record_history")',
	]:
		assert_true(source.contains(contract), "%s must remain in the action boundary" % contract)


func test_confirmed_geometry_actions_keep_preview_cleanup_and_dialog_ownership() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_edit_actions.gd")
	assert_eq(source.count("plugin._add_confirmable_dialog(dlg)"), 4)
	for preview_name in ["hollow_preview", "clip_preview", "carve_preview"]:
		assert_true(source.contains("root.%s.show_preview" % preview_name))
		assert_true(source.contains("root.%s.clear()" % preview_name))
	assert_true(source.contains("not is_instance_valid(plugin)"))
	assert_true(source.contains("not is_instance_valid(root)"))
