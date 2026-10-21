@tool
extends VBoxContainer
## The Colours block of Test > Settings (#1446): a colour button for each overlay
## colour in `HFOverlayColors`, a High Contrast preset and a Reset.
##
## It only edits the preferences. `colors_changed` tells the dock, and through it
## the plugin, which sets the palette from them and redraws what is up.

const HFOverlayColors = preload("../hf_overlay_colors.gd")
const HFUIFactoryType = preload("hf_ui_factory.gd")

## A colour, the preset or Reset changed one or more preferences.
signal colors_changed

var high_contrast_btn: Button = null
var reset_btn: Button = null

var _prefs: HFUserPrefs = null
## The colour button for each key.
var _pickers: Dictionary = {}


func _init() -> void:
	name = "OverlayColors"
	var heading := Label.new()
	heading.text = "Colours"
	add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	for key in HFOverlayColors.DEFAULTS:
		var label := Label.new()
		label.text = HFOverlayColors.LABELS[key]
		label.tooltip_text = HFOverlayColors.TOOLTIPS[key]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(label)
		var picker := ColorPickerButton.new()
		picker.name = key
		picker.edit_alpha = true
		picker.color = HFOverlayColors.DEFAULTS[key]
		picker.custom_minimum_size = Vector2(48, 0)
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.tooltip_text = HFOverlayColors.TOOLTIPS[key]
		picker.color_changed.connect(_on_picker_changed.bind(key))
		# Held in memory while the picker is open, and written once it closes,
		# rather than once a frame while a slider is dragged.
		picker.popup_closed.connect(_on_picker_closed)
		grid.add_child(picker)
		_pickers[key] = picker
	var row := HFUIFactoryType.make_wrap_row()
	high_contrast_btn = HFUIFactoryType.make_button(
		"High Contrast",
		(
			"Colours that stay apart for the common kinds of colour blindness\n"
			+ "Solids and cuts differ in brightness as well as hue"
		)
	)
	high_contrast_btn.pressed.connect(apply_preset.bind(HFOverlayColors.HIGH_CONTRAST))
	row.add_child(high_contrast_btn)
	reset_btn = HFUIFactoryType.make_button("Reset", "Every overlay colour back to its default")
	reset_btn.pressed.connect(apply_preset.bind(HFOverlayColors.DEFAULTS))
	row.add_child(reset_btn)
	add_child(row)


## Show and edit the colours `prefs` holds. Null leaves the buttons on the
## defaults, editing nothing.
func set_user_prefs(prefs: HFUserPrefs) -> void:
	_prefs = prefs
	_sync_pickers()


## The colour button for overlay colour `key`, or null.
func get_picker(key: String) -> ColorPickerButton:
	return _pickers.get(key, null) as ColorPickerButton


## Set every colour from `colors`, a colour by key, and save.
func apply_preset(colors: Dictionary) -> void:
	if _prefs == null:
		return
	_prefs.set_overlay_colors(colors)
	_sync_pickers()
	colors_changed.emit()


func _sync_pickers() -> void:
	for key in _pickers:
		var value: Variant = _prefs.get_pref(key) if _prefs else null
		# Setting the colour from code does not emit color_changed.
		(_pickers[key] as ColorPickerButton).color = HFOverlayColors.from_pref(value, key)


func _on_picker_changed(color: Color, key: String) -> void:
	if _prefs == null:
		return
	_prefs.set_pref(key, color)
	colors_changed.emit()


func _on_picker_closed() -> void:
	if _prefs:
		_prefs.save()
