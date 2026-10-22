@tool
class_name HFPathTool
extends "hf_editor_tool.gd"

## Draw a path of connected line segments, then extrude a rectangular
## cross-section along it to create corridor/walkway brushes.
## Each segment becomes an independent brush, all auto-grouped. Corners are
## mitred, a click on the first point closes the loop, and the cross-section
## can stand to either side of the clicked line, so a room's walls are one
## loop of clicks (#1412). With Curve Smooth the path runs through the points as
## a curve, cut into pieces that meet face to face (#1436), and trim can take a
## shaped profile (#1413).

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const HFStairsBuilder = preload("res://addons/hammerforge/hf_stairs_builder.gd")
const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const PathSweep = preload("res://addons/hammerforge/hf_path_sweep.gd")
const PathCurve = preload("res://addons/hammerforge/hf_path_curve.gd")
const TrimProfile = preload("res://addons/hammerforge/hf_trim_profile.gd")

enum Phase { IDLE, PLACING_WAYPOINTS }

var _phase: int = Phase.IDLE
var _waypoints: PackedVector3Array = PackedVector3Array()
## Each waypoint's tangent handle (#1436): where a click and drag pulled it out to,
## from the point, or zero where it has none and a smooth path takes the
## Catmull-Rom tangent there. One a waypoint, though a caller that sets the
## waypoints alone may leave it short; a missing handle is none.
var _handles: PackedVector3Array = PackedVector3Array()
## The waypoint whose handle the held left button is pulling out, or -1.
var _pulling := -1
## Whether the path runs on from its last point back to its first. Set by the
## click that closes it, for the build that click starts.
var _closed := false
var _ground_y: float = 0.0
var _cursor_pos: Vector3 = Vector3.ZERO
var _mesh_instance: MeshInstance3D = null
var _immediate_mesh: ImmediateMesh = null
## One length label per segment drawn, kept between redraws (#1408).
var _length_labels: Array = []

## Colours of the length labels: a segment placed, and the one following the cursor.
const PLACED_LENGTH_COLOR := Color.CYAN
const LIVE_LENGTH_COLOR := Color.YELLOW

## The preview's outline of what will be built, and of a path that would be refused.
const FOOTPRINT_COLOR := Color(0.0, 0.8, 0.8, 0.6)
const REFUSED_COLOR := Color(1.0, 0.3, 0.2, 0.8)
## The first point's marker while a click would close the loop on it.
const CLOSE_COLOR := Color(0.3, 1.0, 0.3)
## A pulled-out tangent handle, and the curve's line to the cursor.
const HANDLE_COLOR := Color(1.0, 0.5, 1.0)
const LIVE_PATH_COLOR := Color(0.0, 1.0, 1.0, 0.4)

## A segment shorter than this has no length worth a label.
const LABEL_MIN_LENGTH := 0.01

## The least distance a click closes the loop from, whatever the grid: the snap
## system's own "plainly aiming at that point" distance.
const CLOSE_DISTANCE := 0.1

## Which side of the clicked line the cross-section stands on, looking the way the
## path runs. Centre straddles it.
enum PathSide { CENTRE, LEFT, RIGHT }

## Whether the path runs straight from point to point, or as a curve through them.
enum CurveMode { OFF, SMOOTH }


func tool_name() -> String:
	return "Path"


func tool_id() -> int:
	return 103


func tool_shortcut_key() -> int:
	return KEY_SEMICOLON


## Auto-generation mode for path extras.
enum PathExtra { NONE, STAIRS, RAILING, TRIM }


func get_settings_schema() -> Array:
	return [
		{
			"name": "path_width",
			"type": "float",
			"label": "Width",
			"default": 4.0,
			"min": 0.5,
			"max": 64.0,
		},
		{
			"name": "path_height",
			"type": "float",
			"label": "Height",
			"default": 4.0,
			"min": 0.5,
			"max": 64.0,
		},
		{
			"name": "path_side",
			"type": "enum",
			"label": "Side",
			"default": PathSide.CENTRE,
			"options": ["Centre", "Left", "Right"],
		},
		{
			"name": "miter_joints",
			"type": "bool",
			"label": "Miter Joints",
			"default": true,
		},
		{
			"name": "path_curve",
			"type": "enum",
			"label": "Curve",
			"default": CurveMode.OFF,
			"options": ["Off", "Smooth"],
		},
		{
			"name": "curve_segments",
			"type": "int",
			"label": "Curve Segments",
			"default": 8,
			"min": 2,
			"max": 64,
		},
		{
			"name": "path_extra",
			"type": "enum",
			"label": "Auto-Generate",
			"default": 0,
			"options": ["None", "Stairs", "Railings", "Trim"],
		},
		{
			"name": "stair_step_height",
			"type": "float",
			"label": "Step Height",
			"default": 0.25,
			"min": 0.05,
			"max": 2.0,
		},
		{
			"name": "railing_height",
			"type": "float",
			"label": "Railing Height",
			"default": 1.0,
			"min": 0.2,
			"max": 5.0,
		},
		{
			"name": "railing_thickness",
			"type": "float",
			"label": "Railing Thickness",
			"default": 0.1,
			"min": 0.02,
			"max": 1.0,
		},
		{
			"name": "railing_post_spacing",
			"type": "float",
			"label": "Post Spacing",
			"default": 2.0,
			"min": 0.5,
			"max": 10.0,
		},
		{
			"name": "trim_width",
			"type": "float",
			"label": "Trim Width",
			"default": 0.3,
			"min": 0.05,
			"max": 2.0,
		},
		{
			"name": "trim_height",
			"type": "float",
			"label": "Trim Height",
			"default": 0.15,
			"min": 0.02,
			"max": 1.0,
		},
		{
			"name": "trim_profile",
			"type": "enum",
			"label": "Trim Profile",
			"default": TrimProfile.Profile.FLAT,
			"options": TrimProfile.NAMES.duplicate(),
		},
		{
			"name": "trim_segments",
			"type": "int",
			"label": "Trim Segments",
			"default": 4,
			"min": 1,
			"max": 16,
		},
		{
			"name": "trim_flip",
			"type": "bool",
			"label": "Trim Flip",
			"default": false,
		},
		{
			"name": "trim_material_idx",
			"type": "int",
			"label": "Trim Material",
			"default": 0,
			"min": 0,
			"max": 255,
		},
	]


func activate(p_root: Node3D, p_camera: Camera3D) -> void:
	super.activate(p_root, p_camera)
	_reset()


func deactivate() -> void:
	_clear_visuals()
	_reset()
	super.deactivate()


func handle_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
	if not root or not camera:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Keyboard
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			return _handle_escape()
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			return _handle_enter()

	# Left click, and the release that ends a handle's pull
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			return _handle_click(camera, mouse_pos, event.shift_pressed)
		if _pulling >= 0:
			_pulling = -1
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Right click — undo last point
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		return _handle_escape()

	# Mouse motion
	if event is InputEventMouseMotion:
		if _pulling >= 0:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
				recover_lost_pointer_capture()
			else:
				_pull_handle(camera, mouse_pos, event.shift_pressed)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		if _phase == Phase.PLACING_WAYPOINTS:
			_cursor_pos = _place_point(camera, mouse_pos, event.shift_pressed)
			# On the first point while it would close the loop, so the preview
			# shows the closed path a click there builds.
			if _closes_at(_cursor_pos):
				_cursor_pos = _waypoints[0]
			_update_preview()

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func handle_keyboard(event: InputEventKey) -> int:
	if event.pressed:
		if event.keycode == KEY_ESCAPE:
			return _handle_escape()
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			return _handle_enter()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## The Draw hover preview shows where the first waypoint lands (#1400), and
## only until it is placed.
func shows_draw_hover() -> bool:
	return _phase == Phase.IDLE


