@tool
class_name HFPluginProblemReport
extends RefCounted
## Report a Problem in the Console (#1655): a short form, the facts the editor
## already knows, and the bug form opened in the browser filled in with both.
## The person submits it there; nothing is sent from here.

const HFProblemReportType = preload("hf_problem_report.gd")
const HFConsoleLogType = preload("hf_console_log.gd")
const HFCrashJournalType = preload("hf_crash_journal.gd")

const LOG_LINES := 50
const UNDO_STEPS := 10
const CHECK_LINES := 10
const DIALOG_NAME := "HFReportProblemDialog"
const CLIPBOARD_MESSAGE := "The full report is on your clipboard. Paste it into the form."

## Test seams for what a test cannot let happen: a browser opening, the
## clipboard changing, a file browser opening.
static var open_url := Callable()
static var copy_text := Callable()
static var open_folder := Callable()


## Ask what happened, then open the form. Cancelling sends and opens nothing.
static func open_form(plugin: Object) -> void:
	var host: Node = plugin.get("base_control")
	if host == null or not is_instance_valid(host):
		host = plugin as Node
	var old := host.get_node_or_null(DIALOG_NAME)
	if old:
		old.queue_free()
	var dialog := ConfirmationDialog.new()
	dialog.name = DIALOG_NAME
	dialog.title = "Report a Problem"
	dialog.ok_button_text = "Open the Form"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	dialog.add_child(box)
	var fields := {}
	for field in [
		["what-happened", "What happened"],
		["expected", "What you expected"],
		["repro", "Steps to reproduce"],
	]:
		var label := Label.new()
		label.text = field[1]
		box.add_child(label)
		var text := TextEdit.new()
		text.custom_minimum_size = Vector2(0, 56)
		text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		box.add_child(text)
		fields[field[0]] = text
	var options := {}
	for option in [
		["logs", "Include the last 50 HammerForge log lines", true],
		["stats", "Include level stats", true],
		["screenshot", "Save a viewport screenshot", false],
	]:
		var check := CheckBox.new()
		check.text = option[1]
		check.button_pressed = option[2]
		box.add_child(check)
		options[option[0]] = check
	var note := Label.new()
	note.text = "The form opens in your browser. Nothing is sent until you submit it there."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	dialog.confirmed.connect(
		func():
			var answers := {}
			for key in fields:
				answers[key] = (fields[key] as TextEdit).text
			var chosen := {}
			for key in options:
				chosen[key] = (options[key] as CheckBox).button_pressed
			submit(plugin, answers, chosen)
			dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	host.add_child(dialog)
	dialog.popup_centered()


## Build the report from `answers` (what happened, expected, steps) and the
## editor's facts, and open the form. Returns the report as sent to the form.
static func submit(plugin: Object, answers: Dictionary, options: Dictionary) -> Dictionary:
	var report := compose(plugin, answers, options)
	var link := HFProblemReportType.link(report)
	if str(link["clipboard"]) != "":
		_copy(str(link["clipboard"]))
		HFConsoleLogType.shared().info(CLIPBOARD_MESSAGE, "report")
	if options.get("screenshot") == true:
		_save_screenshot(plugin)
	if open_url.is_valid():
		open_url.call(str(link["url"]))
	else:
		OS.shell_open(str(link["url"]))
	return report


## The report: the person's answers and what the editor knows.
static func compose(plugin: Object, answers: Dictionary, options: Dictionary) -> Dictionary:
	var what := str(answers.get("what-happened", "")).strip_edges()
	var report := {
		"title": HFProblemReportType.title_from(what),
		"what-happened": what,
		"expected": str(answers.get("expected", "")).strip_edges(),
		"repro": str(answers.get("repro", "")).strip_edges(),
		"godot-version": str(Engine.get_version_info().get("string", "")),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"commit": HFProblemReportType.hammerforge_version(),
	}
	var logs := PackedStringArray()
	(
		logs
		. append(
			(
				"Renderer: %s, adapter: %s %s"
				% [
					RenderingServer.get_current_rendering_method(),
					RenderingServer.get_video_adapter_vendor(),
					RenderingServer.get_video_adapter_name(),
				]
			)
		)
	)
	if options.get("stats", true) == true:
		logs.append_array(level_facts(plugin))
	if options.get("logs", true) == true:
		logs.append("")
		logs.append("Last HammerForge log lines:")
		logs.append_array(last_log_lines(LOG_LINES))
	report["logs"] = HFProblemReportType.scrub("\n".join(logs).strip_edges())
	var panel = plugin.get("console_panel")
	if panel and is_instance_valid(panel) and panel.has_method("crash_report"):
		var folder := str(panel.crash_report().get("folder", ""))
		if folder != "":
			report["crash-report"] = HFProblemReportType.scrub(
				HFCrashJournalType.report_text(folder)
			)
	return report


## Counts, the tool in use, the last undo steps and what a level check finds.
static func level_facts(plugin: Object) -> PackedStringArray:
	var lines := PackedStringArray()
	var root = plugin.get("active_root")
	if root == null and plugin.has_method("_get_level_root"):
		root = plugin.call("_get_level_root")
	if root == null or not is_instance_valid(root):
		lines.append("Level: none open")
		return lines
	lines.append(
		(
			"Level: %d brushes, %d entities"
			% [int(root.get_live_brush_count()), int(root.get_entity_count())]
		)
	)
	lines.append("Tool: %s" % tool_in_use(plugin))
	var steps := last_undo_steps(plugin, root, UNDO_STEPS)
	if not steps.is_empty():
		lines.append("Last undo steps: %s" % ", ".join(steps))
	if root.has_method("validate_level"):
		var issues: Array = root.validate_level(false).get("issues", [])
		lines.append("Level check: %d issue%s" % [issues.size(), "" if issues.size() == 1 else "s"])
		for issue in issues.slice(0, CHECK_LINES):
			lines.append("  %s" % str(issue))
	return lines


## The tool the mapper has in hand, by name.
static func tool_in_use(plugin: Object) -> String:
	var registry = plugin.get("_tool_registry")
	if registry and registry.has_active_external_tool():
		return str(registry.get_active_tool().tool_name())
	if plugin.get("_vertex_mode") == true:
		return "Vertex"
	var dock = plugin.get("dock")
	if dock and is_instance_valid(dock):
		if dock.paint_mode and dock.paint_mode.button_pressed:
			return "Paint"
		if dock.tool_select and dock.tool_select.button_pressed:
			return "Select"
	return "Draw"


## The newest undo step names in the level's history, oldest first.
static func last_undo_steps(plugin: Object, root: Node, count: int) -> PackedStringArray:
	var names := PackedStringArray()
	var undo = plugin.get("undo_redo_manager")
	if undo == null:
		return names
	var history = undo.get_history_undo_redo(undo.get_object_history_id(root))
	if history == null:
		return names
	var newest: int = history.get_current_action()
	for index in range(maxi(0, newest - count + 1), newest + 1):
		names.append(history.get_action_name(index))
	return names


static func last_log_lines(count: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var entries: Array = HFConsoleLogType.shared().entries()
	for entry in entries.slice(maxi(0, entries.size() - count)):
		lines.append(HFConsoleLogType.format_entry(entry))
	return lines


## A screenshot of the 3D view beside the reports, and the folder opened so it
## can be dragged into the form.
static func _save_screenshot(plugin: Object) -> void:
	var viewport: Viewport = null
	var editor = (
		plugin.get_editor_interface() if plugin.has_method("get_editor_interface") else null
	)
	if editor and editor.has_method("get_editor_viewport_3d"):
		viewport = editor.get_editor_viewport_3d(0)
	if viewport == null:
		return
	var image := viewport.get_texture().get_image()
	if image == null:
		return
	var folder := ProjectSettings.globalize_path("user://hammerforge/reports")
	DirAccess.make_dir_recursive_absolute(folder)
	var stamp := Time.get_datetime_string_from_system().replace("T", "-").replace(":", "")
	image.save_png(folder.path_join("screenshot-%s.png" % stamp))
	if open_folder.is_valid():
		open_folder.call(folder)
	else:
		OS.shell_open(folder)


static func _copy(text: String) -> void:
	if copy_text.is_valid():
		copy_text.call(text)
	else:
		DisplayServer.clipboard_set(text)
