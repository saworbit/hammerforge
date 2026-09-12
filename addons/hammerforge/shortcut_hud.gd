@tool
extends Control

@onready var label: Label = $Panel/Margin/Label

## The HUD is parented into the 3D viewport toolbar, which is a BoxContainer:
## it positions its children itself, sizes them to their minimum, and ignores
## the anchors a free-floating overlay would set. A plain Control reports a
## minimum of zero, so the panel was handed a zero-width slot, drew its seven
## lines out of it, and had six of them painted over by the viewport while the
## seventh landed on top of the context toolbar.
##
## One row is the honest budget in a toolbar, so the HUD spends it on the line
## that actually changes — the active hint, or the primary action for the
## current tool — and keeps the full list one hover away.
const HUD_WIDTH := 260.0
## Every label in the row is drawn at this size, so the row is the same height
## whichever of them is showing. CONTAINER_SPATIAL_EDITOR_MENU is a plain
## HBoxContainer and the 3D viewport gets whatever height is left under it, so a
## HUD that renegotiated its height with each mode or hint slid the viewport
## under the cursor mid-edit. Godot's own controls in that bar are a fixed 29px
## and never move; this one holds still the same way.
const ROW_FONT_SIZE := 12

const HFKeymapType = preload("hf_keymap.gd")

var _last_context := {}
## The keymap every chord on this HUD is read from. A default one stands in
## until the plugin hands over the real one, so the lines are never literals.
var _keymap = null
var _user_prefs = null  # HFUserPrefs — untyped to avoid preload
var _row: HBoxContainer
var _hint_label: Label
var _hint_tween: Tween
var _current_hint_key := ""
# Grid size indicator
var _grid_label: Label
var _grid_flash_tween: Tween
var _last_grid_snap := -1.0

const MODE_HINTS := {
	# One line. The row is one line high, and the toolbar takes its height from
	# this HUD, so a second line here moves the whole 3D viewport down. The rest
	# of the advice is on the tooltip with the full shortcut list.
	"draw_idle": "Click to place corner → drag to set size → release for height",
	"select": "Click to select; drag empty space for a box; drag widgets to edit",
	"extrude_up_idle": "Click a face to start extruding upward",
	"extrude_down_idle": "Click a face to start extruding downward",
	"paint_floor": "Drag to paint; Alt erases, Shift locks an axis, Ctrl picks material",
	"paint_surface": "Click brush faces to apply material",
	"vertex_edit": "Click vertex to select, drag to move, {axis_x}/{axis_y}/{axis_z} to lock axis",
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_layout()
	_setup_row()
	_setup_hint_label()
	_setup_grid_label()
	update_context({})


func _apply_layout() -> void:
	custom_minimum_size = Vector2(HUD_WIDTH, 0.0)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var panel := get_node_or_null("Panel") as Control
	if panel and not panel.minimum_size_changed.is_connected(update_minimum_size):
		panel.minimum_size_changed.connect(update_minimum_size)


## Claim the space the panel actually draws into. Without this the toolbar
## reserves nothing and the panel overlaps whatever is laid out next to it.
func _get_minimum_size() -> Vector2:
	var panel := get_node_or_null("Panel") as Control
	if panel == null:
		return Vector2(HUD_WIDTH, 0.0)
	return Vector2(HUD_WIDTH, panel.get_combined_minimum_size().y)


## A MarginContainer gives every child the same rect, so the three labels have
## been drawing on top of one another, kept apart only by right-alignment and a
## leading newline. One row, laid out as a row.
func _setup_row() -> void:
	var margin := get_node_or_null("Panel/Margin")
	if margin == null or label == null:
		return
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override("separation", 10)
	margin.add_child(_row)
	margin.remove_child(label)
	_row.add_child(label)
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pin_row_height()


## One line, measured from the theme rather than from whatever text happens to
## be in the row. Without a floor the row still collapses when every label in it
## is hidden, and the toolbar shrinks with it.
func _pin_row_height() -> void:
	if _row == null or label == null:
		return
	var font := label.get_theme_font("font")
	var line := float(ROW_FONT_SIZE)
	if font:
		line = font.get_height(ROW_FONT_SIZE)
	_row.custom_minimum_size.y = line


func set_user_prefs(prefs) -> void:
	_user_prefs = prefs


func _setup_hint_label() -> void:
	if _row == null:
		return
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	_hint_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.7))
	_hint_label.visible = false
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_row.add_child(_hint_label)
	_row.move_child(_hint_label, 0)


func _setup_grid_label() -> void:
	if _row == null:
		return
	_grid_label = Label.new()
	_grid_label.name = "GridLabel"
	_grid_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	_grid_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.8))
	_grid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_grid_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_grid_label)


func update_grid_snap(value: float) -> void:
	if not _grid_label:
		return
	# Format: display exact value, strip trailing zeros
	var text: String
	if is_equal_approx(value, roundf(value)):
		text = "Grid: %d" % int(value)
	else:
		# Enough precision for small snaps like 0.125, with the padding zeros
		# taken back off. GDScript has no %g — it rendered the literal "%g" and
		# raised an engine error on every fractional snap.
		var s := String.num(value, 4).rstrip("0").rstrip(".")
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


