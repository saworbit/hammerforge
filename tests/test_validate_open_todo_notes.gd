extends GutTest

## Validate can warn about open To Do notes (#1818). Notes (#1700) show on the
## Console's Notes tab and the Status board, and never in Validate. A level
## setting, off by default, makes Validate list each open To Do note.

const HFConsoleControlsType = preload("res://addons/hammerforge/ui/hf_console_controls.gd")

const LEVEL := "user://hf_test_validate_open_todos.hflevel"

var root: LevelRoot


class DockStub:
	extends Node
	var level_root: Node = null


func before_each() -> void:
	root = _level()


func after_each() -> void:
	root = null
	for suffix in ["", ".previous", ".writing"]:
		if FileAccess.file_exists(LEVEL + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(LEVEL + suffix))


func _level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


func _note(title: String, kind := "Note", done := false) -> DraftEntity:
	return (
		root
		. entity_system
		. restore_entity_from_info(
			{
				"name": "Note",
				"entity_type": "note",
				"properties":
				{"title": title, "body": "", "kind": kind, "author": "", "done": done},
				"transform": Transform3D.IDENTITY,
			}
		)
	)


func _note_findings() -> Array:
	var out: Array = []
	for issue in root.validate_level().get("issues", []):
		if str(issue).begins_with("Open To Do note"):
			out.append(str(issue))
	return out


func test_with_the_setting_off_validate_says_nothing_about_notes():
	_note("Light the stair", "To Do")
	assert_false(root.validate_warns_open_todos, "off by default")
	assert_eq(_note_findings(), [])


func test_with_it_on_each_open_to_do_note_is_one_finding_that_selects_it():
	var open := _note("Light the stair", "To Do")
	_note("Check the jump", "To Do", true)
	_note("Lift goes here", "Note")
	_note("Too dark here", "Playtest")
	var second := _note("Close the gap", "To Do")
	root.validate_warns_open_todos = true
	assert_eq(
		_note_findings(), ["Open To Do note: Light the stair", "Open To Do note: Close the gap"]
	)
	var nodes: Array = []
	for finding in root.validation_system._findings:
		if str(finding.get("message", "")).begins_with("Open To Do note"):
			nodes.append(finding.get("node"))
	assert_eq(nodes, [open, second], "each finding names its note, for Select")


func test_the_setting_saves_with_the_level_file():
	root.validate_warns_open_todos = true
	assert_eq(root.save_hflevel(LEVEL, true), OK)
	if root.file_system:
		for _i in 600:
			root._process_hflevel_saves()
			if not root.file_system._hflevel_thread:
				break
			await get_tree().process_frame
	var again := _level()
	assert_true(again.load_hflevel(LEVEL), "the file loads")
	assert_true(again.validate_warns_open_todos, "and keeps the setting")


func test_the_setting_saves_with_the_scene():
	root.validate_warns_open_todos = true
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK)
	var copy = packed.instantiate()
	add_child_autoqfree(copy)
	assert_true(copy.validate_warns_open_todos)


func test_the_console_has_a_row_for_it_under_safety_net():
	var found := false
	for group in HFConsoleControlsType.GROUPS:
		for row in group["rows"]:
			if str(row.get("key", "")) == "validate_warns_open_todos":
				found = group["title"] == "Safety net"
	assert_true(found, "a row under Safety net")
	var dock := DockStub.new()
	dock.level_root = root
	add_child_autoqfree(dock)
	var controls = HFConsoleControlsType.new()
	add_child_autoqfree(controls)
	controls.set_dock(dock)
	controls.refresh()
	var toggle: BaseButton = null
	for row in controls._rows:
		if str(row["spec"].get("key", "")) == "validate_warns_open_todos":
			toggle = row["control"]
	assert_not_null(toggle, "the row is built")
	if toggle == null:
		return
	assert_false(toggle.disabled, "and usable with a level open")
	toggle.button_pressed = true
	assert_true(root.validate_warns_open_todos, "turning it on sets the level's setting")
