@tool
extends VBoxContainer
class_name HFCollapsibleSection

## A reusable collapsible section for the HammerForge dock.
## Has a toggle header button and a content VBox that shows/hides.

signal toggled(expanded: bool)

var _header: Button
var _content: VBoxContainer
var _expanded := true
var _section_name := ""


func _init(section_name: String = "", start_expanded: bool = true) -> void:
	_section_name = section_name
	_expanded = start_expanded


func _ready() -> void:
	_header = Button.new()
	_header.flat = true
	_header.focus_mode = Control.FOCUS_NONE
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.toggle_mode = true
	_header.button_pressed = _expanded
	_header.toggled.connect(_on_header_toggled)
	_update_header_text()
	add_child(_header)
	move_child(_header, 0)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.visible = _expanded
	add_child(_content)


static func create(section_name: String, start_expanded: bool = true) -> HFCollapsibleSection:
	var section = HFCollapsibleSection.new(section_name, start_expanded)
	section.name = section_name.replace(" ", "").replace("&", "And")
	return section


func get_content() -> VBoxContainer:
	return _content


func set_expanded(value: bool) -> void:
	_expanded = value
	if _content:
		_content.visible = _expanded
	if _header:
		_header.button_pressed = _expanded
		_update_header_text()


func is_expanded() -> bool:
	return _expanded


func _on_header_toggled(pressed: bool) -> void:
	_expanded = pressed
	if _content:
		_content.visible = _expanded
	_update_header_text()
	toggled.emit(_expanded)


func _update_header_text() -> void:
	if not _header:
		return
	var arrow = "\u25bc " if _expanded else "\u25b6 "
	_header.text = arrow + _section_name
