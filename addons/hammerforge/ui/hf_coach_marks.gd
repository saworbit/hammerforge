@tool
extends PanelContainer
## First-use interactive coach marks for advanced tools.
##
## Shows floating step-by-step guidance when a tool is activated for the first
## time. Tracks which guides have been shown via HFUserPrefs and provides
## "Don't show again" per-tool. Each guide is a compact overlay listing the
## tool's key steps with a dismiss/don't-show-again footer.

signal guide_dismissed(tool_key: String, dont_show_again: bool)

const GUIDES: Dictionary = {
	"polygon":
	{
		"title": "Polygon Tool",
		"steps":
		[
			"Click in viewport to place vertices",
			"Press Enter or close loop to finish shape",
			"Drag up/down to set height",
			"Click to confirm brush creation",
		],
	},
	"path":
	{
		"title": "Path Tool",
		"steps":
		[
			"Click to place path control points",
			"Press Enter to finish path placement",
			"Drag up/down to set extrusion height",
			"Click to confirm the path brush",
		],
	},
	"carve":
	{
		"title": "Carve Tool",
		"steps":
		[
			"Select one or more brushes to carve",
			"Press Ctrl+Shift+R or use Command Palette",
			"Overlapping volumes are split into fragments",
			"Delete unwanted fragments after carving",
		],
	},
	"vertex_edit":
	{
		"title": "Vertex Editing",
		"steps":
		[
			"Press V to enter Vertex mode",
			"Click vertices to select (Shift+click to multi-select)",
			"Press E to switch to Edge sub-mode",
			"Ctrl+W merges selected vertices",
			"Ctrl+E splits the hovered edge",
			"Press V again to exit Vertex mode",
		],
	},
	"extrude":
	{
		"title": "Face Extrusion",
		"steps":
		[
			"Select a brush, then press U (up) or J (down)",
			"Click a face to begin extruding",
			"Drag to set extrusion distance",
			"Click to confirm the new brush",
		],
	},
	"clip":
	{
		"title": "Clip Tool",
		"steps":
		[
			"Select one or more brushes to clip",
			"Press Shift+X or use Command Palette",
			"Brush is split along its midplane",
			"Delete the unwanted half afterward",
		],
	},
	"hollow":
	{
		"title": "Hollow Tool",
		"steps":
		[
			"Select a solid brush",
			"Press Ctrl+H or use Command Palette",
			"Enter wall thickness when prompted",
			"Result: outer shell with inner subtraction",
		],
	},
	"measure":
	{
		"title": "Measure Tool",
		"steps":
		[
			"Activate from the tool registry or shortcut",
			"Click to place the first measurement point",
			"Click again to place the second point",
			"Distance is displayed along the line",
		],
	},
	"decal":
	{
		"title": "Decal Tool",
		"steps":
		[
			"Activate from the tool registry or shortcut",
			"Click a surface to place a decal",
			"Drag handles to resize and rotate",
			"Assign material in the Brush tab",
		],
	},
	"surface_paint":
	{
		"title": "Surface Paint",
		"steps":
		[
			"Toggle Paint mode (P) in toolbar",
			"Select a paint tool: Brush (B), Erase (E), etc.",
			"Click floor cells to paint layers",
			"Use Ramp (R) or Line (L) for linear fills",
		],
	},
}

var _title_label: Label
var _steps_container: VBoxContainer
var _dont_show: CheckBox
var _dismiss_btn: Button
var _current_tool_key := ""
var _user_prefs = null  # HFUserPrefs


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_style()
	_build_ui()


func _build_style() -> void:
	var style = HFThemeUtils.make_panel_stylebox()
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.border_color = HFThemeUtils.accent()
	style.border_color.a = 0.6
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(260, 0)


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Header row
	var header = HBoxContainer.new()
	vbox.add_child(header)

	var icon_label = Label.new()
	icon_label.text = "? "
	icon_label.add_theme_font_size_override("font_size", 14)
	icon_label.add_theme_color_override("font_color", HFThemeUtils.accent())
	header.add_child(icon_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", HFThemeUtils.primary_text())
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Steps list
	_steps_container = VBoxContainer.new()
	_steps_container.add_theme_constant_override("separation", 3)
	vbox.add_child(_steps_container)

	# Footer
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)

	_dont_show = CheckBox.new()
	_dont_show.text = "Don't show again"
	_dont_show.add_theme_font_size_override("font_size", 11)
	_dont_show.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_dont_show)

	_dismiss_btn = Button.new()
	_dismiss_btn.text = "Got it"
	_dismiss_btn.pressed.connect(_on_dismiss)
	footer.add_child(_dismiss_btn)


## Refresh colors when editor theme changes.
func refresh_theme_colors() -> void:
	_build_style()
	if _title_label:
		_title_label.add_theme_color_override("font_color", HFThemeUtils.primary_text())


## Set user prefs for persistence of dismissed guides.
func set_user_prefs(prefs) -> void:
	_user_prefs = prefs


## Show the coach mark for a tool if it hasn't been dismissed before.
## Returns true if the guide was shown, false if already dismissed.
func show_guide(tool_key: String) -> bool:
	if not GUIDES.has(tool_key):
		return false
	if _is_guide_dismissed(tool_key):
		return false
	_current_tool_key = tool_key
	var guide: Dictionary = GUIDES[tool_key]
	_title_label.text = guide["title"]
	_populate_steps(guide["steps"])
	_dont_show.button_pressed = false
	visible = true
	return true


## Hide the current guide.
func hide_guide() -> void:
	visible = false
	_current_tool_key = ""


## Get the currently displayed tool key (empty if hidden).
func get_current_tool_key() -> String:
	return _current_tool_key


func _populate_steps(steps: Array) -> void:
	for child in _steps_container.get_children():
		child.queue_free()
	var step_num := 1
	for step_text in steps:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var num_label = Label.new()
		num_label.text = "%d." % step_num
		num_label.add_theme_font_size_override("font_size", 11)
		num_label.add_theme_color_override("font_color", HFThemeUtils.accent())
		num_label.custom_minimum_size = Vector2(18, 0)
		row.add_child(num_label)

		var text_label = Label.new()
		text_label.text = step_text
		text_label.add_theme_font_size_override("font_size", 11)
		text_label.add_theme_color_override("font_color", HFThemeUtils.primary_text())
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_label)

		_steps_container.add_child(row)
		step_num += 1


func _is_guide_dismissed(tool_key: String) -> bool:
	if not _user_prefs:
		return false
	var key := "coach_dismissed_" + tool_key
	return _user_prefs.is_hint_dismissed(key)


func _on_dismiss() -> void:
	var dont_show: bool = _dont_show.button_pressed
	if dont_show and _user_prefs and not _current_tool_key.is_empty():
		_user_prefs.dismiss_hint("coach_dismissed_" + _current_tool_key)
	guide_dismissed.emit(_current_tool_key, dont_show)
	hide_guide()


## Get all available guide keys.
static func get_guide_keys() -> PackedStringArray:
	return PackedStringArray(GUIDES.keys())
