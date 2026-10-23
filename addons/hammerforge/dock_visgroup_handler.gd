@tool
class_name HFDockVisgroupHandler
extends RefCounted
## Visgroup, grouping, and cordon controls extracted from dock.gd.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFCollapsibleSection = preload("ui/collapsible_section.gd")
const HFUIFactory = preload("ui/hf_ui_factory.gd")
const HFBakeSplit = preload("hf_bake_split.gd")
@warning_ignore_restore("shadowed_global_identifier")

## How far a cordon bound may sit from the origin.
##
## The old limit was 9999, which is narrower than the coordinates a level holds:
## a structure builder takes a width or a radius up to 4096 for one piece of
## geometry, and Quake-family maps run well past 4096 per axis. Set from
## Selection on a room outside it clamped the cordon to a zero-width slab at the
## limit and, because the assignment fires `value_changed`, wrote that back onto
## the level - so the next bake produced an empty level and the control that
## caused it read 9999 as though that were the number the mapper chose.
const CORDON_LIMIT := 131072.0


static func setup_visgroup_ui(dock: Object) -> void:
	if dock == null or not dock.manage_tab:
		return
	var manage_vbox = dock.manage_tab.get_node_or_null("ManageMargin/ManageVBox")
	if not manage_vbox:
		return
	var section = HFCollapsibleSection.create("Visgroups & Groups", false)
	manage_vbox.add_child(section)
	manage_vbox.move_child(section, mini(2, manage_vbox.get_child_count() - 1))
	dock._register_section(section, "Visgroups & Groups")
	var content = section.get_content()

	dock.visgroup_list = ItemList.new()
	dock.visgroup_list.custom_minimum_size.y = 80
	dock.visgroup_list.select_mode = ItemList.SELECT_SINGLE
	dock.visgroup_list.allow_reselect = true
	content.add_child(dock.visgroup_list)
	dock.visgroup_list.item_clicked.connect(dock._on_visgroup_item_clicked)

	var name_row = HBoxContainer.new()
	dock.visgroup_name_input = LineEdit.new()
	dock.visgroup_name_input.placeholder_text = "Visgroup name"
	dock.visgroup_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(dock.visgroup_name_input)
	dock.visgroup_add_btn = Button.new()
	dock.visgroup_add_btn.text = "New"
	dock.visgroup_add_btn.tooltip_text = "Create a new visgroup"
	dock.visgroup_add_btn.pressed.connect(dock._on_visgroup_add)
	name_row.add_child(dock.visgroup_add_btn)
	content.add_child(name_row)

	var visgroup_buttons = HFUIFactory.make_wrap_row()
	dock.visgroup_add_sel_btn = Button.new()
	dock.visgroup_add_sel_btn.text = "Add Sel"
	dock.visgroup_add_sel_btn.tooltip_text = ("Add selected brushes/entities to the highlighted visgroup")
	dock.visgroup_add_sel_btn.pressed.connect(dock._on_visgroup_add_selection)
	visgroup_buttons.add_child(dock.visgroup_add_sel_btn)
	dock.visgroup_rem_sel_btn = Button.new()
	dock.visgroup_rem_sel_btn.text = "Rem Sel"
	dock.visgroup_rem_sel_btn.tooltip_text = ("Remove selected brushes/entities from the highlighted visgroup")
	dock.visgroup_rem_sel_btn.pressed.connect(dock._on_visgroup_remove_selection)
	visgroup_buttons.add_child(dock.visgroup_rem_sel_btn)
	dock.visgroup_rename_btn = Button.new()
	dock.visgroup_rename_btn.text = "Rename"
	dock.visgroup_rename_btn.tooltip_text = "Rename the highlighted visgroup"
	dock.visgroup_rename_btn.pressed.connect(dock._on_visgroup_rename)
	visgroup_buttons.add_child(dock.visgroup_rename_btn)
	dock.visgroup_delete_btn = Button.new()
	dock.visgroup_delete_btn.text = "Delete"
	dock.visgroup_delete_btn.tooltip_text = "Delete the highlighted visgroup"
	dock.visgroup_delete_btn.pressed.connect(dock._on_visgroup_delete)
	visgroup_buttons.add_child(dock.visgroup_delete_btn)
	_fill_lines(visgroup_buttons)
	content.add_child(visgroup_buttons)

	# How the highlighted visgroup's brushes cast shadows when they do not say
	# themselves (#1444).
	dock.visgroup_cast_shadow_opt = HFUIFactory.make_cast_shadow_option(true)
	dock.visgroup_cast_shadow_opt.tooltip_text = (
		"How the highlighted visgroup's brushes cast shadows. A brush's own Cast Shadows "
		+ "beats it; between two visgroups, the one higher in this list wins"
	)
	dock.visgroup_cast_shadow_opt.item_selected.connect(dock._on_visgroup_cast_shadow_selected)
	content.add_child(HFUIFactory.make_label_row("Cast Shadows:", dock.visgroup_cast_shadow_opt))

	# Where new work goes, and geometry kept in the editor only (#1732).
	var visgroup_flags = HFUIFactory.make_wrap_row()
	dock.visgroup_current_check = CheckBox.new()
	dock.visgroup_current_check.text = "Current"
	dock.visgroup_current_check.tooltip_text = (
		"New brushes, entities, structures and placed or pasted prefabs join the "
		+ "highlighted visgroup. Untick for none"
	)
	dock.visgroup_current_check.toggled.connect(dock._on_visgroup_current_toggled)
	visgroup_flags.add_child(dock.visgroup_current_check)
	dock.visgroup_bake_check = CheckBox.new()
	dock.visgroup_bake_check.text = "Leave out of bake"
	dock.visgroup_bake_check.tooltip_text = (
		"The highlighted visgroup stays visible and editable, and no bake or export "
		+ "takes it: guide brushes, a scale figure, a reference copy"
	)
	dock.visgroup_bake_check.toggled.connect(dock._on_visgroup_bake_toggled)
	visgroup_flags.add_child(dock.visgroup_bake_check)
	_fill_lines(visgroup_flags)
	content.add_child(visgroup_flags)
	_setup_view_controls(dock, content)

	content.add_child(HSeparator.new())
	var group_buttons = HFUIFactory.make_wrap_row()
	dock.group_sel_btn = Button.new()
	dock.group_sel_btn.text = "Group Sel (Ctrl+G)"
	dock.group_sel_btn.tooltip_text = "Group the current selection"
	dock.group_sel_btn.pressed.connect(dock._on_group_selection)
	group_buttons.add_child(dock.group_sel_btn)
	dock.ungroup_btn = Button.new()
	dock.ungroup_btn.text = "Ungroup (Ctrl+U)"
	dock.ungroup_btn.tooltip_text = "Remove selected brushes/entities from their group"
	dock.ungroup_btn.pressed.connect(dock._on_ungroup_selection)
	group_buttons.add_child(dock.ungroup_btn)
	_fill_lines(group_buttons)
	content.add_child(group_buttons)


