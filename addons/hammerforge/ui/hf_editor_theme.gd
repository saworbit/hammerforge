@tool
class_name HFEditorTheme
extends RefCounted
## Static helpers for resolving editor icons, colors, and styleboxes from the
## current EditorInterface base control.  Extracted from dock.gd so any UI
## module (panels, toolbars, popups) can pull editor-themed visuals without
## reaching into the dock.
##
## All helpers fall back gracefully when the base_control is null (e.g. when
## the dock is constructed in a test harness without the editor).


static func find_editor_icon(base: Control, fallback: Control, icon_names: Array) -> Texture2D:
	for icon_name in icon_names:
		if has_editor_icon(base, fallback, icon_name):
			return get_editor_icon(base, fallback, icon_name)
	return null


static func has_editor_icon(base: Control, fallback: Control, icon_name: String) -> bool:
	if base and base.has_theme_icon(icon_name, "EditorIcons"):
		return true
	if fallback and fallback.has_theme_icon(icon_name, "EditorIcons"):
		return true
	return false


static func get_editor_icon(base: Control, fallback: Control, icon_name: String) -> Texture2D:
	if base and base.has_theme_icon(icon_name, "EditorIcons"):
		return base.get_theme_icon(icon_name, "EditorIcons")
	if fallback:
		return fallback.get_theme_icon(icon_name, "EditorIcons")
	return null


static func get_editor_color(
	base: Control, fallback: Control, color_name: String, default: Color
) -> Color:
	if base and base.has_theme_color(color_name, "Editor"):
		return base.get_theme_color(color_name, "Editor")
	if base and base.has_theme_color(color_name, "EditorStyles"):
		return base.get_theme_color(color_name, "EditorStyles")
	if fallback and fallback.has_theme_color(color_name, "Editor"):
		return fallback.get_theme_color(color_name, "Editor")
	return default


static func resolve_stylebox(base: Control, name: String, type_name: String) -> StyleBox:
	if not base:
		return null
	if base.has_theme_stylebox(name, type_name):
		return base.get_theme_stylebox(name, type_name)
	if base.theme and base.theme.has_stylebox(name, type_name):
		return base.theme.get_stylebox(name, type_name)
	return null


## Apply icon + flat/focus styling to a toolbar button. icon_names is a
## priority list — the first one found in editor theme wins.
static func style_toolbar_button(
	base: Control, fallback: Control, button: Button, icon_names: Array, fallback_text: String
) -> void:
	if not button:
		return
	var icon := find_editor_icon(base, fallback, icon_names)
	if icon:
		button.icon = icon
	button.text = fallback_text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
