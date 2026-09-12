extends GutTest

## #443. The Load button on an Example Level card replaces the open level. It
## used to do that with no confirmation and no undo, while the Clear Brushes
## button two sections up the same tab went through both.

const DockScene = preload("res://addons/hammerforge/dock.tscn")

var dock: HammerForgeDock
var root: LevelRoot


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root


func after_each() -> void:
	dock = null
	root = null


func _example() -> Dictionary:
	return {
		"title": "Simple Room",
		"brushes": [{"position": [0, 0, 0], "size": [8, 8, 8], "shape": 0, "operation": 0}],
		"entities": [],
	}


func _pending_dialog() -> ConfirmationDialog:
	return dock.get_node_or_null("ExampleLoadConfirm") as ConfirmationDialog


func test_loading_into_a_level_with_work_in_it_asks_first():
	root.create_brush_from_info({"size": Vector3(64, 64, 64), "center": Vector3.ZERO})
	assert_eq(root.get_live_brush_count(), 1)
	dock._load_example_data(_example())
	assert_eq(root.get_live_brush_count(), 1, "Nothing is cleared until the mapper says so")
	var dlg := _pending_dialog()
	assert_not_null(dlg, "A confirmation is waiting")
	assert_string_contains(dlg.dialog_text, "Replace 1 brush")
	assert_string_contains(dlg.dialog_text, "Simple Room")


func test_confirming_replaces_the_level():
	root.create_brush_from_info({"size": Vector3(64, 64, 64), "center": Vector3.ZERO})
	dock._load_example_data(_example())
	var dlg := _pending_dialog()
	assert_not_null(dlg)
	dlg.confirmed.emit()
	assert_eq(root.get_live_brush_count(), 1, "The example replaced the level")


func test_loading_into_an_empty_level_does_not_ask():
	assert_eq(root.get_live_brush_count(), 0)
	dock._load_example_data(_example())
	assert_null(_pending_dialog(), "Nothing to lose, nothing to ask about")
	assert_eq(root.get_live_brush_count(), 1, "The example loaded straight away")


func test_the_load_is_one_undoable_step():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var start := source.find("func _apply_example_data(")
	assert_gt(start, 0, "_apply_example_data exists")
	var body := source.substr(start)
	var next := body.find("\nfunc ", 1)
	if next > 0:
		body = body.substr(0, next)
	assert_true(body.contains("capture_full_state"), "It snapshots before it clears")
	assert_true(
		body.contains("_commit_done_state_action"), "And registers the whole load as one action"
	)
