@tool
extends RefCounted
## Builds the Paint tab UI and connects its signals.
## Extracted from dock.gd — purely organizational, no behavior changes.

const HFUIFactoryType = preload("hf_ui_factory.gd")
const FaceDataType = preload("../face_data.gd")

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

	dock.paint_inference_check = dock._make_check("Inference cleanup", false)
	dock.paint_inference_check.tooltip_text = ("Opt-in one-cell cleanup: denoise, hole fill, gap bridge, corridor width")
	fc.add_child(dock.paint_inference_check)

	var mirror_row := HBoxContainer.new()
	dock.paint_mirror_x_check = dock._make_check("Mirror X", false)
	dock.paint_mirror_z_check = dock._make_check("Mirror Z", false)
	mirror_row.add_child(dock.paint_mirror_x_check)
	mirror_row.add_child(dock.paint_mirror_z_check)
	fc.add_child(mirror_row)

	var generative_row := HFUIFactoryType.make_wrap_row()
	dock.paint_raise_btn = Button.new()
	dock.paint_raise_btn.text = "Raise (Y)"
	dock.paint_raise_btn.tooltip_text = "Drag vertically to set wall height for the last paint footprint"
	dock.paint_raise_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generative_row.add_child(dock.paint_raise_btn)
	dock.paint_room_btn = Button.new()
	dock.paint_room_btn.text = "Room (H)"
	dock.paint_room_btn.tooltip_text = "Stamp a room using the last Rect size"
	dock.paint_room_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generative_row.add_child(dock.paint_room_btn)
	dock.paint_connector_confirm_btn = Button.new()
	dock.paint_connector_confirm_btn.text = "Connector (Enter)"
	dock.paint_connector_confirm_btn.tooltip_text = "Confirm the live ramp or stair ghost"
	dock.paint_connector_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generative_row.add_child(dock.paint_connector_confirm_btn)
	fc.add_child(generative_row)

	dock.paint_inference_check.toggled.connect(
		func(_enabled: bool): dock.paint_options_changed.emit()
	)
	dock.paint_mirror_x_check.toggled.connect(
		func(_enabled: bool): dock.paint_options_changed.emit()
	)
	dock.paint_mirror_z_check.toggled.connect(
		func(_enabled: bool): dock.paint_options_changed.emit()
	)
	dock.paint_raise_btn.pressed.connect(func(): dock.paint_raise_requested.emit())
	dock.paint_room_btn.pressed.connect(func(): dock.paint_room_requested.emit())
	dock.paint_connector_confirm_btn.pressed.connect(
		func(): dock.paint_connector_confirm_requested.emit()
	)

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

	# Convert selection to heightmap
	dock.heightmap_convert_btn = Button.new()
	dock.heightmap_convert_btn.text = "Convert Selection → Heightmap"
	dock.heightmap_convert_btn.tooltip_text = "Convert selected additive brushes into a sculptable heightmap layer\nUses mesh bounds (including displacements). Subtract brushes are skipped."
	HFUIFactoryType.wrap_text(dock.heightmap_convert_btn)
	hmc.add_child(dock.heightmap_convert_btn)

	# Sculpt tools
	var sculpt_label = Label.new()
	sculpt_label.text = "Sculpt:"
	hmc.add_child(sculpt_label)
	var sculpt_row = HFUIFactoryType.make_wrap_row()
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

	# --- Foliage & Scatter section ---
	var foliage_sec = hf_collapsible_section.create("Foliage & Scatter", false)
	root_vbox.add_child(foliage_sec)
	dock._register_section(foliage_sec, "Foliage & Scatter")
	var flc = foliage_sec.get_content()

	dock.scatter_mesh_btn = Button.new()
	dock.scatter_mesh_btn.text = "Pick Mesh..."
	dock.scatter_mesh_btn.tooltip_text = "Select a mesh resource for scattering"
	flc.add_child(dock.scatter_mesh_btn)

	dock.scatter_density_spin = dock._make_spin(0.01, 10.0, 0.1, 0.5)
	flc.add_child(dock._make_label_row("Density", dock.scatter_density_spin))

	dock.scatter_radius_spin = dock._make_spin(0.5, 100.0, 0.5, 5.0)
	flc.add_child(dock._make_label_row("Radius", dock.scatter_radius_spin))

	dock.scatter_min_height_spin = dock._make_spin(-1000, 1000, 1.0, -1000.0)
	flc.add_child(dock._make_label_row("Min Height", dock.scatter_min_height_spin))

	dock.scatter_max_height_spin = dock._make_spin(-1000, 1000, 1.0, 1000.0)
	flc.add_child(dock._make_label_row("Max Height", dock.scatter_max_height_spin))

	dock.scatter_max_slope_spin = dock._make_spin(0, 90, 1.0, 45.0)
	flc.add_child(dock._make_label_row("Max Slope", dock.scatter_max_slope_spin))

	dock.scatter_scale_min_spin = dock._make_spin(0.1, 5.0, 0.05, 0.8)
	dock.scatter_scale_max_spin = dock._make_spin(0.1, 5.0, 0.05, 1.2)
	var scale_row = HBoxContainer.new()
	var scale_label = Label.new()
	scale_label.text = "Scale"
	scale_row.add_child(scale_label)
	scale_row.add_child(dock.scatter_scale_min_spin)
	var dash_label = Label.new()
	dash_label.text = "-"
	scale_row.add_child(dash_label)
	scale_row.add_child(dock.scatter_scale_max_spin)
	flc.add_child(scale_row)

	dock.scatter_align_normal = CheckBox.new()
	dock.scatter_align_normal.text = "Align to Surface"
	dock.scatter_align_normal.tooltip_text = "Rotate instances to match terrain normal"
	flc.add_child(dock.scatter_align_normal)

	dock.scatter_random_rotation = CheckBox.new()
	dock.scatter_random_rotation.text = "Random Rotation"
	dock.scatter_random_rotation.button_pressed = true
	flc.add_child(dock.scatter_random_rotation)

	var scatter_shape_row = HBoxContainer.new()
	var shape_label = Label.new()
	shape_label.text = "Shape"
	scatter_shape_row.add_child(shape_label)
	dock.scatter_shape_select = OptionButton.new()
	dock.scatter_shape_select.add_item("Circle", 0)
	dock.scatter_shape_select.add_item("Spline", 1)
	dock.scatter_shape_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scatter_shape_row.add_child(dock.scatter_shape_select)
	flc.add_child(scatter_shape_row)

	dock.scatter_spline_width_spin = dock._make_spin(0.5, 50.0, 0.5, 3.0)
	flc.add_child(dock._make_label_row("Spline Width", dock.scatter_spline_width_spin))

	var preview_row = HBoxContainer.new()
	var preview_label = Label.new()
	preview_label.text = "Preview"
	preview_row.add_child(preview_label)
	dock.scatter_preview_select = OptionButton.new()
	dock.scatter_preview_select.add_item("Dots", 0)
	dock.scatter_preview_select.add_item("Wireframe", 1)
	dock.scatter_preview_select.add_item("Full", 2)
	dock.scatter_preview_select.select(0)
	dock.scatter_preview_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_row.add_child(dock.scatter_preview_select)
	flc.add_child(preview_row)

	var scatter_btn_row = HBoxContainer.new()
	dock.scatter_preview_btn = Button.new()
	dock.scatter_preview_btn.text = "Preview"
	dock.scatter_preview_btn.tooltip_text = "Show density preview at current selection"
	dock.scatter_preview_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scatter_btn_row.add_child(dock.scatter_preview_btn)
	dock.scatter_commit_btn = Button.new()
	dock.scatter_commit_btn.text = "Scatter"
	dock.scatter_commit_btn.tooltip_text = "Place foliage instances permanently"
	dock.scatter_commit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scatter_btn_row.add_child(dock.scatter_commit_btn)
	dock.scatter_clear_btn = Button.new()
	dock.scatter_clear_btn.text = "Clear"
	dock.scatter_clear_btn.tooltip_text = "Remove scatter preview"
	dock.scatter_clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scatter_btn_row.add_child(dock.scatter_clear_btn)
	flc.add_child(scatter_btn_row)

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
	# The browser takes the height the tab has left, so a tall dock shows more
	# than the four rows of its floor, and the tab has nothing of its own to
	# scroll while Materials is the only section open. The tab's column and the
	# margin around it pass that height down from the tab's scroll.
	mat_sec.set_fills_height(true)
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column: Control = root_vbox.get_parent() as Control
	if column:
		column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mc = mat_sec.get_content()

	# Visual material browser (replaces old text-only ItemList)
	dock.material_browser = HFMaterialBrowser.new()
	dock.material_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.material_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# How the open level uses each material, counted once per face change (#1725).
	dock.material_browser.use_provider = dock.material_use_counts
	mc.add_child(dock.material_browser)
	# The count the grid shows goes in the header rather than on a row of its own.
	dock.material_browser.status_changed.connect(mat_sec.set_note)

	# Keep the legacy ItemList hidden for backwards compat with sync logic
	dock.materials_list = ItemList.new()
	dock.materials_list.visible = false
	mc.add_child(dock.materials_list)

	# The palette's own buttons are one click away, closed by default. Open on the
	# grid, their three rows held a 1000 px dock's Paint tab past the dock, and
	# the tab scrolled with the grid inside it (#1366).
	var lib_sec = hf_collapsible_section.create("Material Library", false)
	mc.add_child(lib_sec)
	dock._register_section(lib_sec, "Material Library")
	var lc = lib_sec.get_content()

	var mat_btn_row = HFUIFactoryType.make_wrap_row()
	dock.material_add = Button.new()
	dock.material_add.text = "Add"
	mat_btn_row.add_child(dock.material_add)
	dock.material_remove = Button.new()
	dock.material_remove.text = "Remove"
	mat_btn_row.add_child(dock.material_remove)
	dock.material_load_prototypes = Button.new()
	dock.material_load_prototypes.text = "Refresh Prototypes"
	mat_btn_row.add_child(dock.material_load_prototypes)
	# Refresh Prototypes puts 150 slots in with one press, so the way back is one
	# press too. Before these, it was the minus button 149 times (#661).
	dock.material_remove_unused = Button.new()
	dock.material_remove_unused.text = "Remove Unused"
	mat_btn_row.add_child(dock.material_remove_unused)
	dock.material_replace = Button.new()
	dock.material_replace.text = "Replace..."
	mat_btn_row.add_child(dock.material_replace)
	dock.material_clear = Button.new()
	dock.material_clear.text = "Clear"
	mat_btn_row.add_child(dock.material_clear)
	for button in mat_btn_row.get_children():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.add_child(mat_btn_row)

	# The User Guide has listed Save and Load under Material Library since before
	# either had a button. `MaterialManager` has had both since then, callable
	# from nothing.
	var lib_btn_row = HBoxContainer.new()
	dock.material_save_library = Button.new()
	dock.material_save_library.text = "Save Library"
	lib_btn_row.add_child(dock.material_save_library)
	dock.material_load_library = Button.new()
	dock.material_load_library.text = "Load Library"
	lib_btn_row.add_child(dock.material_load_library)
	lc.add_child(lib_btn_row)

	# Inline hint when no face is selected
	dock._uv_hint_label = Label.new()
	dock._uv_hint_label.text = "Enable Face Select Mode and click a face to edit"
	dock._uv_hint_label.add_theme_font_size_override("font_size", 11)
	dock._uv_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	dock._uv_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dock._uv_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	mc.add_child(dock._uv_hint_label)

	# What to do with the picked faces on one row, how they are picked on the
	# next, each wrapping in a narrow dock. Three to a row was wider than a
	# 400 px dock, and the extra line pushed the Paint tab into scrolling.
	var picked_row := HFUIFactoryType.make_wrap_row()
	dock.material_assign = Button.new()
	dock.material_assign.text = "Assign to Selected Faces"
	dock.material_assign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picked_row.add_child(dock.material_assign)

	dock.face_clear = Button.new()
	dock.face_clear.text = "Clear Face Selection"
	dock.face_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picked_row.add_child(dock.face_clear)
	mc.add_child(picked_row)

	var face_row := HFUIFactoryType.make_wrap_row()
	dock.face_select_mode = CheckBox.new()
	dock.face_select_mode.text = "Face Select Mode"
	dock.face_select_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	face_row.add_child(dock.face_select_mode)

	# Beside the mode it changes: the marquee takes every face in the box (#1432).
	dock.face_select_xray = CheckBox.new()
	dock.face_select_xray.text = "X-ray"
	face_row.add_child(dock.face_select_xray)
	mc.add_child(face_row)

	# --- Face Tools section ---
	# Everything that acts on the face Face Select picked, under one header. The
	# dock adds Displacement and Face Inset after the UV Editor. One header rather
	# than three, so the Materials grid keeps the height #1366 gave it.
	dock._face_tools_section = hf_collapsible_section.create("Face Tools", false)
	root_vbox.add_child(dock._face_tools_section)
	dock._register_section(dock._face_tools_section, "Face Tools")

	# --- UV section ---
	var uv_sec = hf_collapsible_section.create("UV Editor", false)
	dock._face_tools_section.get_content().add_child(uv_sec)
	dock._register_section(uv_sec, "UV Editor")
	var uc = uv_sec.get_content()

	var uv_editor_scene = dock.UVEditorScene
	var uv_instance = uv_editor_scene.instantiate()
	dock.uv_editor = uv_instance as UVEditor
	uc.add_child(uv_instance)

	# UV Snap, under the canvas whose drags it snaps
	var uv_snap_row := HFUIFactoryType.make_wrap_row()
	dock.uv_snap_check = dock._make_check("UV Snap", true)
	uv_snap_row.add_child(dock.uv_snap_check)
	dock.uv_snap_preset_opt = HFUIFactoryType.fit_option(OptionButton.new())
	for i in UVEditor.SNAP_PRESET_LABELS.size():
		dock.uv_snap_preset_opt.add_item(UVEditor.SNAP_PRESET_LABELS[i], i)
	dock.uv_snap_preset_opt.select(UVEditor.SNAP_PRESETS.find(UVEditor.DEFAULT_SNAP_STEP))
	uv_snap_row.add_child(dock.uv_snap_preset_opt)
	# No step of its own, so a typed 1/32 is not rounded to the box's step.
	dock.uv_snap_step_spin = dock._make_spin(0.001, 64.0, 0.0, UVEditor.DEFAULT_SNAP_STEP)
	dock.uv_snap_step_spin.custom_arrow_step = UVEditor.SNAP_PRESETS[0]
	uv_snap_row.add_child(dock.uv_snap_step_spin)
	uc.add_child(uv_snap_row)

	dock.uv_reset = Button.new()
	dock.uv_reset.text = "Reset Projected UVs"
	uc.add_child(dock.uv_reset)

	# Projection mode dropdown + Re-project button
	var proj_label = Label.new()
	proj_label.text = "Projection:"
	uc.add_child(proj_label)
	dock.uv_projection_opt = OptionButton.new()
	dock.uv_projection_opt.add_item("Planar X", 0)
	dock.uv_projection_opt.add_item("Planar Y", 1)
	dock.uv_projection_opt.add_item("Planar Z", 2)
	dock.uv_projection_opt.add_item("Box UV", 3)
	dock.uv_projection_opt.add_item("Cylindrical", 4)
	dock.uv_projection_opt.add_item("Face", 5)
	dock.uv_projection_opt.selected = 3
	uc.add_child(dock.uv_projection_opt)

	dock.uv_reproject_btn = Button.new()
	dock.uv_reproject_btn.text = "Re-project UVs"
	dock.uv_reproject_btn.tooltip_text = "Apply selected projection mode to selected face"
	uc.add_child(dock.uv_reproject_btn)

	# Slide, stretch and turn the picked faces' texture in the viewport (#1420)
	dock.uv_texture_gizmo_check = dock._make_check("Texture Gizmo", false)
	uc.add_child(dock.uv_texture_gizmo_check)

	# Per-face UV scale / offset / rotation
	var uv_params_label = Label.new()
	uv_params_label.text = "UV Transform:"
	uc.add_child(uv_params_label)

	# Wraps x2 and /2 under the boxes in a narrow dock.
	var uv_sc_row := HFUIFactoryType.make_wrap_row()
	var uv_sc_lbl = Label.new()
	uv_sc_lbl.text = "Scale"
	uv_sc_lbl.custom_minimum_size.x = 48
	uv_sc_row.add_child(uv_sc_lbl)
	var scale_limit := HFBrushSystem.UV_SCALE_LIMIT
	dock.uv_scale_x = dock._make_spin(-scale_limit, scale_limit, HFBrushSystem.UV_SCALE_STEP, 1.0)
	dock.uv_scale_x.tooltip_text = "UV scale X"
	uv_sc_row.add_child(dock.uv_scale_x)
	dock.uv_scale_link = Button.new()
	dock.uv_scale_link.text = "Link"
	dock.uv_scale_link.toggle_mode = true
	uv_sc_row.add_child(dock.uv_scale_link)
	dock.uv_scale_y = dock._make_spin(-scale_limit, scale_limit, HFBrushSystem.UV_SCALE_STEP, 1.0)
	dock.uv_scale_y.tooltip_text = "UV scale Y"
	uv_sc_row.add_child(dock.uv_scale_y)
	dock.uv_scale_up_btn = Button.new()
	dock.uv_scale_up_btn.text = "x2"
	uv_sc_row.add_child(dock.uv_scale_up_btn)
	dock.uv_scale_down_btn = Button.new()
	dock.uv_scale_down_btn.text = "/2"
	uv_sc_row.add_child(dock.uv_scale_down_btn)
	uc.add_child(uv_sc_row)

	var uv_off_row = HBoxContainer.new()
	var uv_off_lbl = Label.new()
	uv_off_lbl.text = "Offset"
	uv_off_lbl.custom_minimum_size.x = 48
	uv_off_row.add_child(uv_off_lbl)
	dock.uv_offset_x = dock._make_spin(-1000.0, 1000.0, 0.01, 0.0)
	dock.uv_offset_x.tooltip_text = "UV offset X"
	uv_off_row.add_child(dock.uv_offset_x)
	dock.uv_offset_y = dock._make_spin(-1000.0, 1000.0, 0.01, 0.0)
	dock.uv_offset_y.tooltip_text = "UV offset Y"
	uv_off_row.add_child(dock.uv_offset_y)
	uc.add_child(uv_off_row)

	var uv_rot_row = HBoxContainer.new()
	var uv_rot_lbl = Label.new()
	uv_rot_lbl.text = "Rotate"
	uv_rot_lbl.custom_minimum_size.x = 48
	uv_rot_row.add_child(uv_rot_lbl)
	dock.uv_rotation_spin = dock._make_spin(-360.0, 360.0, 1.0, 0.0)
	dock.uv_rotation_spin.tooltip_text = "UV rotation in degrees"
	dock.uv_rotation_spin.suffix = "\u00b0"
	uv_rot_row.add_child(dock.uv_rotation_spin)
	uc.add_child(uv_rot_row)

	# Flip and quarter turn, each about the face's middle
	var uv_turn_row := HFUIFactoryType.make_wrap_row()
	dock.uv_flip_u_btn = Button.new()
	dock.uv_flip_u_btn.text = "Flip U"
	dock.uv_flip_u_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uv_turn_row.add_child(dock.uv_flip_u_btn)
	dock.uv_flip_v_btn = Button.new()
	dock.uv_flip_v_btn.text = "Flip V"
	dock.uv_flip_v_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uv_turn_row.add_child(dock.uv_flip_v_btn)
	dock.uv_rotate_90_btn = Button.new()
	dock.uv_rotate_90_btn.text = "Rotate 90"
	dock.uv_rotate_90_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uv_turn_row.add_child(dock.uv_rotate_90_btn)
	uc.add_child(uv_turn_row)

	# How the selected faces shade (#1429)
	var uv_smooth_row = HBoxContainer.new()
	var uv_smooth_lbl = Label.new()
	uv_smooth_lbl.text = "Smoothing"
	uv_smooth_row.add_child(uv_smooth_lbl)
	dock.uv_smoothing_spin = dock._make_spin(0.0, FaceData.MAX_SMOOTHING_GROUP, 1.0, 0.0)
	dock.uv_smoothing_spin.tooltip_text = (
		"Smoothing group of the selected faces. 0 shades them flat; faces in the same "
		+ "group above 0 shade round where they meet, across brushes, in the bake"
	)
	uv_smooth_row.add_child(dock.uv_smoothing_spin)
	uc.add_child(uv_smooth_row)

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
	dock.justify_fit_u_btn = Button.new()
	dock.justify_fit_u_btn.text = "Fit U"
	dock.justify_fit_u_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	justify_grid.add_child(dock.justify_fit_u_btn)
	dock.justify_fit_v_btn = Button.new()
	dock.justify_fit_v_btn.text = "Fit V"
	dock.justify_fit_v_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	justify_grid.add_child(dock.justify_fit_v_btn)
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
	# Face or Box UV on every selected face, beside the buttons that place it
	var align_row := HFUIFactoryType.make_wrap_row()
	dock.uv_align_face_btn = Button.new()
	dock.uv_align_face_btn.text = "Align to Face"
	dock.uv_align_face_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	align_row.add_child(dock.uv_align_face_btn)
	dock.uv_align_world_btn = Button.new()
	dock.uv_align_world_btn.text = "Align to World"
	dock.uv_align_world_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	align_row.add_child(dock.uv_align_world_btn)
	uc.add_child(align_row)
	# Turn to an edge, fit whole repeats, or one strip of a trim sheet (#1727)
	var fit_row := HFUIFactoryType.make_wrap_row()
	dock.uv_align_edge_btn = Button.new()
	dock.uv_align_edge_btn.text = "Align to Edge"
	dock.uv_align_edge_btn.tooltip_text = ("Turn the texture to run along an edge of each selected face. Press again for the next edge")
	fit_row.add_child(dock.uv_align_edge_btn)
	var repeats_label := Label.new()
	repeats_label.text = "Repeats"
	fit_row.add_child(repeats_label)
	dock.fit_repeats_u = dock._make_spin(0, 64, 1, 3)
	dock.fit_repeats_u.tooltip_text = "Whole repeats across; 0 keeps the texture's aspect"
	fit_row.add_child(dock.fit_repeats_u)
	dock.fit_repeats_v = dock._make_spin(0, 64, 1, 0)
	dock.fit_repeats_v.tooltip_text = "Whole repeats down; 0 keeps the texture's aspect"
	fit_row.add_child(dock.fit_repeats_v)
	var repeats_btn := Button.new()
	repeats_btn.name = "FitRepeats"
	repeats_btn.text = "Fit"
	repeats_btn.tooltip_text = "Show exactly that many repeats, ending at both edges"
	repeats_btn.pressed.connect(dock._on_fit_repeats)
	fit_row.add_child(repeats_btn)
	uc.add_child(fit_row)
	var strip_row := HFUIFactoryType.make_wrap_row()
	var strip_label := Label.new()
	strip_label.text = "Strip"
	strip_row.add_child(strip_label)
	dock.fit_strip_index = dock._make_spin(1, 4, 1, 1)
	dock.fit_strip_index.tooltip_text = "Which strip of the trim sheet, counted down from the top"
	strip_row.add_child(dock.fit_strip_index)
	var of_label := Label.new()
	of_label.text = "of"
	strip_row.add_child(of_label)
	dock.fit_strip_count = dock._make_spin(1, 64, 1, 4)
	dock.fit_strip_count.tooltip_text = "How many equal strips the texture holds across V"
	dock.fit_strip_count.value_changed.connect(dock._on_fit_strip_count_changed)
	strip_row.add_child(dock.fit_strip_count)
	var strip_btn := Button.new()
	strip_btn.name = "FitStrip"
	strip_btn.text = "Fit"
	strip_btn.tooltip_text = "Fit that strip to each selected face, stretched along U"
	strip_btn.pressed.connect(dock._on_fit_strip)
	strip_row.add_child(strip_btn)
	uc.add_child(strip_row)
	# Treat as One, and the surfaces that stay one after edits
	var surface_row := HFUIFactoryType.make_wrap_row()
	dock.justify_treat_as_one = CheckBox.new()
	dock.justify_treat_as_one.text = "Treat as One"
	dock.justify_treat_as_one.tooltip_text = "Align selected faces as a single unified surface"
	surface_row.add_child(dock.justify_treat_as_one)
	dock.uv_link_btn = Button.new()
	dock.uv_link_btn.text = "Link"
	surface_row.add_child(dock.uv_link_btn)
	dock.uv_unlink_btn = Button.new()
	dock.uv_unlink_btn.text = "Unlink"
	surface_row.add_child(dock.uv_unlink_btn)
	dock.uv_select_group_btn = Button.new()
	dock.uv_select_group_btn.text = "Select Group"
	surface_row.add_child(dock.uv_select_group_btn)
	uc.add_child(surface_row)

	# Carry the selected face's texture over an edge onto the faces clicked next
	dock.uv_wrap_btn = Button.new()
	dock.uv_wrap_btn.text = "Wrap"
	uc.add_child(dock.uv_wrap_btn)

	# The look the Texture Picker read, onto every selected face
	dock.uv_apply_look_btn = Button.new()
	dock.uv_apply_look_btn.text = "Apply Picked Look"
	uc.add_child(dock.uv_apply_look_btn)

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
	if dock.heightmap_convert_btn:
		dock.heightmap_convert_btn.pressed.connect(dock._on_heightmap_convert)
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
		dock.material_browser.material_double_clicked.connect(
			dock._on_browser_material_double_clicked
		)
		dock.material_browser.material_context_menu.connect(dock._on_browser_context_menu)
		dock.material_browser.material_add_requested.connect(
			dock._on_browser_material_add_requested
		)
		dock.material_browser.material_hovered.connect(dock._on_browser_material_hovered)
		dock.material_browser.material_hover_ended.connect(dock._on_browser_material_hover_ended)
		dock.material_browser.hidden_swatch_applied.connect(dock._on_hidden_swatch_applied)
	if dock.materials_list:
		dock.materials_list.item_selected.connect(dock._on_material_selected)
	if dock.material_add:
		dock.material_add.pressed.connect(dock._on_material_add)
	if dock.material_remove:
		dock.material_remove.pressed.connect(dock._on_material_remove)
	if dock.material_load_prototypes:
		dock.material_load_prototypes.pressed.connect(dock._on_material_load_prototypes)
	if dock.material_remove_unused:
		dock.material_remove_unused.pressed.connect(dock._on_material_remove_unused)
	if dock.material_replace:
		dock.material_replace.pressed.connect(dock.open_replace_material.bind(-1))
	if dock.material_clear:
		dock.material_clear.pressed.connect(dock._on_material_clear)
	if dock.material_save_library:
		dock.material_save_library.pressed.connect(dock._on_material_save_library)
	if dock.material_load_library:
		dock.material_load_library.pressed.connect(dock._on_material_load_library)
	if dock.material_assign:
		dock.material_assign.pressed.connect(dock._on_material_assign)
	if dock.face_clear:
		dock.face_clear.pressed.connect(dock._on_face_clear)
	if dock.face_select_mode:
		dock.face_select_mode.toggled.connect(dock._on_face_select_mode_toggled)
	if dock.face_select_xray:
		dock.face_select_xray.toggled.connect(dock._on_face_xray_toggled)
	if dock.uv_reset:
		dock.uv_reset.pressed.connect(dock._on_uv_reset)
	if dock.uv_reproject_btn:
		dock.uv_reproject_btn.pressed.connect(dock._on_uv_reproject)
	if dock.uv_scale_x:
		dock.uv_scale_x.value_changed.connect(dock._on_uv_param_changed.bind("scale_x"))
	if dock.uv_scale_y:
		dock.uv_scale_y.value_changed.connect(dock._on_uv_param_changed.bind("scale_y"))
	if dock.uv_offset_x:
		dock.uv_offset_x.value_changed.connect(dock._on_uv_param_changed.bind("offset_x"))
	if dock.uv_offset_y:
		dock.uv_offset_y.value_changed.connect(dock._on_uv_param_changed.bind("offset_y"))
	if dock.uv_rotation_spin:
		dock.uv_rotation_spin.value_changed.connect(dock._on_uv_param_changed.bind("rotation"))
	if dock.uv_smoothing_spin:
		dock.uv_smoothing_spin.value_changed.connect(dock._on_uv_smoothing_changed)
	if dock.uv_scale_link:
		dock.uv_scale_link.toggled.connect(dock._on_uv_scale_link_toggled)
	for edit_button in [
		[dock.uv_scale_up_btn, "scale_up"],
		[dock.uv_scale_down_btn, "scale_down"],
		[dock.uv_flip_u_btn, "flip_u"],
		[dock.uv_flip_v_btn, "flip_v"],
		[dock.uv_rotate_90_btn, "rotate_90"],
	]:
		if edit_button[0]:
			edit_button[0].pressed.connect(dock._on_uv_edit.bind(edit_button[1]))
	if dock.uv_snap_check:
		dock.uv_snap_check.toggled.connect(dock._on_uv_snap_toggled)
	if dock.uv_texture_gizmo_check:
		dock.uv_texture_gizmo_check.toggled.connect(dock._on_texture_gizmo_toggled)
	if dock.uv_snap_preset_opt:
		dock.uv_snap_preset_opt.item_selected.connect(dock._on_uv_snap_preset_selected)
	if dock.uv_snap_step_spin:
		dock.uv_snap_step_spin.value_changed.connect(dock._on_uv_snap_step_changed)
	if dock.uv_editor:
		dock.uv_editor.uv_changed.connect(dock._on_uv_changed)
		dock.uv_editor.drag_started.connect(dock._on_uv_drag_started)
		dock.uv_editor.drag_finished.connect(dock._on_uv_drag_finished)
		dock.uv_editor.drag_canceled.connect(dock._on_uv_drag_canceled)
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
	if dock.justify_fit_u_btn:
		dock.justify_fit_u_btn.pressed.connect(dock._on_justify.bind("fit_u"))
	if dock.justify_fit_v_btn:
		dock.justify_fit_v_btn.pressed.connect(dock._on_justify.bind("fit_v"))
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
	if dock.uv_align_face_btn:
		dock.uv_align_face_btn.pressed.connect(
			dock._on_uv_align.bind(FaceDataType.UVProjection.FACE)
		)
	if dock.uv_align_world_btn:
		dock.uv_align_world_btn.pressed.connect(
			dock._on_uv_align.bind(FaceDataType.UVProjection.BOX_UV)
		)
	if dock.uv_align_edge_btn:
		dock.uv_align_edge_btn.pressed.connect(dock._on_align_to_edge.bind(null))
	if dock.uv_wrap_btn:
		dock.uv_wrap_btn.pressed.connect(dock._on_uv_wrap)
	if dock.uv_link_btn:
		dock.uv_link_btn.pressed.connect(dock._on_uv_link)
	if dock.uv_unlink_btn:
		dock.uv_unlink_btn.pressed.connect(dock._on_uv_unlink)
	if dock.uv_select_group_btn:
		dock.uv_select_group_btn.pressed.connect(dock._on_uv_select_group)
	if dock.uv_apply_look_btn:
		dock.uv_apply_look_btn.pressed.connect(dock._on_apply_picked_look)
	# Scatter / foliage signals
	if dock.scatter_mesh_btn:
		dock.scatter_mesh_btn.pressed.connect(dock._on_scatter_mesh_pick)
	if dock.scatter_preview_btn:
		dock.scatter_preview_btn.pressed.connect(dock._on_scatter_preview)
	if dock.scatter_commit_btn:
		dock.scatter_commit_btn.pressed.connect(dock._on_scatter_commit)
	if dock.scatter_clear_btn:
		dock.scatter_clear_btn.pressed.connect(dock._on_scatter_clear)
