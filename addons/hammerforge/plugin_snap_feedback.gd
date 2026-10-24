@tool
class_name HFPluginSnapFeedback
extends RefCounted
## What a snap found, shown where it found it (#1691).
##
## A snapped point used to look the same whatever it was on, so near a corner
## the mapper could not tell the grid point from the vertex a few centimetres
## away, and when two candidates were close the nearest one won with no way to
## ask for the other. Each kind now has its own marker shape, drawn the same
## size at every zoom over the 3D view, with a word beside it unless the
## `snap_labels` preference turns the words off. Tab steps to the next kind in
## reach, and a one-pick limit asks for a single kind for the next pick only.
##
## Shapes, not colours, carry the meaning, so they read the same in High
## Contrast. Every pointer tool that snaps through `HFSnapSystem` shows them:
## Draw, Polygon, Path, Measure, Clip, and vertex drags landing on a vertex.

const HFSnapSystemType = preload("hf_snap_system.gd")
const HFOverlayColors = preload("hf_overlay_colors.gd")

## Half a marker's width on screen, in pixels.
const MARKER_HALF := 7.0
## How a marker's lines are drawn.
const LINE_WIDTH := 2.0
## The shape each kind is marked with. A test pins this.
const SHAPES := {
	HFSnapSystemType.KIND_VERTEX: "square",
	HFSnapSystemType.KIND_MIDPOINT: "triangle",
	HFSnapSystemType.KIND_CENTRE: "circle",
	HFSnapSystemType.KIND_PERPENDICULAR: "right angle",
	HFSnapSystemType.KIND_GRID: "cross",
	HFSnapSystemType.KIND_LINE: "diamond",
}
## The one-pick limit each command asks for.
const LIMIT_COMMANDS := {
	"snap_next_vertex": HFSnapSystemType.KIND_VERTEX,
	"snap_next_midpoint": HFSnapSystemType.KIND_MIDPOINT,
	"snap_next_centre": HFSnapSystemType.KIND_CENTRE,
	"snap_next_perpendicular": HFSnapSystemType.KIND_PERPENDICULAR,
	"snap_next_grid": HFSnapSystemType.KIND_GRID,
}


