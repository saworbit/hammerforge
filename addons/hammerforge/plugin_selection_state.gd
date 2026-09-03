@tool
class_name HFPluginSelectionState
extends RefCounted
## EditorSelection synchronization, managed-owner normalization, and action scope guards.

const DraftEntityType = preload("draft_entity.gd")
const HF_SHORTCUT_APPLY := -3
const SCOPE_EMPTY := 0
const SCOPE_NATIVE_ONLY := 1
const SCOPE_HAMMERFORGE_ONLY := 2
const SCOPE_MIXED := 3


static func on_editor_selection_changed(plugin: Object) -> void:
	if plugin == null or plugin._applying_hf_selection:
		return
	var selection = plugin.get_editor_interface().get_selection()
	if not selection:
		return
	var nodes = selection.get_selected_nodes()
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	var selection_before := normalize_editor_selection(plugin, plugin.hf_selection, root)
	if plugin.dock and plugin.dock.is_face_select_mode_enabled() and not nodes.is_empty():
		plugin._prepare_tool_transition(root, false)
		if plugin.dock.face_select_mode:
			plugin.dock.face_select_mode.set_pressed_no_signal(false)
		plugin._face_mode_saved_object_selection.clear()
		if root and root.has_method("clear_face_selection"):
			root.clear_face_selection()
		plugin.dock.show_toast("Face Select closed for object editing", 0)
	var normalized_nodes := normalize_editor_selection(plugin, nodes, root)
	var remove_group: bool = plugin.group_removal_requested(
		plugin._native_selection_active,
		plugin._native_selection_additive,
		plugin._native_selection_toggle,
		Input.is_key_pressed(KEY_SHIFT),
		Input.is_key_pressed(KEY_CTRL),
		Input.is_key_pressed(KEY_META)
	)
	var expanded_nodes := expand_native_group_selection(
		root, selection_before, normalized_nodes, remove_group
	)
	if not same_node_selection(nodes, expanded_nodes):
		plugin.hf_selection = expanded_nodes
		apply_hf_selection(plugin, selection)
		return
	plugin.hf_selection = expanded_nodes
	if root:
		root.clear_hover()
		if root.has_method("set_io_visualizer_selection"):
			root.call("set_io_visualizer_selection", plugin.hf_selection)
	if plugin.dock:
		plugin.dock.set_selection_count(plugin.hf_selection.size())
		plugin.dock.set_selection_nodes(plugin.hf_selection)
	if plugin._vertex_mode and root and root.vertex_system:
		var brushes: Array = []
		for node in plugin.hf_selection:
			if node is DraftBrush:
				brushes.append(node)
		root.vertex_system.set_selection(brushes)
	plugin._update_hud_context()


static func finalize_native_selection(
	plugin: Object, selection_before: Array, additive: bool, toggle: bool
) -> void:
	if plugin == null or not plugin.is_inside_tree():
		return
	var selection = plugin.get_editor_interface().get_selection()
	if not selection:
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	var before := normalize_editor_selection(plugin, selection_before, root)
	var editor_nodes: Array = selection.get_selected_nodes()
	var current := normalize_editor_selection(plugin, editor_nodes, root)
	var expanded := expand_native_group_selection(root, before, current, toggle or additive)
	if same_node_selection(editor_nodes, expanded):
		plugin.hf_selection = expanded
		plugin._on_editor_selection_changed()
		return
	plugin.hf_selection = expanded
	apply_hf_selection(plugin, selection)


static func normalize_editor_selection(plugin: Object, nodes: Array, root: Node) -> Array:
	var normalized: Array = []
	for candidate in nodes:
		if not is_instance_valid(candidate) or not candidate is Node:
			continue
		var node := normalize_managed_selection_owner(candidate as Node, root)
		if node and not normalized.has(node):
			normalized.append(node)
	return normalized


static func normalize_managed_selection_owner(node: Node, root: Node) -> Node:
	var current := node
	var entities_root: Node = root.get("entities_node") as Node if root else null
	while current:
		if current is DraftBrush or current is DraftEntityType:
			return current
		if (
			entities_root
			and current.get_parent() == entities_root
			and root.has_method("is_entity_node")
			and root.is_entity_node(current)
		):
			return current
		if current == root:
			break
		current = current.get_parent()
	return node


