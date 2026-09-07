@tool
class_name HFDockVisgroupHandler
extends RefCounted
## Visgroup, grouping, and cordon controls extracted from dock.gd.

const HFCollapsibleSection = preload("ui/collapsible_section.gd")


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

	var visgroup_buttons = HBoxContainer.new()
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
	dock.visgroup_delete_btn = Button.new()
	dock.visgroup_delete_btn.text = "Delete"
	dock.visgroup_delete_btn.tooltip_text = "Delete the highlighted visgroup"
	dock.visgroup_delete_btn.pressed.connect(dock._on_visgroup_delete)
	visgroup_buttons.add_child(dock.visgroup_delete_btn)
	content.add_child(visgroup_buttons)

	content.add_child(HSeparator.new())
	var group_buttons = HBoxContainer.new()
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
	content.add_child(group_buttons)


static func refresh_visgroup_ui(dock: Object) -> void:
	if dock == null or not dock.visgroup_list:
		return
	dock.visgroup_list.clear()
	if not dock.level_root or not dock.level_root.get("visgroup_system"):
		return
	var system = dock.level_root.get("visgroup_system")
	for visgroup_name in system.get_visgroup_names():
		var prefix = "[V] " if system.is_visgroup_visible(visgroup_name) else "[H] "
		dock.visgroup_list.add_item(prefix + visgroup_name)


static func get_selected_visgroup_name(dock: Object) -> String:
	if dock == null or not dock.visgroup_list:
		return ""
	var selected = dock.visgroup_list.get_selected_items()
	if selected.is_empty():
		return ""
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
	dock.level_root.create_visgroup(visgroup_name)
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
	if index < dock.visgroup_list.item_count:
		dock.visgroup_list.select(index)


static func on_visgroup_add_selection(dock: Object) -> void:
	if dock == null:
		return
	var visgroup_name = get_selected_visgroup_name(dock)
	if visgroup_name == "" or not dock.level_root:
		return
	if not dock._guard_selection_action("Add to Visgroup"):
		return
	dock.level_root.add_selection_to_visgroup(visgroup_name, dock._selection_nodes)
	refresh_visgroup_ui(dock)


static func on_visgroup_remove_selection(dock: Object) -> void:
	if dock == null:
		return
	var visgroup_name = get_selected_visgroup_name(dock)
	if visgroup_name == "" or not dock.level_root:
		return
	if not dock._guard_selection_action("Remove from Visgroup"):
		return
	dock.level_root.remove_selection_from_visgroup(visgroup_name, dock._selection_nodes)
	refresh_visgroup_ui(dock)


static func on_visgroup_delete(dock: Object) -> void:
	if dock == null:
		return
	var visgroup_name = get_selected_visgroup_name(dock)
	if visgroup_name == "" or not dock.level_root:
		return
	dock.level_root.remove_visgroup(visgroup_name)
	refresh_visgroup_ui(dock)


static func on_group_selection(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.size() < 2:
		return
	if not dock._guard_selection_action("Group Selection"):
		return
	dock.level_root.group_selection("group_%d" % Time.get_ticks_usec(), dock._selection_nodes)
	dock.record_history("Group Selection")


static func on_ungroup_selection(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		return
	if not dock._guard_selection_action("Ungroup Selection"):
		return
	dock.level_root.ungroup_nodes(dock._selection_nodes)
	dock.record_history("Ungroup Selection")


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
	dock.cordon_enabled_check.tooltip_text = "Only bake geometry inside the cordon AABB"
	dock.cordon_enabled_check.toggled.connect(dock._on_cordon_toggled)
	content.add_child(dock.cordon_enabled_check)

	var min_label = Label.new()
	min_label.text = "Min (X, Y, Z):"
	content.add_child(min_label)
	var min_row = HBoxContainer.new()
	dock.cordon_min_x = make_cordon_spin(dock, -9999, 9999, -128)
	dock.cordon_min_y = make_cordon_spin(dock, -9999, 9999, -128)
	dock.cordon_min_z = make_cordon_spin(dock, -9999, 9999, -128)
	min_row.add_child(dock.cordon_min_x)
	min_row.add_child(dock.cordon_min_y)
	min_row.add_child(dock.cordon_min_z)
	content.add_child(min_row)

	var max_label = Label.new()
	max_label.text = "Max (X, Y, Z):"
	content.add_child(max_label)
	var max_row = HBoxContainer.new()
	dock.cordon_max_x = make_cordon_spin(dock, -9999, 9999, 128)
	dock.cordon_max_y = make_cordon_spin(dock, -9999, 9999, 128)
	dock.cordon_max_z = make_cordon_spin(dock, -9999, 9999, 128)
	max_row.add_child(dock.cordon_max_x)
	max_row.add_child(dock.cordon_max_y)
	max_row.add_child(dock.cordon_max_z)
	content.add_child(max_row)

	dock.cordon_from_sel_btn = Button.new()
	dock.cordon_from_sel_btn.text = "Set from Selection"
	dock.cordon_from_sel_btn.tooltip_text = "Set cordon bounds to encompass the selected brushes"
	dock.cordon_from_sel_btn.pressed.connect(dock._on_cordon_from_selection)
	content.add_child(dock.cordon_from_sel_btn)


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
		dock.level_root.set("cordon_enabled", pressed)
		dock._tag_bake_setting_change("cordon_enabled")
		if dock.level_root.has_method("update_cordon_visual"):
			dock.level_root.update_cordon_visual()


static func on_cordon_value_changed(dock: Object, _value: float) -> void:
	if dock == null or dock.syncing_grid:
		return
	if not dock.level_root or not dock._root_has_property("cordon_aabb"):
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
	dock.level_root.set("cordon_aabb", AABB(min_point, max_point - min_point))
	dock._tag_bake_setting_change("cordon_aabb")
	dock.level_root.update_cordon_visual()


static func on_cordon_from_selection(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		return
	if not dock._guard_selection_action(
		"Set Cordon from Selection", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	dock.level_root.set_cordon_from_selection(dock._selection_nodes)
	if dock._root_has_property("cordon_aabb"):
		var bounds: AABB = dock.level_root.get("cordon_aabb")
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
		for index in range(controls.size()):
			if controls[index]:
				controls[index].value = values[index]
	if dock.cordon_enabled_check:
		dock.cordon_enabled_check.button_pressed = true
