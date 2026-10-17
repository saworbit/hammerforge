extends RefCounted

## An `EditorUndoRedoManager` cannot be constructed outside the editor, so the MCP
## tests and the bridge smoke script use this instead. It has the manager's call
## shape and real `UndoRedo` histories behind it, so an undo or a redo in a test
## actually runs, names are real, and `version_changed` fires the way the
## editor's does.
##
## Every action lands in `scene_history`. The editor picks the history from the
## first do target, which for everything HammerForge commits is a node in the
## edited scene. `global_history` is there so a test can commit somewhere else
## and see the dispatcher count it.

const SCENE_HISTORY := 1
const GLOBAL_HISTORY := 0

var scene_history := UndoRedo.new()
var global_history := UndoRedo.new()


func create_action(
	action_name: String,
	merge_mode: int = 0,
	_custom_context: Object = null,
	backward_undo_ops: bool = false,
	_mark_unsaved: bool = true
) -> void:
	scene_history.create_action(action_name, merge_mode, backward_undo_ops)


func add_do_method(target: Object, method: StringName, ...args: Array) -> void:
	scene_history.add_do_method(Callable(target, method).bindv(args))


func add_undo_method(target: Object, method: StringName, ...args: Array) -> void:
	scene_history.add_undo_method(Callable(target, method).bindv(args))


func add_do_property(target: Object, property: StringName, value: Variant) -> void:
	scene_history.add_do_property(target, property, value)


func add_undo_property(target: Object, property: StringName, value: Variant) -> void:
	scene_history.add_undo_property(target, property, value)


func add_do_reference(target: Object) -> void:
	scene_history.add_do_reference(target)


func add_undo_reference(target: Object) -> void:
	scene_history.add_undo_reference(target)


func commit_action(execute: bool = true) -> void:
	scene_history.commit_action(execute)


func is_committing_action() -> bool:
	return scene_history.is_committing_action()


func get_object_history_id(_object: Object) -> int:
	return SCENE_HISTORY


func get_history_undo_redo(id: int) -> UndoRedo:
	return global_history if id == GLOBAL_HISTORY else scene_history


## `UndoRedo` is an Object, not a RefCounted. Call this when done with the
## stand-in or the histories leak.
func free_histories() -> void:
	for history in [scene_history, global_history]:
		if is_instance_valid(history):
			history.free()
