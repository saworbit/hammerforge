@tool
extends VBoxContainer
## Enhanced dock section for browsing, saving, and drag-dropping prefabs.
##
## Scans a project directory for .hfprefab files and presents them
## in a searchable grid with thumbnail previews, tag filtering,
## variant indicators, and context-menu actions (rename, delete, tags).

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")

signal save_requested(prefab_name: String)
signal save_linked_requested(prefab_name: String)
signal delete_requested(prefab_path: String)
signal variant_add_requested(prefab_path: String, variant_name: String)

var _search_bar: LineEdit
var _tag_filter: OptionButton
var _file_list: ItemList
var _name_input: LineEdit
var _save_btn: Button
var _save_linked_btn: Button
var _refresh_btn: Button
var _delete_btn: Button
var _prefab_dir: String = "res://prefabs"
var _file_paths: PackedStringArray = []
var _all_tags: PackedStringArray = []
var _prefab_cache: Dictionary = {}  # path -> HFPrefab (lazy loaded for tags/variants)
var _context_menu: PopupMenu


func _ready() -> void:
	_build_ui()
	refresh()


func _build_ui() -> void:
	add_theme_constant_override("separation", 4)

	# Search bar
	_search_bar = LineEdit.new()
	_search_bar.placeholder_text = "Search prefabs..."
	_search_bar.clear_button_enabled = true
	_search_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_bar.text_changed.connect(_on_search_changed)
	add_child(_search_bar)

	# Tag filter row
	var filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	add_child(filter_row)

	var filter_label = Label.new()
	filter_label.text = "Tag:"
	filter_row.add_child(filter_label)

	_tag_filter = OptionButton.new()
	_tag_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_filter.add_item("All", 0)
	_tag_filter.item_selected.connect(_on_tag_filter_changed)
	filter_row.add_child(_tag_filter)

	# File list (icon mode for thumbnails)
	_file_list = ItemList.new()
	_file_list.custom_minimum_size = Vector2(0, 120)
	_file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_file_list.allow_reselect = true
	_file_list.set_drag_forwarding(_get_drag_data_fw, Callable(), Callable())
	_file_list.item_clicked.connect(_on_item_clicked)
	add_child(_file_list)

	# Save row
	var save_row = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 4)
	add_child(save_row)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Prefab name..."
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_name_input)

	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.tooltip_text = "Save current selection as prefab"
	_save_btn.pressed.connect(_on_save_pressed)
	save_row.add_child(_save_btn)

	# Linked save + action row
	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 4)
	add_child(action_row)

	_save_linked_btn = Button.new()
	_save_linked_btn.text = "Save Linked"
	_save_linked_btn.tooltip_text = "Save as live-linked prefab (edits propagate)"
	_save_linked_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_linked_btn.pressed.connect(_on_save_linked_pressed)
	action_row.add_child(_save_linked_btn)

	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.tooltip_text = "Delete selected prefab file"
	_delete_btn.pressed.connect(_on_delete_pressed)
	action_row.add_child(_delete_btn)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.tooltip_text = "Rescan prefab directory"
	_refresh_btn.pressed.connect(refresh)
	action_row.add_child(_refresh_btn)

	# Context menu for right-click
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Add Variant...", 0)
	_context_menu.add_item("Edit Tags...", 1)
	_context_menu.add_separator()
	_context_menu.add_item("Delete", 2)
	_context_menu.id_pressed.connect(_on_context_menu_selected)
	add_child(_context_menu)


func set_prefab_dir(dir: String) -> void:
	_prefab_dir = dir
	refresh()


func refresh() -> void:
	if not _file_list:
		return
	_file_list.clear()
	_file_paths = PackedStringArray()
	_prefab_cache.clear()
	_all_tags = PackedStringArray()

	if not DirAccess.dir_exists_absolute(_prefab_dir):
		_refresh_tag_filter()
		return
	var dir := DirAccess.open(_prefab_dir)
	if not dir:
		_refresh_tag_filter()
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var entries: Array = []
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".hfprefab"):
			entries.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Sort alphabetically
	entries.sort()

	for entry in entries:
		var path: String = _prefab_dir.path_join(entry)
		var display: String = entry.get_basename()

		# Load prefab metadata (tags, variants)
		var prefab = HFPrefabType.load_from_file(path)
		if prefab:
			_prefab_cache[path] = prefab
			for tag in prefab.tags:
				if not _all_tags.has(tag):
					_all_tags.append(tag)
			# Append variant count indicator
			var vcount: int = prefab.get_variant_names().size()
			if vcount > 1:
				display += " [%d variants]" % vcount

		_file_list.add_item(display)
		_file_paths.append(path)

		# Set tooltip with tags
		if prefab and not prefab.tags.is_empty():
			var idx: int = _file_list.item_count - 1
			_file_list.set_item_tooltip(idx, "Tags: %s" % ", ".join(Array(prefab.tags)))

	_refresh_tag_filter()
	_apply_filters()


