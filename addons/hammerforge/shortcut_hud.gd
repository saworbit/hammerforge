@tool
extends Control

@onready var label: Label = $Panel/Margin/Label

var _last_context := {}
var _user_prefs = null  # HFUserPrefs — untyped to avoid preload
var _hint_label: Label
var _hint_tween: Tween
var _current_hint_key := ""
# Grid size indicator
var _grid_label: Label
var _grid_flash_tween: Tween
var _last_grid_snap := -1.0

const MODE_HINTS := {
	"draw_idle":
	(
		"Click to place corner \u2192 drag to set size \u2192 release for height\n"
		+ "Empty scene? Use Manage > Create Floor for a stable draw surface"
	),
	"select": "Click brush to select, Shift+click to multi-select, drag to move",
	"extrude_up_idle": "Click a face to start extruding upward",
	"extrude_down_idle": "Click a face to start extruding downward",
	"paint_floor": "Click cells to paint, Shift+click to erase",
	"paint_surface": "Click brush faces to apply material",
	"vertex_edit": "Click vertex to select, drag to move, X/Y/Z to lock axis",
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_layout()
	_setup_hint_label()
	_setup_grid_label()
	update_context({})


func _apply_layout() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -270.0
	offset_top = 8.0
	offset_right = -8.0
	offset_bottom = 200.0


func set_user_prefs(prefs) -> void:
	_user_prefs = prefs


func _setup_hint_label() -> void:
	if not has_node("Panel/Margin/Label"):
		return
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.7))
	_hint_label.visible = false
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Panel/Margin.add_child(_hint_label)


func _setup_grid_label() -> void:
	if not has_node("Panel/Margin/Label"):
		return
	_grid_label = Label.new()
	_grid_label.name = "GridLabel"
	_grid_label.add_theme_font_size_override("font_size", 12)
	_grid_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.8))
	_grid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_grid_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Panel/Margin.add_child(_grid_label)


func update_grid_snap(value: float) -> void:
	if not _grid_label:
		return
	# Format: display exact value, strip trailing zeros
	var text: String
	if is_equal_approx(value, roundf(value)):
		text = "Grid: %d" % int(value)
	else:
		# Use enough precision to represent small snaps like 0.125 exactly
		var s := "%g" % value
		text = "Grid: %s" % s
	_grid_label.text = text
	# Flash on change (skip initial set)
	if _last_grid_snap >= 0.0 and not is_equal_approx(_last_grid_snap, value):
		_flash_grid_label()
	_last_grid_snap = value


func _flash_grid_label() -> void:
	if not _grid_label:
		return
	if _grid_flash_tween and _grid_flash_tween.is_valid():
		_grid_flash_tween.kill()
	# Bright flash then fade back to normal
	_grid_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6, 1.0))
	_grid_flash_tween = create_tween()
	(
		_grid_flash_tween
		. tween_property(
			_grid_label, "theme_override_colors/font_color", Color(0.7, 0.85, 1.0, 0.8), 0.6
		)
		. set_ease(Tween.EASE_OUT)
	)


func update_context(ctx: Dictionary) -> void:
	if ctx == _last_context:
		return
	_last_context = ctx.duplicate()
	if not label:
		return
	label.text = _build_shortcuts_text(ctx)
	_check_mode_hint(ctx)


func _check_mode_hint(ctx: Dictionary) -> void:
	if not _hint_label:
		return
	var key := _compute_hint_key(ctx)
	if key == _current_hint_key:
		return
	_current_hint_key = key
	if key.is_empty():
		_hide_hint()
		return
	if _user_prefs and _user_prefs.is_hint_dismissed(key):
		_hide_hint()
		return
	if not MODE_HINTS.has(key):
		_hide_hint()
		return
	_show_hint(MODE_HINTS[key])


func _compute_hint_key(ctx: Dictionary) -> String:
	var tool_id: int = ctx.get("tool", 0)
	var mode: int = ctx.get("mode", 0)
	var is_paint: bool = ctx.get("paint_mode", false)

	if is_paint:
		var paint_target: int = ctx.get("paint_target", 0)
		return "paint_surface" if paint_target == 1 else "paint_floor"

	# mode 5 = VERTEX_EDIT
	if mode == 5:
		return "vertex_edit"

	if tool_id == 1:
		return "select"

	if tool_id == 2:
		return "extrude_up_idle" if mode != 4 else ""
	if tool_id == 3:
		return "extrude_down_idle" if mode != 4 else ""

	# Draw tool — only show hint when idle
	if mode == 0:
		return "draw_idle"
	return ""


func _show_hint(text: String) -> void:
	_hint_label.text = "\n" + text
	_hint_label.modulate = Color(1, 1, 1, 1)
	_hint_label.visible = true
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(4.0)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, 1.0)
	_hint_tween.tween_callback(_hide_hint)


func _hide_hint() -> void:
	if _hint_label:
		_hint_label.visible = false
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
		_hint_tween = null


func dismiss_current_hint() -> void:
	if _current_hint_key.is_empty():
		return
	if _user_prefs:
		_user_prefs.dismiss_hint(_current_hint_key)
	_hide_hint()