## The release that ended a handle's pull never came: keep the handle where the
## last drag left it.
func recover_lost_pointer_capture() -> bool:
	if _pulling < 0:
		return false
	_pulling = -1
	_update_preview()
	return true


## The viewport lost focus mid-pull: the point stays, without the handle it was
## being given.
func cancel_pointer_capture() -> bool:
	if _pulling < 0:
		return false
	if _pulling < _handles.size():
		_handles[_pulling] = Vector3.ZERO
	_pulling = -1
	_update_preview()
	return true


func get_shortcut_hud_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("-- Path Tool --")
	var w: float = get_setting("path_width")
	var h: float = get_setting("path_height")
	match _phase:
		Phase.IDLE:
			lines.append("Click: Start path")
			if _smooth():
				lines.append("Drag: Pull a tangent handle")
		Phase.PLACING_WAYPOINTS:
			lines.append("Click: Place point (%d placed)" % _waypoints.size())
			if _smooth():
				lines.append("Drag: Pull a tangent handle")
			if _waypoints.size() >= 3:
				lines.append("Click first point: Close and build")
			lines.append("Shift: Lock to axis")
			lines.append("Enter: Build path")
			lines.append("Esc/RMB: Undo point")
	var side: int = get_setting("path_side")
	var side_names := ["Centre", "Left", "Right"]
	lines.append("Width: %.1f  Height: %.1f  Side: %s" % [w, h, side_names[side]])
	if _smooth():
		lines.append("Curve: Smooth, %d pieces a span" % int(get_setting("curve_segments")))
	var extra_mode: int = get_setting("path_extra")
	var extra_names := ["None", "Stairs", "Railings", "Trim"]
	if extra_mode == PathExtra.TRIM:
		lines.append("Auto: Trim (%s)" % _trim_count_text())
	elif extra_mode > 0 and extra_mode < extra_names.size():
		lines.append("Auto: %s" % extra_names[extra_mode])
	lines.append(";: Exit tool")
	return lines


## How many trim strips Enter would build, for the HUD (#1413): the profile and the
## count for the points placed, or the count a side of each segment before there
## is a segment.
func _trim_count_text() -> String:
	var profile: int = get_setting("trim_profile")
	var profile_name: String = TrimProfile.NAMES[clampi(profile, 0, TrimProfile.NAMES.size() - 1)]
	var per_side := _trim_profile_bands().size()
	var segments := _segment_ends().size()
	if segments == 0:
		return "%s, %d strips a side" % [profile_name, per_side]
	return "%s, %d strips" % [profile_name, per_side * 2 * segments]


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------


func _handle_click(camera: Camera3D, mouse_pos: Vector2, axis_lock := false) -> int:
	match _phase:
		Phase.IDLE:
			var start := first_point_start(camera, mouse_pos)
			if start.is_empty():
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			var snapped_pos: Vector3 = start["point"]
			_ground_y = snapped_pos.y
			_add_waypoint(snapped_pos)
			_cursor_pos = snapped_pos
			_phase = Phase.PLACING_WAYPOINTS
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		Phase.PLACING_WAYPOINTS:
			var hit := _place_point(camera, mouse_pos, axis_lock)
			if _closes_at(hit):
				_close_loop()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_add_waypoint(hit)
			_cursor_pos = hit
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Place a waypoint with no handle. On a smooth path the button that placed it
## goes on to pull its handle out for as long as it is held (#1436).
func _add_waypoint(point: Vector3) -> void:
	_handles.resize(_waypoints.size())
	_waypoints.append(point)
	_handles.append(Vector3.ZERO)
	_pulling = _waypoints.size() - 1 if _smooth() else -1


## Pull the handle of the point just placed out to the mouse (#1436), snapped as a
## point is, and with Shift held kept on the X or Z line through the point. A pull
## no longer than the reach a click closes the loop from is none, so a click that
## wobbles keeps its Catmull-Rom tangent rather than making a sharp corner.
func _pull_handle(camera: Camera3D, mouse_pos: Vector2, axis_lock: bool) -> void:
	if _pulling >= _waypoints.size():
		_pulling = -1
		return
	var point: Vector3 = _waypoints[_pulling]
	var hit: Vector3 = root.screen_ray_to_y_plane(camera, mouse_pos, point.y)
	var end: Vector3 = snap_point_on_axis(point, hit) if axis_lock else snap_point(hit)
	var handle := Vector3(end.x - point.x, 0.0, end.z - point.z)
	if handle.length() <= _reach():
		handle = Vector3.ZERO
	_handles.resize(_waypoints.size())
	_handles[_pulling] = handle
	# No segment runs on to the cursor while it is pulling a handle.
	_cursor_pos = point
	_update_preview()


## Whether a point placed at `pos` closes the loop: three points down, and within
## `_reach()` of the first.
func _closes_at(pos: Vector3) -> bool:
	if _waypoints.size() < 3:
		return false
	var first: Vector3 = _waypoints[0]
	return Vector2(pos.x - first.x, pos.z - first.z).length() <= _reach()


## How near the mouse plainly aims at a point: the snap system's reach, or half a
## grid step, so a click the grid would put on a point does land on it.
func _reach() -> float:
	var reach := CLOSE_DISTANCE
	if root and root.get("snap_system") and root.snap_system.get("snap_threshold") is float:
		reach = maxf(reach, root.snap_system.snap_threshold)
	return maxf(reach, grid_step() * 0.5)


## Whether the path runs as a curve through its points (#1436).
func _smooth() -> bool:
	return int(get_setting("path_curve")) == CurveMode.SMOOTH


## Build the path closed, with a corner at the first point like every other. A
## refused loop stays open, its points kept for the mapper to change.
func _close_loop() -> void:
	_closed = true
	if not _build_path():
		_closed = false
		_update_preview()


## Where the next waypoint lands: on the plane the first one set, snapped, and
## with Shift held kept on the X or Z line through the last waypoint (#1408).
func _place_point(camera: Camera3D, mouse_pos: Vector2, axis_lock: bool) -> Vector3:
	var hit: Vector3 = root.screen_ray_to_y_plane(camera, mouse_pos, _ground_y)
	if axis_lock and not _waypoints.is_empty():
		return snap_point_on_axis(_waypoints[_waypoints.size() - 1], hit)
	return snap_point(hit)


func _handle_enter() -> int:
	if _phase == Phase.PLACING_WAYPOINTS and _waypoints.size() >= 2:
		_build_path()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_escape() -> int:
	if _phase == Phase.PLACING_WAYPOINTS:
		_pulling = -1
		if _waypoints.size() > 0:
			_waypoints.resize(_waypoints.size() - 1)
			if _handles.size() > _waypoints.size():
				_handles.resize(_waypoints.size())
			if _waypoints.is_empty():
				_phase = Phase.IDLE
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		_phase = Phase.IDLE
		_clear_visuals()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


