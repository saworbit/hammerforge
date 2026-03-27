@tool
extends RefCounted
class_name HFIOVisualizer

## Draws ImmediateMesh lines between entities with I/O connections.
## Green = standard, orange = fire_once, bright yellow = selected entity's connections.

var root: Node3D
var _mesh_instance: MeshInstance3D = null
var _immediate_mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null
var enabled: bool = false
var _frame_counter: int = 0
const REFRESH_INTERVAL := 10  # Update every N frames


func _init(level_root: Node3D) -> void:
	root = level_root


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled and _mesh_instance:
		_mesh_instance.visible = false
	if enabled:
		refresh()


func process() -> void:
	if not enabled:
		return
	_frame_counter += 1
	if _frame_counter >= REFRESH_INTERVAL:
		_frame_counter = 0
		refresh()


func refresh() -> void:
	if not root or not enabled:
		return
	_ensure_mesh_instance()
	if not _immediate_mesh:
		return
	_immediate_mesh.clear_surfaces()
	if not root.entity_system:
		return
	var connections = root.entity_system.get_all_connections()
	if connections.is_empty():
		_mesh_instance.visible = false
		return
	_mesh_instance.visible = true
	# Determine which entity (if any) is selected
	var selected_names: Dictionary = {}
	if root.has_method("get_selected_entities"):
		var sel = root.get_selected_entities()
		for e in sel:
			if e is Node:
				selected_names[e.name] = true
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for conn in connections:
		if not (conn is Dictionary):
			continue
		var source: Node3D = conn.get("source", null)
		if not source or not is_instance_valid(source):
			continue
		var target_name = str(conn.get("target_name", ""))
		if target_name == "":
			continue
		var targets = root.entity_system.find_entities_by_name(target_name)
		if targets.is_empty():
			continue
		var fire_once = bool(conn.get("fire_once", false))
		var source_name = str(conn.get("source_name", ""))
		var is_selected = selected_names.has(source_name) or selected_names.has(target_name)
		# Pick color
		var color: Color
		if is_selected:
			color = Color(1.0, 1.0, 0.2, 0.9)  # Bright yellow
		elif fire_once:
			color = Color(1.0, 0.5, 0.0, 0.7)  # Orange
		else:
			color = Color(0.2, 1.0, 0.3, 0.7)  # Green
		for target in targets:
			if not (target is Node3D) or not is_instance_valid(target):
				continue
			var start_pos = source.global_position + Vector3(0, 0.3, 0)
			var end_pos = target.global_position + Vector3(0, 0.3, 0)
			_immediate_mesh.surface_set_color(color)
			_immediate_mesh.surface_add_vertex(start_pos)
			_immediate_mesh.surface_set_color(color)
			_immediate_mesh.surface_add_vertex(end_pos)
	_immediate_mesh.surface_end()


func _ensure_mesh_instance() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "IOVisualizerMesh"
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


func cleanup() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		_mesh_instance.get_parent().remove_child(_mesh_instance)
		_mesh_instance.queue_free()
		_mesh_instance = null
	_immediate_mesh = null
