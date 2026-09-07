@tool
class_name HFPluginEditActions
extends RefCounted
## Undoable managed-object edit actions dispatched by HammerForge's command surfaces.

const HFUndoHelper = preload("undo_helper.gd")
const HFOpResult = preload("hf_op_result.gd")


static func delete_selected(plugin: Object, root: Node) -> bool:
	var selection = plugin.get_editor_interface().get_selection()
	var nodes = plugin._current_selection_nodes()
	var brush_ids: Array = []
	var entity_paths: Array = []
	for node in nodes:
		if root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			if info.is_empty():
				continue
			var brush_id = str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
		elif root.is_entity_node(node):
			var entity: Node = plugin._managed_entity_owner(root, node)
			if entity:
				entity_paths.append(root.get_path_to(entity))
	var object_count := brush_ids.size() + entity_paths.size()
	if object_count == 0:
		return false
	var action_name := (
		"Delete Brushes"
		if entity_paths.is_empty()
		else ("Delete Entities" if brush_ids.is_empty() else "Delete HammerForge Objects")
	)
	if object_count >= 3:
		var dlg = ConfirmationDialog.new()
		dlg.title = action_name
		dlg.dialog_text = (
			"Delete %d HammerForge objects? This can be undone with Ctrl+Z." % object_count
		)
		dlg.min_size = Vector2i(280, 80)
		plugin._add_confirmable_dialog(dlg)
		dlg.confirmed.connect(
			func():
				if not is_instance_valid(plugin) or not is_instance_valid(root):
					dlg.queue_free()
					return
				plugin.hf_selection.clear()
				selection.clear()
				HFUndoHelper.commit(
					plugin._get_undo_redo(),
					root,
					action_name,
					"delete_managed_nodes",
					[brush_ids, entity_paths],
					false,
					Callable(plugin, "_record_history")
				)
				dlg.queue_free()
		)
		dlg.canceled.connect(
			func():
				if not is_instance_valid(plugin):
					return
				dlg.queue_free()
		)
		dlg.popup_centered()
		return true
	plugin.hf_selection.clear()
	selection.clear()
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		action_name,
		"delete_managed_nodes",
		[brush_ids, entity_paths],
		false,
		Callable(plugin, "_record_history")
	)
	return true


static func duplicate_selected(plugin: Object, root: Node) -> bool:
	var selection = plugin.get_editor_interface().get_selection()
	var nodes = plugin._current_selection_nodes()
	var brush_infos: Array = []
	var entity_infos: Array = []
	var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
	for node in nodes:
		if root.is_brush_node(node):
			var info = root.build_duplicate_info(node, Vector3(step, 0.0, 0.0))
			if not info.is_empty():
				brush_infos.append(info)
		elif root.is_entity_node(node):
			var entity: Node = plugin._managed_entity_owner(root, node)
			if entity:
				var info: Dictionary = root.build_duplicate_entity_info(
					entity, Vector3(step, 0.0, 0.0)
				)
				if not info.is_empty():
					entity_infos.append(info)
	if brush_infos.is_empty() and entity_infos.is_empty():
		return false
	var action_name := (
		"Duplicate Brushes"
		if entity_infos.is_empty()
		else ("Duplicate Entities" if brush_infos.is_empty() else "Duplicate HammerForge Objects")
	)
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		action_name,
		"create_managed_duplicates",
		[brush_infos, entity_infos],
		false,
		Callable(plugin, "_record_history")
	)
	plugin.hf_selection.clear()
	for info in brush_infos:
		var duplicate_brush = root.find_brush_by_id(info.get("brush_id", ""))
		if duplicate_brush:
			plugin.hf_selection.append(duplicate_brush)
	for info in entity_infos:
		var duplicate_entity: Node = root.entities_node.get_node_or_null(
			NodePath(str(info.get("name", "")))
		)
		if duplicate_entity:
			plugin.hf_selection.append(duplicate_entity)
	plugin._apply_hf_selection(selection)
	return true


static func nudge_selected(plugin: Object, root: Node, direction: Vector3) -> bool:
	var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
	var nodes = plugin._current_selection_nodes()
	var brush_ids: Array = []
	var entity_paths: Array = []
	for node in nodes:
		if node and node is Node3D and root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			var brush_id = str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
		elif node and node is Node3D and root.is_entity_node(node):
			var entity: Node = plugin._managed_entity_owner(root, node)
			if entity:
				entity_paths.append(root.get_path_to(entity))
	if brush_ids.is_empty() and entity_paths.is_empty():
		return false
	var offset = direction * step
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Nudge HammerForge Objects",
		"nudge_managed_nodes",
		[brush_ids, entity_paths, offset],
		false,
		Callable(plugin, "_record_history"),
		"nudge"
	)
	return true


static func group_selected(plugin: Object, root: Node) -> bool:
	var nodes = plugin._hammerforge_selection_nodes(root)
	if nodes.size() < 2 or not root or not root.visgroup_system:
		return false
	var group_name = "group_%d" % Time.get_ticks_usec()
	root.visgroup_system.group_selection(group_name, nodes)
	plugin._record_history("Group Selection")
	if plugin.dock:
		plugin.dock.refresh_visgroup_ui()
	return true


