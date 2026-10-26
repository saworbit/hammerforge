@tool
extends RefCounted
## Builds the Selection Tools section in the Brush tab and connects its signals.
## Extracted from dock.gd — purely organizational, no behavior changes.

const HFUIFactoryType = preload("hf_ui_factory.gd")
const HFCommandRegistryType = preload("../hf_command_registry.gd")
const HFBakeSplitType = preload("../hf_bake_split.gd")
const HFSelectionInfoType = preload("hf_selection_info.gd")

var dock  # HammerForgeDock reference


func _init(p_dock) -> void:
	dock = p_dock


func build(parent: Control) -> void:
	var brush_vbox = parent
	if not brush_vbox:
		return

	var hf_collapsible_section = dock.HFCollapsibleSection

	# A section of its own at the top rather than a part of Selection Tools, which
	# shows only with brushes selected: Face Select puts the object selection
	# aside, and a picked face still has a centre, a normal and an area to show.
	dock._selection_info_section = hf_collapsible_section.create("Selection Info", true)
	dock._selection_info_section.visible = false
	brush_vbox.add_child(dock._selection_info_section)
	dock._register_section(dock._selection_info_section, "Selection Info")
	dock.selection_info = HFSelectionInfoType.new()
	dock._selection_info_section.get_content().add_child(dock.selection_info)
	dock.selection_info.vertex_typed.connect(dock.selection_vertex_typed.emit)
	dock.selection_info.narrow_requested.connect(dock.selection_narrow_requested.emit)

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
	# Metres, as the grid has been since #638: a quarter-metre wall by default.
	# The range is the command table's, so the dock and an agent's Hollow agree.
	var wall: Dictionary = HFCommandRegistryType.field("hollow", "thickness")
	dock.hollow_thickness = HFUIFactoryType.make_spin(
		float(wall["min"]), float(wall["max"]), float(wall["step"]), float(wall["default"])
	)
	hollow_row.add_child(dock.hollow_thickness)
	dock.hollow_btn = HFUIFactoryType.make_button("Hollow (Ctrl+H)")
	dock.hollow_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hollow_row.add_child(dock.hollow_btn)
	dock.hollow_detach_btn = HFUIFactoryType.make_button(
		"Detach", "Stop these walls being re-shelled, and keep them as ordinary brushes"
	)
	dock.hollow_detach_btn.visible = false
	dock.hollow_detach_btn.pressed.connect(dock._on_detach_hollow)
	hollow_row.add_child(dock.hollow_detach_btn)

	# What a Re-hollow would undo. Under the row rather than in it, because it is a
	# sentence and the row is three controls wide.
	dock.hollow_warning = Label.new()
	dock.hollow_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.hollow_warning.visible = false
	sc.add_child(dock.hollow_warning)

	dock.clip_btn = HFUIFactoryType.make_button("Clip Selected (Shift+X)")
	sc.add_child(dock.clip_btn)

	_add_sub_header(sc, "Positioning")

	var move_row = HFUIFactoryType.make_wrap_row()
	sc.add_child(move_row)
	dock.move_floor_btn = HFUIFactoryType.make_button("To Floor (Ctrl+Shift+F)")
	dock.move_floor_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_row.add_child(dock.move_floor_btn)
	dock.move_ceiling_btn = HFUIFactoryType.make_button("To Ceiling (Ctrl+Shift+C)")
	dock.move_ceiling_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_row.add_child(dock.move_ceiling_btn)
	dock.snap_to_grid_btn = HFUIFactoryType.make_button("Snap to Grid (Ctrl+B)")
	dock.snap_to_grid_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_row.add_child(dock.snap_to_grid_btn)

	_add_sub_header(sc, "Entity Binding")

	var tie_row = HBoxContainer.new()
	sc.add_child(tie_row)
	dock.brush_entity_class_opt = HFUIFactoryType.make_option()
	dock._populate_brush_entity_classes()
	HFUIFactoryType.fit_option(dock.brush_entity_class_opt)
	tie_row.add_child(dock.brush_entity_class_opt)
	# The name is the address every I/O connection is aimed at, and there was
	# nowhere to type one: a door built here could never be targeted, while a
	# door imported from someone else's `.map` could (#668).
	dock.brush_entity_name_edit = LineEdit.new()
	dock.brush_entity_name_edit.placeholder_text = "name (optional)"
	dock.brush_entity_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tie_row.add_child(dock.brush_entity_name_edit)
	dock.tie_entity_btn = HFUIFactoryType.make_button("Tie")
	tie_row.add_child(dock.tie_entity_btn)
	dock.untie_entity_btn = HFUIFactoryType.make_button("Untie")
	tie_row.add_child(dock.untie_entity_btn)

	# How the selected brushes bake: what a merged mesh cannot mix, so a brush
	# that differs bakes into a mesh of its own (#1444, #1438).
	_add_sub_header(sc, "Bake")

	dock.brush_cast_shadow_opt = HFUIFactoryType.make_cast_shadow_option(true)
	dock.brush_cast_shadow_opt.tooltip_text = (
		"How these brushes cast shadows once baked. Level Default leaves it to their "
		+ "visgroups and then to Cast Shadows in Advanced Bake"
	)
	sc.add_child(HFUIFactoryType.make_label_row("Cast Shadows:", dock.brush_cast_shadow_opt))

	var lightmap: Dictionary = {
		"min": HFBakeSplitType.MIN_LIGHTMAP_SCALE,
		"max": HFBakeSplitType.MAX_LIGHTMAP_SCALE,
	}
	dock.brush_lightmap_scale_spin = HFUIFactoryType.make_spin(
		lightmap["min"], lightmap["max"], 0.125, HFBakeSplitType.DEFAULT_LIGHTMAP_SCALE
	)
	dock.brush_lightmap_scale_spin.tooltip_text = (
		"Lightmap detail on these brushes, against the level's Texel Size: 2 is twice as "
		+ "fine, 0.5 half. Takes effect with Lightmap UV2 on"
	)
	sc.add_child(HFUIFactoryType.make_label_row("Lightmap Scale:", dock.brush_lightmap_scale_spin))

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
	dock.transform_pivot_opt = HFUIFactoryType.make_option(
		["Selection", "World Origin", "Active", "Pick"]
	)
	dock.transform_pivot_opt.tooltip_text = ("Selection: the centre of the selected objects. World Origin: (0, 0, 0). Active: the first selected object. Pick: a brush vertex, edge midpoint or face centre you click in the viewport, marked with a cross; Pick Pivot (Alt+P) picks again, Clear Pivot (Shift+Alt+P) goes back to Selection.")
	HFUIFactoryType.fit_option(dock.transform_pivot_opt)
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

	var flip_row = HFUIFactoryType.make_wrap_row()
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
	dock.apply_rotation_scale_btn = HFUIFactoryType.make_button(
		"Apply Rotation and Scale",
		"Fold rotation and scale into the brush's shape: nothing moves, and size reads in metres"
	)
	dock.apply_rotation_scale_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flip_row.add_child(dock.apply_rotation_scale_btn)

	# The boxes are the level's Mirror Copy settings, so Alt+M reads them as they
	# stand. The dock fills them in from the level when one connects.
	var mirror_row = HFUIFactoryType.make_wrap_row()
	sc.add_child(mirror_row)
	var mirror_lbl = Label.new()
	mirror_lbl.text = "Mirror:"
	mirror_row.add_child(mirror_lbl)
	dock.mirror_copy_x_check = HFUIFactoryType.make_check("X", true)
	dock.mirror_copy_x_check.tooltip_text = "Mirror Copy across X"
	mirror_row.add_child(dock.mirror_copy_x_check)
	dock.mirror_copy_y_check = HFUIFactoryType.make_check("Y", false)
	dock.mirror_copy_y_check.tooltip_text = "Mirror Copy across Y"
	mirror_row.add_child(dock.mirror_copy_y_check)
	dock.mirror_copy_z_check = HFUIFactoryType.make_check("Z", false)
	dock.mirror_copy_z_check.tooltip_text = "Mirror Copy across Z"
	mirror_row.add_child(dock.mirror_copy_z_check)
	dock.mirror_copy_edge_check = HFUIFactoryType.make_check("Selection Edge", true)
	dock.mirror_copy_edge_check.tooltip_text = ("On: mirror across the far side of the selection's bounds on each axis, so each copy lands flush beside it. Off: mirror through the Pivot.")
	mirror_row.add_child(dock.mirror_copy_edge_check)
	dock.mirror_copy_btn = HFUIFactoryType.make_button(
		"Mirror Copy (Alt+M)", "Keep the selection and add mirrored copies across the ticked axes"
	)
	dock.mirror_copy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mirror_row.add_child(dock.mirror_copy_btn)

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
	# The counts' ranges are the command table's, so the dock holds any count
	# Adjust Last can set and hands back to it (#1996).
	dock.dup_count_spin = _setting_spin("duplicate_array", "count")
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
	dock.dup_grid_x = _setting_spin("grid_array", "count_x")
	dock.dup_grid_x.tooltip_text = "Cells along X, counting the original"
	dock.dup_grid_row.add_child(dock.dup_grid_x)
	dock.dup_grid_y = _setting_spin("grid_array", "count_y")
	dock.dup_grid_y.tooltip_text = "Cells along Y, counting the original"
	dock.dup_grid_row.add_child(dock.dup_grid_y)
	dock.dup_grid_z = _setting_spin("grid_array", "count_z")
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

	# What an Update would undo. Its own label rather than the summary line, which
	# the ghost rewrites on every turn of a control.
	dock.dup_warning = Label.new()
	dock.dup_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.dup_warning.visible = false
	sc.add_child(dock.dup_warning)

	var dup_btns = HBoxContainer.new()
	sc.add_child(dup_btns)
	dock.dup_create_btn = HFUIFactoryType.make_button(
		"Create Array",
		"Create a duplicate array from the selected brushes, or update the one they belong to"
	)
	dock.dup_create_btn.pressed.connect(dock._on_create_duplicate_array)
	dup_btns.add_child(dock.dup_create_btn)
	var remove_dup_btn = HFUIFactoryType.make_button(
		"Remove Array", "Delete the copies and the array they belong to"
	)
	remove_dup_btn.pressed.connect(dock._on_remove_duplicate_array)
	dup_btns.add_child(remove_dup_btn)
	dock.dup_detach_btn = HFUIFactoryType.make_button(
		"Detach", "Stop this array being rebuilt, and keep its copies as ordinary brushes"
	)
	dock.dup_detach_btn.visible = false
	dock.dup_detach_btn.pressed.connect(dock._on_detach_duplicate_array)
	dup_btns.add_child(dock.dup_detach_btn)


