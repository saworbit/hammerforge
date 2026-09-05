@tool
class_name HFPluginSelectionCommands
extends RefCounted
## User-invoked bulk selection commands: Select All, Deselect All, Select Similar,
## the selection filter popup, and Apply Last Texture.
##
## These are the commands a shortcut, the hotkey palette, or the context toolbar
## fires. Pointer arbitration lives in HFPluginSelectionInput and EditorSelection
## synchronization lives in HFPluginSelectionState.

## Faces whose world normals are within ~15 degrees count as the same direction.
const SIMILAR_NORMAL_DOT := 0.966
## Fractional size difference two brushes may have and still be "similar".
const SIMILAR_SIZE_TOLERANCE := 0.2

# ---------------------------------------------------------------------------
# Face selection
# ---------------------------------------------------------------------------


static func face_key_for(brush: DraftBrush) -> String:
	if brush.brush_id != "":
		return brush.brush_id
	return str(brush.get_instance_id())


static func apply_face_selection(plugin: Object, root: Node, face_sel: Dictionary) -> void:
	root.face_selection = face_sel
	if root.brush_system:
		root.brush_system._apply_face_selection()
	root.face_selection_changed.emit()
	plugin._update_hud_context()


# ---------------------------------------------------------------------------
# Apply Last Texture
# ---------------------------------------------------------------------------


static func apply_last_texture(plugin: Object, root: Node) -> void:
	if plugin._last_picked_material_index < 0:
		if plugin.dock:
			plugin.dock.show_toast("No texture picked yet — use T to pick first", 1)
		return
	if not plugin.dock:
		return
	plugin.dock._selected_material_index = plugin._last_picked_material_index
	var face_count = plugin.dock._count_selected_faces()
	if face_count > 0:
		plugin.dock._on_face_assign_material()
		plugin.dock.show_toast(
			"Applied last texture to %d face%s" % [face_count, "" if face_count == 1 else "s"], 0
		)
		return
	var applied_count := 0
	var mat = (
		root.material_manager.get_material(plugin._last_picked_material_index)
		if root.material_manager
		else null
	)
	if mat:
		for node in plugin.hf_selection:
			if node is DraftBrush:
				plugin._paint_brush_with_undo(root, node, mat)
				applied_count += 1
	if applied_count > 0:
		plugin.dock.show_toast(
			(
				"Applied last texture to %d brush%s"
				% [applied_count, "" if applied_count == 1 else "es"]
			),
			0
		)
	else:
		plugin.dock.show_toast("No brushes or faces selected", 1)


# ---------------------------------------------------------------------------
# Select All / Deselect All
# ---------------------------------------------------------------------------


static func select_all(plugin: Object, root: Node) -> void:
	if not root:
		return
	var selection = plugin.get_editor_interface().get_selection()
	if not selection:
		return
	# Clear face selection first so context toolbar switches to object context
	if root.has_method("clear_face_selection"):
		root.clear_face_selection()
	var all_nodes: Array = root._iter_pick_nodes()
	plugin.hf_selection.clear()
	for node in all_nodes:
		if is_instance_valid(node):
			plugin.hf_selection.append(node)
	plugin._apply_hf_selection(selection)
	plugin._update_hud_context()
	if plugin.dock:
		plugin.dock.set_selection_count(plugin.hf_selection.size())
		plugin.dock.set_selection_nodes(plugin.hf_selection)
		plugin.dock.show_toast("Selected %d objects" % plugin.hf_selection.size(), 0)


static func deselect_all(plugin: Object, root: Node) -> void:
	if not root:
		return
	var selection = plugin.get_editor_interface().get_selection()
	if not selection:
		return
	if plugin.dock:
		plugin.dock.emit_signal("selection_clear_requested")
	plugin.hf_selection.clear()
	selection.clear()
	# Also clear face selection
	if root.has_method("clear_face_selection"):
		root.clear_face_selection()
	elif root.get("face_selection") is Dictionary:
		root.face_selection.clear()
	plugin._update_hud_context()
	if plugin.dock:
		plugin.dock.set_selection_count(0)
		plugin.dock.set_selection_nodes([])


# ---------------------------------------------------------------------------
# Select Similar
# ---------------------------------------------------------------------------


static func select_similar(plugin: Object, root: Node) -> void:
	if not root:
		return
	# If faces are selected, find similar faces across all brushes
	var face_count := 0
	for key in root.face_selection.keys():
		face_count += root.face_selection.get(key, []).size()
	if face_count > 0:
		select_similar_faces(plugin, root)
		return
	# Otherwise match similar brushes by size
	if not plugin.hf_selection.is_empty():
		select_similar_brushes(plugin, root)
		return
	if plugin.dock:
		plugin.dock.show_toast("Select a face or brush first", 1)


