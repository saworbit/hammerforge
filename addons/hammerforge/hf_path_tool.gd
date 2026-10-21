@tool
class_name HFPathTool
extends "hf_editor_tool.gd"

## Draw a path of connected line segments, then extrude a rectangular
## cross-section along it to create corridor/walkway brushes.
## Each segment becomes an independent brush, all auto-grouped. Corners are
## mitred, a click on the first point closes the loop, and the cross-section
## can stand to either side of the clicked line, so a room's walls are one
## loop of clicks (#1412).

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
@warning_ignore_restore("shadowed_global_identifier")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const PathSweep = preload("res://addons/hammerforge/hf_path_sweep.gd")

enum Phase { IDLE, PLACING_WAYPOINTS }

var _phase: int = Phase.IDLE
var _waypoints: PackedVector3Array = PackedVector3Array()
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

## A segment shorter than this has no length worth a label.
const LABEL_MIN_LENGTH := 0.01

## The least distance a click closes the loop from, whatever the grid: the snap
## system's own "plainly aiming at that point" distance.
const CLOSE_DISTANCE := 0.1

## Which side of the clicked line the cross-section stands on, looking the way the
## path runs. Centre straddles it.
enum PathSide { CENTRE, LEFT, RIGHT }


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

	# Left click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return _handle_click(camera, mouse_pos, event.shift_pressed)

	# Right click — undo last point
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		return _handle_escape()

	# Mouse motion
	if event is InputEventMouseMotion:
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


func get_shortcut_hud_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("-- Path Tool --")
	var w: float = get_setting("path_width")
	var h: float = get_setting("path_height")
	match _phase:
		Phase.IDLE:
			lines.append("Click: Start path")
		Phase.PLACING_WAYPOINTS:
			lines.append("Click: Place point (%d placed)" % _waypoints.size())
			if _waypoints.size() >= 3:
				lines.append("Click first point: Close and build")
			lines.append("Shift: Lock to axis")
			lines.append("Enter: Build path")
			lines.append("Esc/RMB: Undo point")
	var side: int = get_setting("path_side")
	var side_names := ["Centre", "Left", "Right"]
	lines.append("Width: %.1f  Height: %.1f  Side: %s" % [w, h, side_names[side]])
	var extra_mode: int = get_setting("path_extra")
	var extra_names := ["None", "Stairs", "Railings", "Trim"]
	if extra_mode > 0 and extra_mode < extra_names.size():
		lines.append("Auto: %s" % extra_names[extra_mode])
	lines.append(";: Exit tool")
	return lines


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
			_waypoints.append(snapped_pos)
			_cursor_pos = snapped_pos
			_phase = Phase.PLACING_WAYPOINTS
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		Phase.PLACING_WAYPOINTS:
			var hit := _place_point(camera, mouse_pos, axis_lock)
			if _closes_at(hit):
				_close_loop()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_waypoints.append(hit)
			_cursor_pos = hit
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Whether a point placed at `pos` closes the loop: three points down, and within
## snap distance of the first. The snap system's reach, or half a grid step, so a
## click the grid would put on the first point does close it.
func _closes_at(pos: Vector3) -> bool:
	if _waypoints.size() < 3:
		return false
	var first: Vector3 = _waypoints[0]
	var reach := CLOSE_DISTANCE
	if root and root.get("snap_system") and root.snap_system.get("snap_threshold") is float:
		reach = maxf(reach, root.snap_system.snap_threshold)
	reach = maxf(reach, grid_step() * 0.5)
	return Vector2(pos.x - first.x, pos.z - first.z).length() <= reach


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
		if _waypoints.size() > 0:
			_waypoints.resize(_waypoints.size() - 1)
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

	# Auto-generate extras (stairs, railings, trim)
	var extra_mode: int = get_setting("path_extra")
	if extra_mode == PathExtra.STAIRS:
		var stair_infos := _build_stairs(path_width, path_height, group_id, custom_shape)
		brush_infos.append_array(stair_infos)
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
		if undo_redo and not pre_state.is_empty():
			var post_state: Dictionary = root.state_system.capture_state(true)
			undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, null, false)
			undo_redo.add_do_method(root.state_system, "restore_state", post_state)
			undo_redo.add_undo_method(root.state_system, "restore_state", pre_state)
			undo_redo.commit_action(false)
		if history_callback.is_valid():
			history_callback.call(action_name)

	_reset()
	return true


