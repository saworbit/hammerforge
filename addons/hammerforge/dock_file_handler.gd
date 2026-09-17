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

	_configure_dialog(
		dock.material_library_save_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_SAVE_FILE,
		PackedStringArray(["*.json ; Material Library"]),
		Callable(dock, "_on_material_library_save_selected")
	)
	_configure_dialog(
		dock.material_library_load_dialog,
		FileDialog.ACCESS_FILESYSTEM,
		FileDialog.FILE_MODE_OPEN_FILE,
		PackedStringArray(["*.json ; Material Library"]),
		Callable(dock, "_on_material_library_load_selected")
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


## Say it once, when a level binds, if its `.hflevel` is newer than the scene
## that opened (#646). A toast and a Console line, not a dialog: this is worth
## knowing, and it is not worth blocking a scene from opening over.
static func report_hflevel_freshness(dock: Object) -> void:
	if dock == null or not dock.connected_root:
		return
	var root = dock.connected_root
	if not root.has_method("take_hflevel_freshness_report"):
		return
	var report: Dictionary = root.take_hflevel_freshness_report()
	if not bool(report.get("stale", false)):
		return
	var message := str(report.get("message", ""))
	if message == "":
		return
	if root.has_signal("user_message"):
		root.user_message.emit(message, 1)


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
	var check: Dictionary = dock.level_root.validate_map(path)
	if not bool(check.get("ok", false)):
		var reason := str(check.get("error", "unreadable file"))
		dock._set_status("Failed to import .map: %s" % reason, true)
		dock.show_toast("Failed to import .map", 2)
		return
	dock._commit_full_state_action("Import .map", "import_map", [path])
	dock._set_status("Imported .map", false, 3.0)
	dock.show_toast("Imported .map", 0)


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


## Write the palette out as a material library.
##
## `save_library()` records each slot's `resource_path`, so a material made in
## this session and never saved to disk cannot be recorded and its slot comes
## back empty. It says which slots those were; this says so where the mapper can
## see it rather than only in the log.
static func on_material_library_save_selected(dock: Object, path: String) -> void:
	if dock == null or not dock.level_root:
		return
	if path == "":
		dock._set_status("Invalid library path", true)
		return
	var manager = dock.level_root.material_manager
	if manager == null:
		dock._set_status("No material palette", true)
		return
	var result: int = manager.save_library(path)
	if result == ERR_CANT_OPEN:
		dock._set_status("Failed to write material library", true)
		return
	var dropped: Array = manager.get_dropped_save_slots()
	if result == ERR_SKIP:
		dock._set_status("Saved, but no material had a path to record", true)
		return
	if not dropped.is_empty():
		dock._set_status(
			(
				"Saved %d materials; %d had no path and were left empty"
				% [manager.materials.size() - dropped.size(), dropped.size()]
			),
			true,
			5.0
		)
		return
	dock._set_status("Saved material library", false, 3.0)


static func on_material_library_load_selected(dock: Object, path: String) -> void:
	if dock == null or not dock.level_root:
		return
	if path == "" or not FileAccess.file_exists(path):
		dock._set_status("Material library not found", true)
		return
	var manager = dock.level_root.material_manager
	if manager == null:
		dock._set_status("No material palette", true)
		return
	if not manager.library_is_readable(path):
		dock._set_status("Could not read material library", true)
		return
	# Every face's material_idx is an index into the palette this replaces, so
	# the load repaints every painted face in the level. It goes through the
	# undo commit for the same reason its neighbours on the Paint tab do.
	dock._commit_state_action("Load Material Library", "load_material_library", [path])
	dock._sync_materials_from_root()
	var missing: int = manager.get_missing_count()
	if missing > 0:
		dock._set_status(
			"Loaded library; %d of %d materials are missing" % [missing, manager.materials.size()],
			true,
			5.0
		)
		return
	dock._set_status("Loaded material library", false, 3.0)
