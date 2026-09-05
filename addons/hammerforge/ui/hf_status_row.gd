@tool
class_name HFStatusRow
extends PanelContainer
## One line of the Console's status board: lamp, what was measured, what it
## means, and the single button that resolves it.
##
## Rows are built once and refreshed in place. Rebuilding them on every poll
## would drop the tooltip the reader is mid-way through reading, and would take
## focus off the action button under their cursor.

const HFStatusBoardType = preload("../hf_status_board.gd")
const HFStatusLampType = preload("hf_status_lamp.gd")

signal action_requested(action_id: String)

var check_id: String = ""

var _lamp: HFStatusLamp = null
var _title: Label = null
var _value: Label = null
var _detail: Label = null
var _action: Button = null
var _action_id: String = ""
var _theme_source: Control = null
## The board refreshes once a second. Rebuilding the stylebox and re-applying
## the colour overrides on every one of those passes allocates for nothing, so
## the styling work only runs when what it depends on has actually moved.
var _styled_severity: int = -1
var _styled_theme: Control = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	_lamp = HFStatusLampType.new()
	_lamp.custom_minimum_size = Vector2(18, 18)
	_lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_lamp)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 1)
	row.add_child(text_column)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	text_column.add_child(heading)

	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)

	_value = Label.new()
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(_value)

	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 11)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_child(_detail)

	_action = Button.new()
	_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action.visible = false
	_action.pressed.connect(_on_action_pressed)
	row.add_child(_action)


## Point the row at a check row from HFStatusBoard.evaluate().
func apply_check(check: Dictionary, base_control: Control = null) -> void:
	check_id = str(check.get("id", ""))
	_theme_source = base_control
	var severity := int(check.get("severity", HFStatusBoardType.Severity.UNKNOWN))

	_lamp.theme_source = base_control
	_lamp.severity = severity

	_set_text(_title, str(check.get("title", "")))
	_set_text(_value, str(check.get("value", "")))
	_set_text(_detail, str(check.get("detail", "")))

	if severity != _styled_severity or base_control != _styled_theme:
		_restyle(severity, base_control)

	_action_id = str(check.get("action_id", ""))
	var action_label := str(check.get("action_label", ""))
	_action.visible = _action_id != "" and action_label != ""
	if _action.visible:
		_set_button_text(_action, action_label)

	# The reader should be able to hover anywhere on the row and learn what the
	# check measures, including over the lamp and the value.
	var help := str(check.get("help", ""))
	var tooltip := ""
	if help != "":
		tooltip = "%s — %s" % [HFStatusBoardType.severity_label(severity), help]
	tooltip_text = tooltip
	_title.tooltip_text = tooltip
	_value.tooltip_text = tooltip
	_detail.tooltip_text = tooltip


## Repaint against a new editor theme without changing what the row says.
func refresh_theme(base_control: Control) -> void:
	_theme_source = base_control
	_lamp.theme_source = base_control
	_lamp.queue_redraw()
	_restyle(_lamp.severity, base_control)


func _restyle(severity: int, base_control: Control) -> void:
	_styled_severity = severity
	_styled_theme = base_control
	_value.add_theme_color_override(
		"font_color", HFStatusLampType.color_for(severity, base_control)
	)
	_detail.add_theme_color_override("font_color", HFThemeUtils.muted_text(base_control))
	_apply_background(severity, base_control)


## A tint only on rows that need attention. Tinting every row would turn the
## board into stripes and cost the amber and red rows the contrast that makes
## them findable at a glance.
func _apply_background(severity: int, base_control: Control) -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	if (
		severity == HFStatusBoardType.Severity.WARN
		or severity == HFStatusBoardType.Severity.PROBLEM
	):
		var accent := HFStatusLampType.color_for(severity, base_control)
		style.bg_color = Color(accent, 0.09)
		style.border_width_left = 3
		style.border_color = Color(accent, 0.8)
	else:
		style.bg_color = Color(0, 0, 0, 0)
		style.border_width_left = 3
		style.border_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", style)


func _on_action_pressed() -> void:
	if _action_id != "":
		action_requested.emit(_action_id)


static func _set_text(label: Label, text: String) -> void:
	if label and label.text != text:
		label.text = text


static func _set_button_text(button: Button, text: String) -> void:
	if button and button.text != text:
		button.text = text
