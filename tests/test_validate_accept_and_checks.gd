extends GutTest

## Validate's findings can be accepted for good, its kinds of check chosen for
## the project, and its list kept current after an edit (#1731).
##
## Findings that were fine for a level came back on every pass and buried the
## real ones, every check ran or none, and the list was a snapshot until Validate
## was pressed again.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFAcceptedFindings = preload("res://addons/hammerforge/hf_accepted_findings.gd")
const HFValidationChecks = preload("res://addons/hammerforge/hf_validation_checks.gd")

const LEVEL := "user://hf_test_validate_accept.hflevel"
const CHECKS := "user://hf_test_validation_checks.json"

var root: LevelRoot
var dock: Node


func before_each() -> void:
	HFValidationChecks.path = CHECKS
	root = _level()
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()


func after_each() -> void:
	HFValidationChecks.path = HFValidationChecks.PROJECT_FILE
	root = null
	dock = null
	for path in [LEVEL, CHECKS]:
		for suffix in ["", ".previous", ".writing"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


func _box(level: LevelRoot, size: Vector3, center: Vector3, subtract := false) -> DraftBrush:
	return (
		level
		. create_brush_from_info(
			{
				"shape": LevelRoot.BrushShape.BOX,
				"size": size,
				"center": center,
				"operation":
				CSGShape3D.OPERATION_SUBTRACTION if subtract else CSGShape3D.OPERATION_UNION,
			}
		)
	)


## A cut in empty space: Validate says it cuts nothing.
func _stray_cut(level: LevelRoot = root) -> DraftBrush:
	_box(level, Vector3(4, 1, 4), Vector3(0, -0.5, 0))
	return _box(level, Vector3(1, 1, 1), Vector3(10, 3, 10), true)


func _finding_about(report: Dictionary, node: Node) -> Dictionary:
	for finding in report.get("findings", []):
		if finding.get("node") == node:
			return finding
	return {}


func _rows() -> Array:
	var out: Array = []
	for row in dock.bake_issue_list.get_children():
		if not row.is_queued_for_deletion() and row.get_child(0) is Label:
			out.append((row.get_child(0) as Label).text)
	return out


func test_an_accepted_finding_is_set_aside_and_survives_a_save():
	var cut := _stray_cut()
	var finding := _finding_about(root.validate_level(), cut)
	assert_false(finding.is_empty(), "fixture: the stray cut is found")
	assert_eq(str(finding.get("check", "")), "overlap", "and says which check found it")
	HFAcceptedFindings.accept(root, finding, "kept for the next room")
	var again := root.validate_level()
	assert_true(_finding_about(again, cut).is_empty(), "it is set aside")
	assert_false((again["issues"] as Array).has(finding["message"]), "and not counted as an issue")
	assert_eq((again["accepted"] as Array).size(), 1, "it is under accepted")
	var record: Dictionary = again["accepted"][0]["accepted"]
	assert_eq(record["note"], "kept for the next room")
	assert_eq(record["date"], Time.get_date_string_from_system())

	assert_eq(root.save_hflevel(LEVEL, true), OK)
	for _i in 600:
		root._process_hflevel_saves()
		if not root.file_system._hflevel_thread:
			break
		await get_tree().process_frame
	var loaded := _level()
	assert_true(loaded.load_hflevel(LEVEL))
	await get_tree().process_frame
	var after_load := loaded.validate_level()
	assert_eq((after_load["accepted"] as Array).size(), 1, "still accepted after a load")
	assert_false((after_load["issues"] as Array).has(finding["message"]), "and still not an issue")


func test_the_acceptance_undoes_with_the_level():
	var cut := _stray_cut()
	var finding := _finding_about(root.validate_level(), cut)
	var before := root.capture_state()
	HFAcceptedFindings.accept(root, finding)
	assert_eq((root.capture_state()["accepted_findings"] as Dictionary).size(), 1)
	root.restore_state(before)
	assert_eq(root.validation_system.accepted, {}, "an undo takes it back")


func test_editing_what_was_accepted_brings_it_back_marked_changed():
	var cut := _stray_cut()
	HFAcceptedFindings.accept(root, _finding_about(root.validate_level(), cut), "on purpose")
	cut.global_position += Vector3(2, 0, 0)
	var report := root.validate_level()
	var back := _finding_about(report, cut)
	assert_false(back.is_empty(), "the finding is listed again")
	assert_true(back.get("changed_since_accepted", false), "marked changed since accepted")
	assert_eq(back.get("accepted_note", ""), "on purpose", "with the note it was accepted with")


func test_unaccepting_lists_it_again():
	var cut := _stray_cut()
	var key := HFAcceptedFindings.accept(root, _finding_about(root.validate_level(), cut))
	assert_true(HFAcceptedFindings.unaccept(root, key))
	assert_false(_finding_about(root.validate_level(), cut).is_empty())
	assert_false(HFAcceptedFindings.unaccept(root, key), "nothing left to take back")


func test_unticking_a_kind_of_check_stops_it_running():
	var cut := _stray_cut()
	assert_true(HFValidationChecks.runs("overlap"), "every kind runs with no file")
	assert_eq(HFValidationChecks.set_runs("overlap", false), OK)
	assert_true(FileAccess.file_exists(CHECKS), "the project file is written")
	assert_true(_finding_about(root.validate_level(), cut).is_empty(), "the overlap check is off")
	assert_eq(HFValidationChecks.set_runs("overlap", true), OK)
	assert_false(_finding_about(root.validate_level(), cut).is_empty(), "and on again")
	assert_ne(HFValidationChecks.set_runs("nonsense", false), OK, "an unknown kind is refused")


func test_every_finding_names_a_kind_the_checks_menu_lists():
	_stray_cut()
	_box(root, Vector3(0, 1, 1), Vector3(-6, 1, 0))
	for finding in root.validate_level().get("findings", []):
		assert_true(
			HFValidationChecks.KINDS.has(str(finding.get("check", ""))),
			"%s names its kind" % finding.get("message", "")
		)
	dock._on_validate_checks_about_to_popup()
	assert_eq(dock.validate_checks_btn.get_popup().item_count, HFValidationChecks.KINDS.size())


func test_the_dock_row_accepts_with_a_note_and_show_accepted_lists_it():
	var cut := _stray_cut()
	HFDockManageHandler.run_validation(dock, false)
	var finding := {}
	for item in dock._shown_findings["open"]:
		if item.get("node") == cut:
			finding = item
	assert_false(finding.is_empty(), "fixture: the cut is a row")
	var dialog: ConfirmationDialog = HFDockManageHandler.open_accept_dialog(dock, finding)
	var note: LineEdit = dialog.find_child("Note", true, false)
	assert_not_null(note, "the dialog asks why")
	note.text = "a test of the row"
	dialog.confirmed.emit()
	await get_tree().process_frame
	assert_false(_rows().any(func(t): return t.contains(finding["message"])), "the row goes")
	dock.show_accepted_findings.button_pressed = true
	var accepted_rows := _rows().filter(func(t): return t.begins_with("Accepted"))
	assert_eq(accepted_rows.size(), 1, "Show accepted lists it")
	assert_string_contains(accepted_rows[0], "a test of the row")
	var key: String = dock._shown_findings["accepted"][0]["key"]
	HFDockManageHandler.unaccept_finding(dock, key)
	assert_true(_rows().any(func(t): return t.contains(finding["message"])), "Un-accept lists it")


func test_fixing_a_problem_clears_its_row_within_a_second():
	var cut := _stray_cut()
	HFDockManageHandler.run_validation(dock, false)
	var message := ""
	for item in dock._shown_findings["open"]:
		if item.get("node") == cut:
			message = item["message"]
	assert_ne(message, "", "fixture: the cut is a row")
	# Into the floor, where it cuts something.
	cut.global_position = Vector3(0, -0.5, 0)
	root.tag_brush_dirty(str(cut.brush_id))
	assert_not_null(dock._findings_settle, "the edit is waited on")
	assert_almost_eq(dock._findings_settle.wait_time, 1.0, 0.001)
	assert_true(_rows().any(func(t): return t.contains(message)), "still there mid edit")
	await get_tree().create_timer(1.2).timeout
	assert_false(_rows().any(func(t): return t.contains(message)), "gone a second later")
	assert_eq(root.validation_system.full_passes, 1, "without another full pass")


func test_a_recheck_finds_what_an_edit_broke():
	var floor_brush := _box(root, Vector3(4, 1, 4), Vector3(0, -0.5, 0))
	var copy := _box(root, Vector3(1, 1, 1), Vector3(5, 0.5, 0))
	HFDockManageHandler.run_validation(dock, false)
	assert_eq(dock._shown_findings["open"].size(), 0, "fixture: nothing to say")
	# Into the floor slab: a solid wholly inside another.
	copy.global_position = Vector3(0, -0.5, 0)
	copy.size = Vector3(1, 0.5, 1)
	root.tag_brush_dirty(str(copy.brush_id))
	dock._on_findings_settled()
	var found := false
	for item in dock._shown_findings["open"]:
		found = found or (item.get("node") == copy and item.get("other_node") == floor_brush)
	assert_true(found, "the recheck lists the brush the edit put inside the floor")


func test_an_edit_on_a_thousand_brush_level_does_not_run_a_full_pass():
	for i in 1000:
		_box(root, Vector3(1, 1, 1), Vector3(float(i % 40) * 3.0, 0.5, float(i / 40) * 3.0))
	var moved: DraftBrush = _box(root, Vector3(1, 1, 1), Vector3(-30, 0.5, -30))
	HFDockManageHandler.run_validation(dock, false)
	var system = root.validation_system
	assert_eq(system.full_passes, 1)
	moved.global_position += Vector3(0.5, 0, 0)
	root.tag_brush_dirty(str(moved.brush_id))
	dock._on_findings_settled()
	assert_eq(system.full_passes, 1, "the edit ran no full pass")
	assert_eq(system.rechecks, 1, "only a recheck")
	assert_lt(system.last_recheck_brushes, 5, "of the moved brush and what is near it")
