@tool
class_name HFAutosaveScheduler
extends RefCounted
## When the timed `.hflevel` autosave runs (#1736).
##
## The timer used to save the moment it fired. The level is captured on the main
## thread before the write goes to its own, so on a big level a timer landing in
## a drag or a paint stroke stalled the editor mid gesture, and the copy it kept
## was the level halfway through that gesture.
##
## Now a timer that fires mid gesture waits: until the gesture ends and nothing
## has changed for `pause_ms`, or until twice the interval has gone by, so a
## session that never pauses is still saved. A level that has not changed since
## the last autosave is not captured at all.
##
## The editor answers the two things the level cannot see for itself, through
## `editor_state`: whether the mapper is mid gesture in a way only the plugin
## knows (a vertex or gizmo drag, a marquee, a tool with points placed), and the
## undo history's version, which moves with every recorded change.

const HFInputStateType = preload("../input_state.gd")

## How long nothing must change before a put off autosave runs.
const PAUSE_MS := 2000
## How often a waiting autosave looks again.
const POLL_MS := 250

## The level's signals that say it changed. The editor's undo version covers the
## rest.
const CHANGE_SIGNALS := [
	"brush_added",
	"brush_removed",
	"brush_changed",
	"entity_added",
	"entity_removed",
	"paint_layer_changed",
	"paint_stroke_committed",
	"material_list_changed",
	"settings_applied",
	"state_loaded",
]
## Those of them that pass nothing. The rest pass one value.
const NO_ARGUMENTS := ["material_list_changed", "settings_applied", "state_loaded"]

## The editor's answer for a level, `{"gesture": bool, "version": int}`. The
## plugin sets it while it is in the tree; outside the editor it is unset.
static var editor_state := Callable()

var root: Node = null
var pause_ms := PAUSE_MS
## The time in milliseconds. Tests set their own.
var clock := Callable()
## True while an autosave is put off.
var waiting := false

var _changes := 0
var _saved_marker: Variant = null
var _wait_marker: Variant = null
var _wait_started := 0
var _quiet_since := 0
var _last_poll := 0


func _init(level_root: Node = null) -> void:
	root = level_root
	if root == null:
		return
	for signal_name in CHANGE_SIGNALS:
		if not root.has_signal(signal_name):
			continue
		# `unbind(0)` is an error, so a signal with nothing to drop connects as is.
		if signal_name in NO_ARGUMENTS:
			root.connect(signal_name, _on_level_changed)
		else:
			root.connect(signal_name, _on_level_changed.unbind(1))


func _on_level_changed() -> void:
	_changes += 1


## The autosave interval came round.
func on_timer() -> void:
	if waiting or not _changed_since_saved():
		return
	if editing():
		_begin_wait()
		return
	_run()


## Called every frame while waiting. Runs the put off autosave once editing has
## paused, or once it has waited twice the interval.
func poll() -> void:
	if not waiting:
		return
	var now := _now()
	if now - _last_poll < POLL_MS:
		return
	_last_poll = now
	if not root.hflevel_autosave_enabled:
		_end_wait()
		return
	var marker: Variant = change_marker()
	if editing() or marker != _wait_marker:
		_wait_marker = marker
		_quiet_since = now
	if now - _quiet_since >= pause_ms or now - _wait_started >= cap_ms():
		_run()


## The longest an autosave waits: twice the interval.
func cap_ms() -> int:
	return int(root.hflevel_autosave_minutes) * 60 * 1000 * 2


## What the level looks like to the question "has it changed": the level's own
## change count, and the editor's undo version when the editor gives one.
func change_marker() -> Variant:
	var state := _editor_state()
	return [_changes, state.get("version")]


## Whether the mapper is mid gesture: the level's own input (a drag, an extrude,
## a paint stroke) or what the editor says.
func editing() -> bool:
	var input = root.get("input_state")
	if (
		input != null
		and input.mode != HFInputStateType.Mode.IDLE
		and input.mode != HFInputStateType.Mode.VERTEX_EDIT
	):
		return true
	var paint = root.get("paint_tool")
	if paint != null and paint.has_method("is_stroke_active") and paint.is_stroke_active():
		return true
	return _editor_state().get("gesture") == true


## An autosave that did not land is not a save. The next timer tries again.
func forget_saved() -> void:
	_saved_marker = null


func _changed_since_saved() -> bool:
	return _saved_marker == null or change_marker() != _saved_marker


func _begin_wait() -> void:
	waiting = true
	_wait_started = _now()
	_quiet_since = _wait_started
	_last_poll = 0
	_wait_marker = change_marker()
	if root.has_signal("autosave_waiting"):
		root.autosave_waiting.emit(true)


func _end_wait() -> void:
	if not waiting:
		return
	waiting = false
	if root.has_signal("autosave_waiting"):
		root.autosave_waiting.emit(false)


func _run() -> void:
	_end_wait()
	_saved_marker = change_marker()
	root.save_hflevel(root.resolved_hflevel_path(), true, true)


func _editor_state() -> Dictionary:
	if not editor_state.is_valid():
		return {}
	var state: Variant = editor_state.call(root)
	return state if state is Dictionary else {}


func _now() -> int:
	if clock.is_valid():
		return int(clock.call())
	return Time.get_ticks_msec()
