@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The Console's command line, Report a Problem and the crash journal, read the
## way a mapper meets them.
##
## The command line (`HFCommandLine`) is promised to take a command "by its id,
## its name or an alias ... as in the palette", values by place or by name, and
## to refuse with the value named. Each name of each command is typed back at it,
## a project alias is offered the way the palette is offered one, and odd lines
## are fed in. A command script runs through `HFPluginCommandLine.run_script()`
## with a stand-in plugin, using commands the bridge does not run so nothing
## reaches a level.
##
## Report a Problem's form is composed from a stand-in plugin and its link is
## decoded again by hand, field by field. The crash journal is pointed at a
## scratch folder under `user://`, never the real one the editor shares.

const HFCommandLine = preload("res://addons/hammerforge/hf_command_line.gd")
const HFCommandAliases = preload("res://addons/hammerforge/hf_command_aliases.gd")
const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const HFPluginCommandLine = preload("res://addons/hammerforge/plugin_command_line.gd")
const HFProblemReport = preload("res://addons/hammerforge/hf_problem_report.gd")
const HFPluginProblemReport = preload("res://addons/hammerforge/plugin_problem_report.gd")
const HFCrashJournal = preload("res://addons/hammerforge/hf_crash_journal.gd")

const SCRATCH := "user://vibe_console_commands"


## Just enough plugin for the runner and the report.
class StandIn:
	extends Node

	var mcp_dispatcher = null
	var hf_selection: Array = []
	var level: Node = null
	var active_root: Node = null
	var palette_ran: Array = []
	var console_panel = null
	var dock = null

	func _get_level_root() -> Node:
		return level

	func _on_hotkey_palette_action(action_id: String) -> void:
		palette_ran.append(action_id)


func id() -> String:
	return "console-commands"


func summary() -> String:
	return "the command line's names, aliases, words and scripts, Report a Problem's link, and the crash journal"


func expected_issues() -> Array[int]:
	return [1991]


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH))
	_every_name()
	_project_aliases()
	_odd_lines()
	await _script()
	await _problem_report()
	_crash_journal()
	_remove_tree(ProjectSettings.globalize_path(SCRATCH))


## Each name a command has, typed on the line, runs that command.
func _every_name() -> void:
	var wrong: PackedStringArray = []
	var checked := 0
	for command_id in HFCommandRegistry.dispatched_ids():
		var names: Array = [command_id, HFCommandRegistry.label(command_id)]
		names.append_array(Array(HFCommandRegistry.aliases(command_id)))
		for typed in names:
			if str(typed) == "":
				continue
			checked += 1
			var found := HFCommandLine.command_of(HFCommandLine.words(str(typed)))
			var got := str(found.get("id", ""))
			if got == command_id:
				continue
			# Two ids kept for one command, such as Extrude Up's, share a label.
			var same_command: bool = (
				got != ""
				and not HFCommandRegistry.runs(got).is_empty()
				and str(HFCommandRegistry.runs(got)) == str(HFCommandRegistry.runs(command_id))
			)
			if same_command:
				continue
			if got == "" and HFCommandLine.words(str(typed)).size() > 6:
				# command_of() reads at most six words, so a longer label is
				# reached by its id or an alias only.
				note(
					"a label of more than six words is not read", "'%s' (%s)" % [typed, command_id]
				)
				continue
			wrong.append("'%s' (%s) runs %s" % [typed, command_id, got if got != "" else "nothing"])
	note("names typed back", "%d, %d run another command or none" % [checked, wrong.size()])
	if not wrong.is_empty():
		flag(
			"%d command names typed on the line run another command or none" % wrong.size(),
			"; ".join(wrong.slice(0, 8))
		)


## A project's own words, from hammerforge_presets/aliases.txt. Parsed from
## text rather than written into res://, and offered to the line as typed.
func _project_aliases() -> void:
	var user := HFCommandAliases.parse("shell2 = hollow\nslice = hollow\n", "vibe aliases")
	var palette := HFCommandAliases.by_command(user)
	note("the palette's words for hollow, with the project file", palette.get("hollow", []))
	var line := HFCommandLine.read("shell2 0.125")
	note("'shell2 0.125' on the line", line)
	var slice := HFCommandLine.read("slice")
	note(
		"'slice' on the line, which the project gives to hollow",
		slice.get("id", slice.get("message"))
	)
	if not bool(line.get("ok", false)) or str(slice.get("id", "")) != "hollow":
		known(
			1991,
			"the command line does not know the project's own aliases",
			(
				"the guide says the line takes a command 'by its id, its name or an alias ... as in the palette', and the palette reads hammerforge_presets/aliases.txt (HFCommandAliases.read_user), where yours win over the built in ones. HFCommandLine._names() reads only HFCommandRegistry.aliases(), so 'shell2' is no command and 'slice' still runs %s"
				% slice.get("id", "nothing")
			)
		)


