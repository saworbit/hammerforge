@tool
class_name HFPathTool
extends "hf_editor_tool.gd"

## Draw a path of connected line segments, then extrude a rectangular
## cross-section along it to create corridor/walkway brushes.
## Each segment becomes an independent brush, all auto-grouped.

const FaceData = preload("res://addons/hammerforge/face_data.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

enum Phase { IDLE, PLACING_WAYPOINTS }

var _phase: int = Phase.IDLE
var _waypoints: PackedVector3Array = PackedVector3Array()
var _ground_y: float = 0.0
var _cursor_pos: Vector3 = Vector3.ZERO
var _mesh_instance: MeshInstance3D = null
var _immediate_mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null


func tool_name() -> String:
	return "Path"


func tool_id() -> int:
	return 103


func tool_shortcut_key() -> int:
	return KEY_SEMICOLON


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
			"name": "miter_joints",
			"type": "bool",
			"label": "Miter Joints",
			"default": true,
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
		return _handle_click(camera, mouse_pos)

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
			_cursor_pos = _raycast_to_y_plane(camera, mouse_pos, _ground_y)
			_cursor_pos = _snap(_cursor_pos)
			_update_preview()

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func handle_keyboard(event: InputEventKey) -> int:
	if event.pressed:
		if event.keycode == KEY_ESCAPE:
			return _handle_escape()
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			return _handle_enter()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


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
			lines.append("Enter: Build path")
			lines.append("Esc/RMB: Undo point")
	lines.append("Width: %.1f  Height: %.1f" % [w, h])
	lines.append(";: Exit tool")
	return lines


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------


func _handle_click(camera: Camera3D, mouse_pos: Vector2) -> int:
	match _phase:
		Phase.IDLE:
			var world_pos = _raycast_ground(camera, mouse_pos)
			if world_pos == null:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			var snapped: Vector3 = _snap(world_pos)
			_ground_y = snapped.y
			_waypoints.append(snapped)
			_phase = Phase.PLACING_WAYPOINTS
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		Phase.PLACING_WAYPOINTS:
			var hit := _raycast_to_y_plane(camera, mouse_pos, _ground_y)
			hit = _snap(hit)
			_waypoints.append(hit)
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


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


func _build_path() -> void:
	if _waypoints.size() < 2:
		_reset()
		return

	var path_width: float = get_setting("path_width")
	var path_height: float = get_setting("path_height")
	var use_miter: bool = get_setting("miter_joints")
	var group_id := "path_%d" % Time.get_ticks_usec()
	# Resolve CUSTOM shape from the preloaded LevelRoot script — no runtime fallback needed.
	var custom_shape: int = LevelRootType.BrushShape.CUSTOM

	var brush_infos: Array = []

	# Build segment brushes
	for i in range(_waypoints.size() - 1):
		var a: Vector3 = _waypoints[i]
		var b: Vector3 = _waypoints[i + 1]
		var info := _build_segment_brush(a, b, path_width, path_height, group_id)
		if not info.is_empty():
			info["shape"] = custom_shape
			brush_infos.append(info)

	# Build miter joint brushes
	if use_miter and _waypoints.size() >= 3:
		for i in range(1, _waypoints.size() - 1):
			var prev: Vector3 = _waypoints[i - 1]
			var curr: Vector3 = _waypoints[i]
			var next: Vector3 = _waypoints[i + 1]
			var miter := _build_miter_brush(prev, curr, next, path_width, path_height, group_id)
			if not miter.is_empty():
				miter["shape"] = custom_shape
				brush_infos.append(miter)

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
			root.brush_system.create_brush_from_info(info)

		var action_name := "Create Path (%d segments)" % brush_infos.size()
		if undo_redo and not pre_state.is_empty():
			var post_state: Dictionary = root.state_system.capture_state(true)
			undo_redo.create_action(action_name, 0, null, false)
			undo_redo.add_do_method(root.state_system, "restore_state", post_state)
			undo_redo.add_undo_method(root.state_system, "restore_state", pre_state)
			undo_redo.commit_action(false)
		if history_callback.is_valid():
			history_callback.call(action_name)

	_reset()


func _build_segment_brush(
	a: Vector3, b: Vector3, width: float, height: float, group_id: String
) -> Dictionary:
	var dir := b - a
	dir.y = 0.0
	var length := dir.length()
	if length < 0.01:
		return {}
	dir = dir.normalized()
	# Perpendicular in XZ plane
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var half_w := width * 0.5
	var half_h := height * 0.5
	var center := (a + b) * 0.5
	center.y = _ground_y + half_h

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
	# Build 6 quads
	var quads := [
		# Front (+length dir): 1, 3, 7, 5
		[corners[1], corners[3], corners[7], corners[5]],
		# Back (-length dir): 2, 0, 4, 6
		[corners[2], corners[0], corners[4], corners[6]],
		# Right (+perp): 3, 2, 6, 7
		[corners[3], corners[2], corners[6], corners[7]],
		# Left (-perp): 0, 1, 5, 4
		[corners[0], corners[1], corners[5], corners[4]],
		# Top: 4, 5, 7, 6
		[corners[4], corners[5], corners[7], corners[6]],
		# Bottom: 0, 2, 3, 1
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


func _build_miter_brush(
	prev: Vector3, curr: Vector3, next: Vector3, width: float, height: float, group_id: String
) -> Dictionary:
	# Compute directions
	var dir_in := curr - prev
	dir_in.y = 0.0
	if dir_in.length() < 0.01:
		return {}
	dir_in = dir_in.normalized()

	var dir_out := next - curr
	dir_out.y = 0.0
	if dir_out.length() < 0.01:
		return {}
	dir_out = dir_out.normalized()

	# Check angle — skip miter for nearly straight or too-acute angles
	var dot := dir_in.dot(dir_out)
	if dot > 0.98 or dot < -0.5:  # Nearly straight or too acute
		return {}

	var half_w := width * 0.5
	var half_h := height * 0.5

	# Perpendiculars
	var perp_in := Vector3(-dir_in.z, 0.0, dir_in.x)
	var perp_out := Vector3(-dir_out.z, 0.0, dir_out.x)

	# The miter fills the triangular gap between the two segment ends.
	# Build a wedge from the 4 corner points at the joint.
	var center := curr
	center.y = _ground_y + half_h

	# Corners of the incoming segment end face (at curr)
	var in_left := curr + perp_in * half_w - center
	var in_right := curr - perp_in * half_w - center
	# Corners of the outgoing segment start face (at curr)
	var out_left := curr + perp_out * half_w - center
	var out_right := curr - perp_out * half_w - center

	# Build a convex shape from these 4 XZ points extruded vertically.
	# Some may overlap — collect unique points only
	var xz_pts := PackedVector3Array()
	xz_pts.append(in_left)
	xz_pts.append(in_right)
	# Only add out points if distinct from in points
	if out_right.distance_to(in_right) > 0.01:
		xz_pts.append(out_right)
	if out_left.distance_to(in_left) > 0.01:
		xz_pts.append(out_left)

	if xz_pts.size() < 3:
		return {}

	# Sort points by angle around centroid for convex hull
	var cx := Vector3.ZERO
	for p in xz_pts:
		cx += p
	cx /= float(xz_pts.size())

	var sorted_indices: Array = []
	for i in range(xz_pts.size()):
		sorted_indices.append(i)
	sorted_indices.sort_custom(
		func(a_idx: int, b_idx: int) -> bool:
			var aa := atan2(xz_pts[a_idx].z - cx.z, xz_pts[a_idx].x - cx.x)
			var bb := atan2(xz_pts[b_idx].z - cx.z, xz_pts[b_idx].x - cx.x)
			return aa < bb
	)

	var sorted_pts := PackedVector3Array()
	for idx in sorted_indices:
		sorted_pts.append(xz_pts[idx])

	var n := sorted_pts.size()
	var faces: Array = []

	# Top face
	var top_face := FaceData.new()
	var top_verts := PackedVector3Array()
	for i in range(n):
		top_verts.append(Vector3(sorted_pts[i].x, half_h, sorted_pts[i].z))
	top_face.local_verts = top_verts
	top_face.ensure_geometry()
	faces.append(top_face.to_dict())

	# Bottom face (reverse winding)
	var bot_face := FaceData.new()
	var bot_verts := PackedVector3Array()
	for i in range(n - 1, -1, -1):
		bot_verts.append(Vector3(sorted_pts[i].x, -half_h, sorted_pts[i].z))
	bot_face.local_verts = bot_verts
	bot_face.ensure_geometry()
	faces.append(bot_face.to_dict())

	# Side faces
	for i in range(n):
		var j := (i + 1) % n
		var side := FaceData.new()
		var sv := PackedVector3Array()
		sv.append(Vector3(sorted_pts[j].x, -half_h, sorted_pts[j].z))
		sv.append(Vector3(sorted_pts[j].x, half_h, sorted_pts[j].z))
		sv.append(Vector3(sorted_pts[i].x, half_h, sorted_pts[i].z))
		sv.append(Vector3(sorted_pts[i].x, -half_h, sorted_pts[i].z))
		side.local_verts = sv
		side.ensure_geometry()
		faces.append(side.to_dict())

	# Compute AABB for size
	var min_pt := Vector3(INF, -half_h, INF)
	var max_pt := Vector3(-INF, half_h, -INF)
	for p in sorted_pts:
		min_pt.x = minf(min_pt.x, p.x)
		min_pt.z = minf(min_pt.z, p.z)
		max_pt.x = maxf(max_pt.x, p.x)
		max_pt.z = maxf(max_pt.z, p.z)

	return {
		"shape": 0,  # Overwritten by _build_path() with BrushShape.CUSTOM — miter joint with custom face data
		"size": Vector3(max_pt.x - min_pt.x, height, max_pt.z - min_pt.z),
		"operation": CSGShape3D.OPERATION_UNION,
		"center": center,
		"faces": faces,
		"group_id": group_id,
	}


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

	# Draw width lines along each segment
	for i in range(n - 1):
		var a: Vector3 = _waypoints[i]
		var b: Vector3 = _waypoints[i + 1]
		var dir := b - a
		dir.y = 0.0
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var perp := Vector3(-dir.z, 0.0, dir.x) * pw * 0.5
		# Left edge
		_immediate_mesh.surface_set_color(Color(0.0, 0.8, 0.8, 0.3))
		_immediate_mesh.surface_add_vertex(a + perp)
		_immediate_mesh.surface_set_color(Color(0.0, 0.8, 0.8, 0.3))
		_immediate_mesh.surface_add_vertex(b + perp)
		# Right edge
		_immediate_mesh.surface_set_color(Color(0.0, 0.8, 0.8, 0.3))
		_immediate_mesh.surface_add_vertex(a - perp)
		_immediate_mesh.surface_set_color(Color(0.0, 0.8, 0.8, 0.3))
		_immediate_mesh.surface_add_vertex(b - perp)

	# Waypoint markers
	for pt in _waypoints:
		var s := 0.4
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(-s, 0, 0))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(s, 0, 0))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(0, 0, -s))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(0, 0, s))

	# Perpendicular ticks at waypoints
	for i in range(n):
		var dir := Vector3.FORWARD
		if i < n - 1:
			dir = (_waypoints[i + 1] - _waypoints[i]).normalized()
		elif i > 0:
			dir = (_waypoints[i] - _waypoints[i - 1]).normalized()
		dir.y = 0.0
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var perp := Vector3(-dir.z, 0.0, dir.x) * pw * 0.5
		_immediate_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.3))
		_immediate_mesh.surface_add_vertex(_waypoints[i] + perp)
		_immediate_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.3))
		_immediate_mesh.surface_add_vertex(_waypoints[i] - perp)

	_immediate_mesh.surface_end()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _reset() -> void:
	_phase = Phase.IDLE
	_waypoints = PackedVector3Array()
	_cursor_pos = Vector3.ZERO
	_clear_visuals()