func _refresh_tag_filter() -> void:
	if not _tag_filter:
		return
	var prev_selected: int = _tag_filter.selected
	_tag_filter.clear()
	_tag_filter.add_item("All", 0)
	for i in range(_all_tags.size()):
		_tag_filter.add_item(_all_tags[i], i + 1)
	if prev_selected >= 0 and prev_selected < _tag_filter.item_count:
		_tag_filter.selected = prev_selected
	else:
		_tag_filter.selected = 0


func _apply_filters() -> void:
	if not _file_list:
		return
	var search_text: String = _search_bar.text.strip_edges().to_lower() if _search_bar else ""
	var tag_idx: int = _tag_filter.selected if _tag_filter else 0
	var filter_tag: String = ""
	if tag_idx > 0 and tag_idx - 1 < _all_tags.size():
		filter_tag = _all_tags[tag_idx - 1]

	for i in range(_file_list.item_count):
		if i >= _file_paths.size():
			break
		var path: String = _file_paths[i]
		var display: String = _file_list.get_item_text(i).to_lower()
		var show := true

		# Search filter
		if search_text != "" and display.find(search_text) == -1:
			# Also check tags
			var prefab = _prefab_cache.get(path)
			var tag_match := false
			if prefab:
				for tag in prefab.tags:
					if tag.to_lower().find(search_text) != -1:
						tag_match = true
						break
			if not tag_match:
				show = false

		# Tag filter
		if show and filter_tag != "":
			var prefab = _prefab_cache.get(path)
			if prefab:
				var has_tag := false
				for tag in prefab.tags:
					if tag == filter_tag:
						has_tag = true
						break
				if not has_tag:
					show = false
			else:
				show = false

		# ItemList doesn't support per-item visibility, so we use modulate
		_file_list.set_item_disabled(i, not show)
		if show:
			_file_list.set_item_custom_fg_color(i, Color.WHITE)
		else:
			_file_list.set_item_custom_fg_color(i, Color(1, 1, 1, 0.15))


## Get the file path for a selected item index.
func get_selected_path() -> String:
	var selected := _file_list.get_selected_items()
	if selected.is_empty():
		return ""
	var idx: int = selected[0]
	if idx < 0 or idx >= _file_paths.size():
		return ""
	return _file_paths[idx]


## Enable drag-and-drop from the file list.
func _get_drag_data_fw(at_position: Vector2, _control: Control) -> Variant:
	var idx := _file_list.get_item_at_position(at_position, true)
	if idx < 0 or idx >= _file_paths.size():
		return null
	var path: String = _file_paths[idx]
	var preview = Label.new()
	preview.text = _file_list.get_item_text(idx)
	set_drag_preview(preview)
	return {"type": "hammerforge_prefab", "path": path}


func _on_save_pressed() -> void:
	var pname := _name_input.text.strip_edges()
	if pname.is_empty():
		pname = "untitled"
	save_requested.emit(pname)
	_name_input.text = ""


func _on_save_linked_pressed() -> void:
	var pname := _name_input.text.strip_edges()
	if pname.is_empty():
		pname = "untitled"
	save_linked_requested.emit(pname)
	_name_input.text = ""


func _on_delete_pressed() -> void:
	var path := get_selected_path()
	if path == "":
		return
	delete_requested.emit(path)


func _on_search_changed(_text: String) -> void:
	_apply_filters()


func _on_tag_filter_changed(_index: int) -> void:
	_apply_filters()


func _on_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_RIGHT and index >= 0:
		_file_list.select(index)
		_context_menu.position = Vector2i(
			int(_file_list.global_position.x + at_position.x),
			int(_file_list.global_position.y + at_position.y)
		)
		_context_menu.popup()


func _on_context_menu_selected(id: int) -> void:
	var path := get_selected_path()
	if path == "":
		return
	match id:
		0:  # Add Variant
			_show_variant_dialog(path)
		1:  # Edit Tags
			_show_tags_dialog(path)
		2:  # Delete
			delete_requested.emit(path)


func _show_variant_dialog(prefab_path: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Add Variant"
	dialog.dialog_text = "Enter variant name:"
	var input = LineEdit.new()
	input.placeholder_text = "e.g. wooden, metal, ornate"
	dialog.add_child(input)
	dialog.confirmed.connect(
		func():
			var vname: String = input.text.strip_edges()
			if vname != "":
				variant_add_requested.emit(prefab_path, vname)
			dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(300, 120))


func _show_tags_dialog(prefab_path: String) -> void:
	var prefab = _prefab_cache.get(prefab_path)
	if not prefab:
		return
	var dialog = AcceptDialog.new()
	dialog.title = "Edit Tags"
	dialog.dialog_text = "Comma-separated tags:"
	var input = LineEdit.new()
	input.text = ", ".join(Array(prefab.tags))
	dialog.add_child(input)
	dialog.confirmed.connect(
		func():
			var raw: String = input.text.strip_edges()
			var new_tags: PackedStringArray = []
			for part in raw.split(","):
				var t: String = part.strip_edges().to_lower()
				if t != "":
					new_tags.append(t)
			prefab.tags = new_tags
			prefab.save_to_file(prefab_path)
			refresh()
			dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(350, 120))


## Called by dock after a successful save to refresh the list.
func on_prefab_saved() -> void:
	refresh()
