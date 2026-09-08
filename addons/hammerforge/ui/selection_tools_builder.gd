@tool
extends RefCounted
## Builds the Selection Tools section in the Brush tab and connects its signals.
## Extracted from dock.gd — purely organizational, no behavior changes.

const HFUIFactoryType = preload("hf_ui_factory.gd")

var dock  # HammerForgeDock reference


func _init(p_dock) -> void:
	dock = p_dock


func build(parent: Control) -> void:
	var brush_vbox = parent
	if not brush_vbox:
		return

	var hf_collapsible_section = dock.HFCollapsibleSection

	dock._selection_tools_section = hf_collapsible_section.create("Selection Tools", true)
	dock._selection_tools_section.visible = false
	brush_vbox.add_child(dock._selection_tools_section)
	dock._register_section(dock._selection_tools_section, "Selection Tools")
	var sc = dock._selection_tools_section.get_content()

	dock._sel_tools_hint_label = Label.new()
	dock._sel_tools_hint_label.text = "Select a brush to use these tools"
	dock._sel_tools_hint_label.add_theme_font_size_override("font_size", 11)
	dock._sel_tools_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	dock._sel_tools_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sc.add_child(dock._sel_tools_hint_label)

	_add_sub_header(sc, "Brush Modification")

	var hollow_row = HBoxContainer.new()
	sc.add_child(hollow_row)
	var hollow_label = Label.new()
	hollow_label.text = "Wall:"
	hollow_row.add_child(hollow_label)
	dock.hollow_thickness = HFUIFactoryType.make_spin(1.0, 128.0, 1.0, 4.0)
	hollow_row.add_child(dock.hollow_thickness)
	dock.hollow_btn = HFUIFactoryType.make_button("Hollow (Ctrl+H)")
	dock.hollow_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hollow_row.add_child(dock.hollow_btn)

	dock.clip_btn = HFUIFactoryType.make_button("Clip Selected (Shift+X)")
	sc.add_child(dock.clip_btn)

	_add_sub_header(sc, "Positioning")

	var move_row = HBoxContainer.new()
	sc.add_child(move_row)
	dock.move_floor_btn = HFUIFactoryType.make_button("To Floor (Ctrl+Shift+F)")
	dock.move_floor_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_row.add_child(dock.move_floor_btn)
	dock.move_ceiling_btn = HFUIFactoryType.make_button("To Ceiling (Ctrl+Shift+C)")
	dock.move_ceiling_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_row.add_child(dock.move_ceiling_btn)

	_add_sub_header(sc, "Entity Binding")

	var tie_row = HBoxContainer.new()
	sc.add_child(tie_row)
	dock.brush_entity_class_opt = HFUIFactoryType.make_option()
	dock._populate_brush_entity_classes()
	tie_row.add_child(dock.brush_entity_class_opt)
	dock.tie_entity_btn = HFUIFactoryType.make_button("Tie")
	tie_row.add_child(dock.tie_entity_btn)
	dock.untie_entity_btn = HFUIFactoryType.make_button("Untie")
	tie_row.add_child(dock.untie_entity_btn)

	_add_sub_header(sc, "Transform")

	var xform_row = HBoxContainer.new()
	sc.add_child(xform_row)
	var angle_lbl = Label.new()
	angle_lbl.text = "Step:"
	xform_row.add_child(angle_lbl)
	dock.rotate_snap_spin = HFUIFactoryType.make_spin(1.0, 180.0, 1.0, 15.0)
	dock.rotate_snap_spin.tooltip_text = "Degrees per rotate press"
	xform_row.add_child(dock.rotate_snap_spin)
	var pivot_lbl = Label.new()
	pivot_lbl.text = "Pivot:"
	xform_row.add_child(pivot_lbl)
	dock.transform_pivot_opt = HFUIFactoryType.make_option(["Selection", "World Origin", "Active"])
	dock.transform_pivot_opt.tooltip_text = ("Selection: the centre of the selected objects. World Origin: (0, 0, 0). Active: the first selected object.")
	xform_row.add_child(dock.transform_pivot_opt)

	var rotate_row = HBoxContainer.new()
	sc.add_child(rotate_row)
	dock.rotate_ccw_btn = HFUIFactoryType.make_button(
		"↺ CCW (R)", "Rotate counter-clockwise about the locked axis, or Y"
	)
	dock.rotate_ccw_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate_row.add_child(dock.rotate_ccw_btn)
	dock.rotate_cw_btn = HFUIFactoryType.make_button(
		"↻ CW (Shift+R)", "Rotate clockwise about the locked axis, or Y"
	)
	dock.rotate_cw_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate_row.add_child(dock.rotate_cw_btn)

	var flip_row = HBoxContainer.new()
	sc.add_child(flip_row)
	dock.flip_btn = HFUIFactoryType.make_button(
		"Flip (Shift+M)", "Mirror the selection across the locked axis, or X"
	)
	dock.flip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flip_row.add_child(dock.flip_btn)
	dock.reset_rotation_btn = HFUIFactoryType.make_button(
		"Reset Rotation (Alt+R)",
		"Clear rotation and keep position — Hollow, Clip and Carve need an unrotated brush"
	)
	dock.reset_rotation_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flip_row.add_child(dock.reset_rotation_btn)

	_add_sub_header(sc, "Duplicate Array")

	var dup_mode_row = HBoxContainer.new()
	sc.add_child(dup_mode_row)
	var mode_lbl = Label.new()
	mode_lbl.text = "Layout:"
	dup_mode_row.add_child(mode_lbl)
	dock.dup_mode_opt = HFUIFactoryType.make_option(["Linear", "Radial", "Grid"])
	dock.dup_mode_opt.tooltip_text = ("Linear: copies along an offset. Radial: copies around an axis. Grid: a 3D lattice of copies.")
	dock.dup_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dup_mode_row.add_child(dock.dup_mode_opt)

	var dup_row1 = HBoxContainer.new()
	sc.add_child(dup_row1)
	var count_lbl = Label.new()
	count_lbl.text = "Count:"
	dup_row1.add_child(count_lbl)
	dock.dup_count_spin = HFUIFactoryType.make_spin(1, 100, 1, 3)
	dock.dup_count_spin.tooltip_text = "Number of copies to create"
	dup_row1.add_child(dock.dup_count_spin)

	var dup_row2 = HBoxContainer.new()
	dock.dup_linear_row = dup_row2
	sc.add_child(dup_row2)
	var off_lbl = Label.new()
	off_lbl.text = "Offset:"
	dup_row2.add_child(off_lbl)
	dock.dup_offset_x = HFUIFactoryType.make_spin(-1000, 1000, 1, 8)
	dock.dup_offset_x.tooltip_text = "X offset per copy"
	dup_row2.add_child(dock.dup_offset_x)
	dock.dup_offset_y = HFUIFactoryType.make_spin(-1000, 1000, 1, 0)
	dock.dup_offset_y.tooltip_text = "Y offset per copy"
	dup_row2.add_child(dock.dup_offset_y)
	dock.dup_offset_z = HFUIFactoryType.make_spin(-1000, 1000, 1, 0)
	dock.dup_offset_z.tooltip_text = "Z offset per copy"
	dup_row2.add_child(dock.dup_offset_z)

	dock.dup_radial_row = HBoxContainer.new()
	dock.dup_radial_row.visible = false
	sc.add_child(dock.dup_radial_row)
	var axis_lbl = Label.new()
	axis_lbl.text = "Axis:"
	dock.dup_radial_row.add_child(axis_lbl)
	dock.dup_axis_opt = HFUIFactoryType.make_option(["X", "Y", "Z"])
	dock.dup_axis_opt.select(1)
	dock.dup_axis_opt.tooltip_text = "Axis the ring turns about"
	dock.dup_radial_row.add_child(dock.dup_axis_opt)
	var step_lbl = Label.new()
	step_lbl.text = "Step°:"
	dock.dup_radial_row.add_child(step_lbl)
	dock.dup_step_spin = HFUIFactoryType.make_spin(-360.0, 360.0, 1.0, 90.0)
	dock.dup_step_spin.tooltip_text = "Degrees between copies"
	dock.dup_radial_row.add_child(dock.dup_step_spin)
	var rise_lbl = Label.new()
	rise_lbl.text = "Rise:"
	dock.dup_radial_row.add_child(rise_lbl)
	dock.dup_rise_spin = HFUIFactoryType.make_spin(-1024.0, 1024.0, 1.0, 0.0)
	dock.dup_rise_spin.tooltip_text = ("How far each copy climbs along the axis. Zero is a flat ring; anything else is a helix, and with a step box, a spiral stair.")
	dock.dup_radial_row.add_child(dock.dup_rise_spin)
	dock.dup_fill_check = HFUIFactoryType.make_check("Fill 360°", false)
	dock.dup_fill_check.tooltip_text = ("Ignore the step and space the copies evenly around a closed ring")
	dock.dup_radial_row.add_child(dock.dup_fill_check)

	dock.dup_grid_row = HBoxContainer.new()
	dock.dup_grid_row.visible = false
	sc.add_child(dock.dup_grid_row)
	var grid_lbl = Label.new()
	grid_lbl.text = "Cells:"
	dock.dup_grid_row.add_child(grid_lbl)
	dock.dup_grid_x = HFUIFactoryType.make_spin(1, 32, 1, 2)
	dock.dup_grid_x.tooltip_text = "Cells along X, counting the original"
	dock.dup_grid_row.add_child(dock.dup_grid_x)
	dock.dup_grid_y = HFUIFactoryType.make_spin(1, 32, 1, 1)
	dock.dup_grid_y.tooltip_text = "Cells along Y, counting the original"
	dock.dup_grid_row.add_child(dock.dup_grid_y)
	dock.dup_grid_z = HFUIFactoryType.make_spin(1, 32, 1, 2)
	dock.dup_grid_z.tooltip_text = "Cells along Z, counting the original"
	dock.dup_grid_row.add_child(dock.dup_grid_z)
	var grid_hint = Label.new()
	grid_hint.text = "spacing = offset"
	grid_hint.add_theme_font_size_override("font_size", 10)
	grid_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	dock.dup_grid_row.add_child(grid_hint)

	dock.dup_summary_label = Label.new()
	dock.dup_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.dup_summary_label.visible = false
	sc.add_child(dock.dup_summary_label)

	var dup_btns = HBoxContainer.new()
	sc.add_child(dup_btns)
	var create_dup_btn = HFUIFactoryType.make_button(
		"Create Array", "Create duplicate array from selected brushes"
	)
	create_dup_btn.pressed.connect(dock._on_create_duplicate_array)
	dup_btns.add_child(create_dup_btn)
	var remove_dup_btn = HFUIFactoryType.make_button(
		"Remove Array", "Remove duplicate array for selected brushes"
	)
	remove_dup_btn.pressed.connect(dock._on_remove_duplicate_array)
	dup_btns.add_child(remove_dup_btn)


