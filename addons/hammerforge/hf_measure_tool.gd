@tool
class_name HFMeasureTool
extends "hf_editor_tool.gd"

## Measure distance between two points in the viewport.
## Shift+Click starts a new ruler without clearing existing ones.
## Consecutive rulers that share endpoints show angle between segments.
## Right-click a ruler to set it as a snap reference line.
## Delete/Backspace removes the last ruler. Escape clears all.

const MAX_RULERS := 20
const RULER_COLORS: Array[Color] = [
	Color.YELLOW,
	Color(0.3, 0.85, 1.0),   # cyan
	Color(0.3, 1.0, 0.5),    # green
	Color(1.0, 0.6, 0.3),    # orange
	Color(0.8, 0.5, 1.0),    # purple
	Color(1.0, 0.4, 0.6),    # pink
]

var _measurements: Array = []  # Array of {a: Vector3, b: Vector3}
var _pending_point: Vector3 = Vector3.ZERO
var _has_pending := false
var _mesh_instance: MeshInstance3D = null
var _immediate_mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null
var _labels: Array = []  # Array of Label3D (one per measurement + angles)
var _align_active := false
var _snap_ref_index := -1  # Index of ruler used as snap reference


func tool_name() -> String:
	return "Measure"


func tool_id() -> int:
	return 100


func tool_shortcut_key() -> int:
	return KEY_M


func can_activate(p_root: Node3D) -> bool:
	return p_root != null


func activate(p_root: Node3D, p_camera: Camera3D) -> void:
	super.activate(p_root, p_camera)
	_clear_all()


func deactivate() -> void:
	_remove_snap_reference()
	_clear_visuals()
	super.deactivate()


func handle_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
	if not root or not camera:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventKey and event.pressed:
		return handle_keyboard(event)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			return _handle_left_click(event, camera, mouse_pos)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			return _handle_right_click(camera, mouse_pos)

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func handle_keyboard(event: InputEventKey) -> int:
	if not event.pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	match event.keycode:
		KEY_ESCAPE:
			_clear_all()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_DELETE, KEY_BACKSPACE:
			_remove_last_ruler()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		KEY_A:
			_toggle_align()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func get_shortcut_hud_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("-- Measure Tool --")
	if _measurements.is_empty() and not _has_pending:
		lines.append("Click: Set point A")
	elif _has_pending:
		lines.append("Click: Set point B")
	else:
		var last: Dictionary = _measurements.back()
		var dist = last["a"].distance_to(last["b"])
		var delta = last["b"] - last["a"]
		lines.append("Distance: %.1f" % dist)
		lines.append("dX: %.1f  dY: %.1f  dZ: %.1f" % [abs(delta.x), abs(delta.y), abs(delta.z)])
	lines.append("Rulers: %d / %d" % [_measurements.size(), MAX_RULERS])
	if _align_active and _snap_ref_index >= 0:
		lines.append("Align: ON (ruler #%d)" % (_snap_ref_index + 1))
	else:
		lines.append("A: Toggle align  |  RMB: Set snap ref")
	lines.append("Shift+Click: Chain ruler")
	lines.append("Del: Remove last  |  Esc: Clear all  |  M: Exit")
	return lines


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------


func _handle_left_click(
	event: InputEventMouseButton, camera: Camera3D, mouse_pos: Vector2
) -> int:
	var hit_pos = _raycast_world(camera, mouse_pos)
	if hit_pos == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	hit_pos = _snap_hit(hit_pos)
	var shift_held: bool = event.shift_pressed

	if not _has_pending:
		# Start new measurement
		if shift_held and not _measurements.is_empty():
			# Chain from last point B
			_pending_point = _measurements.back()["b"]
			_has_pending = true
			# Now immediately set point B to this click
			_finish_ruler(hit_pos)
		else:
			_pending_point = hit_pos
			_has_pending = true
			_update_visuals()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Finish current measurement
	_finish_ruler(hit_pos)
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func _handle_right_click(camera: Camera3D, mouse_pos: Vector2) -> int:
	if _measurements.is_empty():
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	# Set nearest ruler as snap reference
	var hit_pos = _raycast_world(camera, mouse_pos)
	if hit_pos == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var best_idx := -1
	var best_dist := 999999.0
	for i in range(_measurements.size()):
		var m: Dictionary = _measurements[i]
		var d: float = _point_line_distance(hit_pos, m["a"], m["b"])
		if d < best_dist:
			best_dist = d
			best_idx = i
	if best_idx >= 0 and best_dist < 5.0:
		_snap_ref_index = best_idx
		_align_active = true
		_apply_snap_reference()
		_update_visuals()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _finish_ruler(point_b: Vector3) -> void:
	if _measurements.size() >= MAX_RULERS:
		_measurements.pop_front()
		# Adjust snap reference index after removing oldest ruler
		if _snap_ref_index == 0:
			# The active snap reference was evicted
			_remove_snap_reference()
		elif _snap_ref_index > 0:
			_snap_ref_index -= 1
			if _align_active:
				_apply_snap_reference()
	_measurements.append({"a": _pending_point, "b": point_b})
	_has_pending = false
	_update_visuals()


