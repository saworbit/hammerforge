extends GutTest

const HFDockConnections = preload("res://addons/hammerforge/dock_connections.gd")
const HFDockFileHandler = preload("res://addons/hammerforge/dock_file_handler.gd")
const HFDockVisgroupHandler = preload("res://addons/hammerforge/dock_visgroup_handler.gd")


class SignalRoot:
	extends Node

	signal bake_started
	signal bake_progress(value, label)
	signal bake_finished(success)
	signal grid_snap_changed(value)
	signal autosave_failed(message)
	signal hflevel_save_completed(path)
	signal hflevel_save_failed(path, message)
	signal paint_layer_changed(index)
	signal material_list_changed
	signal selection_changed(ids)
	signal face_selection_changed
	signal user_message(text, level)


class SignalDock:
	extends RefCounted

	var connected_root: Node
	var root_properties := {}
	var _hints_dirty := false
	var setup_calls := 0
	var callback_calls := 0

	func _cache_root_properties():
		setup_calls += 1

	func _sync_grid_snap_from_root():
		setup_calls += 1

	func _sync_grid_settings_from_root():
		setup_calls += 1

	func _refresh_paint_layers():
		setup_calls += 1

	func _sync_materials_from_root():
		setup_calls += 1

	func _sync_surface_paint_from_root():
		setup_calls += 1

	func _apply_ui_state_to_root():
		setup_calls += 1

	func _setup_io_wiring_panel():
		setup_calls += 1

	func _on_bake_started():
		callback_calls += 1

	func _on_bake_progress(_value, _label):
		callback_calls += 1

	func _on_bake_finished(_success):
		callback_calls += 1

	func _on_root_grid_snap_changed(_value):
		callback_calls += 1

	func _on_autosave_failed(_message):
		callback_calls += 1

	func _on_hflevel_save_completed(_path):
		callback_calls += 1

	func _on_hflevel_save_failed(_path, _message):
		callback_calls += 1

	func _on_root_paint_layer_changed(_index):
		callback_calls += 1

	func _on_root_material_list_changed():
		callback_calls += 1

	func _on_root_selection_for_surface(_ids):
		callback_calls += 1

	func _on_root_face_selection_changed():
		callback_calls += 1

	func _on_root_user_message(_text, _level):
		callback_calls += 1


class DialogReceiver:
	extends RefCounted

	var selected_paths: Array[String] = []

	func on_file_selected(path: String) -> void:
		selected_paths.append(path)


class FileDock:
	extends RefCounted

	var level_root = null
	var statuses: Array = []

	func _set_status(message: String, is_error: bool = false, timeout: float = 0.0) -> void:
		statuses.append([message, is_error, timeout])

	func show_toast(_message: String, _level: int = 0) -> void:
		pass


class VisgroupDock:
	extends RefCounted

	var visgroup_list: ItemList
	var level_root = null


func test_root_connections_are_idempotent_and_disconnect_cleanly() -> void:
	var root := SignalRoot.new()
	var dock := SignalDock.new()
	dock.connected_root = root
	HFDockConnections.connect_root(dock)
	HFDockConnections.connect_root(dock)
	assert_eq(root.get_signal_connection_list("bake_started").size(), 1)
	assert_eq(root.get_signal_connection_list("user_message").size(), 1)
	root.bake_started.emit()
	root.user_message.emit("hello", 0)
	assert_eq(dock.callback_calls, 2)
	assert_eq(dock.setup_calls, 16, "each explicit connect call refreshes dock state once")
	HFDockConnections.disconnect_root(dock)
	assert_eq(root.get_signal_connection_list("bake_started").size(), 0)
	assert_eq(root.get_signal_connection_list("user_message").size(), 0)
	assert_true(dock._hints_dirty)
	root.free()


func test_dialog_configuration_is_idempotent() -> void:
	var dialog := FileDialog.new()
	var receiver := DialogReceiver.new()
	var callback := Callable(receiver, "on_file_selected")
	var filters := PackedStringArray(["*.map ; Quake Map"])
	HFDockFileHandler._configure_dialog(
		dialog, FileDialog.ACCESS_FILESYSTEM, FileDialog.FILE_MODE_OPEN_FILE, filters, callback
	)
	HFDockFileHandler._configure_dialog(
		dialog, FileDialog.ACCESS_FILESYSTEM, FileDialog.FILE_MODE_OPEN_FILE, filters, callback
	)
	assert_eq(dialog.access, FileDialog.ACCESS_FILESYSTEM)
	assert_eq(dialog.file_mode, FileDialog.FILE_MODE_OPEN_FILE)
	assert_eq(dialog.filters, filters)
	assert_eq(dialog.file_selected.get_connections().size(), 1)
	dialog.file_selected.emit("res://test.map")
	assert_eq(receiver.selected_paths, ["res://test.map"])
	dialog.free()


func test_file_handler_reports_missing_roots_without_side_effects() -> void:
	var dock := FileDock.new()
	HFDockFileHandler.on_hflevel_save_selected(dock, "res://test.hflevel")
	HFDockFileHandler.on_map_export_selected(dock, "res://test.map")
	HFDockFileHandler.on_glb_export_selected(dock, "res://test.glb")
	assert_eq(dock.statuses.size(), 3)
	assert_true(dock.statuses[0][1])
	assert_true(dock.statuses[1][1])
	assert_true(dock.statuses[2][1])


func test_visgroup_name_strips_visibility_prefix() -> void:
	var dock := VisgroupDock.new()
	dock.visgroup_list = ItemList.new()
	dock.visgroup_list.add_item("[H] gameplay")
	dock.visgroup_list.select(0)
	assert_eq(HFDockVisgroupHandler.get_selected_visgroup_name(dock), "gameplay")
	dock.visgroup_list.free()


func test_dock_wrappers_delegate_to_extracted_handlers() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var expectations := {
		"_connect_setting_signals": "HFDockConnections.",
		"_connect_root_signals": "HFDockConnections.",
		"_disconnect_root_signals": "HFDockConnections.",
		"_setup_storage_dialogs": "HFDockFileHandler.",
		"_on_hflevel_save_selected": "HFDockFileHandler.",
		"_on_map_import_selected": "HFDockFileHandler.",
		"_on_glb_export_selected": "HFDockFileHandler.",
		"_setup_visgroup_ui": "HFDockVisgroupHandler.",
		"refresh_visgroup_ui": "HFDockVisgroupHandler.",
		"_on_group_selection": "HFDockVisgroupHandler.",
		"_setup_cordon_ui": "HFDockVisgroupHandler.",
		"_on_cordon_from_selection": "HFDockVisgroupHandler.",
	}
	for method_name in expectations:
		var block := _function_source(source, method_name)
		assert_true(block.contains(expectations[method_name]), "%s delegates" % method_name)
		assert_true(block.count("\n") <= 4, "%s remains a thin wrapper" % method_name)


func test_extracted_handlers_are_noop_without_a_dock() -> void:
	HFDockConnections.connect_root(null)
	HFDockConnections.disconnect_root(null)
	HFDockFileHandler.setup_storage_dialogs(null)
	HFDockFileHandler.on_hflevel_save_selected(null, "")
	HFDockVisgroupHandler.setup_visgroup_ui(null)
	HFDockVisgroupHandler.on_group_selection(null)
	assert_true(true)


func _function_source(source: String, function_name: String) -> String:
	var start := source.find("func %s(" % function_name)
	if start < 0:
		return ""
	var next_function := source.find("\nfunc ", start + 1)
	return (
		source.substr(start) if next_function < 0 else source.substr(start, next_function - start)
	)
