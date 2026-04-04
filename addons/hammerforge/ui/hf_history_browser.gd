@tool
class_name HFHistoryBrowser
extends VBoxContainer
## Rich undo history browser with color-coded action icons and viewport thumbnails.
##
## Replaces the simple ItemList in the History section. Each entry shows an
## action icon, name, and a small viewport thumbnail captured at that state.
## Double-click navigates undo history to that version.

const HFOperationReplayScript = preload("res://addons/hammerforge/ui/hf_operation_replay.gd")

signal navigate_requested(version: int)

const MAX_ENTRIES := 30
const THUMB_WIDTH := 80
const THUMB_HEIGHT := 48

var _entries: Array = []  # Array of {name, version, timestamp, thumbnail, icon_char, color}
var _scroll: ScrollContainer
var _list: VBoxContainer
var _preview_rect: TextureRect  # Enlarged preview on hover
var _undo_btn: Button
var _redo_btn: Button


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_build_ui()


func _build_ui() -> void:
	# Undo/Redo buttons
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	add_child(btn_row)

	_undo_btn = Button.new()
	_undo_btn.text = "Undo"
	_undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(_undo_btn)

	_redo_btn = Button.new()
	_redo_btn.text = "Redo"
	_redo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(_redo_btn)

	# Scrollable entry list
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 140)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	# Thumbnail preview (shown on hover, floats above)
	_preview_rect = TextureRect.new()
	_preview_rect.custom_minimum_size = Vector2(THUMB_WIDTH * 2, THUMB_HEIGHT * 2)
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.visible = false
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview_rect)


## Get the Undo button for external signal connection.
func get_undo_button() -> Button:
	return _undo_btn


## Get the Redo button for external signal connection.
func get_redo_button() -> Button:
	return _redo_btn


## Record a new history entry with optional viewport thumbnail.
func record_entry(action_name: String, version: int = -1) -> void:
	var thumbnail: ImageTexture = _capture_thumbnail()
	var icon_char: String = HFOperationReplayScript._get_icon_for_action(action_name)
	var color: Color = HFOperationReplayScript._get_color_for_action(action_name)

	var entry := {
		"name": action_name,
		"version": version,
		"timestamp": Time.get_ticks_msec(),
		"thumbnail": thumbnail,
		"icon_char": icon_char,
		"color": color,
	}
	_entries.append(entry)

	# Recycle oldest entries
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()

	_rebuild_list()


## Clear all history entries.
func clear() -> void:
	_entries.clear()
	_rebuild_list()


## Get number of entries.
func get_entry_count() -> int:
	return _entries.size()


func _rebuild_list() -> void:
	if not _list:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	for i in range(_entries.size()):
		var entry: Dictionary = _entries[i]
		var row := _create_entry_row(entry, i)
		_list.add_child(row)

	# Auto-scroll to bottom
	if _scroll:
		_scroll.call_deferred("set_v_scroll", 99999)


func _create_entry_row(entry: Dictionary, index: int) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(0, 28)

	# Color-coded icon square
	var icon_panel = PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(22, 22)
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = entry["color"]
	icon_style.set_corner_radius_all(3)
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	var icon_label = Label.new()
	icon_label.text = entry["icon_char"]
	icon_label.add_theme_font_size_override("font_size", 12)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_color_override("font_color", HFThemeUtils.primary_text())
	icon_panel.add_child(icon_label)
	row.add_child(icon_panel)

	# Action name (truncated)
	var name_label = Label.new()
	var display_name: String = entry["name"]
	if display_name.length() > 25:
		display_name = display_name.left(22) + "..."
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = entry["name"]
	row.add_child(name_label)

	# Thumbnail
	var thumb_rect = TextureRect.new()
	thumb_rect.custom_minimum_size = Vector2(THUMB_WIDTH, THUMB_HEIGHT)
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if entry["thumbnail"]:
		thumb_rect.texture = entry["thumbnail"]
	else:
		thumb_rect.modulate = Color(0.5, 0.5, 0.5, 0.3)
	row.add_child(thumb_rect)

	# Interactions
	row.mouse_entered.connect(_on_row_hovered.bind(index))
	row.mouse_exited.connect(_on_row_unhovered)
	row.gui_input.connect(_on_row_input.bind(index))
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	return row


func _on_row_hovered(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry: Dictionary = _entries[index]
	if entry["thumbnail"] and _preview_rect:
		_preview_rect.texture = entry["thumbnail"]
		_preview_rect.visible = true


func _on_row_unhovered() -> void:
	if _preview_rect:
		_preview_rect.visible = false


func _on_row_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click:
		if index >= 0 and index < _entries.size():
			var version: int = _entries[index].get("version", -1)
			if version >= 0:
				navigate_requested.emit(version)


func _capture_thumbnail() -> ImageTexture:
	if not Engine.is_editor_hint():
		return null
	# Try to capture from the 3D editor viewport
	var vp = _get_editor_viewport_3d()
	if not vp:
		return null
	var tex = vp.get_texture()
	if not tex:
		return null
	var img: Image = tex.get_image()
	if not img:
		return null
	img.resize(THUMB_WIDTH, THUMB_HEIGHT, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


func _get_editor_viewport_3d() -> SubViewport:
	if not Engine.is_editor_hint():
		return null
	# Navigate the editor UI tree to find the 3D viewport
	var base = EditorInterface.get_base_control()
	if not base:
		return null
	# Try the EditorInterface API first (Godot 4.3+)
	if EditorInterface.has_method("get_editor_viewport_3d"):
		var vp = EditorInterface.get_editor_viewport_3d(0)
		if vp:
			return vp
	return null
