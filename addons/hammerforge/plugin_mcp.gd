@tool
class_name HFPluginMcp
extends RefCounted
## The MCP bridge in the editor: the dispatcher for the editor session, and the
## listener the Test tab turns on and off.
##
## The dispatcher is made once in `setup()` and lives until the plugin goes, so
## its operation cache lasts the editor session even when the listener is turned
## off and on. The listener only exists while the box is ticked. Nothing here
## starts it on its own: an editor start always leaves the bridge off.

const HFMcpDispatcherType = preload("mcp/hf_mcp_dispatcher.gd")
const HFMcpListenerType = preload("mcp/hf_mcp_listener.gd")
const HFMcpHostType = preload("mcp/hf_mcp_host.gd")
const HFPluginUndoEventsType = preload("plugin_undo_events.gd")
const HFAgentHighlightType = preload("hf_agent_highlight.gd")
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const LevelRoot = preload("level_root.gd")
const HFMcpProtocol = preload("mcp/hf_mcp_protocol.gd")
@warning_ignore_restore("shadowed_global_identifier")

const LISTENER_NODE_NAME := "HFMcpListener"


## The editor as the dispatcher sees it.
class EditorHost:
	extends "mcp/hf_mcp_host.gd"

	var plugin: Object

	func _init(owner_plugin: Object) -> void:
		plugin = owner_plugin

	func edited_scene_root() -> Node:
		return EditorInterface.get_edited_scene_root()

	## The plugin's own lookup, so the bridge works on the same level every other
	## HammerForge command does.
	func level_root_in(scene_root: Node) -> Node:
		if scene_root != null and scene_root == EditorInterface.get_edited_scene_root():
			var found = plugin.call("_get_level_root")
			if found is LevelRoot and (found == scene_root or scene_root.is_ancestor_of(found)):
				return found
		return super.level_root_in(scene_root)

	func undo_manager() -> Object:
		return plugin.get("undo_redo_manager")

	func record_history(action_name: String) -> void:
		plugin.call("_record_history", action_name)

	func viewport_3d() -> Viewport:
		return EditorInterface.get_editor_viewport_3d(0)

	func screenshot_parent() -> Node:
		return EditorInterface.get_base_control()

	func notify_file_written(path: String) -> void:
		var files := EditorInterface.get_resource_filesystem()
		if files:
			files.update_file(path)

	func after_history_step() -> void:
		HFPluginUndoEventsType.on_version_changed(plugin)

	func create_starter(action_name: String) -> Node:
		return plugin.call("create_starter_level", action_name)

	func camera_pose() -> Variant:
		var viewport := EditorInterface.get_editor_viewport_3d(0)
		var camera := viewport.get_camera_3d() if viewport else null
		if camera == null:
			return null
		var degrees := HFMcpProtocol.degrees_from_basis(camera.global_basis)
		return {
			"position":
			[camera.global_position.x, camera.global_position.y, camera.global_position.z],
			"rotation_degrees": [degrees.x, degrees.y, degrees.z],
			"fov": camera.fov,
		}


## `host` is for tests. The plugin passes none and gets the editor's.
static func setup(plugin: Object, host: HFMcpHostType = null) -> void:
	if plugin == null:
		return
	if host == null:
		host = EditorHost.new(plugin)
	plugin.set("mcp_dispatcher", HFMcpDispatcherType.new(host))
	var panel = _panel(plugin)
	if panel:
		var toggled := Callable(plugin, "_on_mcp_enable_toggled")
		if not panel.enable_toggled.is_connected(toggled):
			panel.enable_toggled.connect(toggled)
		var pressed := Callable(plugin, "_on_mcp_last_pressed")
		if not panel.last_pressed.is_connected(pressed):
			panel.last_pressed.connect(pressed)
		panel.set_theme_source(plugin.get("base_control"))


static func teardown(plugin: Object) -> void:
	if plugin == null:
		return
	_stop(plugin)
	var panel = _panel(plugin)
	if panel:
		var toggled := Callable(plugin, "_on_mcp_enable_toggled")
		if panel.enable_toggled.is_connected(toggled):
			panel.enable_toggled.disconnect(toggled)
		var pressed := Callable(plugin, "_on_mcp_last_pressed")
		if panel.last_pressed.is_connected(pressed):
			panel.last_pressed.disconnect(pressed)
	var highlight = plugin.get("_agent_highlight")
	if highlight:
		highlight.clear()
	var dispatcher = plugin.get("mcp_dispatcher")
	if dispatcher:
		dispatcher.shutdown()
	plugin.set("mcp_dispatcher", null)