func _build_shortcuts_text(ctx: Dictionary) -> String:
	var tool_id: int = ctx.get("tool", 0)
	var mode: int = ctx.get("mode", 0)
	var is_paint: bool = ctx.get("paint_mode", false)
	var paint_target: int = ctx.get("paint_target", 0)
	var axis_lock: int = ctx.get("axis_lock", 0)
	var numeric: String = ctx.get("numeric", "")

	var text := ""
	if numeric.length() > 0:
		text = "[Size: %s] Type digits, Enter to apply\n" % numeric

	if is_paint:
		if paint_target == 1:
			return text + _surface_paint_shortcuts()
		return text + _floor_paint_shortcuts()

	if tool_id == 1:
		return text + _select_mode_shortcuts()

	# mode 5 = VERTEX_EDIT
	if mode == 5:
		return text + _vertex_edit_shortcuts()

	if tool_id == 2 or tool_id == 3:
		var dir_label := "Up" if tool_id == 2 else "Down"
		# mode 4 = EXTRUDE (from HFInputState)
		if mode == 4:
			return text + _extrude_active_shortcuts(dir_label)
		return text + _extrude_idle_shortcuts(dir_label)

	# Draw tool
	match mode:
		1:
			return text + _draw_base_shortcuts(axis_lock)
		2:
			return text + _draw_height_shortcuts()
		_:
			return text + _draw_idle_shortcuts(axis_lock)


func _draw_idle_shortcuts(axis_lock: int) -> String:
	var lines := PackedStringArray()
	lines.append("Click + Drag: Draw Base")
	lines.append("Manage > Create Floor: Stable Surface")
	lines.append("Shift: Square | Alt+Shift: Cube")
	lines.append("X / Y / Z: Lock Axis%s" % _axis_suffix(axis_lock))
	lines.append("Ctrl+Scroll: Brush Size")
	lines.append("[ / ]: Grid Size Down/Up")
	lines.append("Ctrl+D: Duplicate | Del: Remove")
	return "\n".join(lines)


func _draw_base_shortcuts(axis_lock: int) -> String:
	var lines := PackedStringArray()
	lines.append("-- Dragging Base%s --" % _axis_suffix(axis_lock))
	lines.append("Shift: Square | Alt+Shift: Cube")
	lines.append("Type number: Set exact size")
	lines.append("Click: Set Height Stage")
	lines.append("Right-click: Cancel")
	return "\n".join(lines)


func _draw_height_shortcuts() -> String:
	var lines := PackedStringArray()
	lines.append("-- Adjusting Height --")
	lines.append("Move Mouse: Change Height")
	lines.append("Type number + Enter: Exact height")
	lines.append("Click: Confirm Placement")
	lines.append("Right-click: Cancel")
	return "\n".join(lines)


func _select_mode_shortcuts() -> String:
	var lines := PackedStringArray()
	lines.append("Click: Select | Shift: Add")
	lines.append("Ctrl+Click: Toggle Selection")
	lines.append("Escape: Clear Selection")
	lines.append("Del: Remove | Ctrl+D: Duplicate")
	lines.append("Arrows: Nudge | PgUp/Dn: Y-Nudge")
	lines.append("Ctrl+H: Hollow | Shift+X: Clip")
	lines.append("Ctrl+Shift+F/C: Floor/Ceiling")
	return "\n".join(lines)


func _extrude_idle_shortcuts(dir_label: String) -> String:
	var lines := PackedStringArray()
	lines.append("-- Extrude %s --" % dir_label)
	lines.append("Click face + Drag: Extrude %s" % dir_label)
	lines.append("U: Extrude Up | J: Extrude Down")
	lines.append("Right-click: Cancel")
	return "\n".join(lines)


func _extrude_active_shortcuts(dir_label: String) -> String:
	var lines := PackedStringArray()
	lines.append("-- Extruding %s --" % dir_label)
	lines.append("Move Mouse: Set Height")
	lines.append("Type number + Enter: Exact height")
	lines.append("Release: Confirm")
	lines.append("Right-click: Cancel")
	return "\n".join(lines)


func _floor_paint_shortcuts() -> String:
	var lines := PackedStringArray()
	lines.append("-- Floor Paint --")
	lines.append("Click + Drag: Paint")
	lines.append("B: Brush | E: Erase | R: Rect")
	lines.append("L: Line | K: Bucket")
	return "\n".join(lines)


func _surface_paint_shortcuts() -> String:
	var lines := PackedStringArray()
	lines.append("-- Surface Paint --")
	lines.append("Click + Drag: Paint Surface")
	lines.append("Radius/Strength in SurfacePaint tab")
	return "\n".join(lines)


func _vertex_edit_shortcuts() -> String:
	var lines := PackedStringArray()
	lines.append("-- Vertex Edit --")
	lines.append("Click: Select vertex")
	lines.append("Shift+Click: Multi-select")
	lines.append("Drag: Move selected")
	lines.append("E: Toggle edge mode")
	lines.append("Ctrl+W: Merge verts | Ctrl+E: Split edge")
	lines.append("X / Y / Z: Lock axis")
	lines.append("Esc: Deselect / V: Exit")
	return "\n".join(lines)


func _axis_suffix(axis_lock: int) -> String:
	match axis_lock:
		1:
			return " [X Locked]"
		2:
			return " [Y Locked]"
		3:
			return " [Z Locked]"
		_:
			return ""
