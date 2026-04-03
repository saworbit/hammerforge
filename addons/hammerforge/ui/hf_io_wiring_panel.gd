@tool
extends VBoxContainer
class_name HFIOWiringPanel

## Visual I/O wiring panel — shows source entity's outputs as draggable ports,
## available targets as drop zones, and a preset picker for quick wiring.
## Embedded in the Entities tab when an entity is selected.

signal connection_added(
	source: Node,
	output_name: String,
	target_name: String,
	input_name: String,
	parameter: String,
	delay: float,
	fire_once: bool
)
signal connection_removed(source: Node, index: int)
signal preset_applied(source: Node, preset_name: String, count: int)
signal highlight_toggled(enabled: bool)

var _source_entity: Node = null
var _entity_system = null  # HFEntitySystem
var _io_presets = null  # HFIOPresets
var _io_visualizer = null  # HFIOVisualizer

# UI elements
var _header_label: Label
var _summary_label: Label
var _highlight_btn: Button
var _outputs_list: ItemList
var _targets_list: ItemList
var _preset_option: OptionButton
var _preset_apply_btn: Button
var _preset_save_btn: Button
var _target_map_container: VBoxContainer
var _target_map_edits: Dictionary = {}  # tag -> LineEdit
var _wire_btn: Button
var _wire_output: LineEdit
var _wire_target: OptionButton
var _wire_input: LineEdit
var _wire_param: LineEdit
var _wire_delay: SpinBox
var _wire_once: CheckBox


func _ready() -> void:
	_build_ui()


func setup(entity_system, io_presets, io_visualizer) -> void:
	_entity_system = entity_system
	_io_presets = io_presets
	_io_visualizer = io_visualizer


func set_source_entity(entity: Node) -> void:
	_source_entity = entity
	_refresh()
	_sync_highlight_button()


## Sync highlight button pressed state from the authoritative visualizer.
func _sync_highlight_button() -> void:
	if _highlight_btn and _io_visualizer:
		var current: bool = _io_visualizer.highlight_connected
		if _highlight_btn.button_pressed != current:
			_highlight_btn.set_pressed_no_signal(current)


