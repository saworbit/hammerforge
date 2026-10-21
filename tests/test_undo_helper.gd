extends GutTest
## Tests for HFUndoHelper collation and history callback behavior.

# HFUndoHelper is a class_name — use it directly, no preload needed.

## For its `FakeUndoRedo`, which records each step's do and undo calls.
const CollationTests = preload("res://tests/test_undo_collation.gd")

# ---------------------------------------------------------------------------
# Minimal root shim that HFUndoHelper.commit() can call methods on.
# ---------------------------------------------------------------------------

var _root_shim_script: GDScript = null
var root: Node = null
var history_log: Array = []


func _make_root_shim_script() -> GDScript:
	if _root_shim_script:
		return _root_shim_script
	_root_shim_script = GDScript.new()
	_root_shim_script.source_code = """
extends Node

var _last_state: Dictionary = {"_init": true}
var call_log: Array = []
var capture_count := 0

func capture_state() -> Dictionary:
	capture_count += 1
	return _last_state.duplicate()

func capture_full_state() -> Dictionary:
	return _last_state.duplicate()

func restore_state(state: Dictionary) -> void:
	_last_state = state

func set_value(key: String, val: float) -> void:
	_last_state[key] = val
	call_log.append({"method": "set_value", "args": [key, val]})

func set_uv_params(brush_id: String, face_idx: int, sx: float, sy: float, rot: float) -> void:
	_last_state["uv"] = {"brush_id": brush_id, "face_idx": face_idx, "sx": sx, "sy": sy, "rot": rot}
	call_log.append({"method": "set_uv_params", "args": [brush_id, face_idx, sx, sy, rot]})

func big_call(a: String, b: int, c: float, d: float, e: float, f: float) -> void:
	call_log.append({"method": "big_call", "args": [a, b, c, d, e, f]})
"""
	_root_shim_script.reload()
	return _root_shim_script


func _record_history(action_name: String) -> void:
	history_log.append(action_name)


func before_each():
	root = Node.new()
	root.set_script(_make_root_shim_script())
	add_child_autoqfree(root)
	history_log.clear()
	# Reset collation state between tests
	HFUndoHelper._reset_collation()


# ===========================================================================
# Basic commit without collation
# ===========================================================================


func test_commit_without_collation_calls_history_cb():
	## Every non-collated commit should invoke the history callback exactly once.
	HFUndoHelper.commit(
		null,  # no EditorUndoRedoManager — falls back to direct callv
		root,
		"TestAction",
		"set_value",
		["x", 1.0],
		false,
		Callable(self, "_record_history"),
		""  # no collation
	)
	assert_eq(history_log.size(), 1, "History callback should fire once")
	assert_eq(history_log[0], "TestAction")


func test_commit_without_collation_fires_each_time():
	## Two separate non-collated commits should each fire the callback.
	for i in range(3):
		HFUndoHelper.commit(
			null,
			root,
			"Action%d" % i,
			"set_value",
			["k", float(i)],
			false,
			Callable(self, "_record_history"),
			""
		)
	assert_eq(history_log.size(), 3, "Each non-collated commit records history")


# ===========================================================================
# Collation: history callback suppression
# ===========================================================================


func test_collation_first_commit_fires_history():
	## The first commit in a collation window should fire the history callback.
	HFUndoHelper.commit(
		null,
		root,
		"UV Edit",
		"set_value",
		["s", 1.0],
		false,
		Callable(self, "_record_history"),
		"uv_brush1_0"
	)
	assert_eq(history_log.size(), 1, "First collated commit should fire history")
	assert_eq(history_log[0], "UV Edit")


func test_collation_subsequent_commits_suppress_history():
	## Consecutive commits with the same collation tag within the window
	## should NOT fire the history callback again.
	var tag := "uv_brush1_0"
	HFUndoHelper.commit(
		null,
		root,
		"UV Edit",
		"set_value",
		["s", 1.0],
		false,
		Callable(self, "_record_history"),
		tag
	)
	HFUndoHelper.commit(
		null,
		root,
		"UV Edit",
		"set_value",
		["s", 1.5],
		false,
		Callable(self, "_record_history"),
		tag
	)
	HFUndoHelper.commit(
		null,
		root,
		"UV Edit",
		"set_value",
		["s", 2.0],
		false,
		Callable(self, "_record_history"),
		tag
	)
	assert_eq(
		history_log.size(), 1, "Only the first commit in a collation run should record history"
	)