# ---------------------------------------------------------------------------
# Path construction
# ---------------------------------------------------------------------------


## Build the path, or refuse it with a toast and keep its points when a segment
## has no room for its mitres or the path turns straight back on itself. Nothing
## is made and no undo step is left by a refusal. Returns false when refused.
func _build_path() -> bool:
	var points := _path_points()
	if points.size() < 2:
		_reset()
		return true
	var refusal := _refusal()
	if refusal != "":
		_warn(refusal)
		return false

	var path_width: float = get_setting("path_width")
	var path_height: float = get_setting("path_height")
	var group_id := "path_%d" % Time.get_ticks_usec()
	# Resolve CUSTOM shape from the preloaded LevelRoot script — no runtime fallback needed.
	var custom_shape: int = LevelRootType.BrushShape.CUSTOM

	# One piece per segment, mitred where it meets the next, so a corner is two
	# pieces sharing a plane rather than two overlapping boxes and a wedge.
	var brush_infos: Array = _band_pieces(_band_for(path_width), path_height, path_width, group_id)

	# Auto-generate extras (stairs, railings, trim). On a curve they follow its
	# pieces, cut on the same planes as the walls (#1436).
	var extra_mode: int = get_setting("path_extra")
	if extra_mode == PathExtra.STAIRS and _smooth():
		brush_infos.append_array(_build_curved_stairs(path_width, group_id, custom_shape))
	elif extra_mode == PathExtra.STAIRS:
		var stair_infos := _build_stairs(path_width, path_height, group_id, custom_shape)
		brush_infos.append_array(stair_infos)
	elif extra_mode == PathExtra.RAILING and _smooth():
		brush_infos.append_array(_build_curved_railings(path_width, group_id, custom_shape))
	elif extra_mode == PathExtra.RAILING:
		var railing_infos := _build_railings(path_width, group_id, custom_shape)
		brush_infos.append_array(railing_infos)
	elif extra_mode == PathExtra.TRIM:
		var trim_infos := _build_trim(path_width, group_id, custom_shape)
		brush_infos.append_array(trim_infos)

	# Create all brushes
	if (
		not brush_infos.is_empty()
		and root
		and root.get("brush_system")
		and root.brush_system.has_method("create_brush_from_info")
	):
		# Capture full state before creation for undo
		var pre_state: Dictionary = {}
		if root.get("state_system") and root.state_system.has_method("capture_state"):
			pre_state = root.state_system.capture_state(true)

		for info in brush_infos:
			root.brush_system.give_active_material(info)
			root.brush_system.create_brush_from_info(info)

		var action_name := "Create Path (%d segments)" % brush_infos.size()
		# Through the helper, which records History and ends a run of nudges (#1677).
		if not pre_state.is_empty():
			HFUndoHelper.commit_completed(undo_redo, root, action_name, pre_state, history_callback)
		elif history_callback.is_valid():
			history_callback.call(action_name)

	_reset()
	return true


## The corners a build cuts: the waypoints, any that repeat the one before left
## out as they have no direction for a corner to be cut across, or on a smooth
## path the samples of the curve through them.
func _path_points() -> PackedVector3Array:
	return _route()["points"]


## The path the build follows, as `_route_of()` gives it for the points placed.
func _route() -> Dictionary:
	return _route_of(_waypoints, _handles, _closed)


## The path through `waypoints` as clicked, with their `handles`: {"points": the
## corners the sweep cuts, "spans": for each segment between them, the clicked
## span it is part of, "clicked": the clicked points, repeats left out}. With
## Curve Off the corners are the clicked points and each segment is a span of its
## own. Smooth, they are `curve_segments` samples a span of the curve through the
## clicked points (#1436), which the sweep cuts as it cuts any corner.
func _route_of(
	waypoints: PackedVector3Array, handles: PackedVector3Array, closed: bool
) -> Dictionary:
	if not _smooth():
		var points := PathSweep.distinct(waypoints, closed)
		var spans := PackedInt32Array()
		for k in PathSweep.segment_count(points.size(), closed):
			spans.append(k)
		return {"points": points, "spans": spans, "clicked": points}
	var clicked := PathCurve.distinct(waypoints, handles, closed)
	var segments: int = get_setting("curve_segments")
	var sampled := PathCurve.sample(clicked["points"], clicked["handles"], closed, segments)
	return {"points": sampled["points"], "spans": sampled["spans"], "clicked": clicked["points"]}


## Each segment's two ends, the one back to the first point included when the
## path is closed.
func _segment_ends() -> Array:
	var points := _path_points()
	var ends: Array = []
	for k in PathSweep.segment_count(points.size(), _closed):
		ends.append([points[k], points[(k + 1) % points.size()]])
	return ends


## The offsets from the clicked line a cross-section `width` wide spans, positive
## to the right of travel: centred on the line, or wholly to one side of it.
func _band_for(width: float) -> Vector2:
	var side: int = get_setting("path_side")
	match side:
		PathSide.LEFT:
			return Vector2(-width, 0.0)
		PathSide.RIGHT:
			return Vector2(0.0, width)
	return Vector2(-width * 0.5, width * 0.5)


## The walls swept along `points`: their cuts and footprints, or the fault that
## stops them, as `PathSweep.sweep()` gives them. A smooth path is always cut on
## the bisectors, as its samples have no corner to leave square.
func _sweep_walls(points: PackedVector3Array, closed: bool, width: float) -> Dictionary:
	var band := _band_for(width)
	var mitred: bool = get_setting("miter_joints") or _smooth()
	return PathSweep.sweep(points, closed, mitred, band.x, band.y)


## Why the path cannot be built as it stands, in words for the mapper, or "" when
## it can. Asked before anything is made, so a refusal leaves nothing behind.
func _refusal() -> String:
	return _fault_of(_route(), _closed, get_setting("path_width"))["message"]


## Why a path along `route` (from `_route_of()`) cannot be built, and where:
## {"message": the refusal in words for the mapper, or "" when it can be built,
## "segments": the segments the preview outlines in red}. On a smooth path the
## message names the clicked span, and every piece of it is outlined.
func _fault_of(route: Dictionary, closed: bool, path_width: float) -> Dictionary:
	var points: PackedVector3Array = route["points"]
	var walls := _sweep_walls(points, closed, path_width)
	var count := PathSweep.segment_count(points.size(), closed)
	if walls["fault"] == "doubles_back":
		var at := int(walls["at"])
		var meeting := PackedInt32Array([(at - 1 + count) % count, at % count])
		var message := (
			"Path not built: it turns straight back on itself at point %d." % (at + 1)
			+ " Take a point back with Esc or right-click"
		)
		if _smooth():
			message = (
				"Path not built: %s turns straight back on itself." % _span_text(route, meeting[1])
				+ " Take a point back with Esc or right-click"
			)
			meeting = _span_segments(route, meeting[1])
		return {"message": message, "segments": meeting}
	var cuts: Array = walls["cuts"]
	if walls["fault"] != "":
		var what := "a path %s wide" % length_text(path_width, grid_step())
		return _too_short_fault(
			route, walls, cuts, _band_for(path_width), "its mitred corners", what
		)
	var extra_mode: int = get_setting("path_extra")
	var extra_bands: Array = []
	var extra_name := ""
	if extra_mode == PathExtra.TRIM:
		extra_bands = _trim_bands(path_width)
		extra_name = "the trim"
	elif extra_mode == PathExtra.RAILING and _smooth():
		extra_bands = _rail_bands(path_width)
		extra_name = "the railings"
	for extra_band: Vector2 in extra_bands:
		var extra := PathSweep.footprints(points, cuts, extra_band.x, extra_band.y)
		if extra["fault"] != "":
			var what := extra_name + "'s mitred corners"
			return _too_short_fault(route, extra, cuts, extra_band, what, extra_name)
	return {"message": "", "segments": PackedInt32Array()}