static func expand_native_group_selection(
	root: Node, selection_before: Array, current_selection: Array, toggle: bool
) -> Array:
	if not root or not root.visgroup_system:
		return current_selection.duplicate()
	var groups := {}
	for node in selection_before + current_selection:
		if not is_instance_valid(node):
			continue
		var group_id: String = str(root.visgroup_system.get_group_of(node))
		if group_id != "" and not groups.has(group_id):
			groups[group_id] = root.visgroup_system.get_group_members(group_id)
	return expand_native_group_members(selection_before, current_selection, toggle, groups)


static func expand_native_group_members(
	selection_before: Array, current_selection: Array, toggle: bool, groups: Dictionary
) -> Array:
	var result := current_selection.duplicate()
	for group_id in groups:
		var members: Array = groups.get(group_id, [])
		if members.is_empty():
			continue
		var before_members: Array = []
		var current_members: Array = []
		for member in members:
			if selection_before.has(member):
				before_members.append(member)
			if current_selection.has(member):
				current_members.append(member)
		if same_node_selection(before_members, current_members):
			continue
		var removed_member := false
		for member in before_members:
			if not current_members.has(member):
				removed_member = true
				break
		if toggle and removed_member:
			for member in members:
				result.erase(member)
		elif not current_members.is_empty():
			for member in members:
				if is_instance_valid(member) and not result.has(member):
					result.append(member)
	return result


