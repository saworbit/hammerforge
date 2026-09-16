@tool
extends RefCounted
## Visual debug overlay for prefab instances.
##
## When hovering a node that belongs to a prefab instance, draws a
## wireframe bounding box around the entire instance.

var root: Node3D  # LevelRoot
var _overlay_mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _active_instance_id: String = ""
var _material: StandardMaterial3D


func _init(level_root: Node3D) -> void:
	root = level_root
	_setup_materials()


func _setup_materials() -> void:
	# Ghost outline material — cyan wireframe
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.3, 0.8, 1.0, 0.5)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true


## Show the ghost overlay for a prefab instance.
## Called when hovering over a node that belongs to a prefab.
func show_instance_overlay(instance_id: String) -> void:
	if instance_id == _active_instance_id:
		return
	hide_overlay()
	_active_instance_id = instance_id

	if not root or not root.has_method("get_node_or_null"):
		return
	var prefab_system = root.get("prefab_system")
	if not prefab_system:
		return
	var rec = prefab_system.get_instance(instance_id)
	if not rec:
		return

	# Compute AABB from all nodes in the instance
	var aabb := AABB()
	var first := true

	for bid in rec.brush_ids:
		var brush = prefab_system._find_brush_by_id(bid)
		if brush and brush is Node3D:
			var node_aabb := _get_node_aabb(brush)
			if first:
				aabb = node_aabb
				first = false
			else:
				aabb = aabb.merge(node_aabb)

	for uid in rec.entity_uids:
		var ent = prefab_system._find_entity_by_uid(uid)
		if ent and ent is Node3D:
			var node_aabb := AABB(ent.global_position - Vector3.ONE * 0.5, Vector3.ONE)
			if first:
				aabb = node_aabb
				first = false
			else:
				aabb = aabb.merge(node_aabb)

	if first:
		return  # no nodes found

	# Expand slightly for visibility
	aabb = aabb.grow(0.15)

	# Create wireframe box
	_draw_wireframe_box(aabb)


## Hide the overlay.
func hide_overlay() -> void:
	_active_instance_id = ""
	if _overlay_mesh_instance and is_instance_valid(_overlay_mesh_instance):
		var mi_parent: Node = _overlay_mesh_instance.get_parent()
		if mi_parent:
			mi_parent.remove_child(_overlay_mesh_instance)
		_overlay_mesh_instance.queue_free()
	_overlay_mesh_instance = null
	_immediate_mesh = null


func get_active_instance_id() -> String:
	return _active_instance_id


func _draw_wireframe_box(aabb: AABB) -> void:
	_immediate_mesh = ImmediateMesh.new()
	var im := _immediate_mesh
	var min_pt := aabb.position
	var max_pt := aabb.position + aabb.size
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners = [
		Vector3(min_pt.x, min_pt.y, min_pt.z),
		Vector3(max_pt.x, min_pt.y, min_pt.z),
		Vector3(max_pt.x, max_pt.y, min_pt.z),
		Vector3(min_pt.x, max_pt.y, min_pt.z),
		Vector3(min_pt.x, min_pt.y, max_pt.z),
		Vector3(max_pt.x, min_pt.y, max_pt.z),
		Vector3(max_pt.x, max_pt.y, max_pt.z),
		Vector3(min_pt.x, max_pt.y, max_pt.z),
	]
	var edges = [
		[0, 1],
		[1, 2],
		[2, 3],
		[3, 0],
		[4, 5],
		[5, 6],
		[6, 7],
		[7, 4],
		[0, 4],
		[1, 5],
		[2, 6],
		[3, 7],
	]
	for edge in edges:
		im.surface_add_vertex(corners[edge[0]])
		im.surface_add_vertex(corners[edge[1]])
	im.surface_end()

	_overlay_mesh_instance = MeshInstance3D.new()
	_overlay_mesh_instance.name = "PrefabGhostOverlay"
	_overlay_mesh_instance.mesh = im
	_overlay_mesh_instance.material_override = _material
	_overlay_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_overlay_mesh_instance)
	# The box corners are world coordinates and this hangs off the LevelRoot, so it
	# has to be pinned to world space.
	_overlay_mesh_instance.global_transform = Transform3D.IDENTITY


func _get_node_aabb(node: Node3D) -> AABB:
	# Try to get the CSG shape's AABB
	if node is CSGShape3D:
		var meshes: Array = node.get_meshes()
		if not meshes.is_empty():
			for i in range(0, meshes.size(), 2):
				if meshes[i + 1] is Mesh:
					var mesh_aabb: AABB = meshes[i + 1].get_aabb()
					var t: Transform3D = (
						meshes[i] if meshes[i] is Transform3D else node.global_transform
					)
					return t * mesh_aabb

	# Fallback: use brush_size meta or default
	var size: Vector3 = node.get_meta("brush_size", Vector3(32, 32, 32))
	var half := size * 0.5
	return AABB(node.global_position - half, size)
