extends GutTest

## Carve asked "Carve 1 brush(es)?" before it knew it could cut anything, and only
## after OK said there was nothing to carve (#1267). The OK went through
## `HFUndoHelper.commit()` either way, and that registers an undo step whatever the
## method then does, so the refusal left a "Carve" step that changed nothing. The
## history callback fires on the same path, so a fake plugin's history counts the
## steps a real editor would get. The press now asks `can_carve_brush()` first, as
## Hollow and Clip ask theirs.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")

var root: LevelRoot
var plugin: FakePlugin
var messages: Array = []


## Just enough of the plugin to open the confirmation and commit what it confirms.
class FakePlugin:
	extends Node

	var dock = null
	var selection: Array = []
	var dialogs: Array = []
	var history: Array = []

	func _current_selection_nodes() -> Array:
		return selection

	func _add_confirmable_dialog(dlg: ConfirmationDialog) -> void:
		dialogs.append(dlg)
		add_child(dlg)

	func _get_undo_redo() -> EditorUndoRedoManager:
		return null

	func _record_history(action_name: String) -> void:
		history.append(action_name)


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	plugin = FakePlugin.new()
	add_child_autofree(plugin)
	messages = []
	root.user_message.connect(func(text: String, _level: int): messages.append(text))


func after_each():
	root = null
	plugin = null


func _box(brush_id: String, centre: Vector3, size: Vector3 = Vector3(32, 32, 32)) -> DraftBrush:
	return root.create_brush_from_info({"size": size, "center": centre, "brush_id": brush_id})


func _brush_count() -> int:
	return root.draft_brushes_node.get_child_count()


## OK on every confirmation the press opened, as a user who says yes to it.
func _confirm_all() -> void:
	for dlg in plugin.dialogs:
		if is_instance_valid(dlg):
			dlg.confirmed.emit()


func test_a_carve_that_would_cut_nothing_says_so_without_asking():
	var carver := _box("carver", Vector3.ZERO)
	_box("far", Vector3(500, 0, 0))
	plugin.selection = [carver]

	assert_true(HFPluginEditActions.carve_selected(plugin, root), "the press is handled")
	assert_eq(plugin.dialogs.size(), 0, "nothing is asked")
	assert_eq(messages.size(), 1, "the reason is given instead")
	if messages.size() == 1:
		assert_string_contains(messages[0], "no overlapping brushes found")

	# The old press asked here. Saying yes recorded a step and changed nothing.
	_confirm_all()
	assert_eq(plugin.history, [], "no undo step for a carve that cut nothing")
	assert_eq(_brush_count(), 2, "and nothing in the level changed")


func test_a_carve_that_cuts_still_asks_and_carves():
	_box("target", Vector3.ZERO, Vector3(64, 64, 64))
	var carver := _box("carver", Vector3(32, 32, 32))
	plugin.selection = [carver]

	HFPluginEditActions.carve_selected(plugin, root)
	assert_eq(plugin.dialogs.size(), 1, "the carve is asked about")
	if plugin.dialogs.size() == 1:
		assert_string_contains(plugin.dialogs[0].dialog_text, "Carve 1 brush?")
	_confirm_all()

	assert_eq(plugin.history, ["Carve"], "one step")
	assert_null(root.brush_system.find_brush_by_id("carver"), "the carver is used up")
	assert_null(root.brush_system.find_brush_by_id("target"), "the target is in pieces")
	assert_gt(_brush_count(), 1, "and the pieces are there")


func test_only_the_carvers_that_cut_are_asked_about_and_committed():
	_box("target", Vector3.ZERO, Vector3(64, 64, 64))
	var cutting := _box("cutting", Vector3(32, 32, 32))
	var idle := _box("idle", Vector3(500, 0, 0))
	plugin.selection = [cutting, idle]

	HFPluginEditActions.carve_selected(plugin, root)
	assert_eq(plugin.dialogs.size(), 1)
	if plugin.dialogs.size() == 1:
		assert_string_contains(plugin.dialogs[0].dialog_text, "Carve 1 brush?")
	_confirm_all()

	assert_eq(plugin.history, ["Carve"], "a step for the carver that cut, none for the other")
	assert_not_null(root.brush_system.find_brush_by_id("idle"), "the idle carver is left alone")
	assert_eq(messages, [], "and nothing is refused after the yes")


## A locked brush the carver overlaps is named before the yes and left whole
## after it (#1973).
func test_the_question_names_a_locked_brush_and_the_carve_leaves_it_whole():
	_box("target", Vector3.ZERO, Vector3(64, 64, 64))
	var done := _box("done", Vector3(64, 0, 0), Vector3(64, 64, 64))
	root.create_visgroup("Done")
	root.add_selection_to_visgroup("Done", [done])
	root.visgroup_system.set_visgroup_locked("Done", true)
	var before: Dictionary = root.get_brush_info_from_node(done)
	var carver := _box("carver", Vector3(32, 0, 0), Vector3(16, 16, 16))
	plugin.selection = [carver]

	HFPluginEditActions.carve_selected(plugin, root)
	assert_eq(plugin.dialogs.size(), 1, "the carve is asked about")
	if plugin.dialogs.size() == 1:
		assert_string_contains(plugin.dialogs[0].dialog_text, "Carve 1 brush?")
		assert_string_contains(
			plugin.dialogs[0].dialog_text, "1 locked brush overlaps and is left alone."
		)
	_confirm_all()

	assert_eq(plugin.history, ["Carve"], "one step")
	assert_null(root.brush_system.find_brush_by_id("target"), "the unlocked brush is in pieces")
	var still = root.brush_system.find_brush_by_id("done")
	assert_not_null(still, "the locked brush is still there")
	if still:
		assert_eq(root.get_brush_info_from_node(still), before, "and is as it was")


## Two carvers that overlap each other: the first cuts the second up along with the
## target, so by its turn the second is no longer there to carve with.
func test_a_carver_an_earlier_one_cut_up_is_not_committed():
	_box("target", Vector3.ZERO, Vector3(64, 64, 64))
	var first := _box("first", Vector3(32, 32, 32))
	var second := _box("second", Vector3(48, 48, 48))
	plugin.selection = [first, second]

	HFPluginEditActions.carve_selected(plugin, root)
	assert_eq(plugin.dialogs.size(), 1)
	if plugin.dialogs.size() == 1:
		assert_string_contains(plugin.dialogs[0].dialog_text, "Carve 2 brushes?")
	_confirm_all()

	assert_null(root.brush_system.find_brush_by_id("second"), "the first carver cut the second up")
	assert_eq(plugin.history, ["Carve"], "so only the first is a step")
	assert_eq(messages, [], "and the second is not refused after the yes")
