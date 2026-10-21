@tool
extends VBoxContainer
class_name HFCollapsibleSection

## A reusable collapsible section for the HammerForge dock.
## Has a toggle header button and a content VBox that shows/hides.

signal toggled(expanded: bool)

var _separator: HSeparator
var _header: Button
var _content_margin: MarginContainer
var _content: VBoxContainer
var _expanded := true
var _section_name := ""
var _note := ""
var _fills_height := false


func _init(section_name: String = "", start_expanded: bool = true) -> void:
	_section_name = section_name
	_expanded = start_expanded


func _ready() -> void:
	_separator = HSeparator.new()
	add_child(_separator)

	_header = Button.new()
	_header.flat = true
	_header.focus_mode = Control.FOCUS_NONE
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.toggle_mode = true
	_header.button_pressed = _expanded
	# A note can be longer than the dock is wide: trim it rather than widen the dock.
	_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header.toggled.connect(_on_header_toggled)
	_update_header_text()
	add_child(_header)

	_content_margin = MarginContainer.new()
	_content_margin.name = "ContentMargin"
	_content_margin.add_theme_constant_override("margin_left", 4)
	_content_margin.visible = _expanded
	add_child(_content_margin)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content_margin.add_child(_content)
	_apply_height_flags()


static func create(section_name: String, start_expanded: bool = true) -> HFCollapsibleSection:
	var section = HFCollapsibleSection.new(section_name, start_expanded)
	section.name = section_name.replace(" ", "").replace("&", "And")
	return section


func get_content() -> VBoxContainer:
	return _content


func set_expanded(value: bool) -> void:
	_expanded = value
	if _content_margin:
		_content_margin.visible = _expanded
	if _header:
		_header.button_pressed = _expanded
		_update_header_text()
	_apply_height_flags()


func is_expanded() -> bool:
	return _expanded


func _on_header_toggled(pressed: bool) -> void:
	_expanded = pressed
	if _content_margin:
		_content_margin.visible = _expanded
	_update_header_text()
	_apply_height_flags()
	toggled.emit(_expanded)


## Let the content take the height its column has left, for a section whose
## content scrolls on its own: the material browser showed two rows of
## thumbnails however tall the dock was. Only while expanded, so a collapsed
## section does not push the ones under it to the bottom of the tab.
func set_fills_height(value: bool) -> void:
	_fills_height = value
	_apply_height_flags()


## A short line after the section's name, such as how many things it holds, so a
## status line does not cost a row of its own. It shows while collapsed too.
func set_note(text: String) -> void:
	_note = text
	_update_header_text()


func _apply_height_flags() -> void:
	var flags: int = Control.SIZE_FILL
	if _fills_height and _expanded:
		flags = Control.SIZE_EXPAND_FILL
	size_flags_vertical = flags
	if _content_margin:
		_content_margin.size_flags_vertical = flags
	if _content:
		_content.size_flags_vertical = flags


func _update_header_text() -> void:
	if not _header:
		return
	var arrow = "\u25bc " if _expanded else "\u25b6 "
	_header.text = arrow + _section_name
	if _note != "":
		_header.text += " \u00b7 " + _note
	_header.tooltip_text = _note
