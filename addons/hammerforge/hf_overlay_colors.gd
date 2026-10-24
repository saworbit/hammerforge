@tool
extends RefCounted
## The colours the editor draws its selection, hover and brush overlays in, which
## a mapper picks under Test > Settings > Colours (#1446). Each one used to be a
## literal in the file that drew it, so hover yellow and selection amber blurred
## on a bright texture, and a mapper who could not tell red from green had no way
## to tell a solid from a cut.
##
## Everything that draws one of these reads it through `get_color()`, so a change
## reaches each overlay the next time it draws, and
## `HFPluginOverlays.refresh_overlay_colors()` redraws the ones already up.
##
## One palette for the editor, not one per level: the plugin sets it from the
## user's preferences (`HFUserPrefs`), where each colour is kept as a hex string.
## Only the editor's looks read it, and each brush look keeps its
## `DraftBrush.EDITOR_LOOK_META` mark, so a bake leaves it behind and a mapper's
## colours never reach a baked level.

const SELECTED_BRUSH := "color_selected_brush"
const SELECTED_FACE := "color_selected_face"
const HOVER := "color_hover"
const VERTEX_HANDLE := "color_vertex_handle"
const SELECTED_VERTEX := "color_selected_vertex"
const ADDITIVE_BRUSH := "color_additive_brush"
const SUBTRACTIVE_BRUSH := "color_subtractive_brush"
const WIREFRAME := "color_wireframe"
const EXTRUDE_UP := "color_extrude_up"
const EXTRUDE_DOWN := "color_extrude_down"
const DRAW_PREVIEW := "color_draw_preview"
const PENDING_CUT := "color_pending_cut"
const FUNC_DETAIL := "color_func_detail"
const TRIGGER := "color_trigger"
const FUNC_WALL := "color_func_wall"
const FUNC_CLIP := "color_func_clip"
const BRUSH_ENTITY := "color_brush_entity"
const AGENT_CHANGE := "color_agent_change"

## The look before these were a preference, in the order Settings lists them.
const DEFAULTS := {
	SELECTED_BRUSH: Color(1.0, 0.82, 0.2, 0.75),
	SELECTED_FACE: Color(1.0, 0.55, 0.0, 0.3),
	HOVER: Color(1.0, 1.0, 0.0, 0.5),
	VERTEX_HANDLE: Color(1.0, 1.0, 1.0, 1.0),
	SELECTED_VERTEX: Color.ORANGE,
	ADDITIVE_BRUSH: Color(0.2, 0.8, 0.2, 0.35),
	SUBTRACTIVE_BRUSH: Color(1.0, 0.2, 0.2, 0.35),
	WIREFRAME: Color(1.0, 0.8, 0.0, 0.6),
	EXTRUDE_UP: Color(0.2, 0.8, 0.3, 0.35),
	EXTRUDE_DOWN: Color(0.8, 0.2, 0.2, 0.35),
	DRAW_PREVIEW: Color(0.3, 0.6, 1.0, 0.35),
	PENDING_CUT: Color(1.0, 0.3, 0.1, 0.5),
	FUNC_DETAIL: Color(0.3, 0.5, 1.0, 0.35),
	TRIGGER: Color(0.4, 0.55, 1.0, 0.3),
	FUNC_WALL: Color(0.25, 0.45, 0.9, 0.25),
	FUNC_CLIP: Color(0.75, 0.35, 1.0, 0.25),
	BRUSH_ENTITY: Color(0.35, 0.5, 0.85, 0.2),
	AGENT_CHANGE: Color(0.2, 0.95, 0.85, 1.0),
}

## Settings' High Contrast button. Taken from the Okabe-Ito colours, which stay
## apart for the three common kinds of colour blindness: the selection is sky
## blue and hover yellow, so the two no longer blur, and a solid is a dark bluish
## green against a bright orange cut, so the two are told apart by brightness as
## well as by hue. A cut waiting for Apply is reddish purple, apart from the
## committed cut's orange, and a solid being drawn is the darker blue (#1680).
## The brush entities keep off the blues, which drew a selected detail or trigger
## blue on blue: detail is yellow, a trigger vermillion, func_wall a dark tint, a
## clip brush a pale one and any other brush entity grey (#1760).
const HIGH_CONTRAST := {
	SELECTED_BRUSH: Color(0.34, 0.71, 0.91, 0.9),
	SELECTED_FACE: Color(0.34, 0.71, 0.91, 0.4),
	HOVER: Color(0.94, 0.89, 0.26, 0.8),
	VERTEX_HANDLE: Color(1.0, 1.0, 1.0, 1.0),
	SELECTED_VERTEX: Color(0.34, 0.71, 0.91, 1.0),
	ADDITIVE_BRUSH: Color(0.0, 0.45, 0.33, 0.35),
	SUBTRACTIVE_BRUSH: Color(0.9, 0.62, 0.0, 0.35),
	WIREFRAME: Color(0.8, 0.47, 0.65, 0.8),
	EXTRUDE_UP: Color(0.0, 0.45, 0.33, 0.45),
	EXTRUDE_DOWN: Color(0.9, 0.62, 0.0, 0.45),
	DRAW_PREVIEW: Color(0.0, 0.45, 0.7, 0.35),
	PENDING_CUT: Color(0.8, 0.47, 0.65, 0.6),
	FUNC_DETAIL: Color(0.94, 0.89, 0.26, 0.35),
	TRIGGER: Color(0.84, 0.37, 0.0, 0.35),
	FUNC_WALL: Color(0.0, 0.0, 0.0, 0.4),
	FUNC_CLIP: Color(1.0, 1.0, 1.0, 0.3),
	BRUSH_ENTITY: Color(0.6, 0.6, 0.6, 0.3),
	AGENT_CHANGE: Color(0.0, 0.62, 0.45, 1.0),
}

