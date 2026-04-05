@tool
class_name HFPolygonTool
extends "hf_editor_tool.gd"

## Draw a convex polygon on the ground plane, then extrude to height to create a brush.
## Click to place vertices, Enter/close-click to finish polygon, then drag height.

const FaceData = preload("res://addons/hammerforge/face_data.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

enum Phase { IDLE, PLACING_VERTS, SETTING_HEIGHT }

var _phase: int = Phase.IDLE
var _polygon_points: PackedVector3Array = PackedVector3Array()
var _ground_y: float = 0.0
var _height: float = 32.0
var _height_start_mouse: Vector2 = Vector2.ZERO
var _height_start_value: float = 32.0
var _cursor_pos: Vector3 = Vector3.ZERO  # Current mouse world pos for preview
var _mesh_instance: MeshInstance3D = null
var _immediate_mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null
const HEIGHT_SENSITIVITY := 0.5


func tool_name() -> String:
	return "Polygon"


func tool_id() -> int:
	return 102


func tool_shortcut_key() -> int:
	return KEY_P


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
			return _handle_click(camera, mouse_pos)
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
		if _phase == Phase.PLACING_VERTS:
			_cursor_pos = _raycast_to_y_plane(camera, mouse_pos, _ground_y)
			_cursor_pos = _snap(_cursor_pos)
			_update_preview()
		elif _phase == Phase.SETTING_HEIGHT:
			var delta_y := (mouse_pos.y - _height_start_mouse.y) * -HEIGHT_SENSITIVITY
			_height = _height_start_value + delta_y
			if root.get("grid_snap") and root.grid_snap > 0.0:
				_height = snappedf(_height, root.grid_snap)
			if absf(_height) < 0.1:
				_height = 0.1
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


func get_shortcut_hud_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("-- Polygon Tool --")
	match _phase:
		Phase.IDLE:
			lines.append("Click: Start polygon")
		Phase.PLACING_VERTS:
			lines.append("Click: Place vertex (%d placed)" % _polygon_points.size())
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


func _handle_click(camera: Camera3D, mouse_pos: Vector2) -> int:
	match _phase:
		Phase.IDLE:
			var world_pos := _raycast_ground(camera, mouse_pos)
			if world_pos == null:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_ground_y = world_pos.y
			var snapped: Vector3 = _snap(world_pos)
			_ground_y = snapped.y
			_polygon_points.append(snapped)
			_phase = Phase.PLACING_VERTS
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		Phase.PLACING_VERTS:
			var hit := _raycast_to_y_plane(camera, mouse_pos, _ground_y)
			hit = _snap(hit)
			# Check auto-close
			var threshold: float = get_setting("auto_close_threshold")
			if _polygon_points.size() >= 3:
				var first: Vector3 = _polygon_points[0]
				if hit.distance_to(first) <= threshold:
					_begin_height_stage(mouse_pos)
					return EditorPlugin.AFTER_GUI_INPUT_STOP
			# Validate convexity
			if not _validate_convex(_polygon_points, hit):
				return EditorPlugin.AFTER_GUI_INPUT_STOP  # Reject concave point
			_polygon_points.append(hit)
			_update_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		Phase.SETTING_HEIGHT:
			_finalize_brush()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_enter(camera: Camera3D, mouse_pos: Vector2) -> int:
	if _phase == Phase.PLACING_VERTS and _polygon_points.size() >= 3:
		_begin_height_stage(mouse_pos)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _phase == Phase.SETTING_HEIGHT:
		_finalize_brush()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_escape() -> int:
	if _phase == Phase.SETTING_HEIGHT:
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


func _begin_height_stage(mouse_pos: Vector2) -> void:
	_phase = Phase.SETTING_HEIGHT
	_height_start_mouse = mouse_pos
	_height = 32.0
	_height_start_value = _height
	_update_preview()


func _validate_convex(existing: PackedVector3Array, new_pt: Vector3) -> bool:
	if existing.size() < 2:
		return true
	# Build temporary polygon with the new point
	var pts := PackedVector3Array(existing)
	pts.append(new_pt)
	return _is_convex_xz(pts)


static func _is_convex_xz(pts: PackedVector3Array) -> bool:
	var n := pts.size()
	if n < 3:
		return true
	var sign := 0.0
	for i in range(n):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % n]
		var c: Vector3 = pts[(i + 2) % n]
		var cross := (b.x - a.x) * (c.z - b.z) - (b.z - a.z) * (c.x - b.x)
		if absf(cross) < 0.001:
			continue
		if sign == 0.0:
			sign = cross
		elif (cross > 0.0) != (sign > 0.0):
			return false
	return true


