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
const HFEntityMultiEdit = preload("ui/hf_entity_multi_edit.gd")
const HFTranslationType = preload("hf_translation.gd")

## A value at its class default reads lighter than one set on purpose (#1729).
const DEFAULT_TINT := Color(1.0, 1.0, 1.0, 0.55)
## A property only some of the selected entities have.
const PARTIAL_TINT := Color(1.0, 1.0, 1.0, 0.45)


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
	# On a piece of a linked prefab copy, what the copy keeps of its own (#1734).
	var kept = _kept_of_linked_piece(dock, entity)

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
		var at_default := HFEntityMultiEdit.same_value(
			prop_type, HFEntityPropUtils.coerce_default(prop_type, current_val), default_val
		)
		if resource_type != "":
			_add_resource_row(dock, row, entity, prop_name, str(current_val), resource_type)
			_mark_default(dock, row, lbl, [entity], prop_name, at_default)
			_add_keep_box(dock, row, entity, prop_name, kept)
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
				for label in enum_labels(prop):
					ob.add_item(label)
				var idx := enum_index(enum_vals, current_val)
				if idx >= 0:
					ob.select(idx)
				ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				ob.item_selected.connect(
					dock._on_entity_prop_enum_changed.bind(entity, prop_name, enum_vals)
				)
				row.add_child(ob)
			"flags":
				_add_flag_boxes(dock, row, entity, prop, int(current_val))
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
		_mark_default(dock, row, lbl, [entity], prop_name, at_default)
		_add_keep_box(dock, row, entity, prop_name, kept)
		_apply_tooltip(row, lbl, str(prop.get("tooltip", "")))
	_add_defaults_row(dock, content, [entity])
	if kept != null:
		_add_kept_row(dock, content, entity, kept)


## Several entities in one panel (#1729): the union of their properties, a count
## on one only some have, a dash where their values differ. A value goes on every
## selected entity that has the property, as one undo step. The wiring below stays
## the first entity's.
static func rebuild_multi_entity_props(dock: Object, entities: Array) -> void:
	if dock == null:
		return
	clear_entity_props(dock)
	if entities.size() < 2 or not dock.level_root:
		return
	dock._entity_props_section.visible = true
	var content = dock._entity_props_section.get_content()
	var header := Label.new()
	header.name = "EntityMultiHeader"
	header.text = (
		HFTranslationType
		. tn(
			"{count} entity. A value goes on each one that has it.",
			"{count} entities. A value goes on each one that has it.",
			entities.size()
		)
		. format({"count": entities.size()})
	)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(header)
	dock._entity_props_controls.append(header)
	for row in HFEntityMultiEdit.rows(dock.entity_defs, entities):
		var holders: Array = row["holders"]
		var line := HBoxContainer.new()
		line.name = "Multi_%s" % row["name"]
		content.add_child(line)
		dock._entity_props_controls.append(line)
		var lbl := Label.new()
		lbl.text = HFTranslationType.t("{label}:").format({"label": row["label"]})
		if holders.size() < entities.size():
			lbl.text = (HFTranslationType.t("{label} ({have} of {count}):").format(
				{"label": row["label"], "have": holders.size(), "count": entities.size()}
			))
			lbl.modulate = PARTIAL_TINT
		lbl.custom_minimum_size.x = 70
		line.add_child(lbl)
		_add_multi_control(dock, line, row)
		_mark_default(dock, line, lbl, holders, row["name"], row["at_default"])
		_apply_tooltip(line, lbl, row["tooltip"])
	_add_defaults_row(dock, content, entities)
	var wiring := Label.new()
	wiring.name = "EntityMultiWiring"
	wiring.text = (HFTranslationType.t("Wiring below is for {name}, the first of them.").format(
		{"name": str(entities[0].name)}
	))
	wiring.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wiring.modulate = DEFAULT_TINT
	content.add_child(wiring)
	dock._entity_props_controls.append(wiring)


