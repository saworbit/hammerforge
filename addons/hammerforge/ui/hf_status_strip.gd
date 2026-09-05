@tool
class_name HFStatusStrip
extends HBoxContainer
## The Console's overall lamp, parked in the 3D viewport toolbar.
##
## The Console lives on the main screen, which means it is not on screen while
## you are actually building. A dashboard you have to switch away from the work
## to read is a dashboard nobody reads, so the one thing worth glancing at —
## is anything wrong — stays beside the viewport, and clicking it opens the
## board that explains why.

const HFStatusBoardType = preload("../hf_status_board.gd")
const HFStatusLampType = preload("hf_status_lamp.gd")

## Slower than the Console's own beat. Nothing here is read closely, and unlike
## the Console's poll this one runs whether or not the Console is open.
const POLL_SECONDS := 2.0

signal console_requested

var _lamp: HFStatusLamp = null
var _button: Button = null
var _poll: Timer = null
var _base_control: Control = null
## Supplies the summary. The Console owns the evaluation, so the strip and the
## board can never disagree about what colour the level is.
var _source = null


func _init() -> void:
	name = "HFStatusStrip"
	add_theme_constant_override("separation", 3)

	_lamp = HFStatusLampType.new()
	_lamp.custom_minimum_size = Vector2(13, 13)
	_lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_lamp)

	_button = Button.new()
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.text = "HammerForge"
	_button.add_theme_font_size_override("font_size", 11)
	_button.pressed.connect(func(): console_requested.emit())
	add_child(_button)

	_poll = Timer.new()
	_poll.wait_time = POLL_SECONDS
	_poll.autostart = true
	_poll.timeout.connect(refresh)
	add_child(_poll)


func _ready() -> void:
	refresh()


## Point the strip at the Console panel, which owns the evaluation.
func set_source(source) -> void:
	_source = source
	refresh()


func set_theme_source(base_control: Control) -> void:
	_base_control = base_control
	if _lamp:
		_lamp.theme_source = base_control
	refresh()


func refresh() -> void:
	if _source == null or not is_instance_valid(_source):
		return
	if not _source.has_method("compute_summary"):
		return
	var summary: Dictionary = _source.compute_summary()
	var severity := int(summary.get("severity", HFStatusBoardType.Severity.UNKNOWN))
	if _lamp:
		_lamp.severity = severity
	var label := str(summary.get("label", ""))
	if _button.text != label:
		_button.text = label
	_button.add_theme_color_override(
		"font_color", HFStatusLampType.color_for(severity, _base_control)
	)
	_button.tooltip_text = (
		"HammerForge: %s. Click to open the Console.\n%d fine, %d to review, %d problem(s)."
		% [
			label,
			int(summary.get("ok", 0)),
			int(summary.get("warn", 0)),
			int(summary.get("problem", 0)),
		]
	)