## What is shown, apart from each visgroup's own eye (#1697): isolate, hide the
## selection, step back, and named views kept with the level.
static func _setup_view_controls(dock: Object, content: Control) -> void:
	content.add_child(HSeparator.new())
	var view_buttons = HFUIFactory.make_wrap_row()
	for spec in [
		[
			"Isolate",
			"Show only the highlighted visgroup, or the visgroups of the selection, and hide the rest",
			"_on_view_isolate"
		],
		[
			"Isolate Sel",
			"Show only the selection and hide everything else",
			"_on_view_isolate_selection"
		],
		[
			"End Isolate",
			"Put back exactly what was shown before the isolate",
			"_on_view_end_isolate"
		],
		[
			"Hide Sel",
			"Hide the selection without a visgroup (Alt+H). Not saved with the level",
			"_on_view_hide_selection"
		],
		[
			"Show Hidden",
			"Show what Hide Sel and an isolate hid (Shift+Alt+H)",
			"_on_view_show_hidden"
		],
		[
			"Previous",
			"Go back to the visibility before the last show, hide or isolate, up to 20 times. Undoes no edit",
			"_on_view_previous"
		],
	]:
		var button := Button.new()
		button.text = spec[0]
		button.tooltip_text = spec[1]
		button.pressed.connect(Callable(dock, spec[2]))
		view_buttons.add_child(button)
	_fill_lines(view_buttons)
	content.add_child(view_buttons)
	# Shown while anything is hidden apart from the visgroups, so nobody loses
	# brushes to a hide they forgot.
	dock.view_hidden_label = Label.new()
	dock.view_hidden_label.name = "ViewHidden"
	dock.view_hidden_label.visible = false
	content.add_child(dock.view_hidden_label)
	var views_row := HBoxContainer.new()
	dock.view_saved_opt = OptionButton.new()
	dock.view_saved_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.view_saved_opt.tooltip_text = "Visibility states saved with the level"
	views_row.add_child(dock.view_saved_opt)
	for spec in [
		["Show", "Show the visgroups the picked view showed", "_on_view_restore"],
		["Delete", "Forget the picked view", "_on_view_delete"],
	]:
		var button := Button.new()
		button.text = spec[0]
		button.tooltip_text = spec[1]
		button.pressed.connect(Callable(dock, spec[2]))
		views_row.add_child(button)
	content.add_child(HFUIFactory.make_label_row("Views:", views_row))
	var save_row := HBoxContainer.new()
	dock.view_name_input = LineEdit.new()
	dock.view_name_input.placeholder_text = "View name"
	dock.view_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(dock.view_name_input)
	var save := Button.new()
	save.text = "Save View"
	save.tooltip_text = "Keep which visgroups are shown now, under this name, with the level"
	save.pressed.connect(Callable(dock, "_on_view_save"))
	save_row.add_child(save)
	content.add_child(save_row)