func _odd_lines() -> void:
	var cases := {
		"": false,
		"   ": false,
		"hollow 0.125": true,
		"HOLLOW 0.125": true,
		"hollow thickness=0.125": true,
		"hollow -0.125": true,
		"hollow 0.1 0.2": false,
		"hollow thickness=0.1 thickness=0.2": false,
		"hollow thickness=abc": false,
		"no_such_command": false,
		"move to floor": true,
		"move to floor 3": false,
	}
	for typed in cases:
		var read := HFCommandLine.read(typed)
		var shown := (
			"ok %s %s" % [read.get("id"), read.get("params")]
			if read["ok"]
			else str(read["message"])
		)
		note("'%s'" % typed.c_escape(), shown)
		if bool(read["ok"]) != bool(cases[typed]):
			flag(
				(
					"'%s' reads %s"
					% [typed.c_escape(), "as a command" if read["ok"] else "as a refusal"]
				),
				shown
			)
		elif not read["ok"] and str(read["message"]).strip_edges() == "":
			flag("'%s' is refused with no reason" % typed.c_escape())
	# Only a space parts words, so a script line laid out with a tab is one
	# word, and a vector pasted as Godot prints one is three.
	note("'hollow<tab>0.125'", HFCommandLine.read("hollow\t0.125").get("message", "ok"))
	# A vector the way the hint shows it, and the way Godot prints one.
	var place := HFCommandLine.read("place_prefab desk position=(1, 2, 3)")
	note("'place_prefab desk position=(1, 2, 3)'", place)


## A script of lines, as a text editor saves one: comments, a blank line, CR LF
## and a line indented with a tab.
func _script() -> void:
	var plain := ""
	for command_id in HFCommandRegistry.dispatched_ids():
		if (
			HFCommandRegistry.bridge(command_id).is_empty()
			and HFCommandRegistry.label(command_id) != ""
			and not command_id.contains("script")
		):
			plain = command_id
			break
	if plain == "":
		note("no command outside the bridge to script with")
		return
	var path := SCRATCH.path_join("vibe.hfcmd")
	var text := "# a comment\r\n\r\n%s\r\n\t%s\r\n%s\t\r\n" % [plain, plain, plain]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var plugin := StandIn.new()
	_tree.get_root().add_child(plugin)
	var outcome: Dictionary = await HFPluginCommandLine.run_script(plugin, path)
	note(
		"script of three %s lines" % plain, "%s; ran %s" % [outcome["message"], plugin.palette_ran]
	)
	if int(outcome.get("ran", 0)) != 3:
		flag(
			"a three line command script ran %d of them" % int(outcome.get("ran", 0)),
			outcome["message"]
		)
	plugin.queue_free()
	await frame()


## Report a Problem's form from a stand-in plugin with a level, and its link
## taken apart again.
func _problem_report() -> void:
	var root: Node3D = await fresh_root("ReportLevel")
	root.hflevel_autosave_enabled = false
	box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	var plugin := StandIn.new()
	plugin.level = root
	plugin.active_root = root
	_tree.get_root().add_child(plugin)
	var home := OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	var user_dir := ProjectSettings.globalize_path("user://")
	HFConsoleLog.shared().info(
		"vibe report: saved %s" % user_dir.path_join("levels/a.hflevel"), "vibe"
	)
	HFConsoleLog.shared().info(
		"vibe report: read %s" % home.path_join("Desktop/x.map").replace("/", "\\"), "vibe"
	)
	var answers := {
		"what-happened": "Hollow & Clip: 100% wrong + odd #3 = bad\nsecond line é 😀",
		"expected": "a=b&c=d",
		"repro": "1. draw\n2. hollow",
	}
	var report: Dictionary = HFPluginProblemReport.compose(
		plugin, answers, {"logs": true, "stats": true}
	)
	note("title", report["title"])
	var logs := str(report.get("logs", ""))
	note("logs, first lines", logs.split("\n").slice(0, 4))
	if home != "" and (logs.contains(home) or logs.contains(home.replace("\\", "/"))):
		flag("the report's logs still name the home folder", home)
	if logs.contains(user_dir.trim_suffix("/")):
		flag("the report's logs still name the user folder", user_dir)
	var link: Dictionary = HFProblemReport.link(report)
	var url := str(link["url"])
	note(
		"link length / limit",
		(
			"%d / %d, clipboard %d chars"
			% [url.length(), HFProblemReport.URL_LIMIT, str(link["clipboard"]).length()]
		)
	)
	var fields := {}
	for pair in url.get_slice("?", 1).split("&"):
		fields[pair.get_slice("=", 0)] = pair.substr(pair.find("=") + 1).uri_decode()
	for key in fields:
		if report.has(key) and str(fields[key]) != str(report[key]):
			flag(
				"the link's %s decodes to something else" % key,
				"%s -> %s" % [str(report[key]).c_escape(), str(fields[key]).c_escape()]
			)
	var short := HFProblemReport.url_for(report, HFProblemReport.FIELDS)
	note("whole form as a link", "%d characters" % short.length())
	var text := HFProblemReport.as_text(report)
	if not text.contains(answers["what-happened"].strip_edges()):
		flag("the clipboard text loses what happened", text.substr(0, 200))
	plugin.queue_free()
	await drop_root(root)


