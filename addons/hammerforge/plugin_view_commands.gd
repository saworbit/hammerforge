@tool
class_name HFPluginViewCommands
extends RefCounted
## What is shown in a busy level (#1697): Hide Selection and Show Hidden, Isolate
## Selection and Isolate Visgroups with End Isolate, and Previous Visibility.
##
## The state is `HFVisgroupSystem`'s: a set of brushes and entities hidden apart
## from any visgroup, never saved with the level, and a history of the last
## visibilities kept apart from the undo history, so stepping back through it
## never undoes an edit.


## Hide the selected brushes and entities, and take them out of the selection.
static func hide_selection(plugin: Object, root: Node) -> void:
	var system = _system(root)
	var nodes: Array = plugin._current_selection_nodes()
	if system == null or nodes.is_empty():
		return
	var hidden: int = system.hide_from_view(nodes)
	_deselect(plugin, nodes)
	_said(plugin, "Hid %d. Show Hidden (Shift+Alt+H) brings them back" % hidden)


static func show_hidden(plugin: Object, root: Node) -> void:
	var system = _system(root)
	if system == null:
		return
	var shown: int = system.show_hidden()
	_said(plugin, "Showed %d hidden" % shown if shown > 0 else "Nothing was hidden")


## Show only the selection, whatever visgroups it is in.
static func isolate_selection(plugin: Object, root: Node) -> void:
	var system = _system(root)
	if system == null or not system.isolate_nodes(plugin._current_selection_nodes()):
		return
	_said(plugin, "Isolated the selection. End Isolate puts the rest back")


## Show only the visgroups the selection is in, and hide everything else.
static func isolate_visgroups(plugin: Object, root: Node) -> void:
	var system = _system(root)
	if system == null:
		return
	var names: Array = []
	for node in plugin._current_selection_nodes():
		for vg_name in system.get_visgroups_of(node):
			if not names.has(vg_name):
				names.append(vg_name)
	if not system.isolate_visgroups(names):
		_said(plugin, "Isolate Visgroups: the selection is in no visgroup", 1)
		return
	_said(plugin, "Isolated %s. End Isolate puts the rest back" % ", ".join(names))


static func end_isolate(plugin: Object, root: Node) -> void:
	var system = _system(root)
	if system == null:
		return
	if not system.end_isolate():
		_said(plugin, "No isolate to end", 1)
		return
	_said(plugin, "Ended the isolate")


static func previous_visibility(plugin: Object, root: Node) -> void:
	var system = _system(root)
	if system == null:
		return
	if not system.previous_view():
		_said(plugin, "No earlier visibility to go back to", 1)
		return
	_said(plugin, "Back to the visibility before (%d more)" % system.view_history_size())


static func _system(root: Node):
	return root.get("visgroup_system") if root else null


## Hidden nodes stay out of the selection, so nothing acts on what is not shown.
static func _deselect(plugin: Object, nodes: Array) -> void:
	var selection = plugin.get_editor_interface().get_selection()
	if selection:
		for node in nodes:
			if node is Node and is_instance_valid(node):
				selection.remove_node(node)
	if "hf_selection" in plugin:
		for node in nodes:
			plugin.hf_selection.erase(node)


static func _said(plugin: Object, message: String, severity: int = 0) -> void:
	var dock = plugin.get("dock")
	if dock == null:
		return
	if dock.has_method("refresh_visgroup_ui"):
		dock.refresh_visgroup_ui()
	dock.show_toast(message, severity)