## The editor for one row of several entities. Where their values differ it
## shows a dash, or nothing picked, until a value is given.
static func _add_multi_control(dock: Object, line: HBoxContainer, row: Dictionary) -> void:
	var holders: Array = row["holders"]
	var value: Variant = row["values"][0]
	var same: bool = row["same"]
	match str(row["type"]):
		"int", "float", "flags":
			var sb := SpinBox.new()
			sb.step = 0.01 if row["type"] == "float" else 1.0
			sb.allow_greater = true
			sb.allow_lesser = true
			sb.value = float(value)
			sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sb.value_changed.connect(dock._on_entities_prop_changed.bind(holders, row["name"]))
			line.add_child(sb)
			# After it is in the tree, which writes the value into the text.
			if not same:
				sb.get_line_edit().text = "-"
		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = bool(value) and same
			if not same:
				cb.text = "-"
			cb.toggled.connect(dock._on_entities_prop_changed.bind(holders, row["name"]))
			line.add_child(cb)
		"enum":
			var ob := OptionButton.new()
			var enum_vals: Array = row["prop"].get("enum_values", [])
			for label in enum_labels(row["prop"]):
				ob.add_item(label)
			ob.select(enum_index(enum_vals, value) if same else -1)
			ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ob.item_selected.connect(
				dock._on_entities_prop_enum_changed.bind(holders, row["name"], enum_vals)
			)
			line.add_child(ob)
		"color":
			var cpb := ColorPickerButton.new()
			cpb.color = value if value is Color else Color.WHITE
			cpb.custom_minimum_size = Vector2(40, 24)
			cpb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if not same:
				cpb.tooltip_text = "The selected entities' colours differ"
			cpb.color_changed.connect(dock._on_entities_prop_changed.bind(holders, row["name"]))
			line.add_child(cpb)
		"vector3":
			for axis_i in range(3):
				var axis_same := true
				for other in row["values"]:
					if not is_equal_approx(float(other[axis_i]), float(value[axis_i])):
						axis_same = false
				var sb := SpinBox.new()
				sb.step = 0.01
				sb.allow_greater = true
				sb.allow_lesser = true
				sb.value = float(value[axis_i])
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.custom_minimum_size.x = 70
				sb.value_changed.connect(
					dock._on_entities_prop_vec3_changed.bind(holders, row["name"], axis_i)
				)
				line.add_child(sb)
				if not axis_same:
					sb.get_line_edit().text = "-"
		_:
			var le := LineEdit.new()
			le.text = str(value) if same else ""
			le.placeholder_text = "" if same else "-"
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(dock._on_entities_prop_changed.bind(holders, row["name"]))
			line.add_child(le)


## A value at its class default reads lighter; one set on purpose gets a Reset
## that puts the default back on `entities`.
static func _mark_default(
	dock: Object,
	row: HBoxContainer,
	label: Label,
	entities: Array,
	prop_name: String,
	at_default: bool
) -> void:
	if at_default:
		label.modulate = Color(label.modulate, label.modulate.a * DEFAULT_TINT.a)
		return
	var reset := Button.new()
	reset.name = "Reset_%s" % prop_name
	reset.text = "Reset"
	reset.flat = true
	reset.tooltip_text = "Put the class default back"
	reset.pressed.connect(dock._on_entity_prop_reset.bind(entities, prop_name))
	row.add_child(reset)


## What a linked prefab copy keeps of `entity`, or null when it is no piece of a
## linked copy.
static func _kept_of_linked_piece(dock: Object, entity: Node3D) -> Variant:
	var system = dock.level_root.get("prefab_system")
	var rec = system.instance_of(entity) if system else null
	if rec == null or not rec.linked:
		return null
	return system.kept_of(entity)


## A Keep box beside a property of a linked copy's piece: kept, the copy's own
## value stays through a Pull and Push leaves it out of the prefab.
static func _add_keep_box(
	dock: Object, row: HBoxContainer, entity: Node3D, prop_name: String, kept: Variant
) -> void:
	if kept == null:
		return
	var box := CheckBox.new()
	box.name = "Keep_%s" % prop_name
	box.text = "Keep"
	box.tooltip_text = "Keep this copy's value through a Pull. Push leaves it out of the prefab"
	box.button_pressed = (kept["properties"] as Array).has(prop_name)
	box.toggled.connect(dock._on_entity_keep_toggled.bind(entity, prop_name))
	row.add_child(box)


