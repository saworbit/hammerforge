@tool
class_name HFConsoleLogView
extends VBoxContainer
## The Console's Log tab: HammerForge's own messages, levelled and filterable.
##
## Godot's Output panel carries every addon's output at once, so a HammerForge
## warning is only findable there if you already know it happened. This shows
## the same messages on their own, with the counts doubling as the filter — the
## reader sees "3 warnings" and clicks that number to see only those three.

const HFConsoleLogType = preload("../hf_console_log.gd")

## Level toggles, in the order they appear. Kept beside the level enum rather
## than derived from it so the labels read as a sentence, not as constants.
const LEVEL_BUTTONS := [
	{"level": HFConsoleLogType.Level.DEBUG, "label": "Debug", "count_key": "debug"},
	{"level": HFConsoleLogType.Level.INFO, "label": "Info", "count_key": "info"},
	{"level": HFConsoleLogType.Level.WARN, "label": "Warnings", "count_key": "warn"},
	{"level": HFConsoleLogType.Level.ERROR, "label": "Errors", "count_key": "error"},
]

## Debug is off by default: it is the level HammerForge writes on every drag,
## and a reader opening the log wants the exception, not the trace.
const DEFAULT_MASK := (
	(1 << HFConsoleLogType.Level.INFO)
	| (1 << HFConsoleLogType.Level.WARN)
	| (1 << HFConsoleLogType.Level.ERROR)
)

var _log = null
var _base_control: Control = null

var _level_mask: int = DEFAULT_MASK
var _search: String = ""
var _autoscroll: bool = true
var _rendered_dropped: int = 0
## Lines currently drawn. Tracked incrementally so the summary never re-filters
## the whole buffer per arriving line, which turns a bake's burst of messages
## into quadratic work.
var _visible_count: int = 0
## A message repeating every frame — a reconcile warning during a drag — would
## otherwise force a full re-render of up to a bufferful of lines per frame.
var _rebuild_queued: bool = false

var _output: RichTextLabel = null
var _search_field: LineEdit = null
var _autoscroll_toggle: CheckButton = null
var _summary: Label = null
var _empty_hint: Label = null
var _save_dialog: FileDialog = null
var _level_toggles: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 4)
	_build()


func _build() -> void:
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 4)
	add_child(filters)

	for spec in LEVEL_BUTTONS:
		var toggle := Button.new()
		toggle.toggle_mode = true
		toggle.button_pressed = bool(DEFAULT_MASK & (1 << int(spec["level"])))
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.text = "%s 0" % spec["label"]
		toggle.tooltip_text = (
			"Show %s messages. The number is how many arrived this session."
			% str(spec["label"]).to_lower()
		)
		toggle.toggled.connect(_on_level_toggled.bind(int(spec["level"])))
		filters.add_child(toggle)
		_level_toggles[int(spec["level"])] = toggle

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(spacer)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Filter text..."
	_search_field.clear_button_enabled = true
	_search_field.custom_minimum_size.x = 180
	_search_field.tooltip_text = "Show only lines containing this text."
	_search_field.text_changed.connect(_on_search_changed)
	filters.add_child(_search_field)

	_autoscroll_toggle = CheckButton.new()
	_autoscroll_toggle.text = "Follow"
	_autoscroll_toggle.button_pressed = true
	_autoscroll_toggle.focus_mode = Control.FOCUS_NONE
	_autoscroll_toggle.tooltip_text = (
		"Keep the newest line in view. Turn this off to read back through the log"
		+ "\nwhile HammerForge is still writing to it."
	)
	_autoscroll_toggle.toggled.connect(_on_autoscroll_toggled)
	filters.add_child(_autoscroll_toggle)

	var copy_btn := Button.new()
	copy_btn.text = "Copy"
	copy_btn.tooltip_text = "Copy the lines currently shown to the clipboard."
	copy_btn.pressed.connect(_on_copy_pressed)
	filters.add_child(copy_btn)

	var save_btn := Button.new()
	save_btn.text = "Save..."
	save_btn.tooltip_text = "Write the lines currently shown to a text file."
	save_btn.pressed.connect(_on_save_pressed)
	filters.add_child(save_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.tooltip_text = "Empty the buffer and reset the session counts."
	clear_btn.pressed.connect(_on_clear_pressed)
	filters.add_child(clear_btn)

	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.selection_enabled = true
	_output.focus_mode = Control.FOCUS_CLICK
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Small enough that the console does not force the bottom panel tall and
	# squeeze the 3D viewport; the panel is resizable for anyone reading a lot.
	_output.custom_minimum_size.y = 80
	add_child(_output)

	_empty_hint = Label.new()
	_empty_hint.add_theme_font_size_override("font_size", 11)
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.text = "Nothing logged yet."
	add_child(_empty_hint)

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 11)
	add_child(_summary)

	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.add_filter("*.txt", "Text file")
	_save_dialog.title = "Save HammerForge log"
	_save_dialog.file_selected.connect(_on_save_path_chosen)
	add_child(_save_dialog)


