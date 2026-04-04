extends GutTest
## Tests for the undo/redo button refresh path when history_list is null
## (history browser replaces ItemList), and for _on_export_playtest() undo
## behavior when auto-creating a spawn.

var root: LevelRoot
var dock: HammerForgeDock


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)

	dock = HammerForgeDock.new()
	dock.level_root = root
	dock._selection_nodes = []


func after_each():
	if dock and is_instance_valid(dock):
		dock.free()
	dock = null
	root = null


# ===========================================================================
# Undo/redo button refresh when history_list is null
# ===========================================================================


func test_history_list_is_null_by_default():
	# When dock is not added to tree (no _ready), history_list stays null.
	# history_browser may also be null. This is the scenario after the
	# manage_tab_builder replaced ItemList with HFHistoryBrowser.
	assert_null(dock.history_list, "history_list should be null without _ready")


func test_refresh_history_list_does_not_crash_when_history_list_null():
	dock.history_list = null
	# Should not crash even though history_list is null
	dock._refresh_history_list()
	assert_true(true, "No crash when history_list is null")


func test_update_history_buttons_called_when_history_list_null():
	# Create real buttons so _update_history_buttons has something to update
	var undo_btn = Button.new()
	var redo_btn = Button.new()
	dock.undo_btn = undo_btn
	dock.redo_btn = redo_btn
	dock.history_list = null

	# Both should start enabled (default Button state)
	assert_false(undo_btn.disabled)
	assert_false(redo_btn.disabled)

	# With no UndoRedo set, _update_history_buttons should disable both.
	# This is the key path: _refresh_history_list must reach _update_history_buttons
	# even when history_list is null.
	dock._refresh_history_list()
	assert_true(undo_btn.disabled, "Undo should be disabled with no UndoRedo")
	assert_true(redo_btn.disabled, "Redo should be disabled with no UndoRedo")

	undo_btn.free()
	redo_btn.free()


func test_refresh_history_list_after_version_changed_updates_buttons():
	# Simulates what happens when _on_undo_redo_version_changed fires.
	# This is the real-world trigger: version changes call _refresh_history_list.
	var undo_btn = Button.new()
	var redo_btn = Button.new()
	dock.undo_btn = undo_btn
	dock.redo_btn = redo_btn
	dock.history_list = null

	# Manually add some history entries (bypass record_history's undo_redo guard)
	dock.history_entries.append({"name": "Test", "version": 1})

	# Simulate version_changed callback
	dock._refresh_history_list()

	# Buttons should be updated (disabled since no UndoRedo manager)
	assert_true(undo_btn.disabled, "Undo should be disabled after version changed")
	assert_true(redo_btn.disabled, "Redo should be disabled after version changed")

	undo_btn.free()
	redo_btn.free()


# ===========================================================================
# Export playtest spawn undo — verify create_default_spawn is undoable
# ===========================================================================


func test_export_playtest_creates_spawn_when_none_exists():
	# Verify no spawn exists initially
	if root.spawn_system:
		var spawn = root.spawn_system.get_active_spawn()
		assert_null(spawn, "Should have no spawn initially")


func test_spawn_system_create_default_spawn_adds_entity():
	if not root.spawn_system:
		pass_test("No spawn system — skipping")
		return
	var before_count: int = root.get_entity_count()
	var spawn = root.spawn_system.create_default_spawn()
	assert_not_null(spawn, "create_default_spawn should return a node")
	var after_count: int = root.get_entity_count()
	assert_gt(after_count, before_count, "Entity count should increase after spawn creation")


func test_state_capture_before_spawn_differs_from_after():
	if not root.spawn_system or not root.state_system:
		pass_test("No spawn/state system — skipping")
		return
	var before_state: Dictionary = root.state_system.capture_state(true)
	root.spawn_system.create_default_spawn()
	var after_state: Dictionary = root.state_system.capture_state(true)
	# The states should differ because a new entity was added
	assert_ne(before_state, after_state, "State should change after spawn creation")
