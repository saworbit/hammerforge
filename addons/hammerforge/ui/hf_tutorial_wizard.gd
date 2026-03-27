@tool
extends PanelContainer
## Interactive step-by-step tutorial wizard for first-time HammerForge users.
##
## Walks through 5 core actions (draw, subtract, paint, entity, bake),
## detecting completion via LevelRoot signals.  Progress persists across
## editor restarts via user prefs.

signal completed
signal dismissed(dont_show_again: bool)

const STEPS: Array[Dictionary] = [
	{
		"title": "Step 1 — Draw your first room",
		"text":
		"Make sure the Brush tab is active and Operation is set to Add.\nClick and drag in the 3D viewport to draw a box brush.",
		"signal_name": "brush_added",
		"validate": "",
		"highlight_tab": "Brush",
	},
	{
		"title": "Step 2 — Subtract a window",
		"text":
		'Set the Operation to Subtract (the "-" button in the toolbar).\nDraw a smaller brush overlapping your room to carve an opening.',
		"signal_name": "brush_added",
		"validate": "_validate_subtract",
		"highlight_tab": "Brush",
	},
	{
		"title": "Step 3 — Paint a floor",
		"text":
		"Switch to the Paint tab and click on floor cells to paint them.\nToggle Paint Mode (P) in the toolbar first.",
		"signal_name": "paint_layer_changed",
		"validate": "",
		"highlight_tab": "Paint",
	},
	{
		"title": "Step 4 — Place an entity",
		"text": "Go to the Entities tab and drag an entity from the palette\ninto the 3D viewport.",
		"signal_name": "entity_added",
		"validate": "",
		"highlight_tab": "Entities",
	},
	{
		"title": "Step 5 — Bake & Preview",
		"text":
		"Open the Manage tab and click Bake.\nThis converts your brushes into final playable geometry.",
		"signal_name": "bake_finished",
		"validate": "_validate_bake_success",
		"highlight_tab": "Manage",
	},
]

var _current_step: int = 0
var _root = null  # LevelRoot (untyped to avoid circular preload)
var _dock = null  # Dock control reference
var _user_prefs = null  # HFUserPrefs

var _title_label: Label
var _text_label: RichTextLabel
var _progress: ProgressBar
var _step_counter: Label
var _skip_btn: Button
var _dismiss_btn: Button
var _dont_show: CheckBox
var _connected_signal := ""
var _started := false


func _ready() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18, 1.0)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	_build_ui()


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1.0))
	vbox.add_child(_title_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = false
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(_text_label)

	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = STEPS.size()
	_progress.custom_minimum_size = Vector2(0, 14)
	_progress.show_percentage = false
	vbox.add_child(_progress)

	_step_counter = Label.new()
	_step_counter.add_theme_font_size_override("font_size", 11)
	_step_counter.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_step_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_step_counter)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)

	_dont_show = CheckBox.new()
	_dont_show.text = "Don't show again"
	_dont_show.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_dont_show)

	_skip_btn = Button.new()
	_skip_btn.text = "Skip Step"
	_skip_btn.pressed.connect(_on_skip)
	bottom.add_child(_skip_btn)

	_dismiss_btn = Button.new()
	_dismiss_btn.text = "Dismiss"
	_dismiss_btn.pressed.connect(_on_dismiss)
	bottom.add_child(_dismiss_btn)


## Begin the tutorial, optionally resuming from a saved step.
func start(root, dock, start_step: int = 0) -> void:
	_root = root
	_dock = dock
	_started = true
	_current_step = clampi(start_step, 0, STEPS.size() - 1)
	_apply_step()


## Set user prefs for persistence.
func set_user_prefs(prefs) -> void:
	_user_prefs = prefs


## Connect to root signals when root becomes available after start.
## If start() was never called (no root at launch), this also initializes the
## wizard UI so first-launch users don't see a blank panel.
func set_root(root, dock = null) -> void:
	_disconnect_current()
	_root = root
	if dock:
		_dock = dock
	if _root and not _started:
		# start() was never called — do the full initialization now
		var start_step: int = 0
		if _user_prefs:
			start_step = int(_user_prefs.get_pref("tutorial_step", 0))
		_current_step = clampi(start_step, 0, STEPS.size() - 1)
		_started = true
		_apply_step()
	elif _root and _current_step < STEPS.size():
		_connect_step_signal()


func _apply_step() -> void:
	if _current_step >= STEPS.size():
		_on_complete()
		return
	var step: Dictionary = STEPS[_current_step]
	_title_label.text = step["title"]
	_text_label.text = step["text"]
	_progress.value = _current_step
	_step_counter.text = "%d / %d" % [_current_step + 1, STEPS.size()]
	_highlight_tab(step.get("highlight_tab", ""))
	_connect_step_signal()
	_persist_step()


func _connect_step_signal() -> void:
	_disconnect_current()
	if not _root or _current_step >= STEPS.size():
		return
	var sig_name: String = STEPS[_current_step]["signal_name"]
	if sig_name.is_empty():
		return
	if _root.has_signal(sig_name):
		_root.connect(sig_name, Callable(self, "_on_signal_received"))
		_connected_signal = sig_name


func _disconnect_current() -> void:
	if _connected_signal.is_empty() or not _root:
		return
	if (
		_root.has_signal(_connected_signal)
		and _root.is_connected(_connected_signal, Callable(self, "_on_signal_received"))
	):
		_root.disconnect(_connected_signal, Callable(self, "_on_signal_received"))
	_connected_signal = ""


func _on_signal_received(arg1 = null, _arg2 = null) -> void:
	if _current_step >= STEPS.size():
		return
	var step: Dictionary = STEPS[_current_step]
	var validator: String = step.get("validate", "")
	if not validator.is_empty() and has_method(validator):
		if not call(validator, arg1):
			return
	_advance_step()


func _advance_step() -> void:
	_disconnect_current()
	_current_step += 1
	_apply_step()


func _validate_bake_success(success) -> bool:
	return success == true


func _validate_subtract(brush_id) -> bool:
	if not _root or not _root.has_method("find_brush_by_id"):
		return true
	var brush = _root.find_brush_by_id(str(brush_id))
	if not brush:
		return true
	if brush is CSGShape3D:
		return brush.operation == CSGShape3D.OPERATION_SUBTRACTION
	return true


func _highlight_tab(tab_name: String) -> void:
	if not _dock or tab_name.is_empty():
		return
	if _dock.has_method("highlight_tab"):
		_dock.highlight_tab(tab_name)


func _persist_step() -> void:
	if _user_prefs:
		_user_prefs.set_pref("tutorial_step", _current_step)
		_user_prefs.save()


func _on_skip() -> void:
	_advance_step()


func _on_dismiss() -> void:
	_disconnect_current()
	dismissed.emit(_dont_show.button_pressed)


func _on_complete() -> void:
	_disconnect_current()
	_progress.value = STEPS.size()
	_step_counter.text = "Done!"
	_title_label.text = "Tutorial Complete"
	_text_label.text = "You've learned the basics of HammerForge!\nPress ? in the toolbar anytime to see all shortcuts."
	_skip_btn.visible = false
	_dismiss_btn.text = "Close"
	if _user_prefs:
		_user_prefs.set_pref("tutorial_step", STEPS.size())
		_user_prefs.save()
	completed.emit()


## Get the current step index (for testing / persistence).
func get_current_step() -> int:
	return _current_step


## Get total number of steps.
static func get_step_count() -> int:
	return STEPS.size()
