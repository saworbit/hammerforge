@tool
extends RefCounted
## Runs what is typed on the Console's command line, and the command scripts the
## line reads from a file (#1696).
##
## `HFCommandLine` reads the line. A command the Agent Bridge runs goes to the
## plugin's dispatcher as the `hf_run_command` request an agent would send, on the
## selection, through `handle_for_person()`: the bridge's checks and refusals, and
## one undo step named for the command. Any other command runs as the palette runs
## it, with the palette's guards.

const HFCommandLine = preload("hf_command_line.gd")
const HFCommandLineViewType = preload("ui/hf_command_line_view.gd")
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFCommandRegistry = preload("hf_command_registry.gd")
const HFConsoleLog = preload("hf_console_log.gd")
const HFPluginMcp = preload("plugin_mcp.gd")
const HFPluginOverlays = preload("plugin_overlays.gd")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The category the line's entries carry in the Console's Log.
const LOG_CATEGORY := "command"
## How wide the line over the viewport is.
const OVERLAY_WIDTH := 520.0


## Wire the Console's own line to the plugin. The line over the viewport is
## built the first time Command Line opens it.
static func setup(plugin: Object) -> void:
	var panel = plugin.get("console_panel")
	if panel and panel.has_method("command_line"):
		_wire(plugin, panel.command_line())


static func teardown(plugin: Object) -> void:
	var panel = plugin.get("console_panel")
	if panel and is_instance_valid(panel) and panel.has_method("command_line"):
		_unwire(panel.command_line())
	var overlay = plugin.get("_command_line_overlay")
	if overlay is Control and is_instance_valid(overlay):
		_unwire(_view_in(overlay))
		HFPluginOverlays.detach_viewport_overlay(plugin, overlay)
		overlay.queue_free()
	plugin.set("_command_line_overlay", null)
	var dialog = plugin.get("_command_script_dialog")
	if dialog is Node and is_instance_valid(dialog):
		dialog.queue_free()
	plugin.set("_command_script_dialog", null)


## Show the line over the viewport and put the keyboard on it.
static func open(plugin: Object) -> void:
	var overlay = plugin.get("_command_line_overlay")
	if not (overlay is Control and is_instance_valid(overlay)):
		overlay = PanelContainer.new()
		overlay.name = "CommandLineOverlay"
		overlay.custom_minimum_size.x = OVERLAY_WIDTH
		var base = plugin.get("base_control")
		if base is Control:
			overlay.theme = base.theme
		var view := HFCommandLineViewType.new()
		overlay.add_child(view)
		_wire(plugin, view)
		view.close_requested.connect(_close.bind(plugin))
		plugin.set("_command_line_overlay", overlay)
		HFPluginOverlays.attach_viewport_overlay(plugin, overlay)
	overlay.visible = true
	HFPluginOverlays.place_viewport_overlay(plugin, overlay)
	_view_in(overlay).call_deferred("focus_line")


static func _close(plugin: Object) -> void:
	var overlay = plugin.get("_command_line_overlay")
	if overlay is Control and is_instance_valid(overlay):
		overlay.visible = false


static func _view_in(overlay: Node) -> Node:
	return overlay.get_child(0) if overlay.get_child_count() > 0 else null


static func _wire(plugin: Object, view: Node) -> void:
	if view == null:
		return
	var history = plugin.get("command_line_history")
	if history is Array:
		view.set_history(history)
	view.run_requested.connect(_run_from.bind(plugin, view))
	view.script_requested.connect(ask_for_script.bind(plugin))


static func _unwire(view: Node) -> void:
	if view == null or not is_instance_valid(view):
		return
	for connection in view.run_requested.get_connections():
		view.run_requested.disconnect(connection["callable"])
	for connection in view.script_requested.get_connections():
		view.script_requested.disconnect(connection["callable"])
	for connection in view.close_requested.get_connections():
		view.close_requested.disconnect(connection["callable"])


static func _run_from(id: String, params: Dictionary, line: String, plugin: Object, view) -> void:
	var outcome: Dictionary = await run(plugin, id, params, line)
	if is_instance_valid(view):
		view.say(outcome["message"])


## Ask for a command script and run it.
static func ask_for_script(plugin: Object) -> void:
	var dialog = plugin.get("_command_script_dialog")
	if not (dialog is FileDialog and is_instance_valid(dialog)):
		dialog = FileDialog.new()
		dialog.name = "CommandScriptDialog"
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.filters = PackedStringArray(["*.txt, *.hfcmd ; Command scripts"])
		dialog.title = "Run Command Script"
		dialog.file_selected.connect(func(path: String): run_script(plugin, path))
		var base: Control = plugin.get_editor_interface().get_base_control()
		if base == null:
			return
		base.add_child(dialog)
		plugin.set("_command_script_dialog", dialog)
	dialog.popup_centered_ratio(0.6)


## Run command `id` with `params`, as `HFCommandLine.read()` gave them, and say
## how it went in the Log. `{ok, message}`; a refusal's message names the field
## the bridge refused, as an agent is told. A coroutine: callers `await` it.
static func run(plugin: Object, id: String, params: Dictionary, line: String) -> Dictionary:
	HFConsoleLog.shared().info("> " + line, LOG_CATEGORY)
	var outcome: Dictionary = await _run(plugin, id, params)
	if outcome["ok"]:
		HFConsoleLog.shared().info(outcome["message"], LOG_CATEGORY)
	else:
		HFConsoleLog.shared().warn(outcome["message"], LOG_CATEGORY)
	return outcome


