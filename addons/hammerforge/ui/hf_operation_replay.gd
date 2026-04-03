@tool
extends PanelContainer
## Mini operation timeline with replay capability.
##
## Captures recent operations (brush creation, carve, extrude, etc.)
## and displays them as a compact horizontal timeline. Users can hover
## entries to see details and click "Replay" to step through the undo
## history to that point and back.

signal replay_requested(entry_index: int)

const MAX_ENTRIES := 20
const ENTRY_WIDTH := 32
const ENTRY_HEIGHT := 28

var _entries: Array = []  # Array of {name, icon_char, timestamp, version}
var _timeline_container: HBoxContainer
var _detail_label: Label
var _replay_btn: Button
var _hovered_index := -1
var _scroll: ScrollContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_style()
	_build_ui()


func _build_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.border_width_bottom = 2
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_color = Color(0.3, 0.4, 0.6, 0.5)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(300, 72)


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Header
	var header = HBoxContainer.new()
	vbox.add_child(header)

	var title = Label.new()
	title.text = "Operation Timeline"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.8))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_replay_btn = Button.new()
	_replay_btn.text = "Replay"
	_replay_btn.add_theme_font_size_override("font_size", 10)
	_replay_btn.visible = false
	_replay_btn.pressed.connect(_on_replay_pressed)
	header.add_child(_replay_btn)

	# Scrollable timeline
	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, ENTRY_HEIGHT + 4)
	vbox.add_child(_scroll)

	_timeline_container = HBoxContainer.new()
	_timeline_container.add_theme_constant_override("separation", 2)
	_scroll.add_child(_timeline_container)

	# Detail label (shows on hover)
	_detail_label = Label.new()
	_detail_label.text = "Hover an operation to see details"
	_detail_label.add_theme_font_size_override("font_size", 10)
	_detail_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75, 0.7))
	vbox.add_child(_detail_label)


## Record an operation into the timeline.
func record_operation(action_name: String, version: int = -1) -> void:
	var icon_char := _get_icon_for_action(action_name)
	var entry := {
		"name": action_name,
		"icon_char": icon_char,
		"timestamp": Time.get_ticks_msec(),
		"version": version,
	}
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	_rebuild_timeline()


## Clear all entries.
func clear() -> void:
	_entries.clear()
	_rebuild_timeline()


## Toggle visibility.
func toggle_visible() -> void:
	visible = not visible


## Get the number of recorded entries.
func get_entry_count() -> int:
	return _entries.size()


## Get the undo version for an entry. Returns -1 if not recorded.
func get_entry_version(index: int) -> int:
	if index < 0 or index >= _entries.size():
		return -1
	return int(_entries[index].get("version", -1))


func _rebuild_timeline() -> void:
	if not _timeline_container:
		return
	for child in _timeline_container.get_children():
		_timeline_container.remove_child(child)
		child.queue_free()

	for i in range(_entries.size()):
		var entry: Dictionary = _entries[i]
		var btn = Button.new()
		btn.text = entry["icon_char"]
		btn.tooltip_text = entry["name"]
		btn.flat = true
		btn.custom_minimum_size = Vector2(ENTRY_WIDTH, ENTRY_HEIGHT)
		btn.add_theme_font_size_override("font_size", 14)

		# Color based on action type
		var color := _get_color_for_action(entry["name"])
		btn.add_theme_color_override("font_color", color)

		btn.mouse_entered.connect(_on_entry_hovered.bind(i))
		btn.mouse_exited.connect(_on_entry_unhovered)
		btn.pressed.connect(_on_entry_clicked.bind(i))
		_timeline_container.add_child(btn)

	# Auto-scroll to end
	if _scroll:
		_scroll.call_deferred("set_h_scroll", 99999)


func _on_entry_hovered(index: int) -> void:
	_hovered_index = index
	if index >= 0 and index < _entries.size():
		var entry: Dictionary = _entries[index]
		var elapsed: float = (Time.get_ticks_msec() - entry["timestamp"]) / 1000.0
		var time_str := ""
		if elapsed < 60.0:
			time_str = "%ds ago" % int(elapsed)
		elif elapsed < 3600.0:
			time_str = "%dm ago" % int(elapsed / 60.0)
		else:
			time_str = "%dh ago" % int(elapsed / 3600.0)
		_detail_label.text = "%s  (%s)" % [entry["name"], time_str]
		_replay_btn.visible = true


func _on_entry_unhovered() -> void:
	_hovered_index = -1
	_detail_label.text = "Hover an operation to see details"
	_replay_btn.visible = false


func _on_entry_clicked(index: int) -> void:
	_hovered_index = index
	_replay_btn.visible = true
	if index >= 0 and index < _entries.size():
		var entry: Dictionary = _entries[index]
		_detail_label.text = "%s  (click Replay to undo/redo to this point)" % entry["name"]


func _on_replay_pressed() -> void:
	if _hovered_index >= 0 and _hovered_index < _entries.size():
		replay_requested.emit(_hovered_index)


func _get_icon_for_action(action_name: String) -> String:
	var lower := action_name.to_lower()
	# More specific matches first (before generic "brush" catch-all)
	if "carve" in lower:
		return "#"
	if "hollow" in lower:
		return "O"
	if "clip" in lower:
		return "/"
	if "extrude" in lower:
		return "^"
	if "subtract" in lower:
		return "-"
	if "duplicate" in lower:
		return "="
	if "delete" in lower or "remove" in lower:
		return "x"
	if "draw" in lower or "brush" in lower or "create" in lower:
		return "+"
	if "move" in lower or "translate" in lower:
		return ">"
	if "paint" in lower:
		return "~"
	if "group" in lower:
		return "G"
	if "vertex" in lower or "merge" in lower or "split" in lower:
		return "V"
	if "bake" in lower:
		return "B"
	if "undo" in lower:
		return "<"
	if "redo" in lower:
		return ">"
	if "rotate" in lower:
		return "R"
	if "scale" in lower:
		return "S"
	if "material" in lower or "texture" in lower:
		return "M"
	if "entity" in lower:
		return "E"
	if "path" in lower:
		return "P"
	if "polygon" in lower:
		return "N"
	return "*"


func _get_color_for_action(action_name: String) -> Color:
	var lower := action_name.to_lower()
	if "delete" in lower or "remove" in lower:
		return Color(0.9, 0.35, 0.3, 0.9)
	if "subtract" in lower:
		return Color(0.9, 0.55, 0.3, 0.9)
	if "extrude" in lower:
		return Color(0.3, 0.8, 0.5, 0.9)
	if "carve" in lower or "clip" in lower:
		return Color(0.9, 0.8, 0.3, 0.9)
	if "paint" in lower or "material" in lower or "texture" in lower:
		return Color(0.5, 0.7, 0.9, 0.9)
	if "draw" in lower or "brush" in lower or "create" in lower:
		return Color(0.3, 0.7, 1.0, 0.9)
	if "vertex" in lower or "merge" in lower or "split" in lower:
		return Color(0.7, 0.5, 0.9, 0.9)
	if "bake" in lower:
		return Color(0.3, 0.9, 0.7, 0.9)
	return Color(0.7, 0.7, 0.7, 0.8)
