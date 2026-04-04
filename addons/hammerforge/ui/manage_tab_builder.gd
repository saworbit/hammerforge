@tool
extends RefCounted
## Builds the Manage tab UI and connects its signals.
## Extracted from dock.gd — purely organizational, no behavior changes.

var dock  # HammerForgeDock reference


func _init(p_dock) -> void:
	dock = p_dock


func build(parent: Control) -> void:
	var root_vbox = parent
	if not root_vbox:
		return

	var hf_collapsible_section = dock.HFCollapsibleSection

	# --- Bake section ---
	var bake_sec = hf_collapsible_section.create("Bake", true)
	root_vbox.add_child(bake_sec)
	dock._register_section(bake_sec, "Bake")
	var bk = bake_sec.get_content()

	dock.bake_btn = dock._make_button("Bake")
	bk.add_child(dock.bake_btn)

	dock.bake_dry_run_btn = dock._make_button("Bake Dry Run")
	bk.add_child(dock.bake_dry_run_btn)

	dock.validate_btn = dock._make_button("Validate Level")
	bk.add_child(dock.validate_btn)

	dock.validate_fix_btn = dock._make_button("Validate + Fix")
	bk.add_child(dock.validate_fix_btn)

	dock.bake_merge_meshes = dock._make_check("Merge Meshes")
	bk.add_child(dock.bake_merge_meshes)

	dock.bake_generate_lods = dock._make_check("Generate LODs")
	bk.add_child(dock.bake_generate_lods)

	dock.bake_lightmap_uv2 = dock._make_check("Lightmap UV2")
	bk.add_child(dock.bake_lightmap_uv2)

	dock.bake_use_face_materials = dock._make_check("Use Face Materials")
	bk.add_child(dock.bake_use_face_materials)

	dock.bake_lightmap_texel_row = HBoxContainer.new()
	var texel_label = Label.new()
	texel_label.text = "Texel Size"
	dock.bake_lightmap_texel_row.add_child(texel_label)
	dock.bake_lightmap_texel = dock._make_spin(0.01, 4.0, 0.01, 0.1)
	dock.bake_lightmap_texel_row.add_child(dock.bake_lightmap_texel)
	bk.add_child(dock.bake_lightmap_texel_row)

	dock.bake_navmesh = dock._make_check("Bake Navmesh")
	bk.add_child(dock.bake_navmesh)

	dock.bake_navmesh_cell_row = HBoxContainer.new()
	var nav_cell_label = Label.new()
	nav_cell_label.text = "Navmesh Cell"
	dock.bake_navmesh_cell_row.add_child(nav_cell_label)
	dock.bake_navmesh_cell_size = dock._make_spin(0.05, 2.0, 0.01, 0.3)
	dock.bake_navmesh_cell_row.add_child(dock.bake_navmesh_cell_size)
	dock.bake_navmesh_cell_height = dock._make_spin(0.05, 2.0, 0.01, 0.2)
	dock.bake_navmesh_cell_row.add_child(dock.bake_navmesh_cell_height)
	bk.add_child(dock.bake_navmesh_cell_row)

	dock.bake_navmesh_agent_row = HBoxContainer.new()
	var nav_agent_label = Label.new()
	nav_agent_label.text = "Agent Size"
	dock.bake_navmesh_agent_row.add_child(nav_agent_label)
	dock.bake_navmesh_agent_height = dock._make_spin(0.5, 5.0, 0.1, 2.0)
	dock.bake_navmesh_agent_row.add_child(dock.bake_navmesh_agent_height)
	dock.bake_navmesh_agent_radius = dock._make_spin(0.1, 2.0, 0.05, 0.4)
	dock.bake_navmesh_agent_row.add_child(dock.bake_navmesh_agent_radius)
	bk.add_child(dock.bake_navmesh_agent_row)

	# -- Incremental / selection bake --
	var bake_opt_sep = HSeparator.new()
	bk.add_child(bake_opt_sep)

	dock.bake_selected_btn = dock._make_button("Bake Selected")
	dock.bake_selected_btn.tooltip_text = "Bake only the currently selected brushes"
	bk.add_child(dock.bake_selected_btn)

	dock.bake_changed_btn = dock._make_button("Bake Changed")
	dock.bake_changed_btn.tooltip_text = "Bake only brushes modified since last bake"
	bk.add_child(dock.bake_changed_btn)

	dock.bake_check_issues_btn = dock._make_button("Check Bake Issues")
	dock.bake_check_issues_btn.tooltip_text = ("Scan for bake problems: degenerate brushes, floating subtracts, overlapping cuts")
	bk.add_child(dock.bake_check_issues_btn)

	# -- Preview mode --
	var preview_row = HBoxContainer.new()
	var preview_label = Label.new()
	preview_label.text = "Preview"
	preview_row.add_child(preview_label)
	dock.bake_preview_mode_opt = OptionButton.new()
	dock.bake_preview_mode_opt.add_item("Full", 0)
	dock.bake_preview_mode_opt.add_item("Wireframe", 1)
	dock.bake_preview_mode_opt.add_item("Proxy", 2)
	dock.bake_preview_mode_opt.tooltip_text = ("Full: final quality. Wireframe: fast unshaded outline. Proxy: low-res solid.")
	dock.bake_preview_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_row.add_child(dock.bake_preview_mode_opt)
	bk.add_child(preview_row)

	# -- Bake time estimate --
	dock.bake_estimate_label = Label.new()
	dock.bake_estimate_label.text = "Est: — "
	dock.bake_estimate_label.add_theme_font_size_override("font_size", 11)
	dock.bake_estimate_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	bk.add_child(dock.bake_estimate_label)

	# -- Quick Play modes --
	var qp_sep = HSeparator.new()
	bk.add_child(qp_sep)

	dock.quick_play_camera_btn = dock._make_button("Play from Camera")
	dock.quick_play_camera_btn.tooltip_text = ("Teleport spawn to current editor camera position and play")
	bk.add_child(dock.quick_play_camera_btn)

	dock.quick_play_area_btn = dock._make_button("Play Selected Area")
	dock.quick_play_area_btn.tooltip_text = ("Auto-cordon to selection, bake only that area, and play")
	bk.add_child(dock.quick_play_area_btn)

	dock.export_playtest_btn = dock._make_button("Export Playtest Build")
	dock.export_playtest_btn.tooltip_text = (
		"Validate, bake optimized, and launch as playable scene"
	)
	bk.add_child(dock.export_playtest_btn)

	# --- Actions section ---
	var act_sec = hf_collapsible_section.create("Actions", true)
	root_vbox.add_child(act_sec)
	dock._register_section(act_sec, "Actions")
	var ac = act_sec.get_content()

	dock.floor_btn = dock._make_button("Create Floor")
	ac.add_child(dock.floor_btn)

	dock.apply_cuts_btn = dock._make_button("Apply Cuts")
	ac.add_child(dock.apply_cuts_btn)

	dock.clear_cuts_btn = dock._make_button("Clear Pending Cuts")
	ac.add_child(dock.clear_cuts_btn)

	dock.commit_cuts_btn = dock._make_button("Commit Cuts (Bake)")
	ac.add_child(dock.commit_cuts_btn)

	dock.restore_cuts_btn = dock._make_button("Restore Committed Cuts")
	ac.add_child(dock.restore_cuts_btn)

	dock.clear_btn = dock._make_button("Clear Brushes")
	ac.add_child(dock.clear_btn)

	# --- File section ---
	var file_sec = hf_collapsible_section.create("File", true)
	root_vbox.add_child(file_sec)
	dock._register_section(file_sec, "File")
	var flc = file_sec.get_content()

	dock.save_hflevel_btn = dock._make_button("Save .hflevel")
	flc.add_child(dock.save_hflevel_btn)

	dock.load_hflevel_btn = dock._make_button("Load .hflevel")
	flc.add_child(dock.load_hflevel_btn)

	dock.import_map_btn = dock._make_button("Import .map")
	flc.add_child(dock.import_map_btn)

	dock.map_format_select = OptionButton.new()
	dock.map_format_select.add_item("Classic Quake", 0)
	dock.map_format_select.add_item("Valve 220", 1)
	dock.map_format_select.tooltip_text = "Map export format"
	flc.add_child(dock.map_format_select)

	dock.export_map_btn = dock._make_button("Export .map")
	flc.add_child(dock.export_map_btn)

	dock.export_glb_btn = dock._make_button("Export .glb")
	flc.add_child(dock.export_glb_btn)

	# --- Presets section ---
	var preset_sec = hf_collapsible_section.create("Presets", false)
	root_vbox.add_child(preset_sec)
	dock._register_section(preset_sec, "Presets")
	var pc = preset_sec.get_content()

	dock.save_preset_btn = dock._make_button("Save Current")
	pc.add_child(dock.save_preset_btn)

	dock.preset_grid = GridContainer.new()
	dock.preset_grid.columns = 2
	pc.add_child(dock.preset_grid)

	# --- Prefabs section ---
	var prefab_sec = hf_collapsible_section.create("Prefabs", false)
	root_vbox.add_child(prefab_sec)
	dock._register_section(prefab_sec, "Prefabs")
	var HFPrefabLibrary = preload("res://addons/hammerforge/ui/hf_prefab_library.gd")
	dock._prefab_library = HFPrefabLibrary.new()
	prefab_sec.get_content().add_child(dock._prefab_library)

	# --- Spawn section ---
	var spawn_sec = hf_collapsible_section.create("Spawn", false)
	root_vbox.add_child(spawn_sec)
	dock._register_section(spawn_sec, "Spawn")
	var spc = spawn_sec.get_content()

	dock._spawn_validate_btn = dock._make_button("Validate Spawn")
	spc.add_child(dock._spawn_validate_btn)

	dock._spawn_auto_create_btn = dock._make_button("Create Default Spawn")
	spc.add_child(dock._spawn_auto_create_btn)

	dock._show_spawn_debug = dock._make_check("Preview Spawn Debug", false)
	spc.add_child(dock._show_spawn_debug)

	# --- History section (collapsed by default) ---
	var hist_sec = hf_collapsible_section.create("History", false)
	root_vbox.add_child(hist_sec)
	dock._register_section(hist_sec, "History")
	var hc = hist_sec.get_content()

	var HFHistoryBrowserScript = preload("res://addons/hammerforge/ui/hf_history_browser.gd")
	dock.history_browser = HFHistoryBrowserScript.new()
	hc.add_child(dock.history_browser)
	dock.undo_btn = dock.history_browser.get_undo_button()
	dock.redo_btn = dock.history_browser.get_redo_button()

	# --- Settings section (collapsed by default) ---
	var set_sec = hf_collapsible_section.create("Settings", false)
	root_vbox.add_child(set_sec)
	dock._register_section(set_sec, "Settings")
	var stc = set_sec.get_content()

	dock.commit_freeze = dock._make_check("Freeze Commit (keep CSG hidden)", true)
	stc.add_child(dock.commit_freeze)

	dock.show_hud = dock._make_check("Show HUD", true)
	stc.add_child(dock.show_hud)

	dock.show_grid = dock._make_check("Show Grid", false)
	stc.add_child(dock.show_grid)

	dock.follow_grid = dock._make_check("Follow Grid", false)
	stc.add_child(dock.follow_grid)

	dock.debug_logs = dock._make_check("Debug Logs", false)
	stc.add_child(dock.debug_logs)

	dock._show_io_lines = dock._make_check("Show I/O Lines", false)
	stc.add_child(dock._show_io_lines)

	dock._show_subtract_preview = dock._make_check("Subtract Preview", false)
	stc.add_child(dock._show_subtract_preview)

	dock.autosave_enabled = dock._make_check("Enable Autosave", true)
	stc.add_child(dock.autosave_enabled)

	dock.autosave_minutes = dock._make_spin(1, 60, 1, 5)
	stc.add_child(dock._make_label_row("Autosave Minutes", dock.autosave_minutes))

	dock.autosave_keep = dock._make_spin(1, 50, 1, 5)
	stc.add_child(dock._make_label_row("Keep Backups", dock.autosave_keep))

	dock.autosave_path_btn = dock._make_button("Set Autosave Path")
	stc.add_child(dock.autosave_path_btn)

	dock.export_settings_btn = dock._make_button("Export Settings")
	stc.add_child(dock.export_settings_btn)

	dock.import_settings_btn = dock._make_button("Import Settings")
	stc.add_child(dock.import_settings_btn)

	# --- Examples section (collapsed by default) ---
	var ex_sec = hf_collapsible_section.create("Examples", false)
	root_vbox.add_child(ex_sec)
	dock._register_section(ex_sec, "Examples")
	var HFExampleLibrary = preload("res://addons/hammerforge/ui/hf_example_library.gd")
	dock._example_library = HFExampleLibrary.new()
	ex_sec.get_content().add_child(dock._example_library)

	# --- Performance section (collapsed by default) ---
	var perf_sec = hf_collapsible_section.create("Performance", false)
	root_vbox.add_child(perf_sec)
	dock._register_section(perf_sec, "Performance")
	var pfc = perf_sec.get_content()

	# Health summary
	dock.perf_health_label = Label.new()
	dock.perf_health_label.text = "Healthy"
	dock.perf_health_label.add_theme_font_size_override("font_size", 13)
	dock.perf_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pfc.add_child(dock.perf_health_label)

	# Brush count progress bar
	dock.perf_brush_bar = ProgressBar.new()
	dock.perf_brush_bar.min_value = 0
	dock.perf_brush_bar.max_value = 200
	dock.perf_brush_bar.value = 0
	dock.perf_brush_bar.show_percentage = false
	dock.perf_brush_bar.custom_minimum_size = Vector2(0, 14)
	dock.perf_brush_bar.tooltip_text = "Brush count relative to recommended max (200)"
	pfc.add_child(dock.perf_brush_bar)

	var perf_grid = GridContainer.new()
	perf_grid.columns = 2
	pfc.add_child(perf_grid)

	var perf_labels = [
		["Active Brushes", "0"],
		["Entities", "0"],
		["Vertices (est)", "0"],
		["Paint Memory", "0 KB"],
		["Bake Chunks", "0"],
		["Last Bake", "0 ms"],
		["Rec. Chunk Size", "-"],
	]
	var perf_value_nodes: Array[Label] = []
	for pair in perf_labels:
		var key_label = Label.new()
		key_label.text = pair[0]
		key_label.add_theme_font_size_override("font_size", 11)
		perf_grid.add_child(key_label)
		var val_label = Label.new()
		val_label.text = pair[1]
		val_label.add_theme_font_size_override("font_size", 11)
		perf_grid.add_child(val_label)
		perf_value_nodes.append(val_label)
	dock.perf_brushes_value = perf_value_nodes[0]
	dock.perf_entity_value = perf_value_nodes[1]
	dock.perf_vertex_value = perf_value_nodes[2]
	dock.perf_paint_mem_value = perf_value_nodes[3]
	dock.perf_bake_chunks_value = perf_value_nodes[4]
	dock.perf_bake_time_value = perf_value_nodes[5]
	dock.perf_chunk_rec_value = perf_value_nodes[6]


