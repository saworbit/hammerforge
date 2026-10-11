@tool
class_name HFMcpPanel
extends VBoxContainer
## The Test tab's Agent Bridge section: one box to let an MCP agent in, a lamp,
## and a line saying what the bridge is doing.
##
## It only asks. `enable_toggled` goes to the plugin, which starts or stops the
## listener and reports back through `set_state()`. A failed start unticks the
## box here, so the box never claims a bridge that is not running.

signal enable_toggled(enabled: bool)

const HFStatusLampType = preload("hf_status_lamp.gd")
const HFStatusBoardType = preload("../hf_status_board.gd")
const HFMcpListenerType = preload("../mcp/hf_mcp_listener.gd")

const HELP_TEXT := (
	"Lets an MCP agent build in the open level through hammerforge-mcp."
	+ " Loopback only, a new token each time, and off again when the editor restarts."
)

var enable_check: CheckBox
var lamp: HFStatusLampType
var status_label: Label
var help_label: Label


func _init() -> void:
	name = "McpPanel"
	enable_check = CheckBox.new()
	enable_check.name = "AllowAgentConnections"
	enable_check.text = "Allow agent connections (MCP)"
	enable_check.tooltip_text = HELP_TEXT
	enable_check.toggled.connect(_on_toggled)
	add_child(enable_check)

	var row := HBoxContainer.new()
	row.name = "Status"
	lamp = HFStatusLampType.new()
	lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lamp)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	row.add_child(status_label)
	add_child(row)

	help_label = Label.new()
	help_label.text = HELP_TEXT
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.add_theme_font_size_override("font_size", 11)
	add_child(help_label)

	set_state(HFMcpListenerType.State.OFF, "Off")


func is_enabled() -> bool:
	return enable_check.button_pressed


func set_theme_source(base: Control) -> void:
	lamp.theme_source = base


## Show what the listener reports. Grey when off, amber while it waits for an
## agent, green with one connected, red when it could not start.
func set_state(state: int, detail: String) -> void:
	status_label.text = detail
	status_label.tooltip_text = detail
	match state:
		HFMcpListenerType.State.LISTENING:
			lamp.severity = HFStatusBoardType.Severity.WARN
		HFMcpListenerType.State.CONNECTED, HFMcpListenerType.State.RUNNING:
			lamp.severity = HFStatusBoardType.Severity.OK
		HFMcpListenerType.State.FAILED:
			lamp.severity = HFStatusBoardType.Severity.PROBLEM
		_:
			lamp.severity = HFStatusBoardType.Severity.UNKNOWN
	if state == HFMcpListenerType.State.OFF or state == HFMcpListenerType.State.FAILED:
		enable_check.set_pressed_no_signal(false)


func _on_toggled(pressed: bool) -> void:
	enable_toggled.emit(pressed)
