@tool
class_name HFDockEntityHandler
extends RefCounted
## Objects-tab entity handlers extracted from dock.gd (properties, create, I/O).

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftEntity = preload("draft_entity.gd")
const HFEntityPropUtils = preload("ui/hf_entity_prop_utils.gd")
const HFUndoHelper = preload("undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")


static func rebuild_entity_props(dock: Object, entity: Node3D) -> void:
	if dock == null:
		return
	clear_entity_props(dock)
	if not entity or not is_instance_valid(entity):
		return
	# A brush tied to an entity class is a brush, so `is_entity_node()` is false
	# for it - and it has properties of its own that nothing could reach (#728).
	if not dock.level_root:
		return
	if not dock.level_root.is_entity_node(entity) and not HFEntityPropUtils.is_brush_entity(entity):
		return

	var entity_type_key := HFEntityPropUtils.get_entity_type(entity)
	if entity_type_key == "":
		return

	var definition := HFEntityPropUtils.find_definition(dock.entity_defs, entity_type_key)
	var props: Array = definition.get("properties", [])
	if props.is_empty():
		return

	dock._entity_props_section.visible = true
	var content = dock._entity_props_section.get_content()

	var e_data := HFEntityPropUtils.get_entity_data(entity)

	var presets := HFEntityPropUtils.preset_names(definition)
	if not presets.is_empty():
		_add_preset_row(dock, content, entity, definition, presets)

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

		var resource_type := resource_type_of(definition, prop_name)
		if resource_type != "":
			_add_resource_row(dock, row, entity, prop_name, str(current_val), resource_type)
			_apply_tooltip(row, lbl, str(prop.get("tooltip", "")))
			continue

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
		_apply_tooltip(row, lbl, str(prop.get("tooltip", "")))


## A definition's `tooltip` on a property's label and controls, which is where a
## caveat such as a renderer that ignores the property gets said up front.
static func _apply_tooltip(row: HBoxContainer, label: Label, tooltip: String) -> void:
	if tooltip == "":
		return
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in row.get_children():
		if child is Control and (child as Control).tooltip_text == "":
			(child as Control).tooltip_text = tooltip


## A Preset list at the top of the panel. Picking one sets every value it names
## as one undo step, and the panel is rebuilt to show them.
static func _add_preset_row(
	dock: Object,
	content: Control,
	entity: Node3D,
	definition: Dictionary,
	presets: PackedStringArray
) -> void:
	var row := HBoxContainer.new()
	content.add_child(row)
	dock._entity_props_controls.append(row)
	var lbl := Label.new()
	lbl.text = "Preset:"
	lbl.custom_minimum_size.x = 70
	row.add_child(lbl)
	var picker := OptionButton.new()
	picker.name = "EntityPreset"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("Apply a preset")
	picker.set_item_disabled(0, true)
	for preset_name in presets:
		picker.add_item(preset_name)
	picker.select(0)
	picker.tooltip_text = "Set this entity's values from a named preset, as one undo step"
	picker.item_selected.connect(dock._on_entity_preset_selected.bind(entity, definition, presets))
	row.add_child(picker)


## Apply the preset picked in the Preset list to `entity`, as one undo step,
## and rebuild the panel to show its values. Index 0 is the prompt, not a preset.
static func on_entity_preset_selected(
	dock: Object, index: int, entity: Node3D, definition: Dictionary, presets: PackedStringArray
) -> void:
	if dock == null or index < 1 or index > presets.size():
		return
	if not can_edit_selected_entity(dock, entity):
		return
	var preset_name := presets[index - 1]
	var values := HFEntityPropUtils.preset_values(definition, preset_name)
	if values.is_empty():
		return
	var root: Node = dock.level_root
	HFUndoHelper.commit(
		dock.undo_redo,
		root,
		"Preset %s" % preset_name,
		"set_entity_properties",
		[entity, values],
		false,
		Callable(dock, "record_history"),
		"",
		true,
		[],
		[root.get_path_to(entity)]
	)
	rebuild_entity_props(dock, entity)


## The resource type an entity definition says a property's path names, such as
## AudioStream for `ambient_sound.stream`, or "" for a plain value.
static func resource_type_of(definition: Dictionary, prop_name: String) -> String:
	var resource_props: Variant = definition.get("resource_properties", {})
	if resource_props is Dictionary:
		return str((resource_props as Dictionary).get(prop_name, ""))
	return ""