## Hand the HUD the keymap its chords come from.
func set_keymap(km) -> void:
	_keymap = km
	var ctx: Dictionary = _last_context.duplicate()
	_last_context = {}
	update_context(ctx)


## Render `{action}` tokens in a line against the current keymap.
func _chords(text: String) -> String:
	if _keymap == null:
		_keymap = HFKeymapType.load_or_default("")
	return _keymap.format_chords(text)


func update_context(ctx: Dictionary) -> void:
	if ctx == _last_context:
		return
	_last_context = ctx.duplicate()
	if not label:
		return
	var full := _build_shortcuts_text(ctx)
	label.text = primary_line(full)
	_set_tooltip(full)
	_check_mode_hint(ctx)


## The first line of each mode list names the action you are about to take; the
## rest are modifiers on it. That first line is what the row shows.
static func primary_line(text: String) -> String:
	for line in text.split("\n", false):
		var trimmed := str(line).strip_edges()
		if trimmed != "":
			return trimmed
	return ""


## Everything the row cannot fit stays reachable without leaving the viewport.
func _set_tooltip(full: String) -> void:
	tooltip_text = full
	var panel := get_node_or_null("Panel") as Control
	if panel:
		panel.tooltip_text = full
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
	if label:
		label.tooltip_text = full


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
	if not str(ctx.get("external_tool_name", "")).is_empty():
		return ""
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
	# The hint replaces the shortcut line rather than stacking under it: the row
	# is one line high, and while a hint is up it is the more useful of the two.
	# A newline here would quietly make the row two lines high and grow the whole
	# toolbar by a line. Anything past the first sentence belongs on the tooltip.
	_hint_label.text = " ".join(text.split("\n", false))
	_hint_label.modulate = Color(1, 1, 1, 1)
	_hint_label.visible = true
	if label:
		label.visible = false
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(4.0)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, 1.0)
	_hint_tween.tween_callback(_hide_hint)


func _hide_hint() -> void:
	if _hint_label:
		_hint_label.visible = false
	if label:
		label.visible = true
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
	var external_name := str(ctx.get("external_tool_name", ""))
	var external_shortcuts: PackedStringArray = ctx.get("external_shortcuts", PackedStringArray())
	if not external_name.is_empty():
		var lines := PackedStringArray(["-- %s --" % external_name])
		lines.append_array(external_shortcuts)
		if external_shortcuts.is_empty():
			lines.append("Esc: Exit tool")
		return text + "\n".join(lines)

	if is_paint:
		if paint_target == 1:
			return text + _surface_paint_shortcuts()
		return text + _floor_paint_shortcuts()

	# mode 5 = VERTEX_EDIT
	if mode == 5:
		return text + _vertex_edit_shortcuts()

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
	lines.append("Manage > Create Floor: Stable Surface")
	lines.append("Shift: Square | Alt+Shift: Cube")
	lines.append(_chords("{axis_x} / {axis_y} / {axis_z}: Lock Axis%s" % _axis_suffix(axis_lock)))
	lines.append("Ctrl+Scroll: Brush Size")
	lines.append("[ / ]: Grid Size Down/Up")
	lines.append(_chords("{duplicate}: Duplicate | {delete}: Remove"))
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
	lines.append("Drag Empty Space: Box Select")
	lines.append("Drag Brush Widgets: Resize/Move")
	lines.append("Escape: Clear Selection")
	lines.append(_chords("{delete}: Remove | {duplicate}: Duplicate"))
	lines.append("Arrows: Nudge | PgUp/Dn: Y-Nudge")
	lines.append(_chords("{hollow}: Hollow | {clip}: Clip"))
	lines.append(_chords("{move_to_floor} / {move_to_ceiling}: Floor / Ceiling"))
	return "\n".join(lines)


func _extrude_idle_shortcuts(dir_label: String) -> String:
	var lines := PackedStringArray()
	lines.append("-- Extrude %s --" % dir_label)
	lines.append("Click face + Drag: Extrude %s" % dir_label)
	lines.append(_chords("{tool_extrude_up}: Extrude Up | {tool_extrude_down}: Extrude Down"))
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
	lines.append("Click + Drag: Paint | Alt: Erase")
	lines.append("Shift+Drag: Axis Lock | Ctrl+Click: Pick Material")
	lines.append(_chords("{paint_bucket}: Brush | {paint_erase}: Erase | {paint_ramp}: Rect"))
	lines.append(_chords("{paint_line}: Line | {paint_fill}: Bucket | Esc: Cancel Stroke"))
	lines.append(
		_chords(
			(
				"{paint_mirror_x}/{paint_mirror_z}: Mirror | {paint_raise}: Raise Last"
				+ " | {paint_room}: Room Stamp"
			)
		)
	)
	lines.append(_chords("{paint_confirm_connector}: Confirm Connector Ghost"))
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
	lines.append(_chords("{vertex_edge_mode}: Toggle edge mode"))
	lines.append(_chords("{vertex_merge}: Merge verts | {vertex_split_edge}: Split edge"))
	lines.append(_chords("{axis_x} / {axis_y} / {axis_z}: Lock axis"))
	lines.append(_chords("Esc: Deselect / {vertex_edit}: Exit"))
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
