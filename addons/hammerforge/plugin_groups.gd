@tool
extends RefCounted
## Groups you can name, nest, list and open (#1723).
##
## A group was a name the editor made up and a click that picked every member.
## Group Selection now asks for a name, a group can hold groups, and opening one
## lets its members be picked and changed one at a time while the rest of the
## level is faded. The model is `HFVisgroupSystem`'s: `group_parents` for the
## nesting and `open_group` for the group open now. These are the commands.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFUndoHelper = preload("undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFGroupNameDialog = preload("ui/hf_group_name_dialog.gd")


## Group Selection: ask for a name, then group the selection as one step. Whole
## groups go in as groups, inside the open group when one is open. True when it
## asked.
static func group_selected(plugin: Object, root: Node) -> bool:
	var system = _system(root)
	if system == null:
		return false
	var nodes: Array = plugin._hammerforge_selection_nodes(root)
	var units: Dictionary = system.units_of(nodes)
	if (units["groups"] as Array).size() + (units["nodes"] as Array).size() < 2:
		_say(plugin, "Select two or more things to group: a group counts as one", 1)
		return false
	var dialog := HFGroupNameDialog.make(
		"Group Selection",
		system.default_group_name(nodes),
		func(group_name: String): _group_as(plugin, root, nodes, group_name)
	)
	_show(plugin, dialog)
	return true


static func _group_as(plugin: Object, root: Node, nodes: Array, group_name: String) -> void:
	var system = _system(root)
	if system == null:
		return
	var live: Array = nodes.filter(func(node): return is_instance_valid(node))
	var unique: String = system.unique_group_name(group_name)
	var before: Dictionary = root.capture_state()
	system.group_units(unique, live)
	_commit(plugin, root, "Group Selection", before)
	_say(plugin, "Grouped as %s" % unique, 0)


## Ungroup: take the selected groups apart one level. With a group open, a node
## of its own leaves it. False when nothing selected is in a group.
static func ungroup_selected(plugin: Object, root: Node) -> bool:
	var system = _system(root)
	if system == null:
		return false
	var nodes: Array = plugin._hammerforge_selection_nodes(root)
	var units: Dictionary = system.units_of(nodes)
	var in_open := false
	for node in units["nodes"]:
		if str(system.open_group) != "" and system.get_group_of(node) == system.open_group:
			in_open = true
	if (units["groups"] as Array).is_empty() and not in_open:
		return false
	var before: Dictionary = root.capture_state()
	system.ungroup_units(nodes)
	_commit(plugin, root, "Ungroup Selection", before)
	return true


## The group the selection is, or "": one group and nothing else, as a click on
## one of its members selects it.
static func selected_group(plugin: Object, root: Node) -> String:
	var system = _system(root)
	if system == null:
		return ""
	var units: Dictionary = system.units_of(plugin._hammerforge_selection_nodes(root))
	if (units["groups"] as Array).size() == 1 and (units["nodes"] as Array).is_empty():
		return str(units["groups"][0])
	return ""


## Open the selected group: its members pick one at a time, and the rest of the
## level is faded until Escape or a click outside closes it.
static func open_selected_group(plugin: Object, root: Node) -> bool:
	var system = _system(root)
	var group_name := selected_group(plugin, root)
	if system == null or group_name == "":
		_say(plugin, "Select a group to open", 1)
		return false
	system.set_open_group(group_name)
	_refresh(plugin)
	_say(plugin, "Open: %s. Its members pick one at a time. Escape closes it" % group_name, 0)
	return true


## A double click at `position`: the group of the brush under it opens, one
## level in, and what the brush is in there is selected. False when it is in no
## group the click could open, and the click is an ordinary one.
static func open_at(plugin: Object, root: Node, camera: Camera3D, position: Vector2) -> bool:
	var system = _system(root)
	if system == null or camera == null or not root.has_method("pick_brush"):
		return false
	var picked = root.pick_brush(camera, position, false)
	if not (picked is Node) or not is_instance_valid(picked):
		return false
	var unit: String = system.selection_unit_of(picked)
	if unit == "":
		return false
	system.set_open_group(unit)
	var inner: String = system.selection_unit_of(picked)
	_select(plugin, system.group_members_deep(inner) if inner != "" else [picked])
	_refresh(plugin)
	_say(plugin, "Open: %s. Its members pick one at a time. Escape closes it" % unit, 0)
	return true


