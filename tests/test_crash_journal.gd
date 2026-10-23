extends GutTest

## A session that dies leaves its journal behind, and the next start turns it
## into a report folder (#1654).

const HFCrashJournalType = preload("res://addons/hammerforge/hf_crash_journal.gd")
const HFPluginCrashJournalType = preload("res://addons/hammerforge/plugin_crash_journal.gd")
const HFStatusBoardType = preload("res://addons/hammerforge/hf_status_board.gd")
const HFStatusRowType = preload("res://addons/hammerforge/ui/hf_status_row.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")

const DIR := "user://hf_test_crash_journal"
## Not a process id Windows hands out (they are multiples of 4), and above what
## Linux reaches on an ordinary machine.
const DEAD := 4000001
const ALIVE := 4000002

var rig: PluginRig = null
var _copied := ""
var _opened := ""
var _ended := 0


func before_each() -> void:
	_clean()
	_copied = ""
	_opened = ""
	_ended = 0


func after_each() -> void:
	if rig:
		await rig.take_down()
		rig = null
	HFPluginCrashJournalType.test_root = ""
	HFPluginCrashJournalType.end_process = Callable()
	HFPluginCrashJournalType.open_folder = Callable()
	HFPluginCrashJournalType.copy_text = Callable()
	OS.unset_environment(HFPluginCrashJournalType.CRASH_TEST_ENV)
	_clean()


func _clean() -> void:
	var folder := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(folder):
		HFCrashJournalType._remove_tree(folder)


func _journal(pid: int = 1) -> HFCrashJournal:
	return HFCrashJournalType.new(DIR, pid)


static func _never_running(_pid: int) -> bool:
	return false


static func _alive_only(pid: int) -> bool:
	return pid == ALIVE


## A journal as a session that died leaves it: started, written, never finished.
func _leave(pid: int, steps: Array = ["Draw Brush"], level := "") -> String:
	var journal := _journal(pid)
	journal.start("test")
	journal.stage("ready")
	for i in steps.size():
		journal.step(str(steps[i]), i + 1, 3, level)
	# The handle closes as the journal is freed, as the system closes it for a
	# process that ended.
	return journal.journal_path()


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func test_a_journal_a_dead_session_left_becomes_a_report():
	var left := _leave(DEAD, ["Draw Brush", "Clip"])
	var reports := _journal().collect(_never_running)
	assert_eq(reports.size(), 1, "one report")
	assert_false(FileAccess.file_exists(left), "the journal is gone once reported")
	if reports.is_empty():
		return
	var folder := str(reports[0]["folder"])
	assert_true(FileAccess.file_exists(folder.path_join("journal.jsonl")))
	var report := HFCrashJournalType.read_report(folder)
	assert_eq(int(report.get("count", 0)), 1)
	assert_eq(str(report.get("stage", "")), "ready", "start up had finished")
	assert_eq(str(report.get("last_step", "")), "Clip")
	assert_eq(str(report.get("hammerforge", "")), "test")
	assert_eq(int(report.get("pid", 0)), DEAD)


func test_a_clean_close_leaves_no_journal():
	var journal := _journal(5)
	assert_eq(journal.start("test"), OK)
	journal.step("Draw Brush", 1, 1, "")
	assert_true(FileAccess.file_exists(journal.journal_path()), "written as it goes")
	journal.finish()
	assert_false(FileAccess.file_exists(journal.journal_path()))


func test_a_running_session_and_another_project_keep_their_journals():
	var running := _leave(ALIVE)
	var other := _journal(DEAD).journal_path()
	var header := JSON.stringify({"kind": "session", "pid": DEAD, "project": "C:/elsewhere/"})
	var step := JSON.stringify({"kind": "step", "name": "Draw Brush", "version": 1})
	_write_bytes(other, ("%s\n%s\n" % [header, step]).to_utf8_buffer())
	var reports := _journal().collect(_alive_only)
	assert_eq(reports.size(), 0, "neither is this session's to report")
	assert_true(FileAccess.file_exists(running), "a live session keeps its journal")
	assert_true(FileAccess.file_exists(other), "another project keeps its journal")


