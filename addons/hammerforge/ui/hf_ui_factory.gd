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

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFBakeSplit = preload("../hf_bake_split.gd")
@warning_ignore_restore("shadowed_global_identifier")


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


## A row of buttons that wraps onto another line when the dock is narrow. An
## HBoxContainer of buttons is as wide as all of them together, and a dock tab
## cannot be narrower than its widest row. Give the buttons expand-fill so each
## line is filled evenly.
static func make_wrap_row() -> HFlowContainer:
	return HFlowContainer.new()


## Let a dropdown take the width it is given. By default an OptionButton is as
## wide as its longest entry, so one long entry set the dock's minimum width.
static func fit_option(opt: OptionButton) -> OptionButton:
	opt.fit_to_longest_item = false
	opt.clip_text = true
	opt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return opt


## Wrap a button's or a checkbox's text instead of letting it widen the dock.
static func wrap_text(button: Button) -> Button:
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


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


## A Cast Shadows dropdown: the four shadow casting settings, after Level Default
## when the control is a brush's or a visgroup's, which can leave the choice to
## the level (#1444). Each item carries its setting as metadata.
static func make_cast_shadow_option(with_level_default: bool) -> OptionButton:
	var opt := make_option()
	var values: Array[int] = []
	if with_level_default:
		values.append(HFBakeSplit.LEVEL_DEFAULT)
	values.append_array(HFBakeSplit.CAST_SHADOW_CHOICES)
	for value in values:
		opt.add_item(HFBakeSplit.cast_shadow_name(value))
		opt.set_item_metadata(opt.item_count - 1, value)
	return fit_option(opt)


## Show `value` on a dropdown from `make_cast_shadow_option()`, or nothing when it
## is not one of its settings, as when the brushes selected disagree.
static func select_cast_shadow(opt: OptionButton, value: int) -> void:
	for i in opt.item_count:
		if int(opt.get_item_metadata(i)) == value:
			opt.select(i)
			return
	opt.select(-1)


## The setting the item at `index` of such a dropdown stands for.
static func cast_shadow_at(opt: OptionButton, index: int) -> int:
	if index < 0 or index >= opt.item_count:
		return HFBakeSplit.LEVEL_DEFAULT
	return int(opt.get_item_metadata(index))
