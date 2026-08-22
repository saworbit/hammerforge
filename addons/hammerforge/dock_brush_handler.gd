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
	var off = Vector3(
		dock.dup_offset_x.value if dock.dup_offset_x else 8,
		dock.dup_offset_y.value if dock.dup_offset_y else 0,
		dock.dup_offset_z.value if dock.dup_offset_z else 0,
	)
	dock._commit_state_action(
		"Create Duplicate Array", "create_duplicate_array", [brush_ids, cnt, off]
	)
	dock._set_status("Created %d copies" % cnt)


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
