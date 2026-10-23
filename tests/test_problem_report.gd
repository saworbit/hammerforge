extends GutTest

## Report a Problem: the bug form opened filled in, and nothing sent (#1655).

const HFProblemReport = preload("res://addons/hammerforge/hf_problem_report.gd")
const HFPluginProblemReport = preload("res://addons/hammerforge/plugin_problem_report.gd")
const HFConsoleLog = preload("res://addons/hammerforge/hf_console_log.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")

const CRASH_DIR := "user://hf_test_problem_report"

var rig: PluginRig = null
var _opened: Array = []
var _copied: Array = []


func before_each() -> void:
	_opened = []
	_copied = []
	HFPluginProblemReport.open_url = func(url: String) -> void: _opened.append(url)
	HFPluginProblemReport.copy_text = func(text: String) -> void: _copied.append(text)
	HFPluginProblemReport.open_folder = func(_folder: String) -> void: pass


func after_each() -> void:
	if rig:
		await rig.take_down()
		rig = null
	HFPluginProblemReport.open_url = Callable()
	HFPluginProblemReport.copy_text = Callable()
	HFPluginProblemReport.open_folder = Callable()
	var folder := ProjectSettings.globalize_path(CRASH_DIR)
	if DirAccess.dir_exists_absolute(folder):
		for file_name in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(file_name))
		DirAccess.remove_absolute(folder)


## The query of a link, decoded, by field.
static func _query(url: String) -> Dictionary:
	var out := {}
	for part in url.get_slice("?", 1).split("&"):
		out[part.get_slice("=", 0)] = part.get_slice("=", 1).uri_decode()
	return out


func _short_report() -> Dictionary:
	return {
		"title": "[Bug] Bake & clip #2",
		"what-happened": "The cut stayed.\nTwo lines, über.",
		"expected": "It goes",
		"repro": "1. Draw\n2. Bake",
		"godot-version": "4.7-stable",
		"os": "Windows 11",
		"commit": "0.4.1",
		"logs": "a line",
	}


func test_the_link_fills_each_field_by_its_id():
	var link := HFProblemReport.link(_short_report())
	assert_eq(link["clipboard"], "", "a short report fits")
	var url: String = link["url"]
	assert_true(url.begins_with(HFProblemReport.ISSUE_URL + "?template=bug_report.yml&"))
	var query := _query(url)
	for field in _short_report():
		assert_eq(query.get(field), _short_report()[field], "%s comes back as written" % field)
	assert_false(url.contains(" ") or url.contains("\n"), "nothing left unencoded")


func test_a_report_too_long_for_a_link_goes_on_the_clipboard():
	var report := _short_report()
	report["logs"] = "x".repeat(3000)
	var link := HFProblemReport.link(report)
	assert_lte((link["url"] as String).length(), HFProblemReport.URL_LIMIT)
	var query := _query(link["url"])
	assert_eq(query.get("godot-version"), "4.7-stable", "the versions still go")
	assert_eq(query.get("os"), "Windows 11")
	assert_false(query.has("logs"), "the long part does not")
	assert_string_contains(link["clipboard"], "### Relevant output\n" + "x".repeat(3000))


func test_the_field_ids_are_the_bug_form_s():
	var form := FileAccess.get_file_as_string("res://.github/ISSUE_TEMPLATE/bug_report.yml")
	var ids: Array = []
	for line in form.split("\n"):
		if line.strip_edges().begins_with("id: "):
			ids.append(line.strip_edges().trim_prefix("id: "))
	assert_eq(ids, HFProblemReport.FIELDS)


func test_a_title_is_the_first_line_cut_short():
	assert_eq(HFProblemReport.title_from("The bake hangs\nat 50%"), "[Bug] The bake hangs")
	var long_title := HFProblemReport.title_from("a".repeat(200))
	assert_eq(long_title.length(), "[Bug] ".length() + HFProblemReport.TITLE_LIMIT)
	assert_true(long_title.ends_with("..."))


