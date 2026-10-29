@tool
extends RefCounted
## Compare the open level with a `.hflevel` (#1701): an older save, an autosave,
## or a file taken out of git. What changed is outlined in the viewport and listed
## in the Console's Compare tab, and the open level is only looked at, never
## changed: nothing here touches it or its undo history.

const HFLevelCompare = preload("hf_level_compare.gd")
const HFCompareOverlay = preload("hf_compare_overlay.gd")
# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFConsoleLog = preload("hf_console_log.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFTranslationType = preload("res://addons/hammerforge/hf_translation.gd")


## Compare the open level with the file at `path`, and show what changed. The
## result, or {} when there was nothing to compare.
static func start(plugin: Object, path: String) -> Dictionary:
	var root: Node = plugin.call("_get_level_root")
	if root == null:
		_say(plugin, "Open a HammerForge level first.", 1)
		return {}
	var read: Dictionary = root.file_system.read_hflevel(path)
	if not bool(read.get("ok", false)):
		var unread := HFTranslationType.t("could not read {file}").format({"file": path.get_file()})
		var failed := HFTranslationType.t("Compare: {error}")
		_say(plugin, failed.format({"error": read.get("error", unread)}), 2)
		return {}
	var result := HFLevelCompare.compare(
		read["bundle"], root.state_system.capture_hflevel_payload()
	)
	var overlay = plugin.get("_compare_overlay")
	if overlay == null:
		overlay = HFCompareOverlay.new()
		plugin.set("_compare_overlay", overlay)
	overlay.show(root, result, fade(plugin))
	var panel = plugin.get("console_panel")
	if panel and is_instance_valid(panel):
		panel.show_compare(path.get_file(), result)
	var summary: String = result["lines"][0]
	HFConsoleLog.shared().info("Compared with %s: %s" % [path.get_file(), summary], "compare")
	var compared := HFTranslationType.t("Compared with {file}: {summary}")
	_say(plugin, compared.format({"file": path.get_file(), "summary": summary}), 0)
	return result


## How far a compare fades the brushes that did not change, from Settings.
static func fade(plugin: Object) -> float:
	var prefs = plugin.get("_user_prefs")
	if prefs == null:
		return HFCompareOverlay.DEFAULT_FADE
	return float(prefs.get_pref("compare_fade", HFCompareOverlay.DEFAULT_FADE))


## Fade the unchanged brushes again after a step, and at the strength Settings
## has now. An undo or a redo that rebuilt a brush made a new node.
static func refresh(plugin: Object) -> void:
	var overlay = plugin.get("_compare_overlay")
	if overlay == null or not overlay.is_showing():
		return
	var root: Node = plugin.call("_get_level_root")
	overlay.set_fade(root, fade(plugin))


## Take the compare off the viewport and the Console.
static func end(plugin: Object) -> void:
	var overlay = plugin.get("_compare_overlay")
	if overlay != null:
		overlay.clear()
	var panel = plugin.get("console_panel")
	if panel and is_instance_valid(panel):
		panel.clear_compare()


## Select what a row of the Compare tab names: "brush:<id>" or "entity:<name>".
static func pick(plugin: Object, ref: String) -> void:
	var root: Node = plugin.call("_get_level_root")
	if root == null:
		return
	var node: Node = null
	if ref.begins_with("brush:"):
		node = root.find_brush_by_id(ref.trim_prefix("brush:"))
	elif ref.begins_with("entity:") and root.get("entities_node") != null:
		node = root.entities_node.get_node_or_null(NodePath(ref.trim_prefix("entity:")))
	if node == null or not plugin.has_method("get_editor_interface"):
		return
	var selection = plugin.get_editor_interface().get_selection()
	if selection == null:
		return
	selection.clear()
	selection.add_node(node)


static func _say(plugin: Object, message: String, level: int) -> void:
	var dock = plugin.get("dock")
	if dock and is_instance_valid(dock) and dock.has_method("show_toast"):
		dock.show_toast(message, level)