## The lines of `shape`, as point pairs round the origin, `half` from it in
## screen pixels, y down.
static func shape_lines(shape: String, half: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	match shape:
		"square":
			_ring(
				out,
				[
					Vector2(-half, -half),
					Vector2(half, -half),
					Vector2(half, half),
					Vector2(-half, half)
				]
			)
		"triangle":
			_ring(out, [Vector2(0, -half), Vector2(half, half), Vector2(-half, half)])
		"circle":
			var points: Array = []
			for i in 16:
				points.append(Vector2.from_angle(TAU * float(i) / 16.0) * half)
			_ring(out, points)
		"right angle":
			var corner := Vector2(-half, half)
			out.append_array([corner, Vector2(-half, -half), corner, Vector2(half, half)])
			var tick := half * 0.5
			(
				out
				. append_array(
					[
						corner + Vector2(0, -tick),
						corner + Vector2(tick, -tick),
						corner + Vector2(tick, -tick),
						corner + Vector2(tick, 0),
					]
				)
			)
		"diamond":
			_ring(out, [Vector2(0, -half), Vector2(half, 0), Vector2(0, half), Vector2(-half, 0)])
		_:
			out.append_array(
				[Vector2(-half, 0), Vector2(half, 0), Vector2(0, -half), Vector2(0, half)]
			)
	return out


static func _ring(out: PackedVector2Array, points: Array) -> void:
	for i in points.size():
		out.append(points[i])
		out.append(points[(i + 1) % points.size()])


## The lines of the marker for `kind`.
static func marker_lines(kind: String, half: float = MARKER_HALF) -> PackedVector2Array:
	return shape_lines(str(SHAPES.get(kind, "cross")), half)


## What the label beside a marker says for `kind`, with the one-pick limit named
## when one is waiting.
static func label_text(kind: String, limit: String = "") -> String:
	var text := str(HFSnapSystemType.KIND_LABELS.get(kind, ""))
	if limit != "" and text != "":
		text += " only"
	return text


static func _snap_of(plugin: Object) -> Object:
	if plugin == null:
		return null
	var root = plugin.get("active_root")
	if root == null or not is_instance_valid(root):
		return null
	return root.get("snap_system")


## Around every pointer event over the 3D view: what snaps inside it is what the
## viewport marks. A left release spends a one-pick limit and a Tab step, after
## the tool has taken its pick.
static func begin(plugin: Object, event: InputEvent) -> void:
	if not (event is InputEventMouse):
		return
	var snap = _snap_of(plugin)
	if snap:
		snap.begin_pointer_event()


static func end(plugin: Object, event: InputEvent) -> void:
	if not (event is InputEventMouse):
		return
	var snap = _snap_of(plugin)
	if snap == null:
		return
	var redraw: bool = snap.end_pointer_event(event is InputEventMouseMotion)
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		snap.pick_taken()
	if redraw and plugin.has_method("update_overlays"):
		plugin.update_overlays()


## Tab: step the shown pick to the next kind in reach, then ask the pointer tool
## again where the cursor is, so the preview and the marker follow. False when
## nothing shows or only one kind is in reach, so Tab keeps its other uses.
static func step(plugin: Object, event: InputEventKey) -> bool:
	if event == null or event.keycode != KEY_TAB or not event.pressed or event.echo:
		return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed:
		return false
	var snap = _snap_of(plugin)
	if snap == null or not snap.step_choice():
		return false
	_ask_again(plugin)
	return true


## Limit the next pick to the kind `command` names, and say so.
static func limit(plugin: Object, command: String) -> bool:
	var snap = _snap_of(plugin)
	var kind := str(LIMIT_COMMANDS.get(command, ""))
	if snap == null or not snap.limit_next_pick(kind):
		return false
	var dock = plugin.get("dock")
	if dock and dock.has_method("show_toast"):
		dock.show_toast(
			"Next pick: %s only" % str(HFSnapSystemType.KIND_LABELS[kind]).to_lower(), 0
		)
	_ask_again(plugin)
	return true


## A motion at the last pointer position, through the viewport's own input, so
## whatever tool is active works out its snap again.
static func _ask_again(plugin: Object) -> void:
	var camera = plugin.get("last_3d_camera")
	if (
		camera == null
		or not is_instance_valid(camera)
		or not plugin.has_method("_forward_3d_gui_input")
	):
		return
	var motion := InputEventMouseMotion.new()
	motion.position = plugin.get("last_3d_mouse_pos")
	# A drag in progress holds its button, or the tool reads the motion as hover.
	motion.button_mask = Input.get_mouse_button_mask()
	motion.shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	motion.alt_pressed = Input.is_key_pressed(KEY_ALT)
	plugin._forward_3d_gui_input(camera, motion)
	if plugin.has_method("update_overlays"):
		plugin.update_overlays()


## Draw the marker and its label over the 3D view.
static func draw(plugin: Object, overlay: Control) -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var snap = _snap_of(plugin)
	var camera = plugin.get("last_3d_camera") if plugin else null
	if snap == null or camera == null or not is_instance_valid(camera):
		return
	var pick: Dictionary = snap.shown_pick
	if pick.is_empty() or not (pick.get("point") is Vector3):
		return
	var point: Vector3 = pick["point"]
	if camera.is_position_behind(point):
		return
	var at: Vector2 = camera.unproject_position(point)
	var color := HFOverlayColors.get_color(HFOverlayColors.HOVER)
	color.a = 1.0
	var lines := marker_lines(str(pick.get("kind", "")))
	var placed := PackedVector2Array()
	for p in lines:
		placed.append(at + p)
	overlay.draw_multiline(placed, Color(0, 0, 0, 0.7), LINE_WIDTH + 2.0)
	overlay.draw_multiline(placed, color, LINE_WIDTH)
	var prefs = plugin.get("_user_prefs")
	if prefs != null and not bool(prefs.get_pref("snap_labels", true)):
		return
	var text := label_text(str(pick.get("kind", "")), snap.next_pick_limit())
	if text == "":
		return
	var font: Font = overlay.get_theme_default_font()
	var font_size: int = overlay.get_theme_default_font_size()
	if font == null:
		return
	var baseline := at + Vector2(MARKER_HALF + 4.0, -MARKER_HALF - 2.0)
	overlay.draw_string_outline(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8)
	)
	overlay.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
