@tool
class_name HFPluginUndoEvents
extends RefCounted
## What the plugin does when the undo version moves: reconciling scene state that
## an undo or redo invalidated, and replaying the history to a chosen operation.

const HFInputStateType = preload("input_state.gd")
const HFBakePreview = preload("plugin_bake_preview.gd")


## Reconcile everything that an undo or redo can leave stale.
##
## Transient tool previews (drag, extrude) own temporary MeshInstance3D nodes that
## reference scene state which no longer exists, so they are torn down. VERTEX_EDIT
## is deliberately left alone: it is a persistent, user-toggled mode, and
## commit_action() fires version_changed after every merge, split, and move, so
## resetting it here would desynchronize the plugin's _vertex_mode flag from
## input_state.
static func on_version_changed(plugin: Object) -> void:
	var root: LevelRoot = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root or not is_instance_valid(root):
		return
	# Native Inspector/gizmo commits and their Undo/Redo are owned by Godot, so
	# reconcile their final brush signature after the editor finishes the action.
	plugin._queue_managed_brush_reconcile()
	if root.drag_system and root.drag_system.input_state:
		var ist: HFInputStateType = root.drag_system.input_state
		# Only reset transient preview modes that own temporary scene nodes.
		if HFInputStateType.is_transient_preview_mode(ist.mode):
			ist._force_reset()
	# Subtract preview may reference stale brush data — rebuild
	if root.subtract_preview and root.subtract_preview.is_enabled():
		root.subtract_preview.request_update()
	HFBakePreview.sync_after_undo(plugin, root)


## Walk the undo history to the version a replay timeline entry was recorded at.
static func on_replay_requested(plugin: Object, entry_index: int) -> void:
	if not plugin._operation_replay or not is_instance_valid(plugin._operation_replay):
		return
	var target_version: int = plugin._operation_replay.get_entry_version(entry_index)
	if target_version < 0:
		_warn(plugin, "Replay: no undo version recorded for this operation")
		return
	if not plugin.undo_redo_manager or not plugin.active_root:
		_warn(plugin, "Replay: no undo history available")
		return
	var history_id: int = plugin.undo_redo_manager.get_object_history_id(plugin.active_root)
	var ur: UndoRedo = plugin.undo_redo_manager.get_history_undo_redo(history_id)
	if not ur:
		_warn(plugin, "Replay: no undo history available")
		return
	var current_version: int = ur.get_version()
	if target_version == current_version:
		_inform(plugin, "Already at this operation")
		return
	# Undo or redo to reach the target version. Both loops also stop when the
	# history runs out, so a version that is no longer reachable cannot spin.
	var steps := 0
	if target_version < current_version:
		while ur.get_version() > target_version and ur.has_undo():
			ur.undo()
			steps += 1
		_inform(plugin, "Replay: undid %d step%s" % [steps, "" if steps == 1 else "s"])
	else:
		while ur.get_version() < target_version and ur.has_redo():
			ur.redo()
			steps += 1
		_inform(plugin, "Replay: redid %d step%s" % [steps, "" if steps == 1 else "s"])


static func _inform(plugin: Object, message: String) -> void:
	if plugin.dock:
		plugin.dock.show_toast(message, 0)


static func _warn(plugin: Object, message: String) -> void:
	if plugin.dock:
		plugin.dock.show_toast(message, 1)
