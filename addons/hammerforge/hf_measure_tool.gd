@tool
class_name HFMeasureTool
extends "hf_editor_tool.gd"

## Measure distance between two points in the viewport.
## Click point A, click point B — displays a persistent line with distance label.
## Escape clears the measurement. Not serialized (transient overlay).

var _point_a: Vector3 = Vector3.ZERO
var _point_b: Vector3 = Vector3.ZERO
var _has_point_a := false
var _has_point_b := false
var _mesh_instance: MeshInstance3D = null
var _label_3d: Label3D = null
var _immediate_mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null


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
	_clear_measurement()


func deactivate() -> void:
	_clear_visuals()
	super.deactivate()


func handle_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
	if not root or not camera:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_clear_measurement()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit_pos = _raycast_world(camera, mouse_pos)
		if hit_pos == null:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if root.has_method("_snap_point"):
			hit_pos = root._snap_point(hit_pos)
		elif root.get("snap_system"):
			hit_pos = root.snap_system.snap_point(hit_pos)
		if not _has_point_a:
			_point_a = hit_pos
			_has_point_a = true
			_update_visuals()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		_point_b = hit_pos
		_has_point_b = true
		_update_visuals()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func handle_keyboard(event: InputEventKey) -> int:
	if event.pressed and event.keycode == KEY_ESCAPE:
		_clear_measurement()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func get_shortcut_hud_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("-- Measure Tool --")
	if not _has_point_a:
		lines.append("Click: Set point A")
	elif not _has_point_b:
		lines.append("Click: Set point B")
	else:
		var dist = _point_a.distance_to(_point_b)
		var delta = _point_b - _point_a
		lines.append("Distance: %.1f" % dist)
		lines.append("dX: %.1f  dY: %.1f  dZ: %.1f" % [abs(delta.x), abs(delta.y), abs(delta.z)])
	lines.append("Esc: Clear / M: Exit")
	return lines


func _raycast_world(camera: Camera3D, mouse_pos: Vector2) -> Variant:
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	if not root:
		return null
	# Try physics raycast first
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


func _clear_measurement() -> void:
	_has_point_a = false
	_has_point_b = false
	_point_a = Vector3.ZERO
	_point_b = Vector3.ZERO
	_clear_visuals()


func _clear_visuals() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		if _mesh_instance.get_parent():
			_mesh_instance.get_parent().remove_child(_mesh_instance)
		_mesh_instance.queue_free()
		_mesh_instance = null
	if _label_3d and is_instance_valid(_label_3d):
		if _label_3d.get_parent():
			_label_3d.get_parent().remove_child(_label_3d)
		_label_3d.queue_free()
		_label_3d = null
	_immediate_mesh = null


func _update_visuals() -> void:
	if not root:
		return
	if not _has_point_a:
		_clear_visuals()
		return
	_ensure_mesh()
	_immediate_mesh.clear_surfaces()
	if _has_point_a and not _has_point_b:
		# Show just point A as a small cross
		_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var s := 0.5
		_immediate_mesh.surface_set_color(Color.YELLOW)
		_immediate_mesh.surface_add_vertex(_point_a + Vector3(-s, 0, 0))
		_immediate_mesh.surface_set_color(Color.YELLOW)
		_immediate_mesh.surface_add_vertex(_point_a + Vector3(s, 0, 0))
		_immediate_mesh.surface_set_color(Color.YELLOW)
		_immediate_mesh.surface_add_vertex(_point_a + Vector3(0, -s, 0))
		_immediate_mesh.surface_set_color(Color.YELLOW)
		_immediate_mesh.surface_add_vertex(_point_a + Vector3(0, s, 0))
		_immediate_mesh.surface_set_color(Color.YELLOW)
		_immediate_mesh.surface_add_vertex(_point_a + Vector3(0, 0, -s))
		_immediate_mesh.surface_set_color(Color.YELLOW)
		_immediate_mesh.surface_add_vertex(_point_a + Vector3(0, 0, s))
		_immediate_mesh.surface_end()
		if _label_3d and is_instance_valid(_label_3d):
			_label_3d.visible = false
		return
	# Draw line from A to B
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_immediate_mesh.surface_set_color(Color.YELLOW)
	_immediate_mesh.surface_add_vertex(_point_a)
	_immediate_mesh.surface_set_color(Color.YELLOW)
	_immediate_mesh.surface_add_vertex(_point_b)
	# Endpoint crosses
	for pt in [_point_a, _point_b]:
		var s := 0.3
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(-s, 0, 0))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(s, 0, 0))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(0, -s, 0))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(0, s, 0))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(0, 0, -s))
		_immediate_mesh.surface_set_color(Color.WHITE)
		_immediate_mesh.surface_add_vertex(pt + Vector3(0, 0, s))
	_immediate_mesh.surface_end()
	# Update label
	_ensure_label()
	var midpoint = (_point_a + _point_b) * 0.5 + Vector3(0, 0.5, 0)
	_label_3d.global_position = midpoint
	var dist = _point_a.distance_to(_point_b)
	var delta = _point_b - _point_a
	_label_3d.text = (
		"%.1f\ndX:%.1f dY:%.1f dZ:%.1f" % [dist, abs(delta.x), abs(delta.y), abs(delta.z)]
	)
	_label_3d.visible = true


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


func _ensure_label() -> void:
	if _label_3d and is_instance_valid(_label_3d):
		return
	_label_3d = Label3D.new()
	_label_3d.name = "MeasureToolLabel"
	_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_3d.no_depth_test = true
	_label_3d.pixel_size = 0.005
	_label_3d.font_size = 24
	_label_3d.modulate = Color.YELLOW
	_label_3d.outline_modulate = Color.BLACK
	_label_3d.outline_size = 4
	root.add_child(_label_3d)
