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
static var _last_collation_scoped := false


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
##
## `scope_brush_ids` names the brushes the command changes, and nothing else. A
## command that can say that gets an undo step the size of the change instead of
## the size of the level (#737). It is a claim about the command, not about the
## arguments: pass it only when the method changes those brushes and no entity,
## no registry, no palette and no other brush. When the ids cannot be a scope --
## one does not resolve, or one is a pending cut -- the whole snapshot is taken
## as before, so a wrong-looking id costs speed and not correctness.
static func commit(
	undo_redo: EditorUndoRedoManager,
	root: Node,
	action_name: String,
	method_name: String,
	args: Array = [],
	full_state: bool = false,
	history_cb: Callable = Callable(),
	collation_tag: String = "",
	absolute_redo: bool = false,
	scope_brush_ids: Array = []
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
		_update_collation(collation_tag, can_collate, full_state, false, now, state)
		_fire_history_cb(history_cb, action_name, can_collate)
		return

	var state: Dictionary = {}
	var scoped := false
	if can_collate:
		# Reuse the *original* pre-action state from the first action in this
		# collation run so that undo jumps all the way back. A run shares one
		# collation tag and the tag names the brushes, so every commit in it
		# scopes the same way the first one did.
		state = _last_collation_state
		scoped = _last_collation_scoped
	else:
		if not full_state and not scope_brush_ids.is_empty():
			if root.has_method("capture_brush_scope"):
				state = root.capture_brush_scope(scope_brush_ids)
				scoped = not state.is_empty()
		if not scoped:
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
		absolute_redo,
		scope_brush_ids if scoped else []
	)

	_update_collation(collation_tag, can_collate, full_state, scoped, now, state)
	_fire_history_cb(history_cb, action_name, can_collate)


## Register an undo step for work the caller has already done.
##
## `commit()` and `register_action()` call the method themselves and discard what
## it returns, so a caller that needs the return value cannot use them.
## `validate_level(true)` reports both how many issues it repaired and which ones
## are left, and Validate + Fix was throwing that away and re-deriving the count
## from two more full validation passes. Hand this the state from before the work
## instead, and read the result at the call site.
##
## `scope_brush_ids` is the same claim `commit()` takes, and `before` has to be
## the matching `capture_brush_scope()` rather than a whole state: the caller took
## it before the work, so only the caller can decide which one to take. Every
## displacement edit comes through here and changes one face of one brush (#761).
static func commit_completed(
	undo_redo,
	root: Node,
	action_name: String,
	before: Dictionary,
	history_cb: Callable = Callable(),
	scope_brush_ids: Array = []
) -> void:
	if undo_redo:
		var restore_name := (
			"restore_brush_scope" if not scope_brush_ids.is_empty() else "restore_state"
		)
		var result: Dictionary = _after_state(root, action_name, scope_brush_ids, false)
		undo_redo.create_action(action_name, 0, null, false)
		undo_redo.add_do_method(root, result["restore"], result["state"])
		undo_redo.add_undo_method(root, restore_name, before)
		undo_redo.commit_action(false)
	_reset_collation()
	_fire_history_cb(history_cb, action_name, false)


## The half of `commit()` that talks to the undo manager.
##
## Its own function so it can be driven against a stand-in: an
## `EditorUndoRedoManager` cannot be constructed outside the editor, and this is
## the part where getting the do operation wrong is invisible until a redo.
##
## `scope_brush_ids` non-empty means `state` is a brush scope rather than a whole
## level, so both ends of the action restore through `restore_brush_scope()`.
## `commit()` passes it only once it has a scope in hand, so this does not have
## to decide whether the ids were usable.
static func register_action(
	undo_redo,
	root: Node,
	action_name: String,
	merge_mode: int,
	method_name: String,
	args: Array,
	state: Dictionary,
	full_state: bool = false,
	absolute_redo: bool = false,
	scope_brush_ids: Array = []
) -> void:
	var scoped := not scope_brush_ids.is_empty()
	var restore_name := "restore_full_state" if full_state else "restore_state"
	if scoped:
		restore_name = "restore_brush_scope"

	# add_do_method takes an object, a method name and varargs. GDScript cannot
	# spread an array into varargs, so the call below is unrolled by hand and
	# stops at five. Past that, register the result instead of the call: the do
	# operation becomes the same kind of state restore the undo already is.
	if absolute_redo or args.size() > MAX_UNROLLED_ARGS:
		# Run it here, then register the result rather than the step, and commit
		# without executing so the work is not done twice.
		root.callv(method_name, args)
		var result: Dictionary = _after_state(root, action_name, scope_brush_ids, full_state)
		undo_redo.create_action(action_name, merge_mode, null, false)
		undo_redo.add_do_method(root, result["restore"], result["state"])
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


## The state a do operation restores, once the work has already been done.
##
## Named ids mean the caller claimed a scope, so the result is the scope those
## ids record now. An empty one back means the command changed which brushes
## exist, which is the one thing a scope promises it does not do. Undo still puts
## the recorded brushes back, but nothing can put back what the command added or
## removed, so the do falls back to the whole level and says so rather than
## letting a silent half-redo ship.
##
## Both places that register a completed action read this, so the fallback cannot
## drift between them.
static func _after_state(
	root: Node, action_name: String, scope_brush_ids: Array, full_state: bool
) -> Dictionary:
	var scoped := not scope_brush_ids.is_empty()
	if scoped:
		var scope: Dictionary = root.capture_brush_scope(scope_brush_ids)
		if not scope.is_empty():
			return {"restore": "restore_brush_scope", "state": scope}
		HFLog.warn(
			"HFUndoHelper: '%s' changed the brush set it scoped, so redo is partial" % action_name
		)
	return {
		"restore": "restore_full_state" if full_state else "restore_state",
		"state": root.capture_full_state() if full_state else root.capture_state(),
	}


## Update collation tracking after a commit.
static func _update_collation(
	tag: String, was_collated: bool, full: bool, scoped: bool, now_ms: int, state: Dictionary
) -> void:
	if tag != "":
		if not was_collated:
			_last_collation_state = state
		_last_collation_tag = tag
		_last_collation_time = now_ms
		_last_collation_full = full
		_last_collation_scoped = scoped
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
	_last_collation_scoped = false
