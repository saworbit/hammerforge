@tool
extends RefCounted
## Builds the Paint tab UI and connects its signals.
## Extracted from dock.gd — purely organizational, no behavior changes.

var dock  # HammerForgeDock reference


func _init(p_dock) -> void:
	dock = p_dock


func build(parent: Control) -> void:
	var root_vbox = parent
	if not root_vbox:
		return

	var hf_collapsible_section = dock.HFCollapsibleSection

	# --- Floor Paint section ---
	var floor_sec = hf_collapsible_section.create("Floor Paint", true)
	root_vbox.add_child(floor_sec)
	dock._register_section(floor_sec, "Floor Paint")
	var fc = floor_sec.get_content()

	dock.paint_tool_select = OptionButton.new()
	fc.add_child(dock._make_label_row("Tool", dock.paint_tool_select))

	dock.paint_radius = dock._make_spin(1, 16, 1, 1)
	fc.add_child(dock._make_label_row("Radius", dock.paint_radius))

	dock.brush_shape_select = OptionButton.new()
	fc.add_child(dock._make_label_row("Shape", dock.brush_shape_select))

	var layer_row = HBoxContainer.new()
	var layer_label = Label.new()
	layer_label.text = "Layer"
	layer_row.add_child(layer_label)
	dock.paint_layer_select = OptionButton.new()
	dock.paint_layer_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_row.add_child(dock.paint_layer_select)
	dock.paint_layer_add = Button.new()
	dock.paint_layer_add.text = "+"
	dock.paint_layer_add.custom_minimum_size = Vector2(32, 0)
	layer_row.add_child(dock.paint_layer_add)
	dock.paint_layer_remove = Button.new()
	dock.paint_layer_remove.text = "-"
	dock.paint_layer_remove.custom_minimum_size = Vector2(32, 0)
	layer_row.add_child(dock.paint_layer_remove)
	dock.paint_layer_rename = Button.new()
	dock.paint_layer_rename.text = "R"
	dock.paint_layer_rename.custom_minimum_size = Vector2(32, 0)
	layer_row.add_child(dock.paint_layer_rename)
	fc.add_child(layer_row)

	dock.layer_y_spin = dock._make_spin(-1000, 1000, 0.5, 0.0)
	fc.add_child(dock._make_label_row("Layer Y", dock.layer_y_spin))

	dock.height_scale_spin = dock._make_spin(0.1, 100, 0.1, 10.0)
	fc.add_child(dock._make_label_row("Height Scale", dock.height_scale_spin))

	# --- Heightmap section ---
	var hm_sec = hf_collapsible_section.create("Heightmap", false)
	root_vbox.add_child(hm_sec)
	dock._register_section(hm_sec, "Heightmap")
	var hmc = hm_sec.get_content()

	var hm_row = HBoxContainer.new()
	dock.heightmap_import = Button.new()
	dock.heightmap_import.text = "Import..."
	dock.heightmap_import.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hm_row.add_child(dock.heightmap_import)
	dock.heightmap_generate = Button.new()
	dock.heightmap_generate.text = "Generate Noise"
	dock.heightmap_generate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hm_row.add_child(dock.heightmap_generate)
	hmc.add_child(hm_row)

	# Sculpt tools
	var sculpt_label = Label.new()
	sculpt_label.text = "Sculpt:"
	hmc.add_child(sculpt_label)
	var sculpt_row = HBoxContainer.new()
	dock._sculpt_raise_btn = Button.new()
	dock._sculpt_raise_btn.text = "Raise"
	dock._sculpt_raise_btn.toggle_mode = true
	dock._sculpt_raise_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sculpt_row.add_child(dock._sculpt_raise_btn)
	dock._sculpt_lower_btn = Button.new()
	dock._sculpt_lower_btn.text = "Lower"
	dock._sculpt_lower_btn.toggle_mode = true
	dock._sculpt_lower_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sculpt_row.add_child(dock._sculpt_lower_btn)
	dock._sculpt_smooth_btn = Button.new()
	dock._sculpt_smooth_btn.text = "Smooth"
	dock._sculpt_smooth_btn.toggle_mode = true
	dock._sculpt_smooth_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sculpt_row.add_child(dock._sculpt_smooth_btn)
	dock._sculpt_flatten_btn = Button.new()
	dock._sculpt_flatten_btn.text = "Flatten"
	dock._sculpt_flatten_btn.toggle_mode = true
	dock._sculpt_flatten_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sculpt_row.add_child(dock._sculpt_flatten_btn)
	hmc.add_child(sculpt_row)
	dock._sculpt_strength_spin = dock._make_spin(0.1, 50.0, 0.5, 5.0)
	hmc.add_child(dock._make_label_row("Strength", dock._sculpt_strength_spin))
	dock._sculpt_radius_spin = dock._make_spin(1.0, 32.0, 1.0, 3.0)
	hmc.add_child(dock._make_label_row("Radius", dock._sculpt_radius_spin))
	dock._sculpt_falloff_spin = dock._make_spin(0.0, 1.0, 0.1, 0.5)
	hmc.add_child(dock._make_label_row("Falloff", dock._sculpt_falloff_spin))

	# --- Blend & Terrain section ---
	var blend_sec = hf_collapsible_section.create("Blend & Terrain", false)
	root_vbox.add_child(blend_sec)
	dock._register_section(blend_sec, "Blend & Terrain")
	var bc = blend_sec.get_content()

	dock.blend_strength_spin = dock._make_spin(0, 1, 0.05, 0.5)
	bc.add_child(dock._make_label_row("Strength", dock.blend_strength_spin))

	dock.blend_slot_select = OptionButton.new()
	bc.add_child(dock._make_label_row("Blend Slot", dock.blend_slot_select))

	var slot_labels = ["Slot A", "Slot B", "Slot C", "Slot D"]
	var slot_buttons: Array[Button] = []
	var slot_scales: Array[SpinBox] = []
	for i in range(4):
		var slot_row = HBoxContainer.new()
		var slot_label = Label.new()
		slot_label.text = slot_labels[i]
		slot_row.add_child(slot_label)
		var tex_btn = Button.new()
		tex_btn.text = "Texture..."
		tex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_row.add_child(tex_btn)
		var scale_spin = dock._make_spin(0.01, 100, 0.1, 1.0)
		slot_row.add_child(scale_spin)
		bc.add_child(slot_row)
		slot_buttons.append(tex_btn)
		slot_scales.append(scale_spin)
	dock.terrain_slot_a_button = slot_buttons[0]
	dock.terrain_slot_b_button = slot_buttons[1]
	dock.terrain_slot_c_button = slot_buttons[2]
	dock.terrain_slot_d_button = slot_buttons[3]
	dock.terrain_slot_a_scale = slot_scales[0]
	dock.terrain_slot_b_scale = slot_scales[1]
	dock.terrain_slot_c_scale = slot_scales[2]
	dock.terrain_slot_d_scale = slot_scales[3]

	# --- Regions section ---
	var region_sec = hf_collapsible_section.create("Regions", false)
	root_vbox.add_child(region_sec)
	dock._register_section(region_sec, "Regions")
	var rc = region_sec.get_content()

	dock.region_enable = CheckBox.new()
	rc.add_child(dock._make_label_row("Streaming", dock.region_enable))

	dock.region_size_spin = dock._make_spin(64, 2048, 64, 512)
	rc.add_child(dock._make_label_row("Region Size", dock.region_size_spin))

	dock.region_radius_spin = dock._make_spin(0, 8, 1, 2)
	rc.add_child(dock._make_label_row("Stream Radius", dock.region_radius_spin))

	dock.region_memory_spin = dock._make_spin(32, 4096, 32, 256)
	rc.add_child(dock._make_label_row("Memory (MB)", dock.region_memory_spin))

	dock.region_grid_toggle = CheckBox.new()
	rc.add_child(dock._make_label_row("Show Region Grid", dock.region_grid_toggle))

	# --- Materials section ---
	var mat_sec = hf_collapsible_section.create("Materials", true)
	root_vbox.add_child(mat_sec)
	dock._register_section(mat_sec, "Materials")
	var mc = mat_sec.get_content()

	# Visual material browser (replaces old text-only ItemList)
	dock.material_browser = HFMaterialBrowser.new()
	dock.material_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.material_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mc.add_child(dock.material_browser)

	# Keep the legacy ItemList hidden for backwards compat with sync logic
	dock.materials_list = ItemList.new()
	dock.materials_list.visible = false
	mc.add_child(dock.materials_list)

	var mat_btn_row = HBoxContainer.new()
	dock.material_add = Button.new()
	dock.material_add.text = "Add"
	mat_btn_row.add_child(dock.material_add)
	dock.material_remove = Button.new()
	dock.material_remove.text = "Remove"
	mat_btn_row.add_child(dock.material_remove)
	dock.material_load_prototypes = Button.new()
	dock.material_load_prototypes.text = "Refresh Prototypes"
	mat_btn_row.add_child(dock.material_load_prototypes)
	mc.add_child(mat_btn_row)

	# Inline hint when no face is selected
	dock._uv_hint_label = Label.new()
	dock._uv_hint_label.text = "Enable Face Select Mode and click a face to edit"
	dock._uv_hint_label.add_theme_font_size_override("font_size", 11)
	dock._uv_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	dock._uv_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dock._uv_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	mc.add_child(dock._uv_hint_label)

	dock.material_assign = Button.new()
	dock.material_assign.text = "Assign to Selected Faces"
	mc.add_child(dock.material_assign)

	dock.face_select_mode = CheckBox.new()
	dock.face_select_mode.text = "Face Select Mode"
	mc.add_child(dock.face_select_mode)

	dock.face_clear = Button.new()
	dock.face_clear.text = "Clear Face Selection"
	mc.add_child(dock.face_clear)

	# --- UV section ---
	var uv_sec = hf_collapsible_section.create("UV Editor", false)
	root_vbox.add_child(uv_sec)
	dock._register_section(uv_sec, "UV Editor")
	var uc = uv_sec.get_content()

	var uv_editor_scene = dock.UVEditorScene
	var uv_instance = uv_editor_scene.instantiate()
	dock.uv_editor = uv_instance as UVEditor
	uc.add_child(uv_instance)

	dock.uv_reset = Button.new()
	dock.uv_reset.text = "Reset Projected UVs"
	uc.add_child(dock.uv_reset)

	# Justify alignment buttons
	var justify_label = Label.new()
	justify_label.text = "Justify:"
	uc.add_child(justify_label)
	var justify_grid = GridContainer.new()
	justify_grid.columns = 3
	uc.add_child(justify_grid)
	dock.justify_fit_btn = Button.new()
	dock.justify_fit_btn.text = "Fit"
	dock.justify_fit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	justify_grid.add_child(dock.justify_fit_btn)
	dock.justify_center_btn = Button.new()
	dock.justify_center_btn.text = "Center"
	dock.justify_center_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	justify_grid.add_child(dock.justify_center_btn)
	dock.justify_left_btn = Button.new()
	dock.justify_left_btn.text = "Left"
	dock.justify_left_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	justify_grid.add_child(dock.justify_left_btn)
	dock.justify_right_btn = Button.new()
	dock.justify_right_btn.text = "Right"
	dock.justify_right_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	justify_grid.add_child(dock.justify_right_btn)
	dock.justify_top_btn = Button.new()
	dock.justify_top_btn.text = "Top"
	dock.justify_top_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	justify_grid.add_child(dock.justify_top_btn)
	dock.justify_bottom_btn = Button.new()
	dock.justify_bottom_btn.text = "Bottom"
	dock.justify_bottom_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	justify_grid.add_child(dock.justify_bottom_btn)
	dock.justify_treat_as_one = CheckBox.new()
	dock.justify_treat_as_one.text = "Treat as One"
	dock.justify_treat_as_one.tooltip_text = "Align selected faces as a single unified surface"
	uc.add_child(dock.justify_treat_as_one)

	# --- Surface Paint section ---
	var sp_sec = hf_collapsible_section.create("Surface Paint", false)
	root_vbox.add_child(sp_sec)
	dock._register_section(sp_sec, "Surface Paint")
	var sc = sp_sec.get_content()

	dock.paint_target_select = OptionButton.new()
	sc.add_child(dock._make_label_row("Target", dock.paint_target_select))

	dock.surface_paint_radius = dock._make_spin(0.01, 0.5, 0.01, 0.1)
	sc.add_child(dock._make_label_row("Radius (UV)", dock.surface_paint_radius))

	dock.surface_paint_strength = dock._make_spin(0.0, 1.0, 0.05, 1.0)
	sc.add_child(dock._make_label_row("Strength", dock.surface_paint_strength))

	var sp_layer_row = HBoxContainer.new()
	var sp_layer_label = Label.new()
	sp_layer_label.text = "Layer"
	sp_layer_row.add_child(sp_layer_label)
	dock.surface_paint_layer_select = OptionButton.new()
	dock.surface_paint_layer_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp_layer_row.add_child(dock.surface_paint_layer_select)
	dock.surface_paint_layer_add = Button.new()
	dock.surface_paint_layer_add.text = "+"
	dock.surface_paint_layer_add.custom_minimum_size = Vector2(32, 0)
	sp_layer_row.add_child(dock.surface_paint_layer_add)
	dock.surface_paint_layer_remove = Button.new()
	dock.surface_paint_layer_remove.text = "-"
	dock.surface_paint_layer_remove.custom_minimum_size = Vector2(32, 0)
	sp_layer_row.add_child(dock.surface_paint_layer_remove)
	sc.add_child(sp_layer_row)

	dock.surface_paint_texture = Button.new()
	dock.surface_paint_texture.text = "Pick Layer Texture"
	sc.add_child(dock.surface_paint_texture)


