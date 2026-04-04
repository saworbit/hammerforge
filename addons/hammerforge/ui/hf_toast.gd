@tool
extends VBoxContainer
## Lightweight toast notification system for surfacing messages to the user.
## Stacks up to MAX_TOASTS transient labels that auto-fade after a duration.

const MAX_TOASTS := 5

enum Level { INFO, WARNING, ERROR }

# Duration per level in seconds.
const DURATION_INFO := 4.0
const DURATION_WARNING := 6.0
const DURATION_ERROR := 8.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("separation", 4)


## Show a toast message at the given level.
func show_toast(message: String, level: int = Level.INFO) -> void:
	# Enforce max visible toasts by removing the oldest.
	while get_child_count() >= MAX_TOASTS:
		var oldest = get_child(0)
		remove_child(oldest)
		oldest.queue_free()

	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4

	match level:
		Level.WARNING:
			style.bg_color = HFThemeUtils.toast_warning_bg()
		Level.ERROR:
			style.bg_color = HFThemeUtils.toast_error_bg()
		_:
			style.bg_color = HFThemeUtils.toast_bg()

	panel.add_theme_stylebox_override("panel", style)

	var label = Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	add_child(panel)

	# Auto-fade and remove.
	var duration := DURATION_INFO
	match level:
		Level.WARNING:
			duration = DURATION_WARNING
		Level.ERROR:
			duration = DURATION_ERROR

	var tween = create_tween()
	tween.tween_interval(duration - 1.0)
	tween.tween_property(panel, "modulate:a", 0.0, 1.0)
	tween.tween_callback(
		func():
			if is_instance_valid(panel):
				remove_child(panel)
				panel.queue_free()
	)
