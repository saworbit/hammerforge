extends GutTest

## Clip with no point picked splits a brush across its middle on Y (#1024).
##
## Both the dock's Clip button and the Clip shortcut read `center` from
## `get_brush_info_from_node()`, which has no such key, so the split was always
## at y = 0. A brush standing on the floor does not cross y = 0, so the commonest
## brush there is could not be clipped, and one that did cross it was split at 0
## rather than at its middle.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")

var root: LevelRoot


class FakePlugin:
	extends Node

	var selection: Array = []
	var dialogs: Array = []

	func _current_selection_nodes() -> Array:
		return selection

	func _add_confirmable_dialog(dlg: ConfirmationDialog) -> void:
		dialogs.append(dlg)
		add_child(dlg)


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	root.grid_snap = 1.0
	add_child_autoqfree(root)


func after_each():
	root = null


## A box from y 0 to 4, standing on the floor.
func _standing_box() -> DraftBrush:
	var info := {
		"shape": LevelRootType.BrushShape.BOX,
		"size": Vector3(4, 4, 4),
		"center": Vector3(10, 2, 0),
		"brush_id": "standing_1",
	}
	return root.create_brush_from_info(info) as DraftBrush


func test_the_default_split_is_the_middle_of_the_brush():
	_standing_box()
	assert_almost_eq(root.default_clip_position("standing_1", 1), 2.0, 0.001, "y 0 to 4")
	assert_almost_eq(root.default_clip_position("standing_1", 0), 10.0, 0.001, "and on X")


func test_the_default_split_of_a_turned_brush_is_its_world_middle():
	var brush := _standing_box()
	brush.global_transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 3, 0))
	var bounds: AABB = root.brush_system.world_bounds_of(brush)
	assert_almost_eq(
		root.default_clip_position("standing_1", 1), bounds.get_center().y, 0.001, "world Y"
	)


func test_the_clip_shortcut_offers_the_middle_of_a_brush_on_the_floor():
	var brush := _standing_box()
	var plugin := FakePlugin.new()
	add_child_autofree(plugin)
	plugin.selection = [brush]
	watch_signals(root)
	HFPluginEditActions.clip_selected(plugin, root)
	assert_signal_not_emitted(root, "user_message", "no refusal")
	assert_eq(plugin.dialogs.size(), 1, "the confirmation opened")
	if plugin.dialogs.size() == 1:
		assert_string_contains(plugin.dialogs[0].dialog_text, "at 2.0")
	if root.clip_preview:
		root.clip_preview.clear()


func test_the_dock_clip_button_offers_the_middle_too():
	var brush := _standing_box()
	var dock: Node = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock._selection_nodes = [brush]
	HFDockBrushHandler.on_clip(dock)
	var dialog: ConfirmationDialog = null
	for child in dock.get_children():
		if child is ConfirmationDialog and child.title == "Clip Brush":
			dialog = child
	assert_not_null(dialog, "the confirmation opened rather than a refusal")
	if dialog:
		assert_string_contains(dialog.dialog_text, "at 2.0")
	if root.clip_preview:
		root.clip_preview.clear()