## A path field with a picker beside it, and for a sound a Play button, so a
## sound can be chosen and heard without typing a path or exporting (#991).
static func _add_resource_row(
	dock: Object,
	row: HBoxContainer,
	entity: Node3D,
	prop_name: String,
	path: String,
	resource_type: String
) -> void:
	var field := LineEdit.new()
	field.text = path
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_changed.connect(dock._on_entity_prop_changed.bind(entity, prop_name))
	row.add_child(field)
	var pick := Button.new()
	pick.text = "..."
	pick.tooltip_text = "Pick a %s file" % resource_type
	pick.pressed.connect(
		dock._on_entity_resource_pick.bind(entity, prop_name, resource_type, field)
	)
	row.add_child(pick)
	if ClassDB.is_parent_class(resource_type, "AudioStream"):
		var play := Button.new()
		play.text = "Play"
		play.tooltip_text = "Play or stop it here. It stops when the selection changes"
		play.pressed.connect(dock._on_entity_sound_preview.bind(field))
		row.add_child(play)


## Open a file picker for a resource property, filtered to the files Godot can
## load as `resource_type`. The pick goes to the field and the entity, as typing
## the path would.
static func pick_entity_resource(
	dock: Object, entity: Node3D, prop_name: String, resource_type: String, field: LineEdit
) -> void:
	var dialog: FileDialog = dock._entity_resource_dialog
	if dialog == null or not is_instance_valid(dialog):
		dialog = FileDialog.new()
		dialog.name = "EntityResourceDialog"
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.access = FileDialog.ACCESS_RESOURCES
		dialog.file_selected.connect(dock._on_entity_resource_picked)
		dock.add_child(dialog)
		dock._entity_resource_dialog = dialog
	var patterns := PackedStringArray()
	var extensions := ResourceLoader.get_recognized_extensions_for_type(resource_type)
	# That list is the saved resource formats only. The files a project actually
	# holds are the ones Godot imports, and GDScript cannot ask the importers.
	if ClassDB.is_parent_class(resource_type, "AudioStream"):
		extensions.append_array(PackedStringArray(["wav", "ogg", "mp3"]))
	for extension in extensions:
		patterns.append("*.%s" % extension)
	dialog.filters = PackedStringArray(["%s ; %s" % [", ".join(patterns), resource_type]])
	dialog.title = "Pick %s" % resource_type
	dock._entity_resource_target = {"entity": entity, "prop": prop_name, "field": field}
	dialog.popup_centered_ratio(0.6)


## Put the file the picker returned in the field and on the entity it was
## opened for, as typing the path would. A pick for an entity since freed does nothing.
static func on_entity_resource_picked(dock: Object, path: String) -> void:
	var target: Dictionary = dock._entity_resource_target
	dock._entity_resource_target = {}
	var entity = target.get("entity")
	if entity == null or not is_instance_valid(entity):
		return
	var field = target.get("field")
	if field != null and is_instance_valid(field):
		field.text = path
	on_entity_prop_changed(dock, path, entity, str(target.get("prop", "")))


## Play the sound at `path` in the editor, or stop it if one is playing. One
## player for the dock, so a second sound replaces the first rather than layering
## on it. The player is a child of the dock and stops when the dock closes.
static func toggle_sound_preview(dock: Object, path: String) -> void:
	var player: AudioStreamPlayer = dock._sound_preview
	if player != null and is_instance_valid(player) and player.playing:
		player.stop()
		return
	var stream: AudioStream = null
	if path != "" and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		dock.show_toast("No sound at %s" % path if path != "" else "Pick a sound first", 1)
		return
	if player == null or not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		player.name = "SoundPreview"
		dock.add_child(player)
		dock._sound_preview = player
	player.stream = stream
	player.play()


## Stop the sound the Entity panel is playing, if one is.
static func stop_sound_preview(dock: Object) -> void:
	var player: AudioStreamPlayer = dock._sound_preview
	if player != null and is_instance_valid(player):
		player.stop()


static func clear_entity_props(dock: Object) -> void:
	if dock == null:
		return
	# The form is rebuilt when the selection changes, and a sound playing for the
	# entity that was selected stops with it.
	stop_sound_preview(dock)
	for ctrl in dock._entity_props_controls:
		if is_instance_valid(ctrl):
			ctrl.queue_free()
	dock._entity_props_controls.clear()
	if dock._entity_props_section:
		dock._entity_props_section.visible = false


static func on_entity_prop_changed(
	dock: Object, value: Variant, entity: Node3D, prop_name: String
) -> void:
	if dock == null or not can_edit_selected_entity(dock, entity):
		return
	commit_entity_property(dock, entity, prop_name, value)


