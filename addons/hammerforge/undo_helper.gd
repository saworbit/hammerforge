@tool
class_name HFUndoHelper
extends RefCounted

## Collation window in milliseconds.  Consecutive actions with the same
## collation_tag that arrive within this window are merged into a single
## undo entry, preventing undo-history flooding during drags / nudges.
const COLLATION_WINDOW_MS := 1000

## How many arguments the hand written add_do_method unroll covers.
const MAX_UNROLLED_ARGS := 5

## Tracks the last collation state so we can merge follow-up commits.
static var _last_collation_tag := ""
static var _last_collation_time := 0
static var _last_collation_state: Dictionary = {}
static var _last_collation_full := false


## Register one undoable action, optionally merging it with the last one.
##
## `absolute_redo` turns the do operation into a snapshot of the result: the
## method runs first, and what gets registered is the state it produced rather
## than the call that produced it. Two kinds of command need that.
##
## Commands that step rather than set: rotate by fifteen degrees, nudge by one
## grid square. Godot's MERGE_ENDS keeps the first action's undo and the last
## action's do, which is only right when that last do names the final result. A
## third quick rotate would otherwise redo fifteen degrees where undo had removed
## forty-five.
##
## Commands whose arguments are live nodes. `restore_state()` clears the brushes
## and entities and rebuilds them from their captured info, so a node an undo
## passed over is freed and the reference held for the redo is dangling.
static func commit(
	undo_redo: EditorUndoRedoManager,
	root: Node,
	action_name: String,
	method_name: String,
	args: Array = [],
	full_state: bool = false,
	history_cb: Callable = Callable(),
	collation_tag: String = "",
	absolute_redo: bool = false
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
	register_action(
		undo_redo,
		root,
		action_name,
		1 if can_collate else 0,
		method_name,
		args,
		state,
		full_state,
		absolute_redo
	)

	_update_collation(collation_tag, can_collate, full_state, now, state)
	_fire_history_cb(history_cb, action_name, can_collate)


## The half of `commit()` that talks to the undo manager.
##
## Its own function so it can be driven against a stand-in: an
## `EditorUndoRedoManager` cannot be constructed outside the editor, and this is
## the part where getting the do operation wrong is invisible until a redo.
static func register_action(
	undo_redo,
	root: Node,
	action_name: String,
	merge_mode: int,
	method_name: String,
	args: Array,
	state: Dictionary,
	full_state: bool = false,
	absolute_redo: bool = false
) -> void:
	var restore_name := "restore_full_state" if full_state else "restore_state"

	# add_do_method takes an object, a method name and varargs. GDScript cannot
	# spread an array into varargs, so the call below is unrolled by hand and
	# stops at five. Past that, register the result instead of the call: the do
	# operation becomes the same kind of state restore the undo already is.
	if absolute_redo or args.size() > MAX_UNROLLED_ARGS:
		# Run it here, then register the result rather than the step, and commit
		# without executing so the work is not done twice.
		root.callv(method_name, args)
		var after: Dictionary = root.capture_full_state() if full_state else root.capture_state()
		undo_redo.create_action(action_name, merge_mode, null, false)
		undo_redo.add_do_method(root, restore_name, after)
		undo_redo.add_undo_method(root, restore_name, state)
		undo_redo.commit_action(false)
		return

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
	undo_redo.add_undo_method(root, restore_name, state)
	undo_redo.commit_action()


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