static func select_similar_faces(plugin: Object, root: Node) -> void:
	# Gather reference face properties with world-space normals
	var ref_faces: Array = []
	var ref_world_normals: Array = []
	for key in root.face_selection.keys():
		var brush = root._find_brush_by_key(str(key))
		if not brush:
			continue
		var basis: Basis = brush.global_transform.basis if brush is Node3D else Basis.IDENTITY
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		for fi in root.face_selection.get(key, []):
			if int(fi) >= 0 and int(fi) < faces.size():
				ref_faces.append(faces[int(fi)])
				ref_world_normals.append((basis * faces[int(fi)].normal).normalized())
	if ref_faces.is_empty():
		return
	# Find all matching faces (same material AND similar world-space normal)
	var face_sel: Dictionary = {}
	var nodes: Array = root._iter_pick_nodes() if root.has_method("_iter_pick_nodes") else []
	var total := 0
	for node in nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		var basis: Basis = brush.global_transform.basis
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		var key: String = face_key_for(brush)
		var indices: Array = []
		for i in range(faces.size()):
			var face = faces[i]
			if not face:
				continue
			var world_normal: Vector3 = (basis * face.normal).normalized()
			for ri in range(ref_faces.size()):
				var ref = ref_faces[ri]
				var ref_wn: Vector3 = ref_world_normals[ri]
				if (
					face.material_idx == ref.material_idx
					and world_normal.dot(ref_wn) > SIMILAR_NORMAL_DOT
				):
					indices.append(i)
					total += 1
					break
		if not indices.is_empty():
			face_sel[key] = indices
	apply_face_selection(plugin, root, face_sel)
	if plugin.dock:
		plugin.dock.show_toast("Selected %d similar face%s" % [total, "" if total == 1 else "s"], 0)


static func select_similar_brushes(plugin: Object, root: Node) -> void:
	var ref_sizes: Array = []
	for node in plugin.hf_selection:
		if node is DraftBrush and is_instance_valid(node):
			ref_sizes.append((node as DraftBrush).size)
	if ref_sizes.is_empty():
		return
	var picked: Array = []
	var nodes: Array = root._iter_pick_nodes() if root.has_method("_iter_pick_nodes") else []
	for node in nodes:
		if not (node is DraftBrush):
			continue
		var sz: Vector3 = (node as DraftBrush).size
		for ref_sz in ref_sizes:
			if size_similar(sz, ref_sz, SIMILAR_SIZE_TOLERANCE):
				picked.append(node)
				break
	plugin._apply_selection_list(picked, false)
	if plugin.dock:
		plugin.dock.show_toast(
			"Selected %d similar brush%s" % [picked.size(), "" if picked.size() == 1 else "es"], 0
		)


static func size_similar(a: Vector3, b: Vector3, tolerance: float) -> bool:
	var sa := sorted_vec(a)
	var sb := sorted_vec(b)
	for i in range(3):
		var ref_val: float = maxf(sb[i], 0.01)
		if absf(sa[i] - sb[i]) / ref_val > tolerance:
			return false
	return true


static func sorted_vec(v: Vector3) -> Array:
	var arr := [v.x, v.y, v.z]
	arr.sort()
	return arr


# ---------------------------------------------------------------------------
# Selection Filter popup
# ---------------------------------------------------------------------------


static func show_selection_filter(plugin: Object) -> void:
	if not plugin._selection_filter:
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	plugin._selection_filter.show_for(root, plugin.hf_selection)
	# Position near the mouse
	var popup_pos := Vector2i(int(plugin.last_3d_mouse_pos.x), int(plugin.last_3d_mouse_pos.y))
	plugin._selection_filter.popup(Rect2i(popup_pos, Vector2i.ZERO))


static func on_filter_applied(plugin: Object, nodes: Array, faces: Dictionary) -> void:
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root:
		return
	# Apply face selection if provided
	if not faces.is_empty():
		apply_face_selection(plugin, root, faces)
		var total := 0
		for key in faces.keys():
			total += faces[key].size()
		if plugin.dock:
			plugin.dock.show_toast("Selected %d face%s" % [total, "" if total == 1 else "s"], 0)
	elif not nodes.is_empty():
		# Node-only filter — clear any stale face selection first
		apply_face_selection(plugin, root, {})
		plugin._apply_selection_list(nodes, false)
		if plugin.dock:
			plugin.dock.show_toast(
				"Selected %d node%s" % [nodes.size(), "" if nodes.size() == 1 else "s"], 0
			)
