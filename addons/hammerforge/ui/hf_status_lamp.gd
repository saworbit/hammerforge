@tool
class_name HFStatusLamp
extends Control
## One red / amber / green lamp.
##
## The glyph inside the lamp is drawn, not set in a font, for two reasons.
## Colour alone fails for the ~8% of men with a red/green deficiency, so the
## shape has to carry the same message as the hue; and a font glyph that the
## editor's font happens not to ship would render as a blank box in exactly the
## place the user is looking for an answer.

const HFStatusBoardType = preload("../hf_status_board.gd")

## Diameter the lamp draws at unless a caller overrides custom_minimum_size.
const DEFAULT_SIZE := 16.0

var severity: int = HFStatusBoardType.Severity.UNKNOWN:
	set(value):
		if severity == value:
			return
		severity = value
		queue_redraw()

## Base control the editor theme is read from. Null falls back to dark-theme
## colours, which is what a test harness or a detached preview gets.
var theme_source: Control = null:
	set(value):
		theme_source = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(DEFAULT_SIZE, DEFAULT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The lamp colour for a severity, in the current editor theme.
static func color_for(severity_value: int, base: Control = null) -> Color:
	match severity_value:
		HFStatusBoardType.Severity.OK:
			return HFThemeUtils.success_color(base)
		HFStatusBoardType.Severity.WARN:
			return HFThemeUtils.warning_color(base)
		HFStatusBoardType.Severity.PROBLEM:
			return HFThemeUtils.error_color(base)
		_:
			return HFThemeUtils.muted_text(base)


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5 - 1.0
	if radius <= 1.0:
		return
	var centre := size * 0.5
	var fill := color_for(severity, theme_source)

	# An unlit lamp reads as "no reading taken", not as a pass. Draw it hollow.
	if severity == HFStatusBoardType.Severity.UNKNOWN:
		draw_circle(centre, radius, Color(fill, 0.14))
		draw_arc(centre, radius, 0.0, TAU, 32, Color(fill, 0.7), 1.5, true)
	else:
		draw_circle(centre, radius, Color(fill, 0.22))
		draw_circle(centre, radius * 0.72, fill)
		draw_arc(centre, radius, 0.0, TAU, 32, Color(fill, 0.85), 1.5, true)

	_draw_glyph(centre, radius, _glyph_color(fill))


## Ink that stays legible on top of the lit lamp.
func _glyph_color(fill: Color) -> Color:
	if severity == HFStatusBoardType.Severity.UNKNOWN:
		return Color(fill, 0.9)
	if fill.get_luminance() > 0.55:
		return Color(0.06, 0.07, 0.09, 0.95)
	return Color(1.0, 1.0, 1.0, 0.95)


func _draw_glyph(centre: Vector2, radius: float, ink: Color) -> void:
	var unit := radius * 0.34
	var width := maxf(1.6, radius * 0.22)
	match severity:
		HFStatusBoardType.Severity.OK:
			# Tick: short down-stroke into a long up-stroke.
			var elbow := centre + Vector2(-unit * 0.15, unit * 0.75)
			draw_line(centre + Vector2(-unit, 0.0), elbow, ink, width, true)
			draw_line(elbow, centre + Vector2(unit * 1.05, -unit * 0.85), ink, width, true)
		HFStatusBoardType.Severity.WARN:
			# Bang: stem above a detached dot.
			draw_line(
				centre + Vector2(0.0, -unit * 1.0),
				centre + Vector2(0.0, unit * 0.28),
				ink,
				width,
				true
			)
			draw_circle(centre + Vector2(0.0, unit * 0.95), width * 0.55, ink)
		HFStatusBoardType.Severity.PROBLEM:
			draw_line(
				centre + Vector2(-unit * 0.85, -unit * 0.85),
				centre + Vector2(unit * 0.85, unit * 0.85),
				ink,
				width,
				true
			)
			draw_line(
				centre + Vector2(unit * 0.85, -unit * 0.85),
				centre + Vector2(-unit * 0.85, unit * 0.85),
				ink,
				width,
				true
			)
		_:
			draw_line(
				centre + Vector2(-unit * 0.8, 0.0),
				centre + Vector2(unit * 0.8, 0.0),
				ink,
				width,
				true
			)
