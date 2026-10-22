@tool
class_name HFPolygonTool
extends "hf_editor_tool.gd"

## Draw a polygon on the ground plane, then extrude to height to create a brush.
## Click to place vertices, Enter/close-click to finish polygon, then drag height.
## An outline that is not convex is split into convex brushes on close (#1430).

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const PolygonSplit = preload("res://addons/hammerforge/hf_polygon_split.gd")

enum Phase { IDLE, PLACING_VERTS, SETTING_HEIGHT }

var _phase: int = Phase.IDLE
var _polygon_points: PackedVector3Array = PackedVector3Array()
var _ground_y: float = 0.0
## How far a polygon extrudes, and what the next one starts at.
##
## Both were the literal 32.0, in the declaration and in two resets. Since #625
## the player is 1.6 units, a default drawn brush is 2 and the grid snaps at 0.5,
## so 32 is twenty players tall -- and because the resets used the literal too, a
## mapper who dragged it down to something usable got 32 back on the next polygon
## (#658). The level's own default brush height is the starting point now, and
## after that it remembers whatever was last built.
var _height: float = 0.0
var _height_start_mouse: Vector2 = Vector2.ZERO
var _height_start_value: float = 0.0
## Zero until the first polygon is finished, so the level's default is used until
## the mapper has expressed a preference. A setting, so it is kept for the next
## session as the tool's other settings are (#1406).
var _remembered_height: float:
	get:
		return float(get_setting(REMEMBERED_HEIGHT))
	set(value):
		set_setting(REMEMBERED_HEIGHT, value)
var _height_pointer_capture := false
var _cursor_pos: Vector3 = Vector3.ZERO  # Current mouse world pos for preview
var _mesh_instance: MeshInstance3D = null
var _immediate_mesh: ImmediateMesh = null
## One length label per edge drawn, kept between redraws (#1408).
var _length_labels: Array = []
## The outline the split below was worked out for, so a mouse motion that moves
## nothing but the cursor does not work it out again.
var _split_for := PackedVector3Array()
var _split: Dictionary = {}
const HEIGHT_SENSITIVITY := 0.5

## Colours of the length labels: an edge placed, and the one following the cursor.
const PLACED_LENGTH_COLOR := Color.CYAN
const LIVE_LENGTH_COLOR := Color.YELLOW
## The lines a concave outline will be split along.
const SPLIT_LINE_COLOR := Color(1.0, 0.6, 0.2, 0.9)

## How close a click has to land to a vertex already placed to count as the same
## vertex. Points arrive snapped, so anything short of the smallest grid step is
## a repeat rather than a very short edge.
const REPEAT_POINT_EPSILON := 0.01

## Smallest XZ area a finished polygon may enclose. Below this the extrusion is a
## sheet rather than a solid.
const MIN_POLYGON_AREA := 0.01

## What a mapper is told when the outline they close cannot be built: it crosses
## itself, or, which the split's own checks are there to catch, its pieces did
## not come out convex and covering it.
const CROSSING_MESSAGE := (
	"Polygon outline crosses itself: take a point back with Esc or right-click,"
	+ " then close it again"
)
const SPLIT_MESSAGE := (
	"Polygon outline could not be split into convex brushes: take a point back with"
	+ " Esc or right-click, then close it again"
)


func tool_name() -> String:
	return "Polygon"


func tool_id() -> int:
	return 102


func tool_shortcut_key() -> int:
	return KEY_P


## The setting the height the last polygon was built to is kept under. Hidden
## from the Tool Settings panel: building a polygon sets it, not a control.
const REMEMBERED_HEIGHT := "extrude_height"