## Isolate the highlighted visgroup, or with none highlighted the selection's.
static func on_view_isolate(dock: Object) -> void:
	var system = _visgroups(dock)
	if system == null:
		return
	var names: Array = []
	var highlighted := get_selected_visgroup_name(dock)
	if highlighted != "":
		names.append(highlighted)
	else:
		for node in dock._selection_nodes:
			for vg_name in system.get_visgroups_of(node):
				if not names.has(vg_name):
					names.append(vg_name)
	if not system.isolate_visgroups(names):
		dock.show_toast("Isolate: highlight a visgroup, or select something in one", 1)
		return
	refresh_visgroup_ui(dock)
	dock._set_status("Isolated %s" % ", ".join(names))


static func on_view_isolate_selection(dock: Object) -> void:
	var system = _visgroups(dock)
	if system == null:
		return
	if not system.isolate_nodes(dock._selection_nodes):
		dock.show_toast("Isolate Sel: select what to keep shown", 1)
		return
	refresh_visgroup_ui(dock)


static func on_view_end_isolate(dock: Object) -> void:
	var system = _visgroups(dock)
	if system and system.end_isolate():
		refresh_visgroup_ui(dock)


static func on_view_hide_selection(dock: Object) -> void:
	var system = _visgroups(dock)
	if system == null or dock._selection_nodes.is_empty():
		return
	var nodes: Array = dock._selection_nodes.duplicate()
	system.hide_from_view(nodes)
	var selection = EditorInterface.get_selection() if dock.editor_interface else null
	if selection:
		for node in nodes:
			if is_instance_valid(node):
				selection.remove_node(node)
	refresh_visgroup_ui(dock)


static func on_view_show_hidden(dock: Object) -> void:
	var system = _visgroups(dock)
	if system:
		system.show_hidden()
		refresh_visgroup_ui(dock)


static func on_view_previous(dock: Object) -> void:
	var system = _visgroups(dock)
	if system == null:
		return
	if not system.previous_view():
		dock.show_toast("No earlier visibility to go back to", 1)
	refresh_visgroup_ui(dock)


## Saving a view changes the level, so it is an undo step.
static func on_view_save(dock: Object) -> void:
	if _visgroups(dock) == null or dock.view_name_input == null:
		return
	var view_name: String = dock.view_name_input.text.strip_edges()
	if view_name == "":
		dock.show_toast("Save View: name the view first", 1)
		return
	dock._commit_state_action("Save View", "save_visibility_view", [view_name])
	dock.view_name_input.text = ""
	refresh_visgroup_ui(dock)


static func on_view_restore(dock: Object) -> void:
	var system = _visgroups(dock)
	var view_name := _picked_view(dock)
	if system and view_name != "" and system.restore_saved_view(view_name):
		refresh_visgroup_ui(dock)


static func on_view_delete(dock: Object) -> void:
	var view_name := _picked_view(dock)
	if _visgroups(dock) == null or view_name == "":
		return
	dock._commit_state_action("Delete View", "remove_visibility_view", [view_name])
	refresh_visgroup_ui(dock)


static func _picked_view(dock: Object) -> String:
	var opt = dock.get("view_saved_opt")
	if opt == null or opt.selected < 0:
		return ""
	return opt.get_item_text(opt.selected)


static func _visgroups(dock: Object):
	if dock == null or not dock.level_root:
		return null
	return dock.level_root.get("visgroup_system")


## The Hidden chip and the saved views list.
static func _sync_view_controls(dock: Object, system) -> void:
	var label = dock.get("view_hidden_label")
	if label:
		var hidden: int = system.view_hidden_nodes().size() if system else 0
		var isolating: bool = system != null and system.is_isolating()
		label.visible = hidden > 0 or isolating
		label.text = (
			("Isolated, %d hidden" % hidden)
			if isolating
			else ("Hidden: %d, not saved with the level" % hidden)
		)
	var opt = dock.get("view_saved_opt")
	if opt:
		var picked := _picked_view(dock)
		opt.clear()
		if system:
			for view_name in system.get_saved_view_names():
				opt.add_item(view_name)
				if view_name == picked:
					opt.select(opt.item_count - 1)


## Let the buttons of a wrapping row share each line evenly.
static func _fill_lines(row: Container) -> void:
	for button in row.get_children():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func refresh_visgroup_ui(dock: Object) -> void:
	if dock == null or not dock.visgroup_list:
		return
	dock.visgroup_list.clear()
	if not dock.level_root or not dock.level_root.get("visgroup_system"):
		return
	var system = dock.level_root.get("visgroup_system")
	var current: String = system.get_current_visgroup()
	for visgroup_name in system.get_visgroup_names():
		var prefix = "[V] " if system.is_visgroup_visible(visgroup_name) else "[H] "
		var label: String = prefix + visgroup_name
		var notes := PackedStringArray()
		if visgroup_name == current:
			label += "  (current)"
			notes.append("New work joins it")
		if not system.visgroup_bakes(visgroup_name):
			label += "  (not baked)"
			notes.append("Left out of every bake and export")
		var index: int = dock.visgroup_list.add_item(label)
		dock.visgroup_list.set_item_metadata(index, visgroup_name)
		if not system.visgroup_bakes(visgroup_name):
			dock.visgroup_list.set_item_custom_fg_color(index, HFThemeUtils.muted_text())
		var cast: int = system.get_visgroup_cast_shadow(visgroup_name)
		if cast != HFBakeSplit.LEVEL_DEFAULT:
			notes.append("Cast Shadows: %s" % HFBakeSplit.cast_shadow_name(cast))
		if not notes.is_empty():
			dock.visgroup_list.set_item_tooltip(index, ". ".join(notes))
	sync_visgroup_cast_shadow(dock)
	_sync_view_controls(dock, system)