func test_different_collation_tags_each_fire_history():
	## Different tags should each start their own collation window.
	HFUndoHelper.commit(
		null,
		root,
		"UV A",
		"set_value",
		["a", 1.0],
		false,
		Callable(self, "_record_history"),
		"uv_brushA_0"
	)
	HFUndoHelper.commit(
		null,
		root,
		"UV B",
		"set_value",
		["b", 1.0],
		false,
		Callable(self, "_record_history"),
		"uv_brushB_0"
	)
	assert_eq(history_log.size(), 2, "Different collation tags each fire history")


func test_collation_resets_after_tag_change():
	## After switching tags and back, a new collation window should start.
	var tag_a := "uv_a"
	var tag_b := "uv_b"
	HFUndoHelper.commit(
		null, root, "A1", "set_value", ["x", 1.0], false, Callable(self, "_record_history"), tag_a
	)
	HFUndoHelper.commit(
		null, root, "A2", "set_value", ["x", 2.0], false, Callable(self, "_record_history"), tag_a
	)
	# Switch to different tag
	HFUndoHelper.commit(
		null, root, "B1", "set_value", ["y", 1.0], false, Callable(self, "_record_history"), tag_b
	)
	# Go back to first tag — should start fresh collation
	HFUndoHelper.commit(
		null, root, "A3", "set_value", ["x", 3.0], false, Callable(self, "_record_history"), tag_a
	)
	# A1 fires, A2 suppressed, B1 fires, A3 fires = 3 total
	assert_eq(history_log.size(), 3, "Tag switch resets collation")
	assert_eq(history_log[0], "A1")
	assert_eq(history_log[1], "B1")
	assert_eq(history_log[2], "A3")


# ===========================================================================
# 5-argument methods (UV params path)
# ===========================================================================


func test_five_arg_method_executes():
	## Verify that 5-arg methods are called via callv (since no undo_redo).
	HFUndoHelper.commit(
		null,
		root,
		"Set UV",
		"set_uv_params",
		["brush_1", 0, 2.0, 2.0, 0.5],
		false,
		Callable(self, "_record_history"),
		""
	)
	var log: Array = root.call_log
	assert_eq(log.size(), 1, "Method should be called once")
	assert_eq(log[0]["method"], "set_uv_params")
	assert_eq(log[0]["args"][0], "brush_1")
	assert_eq(log[0]["args"][2], 2.0)


func test_five_arg_with_collation_suppresses_history():
	## Even with 5 args, collation should suppress duplicate history entries.
	var tag := "uv_b1_0"
	HFUndoHelper.commit(
		null,
		root,
		"UV",
		"set_uv_params",
		["b1", 0, 1.0, 1.0, 0.0],
		false,
		Callable(self, "_record_history"),
		tag
	)
	HFUndoHelper.commit(
		null,
		root,
		"UV",
		"set_uv_params",
		["b1", 0, 1.5, 1.0, 0.0],
		false,
		Callable(self, "_record_history"),
		tag
	)
	HFUndoHelper.commit(
		null,
		root,
		"UV",
		"set_uv_params",
		["b1", 0, 2.0, 1.0, 0.0],
		false,
		Callable(self, "_record_history"),
		tag
	)
	assert_eq(
		history_log.size(), 1, "5-arg collated commits should produce exactly 1 history entry"
	)


# ===========================================================================
# No history callback supplied
# ===========================================================================


func test_null_history_cb_does_not_crash():
	## Passing no history callback should be safe.
	HFUndoHelper.commit(null, root, "NoCb", "set_value", ["k", 1.0], false, Callable(), "")
	# Just verify no crash and method was called
	assert_eq(root.call_log.size(), 1)


# ===========================================================================
# >5 args early-return path with collation
# ===========================================================================


func test_six_arg_collation_suppresses_history():
	## The >5 args early-return path must still track collation state so that
	## consecutive same-tag calls produce only one history entry.
	var tag := "big_tag"
	HFUndoHelper.commit(
		null,
		root,
		"BigCall",
		"big_call",
		["x", 0, 1.0, 2.0, 3.0, 4.0],
		false,
		Callable(self, "_record_history"),
		tag
	)
	HFUndoHelper.commit(
		null,
		root,
		"BigCall",
		"big_call",
		["x", 0, 1.5, 2.0, 3.0, 4.0],
		false,
		Callable(self, "_record_history"),
		tag
	)
	HFUndoHelper.commit(
		null,
		root,
		"BigCall",
		"big_call",
		["x", 0, 2.0, 2.0, 3.0, 4.0],
		false,
		Callable(self, "_record_history"),
		tag
	)
	assert_eq(
		history_log.size(), 1, ">5-arg collated commits should produce exactly 1 history entry"
	)
	# All three calls should have been executed
	var big_calls := 0
	for entry in root.call_log:
		if entry["method"] == "big_call":
			big_calls += 1
	assert_eq(big_calls, 3, "All 3 method calls should still execute")


