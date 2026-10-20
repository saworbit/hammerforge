@tool
extends Node
## What `plugin.gd` gets from `EditorPlugin`, for a headless test.
##
## `EditorPlugin` can only be built by the editor, so `plugin_stand_in.gd`
## compiles the real `plugin.gd` over this class instead. It keeps the names and
## shapes `plugin.gd` and its modules call, does nothing with the editor's
## docks and menus, and hands out a fake `EditorInterface` with a real selection
## and a scene root the test owns. An undo manager is there only when the test
## asks for one; without it every action commits directly.

## `EditorPlugin`'s own constants, the ones `plugin.gd` names unqualified.
const DOCK_SLOT_LEFT_UL := 0
const CONTAINER_SPATIAL_EDITOR_MENU := 1

const HFUserPrefsScript = preload("res://addons/hammerforge/hf_user_prefs.gd")

var stand_in_editor := FakeEditorInterface.new()
## What `get_undo_redo()` hands the plugin. Set it before the plugin enters the
## tree, as `PluginStandIn.build()` does, since `_enter_tree` reads it once.
var stand_in_undo: FakeUndoRedoManager = null


## The fake `EditorInterface`. `base_control` and `scene_root` belong to the test.
class FakeEditorInterface:
	extends RefCounted

	var selection := FakeSelection.new()
	var base_control: Control = null
	var scene_root: Node = null
	var main_screen: Control = null

	func get_selection() -> FakeSelection:
		return selection

	func get_edited_scene_root() -> Node:
		return scene_root if is_instance_valid(scene_root) else null

	func get_base_control() -> Control:
		return base_control

	func get_editor_main_screen() -> Control:
		return main_screen

	func get_editor_viewport_3d(_index: int = 0) -> SubViewport:
		return null

	func set_main_screen_editor(_name: String) -> void:
		pass

	func play_custom_scene(_path: String) -> void:
		pass

	func play_current_scene() -> void:
		pass

	func get_resource_filesystem() -> Object:
		return null

	func get_editor_settings() -> Object:
		return null


## `EditorSelection`, as far as HammerForge uses it. Like the editor's, it drops
## a node that leaves the tree and says so once the frame's deferred calls run.
class FakeSelection:
	extends RefCounted

	signal selection_changed

	var _nodes: Array = []

	func get_selected_nodes() -> Array:
		var live: Array = []
		for node in _nodes:
			if is_instance_valid(node):
				live.append(node)
		return live

	func add_node(node: Node) -> void:
		if node == null or _nodes.has(node):
			return
		_nodes.append(node)
		node.tree_exiting.connect(_on_node_exiting.bind(node), CONNECT_ONE_SHOT)
		selection_changed.emit()

	func remove_node(node: Node) -> void:
		if _nodes.has(node):
			_forget(node)
			selection_changed.emit()

	func clear() -> void:
		if _nodes.is_empty():
			return
		for node in _nodes.duplicate():
			# A node freed while selected out of the tree never said it was
			# leaving, and a typed call refuses what is left of it, which used to
			# stop the clear part way with the rest still selected (#1296).
			if is_instance_valid(node):
				_forget(node)
			else:
				_nodes.erase(node)
		selection_changed.emit()

	func _forget(node: Node) -> void:
		_nodes.erase(node)
		if is_instance_valid(node) and node.tree_exiting.is_connected(_on_node_exiting):
			node.tree_exiting.disconnect(_on_node_exiting)

	func _on_node_exiting(node: Node) -> void:
		_nodes.erase(node)
		selection_changed.emit.call_deferred()


## `EditorUndoRedoManager`, as far as HammerForge uses it: the manager's calls
## over real `UndoRedo` histories (`tests/mcp/mcp_undo_stand_in.gd`), and the
## manager's own `version_changed`, which the plugin and the dock listen to. Like
## the editor's, it has no `undo()` a script can call; a test presses the keys.
class FakeUndoRedoManager:
	extends "res://tests/mcp/mcp_undo_stand_in.gd"

	signal version_changed

	func _init() -> void:
		for history in [scene_history, global_history]:
			history.version_changed.connect(version_changed.emit)

	## The editor's Ctrl+Z and Ctrl+Shift+Z. Everything lands in the scene
	## history, so that is the newest step either key finds.
	func press_undo() -> bool:
		return scene_history.undo()

	func press_redo() -> bool:
		return scene_history.redo()

	## How many steps the scene history holds, undone ones included.
	func step_count() -> int:
		return scene_history.get_history_count()

	## A fresh scene's history, with no step to undo into the level before it.
	func clear() -> void:
		scene_history.clear_history()
		global_history.clear_history()


func get_editor_interface() -> FakeEditorInterface:
	return stand_in_editor


## In place of `HFUserPrefs.load_prefs()`: the defaults, never read from or
## written to the developer's own `user://` file.
# hf-allow-unused-declaration: plugin_stand_in.gd writes the call into plugin.gd
func _stand_in_user_prefs() -> HFUserPrefsScript:
	var prefs := HFUserPrefsScript.new()
	prefs.persistence_enabled = false
	return prefs


## In place of the brush gizmo plugin, which only the editor can build.
## `plugin.gd` already runs without one.
# hf-allow-unused-declaration: plugin_stand_in.gd writes the call into plugin.gd
func _stand_in_gizmo_plugin() -> EditorNode3DGizmoPlugin:
	return null


func get_undo_redo() -> Object:
	return stand_in_undo


func set_input_event_forwarding_always_enabled() -> void:
	pass


func set_force_draw_over_forwarding_enabled() -> void:
	pass


func update_overlays() -> int:
	return 0


func add_custom_type(_type: String, _base: String, _script: Script, _icon: Texture2D) -> void:
	pass


func remove_custom_type(_type: String) -> void:
	pass


func add_node_3d_gizmo_plugin(_gizmo_plugin: Object) -> void:
	pass


func remove_node_3d_gizmo_plugin(_gizmo_plugin: Object) -> void:
	pass


func add_control_to_dock(_slot: int, control: Control, _shortcut: Shortcut = null) -> void:
	_hold(control)


func remove_control_from_docks(control: Control) -> void:
	_release(control)


func add_control_to_container(_container: int, control: Control) -> void:
	_hold(control)


func remove_control_from_container(_container: int, control: Control) -> void:
	_release(control)


## Docked controls are kept under the base control, as the editor keeps them in
## its own tree. Taken off again they stay there: `_exit_tree` queues each one
## for freeing, and a control queued while out of the tree counts as an orphan
## until the frame ends. `PluginStandIn.teardown()` frees the base control.
func _hold(control: Control) -> void:
	if control == null or control.get_parent() != null:
		return
	if stand_in_editor.base_control:
		stand_in_editor.base_control.add_child(control)


func _release(_control: Control) -> void:
	pass