## A spin box for setting `key` of command `id`, with the range, step and
## default the command table gives it.
static func _setting_spin(id: String, key: String) -> SpinBox:
	var setting: Dictionary = HFCommandRegistryType.field(id, key)
	return HFUIFactoryType.make_spin(
		float(setting["min"]),
		float(setting["max"]),
		float(setting["step"]),
		float(setting["default"])
	)


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
	if dock.apply_rotation_scale_btn:
		dock.apply_rotation_scale_btn.pressed.connect(dock._on_apply_rotation_scale)
	for check in [dock.mirror_copy_x_check, dock.mirror_copy_y_check, dock.mirror_copy_z_check]:
		if check:
			(check as CheckBox).toggled.connect(dock._on_mirror_copy_axes_changed)
	if dock.mirror_copy_edge_check:
		dock.mirror_copy_edge_check.toggled.connect(dock._on_mirror_copy_edge_toggled)
	if dock.mirror_copy_btn:
		dock.mirror_copy_btn.pressed.connect(dock._on_mirror_copy)
	if dock.hollow_btn:
		dock.hollow_btn.pressed.connect(dock._on_hollow)
	if dock.move_floor_btn:
		dock.move_floor_btn.pressed.connect(dock._on_move_to_floor)
	if dock.move_ceiling_btn:
		dock.move_ceiling_btn.pressed.connect(dock._on_move_to_ceiling)
	if dock.snap_to_grid_btn:
		dock.snap_to_grid_btn.pressed.connect(dock._on_snap_to_grid)
	if dock.tie_entity_btn:
		dock.tie_entity_btn.pressed.connect(dock._on_tie_entity)
	if dock.untie_entity_btn:
		dock.untie_entity_btn.pressed.connect(dock._on_untie_entity)
	if dock.clip_btn:
		dock.clip_btn.pressed.connect(dock._on_clip)
	if dock.brush_cast_shadow_opt:
		dock.brush_cast_shadow_opt.item_selected.connect(dock._on_brush_cast_shadow_selected)
	if dock.brush_lightmap_scale_spin:
		dock.brush_lightmap_scale_spin.value_changed.connect(dock._on_brush_lightmap_scale_changed)


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