func _build_ui() -> void:
	# --- Header ---
	var header_row = HBoxContainer.new()
	add_child(header_row)

	_header_label = Label.new()
	_header_label.text = "I/O Wiring"
	_header_label.add_theme_font_size_override("font_size", 13)
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_header_label)

	_highlight_btn = Button.new()
	_highlight_btn.text = "Highlight"
	_highlight_btn.tooltip_text = "Toggle Highlight Connected — pulse linked entities"
	_highlight_btn.toggle_mode = true
	_highlight_btn.flat = true
	_highlight_btn.focus_mode = Control.FOCUS_NONE
	_highlight_btn.add_theme_font_size_override("font_size", 11)
	_highlight_btn.toggled.connect(_on_highlight_toggled)
	header_row.add_child(_highlight_btn)

	# --- Connection summary ---
	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 11)
	_summary_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.8))
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_summary_label)

	# --- Current outputs ---
	var out_lbl = Label.new()
	out_lbl.text = "Outputs:"
	out_lbl.add_theme_font_size_override("font_size", 11)
	add_child(out_lbl)

	_outputs_list = ItemList.new()
	_outputs_list.custom_minimum_size.y = 60
	_outputs_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outputs_list.allow_reselect = true
	add_child(_outputs_list)

	# --- Quick wire section ---
	var wire_sep = HSeparator.new()
	add_child(wire_sep)

	var wire_lbl = Label.new()
	wire_lbl.text = "Quick Wire:"
	wire_lbl.add_theme_font_size_override("font_size", 11)
	add_child(wire_lbl)

	# Output name
	var row1 = HBoxContainer.new()
	add_child(row1)
	var r1_lbl = Label.new()
	r1_lbl.text = "Out:"
	r1_lbl.custom_minimum_size.x = 45
	row1.add_child(r1_lbl)
	_wire_output = LineEdit.new()
	_wire_output.placeholder_text = "OnTrigger"
	_wire_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_wire_output)

	# Target entity (dropdown of available entities)
	var row2 = HBoxContainer.new()
	add_child(row2)
	var r2_lbl = Label.new()
	r2_lbl.text = "To:"
	r2_lbl.custom_minimum_size.x = 45
	row2.add_child(r2_lbl)
	_wire_target = OptionButton.new()
	_wire_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_wire_target)

	# Input name
	var row3 = HBoxContainer.new()
	add_child(row3)
	var r3_lbl = Label.new()
	r3_lbl.text = "In:"
	r3_lbl.custom_minimum_size.x = 45
	row3.add_child(r3_lbl)
	_wire_input = LineEdit.new()
	_wire_input.placeholder_text = "Open"
	_wire_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_wire_input)

	# Param + delay + once row
	var row4 = HBoxContainer.new()
	add_child(row4)
	_wire_param = LineEdit.new()
	_wire_param.placeholder_text = "param"
	_wire_param.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wire_param.custom_minimum_size.x = 50
	row4.add_child(_wire_param)
	_wire_delay = SpinBox.new()
	_wire_delay.min_value = 0.0
	_wire_delay.max_value = 999.0
	_wire_delay.step = 0.1
	_wire_delay.suffix = "s"
	_wire_delay.custom_minimum_size.x = 65
	row4.add_child(_wire_delay)
	_wire_once = CheckBox.new()
	_wire_once.text = "1x"
	_wire_once.tooltip_text = "Fire once"
	row4.add_child(_wire_once)

	# Wire button
	_wire_btn = Button.new()
	_wire_btn.text = "Wire Connection"
	_wire_btn.tooltip_text = "Add this output → target.input connection"
	_wire_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wire_btn.pressed.connect(_on_wire_pressed)
	add_child(_wire_btn)

	# --- Preset section ---
	var preset_sep = HSeparator.new()
	add_child(preset_sep)

	var preset_lbl = Label.new()
	preset_lbl.text = "Connection Presets:"
	preset_lbl.add_theme_font_size_override("font_size", 11)
	add_child(preset_lbl)

	var preset_row = HBoxContainer.new()
	add_child(preset_row)
	_preset_option = OptionButton.new()
	_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_option.item_selected.connect(_on_preset_selected)
	preset_row.add_child(_preset_option)

	_preset_apply_btn = Button.new()
	_preset_apply_btn.text = "Apply"
	_preset_apply_btn.tooltip_text = "Apply selected preset to this entity"
	_preset_apply_btn.pressed.connect(_on_preset_apply)
	preset_row.add_child(_preset_apply_btn)

	_preset_save_btn = Button.new()
	_preset_save_btn.text = "Save"
	_preset_save_btn.tooltip_text = "Save this entity's connections as a new preset"
	_preset_save_btn.pressed.connect(_on_preset_save)
	preset_row.add_child(_preset_save_btn)

	# Target mapping area (shown when preset has tags)
	_target_map_container = VBoxContainer.new()
	add_child(_target_map_container)


func _refresh() -> void:
	_refresh_outputs()
	_refresh_target_dropdown()
	_refresh_summary()
	_refresh_presets()


func _refresh_outputs() -> void:
	if not _outputs_list:
		return
	_outputs_list.clear()
	if not _source_entity or not _entity_system:
		return
	var outputs = _entity_system.get_entity_outputs(_source_entity)
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
			label += " [1x]"
		_outputs_list.add_item(label)


func _refresh_target_dropdown() -> void:
	if not _wire_target:
		return
	_wire_target.clear()
	if not _entity_system or not _entity_system.root:
		return
	var entities_node = _entity_system.root.entities_node
	if not entities_node:
		return
	for child in entities_node.get_children():
		if not is_instance_valid(child):
			continue
		if child == _source_entity:
			_wire_target.add_item("%s (self)" % child.name)
		else:
			_wire_target.add_item(child.name)
	# Also list brush entities
	var brushes_node = _entity_system.root.draft_brushes_node
	if brushes_node:
		for child in brushes_node.get_children():
			if is_instance_valid(child):
				_wire_target.add_item(child.name)