func connect_signals() -> void:
	if dock.paint_layer_select:
		dock.paint_layer_select.item_selected.connect(dock._on_paint_layer_selected)
	if dock.paint_layer_add:
		dock.paint_layer_add.pressed.connect(dock._on_paint_layer_add)
	if dock.paint_layer_remove:
		dock.paint_layer_remove.pressed.connect(dock._on_paint_layer_remove)
	if dock.paint_layer_rename:
		dock.paint_layer_rename.pressed.connect(dock._on_paint_layer_rename)
	if dock.heightmap_import:
		dock.heightmap_import.pressed.connect(dock._on_heightmap_import)
	if dock.heightmap_generate:
		dock.heightmap_generate.pressed.connect(dock._on_heightmap_generate)
	if dock.height_scale_spin:
		dock.height_scale_spin.value_changed.connect(dock._on_height_scale_changed)
	if dock._sculpt_raise_btn:
		dock._sculpt_raise_btn.toggled.connect(
			dock._on_sculpt_tool_toggled.bind(HFStroke.Tool.SCULPT_RAISE)
		)
	if dock._sculpt_lower_btn:
		dock._sculpt_lower_btn.toggled.connect(
			dock._on_sculpt_tool_toggled.bind(HFStroke.Tool.SCULPT_LOWER)
		)
	if dock._sculpt_smooth_btn:
		dock._sculpt_smooth_btn.toggled.connect(
			dock._on_sculpt_tool_toggled.bind(HFStroke.Tool.SCULPT_SMOOTH)
		)
	if dock._sculpt_flatten_btn:
		dock._sculpt_flatten_btn.toggled.connect(
			dock._on_sculpt_tool_toggled.bind(HFStroke.Tool.SCULPT_FLATTEN)
		)
	if dock._sculpt_strength_spin:
		dock._sculpt_strength_spin.value_changed.connect(dock._on_sculpt_strength_changed)
	if dock._sculpt_radius_spin:
		dock._sculpt_radius_spin.value_changed.connect(dock._on_sculpt_radius_changed)
	if dock._sculpt_falloff_spin:
		dock._sculpt_falloff_spin.value_changed.connect(dock._on_sculpt_falloff_changed)
	if dock.layer_y_spin:
		dock.layer_y_spin.value_changed.connect(dock._on_layer_y_changed)
	if dock.blend_strength_spin:
		dock.blend_strength_spin.value_changed.connect(dock._on_blend_strength_changed)
	if dock.region_enable:
		dock.region_enable.toggled.connect(dock._on_region_enable_toggled)
	if dock.region_size_spin:
		dock.region_size_spin.value_changed.connect(dock._on_region_size_changed)
	if dock.region_radius_spin:
		dock.region_radius_spin.value_changed.connect(dock._on_region_radius_changed)
	if dock.region_memory_spin:
		dock.region_memory_spin.value_changed.connect(dock._on_region_memory_changed)
	if dock.region_grid_toggle:
		dock.region_grid_toggle.toggled.connect(dock._on_region_grid_toggled)
	if dock.blend_slot_select:
		dock.blend_slot_select.item_selected.connect(dock._on_blend_slot_selected)
	for i in range(dock.terrain_slot_buttons.size()):
		var button = dock.terrain_slot_buttons[i]
		if button:
			button.pressed.connect(dock._on_terrain_slot_pressed.bind(i))
	for i in range(dock.terrain_slot_scales.size()):
		var spin = dock.terrain_slot_scales[i]
		if spin:
			spin.value_changed.connect(dock._on_terrain_slot_scale_changed.bind(i))
	if dock.heightmap_import_dialog:
		dock.heightmap_import_dialog.file_selected.connect(dock._on_heightmap_import_selected)
	if dock.terrain_slot_texture_dialog:
		dock.terrain_slot_texture_dialog.file_selected.connect(
			dock._on_terrain_slot_texture_selected
		)
	if dock.material_browser:
		dock.material_browser.material_selected.connect(dock._on_browser_material_selected)
		dock.material_browser.material_double_clicked.connect(dock._on_browser_material_double_clicked)
		dock.material_browser.material_context_menu.connect(dock._on_browser_context_menu)
		dock.material_browser.material_hovered.connect(dock._on_browser_material_hovered)
		dock.material_browser.material_hover_ended.connect(dock._on_browser_material_hover_ended)
	if dock.materials_list:
		dock.materials_list.item_selected.connect(dock._on_material_selected)
	if dock.material_add:
		dock.material_add.pressed.connect(dock._on_material_add)
	if dock.material_remove:
		dock.material_remove.pressed.connect(dock._on_material_remove)
	if dock.material_load_prototypes:
		dock.material_load_prototypes.pressed.connect(dock._on_material_load_prototypes)
	if dock.material_assign:
		dock.material_assign.pressed.connect(dock._on_material_assign)
	if dock.face_clear:
		dock.face_clear.pressed.connect(dock._on_face_clear)
	if dock.uv_reset:
		dock.uv_reset.pressed.connect(dock._on_uv_reset)
	if dock.uv_editor:
		dock.uv_editor.uv_changed.connect(dock._on_uv_changed)
	if dock.surface_paint_layer_select:
		dock.surface_paint_layer_select.item_selected.connect(dock._on_surface_paint_layer_selected)
	if dock.surface_paint_layer_add:
		dock.surface_paint_layer_add.pressed.connect(dock._on_surface_paint_layer_add)
	if dock.surface_paint_layer_remove:
		dock.surface_paint_layer_remove.pressed.connect(dock._on_surface_paint_layer_remove)
	if dock.surface_paint_texture:
		dock.surface_paint_texture.pressed.connect(dock._on_surface_paint_texture)
	if dock.justify_fit_btn:
		dock.justify_fit_btn.pressed.connect(dock._on_justify.bind("fit"))
	if dock.justify_center_btn:
		dock.justify_center_btn.pressed.connect(dock._on_justify.bind("center"))
	if dock.justify_left_btn:
		dock.justify_left_btn.pressed.connect(dock._on_justify.bind("left"))
	if dock.justify_right_btn:
		dock.justify_right_btn.pressed.connect(dock._on_justify.bind("right"))
	if dock.justify_top_btn:
		dock.justify_top_btn.pressed.connect(dock._on_justify.bind("top"))
	if dock.justify_bottom_btn:
		dock.justify_bottom_btn.pressed.connect(dock._on_justify.bind("bottom"))