func test_paths_lose_everything_but_their_godot_names():
	var project := ProjectSettings.globalize_path("res://levels/a.tscn")
	assert_eq(HFProblemReport.scrub("saved %s" % project), "saved res://levels/a.tscn")
	var home := OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	if home != "":
		var both := "%s/notes.txt and %s\\other.txt" % [home.replace("\\", "/"), home]
		assert_eq(HFProblemReport.scrub(both), "~/notes.txt and ~\\other.txt")


func test_the_plugin_fills_in_what_the_editor_knows_and_opens_the_form():
	rig = PluginRig.new()
	await rig.bring_up(self, true)
	assert_not_null(rig.plugin, rig.error())
	if rig.plugin == null:
		return
	var level = await rig.make_level()
	rig.box(level, "b1", Vector3(0, 2, 0))
	var undo = rig.undo()
	undo.create_action("Probe Step")
	undo.add_do_property(level, "bake_chunk_size", 32.0)
	undo.add_undo_property(level, "bake_chunk_size", level.bake_chunk_size)
	undo.commit_action()
	HFConsoleLog.shared().info("a line the report should carry", "test")
	var report := HFPluginProblemReport.submit(
		rig.plugin,
		{"what-happened": "The cut stayed", "expected": "", "repro": ""},
		{"logs": true, "stats": true, "screenshot": false}
	)
	assert_eq(_opened.size(), 1, "the form opens once")
	var logs: String = report["logs"]
	assert_string_contains(logs, "Level: 1 brushes")
	assert_string_contains(logs, "Tool: Draw")
	assert_string_contains(logs, "Probe Step", "the last undo steps")
	assert_string_contains(logs, "a line the report should carry")
	assert_string_contains(logs, "Level check:")
	assert_eq(report["commit"], HFProblemReport.hammerforge_version())
	var query := _query(_opened[0])
	assert_eq(query.get("title"), "[Bug] The cut stayed")
	assert_eq(query.get("godot-version"), str(Engine.get_version_info()["string"]))


func test_left_out_parts_stay_out():
	rig = PluginRig.new()
	await rig.bring_up(self)
	if rig.plugin == null:
		return
	HFConsoleLog.shared().info("not this line", "test")
	var report := HFPluginProblemReport.submit(
		rig.plugin, {"what-happened": "x"}, {"logs": false, "stats": false}
	)
	assert_false((report["logs"] as String).contains("not this line"))
	assert_false((report["logs"] as String).contains("Level:"))


func test_a_crash_on_the_console_goes_in_its_own_field():
	rig = PluginRig.new()
	await rig.bring_up(self)
	if rig.plugin == null:
		return
	var folder := ProjectSettings.globalize_path(CRASH_DIR)
	DirAccess.make_dir_recursive_absolute(folder)
	var report_file := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	report_file.store_string('{"stage":"ready","last_step":"Clip"}')
	report_file.close()
	rig.plugin.console_panel.record_crash({"folder": folder, "count": 1})
	var report := HFPluginProblemReport.submit(rig.plugin, {}, {"logs": false, "stats": false})
	assert_string_contains(str(report.get("crash-report", "")), "Clip")


func test_cancelling_the_form_opens_nothing():
	rig = PluginRig.new()
	await rig.bring_up(self)
	if rig.plugin == null:
		return
	HFPluginProblemReport.open_form(rig.plugin)
	var host: Node = rig.plugin.base_control if rig.plugin.base_control else rig.plugin
	var dialog = host.get_node_or_null(HFPluginProblemReport.DIALOG_NAME)
	assert_not_null(dialog, "the form is up")
	if dialog == null:
		return
	dialog.canceled.emit()
	assert_eq(_opened, [], "cancel opens no browser")
	await get_tree().process_frame
	HFPluginProblemReport.open_form(rig.plugin)
	dialog = host.get_node_or_null(HFPluginProblemReport.DIALOG_NAME)
	dialog.confirmed.emit()
	assert_eq(_opened.size(), 1, "and the button that says so opens it")
	await get_tree().process_frame
