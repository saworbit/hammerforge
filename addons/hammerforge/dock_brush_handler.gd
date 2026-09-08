@tool
class_name HFDockBrushHandler
extends RefCounted
## Build-tab brush handlers extracted from dock.gd (displacement, bevel,
## hollow, clip, floor/ceiling, duplicate array, tie/untie).

const HFUndoHelper = preload("undo_helper.gd")


static func on_disp_create(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action(
		"Create Displacement", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var info: Dictionary = dock._get_selected_face_info()
	if info.is_empty():
		dock.show_toast("Select a quad face first", 1)
		return
	var power: int = int(dock._disp_power_spin.value) if dock._disp_power_spin else 3
	var ok: bool = dock._try_undoable_action(
		"Create Displacement", "create_displacement", [info["brush_id"], info["face_index"], power]
	)
	if ok:
		dock.show_toast("Displacement created (power %d)" % power, 0)
	else:
		dock.show_toast("Failed — face must be a quad (4 vertices)", 2)


static func on_disp_destroy(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action(
		"Destroy Displacement", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var info: Dictionary = dock._get_selected_face_info()
	if info.is_empty():
		dock.show_toast("Select a displaced face first", 1)
		return
	var ok: bool = dock._try_undoable_action(
		"Destroy Displacement", "destroy_displacement", [info["brush_id"], info["face_index"]]
	)
	if ok:
		dock.show_toast("Displacement removed", 0)
	else:
		dock.show_toast("Face has no displacement to remove", 2)


static func on_disp_elevation_changed(dock: Object, value: float) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action(
		"Edit Displacement", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var info: Dictionary = dock._get_selected_face_info()
	if info.is_empty():
		return
	if not dock._selected_face_has_displacement(info):
		return
	var brush_id: String = info["brush_id"]
	var face_idx: int = info["face_index"]
	HFUndoHelper.commit(
		dock.undo_redo,
		dock.level_root,
		"Set Displacement Elevation",
		"set_displacement_elevation",
		[brush_id, face_idx, value],
		false,
		Callable(dock, "record_history"),
		"disp_elevation_%s_%d" % [brush_id, face_idx]
	)


static func on_disp_smooth(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action(
		"Smooth Displacement", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var info: Dictionary = dock._get_selected_face_info()
	if info.is_empty():
		dock.show_toast("Select a displaced face first", 1)
		return
	var strength: float = dock._disp_strength_spin.value if dock._disp_strength_spin else 0.5
	var ok: bool = dock._try_undoable_action(
		"Smooth Displacement",
		"smooth_displacement",
		[info["brush_id"], info["face_index"], strength]
	)
	if ok:
		dock.show_toast("Displacement smoothed", 0)
	else:
		dock.show_toast("Smooth failed — face has no displacement", 2)


static func on_disp_noise(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action(
		"Noise Displacement", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var info: Dictionary = dock._get_selected_face_info()
	if info.is_empty():
		dock.show_toast("Select a displaced face first", 1)
		return
	var scale: float = dock._disp_strength_spin.value if dock._disp_strength_spin else 1.0
	var ok: bool = dock._try_undoable_action(
		"Noise Displacement", "noise_displacement", [info["brush_id"], info["face_index"], scale]
	)
	if ok:
		dock.show_toast("Noise applied to displacement", 0)
	else:
		dock.show_toast("Noise failed — face has no displacement", 2)


static func on_disp_sew(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	# Capture state, execute, then commit undo only if vertices were actually sewn.
	var pre_state: Dictionary = (
		dock.level_root.capture_state() if dock.level_root.has_method("capture_state") else {}
	)
	var count: int = dock.level_root.sew_all_displacements()
	if count > 0 and dock.undo_redo and not pre_state.is_empty():
		var post_state: Dictionary = dock.level_root.capture_state()
		dock.undo_redo.create_action("Sew Displacements", 0, null, false)
		dock.undo_redo.add_do_method(dock.level_root, "restore_state", post_state)
		dock.undo_redo.add_undo_method(dock.level_root, "restore_state", pre_state)
		dock.undo_redo.commit_action(false)
		dock.record_history("Sew Displacements")
	dock.show_toast("Sewn %d boundary vertices" % count, 0)


static func on_disp_sew_group_changed(dock: Object, value: float) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action(
		"Edit Displacement Sew Group", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var info: Dictionary = dock._get_selected_face_info()
	if info.is_empty():
		return
	if not dock._selected_face_has_displacement(info):
		return
	var brush_id: String = info["brush_id"]
	var face_idx: int = info["face_index"]
	HFUndoHelper.commit(
		dock.undo_redo,
		dock.level_root,
		"Set Sew Group",
		"set_displacement_sew_group",
		[brush_id, face_idx, int(value)],
		false,
		Callable(dock, "record_history"),
		"disp_sew_group_%s_%d" % [brush_id, face_idx]
	)


static func on_bevel_edge(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action("Bevel Edge", dock.DockSelectionRequirement.BRUSHES_ONLY):
		return
	var plugin_ref = dock.level_root.get_meta("_hf_plugin", null)
	if not plugin_ref:
		dock.show_toast("No plugin reference", 2)
		return
	if not plugin_ref.get("_vertex_mode") or not dock.level_root.vertex_system:
		dock.show_toast("Enter vertex/edge mode first (V key)", 1)
		return
	var vs = dock.level_root.vertex_system
	if vs.selected_edges.is_empty():
		dock.show_toast("Select an edge first (edge sub-mode)", 1)
		return
	var segments: int = int(dock._bevel_segments_spin.value) if dock._bevel_segments_spin else 2
	var radius: float = dock._bevel_radius_spin.value if dock._bevel_radius_spin else 2.0
	# Capture state once before the batch, call each bevel, track actual successes.
	var pre_state: Dictionary = (
		dock.level_root.capture_state() if dock.level_root.has_method("capture_state") else {}
	)
	var count := 0
	for brush_id in vs.selected_edges:
		var edges: Array = vs.selected_edges[brush_id]
		for edge in edges:
			if dock.level_root.bevel_edge(brush_id, edge, segments, radius):
				count += 1
	if count > 0:
		if dock.undo_redo and not pre_state.is_empty():
			var post_state: Dictionary = dock.level_root.capture_state()
			dock.undo_redo.create_action("Bevel Edge", 0, null, false)
			dock.undo_redo.add_do_method(dock.level_root, "restore_state", post_state)
			dock.undo_redo.add_undo_method(dock.level_root, "restore_state", pre_state)
			dock.undo_redo.commit_action(false)
			dock.record_history("Bevel Edge")
		dock.show_toast("Beveled %d edge(s)" % count, 0)
	else:
		dock.show_toast("Bevel failed — check edge selection", 2)


static func on_bevel_inset(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action("Inset Face", dock.DockSelectionRequirement.BRUSHES_ONLY):
		return
	var info: Dictionary = dock._get_selected_face_info()
	if info.is_empty():
		dock.show_toast("Select a face first", 1)
		return
	var inset_dist: float = (
		dock._bevel_inset_dist_spin.value if dock._bevel_inset_dist_spin else 2.0
	)
	var height: float = (
		dock._bevel_inset_height_spin.value if dock._bevel_inset_height_spin else 0.0
	)
	var pre_state: Dictionary = (
		dock.level_root.capture_state() if dock.level_root.has_method("capture_state") else {}
	)
	var ok: bool = dock.level_root.inset_face(
		info["brush_id"], info["face_index"], inset_dist, height
	)
	if ok:
		if dock.undo_redo and not pre_state.is_empty():
			var post_state: Dictionary = dock.level_root.capture_state()
			dock.undo_redo.create_action("Inset Face", 0, null, false)
			dock.undo_redo.add_do_method(dock.level_root, "restore_state", post_state)
			dock.undo_redo.add_undo_method(dock.level_root, "restore_state", pre_state)
			dock.undo_redo.commit_action(false)
			dock.record_history("Inset Face")
		dock.show_toast("Face inset applied", 0)
	else:
		dock.show_toast("Inset failed — distance too large or face too small", 2)


static func on_hollow(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		if dock:
			dock._set_status("Select a brush to hollow", true)
		return
	if not dock._guard_selection_action("Hollow", dock.DockSelectionRequirement.BRUSHES_ONLY):
		return
	var brush = dock._first_selected_brush()
	if not brush:
		dock._set_status("Select a brush to hollow", true)
		return
	var info = dock.level_root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return
	var thickness = dock.hollow_thickness.value if dock.hollow_thickness else 4.0
	var check: HFOpResult = dock.level_root.can_hollow_brush(brush_id, thickness)
	if not check.ok:
		dock.show_toast(check.user_text(), 1)
		return
	# Show geometry preview and confirm
	dock.level_root.hollow_preview.show_preview(brush_id, thickness)
	var dlg = ConfirmationDialog.new()
	dlg.title = "Hollow Brush"
	dlg.dialog_text = (
		"Hollow with wall thickness %.1f?\n(Yellow wireframe shows resulting walls)" % thickness
	)
	dlg.min_size = Vector2i(300, 100)
	dock.add_child(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(dock):
				return
			if dock.level_root and dock.level_root.hollow_preview:
				dock.level_root.hollow_preview.clear()
			if not dock._guard_selection_action(
				"Hollow", dock.DockSelectionRequirement.BRUSHES_ONLY
			):
				dlg.queue_free()
				return
			dock._commit_state_action("Hollow", "hollow_brush_by_id", [brush_id, thickness])
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(dock):
				return
			if dock.level_root and dock.level_root.hollow_preview:
				dock.level_root.hollow_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()


static func on_move_to_floor(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		return
	if not dock._guard_selection_action(
		"Move to Floor", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var brush_ids: Array = []
	for node in dock._selection_nodes:
		if dock.level_root.is_brush_node(node):
			var info = dock.level_root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return
	dock._commit_state_action("Move to Floor", "move_brushes_to_floor", [brush_ids])


static func on_move_to_ceiling(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		return
	if not dock._guard_selection_action(
		"Move to Ceiling", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var brush_ids: Array = []
	for node in dock._selection_nodes:
		if dock.level_root.is_brush_node(node):
			var info = dock.level_root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return
	dock._commit_state_action("Move to Ceiling", "move_brushes_to_ceiling", [brush_ids])


static func on_create_duplicate_array(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		if dock:
			dock._set_status("Select brushes first", true)
		return
	if not dock._guard_selection_action(
		"Create Duplicate Array", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var brush_ids = PackedStringArray()
	for node in dock._selection_nodes:
		if dock.level_root.is_brush_node(node):
			var info = dock.level_root.get_brush_info_from_node(node)
			if info and info.has("brush_id"):
				brush_ids.append(info["brush_id"])
	if brush_ids.is_empty():
		dock._set_status("No brushes selected", true)
		return
	var cnt = int(dock.dup_count_spin.value) if dock.dup_count_spin else 3
	var mode: int = dock.dup_mode_opt.selected if dock.dup_mode_opt else 0
	match mode:
		1:
			_create_radial_array(dock, brush_ids, cnt)
		2:
			_create_grid_array(dock, brush_ids)
		_:
			var off = Vector3(
				dock.dup_offset_x.value if dock.dup_offset_x else 8,
				dock.dup_offset_y.value if dock.dup_offset_y else 0,
				dock.dup_offset_z.value if dock.dup_offset_z else 0,
			)
			dock._commit_state_action(
				"Create Duplicate Array", "create_duplicate_array", [brush_ids, cnt, off]
			)
			dock._set_status("Created %d copies" % cnt)


static func _create_radial_array(dock: Object, brush_ids: PackedStringArray, cnt: int) -> void:
	var axis_index: int = dock.dup_axis_opt.selected if dock.dup_axis_opt else 1
	var rise: float = dock.dup_rise_spin.value if dock.dup_rise_spin else 0.0
	var step: float = dock.dup_step_spin.value if dock.dup_step_spin else 90.0
	# "Fill 360" spaces the copies and the source evenly around a closed ring, so
	# the last copy stops one step short of the source rather than on top of it.
	if dock.dup_fill_check and dock.dup_fill_check.button_pressed:
		step = 360.0 / float(cnt + 1)
	var pivot: Vector3 = dock.level_root.resolve_transform_pivot(Array(brush_ids), [])
	dock._commit_state_action(
		"Create Radial Array",
		"create_radial_array",
		[brush_ids, cnt, axis_index, step, pivot, rise]
	)
	if is_zero_approx(rise):
		dock._set_status("Created %d copies %.1f° apart" % [cnt, step])
	else:
		dock._set_status("Created %d copies %.1f° apart, rising %.1f" % [cnt, step, rise])


static func _create_grid_array(dock: Object, brush_ids: PackedStringArray) -> void:
	var counts := Vector3i(
		int(dock.dup_grid_x.value) if dock.dup_grid_x else 2,
		int(dock.dup_grid_y.value) if dock.dup_grid_y else 1,
		int(dock.dup_grid_z.value) if dock.dup_grid_z else 2
	)
	var spacing = Vector3(
		dock.dup_offset_x.value if dock.dup_offset_x else 64,
		dock.dup_offset_y.value if dock.dup_offset_y else 64,
		dock.dup_offset_z.value if dock.dup_offset_z else 64,
	)
	var total: int = counts.x * counts.y * counts.z - 1
	if total < 1:
		dock._set_status("Grid array needs more than one cell", true)
		return
	dock._commit_state_action(
		"Create Grid Array", "create_grid_array", [brush_ids, counts, spacing]
	)
	dock._set_status("Created %d copies" % total)


## Only the row that belongs to the chosen layout stays on screen.
static func on_duplicate_array_mode_changed(dock: Object, index: int) -> void:
	if dock.dup_linear_row:
		dock.dup_linear_row.visible = index != 1
	if dock.dup_radial_row:
		dock.dup_radial_row.visible = index == 1
	if dock.dup_grid_row:
		dock.dup_grid_row.visible = index == 2


# ---------------------------------------------------------------------------
# Free transform
# ---------------------------------------------------------------------------


## Brush ids and entity paths for the dock's current selection, in the shape the
## LevelRoot managed-node methods take.
static func _transform_targets(dock: Object) -> Dictionary:
	var brush_ids: Array = []
	var entity_paths: Array = []
	for node in dock._selection_nodes:
		if not is_instance_valid(node):
			continue
		if dock.level_root.is_brush_node(node):
			var info = dock.level_root.get_brush_info_from_node(node)
			var brush_id := str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
		elif dock.level_root.is_entity_node(node):
			entity_paths.append(dock.level_root.get_path_to(node))
	return {"brush_ids": brush_ids, "entity_paths": entity_paths}


## The type currently chosen in the Structure section.
static func structure_type(dock: Object) -> String:
	if dock == null or dock.structure_type_option == null:
		return HFGeneratorSystem.TYPE_ARCH
	var index: int = dock.structure_type_option.selected
	if index < 0:
		return HFGeneratorSystem.TYPE_ARCH
	return str(dock.structure_type_option.get_item_metadata(index))


## Build the section controls from the chosen builder own description of its
## settings.
##
## This is the whole point of the schema. Nothing here knows what an arch or a
## staircase is made of, so a new generator needs no dock code at all.
static func rebuild_structure_fields(dock: Object) -> void:
	if dock == null or dock.structure_fields_box == null:
		return
	for child in dock.structure_fields_box.get_children():
		dock.structure_fields_box.remove_child(child)
		child.queue_free()
	dock.structure_fields.clear()

	var type := structure_type(dock)
	var row: HBoxContainer = null
	var in_row := 0
	for entry in HFGeneratorSystem.settings_schema(type):
		var schema_field: Dictionary = entry
		var key := str(schema_field["key"])
		var control := _make_field_control(schema_field)
		if control == null:
			continue
		control.tooltip_text = str(schema_field.get("tooltip", ""))
		_watch_structure_field(dock, control)
		dock.structure_fields[key] = control
		# Two to a row, the way the section has always read, so a six-setting
		# generator is three lines rather than six.
		if control is CheckBox:
			dock.structure_fields_box.add_child(control)
			row = null
			in_row = 0
			continue
		if row == null or in_row >= 2:
			row = HBoxContainer.new()
			dock.structure_fields_box.add_child(row)
			in_row = 0
		var label := Label.new()
		label.text = "%s:" % str(schema_field.get("label", key))
		row.add_child(label)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(control)
		in_row += 1


## Keep the ghost in step with the control the user is turning.
##
## Every schema type carries exactly one argument on its change signal, so one
## handler serves all of them and a new field type needs no new wiring here.
static func _watch_structure_field(dock: Object, control: Control) -> void:
	var handler := Callable(dock, "_on_structure_setting_changed")
	if control is CheckBox:
		(control as CheckBox).toggled.connect(handler)
	elif control is OptionButton:
		(control as OptionButton).item_selected.connect(handler)
	elif control is SpinBox:
		(control as SpinBox).value_changed.connect(handler)


static func _make_field_control(schema_field: Dictionary) -> Control:
	match str(schema_field.get("type", HFGeneratorSchema.TYPE_FLOAT)):
		HFGeneratorSchema.TYPE_BOOL:
			return HFUIFactory.make_check(
				str(schema_field.get("label", "")), bool(schema_field.get("default", false))
			)
		HFGeneratorSchema.TYPE_ENUM:
			var option := HFUIFactory.make_option(schema_field.get("options", []))
			option.selected = int(schema_field.get("default", 0))
			return option
		_:
			return HFUIFactory.make_spin(
				float(schema_field.get("min", 0.0)),
				float(schema_field.get("max", 4096.0)),
				float(schema_field.get("step", 1.0)),
				float(schema_field.get("default", 0.0))
			)


## Read the section controls back out as settings for the chosen builder.
static func collect_structure_settings(dock: Object) -> Dictionary:
	var type := structure_type(dock)
	var settings: Dictionary = HFGeneratorSystem.default_settings(type)
	if dock == null:
		return settings
	for key in settings:
		var control = dock.structure_fields.get(str(key), null)
		if control == null:
			continue
		if control is CheckBox:
			settings[key] = control.button_pressed
		elif control is OptionButton:
			settings[key] = control.selected
		elif control is SpinBox:
			settings[key] = control.value
	return HFGeneratorSchema.merge(HFGeneratorSystem.settings_schema(type), settings)


## Choosing a type from the dropdown is a decision to build that thing.
##
## It deliberately does not go back through the selection. Picking Dome while a
## piece of an arch is still selected would otherwise be answered by putting the
## dropdown straight back on Arch, and the only way to build a dome would be to
## click empty space first.
static func on_structure_type_changed(dock: Object) -> void:
	if dock == null:
		return
	dock._active_generator_id = ""
	rebuild_structure_fields(dock)
	if dock.structure_create_btn:
		dock.structure_create_btn.text = (
			"Create %s" % HFGeneratorSystem.display_name(structure_type(dock))
		)
	if dock.structure_detach_btn:
		dock.structure_detach_btn.visible = false
	_show_edit_warning(dock, 0)
	refresh_structure_preview(dock)


## Load the selected structure settings into the section, or reset it to
## creating a new one.
static func refresh_structure_section(dock: Object) -> void:
	if dock == null or dock.structure_create_btn == null:
		return
	var record = null
	if dock.level_root and dock.level_root.has_method("generator_for_selection"):
		record = dock.level_root.generator_for_selection(_transform_targets(dock)["brush_ids"])
	if record == null or HFGeneratorSystem.builder_for(record.type) == null:
		dock._active_generator_id = ""
		dock.structure_create_btn.text = (
			"Create %s" % HFGeneratorSystem.display_name(structure_type(dock))
		)
		if dock.structure_detach_btn:
			dock.structure_detach_btn.visible = false
		_show_edit_warning(dock, 0)
		refresh_structure_preview(dock)
		return

	if str(dock._active_generator_id) != str(record.generator_id):
		dock._structure_overwrite_ack = ""
	dock._active_generator_id = record.generator_id
	if structure_type(dock) != record.type:
		_select_type(dock, record.type)
		rebuild_structure_fields(dock)
	dock.structure_create_btn.text = "Update %s" % HFGeneratorSystem.display_name(record.type)
	if dock.structure_detach_btn:
		dock.structure_detach_btn.visible = true
	_load_structure_settings(dock, record.settings)
	_show_edit_warning(dock, _edited_piece_count(dock, record.generator_id), record.generator_id)
	refresh_structure_preview(dock)


## Say how many pieces a rebuild would overwrite, before it overwrites them.
##
## Detach is the answer to a structure that has been edited by hand, and it sits
## right beside Update — but a choice you do not know you are making is not a
## choice, so the count is said out loud.
static func _show_edit_warning(dock: Object, edited: int, generator_id: String = "") -> void:
	if dock == null or dock.structure_warning == null:
		return
	# Where the structure is has to be said before what shape its pieces are in.
	# A rebuild that carries the whole thing back across the level is the larger
	# surprise, and counting shapes does not mention it.
	if generator_id != "" and _pieces_disagree(dock, generator_id):
		_show_structure_message(
			dock,
			(
				"These pieces no longer agree on where the structure is. Update will rebuild it "
				+ "where it was created — Detach to keep them where they are."
			)
		)
		return
	if edited <= 0:
		_show_structure_message(dock, "")
		return
	_show_structure_message(
		dock,
		(
			"%d piece%s been edited by hand. Update will rebuild over %s — Detach to keep them."
			% [edited, " has" if edited == 1 else "s have", "it" if edited == 1 else "them"]
		)
	)


static func _pieces_disagree(dock: Object, generator_id: String) -> bool:
	if dock == null or not dock.level_root:
		return false
	if not dock.level_root.has_method("generator_pieces_disagree"):
		return false
	return bool(dock.level_root.generator_pieces_disagree(generator_id))


## Draw a ghost of what the button would build, before it builds it.
##
## Gated rather than always on. The ghost stands in the viewport, so it shows only
## while the section that owns it is open and its tab is in front; anything else
## leaves a wireframe floating with nothing on screen to explain where it came
## from.
##
## Settings that cannot build draw nothing, and an empty viewport is not an
## answer — so the refusal goes in the section's own message line, which is where
## the other things worth knowing before you press the button already are.
static func refresh_structure_preview(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock.level_root.has_method("preview_structure"):
		return
	if not _structure_preview_wanted(dock):
		dock.level_root.clear_structure_preview()
		return

	var generator_id := str(dock._active_generator_id)
	var type := structure_type(dock)
	var placement := Transform3D.IDENTITY
	if generator_id != "":
		var record = dock.level_root.generator_for_id(generator_id)
		if record == null:
			generator_id = ""
		else:
			type = record.type
			placement = dock.level_root.generator_rebuild_placement(generator_id)
	if generator_id == "":
		# Where Create would centre it, which is where the transform commands
		# would pivot — the same answer the button itself uses.
		var targets := _transform_targets(dock)
		placement = Transform3D(
			Basis.IDENTITY,
			dock.level_root.resolve_transform_pivot(targets["brush_ids"], targets["entity_paths"])
		)

	var settings := collect_structure_settings(dock)
	var check: HFOpResult = dock.level_root.can_build_generator(type, settings)
	if not check.ok:
		dock.level_root.clear_structure_preview()
		_show_structure_message(dock, check.user_text())
		return
	dock.level_root.preview_structure(type, settings, placement)
	# Any redraw means the section is being looked at again, so a paint warning
	# that has scrolled off it has to be earned a second time. Otherwise the
	# acknowledgement outlives the sentence that asked for it.
	dock._structure_overwrite_ack = ""
	_show_edit_warning(
		dock, _edited_piece_count(dock, generator_id) if generator_id != "" else 0, generator_id
	)


## The ghost belongs to the Structure section, and follows it out of sight.
static func _structure_preview_wanted(dock: Object) -> bool:
	var section = dock._structure_section
	if section == null or not is_instance_valid(section) or not section.is_expanded():
		return false
	var tabs = dock.main_tabs
	if tabs == null or not is_instance_valid(tabs):
		return true
	return tabs.get_tab_title(tabs.current_tab) == "Build"


static func _show_structure_message(dock: Object, text: String) -> void:
	if dock == null or dock.structure_warning == null:
		return
	dock.structure_warning.visible = text != ""
	dock.structure_warning.text = text


static func _edited_piece_count(dock: Object, generator_id: String) -> int:
	if dock == null or not dock.level_root:
		return 0
	if not dock.level_root.has_method("edited_generator_pieces"):
		return 0
	return int(dock.level_root.edited_generator_pieces(generator_id))


static func _select_type(dock: Object, type: String) -> void:
	if dock == null or dock.structure_type_option == null:
		return
	for i in dock.structure_type_option.item_count:
		if str(dock.structure_type_option.get_item_metadata(i)) == type:
			dock.structure_type_option.selected = i
			return


static func _load_structure_settings(dock: Object, settings: Dictionary) -> void:
	if dock == null:
		return
	for key in settings:
		var control = dock.structure_fields.get(str(key), null)
		if control == null:
			continue
		# Writing a value back into a control must not read as the user editing it.
		if control is CheckBox:
			control.set_pressed_no_signal(bool(settings[key]))
		elif control is OptionButton:
			control.selected = int(settings[key])
		elif control is SpinBox:
			control.set_value_no_signal(float(settings[key]))


static func on_detach_generator(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._active_generator_id == "":
		return
	dock._commit_state_action("Detach Structure", "detach_generator", [dock._active_generator_id])
	dock._active_generator_id = ""
	dock._set_status("Structure detached — its brushes are ordinary geometry now")
	refresh_structure_section(dock)
	dock.level_root.clear_structure_preview()


## Build a structure, centred on whatever is selected, or on the world origin.
##
## Placing it where the transform commands would pivot is the least surprising
## answer, and it means a structure lands somewhere you were already looking.
static func on_create_structure(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	var type := structure_type(dock)
	var settings := collect_structure_settings(dock)
	# Editing an existing structure rather than making another one: the section
	# switched to Update when a piece of it was selected.
	var generator_id := str(dock._active_generator_id)
	if generator_id != "":
		_update_structure(dock, generator_id, settings)
		return
	var label := HFGeneratorSystem.display_name(type)
	# Ask whether these settings build before opening an undo action. Each field
	# can be in range while the combination is not, and a refused build would
	# otherwise leave an empty entry in the history under a success message.
	var check: HFOpResult = dock.level_root.can_build_generator(type, settings)
	if not check.ok:
		dock._set_status(check.user_text(), true)
		return
	var targets := _transform_targets(dock)
	var centre: Vector3 = dock.level_root.resolve_transform_pivot(
		targets["brush_ids"], targets["entity_paths"]
	)
	var before: int = dock.level_root.generator_count()
	dock._commit_state_action(
		"Create %s" % label,
		"create_generator",
		[type, settings, Transform3D(Basis.IDENTITY, centre)]
	)
	if dock.level_root.generator_count() > before:
		dock._set_status("Created a %s" % label.to_lower())
	else:
		dock._set_status("%s was not created" % label, true)
	refresh_structure_section(dock)
	# The ghost showed what was not there yet. It is there now, so it stops
	# standing on top of itself; the next change to the settings brings it back.
	dock.level_root.clear_structure_preview()


## Rebuild the selected structure. A refused rebuild has to leave it alone and
## say so, rather than reporting that it was rebuilt.
static func _update_structure(dock: Object, generator_id: String, settings: Dictionary) -> void:
	var record = dock.level_root.generator_for_id(generator_id)
	if record == null:
		dock._set_status("That structure is no longer in the level", true)
		refresh_structure_section(dock)
		return
	var label := HFGeneratorSystem.display_name(record.type)
	var check: HFOpResult = dock.level_root.can_build_generator(record.type, settings)
	if not check.ok:
		dock._set_status("%s not changed. %s" % [label, check.user_text()], true)
		return
	# Painting a generated structure is normal authoring work. A rebuild carries it
	# across whenever the pieces still line up, and when they do not the user gets
	# to see that before it goes, with Detach sitting beside the button.
	if not _confirm_appearance_overwrite(dock, generator_id, settings):
		return
	dock._commit_state_action("Update %s" % label, "regenerate_generator", [generator_id, settings])
	dock._structure_overwrite_ack = ""
	if dock.level_root.has_generator(generator_id):
		dock._set_status("%s rebuilt" % label)
	else:
		dock._set_status("%s was not rebuilt" % label, true)
	refresh_structure_section(dock)
	dock.level_root.clear_structure_preview()


## False when the user has not yet seen that this rebuild would drop painted
## faces. The first press warns and stops; a second press of the same settings
## goes ahead, and Detach is the other way out.
static func _confirm_appearance_overwrite(
	dock: Object, generator_id: String, settings: Dictionary
) -> bool:
	if not dock.level_root.has_method("generator_appearance_at_risk"):
		return true
	var at_risk: int = dock.level_root.generator_appearance_at_risk(generator_id, settings).size()
	if at_risk <= 0:
		dock._structure_overwrite_ack = ""
		return true
	var token := "%s|%d" % [generator_id, hash(settings)]
	if str(dock._structure_overwrite_ack) == token:
		return true
	dock._structure_overwrite_ack = token
	_show_paint_warning(dock, at_risk)
	dock._set_status("Press Update again to rebuild over the painted faces", true)
	return false


static func _show_paint_warning(dock: Object, at_risk: int) -> void:
	_show_structure_message(
		dock,
		(
			"%d piece%s painted faces these settings cannot keep. Update again to rebuild over %s, or Detach to keep them."
			% [at_risk, " has" if at_risk == 1 else "s have", "it" if at_risk == 1 else "them"]
		)
	)


static func on_rotate_selection(dock: Object, direction: int) -> void:
	if dock == null or not dock.level_root:
		return
	var targets := _transform_targets(dock)
	var brush_ids: Array = targets["brush_ids"]
	var entity_paths: Array = targets["entity_paths"]
	if brush_ids.is_empty() and entity_paths.is_empty():
		dock._set_status("Select a brush or entity first", true)
		return
	var step := absf(float(dock.level_root.rotate_snap_degrees))
	if is_zero_approx(step):
		dock._set_status("Rotate step is zero", true)
		return
	var angle := step if direction >= 0 else -step
	var axis_index: int = dock.level_root.transform_axis_index(1)
	var pivot: Vector3 = dock.level_root.resolve_transform_pivot(brush_ids, entity_paths)
	dock._commit_state_action(
		"Rotate HammerForge Objects",
		"rotate_managed_nodes",
		[brush_ids, entity_paths, axis_index, angle, pivot]
	)
	dock._set_status("Rotated %.1f°" % angle)


static func on_flip_selection(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	var targets := _transform_targets(dock)
	var brush_ids: Array = targets["brush_ids"]
	var entity_paths: Array = targets["entity_paths"]
	if brush_ids.is_empty() and entity_paths.is_empty():
		dock._set_status("Select a brush or entity first", true)
		return
	var check = dock.level_root.can_flip_brushes(brush_ids)
	if not check.ok:
		dock._set_status(check.user_text(), true)
		return
	var axis_index: int = dock.level_root.transform_axis_index(0)
	var pivot: Vector3 = dock.level_root.resolve_transform_pivot(brush_ids, entity_paths)
	dock._commit_state_action(
		"Flip HammerForge Objects",
		"flip_managed_nodes",
		[brush_ids, entity_paths, axis_index, pivot]
	)
	dock._set_status("Flipped across %s" % ["X", "Y", "Z"][clampi(axis_index, 0, 2)])


static func on_reset_rotation(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	var targets := _transform_targets(dock)
	var brush_ids: Array = targets["brush_ids"]
	if brush_ids.is_empty():
		dock._set_status("Select a brush first", true)
		return
	dock._commit_state_action("Reset HammerForge Rotation", "reset_managed_rotation", [brush_ids])
	dock._set_status("Rotation cleared")


static func on_remove_duplicate_array(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		if dock:
			dock._set_status("Select a duplicator source brush", true)
		return
	if not dock._guard_selection_action(
		"Remove Duplicate Array", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	for node in dock._selection_nodes:
		if not dock.level_root.is_brush_node(node):
			continue
		var dup_id: String = str(node.get_meta("duplicator_id", ""))
		if dup_id != "":
			dock._commit_state_action("Remove Duplicate Array", "remove_duplicate_array", [dup_id])
			dock._set_status("Removed duplicate array")
			return
	dock._set_status("Selected brush is not a duplicator source", true)


static func on_tie_entity(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		if dock:
			dock._set_status("Select brushes to tie", true)
		return
	if not dock._guard_selection_action(
		"Tie to Entity", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var class_name_str := "func_detail"
	if (
		dock.brush_entity_class_opt
		and dock.brush_entity_class_opt.item_count > 0
		and dock.brush_entity_class_opt.selected >= 0
	):
		class_name_str = dock.brush_entity_class_opt.get_item_text(
			dock.brush_entity_class_opt.selected
		)
	var brush_ids: Array = []
	for node in dock._selection_nodes:
		if dock.level_root.is_brush_node(node):
			var info = dock.level_root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return
	dock._commit_state_action("Tie to Entity", "tie_brushes_to_entity", [brush_ids, class_name_str])


static func on_untie_entity(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		return
	if not dock._guard_selection_action("Untie Entity", dock.DockSelectionRequirement.BRUSHES_ONLY):
		return
	var brush_ids: Array = []
	for node in dock._selection_nodes:
		if dock.level_root.is_brush_node(node):
			var info = dock.level_root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return
	dock._commit_state_action("Untie Entity", "untie_brushes_from_entity", [brush_ids])


static func get_hollow_thickness(dock: Object) -> float:
	if dock == null:
		return 4.0
	return dock.hollow_thickness.value if dock.hollow_thickness else 4.0


static func on_clip(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		if dock:
			dock._set_status("Select a brush to clip", true)
		return
	if not dock._guard_selection_action("Clip", dock.DockSelectionRequirement.BRUSHES_ONLY):
		return
	var brush = dock._first_selected_brush()
	if not brush:
		dock._set_status("Select a brush to clip", true)
		return
	var info = dock.level_root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return
	# Default clip: split along Y axis at center
	var center = info.get("center", Vector3.ZERO)
	var split_pos: float = center.y if center is Vector3 else 0.0
	var check: HFOpResult = dock.level_root.can_clip_brush(brush_id, 1, split_pos)
	if not check.ok:
		dock.show_toast(check.user_text(), 1)
		return
	# Show geometry preview and confirm
	dock.level_root.clip_preview.show_preview(brush_id, 1, split_pos)
	var dlg = ConfirmationDialog.new()
	dlg.title = "Clip Brush"
	dlg.dialog_text = (
		"Split brush along Y axis at %.1f?\n(Cyan wireframe shows resulting pieces)" % split_pos
	)
	dlg.min_size = Vector2i(300, 100)
	dock.add_child(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(dock):
				return
			if dock.level_root and dock.level_root.clip_preview:
				dock.level_root.clip_preview.clear()
			if not dock._guard_selection_action("Clip", dock.DockSelectionRequirement.BRUSHES_ONLY):
				dlg.queue_free()
				return
			dock._commit_state_action("Clip Brush", "clip_brush_by_id", [brush_id, 1, split_pos])
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(dock):
				return
			if dock.level_root and dock.level_root.clip_preview:
				dock.level_root.clip_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
