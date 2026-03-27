@tool
extends VBoxContainer
## Dock section for browsing, saving, and drag-dropping prefabs.
##
## Scans a project directory for .hfprefab files and presents them
## in an ItemList with drag-and-drop support.

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")

signal save_requested(prefab_name: String)

var _file_list: ItemList
var _name_input: LineEdit
var _save_btn: Button
var _refresh_btn: Button
var _prefab_dir: String = "res://prefabs"
var _file_paths: PackedStringArray = []


func _ready() -> void:
	_build_ui()
	refresh()


func _build_ui() -> void:
	add_theme_constant_override("separation", 4)

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

	# File list
	_file_list = ItemList.new()
	_file_list.custom_minimum_size = Vector2(0, 80)
	_file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_file_list.allow_reselect = true
	_file_list.set_drag_forwarding(_get_drag_data_fw, Callable(), Callable())
	add_child(_file_list)

	# Refresh row
	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.tooltip_text = "Rescan prefab directory"
	_refresh_btn.pressed.connect(refresh)
	add_child(_refresh_btn)


func set_prefab_dir(dir: String) -> void:
	_prefab_dir = dir
	refresh()


func refresh() -> void:
	if not _file_list:
		return
	_file_list.clear()
	_file_paths = PackedStringArray()
	if not DirAccess.dir_exists_absolute(_prefab_dir):
		return
	var dir := DirAccess.open(_prefab_dir)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".hfprefab"):
			var display := file_name.get_basename()
			_file_list.add_item(display)
			_file_paths.append(_prefab_dir.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


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


## Called by dock after a successful save to refresh the list.
func on_prefab_saved() -> void:
	refresh()