## The fault `swept`, a sweep of `band` on `cuts` that came out "too_short",
## makes: the first segment too short for `what` on a straight path, or on a
## smooth one the first span bending too tightly for `item`. Every segment with
## no room is outlined, so a bend tight on both sides of a point shows as one.
func _too_short_fault(
	route: Dictionary, swept: Dictionary, cuts: Array, band: Vector2, what: String, item: String
) -> Dictionary:
	var points: PackedVector3Array = route["points"]
	var cramped := PackedInt32Array()
	for k in cuts.size():
		var ends := PackedVector3Array([points[k], points[(k + 1) % points.size()]])
		if PathSweep.footprints(ends, [cuts[k]], band.x, band.y)["fault"] != "":
			cramped.append(k)
	var at := int(swept["at"])
	if not _smooth():
		return {"message": _too_short_message(swept, what), "segments": cramped}
	var outlined := PackedInt32Array()
	for k in cramped:
		for piece in _span_segments(route, k):
			if not outlined.has(piece):
				outlined.append(piece)
	return {
		"message":
		(
			"Path not built: %s bends too tightly for %s." % [_span_text(route, at), item]
			+ " Take a point back with Esc or right-click, or narrow the path"
		),
		"segments": outlined,
	}


## "the curve from point 2 to point 3": the clicked span segment `k` is part of,
## its points counted from 1 as a segment is.
func _span_text(route: Dictionary, k: int) -> String:
	var spans: PackedInt32Array = route["spans"]
	var span: int = spans[clampi(k, 0, spans.size() - 1)] if not spans.is_empty() else 0
	var clicked := (route["clicked"] as PackedVector3Array).size()
	return "the curve from point %d to point %d" % [span + 1, (span + 1) % maxi(clicked, 1) + 1]


## Every segment of the clicked span segment `k` is part of.
func _span_segments(route: Dictionary, k: int) -> PackedInt32Array:
	var spans: PackedInt32Array = route["spans"]
	var out := PackedInt32Array()
	if spans.is_empty():
		return out
	var span: int = spans[clampi(k, 0, spans.size() - 1)]
	for i in spans.size():
		if spans[i] == span:
			out.append(i)
	return out


func _too_short_message(swept: Dictionary, what: String) -> String:
	var step := grid_step()
	return (
		(
			"Path not built: segment %d is %s long, too short for %s, which need more than %s."
			% [
				int(swept["at"]) + 1,
				length_text(swept["length"], step),
				what,
				length_text(swept["needs"], step),
			]
		)
		+ " Take a point back with Esc or right-click, or narrow the path"
	)


## A toast when the level can show one, and a warning in the output either way.
func _warn(message: String) -> void:
	if root and root.has_signal("user_message"):
		root.emit_signal("user_message", message, 1)
	push_warning("HammerForge: " + message)


## The band [lo, hi] swept along the path as brushes `height` tall, each standing
## `lift` above its segment's mean height, where the walls have always stood. Cut
## on the walls' own corners, so a band beside them is cut on the same planes.
func _band_pieces(
	band: Vector2, height: float, path_width: float, group_id: String, lift := 0.0
) -> Array:
	var points := _path_points()
	var walls := _sweep_walls(points, _closed, path_width)
	if walls["fault"] != "":
		return []
	var swept := PathSweep.footprints(points, walls["cuts"], band.x, band.y)
	var infos: Array = []
	var ends := _segment_ends()
	var footprints: Array = swept["footprints"]
	for k in footprints.size():
		var bottom: float = (ends[k][0].y + ends[k][1].y) * 0.5 + lift
		var info := _piece_info(footprints[k], bottom, height, group_id)
		if not info.is_empty():
			infos.append(info)
	return infos


## What `create_brush_from_info()` takes to build `footprint` stood up from
## `bottom`, `height` tall, or an empty Dictionary when it encloses nothing.
func _piece_info(
	footprint: PackedVector3Array, bottom: float, height: float, group_id: String
) -> Dictionary:
	if footprint.size() < 3 or height <= 0.0:
		return {}
	var center := Vector3.ZERO
	for corner in footprint:
		center += corner
	center /= float(footprint.size())
	center.y = bottom + height * 0.5
	return _solid_info(
		PathSweep.prism(footprint, bottom, bottom + height, center), center, group_id
	)


## What `create_brush_from_info()` takes to build the convex `faces`, local to
## `center`, or an empty Dictionary when there are none.
func _solid_info(faces: Array, center: Vector3, group_id: String) -> Dictionary:
	if faces.is_empty():
		return {}
	var face_dicts: Array = []
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for face: FaceData in faces:
		face_dicts.append(face.to_dict())
		for corner in face.local_verts:
			low = low.min(corner)
			high = high.max(corner)
	return {
		"shape": LevelRootType.BrushShape.CUSTOM,
		"size": high - low,
		"operation": CSGShape3D.OPERATION_UNION,
		"center": center,
		"faces": face_dicts,
		"group_id": group_id,
	}


func _build_segment_brush(
	a: Vector3, b: Vector3, width: float, height: float, group_id: String
) -> Dictionary:
	var dir := b - a
	dir.y = 0.0
	var length := dir.length()
	if length < 0.01:
		return {}
	# A negative half-extent swaps the two sides of every corner ring, which
	# reverses the winding of all six quads and builds the corridor inside out.
	# _usable_size() catches a negative in the reported size and never sees the
	# face array that a CUSTOM brush actually renders and bakes.
	if width <= 0.0 or height <= 0.0:
		return {}
	dir = dir.normalized()
	# Perpendicular in XZ plane
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var half_w := width * 0.5
	var half_h := height * 0.5
	var center := (a + b) * 0.5
	center.y = (a.y + b.y) * 0.5 + half_h

	# 8 corners of oriented box (in world space, then convert to local)
	var corners: Array = []
	for vert_y in [-half_h, half_h]:
		for wp in [-1.0, 1.0]:  # width direction
			for lp in [-1.0, 1.0]:  # length direction
				var world_pt: Vector3 = (
					center
					+ dir * (length * 0.5 * lp)
					+ perp * (half_w * wp)
					+ Vector3(0, vert_y, 0)
				)
				corners.append(world_pt - center)  # to local space

	# corners layout:
	# 0: bot, -w, -l  |  1: bot, -w, +l  |  2: bot, +w, -l  |  3: bot, +w, +l
	# 4: top, -w, -l  |  5: top, -w, +l  |  6: top, +w, -l  |  7: top, +w, +l

	var faces: Array = []
	# Build 6 quads, each wound clockwise seen from outside the brush, which is
	# what `FaceData._compute_normal()` reads and what every other brush in the
	# editor uses. These rings used to be listed the other way round, which put
	# all six normals on the inside and baked a corridor inside out.
	var quads := [
		# Front (+length dir)
		[corners[1], corners[3], corners[7], corners[5]],
		# Back (-length dir)
		[corners[2], corners[0], corners[4], corners[6]],
		# Right (+perp)
		[corners[3], corners[2], corners[6], corners[7]],
		# Left (-perp)
		[corners[0], corners[1], corners[5], corners[4]],
		# Top
		[corners[4], corners[5], corners[7], corners[6]],
		# Bottom
		[corners[0], corners[2], corners[3], corners[1]],
	]

	for quad in quads:
		var face := FaceData.new()
		face.local_verts = PackedVector3Array(quad)
		face.ensure_geometry()
		faces.append(face.to_dict())

	return {
		"shape": 0,  # Overwritten by _build_path() with BrushShape.CUSTOM — not axis-aligned box, has custom face data
		"size": Vector3(length, height, width),
		"operation": CSGShape3D.OPERATION_UNION,
		"center": center,
		"faces": faces,
		"group_id": group_id,
	}