func _build_face_data() -> Array:
	var n := _polygon_points.size()
	if n < 3:
		return []
	# Compute center for local space
	var center := Vector3.ZERO
	for pt in _polygon_points:
		center += pt
	center /= float(n)
	center.y = _ground_y + _height * 0.5

	var faces: Array = []
	var bot_y := _ground_y - center.y
	var top_y := _ground_y + _height - center.y

	# Ensure consistent winding — compute winding direction
	var winding := 0.0
	for i in range(n):
		var a: Vector3 = _polygon_points[i]
		var b: Vector3 = _polygon_points[(i + 1) % n]
		winding += (b.x - a.x) * (b.z + a.z)
	var ccw := winding < 0.0  # CCW in XZ when viewed from +Y

	# Convert to local XZ
	var local_xz: Array = []
	for pt in _polygon_points:
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


func _finalize_brush() -> void:
	if _polygon_points.size() < 3:
		_reset()
		return
	var face_dicts := _build_face_data()
	if face_dicts.is_empty():
		_reset()
		return
	# Compute center and AABB size
	var center := Vector3.ZERO
	for pt in _polygon_points:
		center += pt
	center /= float(_polygon_points.size())
	center.y = _ground_y + _height * 0.5

	var min_pt := Vector3(INF, _ground_y, INF)
	var max_pt := Vector3(-INF, _ground_y + _height, -INF)
	for pt in _polygon_points:
		min_pt.x = minf(min_pt.x, pt.x)
		min_pt.z = minf(min_pt.z, pt.z)
		max_pt.x = maxf(max_pt.x, pt.x)
		max_pt.z = maxf(max_pt.z, pt.z)
	var aabb_size := max_pt - min_pt

	var info := {
		"shape": LevelRootType.BrushShape.CUSTOM,
		"size": aabb_size,
		"sides": _polygon_points.size(),
		"operation": CSGShape3D.OPERATION_UNION,
		"center": center,
		"faces": face_dicts,
	}

	if root and root.get("brush_system") and root.brush_system.has_method("create_brush_from_info"):
		# Capture full state before creation for undo
		var pre_state: Dictionary = {}
		if root.get("state_system") and root.state_system.has_method("capture_state"):
			pre_state = root.state_system.capture_state(true)

		root.brush_system.create_brush_from_info(info)

		if undo_redo and not pre_state.is_empty():
			var post_state: Dictionary = root.state_system.capture_state(true)
			undo_redo.create_action("Create Polygon Brush", 0, null, false)
			undo_redo.add_do_method(root.state_system, "restore_state", post_state)
			undo_redo.add_undo_method(root.state_system, "restore_state", pre_state)
			undo_redo.commit_action(false)
		if history_callback.is_valid():
			history_callback.call("Create Polygon Brush")
	_reset()


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
		return

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Draw placed polygon outline
	var n := _polygon_points.size()
	for i in range(n):
		var a: Vector3 = _polygon_points[i]
		var b: Vector3 = _polygon_points[(i + 1) % n] if i < n - 1 else _cursor_pos
		_immediate_mesh.surface_set_color(Color.CYAN)
		_immediate_mesh.surface_add_vertex(a)
		_immediate_mesh.surface_set_color(Color.CYAN)
		_immediate_mesh.surface_add_vertex(b)

	# Draw closing line to cursor or first point
	if _phase == Phase.PLACING_VERTS and n >= 2:
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


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _reset() -> void:
	_phase = Phase.IDLE
	_polygon_points = PackedVector3Array()
	_height = 32.0
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
	# Try physics raycast
	if root:
		var space_state = root.get_world_3d().direct_space_state if root.get_world_3d() else null
		if space_state:
			var query := PhysicsRayQueryParameters3D.new()
			query.from = ray_origin
			query.to = ray_origin + ray_dir * 10000.0
			var result := space_state.intersect_ray(query)
			if not result.is_empty():
				return result.position
	# Fallback: Y=0 plane
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
	_mesh_instance.name = "_PolygonToolPreview"
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
		if _mesh_instance.get_parent():
			_mesh_instance.get_parent().remove_child(_mesh_instance)
		_mesh_instance.queue_free()
		_mesh_instance = null
	_immediate_mesh = null
