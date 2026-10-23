@tool
class_name HFPluginPrefabCommands
extends RefCounted
## Prefab commands driven from the selection: quick save, cycle variant, push to
## source, and propagate to linked instances.
##
## The prefab data itself lives in HFPrefabSystem. This module is the editor side:
## what the current selection means, what the user is told, and how a change that
## rewrites the level reaches undo.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFPrefabSystem = preload("systems/hf_prefab_system.gd")
const HFUndoHelper = preload("undo_helper.gd")
const HFPluginSelectionCommands = preload("plugin_selection_commands.gd")
@warning_ignore_restore("shadowed_global_identifier")

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


static func quick_save(plugin: Object, root: Node, linked: bool) -> void:
	var split: Dictionary = HFPrefabSystem.split_selection(root, plugin.hf_selection)
	if split["brushes"].is_empty() and split["entities"].is_empty():
		return
	# Never over an existing file: there is no dialog here to ask in (#929).
	var suggested: String = root.prefab_system.unused_prefab_name(
		root.prefab_system.suggest_prefab_name(split["brushes"], split["entities"])
	)
	var path := save_selection(
		plugin.undo_redo_manager,
		root,
		plugin.hf_selection,
		suggested,
		linked,
		Callable(plugin, "_record_history")
	)
	if path == "":
		return
	_refresh_prefab_library(plugin)
	if plugin.dock:
		plugin.dock.show_toast("Saved prefab: %s%s" % [suggested, " (linked)" if linked else ""], 0)


## Save the brushes and entities among `nodes` as the prefab `prefab_name`, and
## with `linked` make them a linked copy of it. Quick Save and the library
## panel's Save and Save Linked all come here (#1451).
##
## Linking tags the nodes, so it changes the level and undo takes it back,
## whichever surface asked. The file is the library's and stays written, as an
## unlinked save's does (#1276). Returns the saved path, or "" when nothing in
## `nodes` was savable or the prefab system reported a failed write.
static func save_selection(
	undo_redo, root: Node, nodes: Array, prefab_name: String, linked: bool, history_cb: Callable
) -> String:
	var split: Dictionary = HFPrefabSystem.split_selection(root, nodes)
	if split["brushes"].is_empty() and split["entities"].is_empty():
		return ""
	var before: Dictionary = root.capture_state() if linked else {}
	var path: String = root.prefab_system.quick_save_prefab(
		split["brushes"], split["entities"], prefab_name, linked
	)
	if path != "" and linked:
		HFUndoHelper.commit_completed(undo_redo, root, "Save Linked Prefab", before, history_cb)
	return path


static func cycle_variant(plugin: Object, root: Node) -> void:
	var iid := selected_meta(plugin, HFPrefabSystem.INSTANCE_META)
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
	var iid := selected_meta(plugin, HFPrefabSystem.INSTANCE_META)
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
	var source := selected_meta(plugin, HFPrefabSystem.SOURCE_META)
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


## Make the selected copy ordinary brushes and entities, as one undo step
## (#1734). Later Pulls leave it alone.
static func unlink_copy(plugin: Object, root: Node) -> void:
	var iid := selected_meta(plugin, HFPrefabSystem.INSTANCE_META)
	if iid == "":
		return
	var before_state: Dictionary = root.state_system.capture_state(true)
	if not root.prefab_system.unlink_instance(iid):
		return
	if plugin.dock:
		plugin.dock.show_toast("Unlinked: the copy is ordinary brushes and entities now", 0)
	_commit_state_change(plugin, root, "Unlink Prefab Copy", before_state)
	plugin._update_hud_context()


## Select every copy in the level of the prefab the selection is a copy of, and
## only those (#1734).
static func select_linked_copies(plugin: Object, root: Node) -> void:
	var iid := selected_meta(plugin, HFPrefabSystem.INSTANCE_META)
	if iid == "":
		return
	var copies: Array = root.prefab_system.copies_like(iid)
	var nodes: Array = []
	for rec in copies:
		nodes.append_array(root.prefab_system.pieces_of(rec))
	HFPluginSelectionCommands.select_nodes(
		plugin,
		root,
		nodes,
		"Selected %d cop%s of this prefab" % [copies.size(), "y" if copies.size() == 1 else "ies"]
	)


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
## restore the whole captured state rather than a per-node diff. Through the
## helper, so the step is in History and ends a run of nudges (#1677).
static func _commit_state_change(
	plugin: Object, root: Node, action_name: String, before_state: Dictionary
) -> void:
	HFUndoHelper.commit_completed(
		plugin.undo_redo_manager, root, action_name, before_state, _history_of(plugin)
	)


## The plugin's History entry, or nothing for a caller without one.
static func _history_of(plugin: Object) -> Callable:
	return (
		Callable(plugin, "_record_history") if plugin.has_method("_record_history") else Callable()
	)


static func _refresh_prefab_library(plugin: Object) -> void:
	if plugin.dock and plugin.dock._prefab_library:
		plugin.dock._prefab_library.on_prefab_saved()