## Attach to a log buffer. Safe to call again with a different buffer.
func set_log(buffer) -> void:
	if _log == buffer:
		return
	_disconnect_log()
	_log = buffer
	if _log:
		_log.entry_appended.connect(_on_entry_appended)
		_log.entry_repeated.connect(_on_entry_repeated)
		_log.cleared.connect(_on_log_cleared)
	rebuild()


func set_theme_source(base_control: Control) -> void:
	_base_control = base_control
	# Every line carries theme colours inline as BBCode, so a theme change means
	# re-rendering them all.
	rebuild()


## Fixed-pitch where the editor has one, so the timestamp and level columns line
## up and the eye can run down them.
func _use_monospace_font() -> void:
	if _output == null:
		return
	if _output.has_theme_font("source", "EditorFonts"):
		_output.add_theme_font_override(
			"normal_font", _output.get_theme_font("source", "EditorFonts")
		)


## Focus the search field — what the Console does when a status row sends the
## reader here, so they can narrow straight away.
func focus_search() -> void:
	if _search_field:
		_search_field.grab_focus()


## Turn a level on and leave the others as they were. Used when the reader
## arrives from the "2 errors" status row and should land on those two.
func isolate_level(level: int) -> void:
	_level_mask = 1 << level
	for key in _level_toggles.keys():
		_level_toggles[key].set_pressed_no_signal(key == level)
	rebuild()


## Redraw every line from the buffer. Used on filter changes and whenever the
## buffer has dropped entries the view still has on screen.
func rebuild() -> void:
	if not _output:
		return
	_output.clear()
	if _log == null:
		_update_summary(0)
		return
	_use_monospace_font()
	_rendered_dropped = _log.dropped_count()
	var rows: Array = _log.filtered(_level_mask, _search)
	for entry in rows:
		_output.append_text(_render(entry) + "\n")
	_update_summary(rows.size())
	if _autoscroll:
		_scroll_to_end()


## Collapse a burst of rebuild requests into one, on the next frame.
func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_flush_rebuild")


func _flush_rebuild() -> void:
	_rebuild_queued = false
	rebuild()


func _disconnect_log() -> void:
	if _log == null:
		return
	if _log.entry_appended.is_connected(_on_entry_appended):
		_log.entry_appended.disconnect(_on_entry_appended)
	if _log.entry_repeated.is_connected(_on_entry_repeated):
		_log.entry_repeated.disconnect(_on_entry_repeated)
	if _log.cleared.is_connected(_on_log_cleared):
		_log.cleared.disconnect(_on_log_cleared)


func _exit_tree() -> void:
	_disconnect_log()
	_log = null


func _on_entry_appended(entry: Dictionary) -> void:
	if _log and _log.dropped_count() != _rendered_dropped:
		# The buffer trimmed lines this view still has on screen. Appending on
		# top of a stale head would leave the view claiming entries the buffer
		# no longer holds, so start again.
		_queue_rebuild()
		return
	if not _passes_filter(entry):
		_update_summary(_visible_count)
		return
	_output.append_text(_render(entry) + "\n")
	_update_summary(_visible_count + 1)
	if _autoscroll:
		_scroll_to_end()


func _on_entry_repeated(_entry: Dictionary) -> void:
	# The repeat count lives on a line already drawn, so the only way to show it
	# is to re-render. Queued rather than immediate: this is exactly the path a
	# per-frame repeat takes.
	_queue_rebuild()


func _on_log_cleared() -> void:
	_rendered_dropped = 0
	_visible_count = 0
	rebuild()


func _on_level_toggled(pressed: bool, level: int) -> void:
	if pressed:
		_level_mask |= 1 << level
	else:
		_level_mask &= ~(1 << level)
	rebuild()


func _on_search_changed(text: String) -> void:
	_search = text
	rebuild()


func _on_autoscroll_toggled(pressed: bool) -> void:
	_autoscroll = pressed
	if _autoscroll:
		_scroll_to_end()