## Show the highlighted visgroup's Cast Shadows, whether it is current and
## whether it is baked, and nothing with none highlighted.
static func sync_visgroup_cast_shadow(dock: Object) -> void:
	if dock == null or not dock.visgroup_cast_shadow_opt:
		return
	var visgroup_name := get_selected_visgroup_name(dock)
	var system = dock.level_root.get("visgroup_system") if dock.level_root else null
	for check in [dock.get("visgroup_current_check"), dock.get("visgroup_bake_check")]:
		if check:
			check.disabled = visgroup_name == "" or system == null
	if visgroup_name == "" or system == null:
		dock.visgroup_cast_shadow_opt.select(-1)
		_set_check_quietly(dock.get("visgroup_current_check"), false)
		_set_check_quietly(dock.get("visgroup_bake_check"), false)
		return
	HFUIFactory.select_cast_shadow(
		dock.visgroup_cast_shadow_opt, system.get_visgroup_cast_shadow(visgroup_name)
	)
	_set_check_quietly(
		dock.get("visgroup_current_check"), system.get_current_visgroup() == visgroup_name
	)
	_set_check_quietly(dock.get("visgroup_bake_check"), not system.visgroup_bakes(visgroup_name))


static func _set_check_quietly(check: Variant, pressed: bool) -> void:
	if check is CheckBox:
		(check as CheckBox).set_pressed_no_signal(pressed)


## Make the highlighted visgroup the one new work joins, or none (#1732). A
## setting of the level, not an edit, so it is not an undo step.
static func on_visgroup_current_toggled(dock: Object, pressed: bool) -> void:
	if dock == null or not dock.level_root:
		return
	var visgroup_name := require_visgroup_name(dock, "Current visgroup")
	if visgroup_name == "":
		sync_visgroup_cast_shadow(dock)
		return
	var row := get_selected_visgroup_index(dock)
	dock.level_root.current_visgroup = visgroup_name if pressed else ""
	refresh_visgroup_ui(dock)
	reselect_visgroup_row(dock, row)


## Leave the highlighted visgroup out of the bake, or put it back, as one undo
## step (#1732).
static func on_visgroup_bake_toggled(dock: Object, left_out: bool) -> void:
	if dock == null or not dock.level_root:
		return
	var visgroup_name := require_visgroup_name(dock, "Leave out of bake")
	if visgroup_name == "":
		sync_visgroup_cast_shadow(dock)
		return
	var row := get_selected_visgroup_index(dock)
	dock._commit_state_action_if_changed(
		"Leave Visgroup Out of Bake" if left_out else "Bake Visgroup",
		"set_visgroup_bakes",
		[visgroup_name, not left_out]
	)
	refresh_visgroup_ui(dock)
	reselect_visgroup_row(dock, row)


static func on_visgroup_cast_shadow_selected(dock: Object, index: int) -> void:
	if dock == null or not dock.level_root:
		return
	var visgroup_name := require_visgroup_name(dock, "Visgroup Cast Shadows")
	if visgroup_name == "":
		sync_visgroup_cast_shadow(dock)
		return
	var row := get_selected_visgroup_index(dock)
	dock._commit_state_action_if_changed(
		"Visgroup Cast Shadows",
		"set_visgroup_cast_shadow",
		[visgroup_name, HFUIFactory.cast_shadow_at(dock.visgroup_cast_shadow_opt, index)]
	)
	refresh_visgroup_ui(dock)
	reselect_visgroup_row(dock, row)


## The highlighted row, or -1. `refresh_visgroup_ui()` clears the list and
## rebuilds it, so a command that refreshes has to put the highlight back or the
## next one reads no visgroup and does nothing.
static func get_selected_visgroup_index(dock: Object) -> int:
	if dock == null or not dock.visgroup_list:
		return -1
	var selected = dock.visgroup_list.get_selected_items()
	return -1 if selected.is_empty() else int(selected[0])


static func reselect_visgroup_row(dock: Object, index: int) -> void:
	if dock == null or not dock.visgroup_list or index < 0:
		return
	if index < dock.visgroup_list.item_count:
		dock.visgroup_list.select(index)
	sync_visgroup_cast_shadow(dock)


