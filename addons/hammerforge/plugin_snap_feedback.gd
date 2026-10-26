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
	HFSnapSystemType.KIND_GUIDE: "bar",
	HFSnapSystemType.KIND_GUIDE_CROSS: "x",
	HFSnapSystemType.KIND_GUIDE_EDGE: "bowtie",
}
## How long the pointer rests on a snap point before guides run from it (#1692).
const REST_SECONDS := 0.5
## How far each way from its point a guide is drawn, in metres.
const GUIDE_REACH := 200.0
## A guide's dashes and the gaps between them, in screen pixels.
const DASH := 6.0
## Half the width of the plus on a tracked point, in screen pixels.
const TRACKED_HALF := 5.0
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
		# A guide: a bar with its ends marked (#1692).
		"bar":
			var tick := half * 0.5
			(
				out
				. append_array(
					[
						Vector2(-half, 0),
						Vector2(half, 0),
						Vector2(-half, -tick),
						Vector2(-half, tick),
						Vector2(half, -tick),
						Vector2(half, tick),
					]
				)
			)
		# Where two guides cross.
		"x":
			out.append_array(
				[
					Vector2(-half, -half),
					Vector2(half, half),
					Vector2(-half, half),
					Vector2(half, -half)
				]
			)
		# Where a guide meets an edge.
		"bowtie":
			_ring(
				out,
				[
					Vector2(-half, -half),
					Vector2(half, half),
					Vector2(half, -half),
					Vector2(-half, half)
				]
			)
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
static func label_text(kind: String, limited_to: String = "") -> String:
	var text := str(HFSnapSystemType.KIND_LABELS.get(kind, ""))
	if limited_to != "" and text != "":
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
		var motion := event as InputEventMouseMotion
		if motion and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			snap.drag_moved()
		snap.begin_pointer_event()


static func end(plugin: Object, event: InputEvent) -> void:
	if not (event is InputEventMouse):
		return
	var snap = _snap_of(plugin)
	if snap == null:
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		snap.press_taken()
	var redraw: bool = snap.end_pointer_event(event is InputEventMouseMotion)
	if button and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		snap.pick_taken()
		snap.guide_text = ""
	if event is InputEventMouseMotion:
		note_rest(plugin, snap)
	if redraw and plugin.has_method("update_overlays"):
		plugin.update_overlays()


# ---------------------------------------------------------------------------
# Tracked points and their guides (#1692)
# ---------------------------------------------------------------------------


## Whether guides are on, as the preferences say, and whether Shift takes a
## point rather than a rest.
static func tracking_on(plugin: Object) -> bool:
	var prefs = plugin.get("_user_prefs") if plugin else null
	return prefs == null or bool(prefs.get_pref("snap_tracking", true))


static func shift_takes(plugin: Object) -> bool:
	var prefs = plugin.get("_user_prefs") if plugin else null
	return prefs != null and bool(prefs.get_pref("snap_tracking_shift", false))


## The pointer moved: when it now sits on a snap point a guide can run from,
## wait for it to rest there. Moving on, or onto something else, starts over.
static func note_rest(plugin: Object, snap: Object) -> void:
	snap.tracking = tracking_on(plugin)
	var pick: Dictionary = snap.shown_pick
	var kind := str(pick.get("kind", ""))
	if not snap.tracking or shift_takes(plugin) or not (kind in HFSnapSystemType.TRACKABLE):
		snap.rest_point = null
		return
	var point: Vector3 = pick["point"]
	if snap.rest_point is Vector3 and (snap.rest_point as Vector3).is_equal_approx(point):
		return
	snap.rest_point = point
	snap.rest_done = false
	snap.rest_serial += 1
	if not (plugin is Node) or not (plugin as Node).is_inside_tree():
		return
	var timer := (plugin as Node).get_tree().create_timer(REST_SECONDS)
	timer.timeout.connect(_rested.bind(plugin, int(snap.rest_serial)))


## Untyped, since the plugin may be gone by the time the wait ends.
static func _rested(plugin, serial: int) -> void:
	if not is_instance_valid(plugin):
		return
	var snap = _snap_of(plugin)
	if snap == null or snap.rest_done or int(snap.rest_serial) != serial:
		return
	rest_now(plugin, snap)


## The rest is over: the point the pointer is on is tracked, or let go when it was.
static func rest_now(plugin: Object, snap: Object) -> bool:
	var pick: Dictionary = snap.shown_pick
	if not (snap.rest_point is Vector3) or not (pick.get("point") is Vector3):
		return false
	if not (pick["point"] as Vector3).is_equal_approx(snap.rest_point):
		return false
	snap.rest_done = true
	snap.toggle_tracked(pick["point"], str(pick.get("kind", "")))
	if plugin.has_method("update_overlays"):
		plugin.update_overlays()
	return true


## Track the snap point the viewport shows, or let it go: the palette's Track
## Point, and Shift when the preferences say so.
static func track_here(plugin: Object) -> bool:
	var snap = _snap_of(plugin)
	if snap == null:
		return false
	var pick: Dictionary = snap.shown_pick
	if not (str(pick.get("kind", "")) in HFSnapSystemType.TRACKABLE):
		_say(plugin, "Rest the pointer on a vertex, a midpoint or a centre first", 1)
		return false
	snap.toggle_tracked(pick["point"], str(pick["kind"]))
	if plugin.has_method("update_overlays"):
		plugin.update_overlays()
	return true


