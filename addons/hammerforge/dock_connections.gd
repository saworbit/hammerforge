@tool
class_name HFDockConnections
extends RefCounted
## LevelRoot signal lifecycle extracted from dock.gd.

const ROOT_SIGNALS := {
	"bake_started": "_on_bake_started",
	"bake_progress": "_on_bake_progress",
	"bake_finished": "_on_bake_finished",
	"grid_snap_changed": "_on_root_grid_snap_changed",
	"settings_applied": "_on_root_settings_applied",
	"autosave_failed": "_on_autosave_failed",
	"autosave_waiting": "_on_autosave_waiting",
	"hflevel_save_completed": "_on_hflevel_save_completed",
	"hflevel_save_failed": "_on_hflevel_save_failed",
	"paint_layer_changed": "_on_root_paint_layer_changed",
	"material_list_changed": "_on_root_material_list_changed",
	"face_selection_changed": "_on_root_face_selection_changed",
	"view_filters_changed": "_on_root_view_filters_changed",
	"user_message": "_on_root_user_message",
	"active_material_changed": "_sync_active_material_from_root",
	"transform_pivot_changed": "_on_root_transform_pivot_changed",
	"material_used": "_on_root_material_used",
	# The findings list checks what an edit changed once it settles (#1731).
	"brush_added": "_on_root_brush_findings_changed",
	"brush_removed": "_on_root_brush_findings_changed",
	"brush_changed": "_on_root_brush_findings_changed",
	"entity_added": "_on_root_entity_findings_changed",
	"entity_removed": "_on_root_entity_findings_changed",
}


static func connect_settings(dock: Object) -> void:
	if dock == null:
		return
	var toggle_bindings: Array = [
		[dock.bake_merge_meshes, "bake_merge_meshes"],
		[dock.bake_generate_lods, "bake_generate_lods"],
		[dock.bake_unwrap_uv0, "bake_unwrap_uv0"],
		[dock.bake_lightmap_uv2, "bake_lightmap_uv2"],
		[dock.bake_use_face_materials, "bake_use_face_materials"],
		[dock.bake_navmesh, "bake_navmesh"],
		[dock.bake_visible_only_check, "bake_visible_only"],
		[dock.bake_use_atlas_check, "bake_use_atlas"],
		[dock.bake_auto_connectors_check, "bake_auto_connectors"],
		[dock.bake_generate_occluders_check, "bake_generate_occluders"],
		[dock.commit_freeze, "commit_freeze"],
		[dock.autosave_enabled, "hflevel_autosave_enabled"],
		[dock.show_grid, "grid_visible"],
		[dock.follow_grid, "grid_follow_brush"],
		[dock.export_level_environment_check, "export_level_environment"],
	]
	for binding in toggle_bindings:
		var control: CheckBox = binding[0] as CheckBox
		if control:
			control.toggled.connect(dock._on_setting_toggled.bind(binding[1]))

	var float_bindings: Array = [
		[dock.bake_chunk_size_spin, "bake_chunk_size"],
		[dock.bake_lightmap_texel, "bake_lightmap_texel_size"],
		[dock.bake_navmesh_cell_size, "bake_navmesh_cell_size"],
		[dock.bake_navmesh_cell_height, "bake_navmesh_cell_height"],
		[dock.bake_navmesh_agent_height, "bake_navmesh_agent_height"],
		[dock.bake_navmesh_agent_radius, "bake_navmesh_agent_radius"],
		[dock.bake_navmesh_agent_max_climb, "bake_navmesh_agent_max_climb"],
		[dock.bake_navmesh_agent_max_slope, "bake_navmesh_agent_max_slope"],
		[dock.bake_connector_stair_height_spin, "bake_connector_stair_height"],
		[dock.bake_connector_stair_threshold_spin, "bake_connector_stair_threshold"],
		[dock.bake_occluder_min_area_spin, "bake_occluder_min_area"],
	]
	for binding in float_bindings:
		var control: SpinBox = binding[0] as SpinBox
		if control:
			control.value_changed.connect(dock._on_setting_float_changed.bind(binding[1]))

	var int_bindings: Array = [
		[dock.autosave_minutes, "hflevel_autosave_minutes"],
		[dock.autosave_keep, "hflevel_autosave_keep"],
		[dock.bake_connector_width_spin, "bake_connector_width"],
	]
	for binding in int_bindings:
		var control: SpinBox = binding[0] as SpinBox
		if control:
			control.value_changed.connect(dock._on_setting_int_changed.bind(binding[1]))

	if dock.bake_connector_mode_opt:
		dock.bake_connector_mode_opt.item_selected.connect(
			func(index: int) -> void:
				if dock.syncing_grid or dock._bake_option_held("bake_connector_mode"):
					return
				if dock.level_root and dock._root_has_property("bake_connector_mode"):
					dock.level_root.set("bake_connector_mode", index)
					dock._tag_bake_setting_change("bake_connector_mode")
		)
	if dock.bake_cast_shadows_opt:
		dock.bake_cast_shadows_opt.item_selected.connect(
			func(index: int) -> void:
				if dock.syncing_grid or dock._bake_option_held("bake_cast_shadows"):
					return
				if dock.level_root and dock._root_has_property("bake_cast_shadows"):
					dock.level_root.set(
						"bake_cast_shadows",
						HFUIFactory.cast_shadow_at(dock.bake_cast_shadows_opt, index)
					)
					dock._tag_bake_setting_change("bake_cast_shadows")
		)
	if dock.debug_logs:
		dock.debug_logs.toggled.connect(dock._on_debug_toggled)


static func connect_root(dock: Object) -> void:
	if dock == null:
		return
	# Before the level check: a scene with no level has no Active Material to
	# show either, and the button must not go on naming the last level's.
	dock._sync_active_material_from_root()
	if not dock.connected_root:
		return
	dock._cache_root_properties()
	for signal_name in ROOT_SIGNALS:
		var callback := Callable(dock, ROOT_SIGNALS[signal_name])
		if (
			dock.connected_root.has_signal(signal_name)
			and not dock.connected_root.is_connected(signal_name, callback)
		):
			dock.connected_root.connect(signal_name, callback)
	dock._sync_grid_snap_from_root()
	dock._sync_grid_settings_from_root()
	dock._refresh_paint_layers()
	dock._sync_materials_from_root()
	dock._sync_surface_paint_from_root()
	dock._setup_io_wiring_panel()
	HFDockFileHandler.report_hflevel_freshness(dock)
	# The rows and the chip read the level now connected (#1720).
	dock._on_root_view_filters_changed()
	dock._hints_dirty = true


static func disconnect_root(dock: Object) -> void:
	if dock == null or not dock.connected_root:
		return
	dock.root_properties.clear()
	dock._hints_dirty = true
	for signal_name in ROOT_SIGNALS:
		var callback := Callable(dock, ROOT_SIGNALS[signal_name])
		if (
			dock.connected_root.has_signal(signal_name)
			and dock.connected_root.is_connected(signal_name, callback)
		):
			dock.connected_root.disconnect(signal_name, callback)
