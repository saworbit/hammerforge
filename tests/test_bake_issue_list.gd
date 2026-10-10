extends GutTest

## The issue list under Check Bake Issues, with a fix where one is mechanical
## (#992).
##
## Bake Check toasted its first three findings and sent the rest to Output, so a
## problem was a sentence that faded. Each finding is now a row naming its object,
## with Select, and a Fix button where the fix is one edit and one undo step. A
## fix that would be a guess, such as how deep to sink a floating cutter, is not
## given a button.
##
## The dock's undo manager cannot be built outside the editor, so the two spawn
## commits are caught by a dock that overrides them, as `test_cordon_undo.gd` does.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFSpawnSystemScript = preload("res://addons/hammerforge/systems/hf_spawn_system.gd")


class DockWithCommits:
	extends "res://addons/hammerforge/dock.gd"

	var commits: Array = []

	func _commit_spawn_create(_before_state: Dictionary) -> void:
		commits.append("create")

	func _commit_spawn_move(_spawn: Node3D, _old_pos: Vector3, _new_pos: Vector3) -> void:
		commits.append("move")


var root: LevelRoot
var dock: Node


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock = DockScene.instantiate()
	dock.set_script(DockWithCommits)
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()


func after_each() -> void:
	root = null
	dock = null


func _box(size: Vector3, center: Vector3, subtract: bool = false) -> void:
	var info := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": size,
		"center": center,
		"operation": CSGShape3D.OPERATION_SUBTRACTION if subtract else CSGShape3D.OPERATION_UNION,
	}
	assert_not_null(root.create_brush_from_info(info), "fixture: a brush")


func _floor() -> void:
	_box(Vector3(8, 0.5, 8), Vector3(0, -0.25, 0))


func _spawn_at(at: Vector3) -> Node3D:
	var spawn: Node3D = root._create_entity_from_map({"classname": "player_start", "origin": at})
	spawn.entity_data["height_offset"] = 1.0
	return spawn


func _check() -> void:
	HFDockManageHandler.on_bake_check_issues(dock)


func _row(containing: String) -> HBoxContainer:
	for row in dock.bake_issue_list.get_children():
		if row.is_queued_for_deletion():
			continue
		if (row.get_child(0) as Label).text.contains(containing):
			return row
	return null


func _button(row: HBoxContainer, text: String) -> Button:
	for child in row.get_children():
		if child is Button and (child as Button).text == text:
			return child
	return null


func test_the_list_shows_what_bake_check_raises_on_the_object_it_names():
	_floor()
	_box(Vector3(1, 1, 1), Vector3(0, 6, 0), true)
	_spawn_at(Vector3(2, 1.1, 2))
	_check()
	assert_true(dock.bake_issue_list.visible, "there is something to list")
	var row := _row("doesn't intersect any additive brush")
	assert_not_null(row, "the floating cutter is a row")
	if row == null:
		return
	assert_not_null(_button(row, "Select"), "which can select the cutter it names")
	assert_null(_button(row, "Fix"), "how deep to sink it is the mapper's call")


func test_a_clean_level_lists_nothing():
	_floor()
	_spawn_at(Vector3(2, 1.1, 2))
	_check()
	assert_false(dock.bake_issue_list.visible)


func test_a_missing_spawn_is_fixed_in_one_step():
	_floor()
	_check()
	var row := _row("No player spawn")
	assert_not_null(row, "a level with brushes and no spawn says so")
	if row == null:
		return
	_button(row, "Fix").pressed.emit()
	assert_not_null(root.spawn_system.get_active_spawn(), "the fix made one")
	assert_eq(dock.commits, ["create"], "as one undo step")
	assert_null(_row("No player spawn"), "and the list checked again")


func test_a_spawn_inside_a_brush_moves_clear_in_one_step():
	_floor()
	_box(Vector3(1, 3, 1), Vector3(0, 1.5, 0))
	var spawn := _spawn_at(Vector3(0, 1.1, 0))
	_check()
	var row := _row("stands inside a brush")
	assert_not_null(row, "the spawn in the pillar is a row")
	if row == null:
		return
	assert_not_null(_button(row, "Select"))
	_button(row, "Fix").pressed.emit()
	assert_eq(dock.commits, ["move"], "one undo step")
	assert_false(root.spawn_system.spawn_is_blocked(spawn), "clear of the pillar")
	assert_almost_eq(spawn.global_position.y, 1.1, 0.001, "on the same floor")
	assert_null(_row("stands inside a brush"), "and the row is gone")


func test_a_spawn_upstairs_moves_along_its_own_floor():
	_floor()
	_box(Vector3(8, 0.5, 8), Vector3(0, 3.75, 0))
	_box(Vector3(1, 3, 1), Vector3(0, 5.5, 0))
	var spawn := _spawn_at(Vector3(0, 5.1, 0))
	assert_true(root.spawn_system.spawn_is_blocked(spawn), "fixture: inside the upstairs pillar")
	HFDockManageHandler.move_spawn_clear(dock, spawn)
	assert_almost_eq(spawn.global_position.y, 5.1, 0.001, "still upstairs, not dropped a storey")
	assert_false(root.spawn_system.spawn_is_blocked(spawn))


func test_an_empty_level_has_no_spawn_rows():
	assert_eq(root.spawn_system.layout_issues(), [])
