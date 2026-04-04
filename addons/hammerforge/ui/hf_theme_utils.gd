@tool
class_name HFThemeUtils
extends RefCounted
## Shared theme-aware color helpers for HammerForge custom UI.
## All methods are static — no instance needed.


static func is_dark_theme(base: Control = null) -> bool:
	var base_color := _get_base_color(base)
	return base_color.get_luminance() < 0.5


static func panel_bg(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.1, 0.12, 0.16, 0.95)
	return Color(0.92, 0.93, 0.95, 0.95)


static func panel_border(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.3, 0.4, 0.6, 0.5)
	return Color(0.6, 0.62, 0.68, 0.5)


static func muted_text(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.7, 0.75, 0.85, 0.8)
	return Color(0.3, 0.32, 0.38, 0.8)


static func primary_text(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.9, 0.92, 0.96, 1.0)
	return Color(0.1, 0.1, 0.12, 1.0)


static func accent(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.35, 0.55, 0.9, 1.0)
	return Color(0.2, 0.4, 0.8, 1.0)


static func success_color(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.2, 0.85, 0.35, 1.0)
	return Color(0.1, 0.65, 0.25, 1.0)


static func warning_color(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.95, 0.8, 0.2, 1.0)
	return Color(0.75, 0.6, 0.05, 1.0)


static func error_color(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.95, 0.3, 0.3, 1.0)
	return Color(0.8, 0.15, 0.15, 1.0)


static func toast_bg(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.2, 0.2, 0.2, 0.88)
	return Color(0.88, 0.88, 0.88, 0.92)


static func toast_warning_bg(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.55, 0.45, 0.1, 0.92)
	return Color(0.95, 0.85, 0.55, 0.92)


static func toast_error_bg(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(0.55, 0.15, 0.15, 0.92)
	return Color(0.95, 0.6, 0.6, 0.92)


static func toast_text(base: Control = null) -> Color:
	if is_dark_theme(base):
		return Color(1.0, 1.0, 1.0, 0.95)
	return Color(0.1, 0.1, 0.1, 0.95)


static func make_panel_stylebox(base: Control = null) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = panel_bg(base)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.border_width_bottom = 2
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_color = panel_border(base)
	return style


static func _get_base_color(base: Control = null) -> Color:
	if Engine.is_editor_hint():
		var es = EditorInterface.get_editor_settings()
		if es:
			return es.get_setting("interface/theme/base_color")
	if base and base.theme:
		var style = base.theme.get_stylebox("panel", "PanelContainer")
		if style is StyleBoxFlat:
			return style.bg_color
	return Color(0.15, 0.15, 0.17, 1.0)
