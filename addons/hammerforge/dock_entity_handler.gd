@tool
class_name HFDockEntityHandler
extends RefCounted
## Objects-tab entity handlers extracted from dock.gd (properties, create, I/O).

const DraftEntity = preload("draft_entity.gd")
const HFEntityPropUtils = preload("ui/hf_entity_prop_utils.gd")


static func rebuild_entity_props(dock: Object, entity: Node3D) -> void:
	if dock == null:
		return
	clear_entity_props(dock)
	if not entity or not is_instance_valid(entity):
		return
	if not dock.level_root or not dock.level_root.is_entity_node(entity):
		return

	var entity_type_key := HFEntityPropUtils.get_entity_type(entity)
	if entity_type_key == "":
		return

	var definition := HFEntityPropUtils.find_definition(dock.entity_defs, entity_type_key)
	var props: Array = definition.get("properties", [])
	if props.is_empty():
		return

	dock._entity_props_section.visible = true
	dock._entity_props_entity = entity
	var content = dock._entity_props_section.get_content()

	var e_data := HFEntityPropUtils.get_entity_data(entity)

	for prop in props:
		if not (prop is Dictionary):
			continue
		var prop_name: String = str(prop.get("name", ""))
		if prop_name == "":
			continue
		var prop_type: String = str(prop.get("type", "string"))
		var prop_label: String = str(prop.get("label", prop_name))
		var prop_default: Variant = prop.get("default", null)
		var default_val: Variant = entity_prop_default(prop_type, prop_default)
		var current_val: Variant = e_data.get(prop_name, default_val)

		var row = HBoxContainer.new()
		content.add_child(row)
		dock._entity_props_controls.append(row)

		var lbl = Label.new()
		lbl.text = prop_label + ":"
		lbl.custom_minimum_size.x = 70
		row.add_child(lbl)

		match prop_type:
			"string":
				var le = LineEdit.new()
				le.text = str(current_val)
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				le.text_changed.connect(dock._on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(le)
			"int":
				var sb = SpinBox.new()
				sb.step = 1
				sb.allow_greater = true
				sb.allow_lesser = true
				sb.value = int(current_val)
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.value_changed.connect(dock._on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(sb)
			"float":
				var sb = SpinBox.new()
				sb.step = 0.01
				sb.allow_greater = true
				sb.allow_lesser = true
				sb.value = float(current_val)
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.value_changed.connect(dock._on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(sb)
			"bool":
				var cb = CheckBox.new()
				cb.button_pressed = bool(current_val)
				cb.toggled.connect(dock._on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(cb)
			"enum":
				var ob = OptionButton.new()
				var enum_vals: Array = prop.get("enum_values", [])
				for ev in enum_vals:
					ob.add_item(str(ev))
				var idx = enum_vals.find(current_val)
				if idx >= 0:
					ob.select(idx)
				ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				ob.item_selected.connect(
					dock._on_entity_prop_enum_changed.bind(entity, prop_name, enum_vals)
				)
				row.add_child(ob)
			"color":
				var cpb = ColorPickerButton.new()
				if current_val is Color:
					cpb.color = current_val
				elif current_val is String:
					cpb.color = Color(current_val)
				else:
					cpb.color = Color.WHITE
				cpb.custom_minimum_size = Vector2(40, 24)
				cpb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				cpb.color_changed.connect(dock._on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(cpb)
			"vector3":
				var vec: Vector3 = Vector3.ZERO
				if current_val is Vector3:
					vec = current_val
				elif current_val is Array and current_val.size() == 3:
					vec = Vector3(current_val[0], current_val[1], current_val[2])
				for axis_i in range(3):
					var sb = SpinBox.new()
					sb.step = 0.01
					sb.allow_greater = true
					sb.allow_lesser = true
					sb.value = vec[axis_i]
					sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					sb.custom_minimum_size.x = 70
					sb.value_changed.connect(
						dock._on_entity_prop_vec3_changed.bind(entity, prop_name, axis_i)
					)
					row.add_child(sb)
			_:
				var le = LineEdit.new()
				le.text = str(current_val)
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				le.text_changed.connect(dock._on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(le)


static func clear_entity_props(dock: Object) -> void:
	if dock == null:
		return
	for ctrl in dock._entity_props_controls:
		if is_instance_valid(ctrl):
			ctrl.queue_free()
	dock._entity_props_controls.clear()
	dock._entity_props_entity = null
	if dock._entity_props_section:
		dock._entity_props_section.visible = false


static func on_entity_prop_changed(
	dock: Object, value: Variant, entity: Node3D, prop_name: String
) -> void:
	if dock == null or not can_edit_selected_entity(dock, entity):
		return
	HFEntityPropUtils.set_entity_property(entity, prop_name, value)


static func on_entity_prop_enum_changed(
	dock: Object, index: int, entity: Node3D, prop_name: String, enum_vals: Array
) -> void:
	if dock == null or not can_edit_selected_entity(dock, entity):
		return
	var value: Variant = enum_vals[index] if index < enum_vals.size() else ""
	HFEntityPropUtils.set_entity_property(entity, prop_name, value)


static func on_entity_prop_vec3_changed(
	dock: Object, value: float, entity: Node3D, prop_name: String, axis_index: int
) -> void:
	if dock == null or not can_edit_selected_entity(dock, entity):
		return
	HFEntityPropUtils.set_entity_vec3_axis(entity, prop_name, axis_index, value)


static func can_edit_selected_entity(dock: Object, entity: Node3D) -> bool:
	if dock == null or not dock.level_root or not is_instance_valid(entity):
		return false
	if not dock._guard_selection_action("Edit Entity", dock.DockSelectionRequirement.ENTITIES_ONLY):
		return false
	return dock.level_root.is_entity_node(entity) and dock._selection_nodes.has(entity)


static func entity_prop_default(type_name: String, value: Variant) -> Variant:
	return HFEntityPropUtils.coerce_default(type_name, value)


static func on_create_entity(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	var entity = DraftEntity.new()
	entity.name = "DraftEntity"
	entity.set_meta("is_entity", true)
	var def = get_default_entity_definition(dock)
	if not def.is_empty():
		var type_id = str(def.get("id", def.get("class", "")))
		if type_id != "":
			entity.entity_type = type_id
			entity.entity_class = type_id
	dock.level_root.add_entity(entity)
	focus_entity_selection(dock, entity)


static func focus_entity_selection(dock: Object, entity: Node) -> void:
	if dock == null or not dock.editor_interface or not entity:
		return
	var selection = dock.editor_interface.get_selection()
	if selection:
		selection.clear()
		selection.add_node(entity)


static func get_default_entity_definition(dock: Object) -> Dictionary:
	if dock == null or dock.entity_defs.is_empty():
		return {}
	return dock.entity_defs[0] if dock.entity_defs[0] is Dictionary else {}


static func on_io_add(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		if dock:
			dock._set_status("Select an entity to add output", true)
		return
	if not dock._guard_selection_action(
		"Add Entity Output", dock.DockSelectionRequirement.ENTITIES_ONLY
	):
		return
	var entity = dock._first_selected_entity()
	if not entity:
		dock._set_status("Select an entity to add output", true)
		return
	var output_name = dock.io_output_name.text.strip_edges() if dock.io_output_name else ""
	var target_name = dock.io_target_name.text.strip_edges() if dock.io_target_name else ""
	var input_name = dock.io_input_name.text.strip_edges() if dock.io_input_name else ""
	if output_name == "" or target_name == "" or input_name == "":
		dock._set_status("Fill in Output, Target, and Input fields", true)
		return
	var parameter = dock.io_parameter.text.strip_edges() if dock.io_parameter else ""
	var delay = dock.io_delay.value if dock.io_delay else 0.0
	var fire_once = dock.io_fire_once.button_pressed if dock.io_fire_once else false
	dock.level_root.add_entity_output(
		entity, output_name, target_name, input_name, parameter, delay, fire_once
	)
	refresh_io_list(dock, entity)
	dock._set_status("Added output: %s → %s.%s" % [output_name, target_name, input_name])


static func on_io_remove(dock: Object) -> void:
	if dock == null or not dock.level_root or dock._selection_nodes.is_empty():
		return
	if not dock._guard_selection_action(
		"Remove Entity Output", dock.DockSelectionRequirement.ENTITIES_ONLY
	):
		return
	var entity = dock._first_selected_entity()
	if not entity:
		return
	if not dock.io_list:
		return
	var selected_items = dock.io_list.get_selected_items()
	if selected_items.is_empty():
		dock._set_status("Select a connection to remove", true)
		return
	var index = selected_items[0]
	dock.level_root.remove_entity_output(entity, index)
	refresh_io_list(dock, entity)
	dock._set_status("Removed output connection")


static func refresh_io_list(dock: Object, entity: Node = null) -> void:
	if dock == null or not dock.io_list:
		return
	dock.io_list.clear()
	if not entity:
		if dock._current_selection_scope() == dock.DockSelectionScope.MIXED:
			return
		if dock._selection_nodes.is_empty():
			return
		entity = dock._first_selected_entity()
	if not dock.level_root or not dock.level_root.is_entity_node(entity):
		return
	var outputs = dock.level_root.get_entity_outputs(entity)
	for conn in outputs:
		if not (conn is Dictionary):
			continue
		var out_name = str(conn.get("output_name", ""))
		var tgt = str(conn.get("target_name", ""))
		var inp = str(conn.get("input_name", ""))
		var delay = float(conn.get("delay", 0.0))
		var once = bool(conn.get("fire_once", false))
		var label = "%s → %s.%s" % [out_name, tgt, inp]
		if delay > 0.0:
			label += " (%.1fs)" % delay
		if once:
			label += " [once]"
		dock.io_list.add_item(label)


static func setup_io_wiring_panel(dock: Object) -> void:
	if dock == null or not dock._io_wiring_panel or not dock.level_root:
		return
	dock._io_wiring_panel.setup(
		dock.level_root.entity_system, dock.level_root.io_presets, dock.level_root.io_visualizer
	)


static func on_wiring_connection_added(
	dock: Object,
	source: Node,
	output_name: String,
	target_name: String,
	input_name: String,
	_parameter: String,
	_delay: float,
	_fire_once: bool,
) -> void:
	if dock == null:
		return
	refresh_io_list(dock, source)
	dock._set_status("Wired: %s → %s.%s" % [output_name, target_name, input_name])


static func on_wiring_preset_applied(
	dock: Object, source: Node, preset_name: String, count: int
) -> void:
	if dock == null:
		return
	refresh_io_list(dock, source)
	dock._set_status("Applied preset '%s' (%d connections)" % [preset_name, count])


static func on_wiring_highlight_toggled(dock: Object, enabled: bool) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.set_highlight_connected(enabled)


static func sync_wiring_highlight_state(dock: Object) -> void:
	if dock == null:
		return
	if dock._io_wiring_panel and dock._io_wiring_panel.has_method("_sync_highlight_button"):
		dock._io_wiring_panel._sync_highlight_button()