# ---------------------------------------------------------------------------
# Auto-generation: Stairs
# ---------------------------------------------------------------------------


func _build_stairs(
	path_width: float, _path_height: float, group_id: String, custom_shape: int
) -> Array:
	var infos: Array = []
	var step_h: float = get_setting("stair_step_height")
	if step_h < 0.01:
		return infos

	# Treads span the cross-section, so they follow it to whichever side it stands.
	var band := _band_for(path_width)
	var band_middle := (band.x + band.y) * 0.5
	for ends: Array in _segment_ends():
		var a: Vector3 = ends[0]
		var b: Vector3 = ends[1]
		var height_diff := b.y - a.y
		if absf(height_diff) < 0.01:
			continue  # Flat segment — no stairs needed

		var dir := b - a
		dir.y = 0.0
		var seg_length := dir.length()
		if seg_length < 0.01:
			continue
		dir = dir.normalized()
		var shift := PathSweep.right_of(dir) * band_middle

		var num_steps := HFStairsBuilder.step_count(height_diff, maxf(step_h, 0.01))
		var actual_step_h := height_diff / float(num_steps)

		for s_idx in range(num_steps):
			var t0 := float(s_idx) / float(num_steps)
			var t1 := float(s_idx + 1) / float(num_steps)
			var y_base := a.y + actual_step_h * float(s_idx + 1)
			var step_start := a + shift + dir * (seg_length * t0)
			var step_end := a + shift + dir * (seg_length * t1)
			step_start.y = y_base
			step_end.y = y_base

			# Build a thin box for the tread
			var tread_height := absf(actual_step_h)
			if tread_height < 0.02:
				tread_height = 0.02
			var info := _build_segment_brush(
				step_start, step_end, path_width, tread_height, group_id
			)
			if not info.is_empty():
				info["shape"] = custom_shape
				infos.append(info)

	return infos


## Stairs on a smooth path (#1436). Each clicked span that climbs is cut into
## steps of one rise, at equal lengths along the curve, as a straight segment is
## along its length. A tread crosses the curve's pieces, so it is one brush for
## each piece it crosses: cut where it starts and stops on a line leaning between
## that piece's two end cuts, and on the walls' own cut where it runs on past the
## piece's end, so the parts of a tread meet face to face as the walls do.
func _build_curved_stairs(path_width: float, group_id: String, custom_shape: int) -> Array:
	var infos: Array = []
	var step_h: float = get_setting("stair_step_height")
	if step_h < 0.01:
		return infos
	var route := _route()
	var points: PackedVector3Array = route["points"]
	var walls := _sweep_walls(points, _closed, path_width)
	if walls["fault"] != "":
		return infos
	var cuts: Array = walls["cuts"]
	var footprints: Array = walls["footprints"]
	var clicked: PackedVector3Array = route["clicked"]
	var spans: PackedInt32Array = route["spans"]
	var span_count := PathSweep.segment_count(clicked.size(), _closed)
	for span in span_count:
		var rise: float = clicked[(span + 1) % clicked.size()].y - clicked[span].y
		if absf(rise) < 0.01:
			continue
		var pieces := PackedInt32Array()
		var starts := PackedFloat32Array()
		var lengths := PackedFloat32Array()
		var total := 0.0
		for k in spans.size():
			if spans[k] != span:
				continue
			var run := points[(k + 1) % points.size()] - points[k]
			pieces.append(k)
			starts.append(total)
			lengths.append(Vector2(run.x, run.z).length())
			total += lengths[lengths.size() - 1]
		var steps := HFStairsBuilder.step_count(rise, step_h)
		var rise_each := rise / float(steps)
		var thickness := maxf(absf(rise_each), 0.02)
		# Where each step starts along the span, settled onto a piece's end when
		# nearer it than a segment can be, so no sliver of a tread is left over.
		var marks := PackedFloat32Array()
		for j in steps + 1:
			var at := total * float(j) / float(steps)
			for p in pieces.size() + 1:
				var end_at: float = total if p == pieces.size() else starts[p]
				if absf(at - end_at) < PathSweep.MIN_SEGMENT:
					at = end_at
			marks.append(at)
		for j in steps:
			var y_base: float = clicked[span].y + rise_each * float(j + 1)
			for p in pieces.size():
				var from := clampf((marks[j] - starts[p]) / lengths[p], 0.0, 1.0)
				var to := clampf((marks[j + 1] - starts[p]) / lengths[p], 0.0, 1.0)
				if to - from < 0.000001:
					continue
				var k: int = pieces[p]
				var tread := PathSweep.slice(footprints[k], cuts[k][0], cuts[k][1], from, to)
				var info := _piece_info(tread, y_base, thickness, group_id)
				if not info.is_empty():
					info["shape"] = custom_shape
					infos.append(info)
	return infos


# ---------------------------------------------------------------------------
# Auto-generation: Railings
# ---------------------------------------------------------------------------


func _build_railings(path_width: float, group_id: String, custom_shape: int) -> Array:
	var infos: Array = []
	var rail_h: float = get_setting("railing_height")
	var rail_t: float = get_setting("railing_thickness")
	var post_spacing: float = get_setting("railing_post_spacing")

	# Along both edges of the cross-section, wherever it stands.
	var band := _band_for(path_width)
	for ends: Array in _segment_ends():
		var a: Vector3 = ends[0]
		var b: Vector3 = ends[1]
		var dir := b - a
		dir.y = 0.0
		var seg_length := dir.length()
		if seg_length < 0.01:
			continue
		dir = dir.normalized()
		var perp := PathSweep.right_of(dir)

		# Top rail on each side
		for edge in [band.x, band.y]:
			var rail_a: Vector3 = a + perp * edge
			var rail_b: Vector3 = b + perp * edge
			rail_a.y = lerpf(a.y, b.y, 0.0) + rail_h
			rail_b.y = lerpf(a.y, b.y, 1.0) + rail_h

			var rail_info := _build_segment_brush(rail_a, rail_b, rail_t, rail_t, group_id)
			if not rail_info.is_empty():
				rail_info["shape"] = custom_shape
				infos.append(rail_info)

		# Posts along each side
		var num_posts := maxi(2, int(ceil(seg_length / maxf(post_spacing, 0.1))) + 1)
		for p_idx in range(num_posts):
			var t := float(p_idx) / float(num_posts - 1)
			var pos := a.lerp(b, t)

			for edge in [band.x, band.y]:
				var post_base: Vector3 = pos + perp * edge
				var post_info := _build_segment_brush(
					post_base, post_base + dir * rail_t, rail_t, rail_h, group_id
				)
				if not post_info.is_empty():
					post_info["shape"] = custom_shape
					# Adjust center Y for the post
					post_info["center"].y = post_base.y + rail_h * 0.5
					infos.append(post_info)

	return infos


