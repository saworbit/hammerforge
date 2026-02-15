@tool
class_name HFUndoHelper
extends RefCounted


static func commit(
	undo_redo: EditorUndoRedoManager,
	root: Node,
	action_name: String,
	method_name: String,
	args: Array = [],
	full_state: bool = false,
	history_cb: Callable = Callable()
) -> void:
	if not root or method_name == "" or not root.has_method(method_name):
		return
	if args.size() > 3:
		# Avoid partial undo if too many args were supplied.
		root.callv(method_name, args)
		return
	if not undo_redo:
		root.callv(method_name, args)
		return
	var state = root.capture_full_state() if full_state else root.capture_state()
	undo_redo.create_action(action_name)
	match args.size():
		0:
			undo_redo.add_do_method(root, method_name)
		1:
			undo_redo.add_do_method(root, method_name, args[0])
		2:
			undo_redo.add_do_method(root, method_name, args[0], args[1])
		3:
			undo_redo.add_do_method(root, method_name, args[0], args[1], args[2])
	undo_redo.add_undo_method(root, "restore_full_state" if full_state else "restore_state", state)
	undo_redo.commit_action()
	if history_cb != null and history_cb.is_valid():
		history_cb.call(action_name)