func _remove_last_ruler() -> void:
	if _measurements.is_empty():
		return
	if _snap_ref_index >= _measurements.size() - 1:
		_remove_snap_reference()
	_measurements.pop_back()
	_update_visuals()


func _clear_all() -> void:
	_measurements.clear()
	_has_pending = false
	_pending_point = Vector3.ZERO
	_remove_snap_reference()
	_clear_visuals()


func _toggle_align() -> void:
	if _align_active:
		_remove_snap_reference()
		_align_active = false
	elif _snap_ref_index >= 0:
		_align_active = true
		_apply_snap_reference()
	elif not _measurements.is_empty():
		_snap_ref_index = _measurements.size() - 1
		_align_active = true
		_apply_snap_reference()
	_update_visuals()


# ---------------------------------------------------------------------------
# Snap reference
# ---------------------------------------------------------------------------


func _apply_snap_reference() -> void:
	if _snap_ref_index < 0 or _snap_ref_index >= _measurements.size():
		return
	if not root or not root.get("snap_system"):
		return
	var m: Dictionary = _measurements[_snap_ref_index]
	var direction: Vector3 = (m["b"] - m["a"]).normalized()
	if direction.length_squared() < 0.001:
		return
	root.snap_system.set_custom_snap_line(m["a"], direction)


func _remove_snap_reference() -> void:
	_snap_ref_index = -1
	_align_active = false
	if root and root.get("snap_system") and root.snap_system.has_method("clear_custom_snap_line"):
		root.snap_system.clear_custom_snap_line()


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------


func _clear_visuals() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		if _mesh_instance.get_parent():
			_mesh_instance.get_parent().remove_child(_mesh_instance)
		_mesh_instance.queue_free()
		_mesh_instance = null
	for lbl in _labels:
		if lbl and is_instance_valid(lbl):
			if lbl.get_parent():
				lbl.get_parent().remove_child(lbl)
			lbl.queue_free()
	_labels.clear()
	_immediate_mesh = null