static func on_entity_prop_enum_changed(
	dock: Object, index: int, entity: Node3D, prop_name: String, enum_vals: Array
) -> void:
	if dock == null or not can_edit_selected_entity(dock, entity):
		return
	var value: Variant = enum_vals[index] if index < enum_vals.size() else ""
	commit_entity_property(dock, entity, prop_name, value)


static func on_entity_prop_vec3_changed(
	dock: Object, value: float, entity: Node3D, prop_name: String, axis_index: int
) -> void:
	if dock == null or not can_edit_selected_entity(dock, entity):
		return
	var vec := HFEntityPropUtils.vec3_with_axis(entity, prop_name, axis_index, value)
	commit_entity_property(dock, entity, prop_name, vec)


## Every Entity panel edit is one undo step, the way the same edit in the
## Inspector is. It wrote the field straight, so Ctrl+Z after an edit undid the
## step before it, and after creating an entity that took the entity away (#931).
## Keystrokes in one field collate into a single step while they keep coming, and
## the snapshot is of that one entity rather than the level.
static func commit_entity_property(
	dock: Object, entity: Node3D, prop_name: String, value: Variant
) -> void:
	var root: Node = dock.level_root
	var scope_ids: Array = []
	var scope_paths: Array = []
	if HFEntityPropUtils.is_brush_entity(entity):
		scope_ids = [str(entity.get("brush_id"))]
	else:
		scope_paths = [root.get_path_to(entity)]
	HFUndoHelper.commit(
		dock.undo_redo,
		root,
		"Set %s" % prop_name,
		"set_entity_property",
		[entity, prop_name, value],
		false,
		Callable(dock, "record_history"),
		"entity_prop_%d_%s" % [entity.get_instance_id(), prop_name],
		true,
		scope_ids,
		scope_paths
	)


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
	dock._commit_state_action("Create Entity", "add_entity", [entity], true)
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
	dock._commit_state_action(
		"Add Entity Output",
		"add_entity_output",
		[entity, output_name, target_name, input_name, parameter, delay, fire_once],
		true
	)
	if dock._io_wiring_panel:
		dock._io_wiring_panel.set_source_entity(entity)
	dock._set_status("Added output: %s → %s.%s" % [output_name, target_name, input_name])


## The wiring panel has already removed the output; this commits the undo step
## its `will_change` opened.
static func on_wiring_connection_removed(dock: Object, source: Node, _index: int) -> void:
	if dock == null:
		return
	commit_wiring_change(dock, "Remove Entity Output")
	if source:
		dock._set_status("Removed output connection")


static func setup_io_wiring_panel(dock: Object) -> void:
	if dock == null or not dock._io_wiring_panel or not dock.level_root:
		return
	dock._io_wiring_panel.setup(
		dock.level_root.entity_system, dock.level_root.io_presets, dock.level_root.io_visualizer
	)


static func on_wiring_connection_added(
	dock: Object,
	_source: Node,
	output_name: String,
	target_name: String,
	input_name: String,
	_parameter: String,
	_delay: float,
	_fire_once: bool,
) -> void:
	if dock == null:
		return
	commit_wiring_change(dock, "Add Entity Output")
	dock._set_status("Wired: %s → %s.%s" % [output_name, target_name, input_name])


static func on_wiring_preset_applied(
	dock: Object, _source: Node, preset_name: String, count: int
) -> void:
	if dock == null:
		return
	commit_wiring_change(dock, "Apply I/O Preset: %s" % preset_name)
	dock._set_status("Applied preset '%s' (%d connections)" % [preset_name, count])


## The wiring panel holds the entity system, not the dock's undo manager, so it
## cannot register its own step. It says when it is about to change something and
## the dock takes the before state here; the panel's done signal commits the pair.
static func on_wiring_will_change(dock: Object, _action_name: String) -> void:
	if dock == null or not dock.level_root:
		return
	dock._wiring_before_state = dock.level_root.capture_full_state()


static func on_wiring_change_abandoned(dock: Object) -> void:
	if dock:
		dock._wiring_before_state = {}


static func commit_wiring_change(dock: Object, action_name: String) -> void:
	if dock == null or dock._wiring_before_state.is_empty():
		return
	var before: Dictionary = dock._wiring_before_state
	dock._wiring_before_state = {}
	dock._commit_done_state_action(action_name, before)


static func on_wiring_highlight_toggled(dock: Object, enabled: bool) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.set_highlight_connected(enabled)


static func sync_wiring_highlight_state(dock: Object) -> void:
	if dock == null:
		return
	if dock._io_wiring_panel and dock._io_wiring_panel.has_method("_sync_highlight_button"):
		dock._io_wiring_panel._sync_highlight_button()
