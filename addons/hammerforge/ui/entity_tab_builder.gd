@tool
extends RefCounted
## Builds the Entity I/O section and Entity Properties section in the Entities tab.
## Extracted from dock.gd — purely organizational, no behavior changes.

var dock  # HammerForgeDock reference


func _init(p_dock) -> void:
	dock = p_dock


func build(parent: Control) -> void:
	var entities_vbox = parent
	if not entities_vbox:
		return

	var HFCollapsibleSection = dock.HFCollapsibleSection

	# --- Entity Properties section (above I/O) ---
	var prop_sec = HFCollapsibleSection.create("Entity Properties", true)
	entities_vbox.add_child(prop_sec)
	dock._register_section(prop_sec, "Entity Properties")
	prop_sec.visible = false
	dock._entity_props_section = prop_sec

	# --- Entity I/O section ---
	var io_sec = HFCollapsibleSection.create("Entity I/O", false)
	entities_vbox.add_child(io_sec)
	dock._register_section(io_sec, "Entity I/O")
	var ioc = io_sec.get_content()

	# Output Name
	var out_row = HBoxContainer.new()
	ioc.add_child(out_row)
	var out_lbl = Label.new()
	out_lbl.text = "Output:"
	out_lbl.custom_minimum_size.x = 70
	out_row.add_child(out_lbl)
	dock.io_output_name = LineEdit.new()
	dock.io_output_name.placeholder_text = "OnTrigger"
	dock.io_output_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_row.add_child(dock.io_output_name)

	# Target Name
	var tgt_row = HBoxContainer.new()
	ioc.add_child(tgt_row)
	var tgt_lbl = Label.new()
	tgt_lbl.text = "Target:"
	tgt_lbl.custom_minimum_size.x = 70
	tgt_row.add_child(tgt_lbl)
	dock.io_target_name = LineEdit.new()
	dock.io_target_name.placeholder_text = "door_1"
	dock.io_target_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tgt_row.add_child(dock.io_target_name)

	# Input Name
	var inp_row = HBoxContainer.new()
	ioc.add_child(inp_row)
	var inp_lbl = Label.new()
	inp_lbl.text = "Input:"
	inp_lbl.custom_minimum_size.x = 70
	inp_row.add_child(inp_lbl)
	dock.io_input_name = LineEdit.new()
	dock.io_input_name.placeholder_text = "Open"
	dock.io_input_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inp_row.add_child(dock.io_input_name)

	# Parameter
	var param_row = HBoxContainer.new()
	ioc.add_child(param_row)
	var param_lbl = Label.new()
	param_lbl.text = "Param:"
	param_lbl.custom_minimum_size.x = 70
	param_row.add_child(param_lbl)
	dock.io_parameter = LineEdit.new()
	dock.io_parameter.placeholder_text = "(optional)"
	dock.io_parameter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	param_row.add_child(dock.io_parameter)

	# Delay + Fire Once row
	var delay_row = HBoxContainer.new()
	ioc.add_child(delay_row)
	var delay_lbl = Label.new()
	delay_lbl.text = "Delay:"
	delay_lbl.custom_minimum_size.x = 70
	delay_row.add_child(delay_lbl)
	dock.io_delay = SpinBox.new()
	dock.io_delay.min_value = 0.0
	dock.io_delay.max_value = 999.0
	dock.io_delay.step = 0.1
	dock.io_delay.value = 0.0
	dock.io_delay.suffix = "s"
	dock.io_delay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delay_row.add_child(dock.io_delay)
	dock.io_fire_once = CheckBox.new()
	dock.io_fire_once.text = "Once"
	delay_row.add_child(dock.io_fire_once)

	# Add / Remove buttons
	var io_btn_row = HBoxContainer.new()
	ioc.add_child(io_btn_row)
	dock.io_add_btn = dock._make_button("Add Output")
	dock.io_add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	io_btn_row.add_child(dock.io_add_btn)
	dock.io_remove_btn = dock._make_button("Remove")
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


func connect_signals() -> void:
	if dock.io_add_btn:
		dock.io_add_btn.pressed.connect(dock._on_io_add)
	if dock.io_remove_btn:
		dock.io_remove_btn.pressed.connect(dock._on_io_remove)