## The name on the highlighted row, or "". Commands that need one report the
## miss rather than returning quietly, which used to read as a dead button.
static func require_visgroup_name(dock: Object, action: String) -> String:
	var visgroup_name := get_selected_visgroup_name(dock)
	if visgroup_name == "" and dock:
		dock._set_status("%s: select a visgroup first" % action, true)
	return visgroup_name


static func get_selected_visgroup_name(dock: Object) -> String:
	if dock == null or not dock.visgroup_list:
		return ""
	var selected = dock.visgroup_list.get_selected_items()
	if selected.is_empty():
		return ""
	# The row's text carries markers now, "(current)" and "(not baked)", so the
	# name is read from its metadata.
	var named: Variant = dock.visgroup_list.get_item_metadata(selected[0])
	if named is String and named != "":
		return named
	var text = dock.visgroup_list.get_item_text(selected[0])
	if text.begins_with("[V] ") or text.begins_with("[H] "):
		return text.substr(4)
	return text


static func on_visgroup_add(dock: Object) -> void:
	if dock == null or not dock.visgroup_name_input:
		return
	var visgroup_name = dock.visgroup_name_input.text.strip_edges()
	if visgroup_name == "" or not dock.level_root:
		return
	dock._commit_state_action("New Visgroup", "create_visgroup", [visgroup_name])
	dock.visgroup_name_input.text = ""
	refresh_visgroup_ui(dock)


static func on_visgroup_item_clicked(
	dock: Object, index: int, _at_position: Vector2, mouse_button_index: int
) -> void:
	if dock == null or mouse_button_index != MOUSE_BUTTON_LEFT or not dock.visgroup_list:
		return
	var text = dock.visgroup_list.get_item_text(index)
	var visgroup_name = ""
	var was_visible = true
	if text.begins_with("[V] "):
		visgroup_name = text.substr(4)
	elif text.begins_with("[H] "):
		visgroup_name = text.substr(4)
		was_visible = false
	else:
		return
	if visgroup_name == "" or not dock.level_root:
		return
	dock.level_root.set_visgroup_visible(visgroup_name, not was_visible)
	refresh_visgroup_ui(dock)
	reselect_visgroup_row(dock, index)


static func on_visgroup_add_selection(dock: Object) -> void:
	if dock == null:
		return
	var visgroup_name = require_visgroup_name(dock, "Add to Visgroup")
	if visgroup_name == "" or not dock.level_root:
		return
	if not dock._guard_selection_action("Add to Visgroup"):
		return
	var row := get_selected_visgroup_index(dock)
	dock._commit_state_action(
		"Add to Visgroup",
		"add_selection_to_visgroup",
		[visgroup_name, dock._selection_nodes.duplicate()],
		true
	)
	refresh_visgroup_ui(dock)
	reselect_visgroup_row(dock, row)


static func on_visgroup_remove_selection(dock: Object) -> void:
	if dock == null:
		return
	var visgroup_name = require_visgroup_name(dock, "Remove from Visgroup")
	if visgroup_name == "" or not dock.level_root:
		return
	if not dock._guard_selection_action("Remove from Visgroup"):
		return
	var row := get_selected_visgroup_index(dock)
	dock._commit_state_action(
		"Remove from Visgroup",
		"remove_selection_from_visgroup",
		[visgroup_name, dock._selection_nodes.duplicate()],
		true
	)
	refresh_visgroup_ui(dock)
	reselect_visgroup_row(dock, row)


static func on_visgroup_delete(dock: Object) -> void:
	if dock == null:
		return
	var visgroup_name = require_visgroup_name(dock, "Delete Visgroup")
	if visgroup_name == "" or not dock.level_root:
		return
	dock._commit_state_action("Delete Visgroup", "remove_visgroup", [visgroup_name])
	refresh_visgroup_ui(dock)


