@tool
extends AcceptDialog
## Searchable keyboard shortcut reference dialog.
##
## Displays all HammerForge shortcuts grouped by category with a live
## search/filter field.  Populated from an HFKeymap instance.

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

var _search_field: LineEdit
var _tree: Tree
var _category_items: Dictionary = {}  # category name -> TreeItem


func _ready() -> void:
	title = "Keyboard Shortcuts"
	min_size = Vector2i(380, 460)
	_build_ui()


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Filter shortcuts..."
	_search_field.clear_button_enabled = true
	_search_field.text_changed.connect(_on_search_text_changed)
	vbox.add_child(_search_field)

	_tree = Tree.new()
	_tree.columns = 2
	_tree.set_column_title(0, "Action")
	_tree.set_column_title(1, "Key")
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, true)
	_tree.set_column_expand_ratio(0, 2.0)
	_tree.set_column_expand_ratio(1, 1.0)
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tree)

	var hint = Label.new()
	hint.text = "Type number + Enter during drag for exact size"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


func populate(keymap) -> void:
	_tree.clear()
	_category_items.clear()
	var root_item = _tree.create_item()

	# Ordered categories
	var category_order := ["Tools", "Editing", "Paint", "Axis Lock"]
	var categorized: Dictionary = {}
	for cat in category_order:
		categorized[cat] = []

	var actions: PackedStringArray = keymap.get_actions()
	for action in actions:
		var cat: String = HFKeymapType.get_category(action)
		if not categorized.has(cat):
			categorized[cat] = []
		categorized[cat].append(action)

	for cat in category_order:
		if not categorized.has(cat) or categorized[cat].is_empty():
			continue
		var cat_item: TreeItem = _tree.create_item(root_item)
		cat_item.set_text(0, cat)
		cat_item.set_selectable(0, false)
		cat_item.set_selectable(1, false)
		cat_item.set_custom_color(0, Color(0.7, 0.8, 1.0, 1.0))
		_category_items[cat] = cat_item

		for action in categorized[cat]:
			var item: TreeItem = _tree.create_item(cat_item)
			var label: String = HFKeymapType.get_action_label(action)
			var binding: String = keymap.get_display_string(action)
			item.set_text(0, label)
			item.set_text(1, binding)
			item.set_selectable(0, false)
			item.set_selectable(1, false)
			item.set_meta("action", action)
			item.set_meta("label_lower", label.to_lower())
			item.set_meta("binding_lower", binding.to_lower())


func _on_search_text_changed(filter_text: String) -> void:
	var query := filter_text.strip_edges().to_lower()
	for cat in _category_items:
		var cat_item: TreeItem = _category_items[cat]
		var any_visible := false
		var child: TreeItem = cat_item.get_first_child()
		while child:
			if query.is_empty():
				child.visible = true
				any_visible = true
			else:
				var label_lower: String = child.get_meta("label_lower", "")
				var binding_lower: String = child.get_meta("binding_lower", "")
				var match_found: bool = label_lower.contains(query) or binding_lower.contains(query)
				child.visible = match_found
				if match_found:
					any_visible = true
			child = child.get_next()
		cat_item.visible = any_visible