static func ungroup_selected(plugin: Object, root: Node) -> bool:
	var nodes = plugin._hammerforge_selection_nodes(root)
	if nodes.is_empty() or not root or not root.visgroup_system:
		return false
	var grouped: Array = []
	for node in nodes:
		if str(root.visgroup_system.get_group_of(node)) != "":
			grouped.append(node)
	if grouped.is_empty():
		return false
	root.visgroup_system.ungroup_nodes(grouped)
	plugin._record_history("Ungroup Selection")
	if plugin.dock:
		plugin.dock.refresh_visgroup_ui()
	return true


static func hollow_selected(plugin: Object, root: Node) -> bool:
	var nodes = plugin._current_selection_nodes()
	if nodes.is_empty():
		return false
	var brush = nodes[0]
	if not root.is_brush_node(brush):
		return false
	var info = root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return false
	var thickness = plugin.dock.get_hollow_thickness() if plugin.dock else 4.0
	var check: HFOpResult = root.can_hollow_brush(brush_id, thickness)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	if root.hollow_preview:
		root.hollow_preview.show_preview(brush_id, thickness)
	var dlg = ConfirmationDialog.new()
	dlg.title = "Hollow Brush"
	dlg.dialog_text = (
		"Hollow with wall thickness %.1f?\n(Yellow wireframe shows resulting walls)" % thickness
	)
	dlg.min_size = Vector2i(300, 100)
	plugin._add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(plugin) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.hollow_preview:
				root.hollow_preview.clear()
			HFUndoHelper.commit(
				plugin._get_undo_redo(),
				root,
				"Hollow",
				"hollow_brush_by_id",
				[brush_id, thickness],
				false,
				Callable(plugin, "_record_history")
			)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(plugin):
				return
			if root and is_instance_valid(root) and root.hollow_preview:
				root.hollow_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


static func merge_selected(plugin: Object, root: Node) -> bool:
	var nodes = plugin._current_selection_nodes()
	var brush_ids: Array = []
	for node in nodes:
		if node and root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			var brush_id = str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
	if brush_ids.size() < 2:
		if plugin.dock:
			plugin.dock.show_toast("Select at least 2 brushes to merge", 1)
		return false
	var check: HFOpResult = root.can_merge_brushes(brush_ids)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Merge Brushes",
		"merge_brushes_by_ids",
		[brush_ids],
		false,
		Callable(plugin, "_record_history")
	)
	return true


static func move_selected_to_floor(plugin: Object, root: Node) -> bool:
	return move_selected_vertical(plugin, root, "Move to Floor", "move_brushes_to_floor")


static func move_selected_to_ceiling(plugin: Object, root: Node) -> bool:
	return move_selected_vertical(plugin, root, "Move to Ceiling", "move_brushes_to_ceiling")


static func move_selected_vertical(
	plugin: Object, root: Node, action_name: String, method_name: String
) -> bool:
	var nodes = plugin._current_selection_nodes()
	var brush_ids: Array = []
	for node in nodes:
		if node and root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			var brush_id = str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
	if brush_ids.is_empty():
		return false
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		action_name,
		method_name,
		[brush_ids],
		false,
		Callable(plugin, "_record_history")
	)
	return true


static func clip_selected(plugin: Object, root: Node) -> bool:
	var nodes = plugin._current_selection_nodes()
	if nodes.is_empty():
		return false
	var brush = nodes[0]
	if not root.is_brush_node(brush):
		return false
	var info = root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return false
	var center = info.get("center", Vector3.ZERO)
	var split_pos = center.y if center is Vector3 else 0.0
	var check: HFOpResult = root.can_clip_brush(brush_id, 1, split_pos)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	if root.clip_preview:
		root.clip_preview.show_preview(brush_id, 1, split_pos)
	var dlg = ConfirmationDialog.new()
	dlg.title = "Clip Brush"
	dlg.dialog_text = (
		"Split brush along Y axis at %.1f?\n(Cyan wireframe shows resulting pieces)" % split_pos
	)
	dlg.min_size = Vector2i(300, 100)
	plugin._add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(plugin) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.clip_preview:
				root.clip_preview.clear()
			HFUndoHelper.commit(
				plugin._get_undo_redo(),
				root,
				"Clip Brush",
				"clip_brush_by_id",
				[brush_id, 1, split_pos],
				false,
				Callable(plugin, "_record_history")
			)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(plugin):
				return
			if root and is_instance_valid(root) and root.clip_preview:
				root.clip_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


static func carve_selected(plugin: Object, root: Node) -> bool:
	var nodes = plugin._current_selection_nodes()
	if nodes.is_empty():
		return false
	var carve_ids: Array = []
	for node in nodes:
		if not root.is_brush_node(node):
			continue
		var info = root.get_brush_info_from_node(node)
		var brush_id = str(info.get("brush_id", ""))
		if brush_id != "":
			carve_ids.append(brush_id)
	if carve_ids.is_empty():
		return false
	if root.carve_preview:
		root.carve_preview.show_preview(carve_ids[0])
	var dlg = ConfirmationDialog.new()
	dlg.title = "Carve"
	dlg.dialog_text = (
		"Carve %d brush(es)?\n(Green wireframe shows resulting pieces)" % carve_ids.size()
	)
	dlg.min_size = Vector2i(300, 100)
	plugin._add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(plugin) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.carve_preview:
				root.carve_preview.clear()
			for brush_id in carve_ids:
				HFUndoHelper.commit(
					plugin._get_undo_redo(),
					root,
					"Carve",
					"carve_with_brush",
					[brush_id],
					false,
					Callable(plugin, "_record_history")
				)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(plugin):
				return
			if root and is_instance_valid(root) and root.carve_preview:
				root.carve_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true