## Keep the piece's wiring, and Clear Kept, under a linked copy's properties.
static func _add_kept_row(dock: Object, content: Control, entity: Node3D, kept: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "EntityKept"
	content.add_child(row)
	dock._entity_props_controls.append(row)
	var wiring := CheckBox.new()
	wiring.name = "KeepWiring"
	wiring.text = "Keep wiring on this copy"
	wiring.tooltip_text = "Its outputs stay as this copy has them through a Pull"
	wiring.button_pressed = bool(kept["wiring"])
	wiring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wiring.toggled.connect(dock._on_entity_keep_wiring_toggled.bind(entity))
	row.add_child(wiring)
	var clear := Button.new()
	clear.name = "ClearKept"
	clear.text = "Clear Kept"
	clear.tooltip_text = "Keep nothing of this copy's own, and take the prefab's values again"
	clear.pressed.connect(dock._on_entity_clear_kept.bind(entity))
	row.add_child(clear)


static func on_entity_keep_toggled(
	dock: Object, keep: bool, entity: Node3D, prop_name: String
) -> void:
	if not can_edit_selected_entity(dock, entity):
		return
	var action := "Keep %s on This Copy" % prop_name if keep else "Stop Keeping %s" % prop_name
	dock._commit_state_action(action, "set_prefab_kept", [entity, prop_name, keep])


static func on_entity_keep_wiring_toggled(dock: Object, keep: bool, entity: Node3D) -> void:
	if not can_edit_selected_entity(dock, entity):
		return
	var action := "Keep Wiring on This Copy" if keep else "Stop Keeping Wiring"
	dock._commit_state_action(action, "set_prefab_wiring_kept", [entity, keep])


## The copy is rebuilt from its prefab, so the panel lets go of the node it shows.
## A copy with a locked piece is left as it is, and so is the history (#1977).
static func on_entity_clear_kept(dock: Object, entity: Node3D) -> void:
	if not can_edit_selected_entity(dock, entity):
		return
	if not dock._commit_state_action_if_changed("Clear Kept", "clear_prefab_kept", [entity]):
		return
	if dock.has_method("set_selection_nodes"):
		dock.set_selection_nodes([])


## Reset to Default and Write Defaults, for the entities the panel shows.
static func _add_defaults_row(dock: Object, content: Control, entities: Array) -> void:
	var row := HBoxContainer.new()
	row.name = "EntityDefaults"
	content.add_child(row)
	dock._entity_props_controls.append(row)
	var reset := Button.new()
	reset.name = "ResetToDefault"
	reset.text = "Reset to Default"
	reset.tooltip_text = "Put every property back to its class default"
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(dock._on_entity_reset_all.bind(entities))
	row.add_child(reset)
	var write := Button.new()
	write.name = "WriteDefaults"
	write.text = "Write Defaults"
	write.tooltip_text = (
		"Add the default of each property the class has and an entity is missing,"
		+ " leaving set ones alone"
	)
	write.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	write.pressed.connect(dock._on_entity_write_defaults.bind(entities))
	row.add_child(write)


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
	var scope := edit_scope(root, entity)
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
		scope["ids"],
		scope["paths"]
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
	pick.tooltip_text = HFTranslationType.t("Pick a {kind} file").format({"kind": resource_type})
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
	dialog.title = HFTranslationType.t("Pick {kind}").format({"kind": resource_type})
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
		var missing: String = (
			HFTranslationType.t("No sound at {path}").format({"path": path})
			if path != ""
			else HFTranslationType.t("Pick a sound first")
		)
		dock.show_toast(missing, 1)
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
			# Out of the panel now, so a row built in the same frame keeps its name.
			if ctrl.get_parent():
				ctrl.get_parent().remove_child(ctrl)
			ctrl.queue_free()
	dock._entity_props_controls.clear()
	if dock._entity_props_section:
		dock._entity_props_section.visible = false


## A value typed for several entities goes on each of `entities`, as one step.
static func on_entities_prop_changed(
	dock: Object, value: Variant, entities: Array, prop_name: String
) -> void:
	if not can_edit_entities(dock, entities):
		return
	_commit_entities(
		dock,
		"Set %s" % prop_name,
		"set_property_on_entities",
		[entities, prop_name, value],
		entities,
		"entity_multi_%s" % prop_name
	)


static func on_entities_prop_enum_changed(
	dock: Object, index: int, entities: Array, prop_name: String, enum_vals: Array
) -> void:
	if index >= 0 and index < enum_vals.size():
		on_entities_prop_changed(dock, enum_vals[index], entities, prop_name)


## One axis of a vector, each entity keeping its own other two.
static func on_entities_prop_vec3_changed(
	dock: Object, value: float, entities: Array, prop_name: String, axis_index: int
) -> void:
	if not can_edit_entities(dock, entities):
		return
	var pairs: Array = []
	for entity in entities:
		var vec := HFEntityPropUtils.vec3_with_axis(entity, prop_name, axis_index, value)
		pairs.append([entity, {prop_name: vec}])
	_commit_entities(
		dock,
		"Set %s" % prop_name,
		"set_properties_on_entities",
		[pairs],
		entities,
		"entity_multi_%s_%d" % [prop_name, axis_index]
	)


## Put each of `entities`' class defaults back, for `prop_names` or every
## property, as one step, and show the panel again.
static func reset_to_default(dock: Object, entities: Array, prop_names: Array) -> void:
	if not can_edit_entities(dock, entities):
		return
	var pairs := HFEntityMultiEdit.defaults_for(dock.entity_defs, entities, prop_names)
	if pairs.is_empty():
		return
	_commit_entities(dock, "Reset to Default", "set_properties_on_entities", [pairs], entities)
	_show_again(dock)


## Give each of `entities` the default of any property its class has and it is
## missing, leaving the ones it holds alone.
static func write_defaults(dock: Object, entities: Array) -> void:
	if not can_edit_entities(dock, entities):
		return
	var pairs := HFEntityMultiEdit.missing_defaults(dock.entity_defs, entities)
	if pairs.is_empty():
		dock.show_toast("Every property is written already", 0)
		return
	_commit_entities(dock, "Write Defaults", "set_properties_on_entities", [pairs], entities)
	_show_again(dock)


## Whether these entities, all of them selected, may be edited now.
static func can_edit_entities(dock: Object, entities: Array) -> bool:
	if dock == null or not dock.level_root or entities.is_empty():
		return false
	if not dock._guard_selection_action(
		"Edit Entity", _entity_requirement(dock, dock.DockSelectionRequirement.ENTITIES_ONLY)
	):
		return false
	for entity in entities:
		if not (entity is Node3D) or not is_instance_valid(entity):
			return false
		if not dock._selection_nodes.has(entity):
			return false
	return true


static func _commit_entities(
	dock: Object,
	action_name: String,
	method_name: String,
	args: Array,
	entities: Array,
	collation_tag: String = ""
) -> void:
	var root: Node = dock.level_root
	var ids: Array = []
	var paths: Array = []
	for entity in entities:
		var scope := edit_scope(root, entity)
		for brush_id in scope["ids"]:
			if not ids.has(brush_id):
				ids.append(brush_id)
		paths.append_array(scope["paths"])
	HFUndoHelper.commit(
		dock.undo_redo,
		root,
		action_name,
		method_name,
		args,
		false,
		Callable(dock, "record_history"),
		collation_tag,
		true,
		ids,
		paths
	)


## The panel again after a change it did not type, so the values it shows are
## the entities'.
static func _show_again(dock: Object) -> void:
	if dock.has_method("set_selection_nodes"):
		dock.set_selection_nodes(dock._selection_nodes.duplicate())


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
	var scope := edit_scope(root, entity)
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
		scope["ids"],
		scope["paths"]
	)


