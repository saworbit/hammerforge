extends GutTest

const HFUndoNav = preload("res://addons/hammerforge/ui/hf_undo_nav.gd")

# UndoRedo.get_version() in Godot 4 starts at 1 and increments on each commit.
# Tests below capture v0/v_top dynamically rather than hard-coding so they're
# robust to engine-version drift.


func test_get_scene_history_id_falls_back_to_global_when_undo_redo_null():
	var id = HFUndoNav.get_scene_history_id(null, null)
	assert_eq(id, EditorUndoRedoManager.GLOBAL_HISTORY)


func test_get_scene_undo_redo_returns_null_when_undo_redo_null():
	assert_null(HFUndoNav.get_scene_undo_redo(null, null))


func test_navigate_to_version_no_op_with_null_undo_redo():
	# Must not crash
	HFUndoNav.navigate_to_version(null, 5)


func _make_ur(steps: int) -> UndoRedo:
	# Godot 4: add_do_method/add_undo_method take a Callable.
	# We push counters onto a captured array so undo/redo do real work and
	# UndoRedo.get_version() advances/decrements as expected.
	var ur := UndoRedo.new()
	var counter := [0]
	for i in steps:
		var v := i + 1
		ur.create_action("step %d" % i)
		ur.add_do_method(func(): counter.append(v))
		ur.add_undo_method(func(): counter.pop_back())
		ur.commit_action()
	return ur


func test_make_ur_advances_version_by_step_count():
	# Sanity check: each commit advances version by 1, regardless of v0 offset.
	var ur := UndoRedo.new()
	var v0 := ur.get_version()
	ur.create_action("a")
	ur.add_do_method(func(): pass)
	ur.add_undo_method(func(): pass)
	ur.commit_action()
	assert_eq(ur.get_version(), v0 + 1)
	ur.free()


func test_navigate_to_version_undoes_to_earlier_version():
	var ur := _make_ur(3)
	var v_top := ur.get_version()
	HFUndoNav.navigate_to_version(ur, v_top - 2)
	assert_eq(ur.get_version(), v_top - 2)
	ur.free()


func test_navigate_to_version_redoes_to_later_version():
	var ur := _make_ur(3)
	var v_top := ur.get_version()
	ur.undo()
	ur.undo()
	assert_eq(ur.get_version(), v_top - 2)
	HFUndoNav.navigate_to_version(ur, v_top)
	assert_eq(ur.get_version(), v_top)
	ur.free()


func test_navigate_to_current_version_is_noop():
	var ur := _make_ur(1)
	var v := ur.get_version()
	HFUndoNav.navigate_to_version(ur, v)
	assert_eq(ur.get_version(), v)
	ur.free()


func test_navigate_clamps_at_history_bounds():
	# Targets past the end of available undo/redo should not loop forever.
	# Capture the actual bounds; the engine's version offset doesn't matter.
	var ur := _make_ur(2)
	var v_top := ur.get_version()
	HFUndoNav.navigate_to_version(ur, v_top - 100)
	var v_bottom := ur.get_version()
	assert_false(ur.has_undo(), "navigate clamps to start when target is below history")
	HFUndoNav.navigate_to_version(ur, v_top + 999)
	assert_eq(ur.get_version(), v_top, "navigate clamps to end when target is above history")
	assert_lt(v_bottom, v_top, "bottom version should be strictly less than top")
	ur.free()