static func set_enabled(plugin: Object, enabled: bool) -> void:
	if plugin == null:
		return
	if not enabled:
		_stop(plugin)
		return
	if plugin.get("mcp_dispatcher") == null:
		show_state(plugin, HFMcpListenerType.State.FAILED, "The bridge is not set up")
		return
	var listener = plugin.get("mcp_listener")
	if listener == null:
		listener = HFMcpListenerType.new()
		listener.name = LISTENER_NODE_NAME
		listener.dispatcher = plugin.get("mcp_dispatcher")
		# Test seams: the real plugin has neither field, and get() gives null.
		listener.allow_outside_editor = plugin.get("mcp_allow_outside_editor") == true
		var path = plugin.get("mcp_discovery_path")
		if path is String and path != "":
			listener.discovery_path = path
		listener.state_changed.connect(Callable(plugin, "_on_mcp_state_changed"))
		listener.command_finished.connect(Callable(plugin, "_on_mcp_command_finished"))
		plugin.add_child(listener)
		plugin.set("mcp_listener", listener)
	var err: int = listener.start()
	if err == ERR_UNAVAILABLE:
		_stop(plugin)
		show_state(plugin, HFMcpListenerType.State.FAILED, "The bridge only runs in the editor")
	elif err != OK:
		# The listener said why through state_changed; take it down so the next
		# tick starts clean.
		var reason: String = _panel(plugin).status_label.text if _panel(plugin) else ""
		_stop(plugin)
		show_state(plugin, HFMcpListenerType.State.FAILED, reason)


## The listener's state, on the panel.
static func show_state(plugin: Object, state: int, detail: String) -> void:
	var panel = _panel(plugin)
	if panel:
		panel.set_state(state, detail)


## The agent's last command, on the panel.
## What it changed is outlined in the viewport for a moment (#1653).
static func show_last(plugin: Object, method: String, ok: bool, code: String, ms: int) -> void:
	var changed: Dictionary = {}
	var dispatcher = plugin.get("mcp_dispatcher")
	if ok and dispatcher and not (dispatcher.last_changed as Dictionary).is_empty():
		changed = dispatcher.last_changed
		dispatcher.last_changed = {}
		plugin.set("_mcp_last_changed", changed)
		show_changes(plugin, changed)
	var panel = _panel(plugin)
	if panel:
		panel.show_last(method, ok, code, ms, int(changed.get("removed", 0)))


## The nodes a change named, those still in the level.
static func changed_nodes(plugin: Object, changed: Dictionary) -> Array:
	var root = plugin.get("active_root")
	if root == null and plugin.has_method("_get_level_root"):
		root = plugin.call("_get_level_root")
	var nodes: Array = []
	if root == null or not is_instance_valid(root):
		return nodes
	for brush_id in changed.get("brush_ids", []):
		var brush = root.find_brush_by_id(str(brush_id))
		if brush:
			nodes.append(brush)
	for entity in changed.get("entities", []):
		if entity is Node and is_instance_valid(entity):
			nodes.append(entity)
	return nodes


## Outline what a change changed, unless Show agent changes is off.
static func show_changes(plugin: Object, changed: Dictionary) -> void:
	var prefs = plugin.get("_user_prefs")
	if prefs and not bool(prefs.get_pref("show_agent_changes", true)):
		return
	var nodes := changed_nodes(plugin, changed)
	if nodes.is_empty() or not ("_agent_highlight" in plugin):
		return
	if plugin.get("_agent_highlight") == null:
		plugin.set("_agent_highlight", HFAgentHighlightType.new())
	var root = (nodes[0] as Node).get_parent()
	while root and not root.has_method("find_brush_by_id"):
		root = root.get_parent()
	var redraw := (
		Callable(plugin, "update_overlays") if plugin.has_method("update_overlays") else Callable()
	)
	plugin.get("_agent_highlight").show(root, nodes, redraw)
	if redraw.is_valid():
		redraw.call()


## The Last line's click: select what the last change changed. The camera stays
## where it is; Focus Selection frames it.
static func select_last_changed(plugin: Object, changed: Dictionary) -> void:
	var nodes := changed_nodes(plugin, changed)
	if nodes.is_empty():
		return
	var selection = plugin.get_editor_interface().get_selection()
	if selection == null:
		return
	selection.clear()
	for node in nodes:
		selection.add_node(node)


static func _stop(plugin: Object) -> void:
	var listener = plugin.get("mcp_listener")
	if listener == null or not is_instance_valid(listener):
		plugin.set("mcp_listener", null)
		return
	listener.stop()
	var changed := Callable(plugin, "_on_mcp_state_changed")
	if listener.state_changed.is_connected(changed):
		listener.state_changed.disconnect(changed)
	var finished := Callable(plugin, "_on_mcp_command_finished")
	if listener.command_finished.is_connected(finished):
		listener.command_finished.disconnect(finished)
	if listener.get_parent():
		listener.get_parent().remove_child(listener)
	listener.queue_free()
	plugin.set("mcp_listener", null)
	show_state(plugin, HFMcpListenerType.State.OFF, "Off")


static func _panel(plugin: Object) -> Object:
	var dock = plugin.get("dock")
	if dock == null or not is_instance_valid(dock):
		return null
	var panel = dock.get("mcp_panel")
	return panel if panel != null and is_instance_valid(panel) else null