const LABELS := {
	SELECTED_BRUSH: "Selected brush",
	SELECTED_FACE: "Selected face",
	HOVER: "Hover",
	VERTEX_HANDLE: "Vertex handle",
	SELECTED_VERTEX: "Selected vertex",
	ADDITIVE_BRUSH: "Solid brush",
	SUBTRACTIVE_BRUSH: "Cut brush",
	WIREFRAME: "Cordon wireframe",
	EXTRUDE_UP: "Extrude up",
	EXTRUDE_DOWN: "Extrude down",
	DRAW_PREVIEW: "Draw preview",
	PENDING_CUT: "Pending cut",
	FUNC_DETAIL: "func_detail",
	TRIGGER: "trigger_*",
	FUNC_WALL: "func_wall",
	FUNC_CLIP: "func_clip",
	BRUSH_ENTITY: "Other brush entity",
	AGENT_CHANGE: "Agent change",
}

const TOOLTIPS := {
	SELECTED_BRUSH: "The outline of a selected brush or entity\nUnselected ones draw it faintly",
	SELECTED_FACE: "The tint on faces picked in Face Select, outlined at full strength",
	HOVER: "The outline of the brush under the cursor, and a hovered vertex or edge",
	VERTEX_HANDLE: "Vertex crosses in Vertex mode\nEdges draw it at half strength",
	SELECTED_VERTEX: "Selected vertices and edges",
	ADDITIVE_BRUSH: "The see-through look of a solid brush with no material",
	SUBTRACTIVE_BRUSH: "The see-through look of a cut, and its outline",
	WIREFRAME: "The cordon box\nA cordon switched off draws it fainter",
	EXTRUDE_UP: "The face under the cursor and the new brush while extruding outwards",
	EXTRUDE_DOWN: "The face under the cursor and the new brush while extruding inwards",
	DRAW_PREVIEW: "The solid being drawn, before the mouse lets go",
	PENDING_CUT: "A cut waiting for Apply, and the cut being drawn",
	FUNC_DETAIL: "The see-through look of a func_detail brush with no material",
	TRIGGER: "The see-through look of a trigger_* brush with no material",
	FUNC_WALL: "The see-through look of a func_wall brush with no material",
	FUNC_CLIP: "The see-through look of a func_clip brush, whatever its faces carry",
	BRUSH_ENTITY: "The see-through look of any other brush entity with no material",
	AGENT_CHANGE: "The outline round what an agent just changed over the bridge, for a moment",
}

## The colours drawn on or round every brush. A change to one of these redraws
## every brush in the level, so the others leave the brushes alone.
const BRUSH_KEYS := [
	SELECTED_BRUSH,
	ADDITIVE_BRUSH,
	SUBTRACTIVE_BRUSH,
	PENDING_CUT,
	FUNC_DETAIL,
	TRIGGER,
	FUNC_WALL,
	FUNC_CLIP,
	BRUSH_ENTITY,
]

## How strongly a cut's outline is drawn, against the see-through fill.
const SUBTRACT_OUTLINE_ALPHA := 0.7
## A cordon switched off is drawn at this share of the wireframe's strength.
const CORDON_OFF_SHARE := 0.25

## Empty until the plugin sets a palette, which is today's look.
static var _colors: Dictionary = {}
## Counts the palette changes, so a level drawn under an older palette can be
## found and redrawn when it is next in front.
static var _revision := 0
## Counts the changes to `BRUSH_KEYS` alone.
static var _brush_revision := 0


## The colour overlay `key` is drawn in now.
static func get_color(key: String) -> Color:
	if _colors.has(key):
		return _colors[key]
	return DEFAULTS.get(key, Color.WHITE)


## Take every colour from `prefs`, an `HFUserPrefs`, or today's look with none.
## True when any colour changed, which is when overlays already up need a redraw.
static func apply_prefs(prefs: Object) -> bool:
	var next := {}
	for key in DEFAULTS:
		next[key] = from_pref(prefs.get_pref(key) if prefs else null, key)
	var now := {}
	for key in DEFAULTS:
		now[key] = get_color(key)
	if next == now:
		return false
	for key in BRUSH_KEYS:
		if next[key] != now[key]:
			_brush_revision += 1
			break
	_colors = next
	_revision += 1
	return true


## Back to today's look. Tests use this to leave the palette as they found it.
static func reset() -> void:
	if not _colors.is_empty():
		_colors = {}
		_revision += 1
		_brush_revision += 1


static func revision() -> int:
	return _revision


static func brush_revision() -> int:
	return _brush_revision


## How a colour is kept in the preferences file: a hex string with its alpha.
static func to_pref(color: Color) -> String:
	return "#" + color.to_html(true)


## The colour a preference holds, or `key`'s default for anything that is not one.
## A default comes back exactly, not through the eight bits a channel the hex
## string keeps, so the default look matches the one these replaced.
static func from_pref(value: Variant, key: String) -> Color:
	var fallback: Color = DEFAULTS.get(key, Color.WHITE)
	if value is Color:
		return value
	if not (value is String) or not Color.html_is_valid(value):
		return fallback
	var color := Color.html(value)
	if to_pref(color) == to_pref(fallback):
		return fallback
	return color


## `color` with its alpha replaced, for a look drawn at a strength of its own.
static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