func get_settings_schema() -> Array:
	return [
		{
			"name": "auto_close_threshold",
			"type": "float",
			"label": "Auto-close Dist",
			"default": 1.5,
			"min": 0.1,
			"max": 10.0,
		},
		{
			"name": REMEMBERED_HEIGHT,
			"type": "float",
			"label": "Extrude Height",
			"default": 0.0,
			"min": 0.0,
			"max": 4096.0,
			"hidden": true,
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
			return _handle_enter(camera, mouse_pos)

	# Mouse click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			return _handle_click(camera, mouse_pos, event.shift_pressed)
		# Release during height stage — finalize
		if _phase == Phase.SETTING_HEIGHT:
			_finalize_brush()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Right-click to undo last point or cancel
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		return _handle_escape()

	# Mouse motion
	if event is InputEventMouseMotion:
		if (
			_phase == Phase.SETTING_HEIGHT
			and _height_pointer_capture
			and event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0
		):
			recover_lost_pointer_capture()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if _phase == Phase.PLACING_VERTS:
			_cursor_pos = _place_point(camera, mouse_pos, event.shift_pressed)
			_update_preview()
		elif _phase == Phase.SETTING_HEIGHT:
			var delta_y := (mouse_pos.y - _height_start_mouse.y) * -HEIGHT_SENSITIVITY
			_height = _height_start_value + delta_y
			if root.get("grid_snap") and root.grid_snap > 0.0:
				_height = snappedf(_height, root.grid_snap)
			_height = maxf(0.1, _height)
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func handle_keyboard(event: InputEventKey) -> int:
	if event.pressed:
		if event.keycode == KEY_ESCAPE:
			return _handle_escape()
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			return _handle_enter(null, Vector2.ZERO)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## The Draw hover preview shows where the first point lands (#1400), and only
## until it is placed.
func shows_draw_hover() -> bool:
	return _phase == Phase.IDLE


func recover_lost_pointer_capture() -> bool:
	if _phase != Phase.SETTING_HEIGHT or not _height_pointer_capture:
		return false
	_finalize_brush()
	return true


func cancel_pointer_capture() -> bool:
	if _phase != Phase.SETTING_HEIGHT:
		return false
	_height_pointer_capture = false
	_phase = Phase.PLACING_VERTS
	_update_preview()
	return true


func get_shortcut_hud_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("-- Polygon Tool --")
	match _phase:
		Phase.IDLE:
			lines.append("Click: Start polygon")
		Phase.PLACING_VERTS:
			lines.append("Click: Place vertex (%d placed)" % _polygon_points.size())
			lines.append("Shift: Lock to axis")
			lines.append("Enter: Close polygon")
			lines.append("Esc/RMB: Undo point")
		Phase.SETTING_HEIGHT:
			lines.append("Drag/Move: Set height (%.1f)" % _height)
			lines.append("Release/Enter: Confirm")
			lines.append("Esc: Cancel")
	lines.append("P: Exit tool")
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
			_polygon_points.append(snapped_pos)
			_cursor_pos = snapped_pos
			_phase = Phase.PLACING_VERTS
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		Phase.PLACING_VERTS:
			var hit := _place_point(camera, mouse_pos, axis_lock)
			# Check auto-close
			var threshold: float = get_setting("auto_close_threshold")
			if _polygon_points.size() >= 3:
				var first: Vector3 = _polygon_points[0]
				if hit.distance_to(first) <= threshold:
					_begin_height_stage(mouse_pos, true)
					return EditorPlugin.AFTER_GUI_INPUT_STOP
			# Reject a point on top of one already placed. Two coincident
			# vertices make a side quad with no area, and the convexity gate
			# cannot see them because their cross products are all zero.
			if _is_repeat_point(_polygon_points, hit):
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			# Any point is taken, concave or not. An outline that crosses itself
			# is refused when it is closed, and a concave one is split then.
			_polygon_points.append(hit)
			_cursor_pos = hit
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		Phase.SETTING_HEIGHT:
			_finalize_brush()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Where the next vertex lands: on the plane the first one set, snapped, and with
## Shift held kept on the X or Z line through the last vertex (#1408).
func _place_point(camera: Camera3D, mouse_pos: Vector2, axis_lock: bool) -> Vector3:
	var hit: Vector3 = root.screen_ray_to_y_plane(camera, mouse_pos, _ground_y)
	if axis_lock and not _polygon_points.is_empty():
		return snap_point_on_axis(_polygon_points[_polygon_points.size() - 1], hit)
	return snap_point(hit)


func _handle_enter(_camera: Camera3D, mouse_pos: Vector2) -> int:
	if _phase == Phase.PLACING_VERTS and _polygon_points.size() >= 3:
		_begin_height_stage(mouse_pos, false)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _phase == Phase.SETTING_HEIGHT:
		_finalize_brush()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_escape() -> int:
	if _phase == Phase.SETTING_HEIGHT:
		_height_pointer_capture = false
		_phase = Phase.PLACING_VERTS
		_update_preview()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _phase == Phase.PLACING_VERTS:
		if _polygon_points.size() > 0:
			_polygon_points.resize(_polygon_points.size() - 1)
			if _polygon_points.is_empty():
				_phase = Phase.IDLE
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		_phase = Phase.IDLE
		_clear_visuals()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------


## Returns false and leaves the tool where it is when the polygon encloses
## nothing. `_is_convex_xz()` cannot catch this: for points on one line every
## cross product falls under its degenerate threshold, so it never disagrees with
## itself and reports a convex polygon. Extruding one gives a brush with no
## volume that still saves, bakes and sits in front of every pick.
##
## An outline that crosses itself is refused here too, with a toast, and every
## point stays so the mapper can take back the one that crossed (#1430). That is
## asked first: the two halves of a bow tie cancel in the area sum, so it would
## otherwise be refused as points on one line. Points that really are on one line
## run back over themselves too, and keep their own warning.
func _begin_height_stage(mouse_pos: Vector2, pointer_capture: bool = false) -> bool:
	var outline := _outline_xz(_polygon_points)
	if PolygonSplit.crosses_itself(outline) and not _on_one_line(outline):
		_warn(CROSSING_MESSAGE)
		return false
	if _polygon_area_xz(_polygon_points) < MIN_POLYGON_AREA:
		push_warning(
			(
				"HammerForge: polygon encloses no area (%d points on one line) - not extruding."
				% _polygon_points.size()
			)
		)
		return false
	if _brush_outlines().is_empty():
		_warn(SPLIT_MESSAGE)
		return false
	_phase = Phase.SETTING_HEIGHT
	_height_pointer_capture = pointer_capture
	_height_start_mouse = mouse_pos
	_height = _starting_height()
	_height_start_value = _height
	_update_preview()
	return true


static func _is_repeat_point(existing: PackedVector3Array, new_pt: Vector3) -> bool:
	for pt in existing:
		if pt.distance_to(new_pt) < REPEAT_POINT_EPSILON:
			return true
	return false


## Area the polygon encloses in XZ, by the shoelace sum. Zero when every point
## is on one line, which is what the convexity gate reads as agreement.
static func _polygon_area_xz(pts: PackedVector3Array) -> float:
	var n := pts.size()
	if n < 3:
		return 0.0
	var twice_area := 0.0
	for i in range(n):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % n]
		twice_area += a.x * b.z - b.x * a.z
	return absf(twice_area) * 0.5


## Whether every point is on the line through the first two.
static func _on_one_line(outline: PackedVector2Array) -> bool:
	if outline.size() < 3:
		return true
	var along := outline[1] - outline[0]
	if along.length() < REPEAT_POINT_EPSILON:
		return false
	for i in range(2, outline.size()):
		if absf(along.cross(outline[i] - outline[0])) / along.length() > REPEAT_POINT_EPSILON:
			return false
	return true


## The outline in the XZ plane, the plane the polygon is built on.
static func _outline_xz(pts: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for pt in pts:
		out.append(Vector2(pt.x, pt.z))
	return out


## The outlines the polygon is built from: the outline itself when it is convex,
## so a convex polygon is the one brush it always was, or its convex pieces
## (#1430). Empty when it crosses itself or cannot be split.
func _brush_outlines() -> Array:
	if _polygon_points.size() < 3:
		return []
	if PolygonSplit.crosses_itself(_outline_xz(_polygon_points)):
		return []
	if _is_convex_xz(_polygon_points):
		return [_polygon_points]
	var out: Array = []
	for part: PackedVector2Array in _current_split().get("parts", []):
		var pts := PackedVector3Array()
		for p in part:
			pts.append(Vector3(p.x, _ground_y, p.y))
		out.append(pts)
	return out


## The split of the outline as placed, worked out again only when a vertex is
## added or taken away rather than on every mouse motion.
func _current_split() -> Dictionary:
	if _split_for != _polygon_points:
		_split_for = PackedVector3Array(_polygon_points)
		_split = {}
		if _polygon_points.size() >= 3 and not _is_convex_xz(_polygon_points):
			_split = PolygonSplit.convex_parts(_outline_xz(_polygon_points))
	return _split


static func _is_convex_xz(pts: PackedVector3Array) -> bool:
	var n := pts.size()
	if n < 3:
		return true
	var winding_sign := 0.0
	for i in range(n):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % n]
		var c: Vector3 = pts[(i + 2) % n]
		var cross := (b.x - a.x) * (c.z - b.z) - (b.z - a.z) * (c.x - b.x)
		if absf(cross) < 0.001:
			continue
		if winding_sign == 0.0:
			winding_sign = cross
		elif (cross > 0.0) != (winding_sign > 0.0):
			return false
	return true


func _build_face_data() -> Array:
	return _faces_for(_polygon_points)


## The faces of `points` extruded from the ground to the height, local to the
## average of the points.
func _faces_for(points: PackedVector3Array) -> Array:
	var n := points.size()
	if n < 3:
		return []
	# Compute center for local space
	var center := Vector3.ZERO
	for pt in points:
		center += pt
	center /= float(n)
	center.y = _ground_y + _height * 0.5

	var faces: Array = []
	var bot_y := _ground_y - center.y
	var top_y := _ground_y + _height - center.y

	# Ensure consistent winding — compute winding direction
	var winding := 0.0
	for i in range(n):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % n]
		winding += (b.x - a.x) * (b.z + a.z)
	var ccw := winding < 0.0  # CCW in XZ when viewed from +Y

	# Convert to local XZ
	var local_xz: Array = []
	for pt in points:
		local_xz.append(Vector3(pt.x - center.x, 0.0, pt.z - center.z))

	# Top face — needs normal pointing UP.  Winding is reversed from the
	# cross-product convention so that triangulate() emits front-facing
	# triangles; the normal is then negated to point outward.
	var top_face := FaceData.new()
	var top_verts := PackedVector3Array()
	if ccw:
		for i in range(n):
			top_verts.append(Vector3(local_xz[i].x, top_y, local_xz[i].z))
	else:
		for i in range(n - 1, -1, -1):
			top_verts.append(Vector3(local_xz[i].x, top_y, local_xz[i].z))
	top_face.local_verts = top_verts
	top_face.ensure_geometry()
	faces.append(top_face.to_dict())

	# Bottom face — normal pointing DOWN (reverse winding of top)
	var bot_face := FaceData.new()
	var bot_verts := PackedVector3Array()
	if ccw:
		for i in range(n - 1, -1, -1):
			bot_verts.append(Vector3(local_xz[i].x, bot_y, local_xz[i].z))
	else:
		for i in range(n):
			bot_verts.append(Vector3(local_xz[i].x, bot_y, local_xz[i].z))
	bot_face.local_verts = bot_verts
	bot_face.ensure_geometry()
	faces.append(bot_face.to_dict())

	# Side faces — quads for each polygon edge, wound CW from outside.
	for i in range(n):
		var j := (i + 1) % n
		var side := FaceData.new()
		var a_xz: Vector3 = local_xz[i] if ccw else local_xz[j]
		var b_xz: Vector3 = local_xz[j] if ccw else local_xz[i]
		var side_verts := PackedVector3Array()
		side_verts.append(Vector3(b_xz.x, bot_y, b_xz.z))
		side_verts.append(Vector3(b_xz.x, top_y, b_xz.z))
		side_verts.append(Vector3(a_xz.x, top_y, a_xz.z))
		side_verts.append(Vector3(a_xz.x, bot_y, a_xz.z))
		side.local_verts = side_verts
		side.ensure_geometry()
		faces.append(side.to_dict())

	return faces


