@tool
extends VBoxContainer
## Example level library browser for the Manage tab.
##
## Lists built-in demo levels with descriptions, difficulty badges,
## and "Study This" annotations. Provides Load button to instantiate
## brushes/entities into the current LevelRoot.

signal load_requested(example_id: String)

const EXAMPLES_PATH := "res://addons/hammerforge/data/example_levels.json"

const DIFFICULTY_COLORS := {
	"Beginner": Color(0.3, 0.8, 0.4, 0.9),
	"Intermediate": Color(0.9, 0.7, 0.2, 0.9),
	"Advanced": Color(0.9, 0.35, 0.3, 0.9),
}

var _examples: Array = []
var _cards_container: VBoxContainer
var _search_field: LineEdit
var _annotation_panel: PanelContainer
var _annotation_list: VBoxContainer
var _selected_id := ""


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build_ui()
	_load_examples()


func _build_ui() -> void:
	# Search
	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Search examples..."
	_search_field.clear_button_enabled = true
	_search_field.text_changed.connect(_on_search_changed)
	add_child(_search_field)

	# Cards container
	_cards_container = VBoxContainer.new()
	_cards_container.add_theme_constant_override("separation", 4)
	add_child(_cards_container)

	# Annotation panel (shown when "Study This" is clicked)
	_annotation_panel = PanelContainer.new()
	_annotation_panel.visible = false
	var ann_style = StyleBoxFlat.new()
	ann_style.bg_color = Color(0.1, 0.15, 0.2, 0.9)
	ann_style.set_corner_radius_all(4)
	ann_style.content_margin_left = 8
	ann_style.content_margin_right = 8
	ann_style.content_margin_top = 6
	ann_style.content_margin_bottom = 6
	_annotation_panel.add_theme_stylebox_override("panel", ann_style)
	add_child(_annotation_panel)

	_annotation_list = VBoxContainer.new()
	_annotation_list.add_theme_constant_override("separation", 4)
	_annotation_panel.add_child(_annotation_list)


func _load_examples() -> void:
	_examples.clear()
	if not FileAccess.file_exists(EXAMPLES_PATH):
		push_warning("HFExampleLibrary: examples file not found at %s" % EXAMPLES_PATH)
		return
	var file = FileAccess.open(EXAMPLES_PATH, FileAccess.READ)
	if not file:
		return
	var text = file.get_as_text()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary and parsed.has("examples"):
		_examples = parsed["examples"]
	_rebuild_cards()


func _rebuild_cards() -> void:
	for child in _cards_container.get_children():
		child.queue_free()

	for example in _examples:
		var card := _create_card(example)
		_cards_container.add_child(card)


func _create_card(example: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.name = "card_" + example.get("id", "unknown")
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.17, 0.22, 0.85)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# Title row
	var title_row = HBoxContainer.new()
	vbox.add_child(title_row)

	var title = Label.new()
	title.text = example.get("title", "Untitled")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	# Difficulty badge
	var difficulty: String = example.get("difficulty", "Beginner")
	var badge = Label.new()
	badge.text = " %s " % difficulty
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color", DIFFICULTY_COLORS.get(difficulty, Color.WHITE))
	title_row.add_child(badge)

	# Description
	var desc = Label.new()
	desc.text = example.get("description", "")
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75, 0.85))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	# Tags
	var tags: Array = example.get("tags", [])
	if not tags.is_empty():
		var tag_label = Label.new()
		var tag_parts: PackedStringArray = []
		for tag in tags:
			tag_parts.append(str(tag))
		tag_label.text = "Tags: " + ", ".join(tag_parts)
		tag_label.add_theme_font_size_override("font_size", 9)
		tag_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65, 0.7))
		vbox.add_child(tag_label)

	# Buttons
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	var load_btn = Button.new()
	load_btn.text = "Load"
	load_btn.tooltip_text = "Clear the current level and load this example"
	load_btn.pressed.connect(_on_load_pressed.bind(example.get("id", "")))
	btn_row.add_child(load_btn)

	var study_btn = Button.new()
	study_btn.text = "Study This"
	study_btn.tooltip_text = "Show annotations explaining the design"
	study_btn.pressed.connect(_on_study_pressed.bind(example))
	btn_row.add_child(study_btn)

	# Info: brush and entity counts
	var brushes: Array = example.get("brushes", [])
	var entities: Array = example.get("entities", [])
	var info = Label.new()
	info.text = "%d brushes, %d entities" % [brushes.size(), entities.size()]
	info.add_theme_font_size_override("font_size", 9)
	info.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6, 0.6))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	btn_row.add_child(info)

	return card


func _on_load_pressed(example_id: String) -> void:
	_selected_id = example_id
	load_requested.emit(example_id)


func _on_study_pressed(example: Dictionary) -> void:
	_show_annotations(example)


func _show_annotations(example: Dictionary) -> void:
	for child in _annotation_list.get_children():
		child.queue_free()

	var annotations: Array = example.get("annotations", [])
	if annotations.is_empty():
		_annotation_panel.visible = false
		return

	# Header
	var header = Label.new()
	header.text = "Study: %s" % example.get("title", "")
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 0.9))
	_annotation_list.add_child(header)

	for i in range(annotations.size()):
		var ann: Dictionary = annotations[i]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var num = Label.new()
		num.text = "%d." % (i + 1)
		num.add_theme_font_size_override("font_size", 11)
		num.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 0.7))
		num.custom_minimum_size = Vector2(18, 0)
		row.add_child(num)

		var text = Label.new()
		text.text = ann.get("text", "")
		text.add_theme_font_size_override("font_size", 11)
		text.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85, 0.9))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)

		_annotation_list.add_child(row)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): _annotation_panel.visible = false)
	_annotation_list.add_child(close_btn)

	_annotation_panel.visible = true


func _on_search_changed(text: String) -> void:
	var query := text.strip_edges().to_lower()
	for i in range(_cards_container.get_child_count()):
		if i >= _examples.size():
			break
		var card: Control = _cards_container.get_child(i)
		if query.is_empty():
			card.visible = true
		else:
			var example: Dictionary = _examples[i]
			var title_match: bool = example.get("title", "").to_lower().contains(query)
			var desc_match: bool = example.get("description", "").to_lower().contains(query)
			var tag_match := false
			for tag in example.get("tags", []):
				if str(tag).to_lower().contains(query):
					tag_match = true
					break
			var diff_match: bool = example.get("difficulty", "").to_lower().contains(query)
			card.visible = title_match or desc_match or tag_match or diff_match


## Get example data by ID for loading.
func get_example_data(example_id: String) -> Dictionary:
	for example in _examples:
		if example.get("id", "") == example_id:
			return example
	return {}


## Get total count of available examples.
func get_example_count() -> int:
	return _examples.size()