## What an Entity panel edit changes, for its undo step: every brush of a brush
## entity by id, since the edit goes on all of them (#1113), or a point entity by
## its path.
static func edit_scope(root: Node, entity: Node3D) -> Dictionary:
	if not HFEntityPropUtils.is_brush_entity(entity):
		return {"ids": [], "paths": [root.get_path_to(entity)]}
	var ids: Array = []
	for node in root.entity_property_nodes(entity):
		ids.append(str(node.get("brush_id")))
	return {"ids": ids, "paths": []}


static func can_edit_selected_entity(dock: Object, entity: Node3D) -> bool:
	if dock == null or not dock.level_root or not is_instance_valid(entity):
		return false
	if not dock._guard_selection_action(
		"Edit Entity", _entity_requirement(dock, dock.DockSelectionRequirement.ENTITIES_ONLY)
	):
		return false
	var editable: bool = (
		dock.level_root.is_entity_node(entity) or HFEntityPropUtils.is_brush_entity(entity)
	)
	return editable and dock._selection_nodes.has(entity)


## What an entity edit asks of the selection guard. A brush tied to an entity
## class is a brush to the guard, but its properties and wires are an entity's
## (#728), so a selection of point entities and tied brushes asks only that it is
## all HammerForge's (#1784). A plain brush in it is still refused by `requirement`.
static func _entity_requirement(dock: Object, requirement: int) -> int:
	for node in dock._selection_nodes:
		if not is_instance_valid(node):
			continue
		if dock.level_root.is_brush_node(node) and not HFEntityPropUtils.is_brush_entity(node):
			return requirement
	return dock.DockSelectionRequirement.MANAGED


