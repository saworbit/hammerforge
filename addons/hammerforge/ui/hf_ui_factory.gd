@tool
class_name HFUIFactory
extends RefCounted
## Static factory for the repeated dock UI patterns (labeled rows, spinboxes,
## checkboxes, buttons, sections). Replaces the 100+ inline copies of
## `var row = HBoxContainer.new(); var lbl = Label.new(); ...` scattered
## across dock.gd and the tab builders.
##
## All methods return ready-to-add Control nodes. Callers add them to their
## parent container. Sizing flags default to expand-fill where useful.


static func make_label_row(
	label_text: String, control: Control, label_min_width: int = 0
) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	if label_min_width > 0:
		label.custom_minimum_size.x = label_min_width
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


static func make_spin(
	min_val: float, max_val: float, step_val: float, default_val: float
) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step_val
	spin.value = default_val
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


static func make_check(label_text: String, default_on: bool = false) -> CheckBox:
	var check := CheckBox.new()
	check.text = label_text
	check.button_pressed = default_on
	return check


static func make_button(label_text: String, tooltip: String = "") -> Button:
	var btn := Button.new()
	btn.text = label_text
	if tooltip != "":
		btn.tooltip_text = tooltip
	return btn


static func make_option(items: Array = []) -> OptionButton:
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		opt.add_item(str(item))
	return opt


static func make_separator() -> HSeparator:
	return HSeparator.new()


## Constructs a labeled SpinBox row in one call. Returns the row;
## the SpinBox is exposed via `row.get_child(1)` or callers can hold the
## SpinBox reference passed in.
static func make_spin_row(
	label_text: String, min_val: float, max_val: float, step_val: float, default_val: float
) -> HBoxContainer:
	var spin := make_spin(min_val, max_val, step_val, default_val)
	return make_label_row(label_text, spin)


static func make_section_header(title: String) -> Label:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 13)
	return lbl
