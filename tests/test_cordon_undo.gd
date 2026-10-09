extends GutTest

## The dock's cordon edits are on the undo stack (#969).
##
## The cordons are settings, so a state action neither carries nor restores
## them, and every cordon control wrote straight to the level. Remove deleted a
## cordon fitted round a room with no way back.
##
## Each test drives the real dock and its real handlers. Only where the step
## lands is swapped: an `EditorUndoRedoManager` cannot be built outside the
## editor, so `_commit_cordon_edit()` hands the step to the stand-in
## `test_undo_collation.gd` carries, through the same `record_cordon_edit()`.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const CollationTests = preload("res://tests/test_undo_collation.gd")

const NEAR := AABB(Vector3(-16, -16, -16), Vector3(32, 32, 32))
const FAR := AABB(Vector3(184, -16, -16), Vector3(32, 32, 32))


## The dock, with its cordon steps going to the stand-in.
class DockWithUndo:
	extends "res://addons/hammerforge/dock.gd"

	var fake_undo = null

	func _commit_cordon_edit(action_name: String, before: Dictionary, merge: bool = false) -> void:
		HFDockVisgroupHandler.record_cordon_edit(fake_undo, level_root, action_name, before, merge)


var root: LevelRoot
var dock: Node
var undo


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.cordon_aabb = NEAR
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	root.set_cordon_name(1, "Arena")
	undo = CollationTests.FakeUndoRedo.new()
	dock = DockScene.instantiate()
	dock.set_script(DockWithUndo)
	dock.fake_undo = undo
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()


func after_each():
	dock = null
	root = null
	undo = null


func _box(brush_id: String, centre: Vector3) -> DraftBrush:
	return (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRoot.BrushShape.BOX,
					"size": Vector3(8, 8, 8),
					"center": centre,
					"operation": CSGShape3D.OPERATION_UNION,
					"brush_id": brush_id,
				}
			)
		)
		as DraftBrush
	)


func _pick(index: int) -> void:
	dock.cordon_region_opt.select(index)
	dock._on_cordon_region_selected(index)


func _spins() -> AABB:
	var low := Vector3(dock.cordon_min_x.value, dock.cordon_min_y.value, dock.cordon_min_z.value)
	var high := Vector3(dock.cordon_max_x.value, dock.cordon_max_y.value, dock.cordon_max_z.value)
	return AABB(low, high - low)


## Undo the one step the edit made and check every cordon came back as it was,
## that the next bake rebuilds, and that the dock shows it. Then redo.
func _assert_undo_and_redo(action_name: String, before: Dictionary) -> void:
	assert_eq(undo.entries.size(), 1, "%s is one step" % action_name)
	if undo.entries.size() != 1:
		return
	assert_eq(undo.entries[0]["name"], action_name)
	var after: Dictionary = root.capture_cordons()
	assert_ne(after, before, "fixture: %s changed the cordons" % action_name)

	root._full_reconcile_needed = false
	undo.undo()
	assert_eq(root.capture_cordons(), before, "undo puts every cordon back exactly")
	assert_true(root._full_reconcile_needed, "and the next bake rebuilds")
	assert_eq(
		dock.cordon_region_opt.item_count,
		root.get_all_cordon_regions().size(),
		"the dock lists the cordons undo brought back"
	)
	var shown: int = dock.cordon_region_opt.selected
	assert_eq(_spins(), root.get_all_cordon_regions()[shown], "and shows their bounds")
	assert_eq(dock.cordon_enabled_check.button_pressed, root.cordon_enabled)

	undo.redo()
	assert_eq(root.capture_cordons(), after, "redo makes the edit again")
	assert_eq(dock.cordon_region_opt.item_count, root.get_all_cordon_regions().size())


func test_remove_can_be_undone():
	_pick(0)
	var before: Dictionary = root.capture_cordons()
	dock._on_cordon_remove()
	assert_eq(root.get_all_cordon_regions().size(), 1, "fixture: Remove took one out")
	_assert_undo_and_redo("Remove Cordon", before)
	undo.undo()
	assert_eq(root.get_cordon_name(1), "Arena", "the cordon after it keeps its name")


func test_add_from_selection_can_be_undone():
	var vault := _box("vault", Vector3(-200, 0, 0))
	dock._selection_nodes = [vault]
	var before: Dictionary = root.capture_cordons()
	dock._on_cordon_add_from_selection()
	assert_eq(root.get_all_cordon_regions().size(), 3, "fixture: a cordon was added")
	# Showing the new cordon ticks Enable Cordon, which must not be a second step.
	_assert_undo_and_redo("Add Cordon from Selection", before)


func test_set_from_selection_can_be_undone():
	_pick(1)
	var corridor := _box("corridor", Vector3(100, 0, 0))
	dock._selection_nodes = [corridor]
	var before: Dictionary = root.capture_cordons()
	dock._on_cordon_from_selection()
	assert_true(root.get_all_cordon_regions()[1].has_point(Vector3(100, 0, 0)), "fixture")
	_assert_undo_and_redo("Set Cordon from Selection", before)
	undo.undo()
	assert_eq(root.cordon_extra_aabbs[0], FAR, "the arena is back where it was")


func test_dragging_a_spin_is_one_step():
	_pick(1)
	var before: Dictionary = root.capture_cordons()
	dock.cordon_max_x.value = FAR.end.x + 10.0
	dock.cordon_max_x.value = FAR.end.x + 20.0
	dock.cordon_max_x.value = FAR.end.x + 40.0
	assert_almost_eq(root.cordon_extra_aabbs[0].end.x, FAR.end.x + 40.0, 0.01, "fixture")
	_assert_undo_and_redo("Move Cordon 2", before)
	undo.undo()
	assert_eq(_spins(), FAR, "the spins show the arena where it was")


func test_the_enable_toggle_can_be_undone():
	var before: Dictionary = root.capture_cordons()
	dock.cordon_enabled_check.button_pressed = true
	assert_true(root.cordon_enabled, "fixture")
	_assert_undo_and_redo("Enable Cordon", before)
	undo.undo()
	assert_false(dock.cordon_enabled_check.button_pressed, "the check shows the cordon off again")


func test_a_cordon_s_switch_can_be_undone():
	_pick(1)
	var before: Dictionary = root.capture_cordons()
	dock.cordon_active_check.button_pressed = false
	assert_false(root.is_cordon_active(1), "fixture")
	_assert_undo_and_redo("Skip Cordon", before)
	undo.undo()
	assert_true(dock.cordon_active_check.button_pressed, "the check shows it on again")


func test_a_rename_can_be_undone():
	_pick(1)
	var before: Dictionary = root.capture_cordons()
	dock.cordon_name_edit.text = "Courtyard"
	dock.cordon_name_edit.text_submitted.emit("Courtyard")
	assert_eq(root.get_cordon_name(1), "Courtyard", "fixture")
	_assert_undo_and_redo("Rename Cordon", before)
	undo.undo()
	assert_eq(dock.cordon_region_opt.get_item_text(1), "Arena", "the list shows the old name")


func test_an_edit_that_changes_nothing_is_no_step():
	_pick(1)
	dock.cordon_name_edit.text_submitted.emit("Arena")
	dock.cordon_max_x.value = FAR.end.x
	assert_eq(undo.entries.size(), 0, "nothing changed, so there is nothing to undo")
	assert_false(
		HFDockVisgroupHandler.record_cordon_edit(undo, root, "Nothing", root.capture_cordons()),
		"and recording it says so"
	)
	assert_false(
		HFDockVisgroupHandler.record_cordon_edit(null, root, "Nothing", {}),
		"without an undo manager nothing is recorded"
	)
