@tool
class_name HFPluginPrefabCommands
extends RefCounted
## Prefab commands driven from the selection: quick save, cycle variant, push to
## source, and propagate to linked instances.
##
## The prefab data itself lives in HFPrefabSystem. This module is the editor side:
## what the current selection means, what the user is told, and how a change that
## rewrites the level reaches undo.

## Meta key marking a node as an instance of a prefab.
const INSTANCE_META := "hf_prefab_instance"
## Meta key naming the prefab a linked instance came from.
const SOURCE_META := "hf_prefab_source"

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


static func quick_save(plugin: Object, root: Node, linked: bool) -> void:
	var brush_nodes: Array = []
	var entity_nodes: Array = []
	for node in plugin.hf_selection:
		if root.is_brush_node(node):
			brush_nodes.append(node)
		elif root.is_entity_node(node):
			entity_nodes.append(node)
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return
	var suggested: String = root.prefab_system.suggest_prefab_name(brush_nodes, entity_nodes)
	var path: String = root.prefab_system.quick_save_prefab(
		brush_nodes, entity_nodes, suggested, linked
	)
	if path == "":
		return
	_refresh_prefab_library(plugin)
	if plugin.dock:
		plugin.dock.show_toast("Saved prefab: %s%s" % [suggested, " (linked)" if linked else ""], 0)


static func cycle_variant(plugin: Object, root: Node) -> void:
	var iid := selected_meta(plugin, INSTANCE_META)
	if iid == "":
		return
	var before_state: Dictionary = root.state_system.capture_state(true)
	var new_variant: String = root.prefab_system.cycle_variant(iid)
	if new_variant == "":
		return
	if plugin.dock:
		plugin.dock.show_toast("Variant: %s" % new_variant, 0)
	_commit_state_change(plugin, root, "Cycle Prefab Variant", before_state)
	plugin._update_hud_context()


static func push_to_source(plugin: Object, root: Node) -> void:
	var iid := selected_meta(plugin, INSTANCE_META)
	if iid == "":
		return
	var ok: bool = root.prefab_system.push_instance_to_source(iid)
	if not ok:
		if plugin.dock:
			plugin.dock.show_toast("Failed to push to source", 1)
		return
	if plugin.dock:
		plugin.dock.show_toast("Pushed changes to prefab source", 0)
	_refresh_prefab_library(plugin)


static func propagate(plugin: Object, root: Node) -> void:
	var source := selected_meta(plugin, SOURCE_META)
	if source == "":
		return
	var before_state: Dictionary = root.state_system.capture_state(true)
	var count: int = root.prefab_system.propagate_from_source(source)
	if count <= 0:
		if plugin.dock:
			plugin.dock.show_toast("No linked instances to propagate", 1)
		return
	if plugin.dock:
		plugin.dock.show_toast(
			"Propagated to %d linked instance%s" % [count, "" if count == 1 else "s"], 0
		)
	_commit_state_change(plugin, root, "Propagate Prefab", before_state)


# ---------------------------------------------------------------------------
# Shared pieces
# ---------------------------------------------------------------------------


## Read a prefab meta value off the first selected node.
##
## Returns "" when there is nothing usable, warning the user only when they did
## select a node and it simply is not a prefab instance. An empty or stale
## selection is not worth a toast.
static func selected_meta(plugin: Object, meta_key: String) -> String:
	if plugin.hf_selection.is_empty():
		return ""
	var node = plugin.hf_selection[0]
	if not is_instance_valid(node) or not (node is Node):
		return ""
	var value: String = str(node.get_meta(meta_key, ""))
	if value == "":
		if plugin.dock:
			plugin.dock.show_toast("Not a prefab instance", 1)
	return value


## Prefab pushes rewrite brushes and entities across the level, so undo has to
## restore the whole captured state rather than a per-node diff.
static func _commit_state_change(
	plugin: Object, root: Node, action_name: String, before_state: Dictionary
) -> void:
	var undo_redo = plugin.undo_redo_manager
	if not undo_redo:
		return
	undo_redo.create_action(action_name)
	undo_redo.add_do_method(
		root.state_system, "restore_state", root.state_system.capture_state(true)
	)
	undo_redo.add_undo_method(root.state_system, "restore_state", before_state)
	undo_redo.commit_action(false)


static func _refresh_prefab_library(plugin: Object) -> void:
	if plugin.dock and plugin.dock._prefab_library:
		plugin.dock._prefab_library.on_prefab_saved()