func test_a_broken_journal_is_reported_with_no_script_error():
	var me := _journal()
	# Cut off in the middle of a line.
	var cut := _journal(DEAD).journal_path()
	_leave(DEAD)
	var file := FileAccess.open(cut, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_string('{"kind": "step", "na')
	file.close()
	# Binary junk, with no session line.
	var junk := PackedByteArray()
	for i in 3000:
		junk.append((i * 37 + 11) % 256)
	_write_bytes(_journal(DEAD + 4).journal_path(), junk)
	# 50 MB of one line, and one good line after it.
	var huge := PackedByteArray()
	huge.resize(50 * 1024 * 1024)
	huge.fill(120)
	huge.append_array(
		("\n%s\n" % JSON.stringify({"kind": "step", "name": "Late"})).to_utf8_buffer()
	)
	_write_bytes(_journal(DEAD + 8).journal_path(), huge)

	var reports := me.collect(_never_running)
	assert_eq(reports.size(), 3, "each is reported")
	var by_pid := {}
	for report in reports:
		by_pid[int(report.get("pid", 0))] = report
	assert_eq(int(by_pid.get(DEAD, {}).get("unreadable_lines", 0)), 1, "the cut line is counted")
	assert_eq(str(by_pid.get(DEAD, {}).get("last_step", "")), "Draw Brush")
	assert_gt(int(by_pid.get(DEAD + 4, {}).get("unreadable_lines", 0)), 0)
	assert_eq(str(by_pid.get(DEAD + 8, {}).get("last_step", "")), "Late", "read from its end")
	assert_eq(me.report_folders().size(), 3)
	for folder in me.report_folders():
		assert_lt(HFCrashJournalType._tree_size(folder), 1024 * 1024, "nothing is copied whole")


func test_two_crashes_that_end_alike_are_one_report_seen_twice():
	var me := _journal()
	_leave(DEAD, ["Draw Brush", "Clip"])
	me.collect(_never_running)
	_leave(DEAD + 4, ["Draw Brush", "Clip"])
	var reports := me.collect(_never_running)
	assert_eq(me.report_folders().size(), 1, "one folder")
	assert_eq(int(reports[0].get("count", 0)), 2, "counted twice")
	_leave(DEAD + 8, ["Draw Brush", "Carve"])
	me.collect(_never_running)
	assert_eq(me.report_folders().size(), 2, "a different end is a new report")


func test_reports_are_kept_to_ten_ninety_days_and_a_size():
	var me := _journal()
	for i in 12:
		_leave(DEAD + 4 * i, ["Step %d" % i])
		me.collect(_never_running)
	assert_eq(me.report_folders().size(), HFCrashJournalType.MAX_REPORTS, "ten kept")
	var newest: String = me.report_folders()[0]
	assert_eq(str(HFCrashJournalType.read_report(newest).get("last_step", "")), "Step 11")

	var oldest: String = me.report_folders()[-1]
	var report := HFCrashJournalType.read_report(oldest)
	report["last_seen"] = Time.get_unix_time_from_system() - 91 * 86400
	HFCrashJournalType._store_text(
		oldest.path_join("report.json"), HFCrashJournalType._encode_report(report)
	)
	me.prune()
	assert_false(DirAccess.dir_exists_absolute(oldest), "one over 90 days goes")
	assert_eq(me.report_folders().size(), 9)

	me.max_report_bytes = 1
	me.prune()
	assert_eq(me.report_folders().size(), 1, "over the size, only the newest stays")
	assert_eq(me.report_folders()[0], newest)


func test_the_journal_keeps_its_newest_lines_and_where_start_up_got_to():
	var journal := _journal(7)
	journal.start("test")
	journal.stage("ready")
	for i in 450:
		journal.step("Step %d" % i, i + 1, 1, "")
	var read := HFCrashJournalType.read_journal(journal.journal_path())
	var entries: Array = read["entries"]
	assert_lte(entries.size(), HFCrashJournalType.KEEP_LINES * 2, "trimmed")
	assert_eq(str(entries[-1].get("name", "")), "Step 449")
	assert_eq(HFCrashJournalType._last_name(entries, "stage"), "ready", "the stage line stays")
	assert_false((read["session"] as Dictionary).is_empty(), "the session line stays")
	journal.step("After", 451, 1, "")
	read = HFCrashJournalType.read_journal(journal.journal_path())
	assert_eq(str((read["entries"] as Array)[-1].get("name", "")), "After", "still writing")
	journal.finish()


func test_an_undo_and_a_name_beyond_ascii_read_back():
	var journal := _journal(9)
	journal.start("test")
	journal.step("Réglage ✓", 2, 1, "res://niveau_é.hflevel")
	journal.step("Réglage ✓", 1, 1, "res://niveau_é.hflevel")
	var entries: Array = HFCrashJournalType.read_journal(journal.journal_path())["entries"]
	assert_eq(entries.size(), 2)
	assert_eq(str(entries[0].get("name", "")), "Réglage ✓")
	assert_eq(str(entries[0].get("level", "")), "res://niveau_é.hflevel")
	assert_eq(entries[1].get("undo"), true, "a lower version is an undo")
	journal.finish()


func test_a_report_keeps_the_newest_autosave_and_names_one_too_big():
	var small := DIR.path_join("levels/small.hflevel")
	var big := DIR.path_join("levels/big.hflevel")
	_write_bytes(ProjectSettings.globalize_path(small), "{}".to_utf8_buffer())
	var bytes := PackedByteArray()
	bytes.resize(400)
	_write_bytes(ProjectSettings.globalize_path(big), bytes)
	var journal := _journal(DEAD)
	journal.start("test")
	journal.step("Draw Brush", 1, 1, small)
	journal.step("Draw Brush", 2, 1, big)
	journal = null
	var me := _journal()
	me.max_level_bytes = 100
	var reports := me.collect(_never_running)
	assert_eq(reports.size(), 1)
	var folder := str(reports[0]["folder"])
	assert_true(FileAccess.file_exists(folder.path_join("levels/small.hflevel")), "copied")
	assert_false(FileAccess.file_exists(folder.path_join("levels/big.hflevel")), "left out")
	var notes := {}
	for level in reports[0]["levels"]:
		notes[str(level["level"])] = level
	assert_eq(str(notes[small]["copy"]), "levels/small.hflevel")
	assert_string_contains(str(notes[big]["note"]), "left out")


func test_the_status_board_shows_a_crash_first_with_its_three_buttons():
	var ctx := HFStatusBoardType._empty_context()
	var plain := HFStatusBoardType.evaluate(ctx)
	assert_ne(str(plain[0]["id"]), "crash", "no crash, no row")
	ctx["crash_report"] = {"count": 2, "stage": "ready", "last_step": "Clip", "folder": "x"}
	var checks := HFStatusBoardType.evaluate(ctx)
	assert_eq(checks.size(), plain.size() + 1)
	var row: Dictionary = checks[0]
	assert_eq(str(row["id"]), "crash")
	assert_eq(str(row["value"]), "2 times")
	assert_string_contains(str(row["detail"]), "Clip")
	assert_eq(str(row["action_id"]), "crash_open")
	var more: Array = row.get("more_actions", [])
	assert_eq(more.map(func(action): return action["id"]), ["crash_copy", "crash_dismiss"])
	ctx["crash_report"]["stage"] = "dock"
	assert_string_contains(str(HFStatusBoardType.evaluate(ctx)[0]["detail"]), "starting up")
	ctx["crash_test"] = true
	assert_eq(str(HFStatusBoardType.evaluate(ctx)[-1]["id"]), "crash_test")


func test_the_crash_row_draws_its_further_buttons_and_keeps_them_through_a_refresh():
	var row := HFStatusRowType.new()
	add_child_autofree(row)
	var check := HFStatusBoardType._check_crash({"count": 1, "stage": "ready"})
	row.apply_check(check)
	var buttons: Array = row._more.get_children()
	assert_eq(buttons.map(func(button): return button.text), ["Copy Report", "Dismiss"])
	watch_signals(row)
	buttons[1].pressed.emit()
	assert_signal_emitted_with_parameters(row, "action_requested", ["crash_dismiss"])
	row.apply_check(check)
	assert_eq(row._more.get_child(0), buttons[0], "the same buttons after a refresh")
	row.apply_check(HFStatusBoardType._check_crash_test())
	assert_eq(row._more.get_child_count(), 0, "a row with one button has no others")
	await get_tree().process_frame


func test_the_plugin_reports_a_dead_session_on_start_and_leaves_no_journal_on_close():
	HFPluginCrashJournalType.test_root = DIR
	var left := _leave(DEAD, ["Draw Brush", "Clip"])
	rig = PluginRig.new()
	await rig.bring_up(self)
	var plugin = rig.plugin
	assert_not_null(plugin, rig.error())
	if plugin == null:
		return
	var mine: String = plugin.crash_journal.journal_path()
	assert_true(FileAccess.file_exists(mine), "this session is journaled")
	assert_false(FileAccess.file_exists(left), "the dead one is reported and removed")
	var panel = plugin.console_panel
	var report: Dictionary = panel.crash_report()
	assert_eq(str(report.get("last_step", "")), "Clip", "the Console shows it")

	HFPluginCrashJournalType.copy_text = func(text: String) -> void: _copied = text
	HFPluginCrashJournalType.open_folder = func(folder: String) -> void: _opened = folder
	plugin._on_console_action("crash_copy")
	assert_string_contains(_copied, "Clip", "Copy Report holds the journal's end")
	plugin._on_console_action("crash_open")
	assert_eq(_opened, str(report["folder"]))
	plugin._on_console_action("crash_dismiss")
	assert_true(panel.crash_report().is_empty(), "Dismiss takes the row away")

	await rig.take_down()
	rig = null
	assert_false(FileAccess.file_exists(mine), "a clean close leaves no journal")


func test_an_undo_step_and_a_bridge_call_land_in_the_journal():
	HFPluginCrashJournalType.test_root = DIR
	rig = PluginRig.new()
	await rig.bring_up(self, true)
	var plugin = rig.plugin
	assert_not_null(plugin, rig.error())
	if plugin == null:
		return
	var level = await rig.make_level()
	var undo = rig.undo()
	undo.create_action("Journal Probe")
	undo.add_do_property(level, "bake_chunk_size", 32.0)
	undo.add_undo_property(level, "bake_chunk_size", level.bake_chunk_size)
	undo.commit_action()
	plugin._on_mcp_command_finished("hf_place_brush", false, "LOCKED", 3)
	var read := HFCrashJournalType.read_journal(plugin.crash_journal.journal_path())
	var step := {}
	var bridge := {}
	for entry in read["entries"]:
		if entry.get("name") == "Journal Probe":
			step = entry
		elif entry.get("kind") == "bridge":
			bridge = entry
	assert_eq(str(step.get("kind", "")), "step", "the undo step is journaled")
	assert_eq(str(step.get("level", "")), str(level.resolved_hflevel_path()))
	assert_eq(str(bridge.get("name", "")), "hf_place_brush", "the bridge call is journaled")
	assert_eq(str(bridge.get("code", "")), "LOCKED")


func test_end_editor_runs_only_with_the_crash_test_variable_set():
	HFPluginCrashJournalType.end_process = func() -> void: _ended += 1
	var plugin := RefCounted.new()
	HFPluginCrashJournalType.handle_action(plugin, "crash_test_end")
	assert_eq(_ended, 0, "not without the variable")
	OS.set_environment(HFPluginCrashJournalType.CRASH_TEST_ENV, "1")
	HFPluginCrashJournalType.handle_action(plugin, "crash_test_end")
	assert_eq(_ended, 1)
