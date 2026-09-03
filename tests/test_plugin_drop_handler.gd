extends GutTest

const DropHandler = preload("res://addons/hammerforge/plugin_drop_handler.gd")


func test_drop_data_classification_accepts_only_supported_payloads() -> void:
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_entity"}))
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_brush_preset"}))
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_prefab"}))
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_material"}))
	assert_false(DropHandler.can_drop_data({"type": "files"}))
	assert_false(DropHandler.can_drop_data({}))
	assert_false(DropHandler.can_drop_data(null))


func test_plugin_drop_callbacks_are_thin_delegates() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for method_name in [
		"can_drop_data",
		"drop_data",
		"is_entity_drag_data",
		"handle_entity_drop",
		"is_brush_preset_drag_data",
		"handle_brush_preset_drop",
		"is_prefab_drag_data",
		"handle_prefab_drop",
		"is_material_drag_data",
		"handle_material_drop",
	]:
		assert_true(source.contains("HFPluginDropHandler.%s" % method_name))


func test_drop_handler_keeps_placement_selection_and_undo_contracts() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_drop_handler.gd")
	assert_eq(source.count("root = plugin._create_level_root()"), 3)
	assert_true(source.contains("root.place_entity_at_screen"))
	assert_true(source.contains("plugin.hf_selection.append(entity)"))
	assert_true(source.contains("plugin._commit_brush_placement(root, info)"))
	assert_true(source.contains("prefab.instantiate(root.brush_system, root.entity_system"))
	assert_true(source.contains("root.prefab_system.register_instance"))
	assert_true(source.contains('undo_redo.create_action("Place Prefab:'))
	assert_true(source.contains("root.pick_face(camera, mouse_pos)"))
	assert_true(source.contains('"assign_material_to_faces_by_id"'))
	assert_true(source.contains('Callable(plugin, "_record_history")'))