static func same_node_selection(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for node in first:
		if not second.has(node):
			return false
	return true


static func apply_selection_list(
	plugin: Object, nodes: Array, additive: bool, toggle: bool = false
) -> void:
	if plugin == null:
		return
	var selection = plugin.get_editor_interface().get_selection()
	if not selection:
		return
	if not additive:
		plugin.hf_selection.clear()
	else:
		sync_hf_selection_if_empty(plugin)
	for node in nodes:
		if not node:
			continue
		if additive and toggle and plugin.hf_selection.has(node):
			plugin.hf_selection.erase(node)
		elif not plugin.hf_selection.has(node):
			plugin.hf_selection.append(node)
	apply_hf_selection(plugin, selection)


static func apply_hf_selection(plugin: Object, selection: EditorSelection) -> void:
	if plugin == null or selection == null:
		return
	plugin._applying_hf_selection = true
	selection.clear()
	for node in plugin.hf_selection:
		if is_instance_valid(node):
			selection.add_node(node)
	plugin._applying_hf_selection = false
	plugin._on_editor_selection_changed()


static func sync_hf_selection_if_empty(plugin: Object) -> void:
	if plugin == null or not plugin.hf_selection.is_empty():
		return
	var selection = plugin.get_editor_interface().get_selection()
	if selection:
		plugin.hf_selection = selection.get_selected_nodes()


static func selection_has_brush(nodes: Array, root: Node) -> bool:
	if not root:
		return false
	for node in nodes:
		if root.is_brush_node(node):
			return true
	return false


static func selection_has_entity(nodes: Array, root: Node) -> bool:
	if not root:
		return false
	for node in nodes:
		if root.is_entity_node(node):
			return true
	return false


static func classify_selection_scope(nodes: Array, root: Node) -> int:
	if nodes.is_empty() or not root:
		return SCOPE_EMPTY
	var has_hammerforge := false
	var has_native := false
	for node in nodes:
		if not is_instance_valid(node) or not node is Node:
			has_native = true
		elif root.is_brush_node(node) or root.is_entity_node(node):
			has_hammerforge = true
		else:
			has_native = true
	if has_hammerforge and has_native:
		return SCOPE_MIXED
	return SCOPE_HAMMERFORGE_ONLY if has_hammerforge else SCOPE_NATIVE_ONLY


static func guard_hammerforge_shortcut(
	plugin: Object, root: Node, brushes_only: bool, minimum_count: int, action_label: String
) -> int:
	var nodes := current_selection_nodes(plugin)
	var scope := classify_selection_scope(nodes, root)
	if scope in [SCOPE_EMPTY, SCOPE_NATIVE_ONLY]:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if scope == SCOPE_MIXED:
		if plugin.dock:
			plugin.dock.show_toast("Edit HammerForge and Godot nodes separately", 1)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if brushes_only:
		for node in nodes:
			if not root.is_brush_node(node):
				if plugin.dock:
					plugin.dock.show_toast("%s works on brushes only" % action_label, 1)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	if nodes.size() < minimum_count:
		if plugin.dock:
			plugin.dock.show_toast(
				"%s needs at least %d selected" % [action_label, minimum_count], 1
			)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return HF_SHORTCUT_APPLY


static func managed_surface_action_requirement(action: String) -> Dictionary:
	if action in ["delete", "duplicate"]:
		return {"brushes_only": false, "minimum": 1, "label": action.capitalize()}
	if action == "group":
		return {"brushes_only": false, "minimum": 2, "label": "Group"}
	if action == "ungroup":
		return {"brushes_only": false, "minimum": 1, "label": "Ungroup"}
	if action == "merge":
		return {"brushes_only": true, "minimum": 2, "label": "Merge"}
	if (
		action
		in [
			"hollow",
			"clip",
			"carve",
			"move_to_floor",
			"move_to_ceiling",
			"vertex_edit",
			"vertex_submode",
			"edge_submode",
			"vertex_merge",
			"vertex_split",
			"vertex_split_edge",
			"vertex_clip_convex",
		]
	):
		return {
			"brushes_only": true,
			"minimum": 1,
			"label": action.replace("_", " ").capitalize(),
		}
	if (
		action
		in ["apply_to_brush", "apply_context_material", "apply_last_texture", "select_similar"]
	):
		return {
			"brushes_only": true,
			"minimum": 1,
			"label": action.replace("_", " ").capitalize(),
			"allow_faces": true,
		}
	if (
		action
		in [
			"justify_fit",
			"justify_center",
			"justify_left",
			"justify_right",
			"justify_top",
			"justify_bottom",
		]
	):
		return {
			"brushes_only": true,
			"minimum": 1,
			"label": "UV Justify",
			"allow_faces": true,
		}
	if (
		action
		in [
			"quick_save_prefab",
			"quick_save_linked_prefab",
			"cycle_variant",
			"push_to_source",
			"propagate_prefab",
			"entity_io",
			"entity_props",
			"highlight_connected",
		]
	):
		return {
			"brushes_only": false,
			"minimum": 1,
			"label": action.replace("_", " ").capitalize(),
		}
	if action == "selection_filter":
		return {"mixed_only": true, "label": "Selection Filters"}
	return {}


static func managed_action_surface_allowed(plugin: Object, root: Node, action: String) -> bool:
	var requirement := managed_surface_action_requirement(action)
	if requirement.is_empty():
		return true
	var nodes := current_selection_nodes(plugin)
	var scope := classify_selection_scope(nodes, root)
	if scope == SCOPE_MIXED:
		if plugin.dock:
			plugin.dock.show_toast("Edit HammerForge and Godot nodes separately", 1)
		return false
	if bool(requirement.get("mixed_only", false)):
		return true
	if bool(requirement.get("allow_faces", false)) and root:
		var faces = root.get("face_selection")
		if faces is Dictionary and not faces.is_empty():
			return true
	var guard := guard_hammerforge_shortcut(
		plugin,
		root,
		bool(requirement.get("brushes_only", false)),
		int(requirement.get("minimum", 1)),
		str(requirement.get("label", "Action"))
	)
	if guard == HF_SHORTCUT_APPLY:
		return true
	if guard == EditorPlugin.AFTER_GUI_INPUT_PASS and plugin.dock:
		plugin.dock.show_toast("Select a HammerForge object first", 1)
	return false


static func hammerforge_selection_nodes(
	plugin: Object, root: Node, brushes_only: bool = false
) -> Array:
	var eligible: Array = []
	if not root:
		return eligible
	for node in current_selection_nodes(plugin):
		if not is_instance_valid(node) or not node is Node:
			continue
		if root.is_brush_node(node) or (not brushes_only and root.is_entity_node(node)):
			eligible.append(node)
	return eligible


static func managed_entity_owner(root: Node, node: Node) -> Node:
	if not root or not node or not root.is_entity_node(node):
		return null
	var owner := normalize_managed_selection_owner(node, root)
	return owner if owner is DraftEntityType else null


static func current_selection_nodes(plugin: Object) -> Array:
	if plugin == null:
		return []
	if not plugin.hf_selection.is_empty():
		return plugin.hf_selection.duplicate()
	var selection = plugin.get_editor_interface().get_selection()
	if selection:
		return selection.get_selected_nodes()
	return []