func _add_sub_header(parent: Control, text: String) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)
	var sep_left = HSeparator.new()
	sep_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sep_left)
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	hbox.add_child(lbl)
	var sep_right = HSeparator.new()
	sep_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sep_right)


func connect_signals() -> void:
	if dock.dup_mode_opt:
		dock.dup_mode_opt.item_selected.connect(dock._on_duplicate_array_mode_changed)
	_watch_array_controls()
	if dock.rotate_snap_spin:
		dock.rotate_snap_spin.value_changed.connect(dock._on_rotate_snap_changed)
	if dock.transform_pivot_opt:
		dock.transform_pivot_opt.item_selected.connect(dock._on_transform_pivot_changed)
	if dock.rotate_ccw_btn:
		dock.rotate_ccw_btn.pressed.connect(dock._on_rotate_selection.bind(1))
	if dock.rotate_cw_btn:
		dock.rotate_cw_btn.pressed.connect(dock._on_rotate_selection.bind(-1))
	if dock.flip_btn:
		dock.flip_btn.pressed.connect(dock._on_flip_selection)
	if dock.reset_rotation_btn:
		dock.reset_rotation_btn.pressed.connect(dock._on_reset_rotation)
	if dock.hollow_btn:
		dock.hollow_btn.pressed.connect(dock._on_hollow)
	if dock.move_floor_btn:
		dock.move_floor_btn.pressed.connect(dock._on_move_to_floor)
	if dock.move_ceiling_btn:
		dock.move_ceiling_btn.pressed.connect(dock._on_move_to_ceiling)
	if dock.tie_entity_btn:
		dock.tie_entity_btn.pressed.connect(dock._on_tie_entity)
	if dock.untie_entity_btn:
		dock.untie_entity_btn.pressed.connect(dock._on_untie_entity)
	if dock.clip_btn:
		dock.clip_btn.pressed.connect(dock._on_clip)


## Keep the array ghost in step with the controls that describe it.
##
## Every control here carries exactly one argument on its change signal, so one
## handler serves all of them.
func _watch_array_controls() -> void:
	var handler := Callable(dock, "_on_array_setting_changed")
	for control in [
		dock.dup_mode_opt,
		dock.dup_count_spin,
		dock.dup_offset_x,
		dock.dup_offset_y,
		dock.dup_offset_z,
		dock.dup_axis_opt,
		dock.dup_step_spin,
		dock.dup_rise_spin,
		dock.dup_fill_check,
		dock.dup_grid_x,
		dock.dup_grid_y,
		dock.dup_grid_z,
	]:
		if control == null:
			continue
		if control is CheckBox:
			(control as CheckBox).toggled.connect(handler)
		elif control is OptionButton:
			(control as OptionButton).item_selected.connect(handler)
		elif control is SpinBox:
			(control as SpinBox).value_changed.connect(handler)