## Railings on a smooth path (#1436): each rail swept along the curve on the
## walls' own cuts, as trim is, so it turns with them rather than breaking at
## every piece, and posts spaced evenly along the whole path rather than at both
## ends of every piece.
func _build_curved_railings(path_width: float, group_id: String, custom_shape: int) -> Array:
	var infos: Array = []
	var rail_h: float = get_setting("railing_height")
	var rail_t: float = get_setting("railing_thickness")
	var post_spacing: float = get_setting("railing_post_spacing")
	for rail_band: Vector2 in _rail_bands(path_width):
		for info: Dictionary in _band_pieces(rail_band, rail_t, path_width, group_id, rail_h):
			info["shape"] = custom_shape
			infos.append(info)

	var points := _path_points()
	var count := PathSweep.segment_count(points.size(), _closed)
	var lengths := PackedFloat32Array()
	var total := 0.0
	for k in count:
		var run := points[(k + 1) % points.size()] - points[k]
		lengths.append(Vector2(run.x, run.z).length())
		total += lengths[k]
	if total <= 0.0:
		return infos
	# An open path has a post at both ends; a closed one's last would stand on its first.
	var gaps := maxi(1, ceili(total / maxf(post_spacing, 0.1)))
	var posts := gaps if _closed else gaps + 1
	var band := _band_for(path_width)
	var piece := 0
	var start := 0.0
	for p in posts:
		var at := total * float(p) / float(gaps)
		while piece < count - 1 and at > start + lengths[piece]:
			start += lengths[piece]
			piece += 1
		var a: Vector3 = points[piece]
		var b: Vector3 = points[(piece + 1) % points.size()]
		var along := clampf((at - start) / maxf(lengths[piece], 0.000001), 0.0, 1.0)
		var pos := a.lerp(b, along)
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		for edge: float in [band.x, band.y]:
			var post_base: Vector3 = pos + PathSweep.right_of(dir) * edge
			var post_info := _build_segment_brush(
				post_base, post_base + dir * rail_t, rail_t, rail_h, group_id
			)
			if not post_info.is_empty():
				post_info["shape"] = custom_shape
				post_info["center"].y = post_base.y + rail_h * 0.5
				infos.append(post_info)
	return infos


## The two rails' bands, each `railing_thickness` wide and centred on an edge of
## a cross-section `path_width` wide.
func _rail_bands(path_width: float) -> Array:
	var half: float = float(get_setting("railing_thickness")) * 0.5
	var band := _band_for(path_width)
	return [Vector2(band.x - half, band.x + half), Vector2(band.y - half, band.y + half)]


# ---------------------------------------------------------------------------
# Auto-generation: Trim (edge strips with material assignment)
# ---------------------------------------------------------------------------


func _build_trim(path_width: float, group_id: String, custom_shape: int) -> Array:
	var infos: Array = []
	var trim_mat: int = get_setting("trim_material_idx")
	var points := _path_points()
	var walls := _sweep_walls(points, _closed, path_width)
	if walls["fault"] != "":
		return infos
	var cuts: Array = walls["cuts"]
	var ends := _segment_ends()
	var lift := _trim_lift()

	# A strip along the outside of each edge, mitred on the walls' own corners so
	# it turns them with the walls rather than overlapping itself at each one. A
	# shaped profile is one strip for each of its bands (#1413).
	for side: Dictionary in _trim_sides(path_width):
		var plan: Vector2 = side["band"]
		if PathSweep.footprints(points, cuts, plan.x, plan.y)["fault"] != "":
			continue
		for section: PackedVector2Array in side["sections"]:
			for k in cuts.size():
				var base: float = (ends[k][0].y + ends[k][1].y) * 0.5 + lift
				var info := _section_info(cuts[k][0], cuts[k][1], section, base, ends[k], group_id)
				if info.is_empty():
					continue
				info["shape"] = custom_shape
				# Apply material to all faces
				if trim_mat >= 0:
					for face_dict: Dictionary in info["faces"]:
						face_dict["material_idx"] = trim_mat
				infos.append(info)

	return infos


## What `create_brush_from_info()` takes to build `section` (offsets and heights
## above `base`) swept along a segment from its `start` cut to its `end` cut,
## `ends` being the segment's two points.
func _section_info(
	start: Dictionary,
	end: Dictionary,
	section: PackedVector2Array,
	base: float,
	ends: Array,
	group_id: String
) -> Dictionary:
	if section.size() < 3:
		return {}
	var a: Vector3 = ends[0]
	var b: Vector3 = ends[1]
	var middle := Vector2.ZERO
	for corner in section:
		middle += corner
	middle /= float(section.size())
	var across := PathSweep.right_of(Vector3(b.x - a.x, 0.0, b.z - a.z).normalized())
	var center := Vector3((a.x + b.x) * 0.5, base + middle.y, (a.z + b.z) * 0.5) + across * middle.x
	return _solid_info(PathSweep.section_solid(start, end, section, base, center), center, group_id)


## The trim's section a side: {"band": the offsets it spans, "sections": each of
## the profile's bands as a ring of offsets and heights}, the profile's "out"
## running away from the path on each side.
func _trim_sides(path_width: float) -> Array:
	var trim_w: float = get_setting("trim_width")
	var band := _band_for(path_width)
	var profile_bands := _trim_profile_bands()
	var sides: Array = []
	for side: Vector2 in [Vector2(band.x, -1.0), Vector2(band.y, 1.0)]:
		var sections: Array = []
		for profile_band: PackedVector2Array in profile_bands:
			var section := PackedVector2Array()
			for corner in profile_band:
				section.append(Vector2(side.x + side.y * corner.x, corner.y))
			sections.append(section)
		var reach := side.x + side.y * trim_w
		sides.append(
			{"band": Vector2(minf(side.x, reach), maxf(side.x, reach)), "sections": sections}
		)
	return sides


## The trim's profile, as the bands `TrimProfile.bands()` cuts it into.
func _trim_profile_bands() -> Array:
	return TrimProfile.bands(
		get_setting("trim_profile"),
		get_setting("trim_width"),
		get_setting("trim_height"),
		get_setting("trim_segments"),
		get_setting("trim_flip")
	)


## How far above the path's base the trim's base stands: none, or with Trim Flip
## as far as puts the trim's top flush with the path's.
func _trim_lift() -> float:
	if not get_setting("trim_flip"):
		return 0.0
	return float(get_setting("path_height")) - float(get_setting("trim_height"))


## The two trim strips' bands, one against the outside of each edge of a
## cross-section `path_width` wide.
func _trim_bands(path_width: float) -> Array:
	var trim_w: float = get_setting("trim_width")
	var band := _band_for(path_width)
	return [Vector2(band.x - trim_w, band.x), Vector2(band.y, band.y + trim_w)]


# ---------------------------------------------------------------------------
# Preview rendering
# ---------------------------------------------------------------------------