## Close the open group one level, and select the group just closed, as a click
## on one of its members would now.
static func close_group(plugin: Object, root: Node) -> bool:
	var system = _system(root)
	if system == null or str(system.open_group) == "":
		return false
	var closed := str(system.open_group)
	var members: Array = system.group_members_deep(closed)
	system.set_open_group(system.parent_of_group(closed))
	if not members.is_empty():
		var unit: String = system.selection_unit_of(members[0])
		var picked: Array = system.group_members_deep(unit) if unit != "" else members
		_select(plugin, picked)
	_refresh(plugin)
	_say(plugin, "Closed %s" % closed, 0)
	return true


## The group a command adds to or takes from when none is named: the one
## highlighted in the dock's Groups list, or else the open one. A pick outside an
## open group closes it, so adding to one goes through the list.
static func target_group(plugin: Object, root: Node) -> String:
	var dock = plugin.get("dock")
	if dock and is_instance_valid(dock) and dock.has_method("highlighted_group"):
		var listed := str(dock.highlighted_group())
		if listed != "":
			return listed
	var system = _system(root)
	return str(system.open_group) if system else ""


## Add to Group: the selection into `group_name`, or the target group when none
## is named.
static func add_selection_to_group(plugin: Object, root: Node, group_name := "") -> bool:
	var system = _system(root)
	if system == null:
		return false
	var target := group_name if group_name != "" else target_group(plugin, root)
	if target == "":
		_say(plugin, "Pick a group in the Groups list, or open one", 1)
		return false
	var nodes: Array = plugin._hammerforge_selection_nodes(root)
	if nodes.is_empty():
		return false
	var before: Dictionary = root.capture_state()
	system.add_units_to_group(nodes, target)
	_commit(plugin, root, "Add to Group", before)
	return true


## Remove from Group: what of the selection is in `group_name`, or the target
## group, out to the group around it.
static func remove_selection_from_group(plugin: Object, root: Node, group_name := "") -> bool:
	var system = _system(root)
	if system == null:
		return false
	var target := group_name if group_name != "" else target_group(plugin, root)
	if target == "":
		_say(plugin, "Pick a group in the Groups list, or open one", 1)
		return false
	var nodes: Array = plugin._hammerforge_selection_nodes(root)
	if nodes.is_empty():
		return false
	var before: Dictionary = root.capture_state()
	system.remove_units_from_group(nodes, target)
	_commit(plugin, root, "Remove from Group", before)
	return true


## Rename Group: ask for a new name for the selected group, or the open one.
static func rename_selected_group(plugin: Object, root: Node) -> bool:
	var system = _system(root)
	if system == null:
		return false
	var group_name := selected_group(plugin, root)
	if group_name == "":
		group_name = str(system.open_group)
	if group_name == "":
		_say(plugin, "Select a group to rename", 1)
		return false
	var dialog := HFGroupNameDialog.make(
		"Rename Group",
		group_name,
		func(new_name: String): rename(plugin, root, group_name, new_name)
	)
	_show(plugin, dialog)
	return true


## Rename `old_name` as one step, saying why when the name is taken.
static func rename(plugin: Object, root: Node, old_name: String, new_name: String) -> bool:
	var system = _system(root)
	if system == null or new_name.strip_edges() == old_name:
		return false
	if system.groups.has(new_name.strip_edges()):
		_say(plugin, 'A group is already called "%s"' % new_name.strip_edges(), 1)
		return false
	var before: Dictionary = root.capture_state()
	if not system.rename_group(old_name, new_name):
		return false
	_commit(plugin, root, "Rename Group", before)
	return true


static func _commit(plugin: Object, root: Node, action: String, before: Dictionary) -> void:
	HFUndoHelper.commit_completed(
		plugin._get_undo_redo(), root, action, before, Callable(plugin, "_record_history")
	)
	_refresh(plugin)


static func _system(root: Node) -> Object:
	return root.get("visgroup_system") if root and is_instance_valid(root) else null


static func _show(plugin: Object, dialog: ConfirmationDialog) -> void:
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.confirmed.connect(func(): dialog.queue_free(), CONNECT_DEFERRED)
	plugin._add_confirmable_dialog(dialog)
	if dialog.is_inside_tree():
		dialog.popup_centered()


static func _select(plugin: Object, nodes: Array) -> void:
	plugin.hf_selection = nodes.duplicate()
	var selection = plugin.get_editor_interface().get_selection()
	if selection:
		plugin._apply_hf_selection(selection)


static func _refresh(plugin: Object) -> void:
	var dock = plugin.get("dock")
	if dock and is_instance_valid(dock) and dock.has_method("refresh_visgroup_ui"):
		dock.refresh_visgroup_ui()
	if plugin.has_method("_update_hud_context"):
		plugin._update_hud_context()


static func _say(plugin: Object, message: String, level: int) -> void:
	var dock = plugin.get("dock")
	if dock and is_instance_valid(dock) and dock.has_method("show_toast"):
		dock.show_toast(message, level)