func _snap(pos: Vector3) -> Vector3:
	if root and root.get("snap_system"):
		return root.snap_system.snap_point(pos)
	if root and root.get("grid_snap") and root.grid_snap > 0.0:
		var g: float = root.grid_snap
		return Vector3(snappedf(pos.x, g), snappedf(pos.y, g), snappedf(pos.z, g))
	return pos


func _raycast_ground(camera: Camera3D, mouse_pos: Vector2) -> Variant:
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	if root:
		var space_state = root.get_world_3d().direct_space_state if root.get_world_3d() else null
		if space_state:
			var query := PhysicsRayQueryParameters3D.new()
			query.from = ray_origin
			query.to = ray_origin + ray_dir * 10000.0
			var result := space_state.intersect_ray(query)
			if not result.is_empty():
				return result.position
	return _raycast_to_y_plane(camera, mouse_pos, 0.0)


func _raycast_to_y_plane(camera: Camera3D, mouse_pos: Vector2, y: float) -> Vector3:
	var origin := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.0001:
		return Vector3(origin.x, y, origin.z)
	var t := (y - origin.y) / dir.y
	if t < 0.0:
		t = 0.0
	return origin + dir * t


func _ensure_mesh() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "_PathToolPreview"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _material:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.no_depth_test = true
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance.material_override = _material
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _immediate_mesh
	root.add_child(_mesh_instance)


func _clear_visuals() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		_mesh_instance.get_parent().remove_child(_mesh_instance)
		_mesh_instance.queue_free()
		_mesh_instance = null
	_immediate_mesh = null
