@tool
extends Control
## Radial (pie) menu triggered by backtick (`) key in the 3D viewport.
## Shows 8 tool/shape actions in a circle around the cursor. Move mouse
## to highlight a sector, LMB to select; Escape/backtick/RMB to cancel.

const HFThemeUtils = preload("hf_theme_utils.gd")

signal action_selected(action: String)

const SEGMENTS: Array[Dictionary] = [
	{"action": "shape_box", "label": "Box"},
	{"action": "shape_cylinder", "label": "Cylinder"},
	{"action": "tool_select", "label": "Select"},
	{"action": "surface_paint", "label": "Paint"},
	{"action": "vertex_edit", "label": "Vertex"},
	{"action": "texture_picker", "label": "Tex Pick"},
	{"action": "measure", "label": "Measure"},
	{"action": "clip", "label": "Clip"},
]

const OUTER_RADIUS := 120.0
const INNER_RADIUS := 30.0
const LABEL_RADIUS := 75.0

var _center := Vector2.ZERO
var _hovered_segment := -1
var _active := false


func _init() -> void:
	name = "HFRadialMenu"
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = 100


func show_at(center_pos: Vector2) -> void:
	_hovered_segment = -1
	_active = true
	visible = true
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# center_pos comes from _forward_3d_gui_input's event.position and matches
	# the overlay canvas space used by this full-rect Control.
	_center = center_pos
	queue_redraw()


func hide_menu() -> void:
	_active = false
	_hovered_segment = -1
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	queue_redraw()


func is_active() -> bool:
	return _active


## Called manually from plugin.gd — not through Godot's GUI event chain.
## Do NOT call accept_event() here; the plugin controls propagation via
## its own AFTER_GUI_INPUT return value.
## Uses the same viewport-space mouse coordinates that HammerForge stores from
## _forward_3d_gui_input. The radial center, hover hit-test, and drawing all
## stay in that one space.
##
## Interaction model (triggered by backtick key, NOT RMB):
##   - Mouse motion: hover highlight
##   - LMB click: select hovered sector (or cancel if in dead zone)
##   - Escape / backtick / RMB: cancel without selecting
func _gui_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseMotion:
		_hovered_segment = _segment_at_position(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_hovered_segment = _segment_at_position(event.position)
			# LMB click: select hovered sector or cancel
			if _hovered_segment >= 0 and _hovered_segment < SEGMENTS.size():
				action_selected.emit(SEGMENTS[_hovered_segment]["action"])
			hide_menu()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# RMB: cancel
			hide_menu()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_QUOTELEFT:
			hide_menu()


func _segment_at_position(pos: Vector2) -> int:
	var rel: Vector2 = pos - _center
	var dist := rel.length()
	if dist < INNER_RADIUS or dist > OUTER_RADIUS:
		return -1
	var angle := fposmod(rel.angle() + PI / 2.0, TAU)
	var seg_count := SEGMENTS.size()
	var seg_angle := TAU / seg_count
	return int(angle / seg_angle) % seg_count


func _draw() -> void:
	if not _active:
		return
	var seg_count := SEGMENTS.size()
	var seg_angle := TAU / seg_count
	var bg_color: Color = HFThemeUtils.panel_bg(self)
	var border_color: Color = HFThemeUtils.panel_border(self)
	var text_color: Color = HFThemeUtils.primary_text(self)
	var accent_color: Color = HFThemeUtils.accent(self)
	var highlight := Color(accent_color, 0.35)

	# Dim overlay behind the radial
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.2))

	# Draw sectors
	for i in seg_count:
		var start_angle := i * seg_angle - PI / 2.0  # Start from top
		var end_angle := start_angle + seg_angle
		var points := PackedVector2Array()
		# Build sector polygon: inner arc → outer arc → close
		var arc_steps := 16
		# Inner arc
		for s in range(arc_steps + 1):
			var a := start_angle + (end_angle - start_angle) * s / arc_steps
			points.append(_center + Vector2(cos(a), sin(a)) * INNER_RADIUS)
		# Outer arc (reverse)
		for s in range(arc_steps, -1, -1):
			var a := start_angle + (end_angle - start_angle) * s / arc_steps
			points.append(_center + Vector2(cos(a), sin(a)) * OUTER_RADIUS)

		var fill := highlight if i == _hovered_segment else Color(bg_color, 0.85)
		draw_polygon(points, PackedColorArray([fill]))
		# Sector border lines
		var inner_start := _center + Vector2(cos(start_angle), sin(start_angle)) * INNER_RADIUS
		var outer_start := _center + Vector2(cos(start_angle), sin(start_angle)) * OUTER_RADIUS
		draw_line(inner_start, outer_start, border_color, 1.0)

	# Outer and inner circles for clean edges
	_draw_circle_arc(_center, OUTER_RADIUS, 0, TAU, border_color, 1.5)
	_draw_circle_arc(_center, INNER_RADIUS, 0, TAU, border_color, 1.5)

	# Center dead-zone fill
	_draw_filled_circle(_center, INNER_RADIUS, Color(bg_color, 0.95))

	# Labels
	var font := get_theme_default_font()
	var font_size := 12
	for i in seg_count:
		var mid_angle := i * seg_angle + seg_angle / 2.0 - PI / 2.0
		var label_pos := _center + Vector2(cos(mid_angle), sin(mid_angle)) * LABEL_RADIUS
		var label_text: String = SEGMENTS[i]["label"]
		var text_size := font.get_string_size(
			label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size
		)
		var color := text_color if i != _hovered_segment else accent_color
		draw_string(
			font,
			label_pos - Vector2(text_size.x / 2.0, -text_size.y / 4.0),
			label_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_size,
			color
		)

	# Center dot
	_draw_filled_circle(_center, 4.0, border_color)


func _draw_circle_arc(
	center: Vector2, radius: float, start: float, end: float, color: Color, width: float
) -> void:
	var steps := 48
	var prev := center + Vector2(cos(start), sin(start)) * radius
	for i in range(1, steps + 1):
		var a := start + (end - start) * i / steps
		var next := center + Vector2(cos(a), sin(a)) * radius
		draw_line(prev, next, color, width)
		prev = next


func _draw_filled_circle(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 32
	for i in steps:
		var a := TAU * i / steps
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_polygon(points, PackedColorArray([color]))
