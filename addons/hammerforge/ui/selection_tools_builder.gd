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

	_add_sub_header(sc, "Duplicate Array")

	var dup_row1 = HBoxContainer.new()
	sc.add_child(dup_row1)
	var count_lbl = Label.new()
	count_lbl.text = "Count:"
	dup_row1.add_child(count_lbl)
	dock.dup_count_spin = HFUIFactoryType.make_spin(1, 100, 1, 3)
	dock.dup_count_spin.tooltip_text = "Number of copies to create"
	dup_row1.add_child(dock.dup_count_spin)

	var dup_row2 = HBoxContainer.new()
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
