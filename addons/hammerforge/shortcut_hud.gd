@tool
extends Control

@onready var label: Label = $Panel/Margin/Label

var _last_context := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_layout()
	update_context({})


func _apply_layout() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -270.0
	offset_top = 8.0
	offset_right = -8.0
	offset_bottom = 170.0


func update_context(ctx: Dictionary) -> void:
	if ctx == _last_context:
		return
	_last_context = ctx.duplicate()
	if not label:
		return
	label.text = _build_shortcuts_text(ctx)


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
	lines.append("Shift: Square | Alt+Shift: Cube")
	lines.append("X / Y / Z: Lock Axis%s" % _axis_suffix(axis_lock))
	lines.append("Ctrl+Scroll: Brush Size")
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