func _on_copy_pressed() -> void:
	if _log == null:
		return
	DisplayServer.clipboard_set(_log.to_text(_level_mask, _search))
	_flash_summary("Copied to clipboard.")


func _on_save_pressed() -> void:
	if _save_dialog == null:
		return
	_save_dialog.current_file = (
		"hammerforge-log-%s.txt"
		% (
			Time
			. get_datetime_string_from_system(false, false)
			. replace(":", "")
			. replace("-", "")
			. replace("T", "-")
		)
	)
	_save_dialog.popup_centered(Vector2i(720, 480))


func _on_save_path_chosen(path: String) -> void:
	if _log == null:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_flash_summary("Could not write %s (error %d)." % [path, FileAccess.get_open_error()])
		return
	file.store_string(_log.to_text(_level_mask, _search))
	file.close()
	_flash_summary("Saved to %s" % path)


func _on_clear_pressed() -> void:
	if _log:
		_log.clear()


func _passes_filter(entry: Dictionary) -> bool:
	if not (_level_mask & (1 << int(entry.get("level", 0)))):
		return false
	if _search.strip_edges() == "":
		return true
	var hay := "%s %s" % [entry.get("category", ""), entry.get("message", "")]
	return hay.to_lower().contains(_search.strip_edges().to_lower())


func _render(entry: Dictionary) -> String:
	var level := int(entry.get("level", 0))
	var muted := HFThemeUtils.muted_text(_base_control)
	var accent := _level_color(level)
	var category := str(entry.get("category", ""))
	var line := "[color=#%s]%s[/color]  " % [muted.to_html(false), entry.get("stamp", "")]
	line += (
		"[color=#%s]%-5s[/color]  " % [accent.to_html(false), HFConsoleLogType.level_name(level)]
	)
	if category != "":
		line += (
			"[color=#%s]%s[/color]  "
			% [muted.to_html(false), HFConsoleLogType.escape_bbcode("[%s]" % category)]
		)
	line += HFConsoleLogType.escape_bbcode(str(entry.get("message", "")))
	var repeat := int(entry.get("repeat", 1))
	if repeat > 1:
		line += "  [color=#%s](x%d)[/color]" % [muted.to_html(false), repeat]
	return line


func _level_color(level: int) -> Color:
	match level:
		HFConsoleLogType.Level.ERROR:
			return HFThemeUtils.error_color(_base_control)
		HFConsoleLogType.Level.WARN:
			return HFThemeUtils.warning_color(_base_control)
		HFConsoleLogType.Level.INFO:
			return HFThemeUtils.primary_text(_base_control)
		_:
			return HFThemeUtils.muted_text(_base_control)


## `shown` is how many lines are currently drawn. Callers track it rather than
## asking the buffer, so an arriving line costs one append, not a rescan.
func _update_summary(shown: int) -> void:
	if _log == null:
		if _summary:
			_summary.text = "No log attached."
		if _empty_hint:
			_empty_hint.visible = false
		return
	var counts: Dictionary = _log.counts()
	for spec in LEVEL_BUTTONS:
		var toggle: Button = _level_toggles.get(int(spec["level"]))
		if toggle:
			toggle.text = "%s %d" % [spec["label"], int(counts.get(spec["count_key"], 0))]
			toggle.add_theme_color_override("font_color", _level_color(int(spec["level"])))
	var visible_count: int = maxi(shown, 0)
	_visible_count = visible_count
	var total: int = _log.size()
	var text := "Showing %d of %d retained" % [visible_count, total]
	var dropped: int = _log.dropped_count()
	if dropped > 0:
		text += " · %d older dropped (buffer holds %d)" % [dropped, _log.capacity]
	if _summary:
		_summary.text = text
		_summary.add_theme_color_override("font_color", HFThemeUtils.muted_text(_base_control))
	if _empty_hint:
		_empty_hint.visible = visible_count == 0
		_empty_hint.add_theme_color_override("font_color", HFThemeUtils.muted_text(_base_control))
		if total == 0:
			_empty_hint.text = "Nothing logged yet. HammerForge writes here as you build."
		else:
			_empty_hint.text = "No lines match the current filter."


func _flash_summary(message: String) -> void:
	if _summary:
		_summary.text = message


func _scroll_to_end() -> void:
	if not _output:
		return
	var bar := _output.get_v_scroll_bar()
	if bar:
		bar.value = bar.max_value
