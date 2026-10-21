@tool
extends PanelContainer
## Small floating property popup that appears at cursor for quick numeric input.
## Triggered by double-tap hotkeys: G G (grid snap), B B (brush size), R R (paint
## radius), and by Offset (Alt+G), which adds a World / Local choice.
## Auto-dismisses on Enter, Escape, or click-away.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFThemeUtils = preload("hf_theme_utils.gd")
@warning_ignore_restore("shadowed_global_identifier")

signal value_committed(property_type: int, values: Array)

enum PropertyType { GRID_SNAP, BRUSH_SIZE, PAINT_RADIUS, OFFSET }

## Only used when the caller has no control to take a range from.
const DEFAULT_GRID_SNAP_RANGE := {"min": 0.0, "max": 128.0, "step": 0.05}
const DEFAULT_BRUSH_SIZE_RANGE := {"min": 0.05, "max": 256.0, "step": 0.05}
const DEFAULT_PAINT_RADIUS_RANGE := {"min": 0.01, "max": 0.5, "step": 0.01}
## An offset goes either way, as far as a level reaches, to the millimetre.
const OFFSET_RANGE := {"min": -65536.0, "max": 65536.0, "step": 0.001}
## Under Local when the selection does not all face one way.
const NO_SHARED_AXES_TEXT := "No shared axes: moves along the world's"

var _type: int = PropertyType.GRID_SNAP
var _vbox: VBoxContainer
var _spinboxes: Array[SpinBox] = []
var _active := false
## Offset's World / Local choice, and the line that says Local has no axes of
## its own to go by. Null for the other properties.
var _local_button: Button = null
var _note: Label = null
var _shares_basis := true


func _init() -> void:
	name = "HFQuickProperty"
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	z_index = 100
	custom_minimum_size = Vector2(160, 0)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	add_child(_vbox)


func _ready() -> void:
	_apply_style()


## Show the popup for one property.
##
## `ranges` carries the min/max/step of the dock controls the committed value
## is written into, one entry per field. Restating them here instead meant the
## popup offered values the control could not hold - its own default radius was
## ten times that control's maximum, and the brush size step of 0.5 from a
## minimum of 0.1 could not express a whole number at all, so opening the popup
## on a 4 unit brush showed 4.1 and committing it changed the size.
func show_property(type: int, pos: Vector2, current_values: Array, ranges: Array = []) -> void:
	_type = type
	_clear_fields()

	match type:
		PropertyType.GRID_SNAP:
			var r: Dictionary = _range_at(ranges, 0, DEFAULT_GRID_SNAP_RANGE)
			_add_labeled_spin(
				"Grid Snap",
				r["min"],
				r["max"],
				r["step"],
				current_values[0] if not current_values.is_empty() else 16.0
			)
		PropertyType.BRUSH_SIZE:
			var defaults: Array = current_values if current_values.size() >= 3 else [4.0, 4.0, 4.0]
			for i in range(3):
				var r: Dictionary = _range_at(ranges, i, DEFAULT_BRUSH_SIZE_RANGE)
				_add_labeled_spin(["X", "Y", "Z"][i], r["min"], r["max"], r["step"], defaults[i])
		PropertyType.PAINT_RADIUS:
			var r: Dictionary = _range_at(ranges, 0, DEFAULT_PAINT_RADIUS_RANGE)
			_add_labeled_spin(
				"Radius",
				r["min"],
				r["max"],
				r["step"],
				current_values[0] if not current_values.is_empty() else r["min"]
			)
	await _present(pos)


