@tool
class_name HFPluginCrashJournal
extends RefCounted
## The crash journal in the editor (#1654). Started first in `_enter_tree`, fed
## by every undo step and bridge call, deleted by a clean `_exit_tree`, and read
## on the next start for what a session that died left behind.

const HFCrashJournalType = preload("hf_crash_journal.gd")
const HFConsoleLogType = preload("hf_console_log.gd")

## Set, the Console offers End Editor, which stops the editor the way a crash
## does, so the whole path can be tried.
const CRASH_TEST_ENV := "HAMMERFORGE_CRASH_TEST"

## Outside the editor nothing is journaled unless a test points this at a
## folder of its own.
static var test_root := ""
## Test seams for the three things a test cannot let happen: the editor ending,
## a file browser opening, and the clipboard changing.
static var end_process := Callable()
static var open_folder := Callable()
static var copy_text := Callable()


## Start this editor session's journal, at the start of `_enter_tree`. Only
## in the editor, or in a test that sets `test_root`.
static func setup(plugin: Object) -> void:
	if plugin == null or (not Engine.is_editor_hint() and test_root == ""):
		return
	var journal := HFCrashJournalType.new(test_root if test_root != "" else HFCrashJournalType.ROOT)
	if journal.start(_version()) != OK:
		HFConsoleLogType.shared().warn(
			"Could not start the crash journal at %s." % journal.journal_path(), "crash"
		)
		return
	plugin.set("crash_journal", journal)
	journal.stage("enter_tree")


## Note how far start up or shut down got.
static func stage(plugin: Object, stage_name: String) -> void:
	var journal = _journal(plugin)
	if journal:
		journal.stage(stage_name)


## The end of `_enter_tree`: start up finished, so read what an earlier session
## left behind.
static func started(plugin: Object) -> void:
	var journal = _journal(plugin)
	if journal == null:
		return
	journal.stage("ready")
	var panel = plugin.get("console_panel")
	if panel and is_instance_valid(panel) and OS.has_environment(CRASH_TEST_ENV):
		panel.record_crash_test(true)
	var reports: Array[Dictionary] = journal.collect()
	if reports.is_empty():
		return
	var newest: Dictionary = reports[reports.size() - 1]
	HFConsoleLogType.shared().warn(
		"HammerForge did not close cleanly last time. The report is in %s." % newest["folder"],
		"crash"
	)
	if panel and is_instance_valid(panel):
		panel.record_crash(newest)


## A clean close takes the journal with it.
static func teardown(plugin: Object) -> void:
	var journal = _journal(plugin)
	if journal:
		journal.finish()
	if plugin:
		plugin.set("crash_journal", null)


## Note the undo step just done, with the brush count and the level file, so
## a crash report says what was last done.
static func note_step(plugin: Object, root: Node, history: UndoRedo) -> void:
	var journal = _journal(plugin)
	if journal == null or history == null:
		return
	var brushes := 0
	var level := ""
	if root and is_instance_valid(root):
		if root.has_method("get_live_brush_count"):
			brushes = int(root.call("get_live_brush_count"))
		if root.has_method("resolved_hflevel_path"):
			level = str(root.call("resolved_hflevel_path"))
	journal.step(history.get_current_action_name(), history.get_version(), brushes, level)


## Note a call over the agent bridge and how it ended.
static func note_bridge(plugin: Object, method: String, ok: bool, code: String) -> void:
	var journal = _journal(plugin)
	if journal:
		journal.bridge(method, ok, code)


## The Console's buttons on the crash row and the crash test row.
static func handle_action(plugin: Object, action_id: String) -> void:
	var panel = plugin.get("console_panel")
	if panel and not is_instance_valid(panel):
		panel = null
	var folder := ""
	if panel:
		folder = str(panel.crash_report().get("folder", ""))
	match action_id:
		"crash_open":
			if folder == "":
				return
			if open_folder.is_valid():
				open_folder.call(folder)
			else:
				OS.shell_open(folder)
		"crash_copy":
			if folder == "":
				return
			var text := HFCrashJournalType.report_text(folder)
			if copy_text.is_valid():
				copy_text.call(text)
			else:
				DisplayServer.clipboard_set(text)
			HFConsoleLogType.shared().info("Copied the crash report.", "crash")
		"crash_dismiss":
			if panel:
				panel.record_crash({})
		"crash_test_end":
			if not OS.has_environment(CRASH_TEST_ENV):
				return
			if end_process.is_valid():
				end_process.call()
			else:
				OS.kill(OS.get_process_id())


static func _journal(plugin: Object) -> Object:
	if plugin == null:
		return null
	var journal = plugin.get("crash_journal")
	return journal if journal is HFCrashJournalType and journal.is_open() else null


static func _version() -> String:
	var config := ConfigFile.new()
	if config.load("res://addons/hammerforge/plugin.cfg") != OK:
		return ""
	return str(config.get_value("plugin", "version", ""))
