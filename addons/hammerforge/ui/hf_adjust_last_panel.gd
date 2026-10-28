@tool
extends PanelContainer
## Adjust Last (#1867): the settings the last command ran with, in a corner of the
## viewport, as controls built from the command's `params`. Changing one asks for
## the command again with the new value, which the plugin does as one step in
## place of the first. A saved set of settings can be picked by name.
##
## It only asks. `setting_changed` and `preset_saved` go to
## `plugin_adjust_last.gd`, which undoes, runs again and keeps the names.

const HFUIFactoryType = preload("hf_ui_factory.gd")
const HFTranslationType = preload("res://addons/hammerforge/hf_translation.gd")

## One setting of the shown command took `value`.
signal setting_changed(key: String, value: Variant)
## The settings shown now are to be kept as `preset_name`.
signal preset_saved(preset_name: String)
## A saved set was picked.
signal preset_picked(preset_name: String)
signal close_requested

const AXES := ["x", "y", "z"]

var _title: Label = null
var _fields: GridContainer = null
var _presets: OptionButton = null
var _preset_name: LineEdit = null
## The control for each setting, by key.
var _controls: Dictionary = {}
## The setting each control is for, by key.
var _schema: Dictionary = {}
## What a setting shown and not changed here holds: a string or a face, as a
## material Replace Material swapped or the face a Clip to Face Plane cut along
## (#1896), by key.
var _fixed: Dictionary = {}
## Set while the controls are filled from code, so they do not ask to run.
var _filling := false


func _init() -> void:
	name = "AdjustLast"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var box := VBoxContainer.new()
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := HFUIFactoryType.make_button("x", "Close Adjust Last")
	close.flat = true
	close.pressed.connect(func(): close_requested.emit())
	header.add_child(close)
	_fields = GridContainer.new()
	_fields.columns = 2
	box.add_child(_fields)
	var preset_row := HBoxContainer.new()
	_presets = HFUIFactoryType.make_option([])
	_presets.tooltip_text = "Settings saved under a name for this command"
	_presets.item_selected.connect(_on_preset_selected)
	preset_row.add_child(_presets)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "Name"
	_preset_name.custom_minimum_size.x = 80
	preset_row.add_child(_preset_name)
	var save := HFUIFactoryType.make_button("Save", "Keep these settings under the name")
	save.pressed.connect(_on_save_pressed)
	preset_row.add_child(save)
	box.add_child(preset_row)


## Show `label`'s settings, `params` in `HFGeneratorSchema`'s shape, at `values`,
## with the names `preset_names` saved for it.
func show_command(
	label: String, params: Array, values: Dictionary, preset_names: PackedStringArray
) -> void:
	_filling = true
	_title.text = HFTranslationType.t("Adjust {command}").format({"command": label})
	for child in _fields.get_children():
		_fields.remove_child(child)
		child.queue_free()
	_controls.clear()
	_schema.clear()
	_fixed.clear()
	for field_def in params:
		var key := str(field_def.get("key", ""))
		if key == "":
			continue
		var label_node := Label.new()
		label_node.text = str(field_def.get("label", key.capitalize()))
		label_node.tooltip_text = str(field_def.get("description", ""))
		label_node.mouse_filter = Control.MOUSE_FILTER_PASS
		_fields.add_child(label_node)
		var control := _control_for(field_def)
		control.name = key
		control.tooltip_text = label_node.tooltip_text
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_fields.add_child(control)
		_controls[key] = control
		_schema[key] = field_def
		if values.has(key):
			_set_value(key, values[key])
		_watch(key, control)
	_presets.clear()
	_presets.add_item("Saved settings")
	for preset in preset_names:
		_presets.add_item(preset)
	_presets.selected = 0
	_filling = false
	visible = true