## The Offset popup: X, Y and Z at `offset`, and World or Local as `local` says.
## `shares_basis` is whether the selection all faces one way. When it does not,
## Local says it moves along the world's axes, which is what it will do.
func show_offset(pos: Vector2, offset: Vector3, local: bool, shares_basis: bool) -> void:
	_type = PropertyType.OFFSET
	_clear_fields()
	for i in range(3):
		_add_labeled_spin(
			["X", "Y", "Z"][i],
			OFFSET_RANGE["min"],
			OFFSET_RANGE["max"],
			OFFSET_RANGE["step"],
			offset[i]
		)
	_shares_basis = shares_basis
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	var world_button := Button.new()
	world_button.text = "World"
	world_button.toggle_mode = true
	world_button.button_group = group
	world_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(world_button)
	_local_button = Button.new()
	_local_button.text = "Local"
	_local_button.toggle_mode = true
	_local_button.button_group = group
	_local_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_local_button.tooltip_text = "Along the selection's own axes"
	row.add_child(_local_button)
	_vbox.add_child(row)
	_note = Label.new()
	_note.text = NO_SHARED_AXES_TEXT
	_note.add_theme_font_size_override("font_size", 10)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_note)
	_local_button.toggled.connect(_on_local_toggled)
	world_button.button_pressed = not local
	_local_button.button_pressed = local
	_on_local_toggled(local)
	await _present(pos)


## Whether Offset's Local is chosen. False for the other properties.
func is_local() -> bool:
	return _local_button != null and _local_button.button_pressed


## Whether the popup is saying that Local falls back to the world's axes.
func is_showing_no_shared_axes() -> bool:
	return _note != null and _note.visible


func _on_local_toggled(local: bool) -> void:
	if _note:
		_note.visible = local and not _shares_basis


func _clear_fields() -> void:
	_spinboxes.clear()
	_local_button = null
	_note = null
	_shares_basis = true
	for child in _vbox.get_children():
		_vbox.remove_child(child)
		child.queue_free()


func _present(pos: Vector2) -> void:
	_active = true
	visible = true
	_apply_style()

	# Position at cursor, clamped to parent bounds.
	# pos is in the same coordinate space as CONTAINER_SPATIAL_EDITOR_MENU overlays
	# (identical to event.position from _forward_3d_gui_input).
	await get_tree().process_frame
	var parent_size := get_parent_area_size()
	var panel_size := size
	var clamped_x := clampf(pos.x, 8.0, parent_size.x - panel_size.x - 8.0)
	var clamped_y := clampf(pos.y, 8.0, parent_size.y - panel_size.y - 8.0)
	position = Vector2(clamped_x, clamped_y)

	# Focus first spinbox
	if not _spinboxes.is_empty():
		_spinboxes[0].get_line_edit().grab_focus()
		_spinboxes[0].get_line_edit().select_all()


## The range for field `index`, falling back to `fallback` when the caller gave
## none. A single entry stands for every field.
static func _range_at(ranges: Array, index: int, fallback: Dictionary) -> Dictionary:
	if ranges.is_empty():
		return fallback
	var entry = ranges[index] if index < ranges.size() else ranges[0]
	if not (entry is Dictionary):
		return fallback
	return {
		"min": float(entry.get("min", fallback["min"])),
		"max": float(entry.get("max", fallback["max"])),
		"step": float(entry.get("step", fallback["step"])),
	}


func hide_popup() -> void:
	if not _active:
		return
	_active = false
	visible = false


func is_active() -> bool:
	return _active


func _add_labeled_spin(
	label_text: String, min_val: float, max_val: float, step: float, value: float
) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.custom_minimum_size.x = 52
	hbox.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 80
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.get_line_edit().gui_input.connect(_on_spin_key.bind(spin))
	hbox.add_child(spin)
	_vbox.add_child(hbox)
	_spinboxes.append(spin)


func _on_spin_key(event: InputEvent, _spin: SpinBox) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_commit_and_close()
			KEY_ESCAPE:
				hide_popup()


func _commit_and_close() -> void:
	var values: Array = []
	for spin in _spinboxes:
		# The key handler runs before the line edit has taken the Enter, so a
		# number typed into the field is not the spin's value yet.
		spin.apply()
		values.append(spin.value)
	if _type == PropertyType.OFFSET:
		values.append(is_local())
	value_committed.emit(_type, values)
	hide_popup()


func _apply_style() -> void:
	var style := HFThemeUtils.make_panel_stylebox(self)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)


func refresh_theme_colors() -> void:
	_apply_style()
