@tool
extends RefCounted
## Builds the Entity I/O section and Entity Properties section in the Entities tab.
## Extracted from dock.gd — purely organizational, no behavior changes.

const HFIOWiringPanelType = preload("hf_io_wiring_panel.gd")
const HFUIFactoryType = preload("hf_ui_factory.gd")


# Helper: build a labeled-LineEdit row used by the I/O fields.
static func _make_lineedit_row(label_text: String, placeholder: String) -> Array:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 70
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return [row, edit]


var dock  # HammerForgeDock reference


func _init(p_dock) -> void:
	dock = p_dock


func build(parent: Control) -> void:
	var entities_vbox = parent
	if not entities_vbox:
		return

	var hf_collapsible_section = dock.HFCollapsibleSection

	# --- Entity Properties section (above I/O) ---
	var prop_sec = hf_collapsible_section.create("Entity Properties", true)
	entities_vbox.add_child(prop_sec)
	dock._register_section(prop_sec, "Entity Properties")
	prop_sec.visible = false
	dock._entity_props_section = prop_sec

	# --- Entity I/O section (hidden until entity selected) ---
	var io_sec = hf_collapsible_section.create("Entity I/O", false)
	entities_vbox.add_child(io_sec)
	dock._register_section(io_sec, "Entity I/O")
	io_sec.visible = false
	dock._entity_io_section = io_sec
	var ioc = io_sec.get_content()

	var out_pair = _make_lineedit_row("Output:", "OnTrigger")
	ioc.add_child(out_pair[0])
	dock.io_output_name = out_pair[1]

	var tgt_pair = _make_lineedit_row("Target:", "door_1")
	ioc.add_child(tgt_pair[0])
	dock.io_target_name = tgt_pair[1]

	var inp_pair = _make_lineedit_row("Input:", "Open")
	ioc.add_child(inp_pair[0])
	dock.io_input_name = inp_pair[1]

	var param_pair = _make_lineedit_row("Param:", "(optional)")
	ioc.add_child(param_pair[0])
	dock.io_parameter = param_pair[1]

	# Delay + Fire Once row
	var delay_row = HBoxContainer.new()
	ioc.add_child(delay_row)
	var delay_lbl = Label.new()
	delay_lbl.text = "Delay:"
	delay_lbl.custom_minimum_size.x = 70
	delay_row.add_child(delay_lbl)
	dock.io_delay = HFUIFactoryType.make_spin(0.0, 999.0, 0.1, 0.0)
	dock.io_delay.suffix = "s"
	delay_row.add_child(dock.io_delay)
	dock.io_fire_once = HFUIFactoryType.make_check("Once")
	delay_row.add_child(dock.io_fire_once)

	# Add / Remove buttons
	var io_btn_row = HBoxContainer.new()
	ioc.add_child(io_btn_row)
	dock.io_add_btn = HFUIFactoryType.make_button("Add Output")
	dock.io_add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	io_btn_row.add_child(dock.io_add_btn)
	dock.io_remove_btn = HFUIFactoryType.make_button("Remove")
	io_btn_row.add_child(dock.io_remove_btn)

	# Connection list
	var list_lbl = Label.new()
	list_lbl.text = "Connections:"
	ioc.add_child(list_lbl)
	dock.io_list = ItemList.new()
	dock.io_list.custom_minimum_size.y = 80
	dock.io_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.io_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ioc.add_child(dock.io_list)

	# --- I/O Wiring Panel section (collapsed & hidden until entity selected) ---
	var wire_sec = hf_collapsible_section.create("I/O Wiring", false)
	entities_vbox.add_child(wire_sec)
	dock._register_section(wire_sec, "I/O Wiring")
	wire_sec.visible = false
	dock._io_wiring_section = wire_sec
	var wire_content = wire_sec.get_content()

	dock._io_wiring_panel = HFIOWiringPanelType.new()
	wire_content.add_child(dock._io_wiring_panel)


func connect_signals() -> void:
	if dock.io_add_btn:
		dock.io_add_btn.pressed.connect(dock._on_io_add)
	if dock.io_remove_btn:
		dock.io_remove_btn.pressed.connect(dock._on_io_remove)
	if dock._io_wiring_panel:
		dock._io_wiring_panel.connection_added.connect(dock._on_wiring_connection_added)
		dock._io_wiring_panel.preset_applied.connect(dock._on_wiring_preset_applied)
		dock._io_wiring_panel.highlight_toggled.connect(dock._on_wiring_highlight_toggled)