## The value the control for `key` shows, in the type its setting takes.
func value_of(key: String) -> Variant:
	var control: Control = _controls.get(key, null)
	var field_def: Dictionary = _schema.get(key, {})
	if control == null:
		return null
	match str(field_def.get("type", "float")):
		"bool":
			return (control as CheckBox).button_pressed
		"axis":
			return AXES[(control as OptionButton).selected]
		"enum":
			return (control as OptionButton).selected
		"int":
			return int((control as SpinBox).value)
		"vec3":
			var spins := control.get_children()
			return Vector3(spins[0].value, spins[1].value, spins[2].value)
		"string", "face":
			return _fixed.get(key)
	return (control as SpinBox).value


## The control for `key`, or null.
func control_for(key: String) -> Control:
	return _controls.get(key, null)


func _control_for(field_def: Dictionary) -> Control:
	match str(field_def.get("type", "float")):
		"bool":
			return HFUIFactoryType.make_check("", bool(field_def.get("default", false)))
		"axis":
			var axis := HFUIFactoryType.make_option(["X", "Y", "Z"])
			axis.selected = maxi(0, AXES.find(str(field_def.get("default", "y"))))
			return axis
		"enum":
			var option := HFUIFactoryType.make_option(field_def.get("options", []))
			option.selected = int(field_def.get("default", 0))
			return option
		"vec3":
			var row := HBoxContainer.new()
			for i in 3:
				row.add_child(_spin(field_def))
			return row
		"string", "face":
			# Shown, not changed: what a step was made from.
			var shown := Label.new()
			shown.clip_text = true
			return shown
	return _spin(field_def)


func _spin(field_def: Dictionary) -> SpinBox:
	var step := float(field_def.get("step", 1.0 if str(field_def.get("type")) == "int" else 0.05))
	var spin := HFUIFactoryType.make_spin(
		float(field_def.get("min", -100000.0)),
		float(field_def.get("max", 100000.0)),
		step,
		float(field_def.get("default", 0.0))
	)
	spin.custom_minimum_size.x = 72
	return spin


func _set_value(key: String, value: Variant) -> void:
	var control: Control = _controls[key]
	match str(_schema[key].get("type", "float")):
		"bool":
			(control as CheckBox).button_pressed = bool(value)
		"axis":
			(control as OptionButton).selected = maxi(0, AXES.find(str(value)))
		"enum":
			# By its option, as the bridge takes it, or by index.
			var options: Array = _schema[key].get("options", [])
			var at_option := options.find(value) if value is String else int(value)
			(control as OptionButton).selected = maxi(0, at_option)
		"vec3":
			var at: Vector3 = value if value is Vector3 else Vector3.ZERO
			var spins := control.get_children()
			for i in 3:
				(spins[i] as SpinBox).value = at[i]
		"string", "face":
			_fixed[key] = value
			# A material's file shows by its name, not its folder.
			var text := str(value)
			(control as Label).text = text.get_file() if text.contains("/") else text
		_:
			(control as SpinBox).value = float(value)


func _watch(key: String, control: Control) -> void:
	var changed := func(_value = null): _on_control_changed(key)
	if control is CheckBox:
		(control as CheckBox).toggled.connect(changed)
	elif control is OptionButton:
		(control as OptionButton).item_selected.connect(changed)
	elif control is SpinBox:
		(control as SpinBox).value_changed.connect(changed)
	elif control is Label:
		return
	else:
		for spin in control.get_children():
			(spin as SpinBox).value_changed.connect(changed)


func _on_control_changed(key: String) -> void:
	if _filling:
		return
	setting_changed.emit(key, value_of(key))


## Put `values` on the controls without asking to run.
func fill(values: Dictionary) -> void:
	_filling = true
	for key in values:
		if _controls.has(key):
			_set_value(key, values[key])
	_filling = false


func _on_save_pressed() -> void:
	var preset := _preset_name.text.strip_edges()
	if preset == "":
		return
	preset_saved.emit(preset)
	_preset_name.text = ""


func _on_preset_selected(index: int) -> void:
	if _filling or index <= 0:
		return
	preset_picked.emit(_presets.get_item_text(index))
	_presets.selected = 0