func connect_signals() -> void:
	if dock.bake_btn:
		dock.bake_btn.pressed.connect(dock._on_bake)
	if dock.bake_dry_run_btn:
		dock.bake_dry_run_btn.pressed.connect(dock._on_bake_dry_run)
	if dock.validate_btn:
		dock.validate_btn.pressed.connect(dock._on_validate_level)
	if dock.validate_fix_btn:
		dock.validate_fix_btn.pressed.connect(dock._on_validate_fix)
	if dock.clear_btn:
		dock.clear_btn.pressed.connect(dock._on_clear)
	if dock.save_hflevel_btn:
		dock.save_hflevel_btn.pressed.connect(dock._on_save_hflevel)
	if dock.load_hflevel_btn:
		dock.load_hflevel_btn.pressed.connect(dock._on_load_hflevel)
	if dock.import_map_btn:
		dock.import_map_btn.pressed.connect(dock._on_import_map)
	if dock.export_map_btn:
		dock.export_map_btn.pressed.connect(dock._on_export_map)
	if dock.export_glb_btn:
		dock.export_glb_btn.pressed.connect(dock._on_export_glb)
	if dock.autosave_path_btn:
		dock.autosave_path_btn.pressed.connect(dock._on_set_autosave_path)
	if dock.export_settings_btn:
		dock.export_settings_btn.pressed.connect(dock._on_export_settings)
	if dock.import_settings_btn:
		dock.import_settings_btn.pressed.connect(dock._on_import_settings)
	if dock.floor_btn:
		dock.floor_btn.pressed.connect(dock._on_floor)
	if dock.apply_cuts_btn:
		dock.apply_cuts_btn.pressed.connect(dock._on_apply_cuts)
	if dock.clear_cuts_btn:
		dock.clear_cuts_btn.pressed.connect(dock._on_clear_cuts)
	if dock.commit_cuts_btn:
		dock.commit_cuts_btn.pressed.connect(dock._on_commit_cuts)
	if dock.restore_cuts_btn:
		dock.restore_cuts_btn.pressed.connect(dock._on_restore_cuts)
	if dock.undo_btn:
		dock.undo_btn.pressed.connect(dock._on_history_undo)
	if dock.redo_btn:
		dock.redo_btn.pressed.connect(dock._on_history_redo)
	if dock.history_browser:
		dock.history_browser.navigate_requested.connect(dock._on_history_navigate)
	if dock.save_preset_btn:
		dock.save_preset_btn.pressed.connect(dock._on_save_preset)
	if dock.show_hud:
		dock.show_hud.toggled.connect(dock._on_show_hud_toggled)
	if dock.show_grid:
		dock.show_grid.toggled.connect(dock._on_show_grid_toggled)
	if dock.follow_grid:
		dock.follow_grid.toggled.connect(dock._on_follow_grid_toggled)
	if dock.debug_logs:
		dock.debug_logs.toggled.connect(dock._on_debug_logs_toggled)
	if dock._show_io_lines:
		dock._show_io_lines.toggled.connect(dock._on_show_io_lines_toggled)
	if dock._show_subtract_preview:
		dock._show_subtract_preview.toggled.connect(dock._on_show_subtract_preview_toggled)
	if dock._prefab_library and dock._prefab_library.has_signal("save_requested"):
		dock._prefab_library.save_requested.connect(dock._on_prefab_save_requested)
	if dock._prefab_library and dock._prefab_library.has_signal("save_linked_requested"):
		dock._prefab_library.save_linked_requested.connect(dock._on_prefab_save_linked_requested)
	if dock._prefab_library and dock._prefab_library.has_signal("delete_requested"):
		dock._prefab_library.delete_requested.connect(dock._on_prefab_delete_requested)
	if dock._prefab_library and dock._prefab_library.has_signal("variant_add_requested"):
		dock._prefab_library.variant_add_requested.connect(dock._on_prefab_variant_add_requested)
	if dock.bake_lightmap_uv2:
		dock.bake_lightmap_uv2.toggled.connect(dock._on_bake_lightmap_uv2_toggled)
	if dock.bake_navmesh:
		dock.bake_navmesh.toggled.connect(dock._on_bake_navmesh_toggled)
	if dock.bake_selected_btn:
		dock.bake_selected_btn.pressed.connect(dock._on_bake_selected)
	if dock.bake_changed_btn:
		dock.bake_changed_btn.pressed.connect(dock._on_bake_changed)
	if dock.bake_check_issues_btn:
		dock.bake_check_issues_btn.pressed.connect(dock._on_bake_check_issues)
	if dock.quick_play_camera_btn:
		dock.quick_play_camera_btn.pressed.connect(dock._on_quick_play_from_camera)
	if dock.quick_play_area_btn:
		dock.quick_play_area_btn.pressed.connect(dock._on_quick_play_selected_area)
	if dock.export_playtest_btn:
		dock.export_playtest_btn.pressed.connect(dock._on_export_playtest)
	if dock._spawn_validate_btn:
		dock._spawn_validate_btn.pressed.connect(dock._on_spawn_validate)
	if dock._spawn_auto_create_btn:
		dock._spawn_auto_create_btn.pressed.connect(dock._on_spawn_auto_create)
	if dock._show_spawn_debug:
		dock._show_spawn_debug.toggled.connect(dock._on_show_spawn_debug_toggled)
	if dock._example_library and dock._example_library.has_signal("load_requested"):
		dock._example_library.load_requested.connect(dock._on_example_load_requested)