## Rename the highlighted visgroup.
##
## The system has always been able to do this, carefully: it refuses a name that
## is taken rather than merging two visgroups, and it rewrites the membership
## metadata on every node that carried the old name. Nothing outside the suite
## could ask for it (#615), so a mapper who named one `roof` and then wanted
## `roof_upper` had to make a new one, re-add every member and delete the old.
##
## The collision is checked here rather than left to the refusal, because
## `_commit_state_action()` cannot see a return value and would otherwise push an
## undo step for a rename that did not happen.
static func on_visgroup_rename(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	var current_name := require_visgroup_name(dock, "Rename Visgroup")
	if current_name == "":
		return
	var row := get_selected_visgroup_index(dock)
	var dialog := AcceptDialog.new()
	dialog.title = "Rename Visgroup"
	var line_edit := LineEdit.new()
	line_edit.text = current_name
	line_edit.select_all()
	dialog.add_child(line_edit)
	dialog.confirmed.connect(
		func():
			if not is_instance_valid(dock) or not dock.level_root:
				return
			var new_name: String = line_edit.text.strip_edges()
			if new_name == "" or new_name == current_name:
				return
			if Array(dock.level_root.get_visgroup_names()).has(new_name):
				if dock.has_method("show_toast"):
					dock.show_toast('A visgroup is already called "%s"' % new_name, 2)
				return
			dock._commit_state_action(
				"Rename Visgroup", "rename_visgroup", [current_name, new_name]
			)
			refresh_visgroup_ui(dock)
			reselect_visgroup_row(dock, row)
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.confirmed.connect(func(): dialog.queue_free(), CONNECT_DEFERRED)
	dock.add_child(dialog)
	dialog.popup_centered(Vector2i(300, 80))
	line_edit.grab_focus()


static func on_group_selection(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.size() < 2:
		return
	if not dock._guard_selection_action("Group Selection"):
		return
	dock._commit_state_action(
		"Group Selection",
		"group_selection",
		["group_%d" % Time.get_ticks_usec(), dock._selection_nodes.duplicate()],
		true
	)


static func on_ungroup_selection(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		return
	if not dock._guard_selection_action("Ungroup Selection"):
		return
	dock._commit_state_action(
		"Ungroup Selection", "ungroup_nodes", [dock._selection_nodes.duplicate()], true
	)


static func setup_cordon_ui(dock: Object) -> void:
	if dock == null or not dock.manage_tab:
		return
	var manage_vbox = dock.manage_tab.get_node_or_null("ManageMargin/ManageVBox")
	if not manage_vbox:
		return
	var section = HFCollapsibleSection.create("Cordon (Partial Bake)", false)
	manage_vbox.add_child(section)
	manage_vbox.move_child(section, 2)
	dock._register_section(section, "Cordon (Partial Bake)")
	var content = section.get_content()
	dock.cordon_enabled_check = CheckBox.new()
	dock.cordon_enabled_check.text = "Enable Cordon"
	dock.cordon_enabled_check.tooltip_text = "Only bake geometry inside the cordons"
	dock.cordon_enabled_check.toggled.connect(dock._on_cordon_toggled)
	content.add_child(dock.cordon_enabled_check)

	# Which cordon the bounds below edit. The bake takes every brush that touches
	# any of them.
	var region_row = HBoxContainer.new()
	dock.cordon_region_opt = OptionButton.new()
	dock.cordon_region_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.cordon_region_opt.tooltip_text = "The cordon the bounds below edit"
	dock.cordon_region_opt.add_item("Cordon 1")
	dock.cordon_region_opt.item_selected.connect(dock._on_cordon_region_selected)
	region_row.add_child(dock.cordon_region_opt)
	dock.cordon_remove_btn = Button.new()
	dock.cordon_remove_btn.text = "Remove"
	dock.cordon_remove_btn.tooltip_text = "Remove this cordon. The last one cannot go"
	dock.cordon_remove_btn.disabled = true
	dock.cordon_remove_btn.pressed.connect(dock._on_cordon_remove)
	region_row.add_child(dock.cordon_remove_btn)
	content.add_child(region_row)

	# The chosen cordon's own switch and name. One that is off keeps its bounds
	# and is drawn dimmer, so a room can sit out a bake and come back later.
	var detail_row = HBoxContainer.new()
	dock.cordon_active_check = CheckBox.new()
	dock.cordon_active_check.text = "Bake"
	dock.cordon_active_check.button_pressed = true
	dock.cordon_active_check.tooltip_text = "Bake this cordon. Off keeps it for later"
	dock.cordon_active_check.toggled.connect(dock._on_cordon_active_toggled)
	detail_row.add_child(dock.cordon_active_check)
	dock.cordon_name_edit = LineEdit.new()
	dock.cordon_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.cordon_name_edit.placeholder_text = "Cordon 1"
	dock.cordon_name_edit.tooltip_text = "This cordon's name"
	dock.cordon_name_edit.text_submitted.connect(dock._on_cordon_name_submitted)
	dock.cordon_name_edit.focus_exited.connect(
		func() -> void: dock._on_cordon_name_submitted(dock.cordon_name_edit.text)
	)
	detail_row.add_child(dock.cordon_name_edit)
	content.add_child(detail_row)

	var min_label = Label.new()
	min_label.text = "Min (X, Y, Z):"
	content.add_child(min_label)
	var min_row = HBoxContainer.new()
	dock.cordon_min_x = make_cordon_spin(dock, -CORDON_LIMIT, CORDON_LIMIT, -128)
	dock.cordon_min_y = make_cordon_spin(dock, -CORDON_LIMIT, CORDON_LIMIT, -128)
	dock.cordon_min_z = make_cordon_spin(dock, -CORDON_LIMIT, CORDON_LIMIT, -128)
	min_row.add_child(dock.cordon_min_x)
	min_row.add_child(dock.cordon_min_y)
	min_row.add_child(dock.cordon_min_z)
	content.add_child(min_row)

	var max_label = Label.new()
	max_label.text = "Max (X, Y, Z):"
	content.add_child(max_label)
	var max_row = HBoxContainer.new()
	dock.cordon_max_x = make_cordon_spin(dock, -CORDON_LIMIT, CORDON_LIMIT, 128)
	dock.cordon_max_y = make_cordon_spin(dock, -CORDON_LIMIT, CORDON_LIMIT, 128)
	dock.cordon_max_z = make_cordon_spin(dock, -CORDON_LIMIT, CORDON_LIMIT, 128)
	max_row.add_child(dock.cordon_max_x)
	max_row.add_child(dock.cordon_max_y)
	max_row.add_child(dock.cordon_max_z)
	content.add_child(max_row)

	var selection_row = HFUIFactory.make_wrap_row()
	dock.cordon_from_sel_btn = Button.new()
	dock.cordon_from_sel_btn.text = "Set from Selection"
	dock.cordon_from_sel_btn.tooltip_text = "Fit this cordon around the selected brushes"
	dock.cordon_from_sel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.cordon_from_sel_btn.pressed.connect(dock._on_cordon_from_selection)
	selection_row.add_child(dock.cordon_from_sel_btn)
	dock.cordon_add_sel_btn = Button.new()
	dock.cordon_add_sel_btn.text = "Add from Selection"
	dock.cordon_add_sel_btn.tooltip_text = "Add a cordon round the selected brushes"
	dock.cordon_add_sel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.cordon_add_sel_btn.pressed.connect(dock._on_cordon_add_from_selection)
	selection_row.add_child(dock.cordon_add_sel_btn)
	content.add_child(selection_row)


static func make_cordon_spin(
	dock: Object, min_value: float, max_value: float, default_value: float
) -> SpinBox:
	var spin = SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.value = default_value
	spin.step = 1.0
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(dock._on_cordon_value_changed)
	return spin


static func on_cordon_toggled(dock: Object, pressed: bool) -> void:
	if dock == null or dock.syncing_grid:
		return
	if dock.level_root and dock._root_has_property("cordon_enabled"):
		var before: Dictionary = dock.level_root.capture_cordons()
		dock.level_root.set("cordon_enabled", pressed)
		dock._tag_bake_setting_change("cordon_enabled")
		if dock.level_root.has_method("update_cordon_visual"):
			dock.level_root.update_cordon_visual()
		dock._commit_cordon_edit("Enable Cordon" if pressed else "Disable Cordon", before)


## The cordon the spins edit: 0 is the level's `cordon_aabb`.
static func selected_cordon_index(dock: Object) -> int:
	if dock == null or not dock.cordon_region_opt:
		return 0
	return maxi(dock.cordon_region_opt.selected, 0)


static func on_cordon_region_selected(dock: Object, index: int) -> void:
	sync_cordon_ui(dock, index)


static func on_cordon_value_changed(dock: Object, _value: float) -> void:
	if dock == null or dock.syncing_grid or not dock.level_root:
		return
	var min_point = Vector3(
		dock.cordon_min_x.value if dock.cordon_min_x else -128,
		dock.cordon_min_y.value if dock.cordon_min_y else -128,
		dock.cordon_min_z.value if dock.cordon_min_z else -128
	)
	var max_point = Vector3(
		dock.cordon_max_x.value if dock.cordon_max_x else 128,
		dock.cordon_max_y.value if dock.cordon_max_y else 128,
		dock.cordon_max_z.value if dock.cordon_max_z else 128
	)
	# A level loaded since the list was built can hold fewer cordons, and one past
	# the last would add a cordon where the mapper meant to move one.
	var index := selected_cordon_index(dock)
	if index >= dock.level_root.get_all_cordon_regions().size():
		sync_cordon_ui(dock)
		return
	var before: Dictionary = dock.level_root.capture_cordons()
	if dock.level_root.set_cordon_region(index, AABB(min_point, max_point - min_point)):
		# One step a cordon, so dragging a spin is one undo and not one a value.
		dock._commit_cordon_edit("Move Cordon %d" % (index + 1), before, true)


static func on_cordon_from_selection(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		return
	if not dock._guard_selection_action(
		"Set Cordon from Selection", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	# Kept to a cordon the level holds, for the same reason as the spins.
	var last: int = dock.level_root.get_all_cordon_regions().size() - 1
	var index := mini(selected_cordon_index(dock), last)
	var before: Dictionary = dock.level_root.capture_cordons()
	dock.level_root.set_cordon_from_selection(dock._selection_nodes, index)
	dock._commit_cordon_edit("Set Cordon from Selection", before)
	_show_cordon_from_selection(dock, index)


static func on_cordon_add_from_selection(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		return
	if not dock._guard_selection_action(
		"Add Cordon from Selection", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	# One past the last cordon, which is how the level is asked to add one.
	var index: int = dock.level_root.get_all_cordon_regions().size()
	var before: Dictionary = dock.level_root.capture_cordons()
	dock.level_root.set_cordon_from_selection(dock._selection_nodes, index)
	dock._commit_cordon_edit("Add Cordon from Selection", before)
	_show_cordon_from_selection(dock, index)


static func on_cordon_remove(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	var index := selected_cordon_index(dock)
	var before: Dictionary = dock.level_root.capture_cordons()
	if dock.level_root.remove_cordon_region(index):
		dock._commit_cordon_edit("Remove Cordon", before)
		# The cordon after it has moved up into its place.
		sync_cordon_ui(dock, index)


static func on_cordon_active_toggled(dock: Object, pressed: bool) -> void:
	if dock == null or dock.syncing_grid or not dock.level_root:
		return
	# A list left over from another level names a cordon that is not there, and
	# the level refuses it; the dock looks again instead.
	var index := selected_cordon_index(dock)
	var before: Dictionary = dock.level_root.capture_cordons()
	if dock.level_root.set_cordon_active(index, pressed):
		dock._commit_cordon_edit("Bake Cordon" if pressed else "Skip Cordon", before)
		sync_cordon_ui(dock, index)
	else:
		sync_cordon_ui(dock)


static func on_cordon_name_submitted(dock: Object, text: String) -> void:
	if dock == null or dock.syncing_grid or not dock.level_root:
		return
	var index := selected_cordon_index(dock)
	if dock.level_root.get_cordon_name(index) == text.strip_edges():
		return
	var before: Dictionary = dock.level_root.capture_cordons()
	if dock.level_root.set_cordon_name(index, text):
		dock._commit_cordon_edit("Rename Cordon", before)
		sync_cordon_ui(dock, index)
	else:
		sync_cordon_ui(dock)


## Put a cordon edit on `undo_redo` as the cordons before it and after it, both
## ends restored through `restore_cordons()`, which also refreshes the dock.
## `merge` folds it into the step before when that one has the same name.
## Returns false, registering nothing, when the edit changed nothing.
##
## Takes the manager rather than the dock, so it can be driven against a
## stand-in: an `EditorUndoRedoManager` cannot be built outside the editor.
static func record_cordon_edit(
	undo_redo, root: Node, action_name: String, before: Dictionary, merge: bool = false
) -> bool:
	if undo_redo == null or root == null:
		return false
	var after: Dictionary = root.capture_cordons()
	if after == before:
		return false
	var mode: int = UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE
	undo_redo.create_action(action_name, mode, root, false)
	undo_redo.add_do_method(root, "restore_cordons", after)
	undo_redo.add_undo_method(root, "restore_cordons", before)
	undo_redo.commit_action(false)
	return true


## Copy the level's cordons into the dock: one entry for each, by name, the
## selected one's bounds, switch and name below, and Remove only while there is a
## cordon to spare. Returns true when a bound sits past what the spins can show.
static func sync_cordon_ui(dock: Object, select: int = -1) -> bool:
	if dock == null or not dock.level_root:
		return false
	var regions: Array[AABB] = dock.level_root.get_all_cordon_regions()
	var index: int = select if select >= 0 else selected_cordon_index(dock)
	index = clampi(index, 0, regions.size() - 1)
	var bounds := regions[index]
	var values := [
		bounds.position.x,
		bounds.position.y,
		bounds.position.z,
		bounds.end.x,
		bounds.end.y,
		bounds.end.z,
	]
	var controls := [
		dock.cordon_min_x,
		dock.cordon_min_y,
		dock.cordon_min_z,
		dock.cordon_max_x,
		dock.cordon_max_y,
		dock.cordon_max_z,
	]
	# Each assignment clamps to the control's range *and* fires `value_changed`,
	# which reads all six spins straight back onto the level. Without this guard
	# the cordon was replaced by whatever the spins could hold.
	var was_syncing: bool = dock.syncing_grid
	dock.syncing_grid = true
	if dock.cordon_region_opt:
		dock.cordon_region_opt.clear()
		for i in range(regions.size()):
			var label: String = dock.level_root.get_cordon_name(i)
			if not dock.level_root.is_cordon_active(i):
				label += " (off)"
			dock.cordon_region_opt.add_item(label)
		dock.cordon_region_opt.select(index)
	if dock.cordon_remove_btn:
		dock.cordon_remove_btn.disabled = regions.size() < 2
	if dock.cordon_active_check:
		dock.cordon_active_check.button_pressed = dock.level_root.is_cordon_active(index)
	if dock.cordon_name_edit:
		var names: PackedStringArray = dock.level_root.cordon_names
		dock.cordon_name_edit.text = names[index] if index < names.size() else ""
		dock.cordon_name_edit.placeholder_text = "Cordon %d" % (index + 1)
	var clamped := false
	for i in range(controls.size()):
		if controls[i]:
			controls[i].value = values[i]
			if not is_equal_approx(controls[i].value, values[i]):
				clamped = true
	dock.syncing_grid = was_syncing
	return clamped


static func _show_cordon_from_selection(dock: Object, index: int) -> void:
	if sync_cordon_ui(dock, index):
		dock._set_status_warning(
			"Cordon set past +/-%d; the spins cannot show it all" % int(CORDON_LIMIT)
		)
	if dock.cordon_enabled_check:
		dock.cordon_enabled_check.button_pressed = true