func _update_preview() -> void:
	if not root:
		return
	if _waypoints.is_empty() and _phase == Phase.IDLE:
		_clear_visuals()
		return
	_ensure_mesh()
	_immediate_mesh.clear_surfaces()

	if _waypoints.is_empty():
		free_overlay_labels(_length_labels)
		return

	var pw: float = get_setting("path_width")

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Draw path polyline
	var n := _waypoints.size()
	if _smooth():
		_draw_curve()
	else:
		for i in range(n - 1):
			_immediate_mesh.surface_set_color(Color.CYAN)
			_immediate_mesh.surface_add_vertex(_waypoints[i])
			_immediate_mesh.surface_set_color(Color.CYAN)
			_immediate_mesh.surface_add_vertex(_waypoints[i + 1])

		# Line from last waypoint to cursor
		if _phase == Phase.PLACING_WAYPOINTS and n >= 1:
			_immediate_mesh.surface_set_color(LIVE_PATH_COLOR)
			_immediate_mesh.surface_add_vertex(_waypoints[n - 1])
			_immediate_mesh.surface_set_color(LIVE_PATH_COLOR)
			_immediate_mesh.surface_add_vertex(_cursor_pos)

	# What will be built: each segment's footprint, mitred and to its side, with
	# the segment to the cursor and the closing one while a click would close it.
	_draw_footprints(pw)

	# Waypoint markers, the first lit while a click on it would close the loop.
	var closing := _closes_at(_cursor_pos)
	for i in n:
		var pt: Vector3 = _waypoints[i]
		var s := 0.4
		var color := CLOSE_COLOR if i == 0 and closing else Color.WHITE
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(pt + Vector3(-s, 0, 0))
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(pt + Vector3(s, 0, 0))
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(pt + Vector3(0, 0, -s))
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(pt + Vector3(0, 0, s))

	if _smooth():
		_draw_handles()

	# Draw auto-generation extras preview
	var extra_mode: int = get_setting("path_extra")
	var band := _band_for(pw)
	if extra_mode == PathExtra.RAILING and n >= 2:
		_draw_railing_preview(band)
	elif extra_mode == PathExtra.TRIM and n >= 2:
		_draw_trim_preview(band)
	elif extra_mode == PathExtra.STAIRS and n >= 2:
		_draw_stairs_preview(band)

	_immediate_mesh.surface_end()
	_update_length_labels()


func _line(from: Vector3, to: Vector3, color: Color) -> void:
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(from)
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(to)


## The smooth path as it will be cut, through the points placed and on to the
## cursor, the part on to the cursor fainter.
func _draw_curve() -> void:
	var placing := _placing_route()
	var route: Dictionary = placing["route"]
	var points: PackedVector3Array = route["points"]
	var spans: PackedInt32Array = route["spans"]
	for k in spans.size():
		var color := LIVE_PATH_COLOR if spans[k] >= int(placing["live_from"]) else Color.CYAN
		_line(points[k], points[(k + 1) % points.size()], color)


## Each pulled-out handle, through its point to both its ends.
func _draw_handles() -> void:
	var s := 0.2
	for i in mini(_waypoints.size(), _handles.size()):
		var handle: Vector3 = _handles[i]
		if handle == Vector3.ZERO:
			continue
		var point: Vector3 = _waypoints[i]
		_line(point - handle, point + handle, HANDLE_COLOR)
		for end in [point - handle, point + handle]:
			_line(end + Vector3(-s, 0, -s), end + Vector3(s, 0, s), HANDLE_COLOR)
			_line(end + Vector3(-s, 0, s), end + Vector3(s, 0, -s), HANDLE_COLOR)


## Outline the walls a build would make from the points placed and the cursor:
## each segment's footprint as the sweep cuts it, or, when the sweep would refuse
## them, each segment's band square-ended. What stops the build is in the refusal
## colour: the segment, or on a smooth path every piece of the span, a toast would
## name.
func _draw_footprints(pw: float) -> void:
	var outline := _preview_footprints(pw)
	var rings: Array = outline["rings"]
	var faulty: Array = outline["faulty"]
	for r in rings.size():
		var ring: PackedVector3Array = rings[r]
		var color := REFUSED_COLOR if faulty[r] else FOOTPRINT_COLOR
		for i in ring.size():
			_line(ring[i], ring[(i + 1) % ring.size()], color)


## The outlines `_draw_footprints()` draws, each at its segment's height:
## {"rings": Array, "refused": whether the path would be refused, "faulty": for
## each ring, whether it is part of what stops the build}.
func _preview_footprints(pw: float) -> Dictionary:
	var placing := _placing_route()
	var route: Dictionary = placing["route"]
	var closed: bool = placing["closed"]
	var points: PackedVector3Array = route["points"]
	var walls := _sweep_walls(points, closed, pw)
	var fault := _fault_of(route, closed, pw)
	var at_fault: PackedInt32Array = fault["segments"]
	var square: bool = walls["fault"] != ""
	var band := _band_for(pw)
	var rings: Array = []
	var faulty: Array = []
	for k in PathSweep.segment_count(points.size(), closed):
		var a: Vector3 = points[k]
		var b: Vector3 = points[(k + 1) % points.size()]
		var footprint := PackedVector3Array()
		if square:
			var right := PathSweep.right_of(Vector3(b.x - a.x, 0.0, b.z - a.z).normalized())
			for corner in [
				a + right * band.x, b + right * band.x, b + right * band.y, a + right * band.y
			]:
				footprint.append(Vector3(corner.x, 0.0, corner.z))
		else:
			footprint = walls["footprints"][k]
		var ring := PackedVector3Array()
		for corner in footprint:
			ring.append(corner + Vector3(0.0, (a.y + b.y) * 0.5, 0.0))
		rings.append(ring)
		faulty.append(at_fault.has(k))
	return {"rings": rings, "refused": fault["message"] != "", "faulty": faulty}


## The path the preview shows: the points placed and, unless a click there would
## close the loop, the cursor. {"route": as `_route_of()` gives it, "closed",
## "live_from": the first span on to the cursor, past the last when there is none}.
func _placing_route() -> Dictionary:
	var placing := _waypoints.duplicate()
	var handles := _handles.duplicate()
	handles.resize(placing.size())
	var closed := _closes_at(_cursor_pos)
	var live := _phase == Phase.PLACING_WAYPOINTS and not closed
	if live:
		placing.append(_cursor_pos)
		handles.append(Vector3.ZERO)
	var route := _route_of(placing, handles, closed)
	var placed := PathSweep.distinct(_waypoints, false).size()
	var live_from := placed - 1 if live else placed
	if live and (route["clicked"] as PackedVector3Array).size() <= placed:
		# The cursor is on the last point, so no span runs on to it.
		live_from = placed
	return {"route": route, "closed": closed, "live_from": live_from}


## Each segment's length at its middle (#1408): the segments placed, and the one
## to the cursor while placing.
func _update_length_labels() -> void:
	var segments: Array = []
	var n := _waypoints.size()
	for i in range(n - 1):
		segments.append([_waypoints[i], _waypoints[i + 1], PLACED_LENGTH_COLOR])
	if _phase == Phase.PLACING_WAYPOINTS and n >= 1:
		segments.append([_waypoints[n - 1], _cursor_pos, LIVE_LENGTH_COLOR])
	# Nothing to label on a segment with no length, such as the one to the
	# cursor before the mouse has moved off the waypoint just placed.
	var labelled: Array = []
	for segment: Array in segments:
		if (segment[0] as Vector3).distance_to(segment[1]) > LABEL_MIN_LENGTH:
			labelled.append(segment)
	show_segment_lengths(root, _length_labels, labelled, grid_step())