func _update_visuals() -> void:
	if not root:
		return
	if _measurements.is_empty() and not _has_pending:
		_clear_visuals()
		return

	_ensure_mesh()
	_immediate_mesh.clear_surfaces()
	# Free old labels
	for lbl in _labels:
		if lbl and is_instance_valid(lbl):
			if lbl.get_parent():
				lbl.get_parent().remove_child(lbl)
			lbl.queue_free()
	_labels.clear()

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Draw pending point cross
	if _has_pending and _measurements.is_empty():
		_draw_cross(_pending_point, 0.5, Color.YELLOW)
	elif _has_pending:
		_draw_cross(_pending_point, 0.5, Color.YELLOW)

	# Draw completed rulers
	for i in range(_measurements.size()):
		var m: Dictionary = _measurements[i]
		var color: Color = _ruler_color(i)
		var is_snap_ref: bool = _align_active and i == _snap_ref_index

		# Brighter if snap reference
		if is_snap_ref:
			color = Color(1.0, 1.0, 1.0, 1.0)

		# Line
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(m["a"])
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(m["b"])

		# Endpoint crosses
		_draw_cross(m["a"], 0.3, Color.WHITE)
		_draw_cross(m["b"], 0.3, Color.WHITE)

		# Distance label
		var midpoint: Vector3 = (m["a"] + m["b"]) * 0.5 + Vector3(0, 0.5, 0)
		var dist: float = m["a"].distance_to(m["b"])
		var delta: Vector3 = m["b"] - m["a"]
		var text := "%.1f\ndX:%.1f dY:%.1f dZ:%.1f" % [
			dist, abs(delta.x), abs(delta.y), abs(delta.z)
		]
		if is_snap_ref:
			text += "\n[SNAP REF]"
		_add_label(midpoint, text, color)

	# Draw angles between consecutive chained rulers
	for i in range(_measurements.size() - 1):
		var m0: Dictionary = _measurements[i]
		var m1: Dictionary = _measurements[i + 1]
		if m0["b"].distance_to(m1["a"]) < 0.01:
			# Shared vertex — compute angle
			var dir_a: Vector3 = (m0["a"] - m0["b"]).normalized()
			var dir_b: Vector3 = (m1["b"] - m1["a"]).normalized()
			if dir_a.length_squared() > 0.001 and dir_b.length_squared() > 0.001:
				var angle_rad: float = dir_a.angle_to(dir_b)
				var angle_deg: float = rad_to_deg(angle_rad)
				var vertex: Vector3 = m0["b"]
				var offset: Vector3 = (dir_a + dir_b).normalized() * 0.8
				if offset.length_squared() < 0.001:
					offset = Vector3(0, 0.5, 0)
				_add_label(
					vertex + offset, "%.1f\u00b0" % angle_deg, Color(1.0, 0.9, 0.4)
				)
				# Draw small angle arc lines
				var arc_color := Color(1.0, 0.9, 0.4, 0.6)
				var arc_radius := 0.6
				_immediate_mesh.surface_set_color(arc_color)
				_immediate_mesh.surface_add_vertex(vertex + dir_a * arc_radius)
				_immediate_mesh.surface_set_color(arc_color)
				_immediate_mesh.surface_add_vertex(
					vertex + (dir_a + dir_b).normalized() * arc_radius
				)
				_immediate_mesh.surface_set_color(arc_color)
				_immediate_mesh.surface_add_vertex(
					vertex + (dir_a + dir_b).normalized() * arc_radius
				)
				_immediate_mesh.surface_set_color(arc_color)
				_immediate_mesh.surface_add_vertex(vertex + dir_b * arc_radius)

	_immediate_mesh.surface_end()


func _draw_cross(pos: Vector3, size: float, color: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(pos - axis * size)
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(pos + axis * size)


func _ruler_color(index: int) -> Color:
	return RULER_COLORS[index % RULER_COLORS.size()]


func _add_label(pos: Vector3, text: String, color: Color) -> void:
	var lbl := Label3D.new()
	lbl.name = "MeasureLabel_%d" % _labels.size()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.pixel_size = 0.005
	lbl.font_size = 24
	lbl.modulate = color
	lbl.outline_modulate = Color.BLACK
	lbl.outline_size = 4
	lbl.text = text
	root.add_child(lbl)
	lbl.global_position = pos
	_labels.append(lbl)


func _ensure_mesh() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "MeasureToolMesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _material:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.no_depth_test = true
	_mesh_instance.material_override = _material
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _immediate_mesh
	root.add_child(_mesh_instance)


# ---------------------------------------------------------------------------
# Raycasting & geometry helpers
# ---------------------------------------------------------------------------


func _raycast_world(camera: Camera3D, mouse_pos: Vector2) -> Variant:
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	if not root:
		return null
	var space_state = root.get_world_3d().direct_space_state if root.get_world_3d() else null
	if space_state:
		var query = PhysicsRayQueryParameters3D.new()
		query.from = ray_origin
		query.to = ray_origin + ray_dir * 10000.0
		var result = space_state.intersect_ray(query)
		if not result.is_empty():
			return result.position
	# Fallback: intersect Y=0 plane
	var denom = ray_dir.y
	if abs(denom) < 0.0001:
		return null
	var t = -ray_origin.y / denom
	if t < 0.0:
		return null
	return ray_origin + ray_dir * t


func _snap_hit(hit_pos: Vector3) -> Vector3:
	if root.has_method("_snap_point"):
		return root._snap_point(hit_pos)
	elif root.get("snap_system"):
		return root.snap_system.snap_point(hit_pos)
	return hit_pos


func _point_line_distance(point: Vector3, line_a: Vector3, line_b: Vector3) -> float:
	var ab: Vector3 = line_b - line_a
	var ap: Vector3 = point - line_a
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq < 0.0001:
		return ap.length()
	var t: float = clampf(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest: Vector3 = line_a + ab * t
	return point.distance_to(closest)