## What `create_brush_from_info()` takes to build `points` as a brush, or an
## empty dictionary when they make no faces.
func _brush_info(points: PackedVector3Array) -> Dictionary:
	var face_dicts := _faces_for(points)
	if face_dicts.is_empty():
		return {}
	# Compute center and AABB size
	var center := Vector3.ZERO
	for pt in points:
		center += pt
	center /= float(points.size())
	center.y = _ground_y + _height * 0.5

	var min_pt := Vector3(INF, _ground_y, INF)
	var max_pt := Vector3(-INF, _ground_y + _height, -INF)
	for pt in points:
		min_pt.x = minf(min_pt.x, pt.x)
		min_pt.z = minf(min_pt.z, pt.z)
		max_pt.x = maxf(max_pt.x, pt.x)
		max_pt.z = maxf(max_pt.z, pt.z)
	var aabb_size := max_pt - min_pt

	return {
		"shape": LevelRootType.BrushShape.CUSTOM,
		"size": aabb_size,
		"sides": points.size(),
		"operation": CSGShape3D.OPERATION_UNION,
		"center": center,
		"faces": face_dicts,
	}


func _finalize_brush() -> void:
	if _polygon_points.size() < 3:
		_reset()
		return
	var outlines := _brush_outlines()
	if outlines.is_empty():
		# The height stage refuses an outline that cannot be built, so only a
		# caller that went round it gets here with one.
		var crosses := PolygonSplit.crosses_itself(_outline_xz(_polygon_points))
		_warn(CROSSING_MESSAGE if crosses else SPLIT_MESSAGE)
		_reset()
		return
	var infos: Array = []
	for points: PackedVector3Array in outlines:
		var info := _brush_info(points)
		if not info.is_empty():
			infos.append(info)
	if infos.is_empty():
		_reset()
		return
	# The pieces of a split outline share a group, as a path's pieces do, so one
	# click selects the whole polygon.
	var action_name := "Create Polygon Brush"
	if infos.size() > 1:
		action_name = "Create Polygon (%d brushes)" % infos.size()
		var group_id := "polygon_%d" % Time.get_ticks_usec()
		for info: Dictionary in infos:
			info["group_id"] = group_id

	if root and root.get("brush_system") and root.brush_system.has_method("create_brush_from_info"):
		# Capture full state before creation for undo
		var pre_state: Dictionary = {}
		if root.get("state_system") and root.state_system.has_method("capture_state"):
			pre_state = root.state_system.capture_state(true)

		for info: Dictionary in infos:
			root.brush_system.give_active_material(info)
			root.brush_system.create_brush_from_info(info)

		# Through the helper, which records History and ends a run of nudges (#1677).
		if not pre_state.is_empty():
			HFUndoHelper.commit_completed(undo_redo, root, action_name, pre_state, history_callback)
		elif history_callback.is_valid():
			history_callback.call(action_name)
	# Before the reset, so the next polygon starts where this one ended rather
	# than back at a literal the mapper has already dragged away from.
	_remembered_height = _height
	_reset()