## The first selected point entity or tied brush.
static func _first_entity_subject(dock: Object) -> Node:
	for node in dock._selection_nodes:
		if not is_instance_valid(node):
			continue
		if dock.level_root.is_entity_node(node) or HFEntityPropUtils.is_brush_entity(node):
			return node
	return null


## What an enum row shows for each value: the definition's labels when it has one
## for each value, as an FGD's choices do (#1721), or the values themselves.
static func enum_labels(prop: Dictionary) -> Array:
	var values: Array = prop.get("enum_values", [])
	var labels: Variant = prop.get("enum_labels", [])
	var out: Array = []
	for i in values.size():
		if labels is Array and (labels as Array).size() == values.size():
			out.append(str(labels[i]))
		else:
			out.append(str(values[i]))
	return out


## Where `value` is among `values`, by its text, since a `.map` brings every value
## in as text and a definition may write a number. -1 when it is not there.
static func enum_index(values: Array, value: Variant) -> int:
	for i in values.size():
		if str(values[i]) == str(value):
			return i
	return -1


## A box for each bit of a flags property, as an FGD's spawnflags (#1721). A tick
## sets that bit of the entity's value as it is now, as one undo step.
static func _add_flag_boxes(
	dock: Object, row: HBoxContainer, entity: Node3D, prop: Dictionary, value: int
) -> void:
	var boxes := HFlowContainer.new()
	boxes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(boxes)
	var bits: Array = prop.get("flag_values", [])
	var labels: Array = prop.get("flag_labels", [])
	for i in bits.size():
		var bit := int(bits[i])
		var box := CheckBox.new()
		box.text = str(labels[i]) if i < labels.size() else str(bit)
		box.tooltip_text = HFTranslationType.t("Bit {number}").format({"number": bit})
		box.button_pressed = (value & bit) != 0
		box.toggled.connect(
			func(on: bool): on_entity_flag_toggled(dock, on, entity, str(prop.get("name", "")), bit)
		)
		boxes.add_child(box)


static func on_entity_flag_toggled(
	dock: Object, on: bool, entity: Node3D, prop_name: String, bit: int
) -> void:
	if dock == null or not can_edit_selected_entity(dock, entity):
		return
	var now := int(HFEntityPropUtils.get_entity_data(entity).get(prop_name, 0))
	commit_entity_property(dock, entity, prop_name, (now | bit) if on else (now & ~bit))


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
		"Add Entity Output", _entity_requirement(dock, dock.DockSelectionRequirement.ENTITIES_ONLY)
	):
		return
	var entity = _first_entity_subject(dock)
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
	dock._set_status(
		HFTranslationType.t("Added output: {output} → {target}.{input}").format(
			{"output": output_name, "target": target_name, "input": input_name}
		)
	)


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
	dock._set_status(
		HFTranslationType.t("Wired: {output} → {target}.{input}").format(
			{"output": output_name, "target": target_name, "input": input_name}
		)
	)


static func on_wiring_preset_applied(
	dock: Object, _source: Node, preset_name: String, count: int
) -> void:
	if dock == null:
		return
	commit_wiring_change(dock, "Apply I/O Preset: %s" % preset_name)
	var applied := HFTranslationType.tn(
		"Applied preset '{preset}' ({count} connection)",
		"Applied preset '{preset}' ({count} connections)",
		count
	)
	dock._set_status(applied.format({"preset": preset_name, "count": count}))


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