static func _run(plugin: Object, id: String, params: Dictionary) -> Dictionary:
	var spec := HFCommandRegistry.bridge(id)
	if spec.is_empty():
		plugin.call("_on_hotkey_palette_action", id)
		return {"ok": true, "message": "%s: run" % HFCommandRegistry.label(id)}
	var root: Node = plugin.call("_get_level_root")
	if root == null:
		return {"ok": false, "message": "Open a HammerForge level first."}
	var dispatcher = plugin.get("mcp_dispatcher")
	if dispatcher == null:
		return {"ok": false, "message": "The command line is not ready yet."}
	var request := {"command": id, "params": params}
	var targets := spec.get("targets", {}) as Dictionary
	if int(targets.get("max", -1)) != 0:
		var picked := _selected(plugin, root, bool(targets.get("entities", false)))
		request["brush_ids"] = picked["brush_ids"]
		if not (picked["entities"] as Array).is_empty():
			request["entities"] = picked["entities"]
	var answer: Dictionary = await dispatcher.handle_for_person(
		{"id": "console", "method": "hf_run_command", "params": request}
	)
	if answer.has("error"):
		return {"ok": false, "message": refusal_text(answer["error"])}
	var result: Dictionary = answer.get("result", {})
	var changed: Dictionary = dispatcher.get("last_changed")
	if (
		changed is Dictionary
		and not changed.is_empty()
		and plugin.has_method("get_editor_interface")
	):
		HFPluginMcp.select_last_changed(plugin, changed)
	return {"ok": true, "message": summary(result)}


## The selected brushes by id and the selected entities by path, as the bridge
## names them.
static func _selected(plugin: Object, root: Node, entities_ok: bool) -> Dictionary:
	var ids: Array = []
	var paths: Array = []
	var selection: Array = plugin.get("hf_selection") if plugin.get("hf_selection") is Array else []
	for node in selection:
		if not is_instance_valid(node):
			continue
		if node is DraftBrush and str(node.brush_id) != "":
			ids.append(str(node.brush_id))
		elif entities_ok and node is DraftEntity:
			paths.append(str(root.get_path_to(node)))
	return {"brush_ids": ids, "entities": paths}


## A refusal from the bridge as the line says it: its message, and the value it
## names, so `thickness` is named whether the line gave it by name or by place.
static func refusal_text(error: Dictionary) -> String:
	var message := str(error.get("message", "The command was refused."))
	var details: Dictionary = error.get("details", {})
	var param := str(details.get("param", "")).trim_prefix("params.")
	if param != "" and param not in ["brush_ids", "entities"] and not message.contains(param):
		return "%s: %s" % [param, message]
	return message


## What a command did, in one line: "Hollow: 6 made, 1 removed".
static func summary(result: Dictionary) -> String:
	var parts: PackedStringArray = []
	for pair in [
		["made", "made"],
		["changed", "changed"],
		["removed", "removed"],
		["entities_made", "entities made"],
		["entities_removed", "entities removed"],
	]:
		var many := (result.get(pair[0], []) as Array).size()
		if many > 0:
			parts.append("%d %s" % [many, pair[1]])
	var label := str(result.get("label", "Done"))
	if parts.is_empty():
		return "%s: nothing to change" % label
	return "%s: %s" % [label, ", ".join(parts)]


## Run the command script at `path`: one command a line, `#` for a comment, each
## line its own undo step. Stops at the first line that does not read or is
## refused, and names it. `{ok, message, ran}`. A coroutine: callers `await` it.
static func run_script(plugin: Object, path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _said({"ok": false, "message": "There is no script at %s." % path, "ran": 0})
	var lines := FileAccess.get_file_as_string(path).replace("\r", "").split("\n")
	var ran := 0
	for index in lines.size():
		var line := lines[index].strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var read := HFCommandLine.read(line)
		if read["ok"]:
			var missing := HFCommandLine.missing(read["id"], read["params"])
			if not missing.is_empty():
				read = {"ok": false, "message": "%s needs a value." % missing[0]["key"]}
		if not read["ok"]:
			return _said(_stopped(path, index, read["message"], ran))
		var outcome: Dictionary = await run(plugin, read["id"], read["params"], line)
		if not outcome["ok"]:
			return _said(_stopped(path, index, outcome["message"], ran))
		ran += 1
	return _said(
		{
			"ok": true,
			"message": "%s: ran %d command%s" % [path.get_file(), ran, "" if ran == 1 else "s"],
			"ran": ran,
		}
	)


static func _stopped(path: String, index: int, why: String, ran: int) -> Dictionary:
	return {
		"ok": false,
		"message":
		(
			"%s stopped at line %d, after %d command%s: %s"
			% [path.get_file(), index + 1, ran, "" if ran == 1 else "s", why]
		),
		"ran": ran,
	}


static func _said(outcome: Dictionary) -> Dictionary:
	if outcome["ok"]:
		HFConsoleLog.shared().info(outcome["message"], LOG_CATEGORY)
	else:
		HFConsoleLog.shared().warn(outcome["message"], LOG_CATEGORY)
	return outcome