## A session that writes 450 steps and a bridge call, with names outside ASCII,
## and dies; the next session collects it; a second crash ending the same way.
func _crash_journal() -> void:
	var dir := SCRATCH.path_join("journal_root")
	var dead := HFCrashJournal.new(dir, 990001)
	if dead.start("vibe") != OK:
		flag("the journal does not start in a scratch folder", dead.journal_path())
		return
	dead.stage("enter_tree")
	dead.stage("ready")
	for i in 450:
		dead.step("Nudge %d" % i, i + 1, 3, "res://levels/café_%d.hflevel" % (i % 2))
	dead.step("Hollow — 墙", 451, 9, "res://levels/café_1.hflevel")
	dead.bridge("hf_run_command", false, "refused")
	# Dies: the handle goes with the process and the file stays.
	dead._file.close()
	dead._file = null
	var read := HFCrashJournal.read_journal(dead.journal_path())
	note(
		"journal after 452 lines",
		(
			"%d entries, %d unreadable, %d bytes"
			% [read["entries"].size(), read["unreadable"], read["bytes"]]
		)
	)
	var next := HFCrashJournal.new(dir, 990002)
	var reports: Array = next.collect(func(_pid: int) -> bool: return false)
	if reports.size() != 1:
		flag("one dead journal gave %d reports" % reports.size())
		return
	var report: Dictionary = reports[0]
	note(
		"report",
		(
			"stage %s, last step %s, last bridge %s, levels %s"
			% [
				report["stage"],
				report["last_step"],
				report["last_bridge_call"],
				(report["levels"] as Array).size()
			]
		)
	)
	if str(report["last_step"]) != "Hollow — 墙":
		flag("the report's last step is not the last step written", report["last_step"])
	if str(report["stage"]) != "ready":
		flag("the report's stage is not how far start up got", report["stage"])
	var again := HFCrashJournal.read_report(str(report["folder"]))
	if str(again.get("last_step", "")) != "Hollow — 墙":
		flag("report.json does not read back the last step", again.get("last_step"))
	var text := HFCrashJournal.report_text(str(report["folder"]))
	note("report text", "%d lines" % text.split("\n").size())
	# The same crash again.
	var twice := HFCrashJournal.new(dir, 990003)
	twice.start("vibe")
	twice.stage("enter_tree")
	twice.stage("ready")
	for i in 450:
		twice.step("Nudge %d" % i, i + 1, 3, "res://levels/café_%d.hflevel" % (i % 2))
	twice.step("Hollow — 墙", 451, 9, "res://levels/café_1.hflevel")
	twice.bridge("hf_run_command", false, "refused")
	twice._file.close()
	twice._file = null
	var later := HFCrashJournal.new(dir, 990004)
	var counted: Array = later.collect(func(_pid: int) -> bool: return false)
	var count := int(counted[0].get("count", 0)) if counted.size() == 1 else -1
	note(
		"the same crash twice",
		"count %d, %d report folders" % [count, later.report_folders().size()]
	)
	if count != 2 or later.report_folders().size() != 1:
		flag(
			"the same crash twice is not one report counted twice",
			"count %d, folders %d" % [count, later.report_folders().size()]
		)


func _remove_tree(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for file_name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file_name))
	for sub in DirAccess.get_directories_at(folder):
		_remove_tree(folder.path_join(sub))
	DirAccess.remove_absolute(folder)