## A toast when the level can show one, and a warning in the output either way.
func _warn(message: String) -> void:
	if root and root.has_signal("user_message"):
		root.emit_signal("user_message", message, 1)
	push_warning("HammerForge: " + message)


# ---------------------------------------------------------------------------
# Preview rendering
# ---------------------------------------------------------------------------


func _update_preview() -> void:
	if not root:
		return
	if _polygon_points.is_empty() and _phase == Phase.IDLE:
		_clear_visuals()
		return
	_ensure_mesh()
	_immediate_mesh.clear_surfaces()

	if _polygon_points.is_empty():
		free_overlay_labels(_length_labels)
		return

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Draw placed polygon outline. While placing, the last edge runs to the
	# cursor; once the outline is closed it runs back to the first vertex.
	var placing := _phase == Phase.PLACING_VERTS
	var n := _polygon_points.size()
	for i in range(n):
		var a: Vector3 = _polygon_points[i]
		var b: Vector3 = _polygon_points[(i + 1) % n] if i < n - 1 or not placing else _cursor_pos
		_immediate_mesh.surface_set_color(Color.CYAN)
		_immediate_mesh.surface_add_vertex(a)
		_immediate_mesh.surface_set_color(Color.CYAN)
		_immediate_mesh.surface_add_vertex(b)

	# Draw closing line to cursor or first point
	if placing and n >= 2:
		# Line from last point to cursor
		# And line from cursor to first point (preview closing)
		_immediate_mesh.surface_set_color(Color(0.0, 1.0, 1.0, 0.3))
		_immediate_mesh.surface_add_vertex(_cursor_pos)
		_immediate_mesh.surface_set_color(Color(0.0, 1.0, 1.0, 0.3))
		_immediate_mesh.surface_add_vertex(_polygon_points[0])

	# In height mode, draw vertical extrusion
	if _phase == Phase.SETTING_HEIGHT and n >= 3:
		var top_y := _ground_y + _height
		# Vertical edges
		for i in range(n):
			var pt: Vector3 = _polygon_points[i]
			_immediate_mesh.surface_set_color(Color.GREEN)
			_immediate_mesh.surface_add_vertex(pt)
			_immediate_mesh.surface_set_color(Color.GREEN)
			_immediate_mesh.surface_add_vertex(Vector3(pt.x, top_y, pt.z))
		# Top polygon outline
		for i in range(n):
			var a: Vector3 = _polygon_points[i]
			var b: Vector3 = _polygon_points[(i + 1) % n]
			_immediate_mesh.surface_set_color(Color.GREEN)
			_immediate_mesh.surface_add_vertex(Vector3(a.x, top_y, a.z))
			_immediate_mesh.surface_set_color(Color.GREEN)
			_immediate_mesh.surface_add_vertex(Vector3(b.x, top_y, b.z))

	# The lines a concave outline will be split along (#1430), on the ground and,
	# while it is raised, across the top too, so the brushes it will make are
	# plain before they are made.
	for cut: Array in _current_split().get("cuts", []):
		var from := Vector3(cut[0].x, _ground_y, cut[0].y)
		var to := Vector3(cut[1].x, _ground_y, cut[1].y)
		var lifts := [0.0] if placing else [0.0, _height]
		for lift: float in lifts:
			_immediate_mesh.surface_set_color(SPLIT_LINE_COLOR)
			_immediate_mesh.surface_add_vertex(from + Vector3(0, lift, 0))
			_immediate_mesh.surface_set_color(SPLIT_LINE_COLOR)
			_immediate_mesh.surface_add_vertex(to + Vector3(0, lift, 0))

	# Vertex markers
	for pt in _polygon_points:
		var s := 0.3
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(-s, 0, 0))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(s, 0, 0))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(0, 0, -s))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(0, 0, s))

	_immediate_mesh.surface_end()
	_update_length_labels()


