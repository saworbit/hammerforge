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
	# Godot calls `_can_drop_data` and `_drop_data` on the plugin, and those two
	# are the whole of the viewport drop path it owns. `drop_data()` dispatches to
	# the four payload kinds itself, so plugin.gd had a second layer of wrappers
	# in front of that dispatch which nothing called (#609).
	#
	# The delegation is asserted on the two entry points that exist, and the
	# absence of the classification is asserted directly. Listing the wrappers was
	# the weaker check: it passed while plugin.gd held a duplicate of the payload
	# logic, which is the thing "thin delegate" is supposed to rule out.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for method_name in ["can_drop_data", "drop_data"]:
		assert_true(
			source.contains("HFPluginDropHandler.%s" % method_name),
			"plugin.gd hands %s straight to the drop handler" % method_name
		)
	for payload in [
		"hammerforge_entity",
		"hammerforge_brush_preset",
		"hammerforge_prefab",
		"hammerforge_material",
	]:
		assert_false(
			source.contains(payload),
			"plugin.gd does not classify %s itself; the drop handler does" % payload
		)


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
