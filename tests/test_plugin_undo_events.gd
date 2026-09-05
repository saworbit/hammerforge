extends GutTest
## Boundary coverage for the extracted undo/redo reconciliation and replay.

const HFPluginUndoEvents = preload("res://addons/hammerforge/plugin_undo_events.gd")


class FakeOperationReplay:
	extends RefCounted

	var versions: Dictionary = {}

	func get_entry_version(index: int) -> int:
		return int(versions.get(index, -1))


class FakeDock:
	extends RefCounted

	var toasts: Array = []

	func show_toast(message: String, level: int = 0) -> void:
		toasts.append({"message": message, "level": level})

	func last_toast() -> Dictionary:
		return toasts[-1] if not toasts.is_empty() else {}


class FakeUndoRedoManager:
	extends RefCounted

	var history: UndoRedo = null
	var history_id := 7

	func get_object_history_id(_object) -> int:
		return history_id

	func get_history_undo_redo(_id: int) -> UndoRedo:
		return history


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var active_root: Node = null
	var undo_redo_manager = null
	var _operation_replay = null
	var reconcile_queues := 0

	func _queue_managed_brush_reconcile() -> void:
		reconcile_queues += 1

	func _get_level_root() -> Node:
		return active_root


class Counter:
	extends RefCounted

	var value := 0

	func bump() -> void:
		value += 1


var plugin: FakePlugin


func before_each():
	plugin = FakePlugin.new()


func after_each():
	plugin = null


## An UndoRedo with `count` committed actions, left at the newest version.
func _history_with(count: int, counter: Counter) -> UndoRedo:
	var ur := UndoRedo.new()
	autofree(ur)
	for i in count:
		ur.create_action("Step %d" % i)
		ur.add_do_method(counter.bump)
		ur.add_undo_method(counter.bump)
		ur.commit_action()
	return ur


func _with_history(ur: UndoRedo) -> void:
	var manager := FakeUndoRedoManager.new()
	manager.history = ur
	plugin.undo_redo_manager = manager
	plugin.active_root = Node3D.new()
	add_child_autoqfree(plugin.active_root)


# ---------------------------------------------------------------------------
# Replay guards
# ---------------------------------------------------------------------------


func test_replay_without_a_timeline_does_nothing():
	HFPluginUndoEvents.on_replay_requested(plugin, 0)
	assert_eq(plugin.dock.toasts.size(), 0)


func test_replay_of_an_unrecorded_entry_warns():
	plugin._operation_replay = FakeOperationReplay.new()

	HFPluginUndoEvents.on_replay_requested(plugin, 3)

	assert_eq(
		plugin.dock.last_toast().get("message"),
		"Replay: no undo version recorded for this operation"
	)
	assert_eq(plugin.dock.last_toast().get("level"), 1)


func test_replay_without_an_undo_manager_warns():
	var replay := FakeOperationReplay.new()
	replay.versions = {0: 2}
	plugin._operation_replay = replay

	HFPluginUndoEvents.on_replay_requested(plugin, 0)

	assert_eq(plugin.dock.last_toast().get("message"), "Replay: no undo history available")


func test_replay_without_a_history_object_warns():
	var replay := FakeOperationReplay.new()
	replay.versions = {0: 2}
	plugin._operation_replay = replay
	_with_history(null)

	HFPluginUndoEvents.on_replay_requested(plugin, 0)

	assert_eq(plugin.dock.last_toast().get("message"), "Replay: no undo history available")


# ---------------------------------------------------------------------------
# Replay navigation
# ---------------------------------------------------------------------------


func test_replay_walks_back_to_an_older_version():
	var counter := Counter.new()
	var ur := _history_with(3, counter)
	var target: int = ur.get_version() - 2
	var replay := FakeOperationReplay.new()
	replay.versions = {0: target}
	plugin._operation_replay = replay
	_with_history(ur)

	HFPluginUndoEvents.on_replay_requested(plugin, 0)

	assert_eq(ur.get_version(), target, "History should land exactly on the target version")
	assert_eq(plugin.dock.last_toast().get("message"), "Replay: undid 2 steps")


func test_replay_walks_forward_to_a_newer_version():
	var counter := Counter.new()
	var ur := _history_with(3, counter)
	var newest: int = ur.get_version()
	ur.undo()
	ur.undo()
	var replay := FakeOperationReplay.new()
	replay.versions = {0: newest}
	plugin._operation_replay = replay
	_with_history(ur)

	HFPluginUndoEvents.on_replay_requested(plugin, 0)

	assert_eq(ur.get_version(), newest)
	assert_eq(plugin.dock.last_toast().get("message"), "Replay: redid 2 steps")


func test_replay_to_the_current_version_says_so_and_moves_nothing():
	var counter := Counter.new()
	var ur := _history_with(2, counter)
	var current: int = ur.get_version()
	var replay := FakeOperationReplay.new()
	replay.versions = {0: current}
	plugin._operation_replay = replay
	_with_history(ur)

	HFPluginUndoEvents.on_replay_requested(plugin, 0)

	assert_eq(ur.get_version(), current)
	assert_eq(plugin.dock.last_toast().get("message"), "Already at this operation")
	assert_eq(plugin.dock.last_toast().get("level"), 0)


func test_replay_stops_when_the_history_runs_out():
	# A version below everything still in the history must not spin forever.
	var counter := Counter.new()
	var ur := _history_with(2, counter)
	var replay := FakeOperationReplay.new()
	replay.versions = {0: 0}
	plugin._operation_replay = replay
	_with_history(ur)

	HFPluginUndoEvents.on_replay_requested(plugin, 0)

	assert_false(ur.has_undo(), "Every available step should have been undone")
	assert_eq(plugin.dock.last_toast().get("message"), "Replay: undid 2 steps")


func test_replay_reports_a_single_step_in_the_singular():
	var counter := Counter.new()
	var ur := _history_with(2, counter)
	var replay := FakeOperationReplay.new()
	replay.versions = {0: ur.get_version() - 1}
	plugin._operation_replay = replay
	_with_history(ur)

	HFPluginUndoEvents.on_replay_requested(plugin, 0)

	assert_eq(plugin.dock.last_toast().get("message"), "Replay: undid 1 step")


# ---------------------------------------------------------------------------
# Version change reconciliation
# ---------------------------------------------------------------------------


func test_version_change_without_a_root_does_nothing():
	HFPluginUndoEvents.on_version_changed(plugin)
	assert_eq(plugin.reconcile_queues, 0)