# ---------------------------------------------------------------------------
# commit_if_changed: no step for a command that changed nothing (#1303)
# ---------------------------------------------------------------------------


func test_commit_if_changed_records_the_step_and_the_history_when_the_level_changed():
	var fake = CollationTests.FakeUndoRedo.new()
	var recorded: bool = HFUndoHelper.commit_if_changed(
		fake, root, "Set", "set_value", ["x", 1.0], Callable(self, "_record_history")
	)
	assert_true(recorded, "a change is a step")
	assert_eq(fake.entries.size(), 1)
	assert_eq(history_log, ["Set"])
	assert_eq(root.call_log.size(), 1, "the method ran once")
	var entry: Dictionary = fake.entries[0]
	assert_eq(entry["do"][0]["method"], "restore_state", "the do is the state the call produced")
	assert_eq(entry["do"][0]["args"][0].get("x"), 1.0)
	assert_eq(entry["undo"][0]["method"], "restore_state")
	assert_false(entry["undo"][0]["args"][0].has("x"), "and the undo is the state before it")
	assert_eq(root.capture_count, 2, "one before capture and one after capture")


class DockShim:
	extends RefCounted
	var level_root: Node
	var undo_redo
	var history: Array = []

	func record_history(action_name: String) -> void:
		history.append(action_name)


class CaptureCountingLevel:
	extends LevelRoot
	var capture_count := 0
	var apply_count := 0

	func capture_state(include_transient: bool = true) -> Dictionary:
		capture_count += 1
		return super.capture_state(include_transient)

	func apply_pending_cuts() -> void:
		apply_count += 1
		super.apply_pending_cuts()


func test_apply_without_pending_cuts_takes_no_captures():
	var level := CaptureCountingLevel.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	level.capture_count = 0
	var dock := DockShim.new()
	dock.level_root = level
	dock.undo_redo = CollationTests.FakeUndoRedo.new()
	HFDockManageHandler.apply_pending_cuts_as_a_step(dock)
	assert_eq(level.capture_count, 0, "the common no-pending path does not capture the level")
	assert_eq(level.apply_count, 0, "there is no work to apply")
	assert_eq(dock.undo_redo.entries.size(), 0)
	assert_eq(dock.history, [])


func test_commit_if_changed_leaves_no_step_when_nothing_changed():
	var fake = CollationTests.FakeUndoRedo.new()
	HFUndoHelper.commit_if_changed(
		fake, root, "Set", "set_value", ["x", 1.0], Callable(self, "_record_history")
	)
	var recorded: bool = HFUndoHelper.commit_if_changed(
		fake, root, "Set", "set_value", ["x", 1.0], Callable(self, "_record_history")
	)
	assert_false(recorded, "setting x to what it already is changes nothing")
	assert_eq(root.call_log.size(), 2, "the method still ran")
	assert_eq(fake.entries.size(), 1, "and left no second step")
	assert_eq(history_log, ["Set"], "nor a second history entry")


# ---------------------------------------------------------------------------
# commit_completed_if_changed: the same, for work already done (#1365)
# ---------------------------------------------------------------------------


func test_commit_completed_if_changed_records_the_work_it_is_handed():
	var fake = CollationTests.FakeUndoRedo.new()
	var before: Dictionary = root.capture_state()
	root.set_value("x", 1.0)
	var recorded: bool = HFUndoHelper.commit_completed_if_changed(
		fake, root, "Set", before, Callable(self, "_record_history")
	)
	assert_true(recorded, "a change is a step")
	assert_eq(fake.entries.size(), 1)
	assert_eq(history_log, ["Set"])
	var entry: Dictionary = fake.entries[0]
	assert_eq(entry["do"][0]["args"][0].get("x"), 1.0, "the do is the state the work left")
	assert_false(entry["undo"][0]["args"][0].has("x"), "and the undo is the state before it")


func test_commit_completed_if_changed_leaves_no_step_when_the_work_changed_nothing():
	var fake = CollationTests.FakeUndoRedo.new()
	root.set_value("x", 1.0)
	var before: Dictionary = root.capture_state()
	root.set_value("x", 1.0)
	var recorded: bool = HFUndoHelper.commit_completed_if_changed(
		fake, root, "Set", before, Callable(self, "_record_history")
	)
	assert_false(recorded, "setting x to what it already is changes nothing")
	assert_eq(fake.entries.size(), 0, "no step")
	assert_eq(history_log, [], "and no history entry")