## Each edge's length at its middle (#1408): the edges placed and, while
## placing, the one to the cursor and the one closing back to the first vertex.
## Once the outline is closed, every edge of it.
func _update_length_labels() -> void:
	var segments: Array = []
	var n := _polygon_points.size()
	for i in range(n - 1):
		segments.append([_polygon_points[i], _polygon_points[i + 1], PLACED_LENGTH_COLOR])
	if _phase == Phase.PLACING_VERTS:
		segments.append([_polygon_points[n - 1], _cursor_pos, LIVE_LENGTH_COLOR])
		if n >= 2:
			segments.append([_cursor_pos, _polygon_points[0], LIVE_LENGTH_COLOR])
	elif n >= 3:
		segments.append([_polygon_points[n - 1], _polygon_points[0], PLACED_LENGTH_COLOR])
	# Nothing to label on an edge with no length, such as the one to the cursor
	# before the mouse has moved off the vertex just placed.
	var labelled: Array = []
	for segment: Array in segments:
		if (segment[0] as Vector3).distance_to(segment[1]) > REPEAT_POINT_EPSILON:
			labelled.append(segment)
	show_segment_lengths(root, _length_labels, labelled, grid_step())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## What a new polygon starts at: what the mapper last built, or the level's own
## default brush height before they have built one.
func _starting_height() -> float:
	if _remembered_height > 0.0:
		return _remembered_height
	if root and "brush_size_default" in root:
		var fallback: float = (root.brush_size_default as Vector3).y
		if fallback > 0.0:
			return fallback
	return 2.0


func _reset() -> void:
	_phase = Phase.IDLE
	_height_pointer_capture = false
	_polygon_points = PackedVector3Array()
	_split_for = PackedVector3Array()
	_split = {}
	_height = _starting_height()
	_cursor_pos = Vector3.ZERO
	_clear_visuals()


func _ensure_mesh() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = make_overlay_mesh(root, "_PolygonToolPreview")
	_immediate_mesh = _mesh_instance.mesh as ImmediateMesh


func _clear_visuals() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		free_overlay_mesh(_mesh_instance)
	_mesh_instance = null
	_immediate_mesh = null
	free_overlay_labels(_length_labels)