func _refresh_summary() -> void:
	if not _summary_label:
		return
	if not _source_entity or not _io_visualizer:
		_summary_label.text = ""
		return
	var summary = _io_visualizer.get_connection_summary(_source_entity.name)
	var triggers: int = summary.get("triggers", 0)
	var triggered_by: int = summary.get("triggered_by", 0)
	var target_names: Array = summary.get("target_names", [])
	var source_names: Array = summary.get("source_names", [])
	var parts: Array = []
	if triggers > 0:
		(
			parts
			. append(
				(
					"Triggers %d target%s (%s)"
					% [
						triggers,
						"" if triggers == 1 else "s",
						", ".join(target_names.slice(0, 4)),
					]
				)
			)
		)
	if triggered_by > 0:
		(
			parts
			. append(
				(
					"Triggered by %d source%s (%s)"
					% [
						triggered_by,
						"" if triggered_by == 1 else "s",
						", ".join(source_names.slice(0, 4)),
					]
				)
			)
		)
	if parts.is_empty():
		_summary_label.text = "No connections"
	else:
		_summary_label.text = " | ".join(parts)


func _refresh_presets() -> void:
	if not _preset_option:
		return
	_preset_option.clear()
	if not _io_presets:
		return
	var presets = _io_presets.get_all_presets()
	for p in presets:
		var name_str: String = str(p.get("name", ""))
		var builtin: bool = bool(p.get("builtin", false))
		if builtin:
			_preset_option.add_item(name_str + " [built-in]")
		else:
			_preset_option.add_item(name_str)
	_update_target_map_ui()


func _on_highlight_toggled(pressed: bool) -> void:
	highlight_toggled.emit(pressed)


func _on_wire_pressed() -> void:
	if not _source_entity or not _entity_system:
		return
	var output_name = _wire_output.text.strip_edges()
	if output_name == "":
		return
	var target_idx = _wire_target.selected
	if target_idx < 0:
		return
	var target_text: String = _wire_target.get_item_text(target_idx)
	# Strip " (self)" suffix
	var target_name = target_text.replace(" (self)", "")
	var input_name = _wire_input.text.strip_edges()
	if input_name == "":
		return
	var parameter = _wire_param.text.strip_edges()
	var delay = _wire_delay.value
	var fire_once = _wire_once.button_pressed
	_entity_system.add_entity_output(
		_source_entity, output_name, target_name, input_name, parameter, delay, fire_once
	)
	connection_added.emit(
		_source_entity, output_name, target_name, input_name, parameter, delay, fire_once
	)
	_refresh()


func _on_preset_selected(index: int) -> void:
	_update_target_map_ui()


func _on_preset_apply() -> void:
	if not _source_entity or not _io_presets:
		return
	var presets = _io_presets.get_all_presets()
	var idx = _preset_option.selected
	if idx < 0 or idx >= presets.size():
		return
	var preset = presets[idx]
	# Build target map from LineEdits
	var target_map: Dictionary = {}
	for tag in _target_map_edits:
		var edit: LineEdit = _target_map_edits[tag]
		if edit and edit.text.strip_edges() != "":
			target_map[tag] = edit.text.strip_edges()
	var count = _io_presets.apply_preset(_source_entity, preset, target_map)
	if count > 0:
		preset_applied.emit(_source_entity, str(preset.get("name", "")), count)
		_refresh()


func _on_preset_save() -> void:
	if not _source_entity or not _io_presets:
		return
	var entity_name: String = _source_entity.name
	var preset_name = "From %s" % entity_name
	var ok = _io_presets.save_entity_as_preset(_source_entity, preset_name)
	if ok:
		_refresh_presets()


func _update_target_map_ui() -> void:
	# Clear existing map editors
	for child in _target_map_container.get_children():
		_target_map_container.remove_child(child)
		child.queue_free()
	_target_map_edits.clear()

	if not _io_presets or not _preset_option:
		return
	var presets = _io_presets.get_all_presets()
	var idx = _preset_option.selected
	if idx < 0 or idx >= presets.size():
		return
	var preset = presets[idx]
	var tags = _io_presets.get_preset_target_tags(preset)
	if tags.is_empty():
		return

	var map_lbl = Label.new()
	map_lbl.text = "Map targets:"
	map_lbl.add_theme_font_size_override("font_size", 10)
	map_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 0.8))
	_target_map_container.add_child(map_lbl)

	for tag in tags:
		var row = HBoxContainer.new()
		_target_map_container.add_child(row)
		var lbl = Label.new()
		lbl.text = "%s:" % tag
		lbl.custom_minimum_size.x = 70
		lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(lbl)
		var edit = LineEdit.new()
		edit.placeholder_text = "entity_name"
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)
		_target_map_edits[tag] = edit
