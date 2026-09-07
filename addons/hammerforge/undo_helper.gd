@tool
class_name HFUndoHelper
extends RefCounted

## Collation window in milliseconds.  Consecutive actions with the same
## collation_tag that arrive within this window are merged into a single
## undo entry, preventing undo-history flooding during drags / nudges.
const COLLATION_WINDOW_MS := 1000

## Tracks the last collation state so we can merge follow-up commits.
static var _last_collation_tag := ""
static var _last_collation_time := 0
static var _last_collation_state: Dictionary = {}
static var _last_collation_full := false


static func commit(
	undo_redo: EditorUndoRedoManager,
	root: Node,
	action_name: String,
	method_name: String,
	args: Array = [],
	full_state: bool = false,
	history_cb: Callable = Callable(),
	collation_tag: String = ""
) -> void:
	if not root or method_name == "" or not root.has_method(method_name):
		return

	# Evaluate collation state up front — needed for both undo_redo and direct
	# call paths so that history callback suppression works everywhere.
	var now := Time.get_ticks_msec()
	var can_collate := (
		collation_tag != ""
		and collation_tag == _last_collation_tag
		and full_state == _last_collation_full
		and (now - _last_collation_time) < COLLATION_WINDOW_MS
		and not _last_collation_state.is_empty()
	)

	if args.size() > 5:
		root.callv(method_name, args)
		var state: Dictionary = root.capture_full_state() if full_state else root.capture_state()
		_update_collation(collation_tag, can_collate, full_state, now, state)
		_fire_history_cb(history_cb, action_name, can_collate)
		return
	if not undo_redo:
		root.callv(method_name, args)
		# Still maintain collation tracking + history even without undo_redo,
		# so history UI stays consistent in edge cases.
		var state: Dictionary = root.capture_full_state() if full_state else root.capture_state()
		_update_collation(collation_tag, can_collate, full_state, now, state)
		_fire_history_cb(history_cb, action_name, can_collate)
		return

	var state: Dictionary
	if can_collate:
		# Reuse the *original* pre-action state from the first action in this
		# collation run so that undo jumps all the way back.
		state = _last_collation_state
	else:
		state = root.capture_full_state() if full_state else root.capture_state()

	# merge_mode: 0 = MERGE_DISABLE, 1 = MERGE_ENDS (merges consecutive same-name actions)
	var merge_mode := 1 if can_collate else 0
	undo_redo.create_action(action_name, merge_mode, null, false)
	match args.size():
		0:
			undo_redo.add_do_method(root, method_name)
		1:
			undo_redo.add_do_method(root, method_name, args[0])
		2:
			undo_redo.add_do_method(root, method_name, args[0], args[1])
		3:
			undo_redo.add_do_method(root, method_name, args[0], args[1], args[2])
		4:
			undo_redo.add_do_method(root, method_name, args[0], args[1], args[2], args[3])
		5:
			undo_redo.add_do_method(root, method_name, args[0], args[1], args[2], args[3], args[4])
	undo_redo.add_undo_method(root, "restore_full_state" if full_state else "restore_state", state)
	undo_redo.commit_action()

	_update_collation(collation_tag, can_collate, full_state, now, state)
	_fire_history_cb(history_cb, action_name, can_collate)


## Update collation tracking after a commit.
static func _update_collation(
	tag: String, was_collated: bool, full: bool, now_ms: int, state: Dictionary
) -> void:
	if tag != "":
		if not was_collated:
			_last_collation_state = state
		_last_collation_tag = tag
		_last_collation_time = now_ms
		_last_collation_full = full
	else:
		_reset_collation()


## Fire history callback only on the first action of a collation run.
static func _fire_history_cb(cb: Callable, action_name: String, was_collated: bool) -> void:
	if cb != null and cb.is_valid() and not was_collated:
		cb.call(action_name)


static func _reset_collation() -> void:
	_last_collation_tag = ""
	_last_collation_time = 0
	_last_collation_state = {}
	_last_collation_full = false
