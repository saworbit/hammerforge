@tool
class_name HFDockFileHandler
extends RefCounted
## File dialogs, level import/export, autosave paths, and settings files extracted from dock.gd.


static func setup_storage_dialogs(dock: Object) -> void:
	if dock == null:
		return
	_configure_dialog(
		dock.material_dialog,
		FileDialog.ACCESS_RESOURCES,
		FileDialog.FILE_MODE_OPEN_FILE,
		PackedStringArray(["*.tres ; Material", "*.material ; Material"]),
		Callable(dock, "_on_material_file_selected")
	)
	_configure_dialog(
		dock.hflevel_save_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_SAVE_FILE,
		PackedStringArray(["*.hflevel ; HammerForge Level"]),
		Callable(dock, "_on_hflevel_save_selected")
	)
	_configure_dialog(
		dock.material_palette_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_OPEN_FILE,
		PackedStringArray(
			["*.tres, *.res ; Material", "*.material ; Material", "*.tres ; Resource"]
		),
		Callable(dock, "_on_material_palette_selected")
	)
	_configure_dialog(
		dock.surface_paint_texture_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_OPEN_FILE,
		PackedStringArray(["*.png, *.jpg, *.tres, *.res ; Texture"]),
		Callable(dock, "_on_surface_paint_texture_selected")
	)
	_configure_dialog(
		dock.hflevel_load_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_OPEN_FILE,
		PackedStringArray(["*.hflevel ; HammerForge Level"]),
		Callable(dock, "_on_hflevel_load_selected")
	)
	_configure_dialog(
		dock.map_import_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_OPEN_FILE,
		PackedStringArray(["*.map ; Quake Map"]),
		Callable(dock, "_on_map_import_selected")
	)
	_configure_dialog(
		dock.map_export_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_SAVE_FILE,
		PackedStringArray(["*.map ; Quake Map"]),
		Callable(dock, "_on_map_export_selected")
	)
	_configure_dialog(
		dock.glb_export_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_SAVE_FILE,
		PackedStringArray(["*.glb ; GLB"]),
		Callable(dock, "_on_glb_export_selected")
	)
	_configure_dialog(
		dock.autosave_path_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_SAVE_FILE,
		PackedStringArray(["*.hflevel ; HammerForge Level"]),
		Callable(dock, "_on_autosave_path_selected")
	)
	var settings_filters := PackedStringArray(
		["*.hfsettings ; HammerForge Settings", "*.json ; JSON"]
	)
	_configure_dialog(
		dock.settings_export_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_SAVE_FILE,
		settings_filters,
		Callable(dock, "_on_settings_export_selected")
	)
	_configure_dialog(
		dock.settings_import_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_OPEN_FILE,
		settings_filters,
		Callable(dock, "_on_settings_import_selected")
	)


static func _configure_dialog(
	dialog: FileDialog,
	access: FileDialog.Access,
	file_mode: FileDialog.FileMode,
	filters: PackedStringArray,
	callback: Callable
) -> void:
	if not dialog:
		return
	dialog.access = access
	dialog.file_mode = file_mode
	dialog.filters = filters
	if not dialog.file_selected.is_connected(callback):
		dialog.file_selected.connect(callback)


static func show_dialog(dialog: FileDialog) -> void:
	if dialog:
		dialog.popup_centered_ratio(0.6)


static func on_hflevel_save_selected(dock: Object, path: String) -> void:
	if dock == null:
		return
	if not dock.level_root:
		dock._set_status("No LevelRoot for .hflevel save", true)
		return
	var error := int(dock.level_root.save_hflevel(path, true))
	if error != OK:
		dock._set_status("Failed to save .hflevel", true, 3.0)
		dock.show_toast("Failed to save .hflevel: %s" % path.get_file(), 2)
	else:
		dock._set_status("Saving .hflevel...", false)


static func on_hflevel_load_selected(dock: Object, path: String) -> void:
	if dock == null:
		return
	if path == "" or not FileAccess.file_exists(path):
		dock._set_status("Invalid .hflevel path", true)
		return
	if not dock.level_root:
		dock._set_status("No LevelRoot for .hflevel load", true)
		return
	dock._commit_full_state_action("Load .hflevel", "load_hflevel", [path])
	dock._set_status("Loaded .hflevel", false, 3.0)
	if dock._user_prefs:
		dock._user_prefs.add_recent_file(path)
		dock._user_prefs.save()


static func on_map_import_selected(dock: Object, path: String) -> void:
	if dock == null:
		return
	if path == "" or not FileAccess.file_exists(path):
		dock._set_status("Invalid .map path", true)
		return
	if not dock.level_root:
		dock._set_status("No LevelRoot for .map import", true)
		return
	dock._commit_full_state_action("Import .map", "import_map", [path])
	dock._set_status("Imported .map", false, 3.0)


static func on_map_export_selected(dock: Object, path: String) -> void:
	if dock == null:
		return
	if not dock.level_root:
		dock._set_status("No LevelRoot for .map export", true)
		return
	var format = (
		"valve220" if dock.map_format_select and dock.map_format_select.selected == 1 else "quake"
	)
	var error := int(dock.level_root.export_map(path, format))
	var format_name = "Valve 220" if format == "valve220" else "Classic Quake"
	var message = "Exported .map (%s)" % format_name if error == OK else "Failed to export .map"
	dock._set_status(message, error != OK, 3.0)
	if error != OK:
		dock.show_toast("Failed to export .map", 2)
	else:
		dock.show_toast("Exported .map (%s)" % format_name, 0)


static func on_glb_export_selected(dock: Object, path: String) -> void:
	if dock == null:
		return
	if not dock.level_root:
		dock._set_status("No LevelRoot for .glb export", true)
		return
	dock._warn_missing_dependencies()
	var error := int(dock.level_root.export_baked_gltf(path))
	dock._set_status("Exported .glb" if error == OK else "Failed to export .glb", error != OK, 3.0)
	if error != OK:
		dock.show_toast("Failed to export .glb", 2)
	else:
		dock.show_toast("Exported .glb", 0)


static func on_autosave_path_selected(dock: Object, path: String) -> void:
	if dock == null:
		return
	if not dock.level_root or not dock._root_has_property("hflevel_autosave_path"):
		dock._set_status("No LevelRoot for autosave path", true)
		return
	dock.level_root.set("hflevel_autosave_path", path)
	dock._set_status("Autosave path set", false, 3.0)


static func on_settings_export_selected(dock: Object, path: String) -> void:
	if dock == null:
		return
	if path == "":
		dock._set_status("Invalid settings path", true)
		return
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		dock._set_status("Failed to export settings", true)
		return
	file.store_string(JSON.stringify(dock._collect_editor_settings(), "\t"))
	dock._set_status("Exported settings", false, 3.0)


static func on_settings_import_selected(dock: Object, path: String) -> void:
	if dock == null:
		return
	if path == "":
		dock._set_status("Invalid settings path", true)
		return
	if not FileAccess.file_exists(path):
		dock._set_status("Settings file not found", true)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		dock._set_status("Failed to open settings file", true)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		dock._set_status("Invalid settings file", true)
		return
	dock._apply_editor_settings(parsed)
	dock._set_status("Imported settings", false, 3.0)