## Take X and Z for the next pick from the snap point the viewport shows; the pick
## keeps its own height.
static func take_xz_here(plugin: Object) -> bool:
	var snap = _snap_of(plugin)
	if snap == null or not (snap.shown_pick.get("point") is Vector3):
		_say(plugin, "Point at the point to take X and Z from first", 1)
		return false
	snap.take_xz_from(snap.shown_pick["point"])
	_say(plugin, "Next pick: X and Z from here, the height from where you click", 0)
	_ask_again(plugin)
	return true


static func clear(plugin: Object) -> bool:
	var snap = _snap_of(plugin)
	if snap == null:
		return false
	snap.clear_tracked()
	if plugin.has_method("update_overlays"):
		plugin.update_overlays()
	return true


## Escape: drop a typed distance or the X and Z taken for the next pick.
static func cancel(plugin: Object) -> bool:
	var snap = _snap_of(plugin)
	if snap == null:
		return false
	var had_text := str(snap.guide_text) != ""
	snap.guide_text = ""
	if snap.cancel_pending_point() or had_text:
		_ask_again(plugin)
		return true
	return false


## A key over the viewport while a guide shows: a number typed puts the next pick
## that far along the guide from its point, Enter to take it. Shift tracks the
## point under the pointer when the preferences say Shift does. False for any
## other key, which goes on as before.
static func key(plugin: Object, event: InputEventKey) -> bool:
	if event == null or not event.pressed or event.echo:
		return false
	var snap = _snap_of(plugin)
	if snap == null or not snap.tracking:
		return false
	if event.keycode == KEY_SHIFT and shift_takes(plugin):
		if str(snap.shown_pick.get("kind", "")) in HFSnapSystemType.TRACKABLE:
			return track_here(plugin)
		return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	var on_guide := str(snap.shown_pick.get("kind", "")) == HFSnapSystemType.KIND_GUIDE
	var text := str(snap.guide_text)
	if not on_guide and text == "":
		return false
	var digit := _digit(event.keycode)
	if digit >= 0:
		snap.guide_text = text + str(digit)
	elif event.keycode in [KEY_PERIOD, KEY_KP_PERIOD] and not text.contains("."):
		snap.guide_text = text + "."
	elif event.keycode == KEY_BACKSPACE and text != "":
		snap.guide_text = text.substr(0, text.length() - 1)
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and text != "":
		snap.guide_text = ""
		if not text.is_valid_float() or not snap.type_along_guide(float(text)):
			return false
		_ask_again(plugin)
		return true
	else:
		return false
	if plugin.has_method("update_overlays"):
		plugin.update_overlays()
	return true


static func _digit(keycode: int) -> int:
	if keycode >= KEY_0 and keycode <= KEY_9:
		return keycode - KEY_0
	if keycode >= KEY_KP_0 and keycode <= KEY_KP_9:
		return keycode - KEY_KP_0
	return -1


static func _say(plugin: Object, message: String, level: int) -> void:
	var dock = plugin.get("dock")
	if dock and dock.has_method("show_toast"):
		dock.show_toast(message, level)


## The tracked points, each a plus, and the guides from them, dotted, along the
## world axes; the guide the pick is on drawn bright.
static func draw_guides(overlay: Control, camera: Camera3D, snap: Object) -> void:
	if not snap.tracking or snap.tracked.is_empty():
		return
	var color := HFOverlayColors.get_color(HFOverlayColors.HOVER)
	var faint := Color(color.r, color.g, color.b, 0.35)
	for entry in snap.tracked:
		var point: Vector3 = entry["point"]
		for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			_dashed(overlay, camera, point, axis, faint)
		if camera.is_position_behind(point):
			continue
		var at := camera.unproject_position(point)
		var plus := PackedVector2Array(
			[
				at + Vector2(-TRACKED_HALF, 0),
				at + Vector2(TRACKED_HALF, 0),
				at + Vector2(0, -TRACKED_HALF),
				at + Vector2(0, TRACKED_HALF),
			]
		)
		overlay.draw_multiline(plus, color, LINE_WIDTH)
	var pick: Dictionary = snap.shown_pick
	if str(pick.get("kind", "")) == HFSnapSystemType.KIND_GUIDE and pick.has("source"):
		var axis := Vector3.ZERO
		axis[int(pick["axis"])] = 1.0
		_dashed(overlay, camera, pick["source"], axis, Color(color.r, color.g, color.b, 1.0))


## A dotted line through `point` along `axis`, the part of it in front of the
## camera.
static func _dashed(
	overlay: Control, camera: Camera3D, point: Vector3, axis: Vector3, color: Color
) -> void:
	var forward := -camera.global_basis.z
	var depth := (point - camera.global_position).dot(forward)
	var rate := axis.dot(forward)
	var low := -GUIDE_REACH
	var high := GUIDE_REACH
	var near := camera.near + 0.05
	if not is_zero_approx(rate):
		var edge := (near - depth) / rate
		if rate > 0.0:
			low = maxf(low, edge)
		else:
			high = minf(high, edge)
	elif depth < near:
		return
	if low >= high:
		return
	var a := camera.unproject_position(point + axis * low)
	var b := camera.unproject_position(point + axis * high)
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var dashes := PackedVector2Array()
	var t := 0.0
	while t < length and dashes.size() < 4000:
		dashes.append(a.lerp(b, t / length))
		dashes.append(a.lerp(b, minf(t + DASH, length) / length))
		t += DASH * 2.0
	overlay.draw_multiline(dashes, color, 1.0)


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
	draw_guides(overlay, camera, snap)
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
	# A guide says where it runs from and how far along it the point is (#1692).
	if str(pick.get("label", "")) != "":
		text = str(pick["label"])
	if str(snap.guide_text) != "":
		text += "  (%s m, Enter)" % str(snap.guide_text)
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