## The segments the extras' preview lines follow: each pair of waypoints placed,
## or on a smooth path each piece of the curve through them.
func _preview_segments() -> Array:
	if _smooth():
		return _segment_ends()
	var pairs: Array = []
	for i in range(_waypoints.size() - 1):
		pairs.append([_waypoints[i], _waypoints[i + 1]])
	return pairs


func _draw_railing_preview(band: Vector2) -> void:
	var rail_h: float = get_setting("railing_height")
	var segments := _preview_segments()
	var n := segments.size() + 1
	# A curve's posts are spaced along it, not stood at every piece's end.
	var posts_each := not _smooth()
	for i in range(n - 1):
		var a: Vector3 = segments[i][0]
		var b: Vector3 = segments[i][1]
		var dir := b - a
		dir.y = 0.0
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var perp := PathSweep.right_of(dir)
		# Railing lines on each edge (at rail height)
		for edge in [band.x, band.y]:
			var ra: Vector3 = a + perp * edge + Vector3(0, rail_h, 0)
			var rb: Vector3 = b + perp * edge + Vector3(0, rail_h, 0)
			_immediate_mesh.surface_set_color(Color(1.0, 0.8, 0.2, 0.6))
			_immediate_mesh.surface_add_vertex(ra)
			_immediate_mesh.surface_set_color(Color(1.0, 0.8, 0.2, 0.6))
			_immediate_mesh.surface_add_vertex(rb)
			# Vertical posts at endpoints
			if posts_each or i == 0:
				_immediate_mesh.surface_set_color(Color(1.0, 0.8, 0.2, 0.4))
				_immediate_mesh.surface_add_vertex(a + perp * edge)
				_immediate_mesh.surface_set_color(Color(1.0, 0.8, 0.2, 0.4))
				_immediate_mesh.surface_add_vertex(ra)
			if i == n - 2:
				_immediate_mesh.surface_set_color(Color(1.0, 0.8, 0.2, 0.4))
				_immediate_mesh.surface_add_vertex(b + perp * edge)
				_immediate_mesh.surface_set_color(Color(1.0, 0.8, 0.2, 0.4))
				_immediate_mesh.surface_add_vertex(rb)


func _draw_trim_preview(band: Vector2) -> void:
	var trim_w: float = get_setting("trim_width")
	# At the trim's foot, which Trim Flip hangs from the path's top.
	var lift := Vector3(0.0, _trim_lift(), 0.0)
	for segment: Array in _preview_segments():
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var dir := b - a
		dir.y = 0.0
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var perp := PathSweep.right_of(dir)
		# Trim strip edges (offset from path edge)
		for edge in [band.x - trim_w, band.y + trim_w]:
			var outer: Vector3 = perp * edge + lift
			_immediate_mesh.surface_set_color(Color(0.9, 0.4, 0.1, 0.5))
			_immediate_mesh.surface_add_vertex(a + outer)
			_immediate_mesh.surface_set_color(Color(0.9, 0.4, 0.1, 0.5))
			_immediate_mesh.surface_add_vertex(b + outer)


## Where each step of a smooth path's stairs ends, as `_build_curved_stairs()`
## counts and spaces them: `[position, direction]` for every step of every
## clicked span that climbs, at equal lengths along its curve. One per tread the
## build makes, where counting each curve piece on its own made more (#1676).
func _curved_step_ends() -> Array:
	var out: Array = []
	var step_h: float = get_setting("stair_step_height")
	if step_h < 0.01:
		return out
	var route := _route()
	var points: PackedVector3Array = route["points"]
	var clicked: PackedVector3Array = route["clicked"]
	var spans: PackedInt32Array = route["spans"]
	for span in PathSweep.segment_count(clicked.size(), _closed):
		var rise: float = clicked[(span + 1) % clicked.size()].y - clicked[span].y
		if absf(rise) < 0.01:
			continue
		var pieces: Array = []
		var total := 0.0
		for k in spans.size():
			if spans[k] != span:
				continue
			var a: Vector3 = points[k]
			var b: Vector3 = points[(k + 1) % points.size()]
			var length := Vector2(b.x - a.x, b.z - a.z).length()
			pieces.append([a, b, length])
			total += length
		if pieces.is_empty() or total <= 0.0:
			continue
		var steps := HFStairsBuilder.step_count(rise, step_h)
		for j in range(1, steps + 1):
			var at := total * float(j) / float(steps)
			var walked := 0.0
			for p in pieces.size():
				var length: float = pieces[p][2]
				if at > walked + length and p < pieces.size() - 1:
					walked += length
					continue
				var a: Vector3 = pieces[p][0]
				var b: Vector3 = pieces[p][1]
				var pos := a.lerp(
					b, clampf((at - walked) / length, 0.0, 1.0) if length > 0.0 else 1.0
				)
				pos.y = clicked[span].y + rise * float(j) / float(steps)
				var dir := b - a
				dir.y = 0.0
				out.append([pos, dir.normalized()])
				break
	return out


func _draw_stairs_preview(band: Vector2) -> void:
	var step_h: float = get_setting("stair_step_height")
	if _smooth():
		for end: Array in _curved_step_ends():
			var at: Vector3 = end[0]
			var across := PathSweep.right_of(end[1])
			_immediate_mesh.surface_set_color(Color(0.4, 1.0, 0.4, 0.4))
			_immediate_mesh.surface_add_vertex(at + across * band.x)
			_immediate_mesh.surface_set_color(Color(0.4, 1.0, 0.4, 0.4))
			_immediate_mesh.surface_add_vertex(at + across * band.y)
		return
	for segment: Array in _preview_segments():
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var height_diff := b.y - a.y
		if absf(height_diff) < 0.01:
			continue
		var dir := b - a
		dir.y = 0.0
		var seg_length := dir.length()
		if seg_length < 0.01:
			continue
		dir = dir.normalized()
		var perp := PathSweep.right_of(dir)
		var num_steps := HFStairsBuilder.step_count(height_diff, maxf(step_h, 0.01))
		for s_idx in range(num_steps):
			var t := float(s_idx + 1) / float(num_steps)
			var y := a.y + height_diff * t
			var pos := a + dir * (seg_length * t)
			pos.y = y
			# Horizontal tick at each step
			_immediate_mesh.surface_set_color(Color(0.4, 1.0, 0.4, 0.4))
			_immediate_mesh.surface_add_vertex(pos + perp * band.x)
			_immediate_mesh.surface_set_color(Color(0.4, 1.0, 0.4, 0.4))
			_immediate_mesh.surface_add_vertex(pos + perp * band.y)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _reset() -> void:
	_phase = Phase.IDLE
	_waypoints = PackedVector3Array()
	_handles = PackedVector3Array()
	_pulling = -1
	_closed = false
	_cursor_pos = Vector3.ZERO
	_clear_visuals()


func _ensure_mesh() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = make_overlay_mesh(root, "_PathToolPreview")
	_immediate_mesh = _mesh_instance.mesh as ImmediateMesh


func _clear_visuals() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		free_overlay_mesh(_mesh_instance)
	_mesh_instance = null
	_immediate_mesh = null
	free_overlay_labels(_length_labels)
