@tool
class_name HFUndoNav
extends RefCounted
## Static helpers for navigating EditorUndoRedoManager history per-scene.
## Extracted from dock.gd. The dock holds the manager + level_root references
## and threads them through these helpers.


static func get_scene_history_id(undo_redo: EditorUndoRedoManager, level_root: Object) -> int:
	if undo_redo and level_root and is_instance_valid(level_root):
		return undo_redo.get_object_history_id(level_root)
	return EditorUndoRedoManager.GLOBAL_HISTORY


static func get_scene_undo_redo(undo_redo: EditorUndoRedoManager, level_root: Object) -> UndoRedo:
	if not undo_redo:
		return null
	return undo_redo.get_history_undo_redo(get_scene_history_id(undo_redo, level_root))


## Navigate the per-scene UndoRedo to a specific version. Walks undo() or
## redo() until the target version is reached or the history is exhausted.
static func navigate_to_version(ur: UndoRedo, target_version: int) -> void:
	if not ur:
		return
	var current := ur.get_version()
	if target_version < current:
		while ur.get_version() > target_version and ur.has_undo():
			ur.undo()
	elif target_version > current:
		while ur.get_version() < target_version and ur.has_redo():
			ur.redo()