## The waypoints a build reads: any that repeat the one before are left out, as
## they have no direction for a corner to be cut across.
func _path_points() -> PackedVector3Array:
	return PathSweep.distinct(_waypoints, _closed)


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
## stops them, as `PathSweep.sweep()` gives them.
func _sweep_walls(points: PackedVector3Array, closed: bool, width: float) -> Dictionary:
	var band := _band_for(width)
	var mitred: bool = get_setting("miter_joints")
	return PathSweep.sweep(points, closed, mitred, band.x, band.y)


## Why the path cannot be built as it stands, in words for the mapper, or "" when
## it can. Asked before anything is made, so a refusal leaves nothing behind.
func _refusal() -> String:
	var path_width: float = get_setting("path_width")
	var points := _path_points()
	var walls := _sweep_walls(points, _closed, path_width)
	if walls["fault"] == "doubles_back":
		return (
			"Path not built: it turns straight back on itself at point %d." % (int(walls["at"]) + 1)
			+ " Take a point back with Esc or right-click"
		)
	if walls["fault"] != "":
		return _too_short_message(walls, "its mitred corners")
	var extra_mode: int = get_setting("path_extra")
	if extra_mode == PathExtra.TRIM:
		for trim_band: Vector2 in _trim_bands(path_width):
			var trim := PathSweep.footprints(points, walls["cuts"], trim_band.x, trim_band.y)
			if trim["fault"] != "":
				return _too_short_message(trim, "the trim's mitred corners")
	return ""


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
## on its segment's mean height as the walls always have. Cut on the walls' own
## corners, so a band beside them is cut on the same planes.
func _band_pieces(band: Vector2, height: float, path_width: float, group_id: String) -> Array:
	var points := _path_points()
	var walls := _sweep_walls(points, _closed, path_width)
	if walls["fault"] != "":
		return []
	var swept := PathSweep.footprints(points, walls["cuts"], band.x, band.y)
	var infos: Array = []
	var ends := _segment_ends()
	var footprints: Array = swept["footprints"]
	for k in footprints.size():
		var bottom: float = (ends[k][0].y + ends[k][1].y) * 0.5
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
	var faces := PathSweep.prism(footprint, bottom, bottom + height, center)
	if faces.is_empty():
		return {}
	var face_dicts: Array = []
	for face: FaceData in faces:
		face_dicts.append(face.to_dict())
	var low := Vector3(INF, 0.0, INF)
	var high := Vector3(-INF, 0.0, -INF)
	for corner in footprint:
		low = Vector3(minf(low.x, corner.x), 0.0, minf(low.z, corner.z))
		high = Vector3(maxf(high.x, corner.x), 0.0, maxf(high.z, corner.z))
	return {
		"shape": LevelRootType.BrushShape.CUSTOM,
		"size": Vector3(high.x - low.x, height, high.z - low.z),
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

		var num_steps := maxi(1, int(ceil(absf(height_diff) / maxf(step_h, 0.01))))
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


# ---------------------------------------------------------------------------
# Auto-generation: Trim (edge strips with material assignment)
# ---------------------------------------------------------------------------


func _build_trim(path_width: float, group_id: String, custom_shape: int) -> Array:
	var infos: Array = []
	var trim_h: float = get_setting("trim_height")
	var trim_mat: int = get_setting("trim_material_idx")

	# A strip along the outside of each edge, mitred on the walls' own corners so
	# it turns them with the walls rather than overlapping itself at each one.
	for trim_band: Vector2 in _trim_bands(path_width):
		for info: Dictionary in _band_pieces(trim_band, trim_h, path_width, group_id):
			info["shape"] = custom_shape
			# Apply material to all faces
			if trim_mat >= 0:
				for face_dict: Dictionary in info["faces"]:
					face_dict["material_idx"] = trim_mat
			infos.append(info)

	return infos


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
	for i in range(n - 1):
		_immediate_mesh.surface_set_color(Color.CYAN)
		_immediate_mesh.surface_add_vertex(_waypoints[i])
		_immediate_mesh.surface_set_color(Color.CYAN)
		_immediate_mesh.surface_add_vertex(_waypoints[i + 1])

	# Line from last waypoint to cursor
	if _phase == Phase.PLACING_WAYPOINTS and n >= 1:
		_immediate_mesh.surface_set_color(Color(0.0, 1.0, 1.0, 0.4))
		_immediate_mesh.surface_add_vertex(_waypoints[n - 1])
		_immediate_mesh.surface_set_color(Color(0.0, 1.0, 1.0, 0.4))
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


## Outline the walls a build would make from the points placed and the cursor:
## each segment's footprint as the sweep cuts it, or, when the sweep would refuse
## them, each segment's band square-ended and in the refusal colour.
func _draw_footprints(pw: float) -> void:
	var outline := _preview_footprints(pw)
	var color := REFUSED_COLOR if outline["refused"] else FOOTPRINT_COLOR
	for ring: PackedVector3Array in outline["rings"]:
		for i in ring.size():
			_immediate_mesh.surface_set_color(color)
			_immediate_mesh.surface_add_vertex(ring[i])
			_immediate_mesh.surface_set_color(color)
			_immediate_mesh.surface_add_vertex(ring[(i + 1) % ring.size()])


## The outlines `_draw_footprints()` draws, each at its segment's height:
## {"rings": Array, "refused": bool}.
func _preview_footprints(pw: float) -> Dictionary:
	var placing := _waypoints.duplicate()
	var closed := _closes_at(_cursor_pos)
	if _phase == Phase.PLACING_WAYPOINTS and not closed:
		placing.append(_cursor_pos)
	var points := PathSweep.distinct(placing, closed)
	var walls := _sweep_walls(points, closed, pw)
	var refused: bool = walls["fault"] != ""
	var band := _band_for(pw)
	var rings: Array = []
	for k in PathSweep.segment_count(points.size(), closed):
		var a: Vector3 = points[k]
		var b: Vector3 = points[(k + 1) % points.size()]
		var footprint := PackedVector3Array()
		if refused:
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
	return {"rings": rings, "refused": refused}


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


func _draw_railing_preview(band: Vector2) -> void:
	var rail_h: float = get_setting("railing_height")
	var n := _waypoints.size()
	for i in range(n - 1):
		var a: Vector3 = _waypoints[i]
		var b: Vector3 = _waypoints[i + 1]
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
	var n := _waypoints.size()
	for i in range(n - 1):
		var a: Vector3 = _waypoints[i]
		var b: Vector3 = _waypoints[i + 1]
		var dir := b - a
		dir.y = 0.0
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var perp := PathSweep.right_of(dir)
		# Trim strip edges (offset from path edge)
		for edge in [band.x - trim_w, band.y + trim_w]:
			var outer: Vector3 = perp * edge
			_immediate_mesh.surface_set_color(Color(0.9, 0.4, 0.1, 0.5))
			_immediate_mesh.surface_add_vertex(a + outer)
			_immediate_mesh.surface_set_color(Color(0.9, 0.4, 0.1, 0.5))
			_immediate_mesh.surface_add_vertex(b + outer)


func _draw_stairs_preview(band: Vector2) -> void:
	var step_h: float = get_setting("stair_step_height")
	var n := _waypoints.size()
	for i in range(n - 1):
		var a: Vector3 = _waypoints[i]
		var b: Vector3 = _waypoints[i + 1]
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
		var num_steps := maxi(1, int(ceil(absf(height_diff) / maxf(step_h, 0.01))))
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
