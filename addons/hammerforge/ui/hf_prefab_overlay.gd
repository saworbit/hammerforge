@tool
extends RefCounted
## Visual debug overlay for prefab instances.
##
## When hovering a node that belongs to a prefab instance, draws a
## wireframe bounding box around the entire instance and shows
## override indicators (colored dots) on modified nodes.

var root: Node3D  # LevelRoot
var _overlay_mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _override_markers: Array = []  # MeshInstance3D nodes for override dots
var _active_instance_id: String = ""
var _material: StandardMaterial3D
var _override_material: StandardMaterial3D


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

	# Override indicator material — orange
	_override_material = StandardMaterial3D.new()
	_override_material.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
	_override_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_override_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_override_material.no_depth_test = true


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

	# Draw override markers
	if not rec.overrides.is_empty():
		_draw_override_markers(rec)


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
	for marker in _override_markers:
		if is_instance_valid(marker):
			var mk_parent: Node = marker.get_parent()
			if mk_parent:
				mk_parent.remove_child(marker)
			marker.queue_free()
	_override_markers.clear()


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


func _draw_override_markers(rec) -> void:
	# Show small spheres at nodes that have overrides
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.2
	sphere_mesh.height = 0.4
	sphere_mesh.radial_segments = 8
	sphere_mesh.rings = 4

	var marked_positions: Dictionary = {}

	for field_path in rec.overrides:
		var parts: PackedStringArray = field_path.split("/")
		if parts.size() < 2:
			continue
		var target_type: String = parts[0]
		var idx_str: String = parts[1]
		if not idx_str.is_valid_int():
			continue
		var idx: int = idx_str.to_int()
		var pos := Vector3.ZERO
		var found := false

		var ps = root.get("prefab_system")
		if target_type == "brush" and idx < rec.brush_ids.size():
			if ps:
				var brush = ps._find_brush_by_id(rec.brush_ids[idx])
				if brush and brush is Node3D:
					pos = brush.global_position
					found = true
		elif target_type == "entity" and idx < rec.entity_uids.size():
			if ps:
				var ent = ps._find_entity_by_uid(rec.entity_uids[idx])
				if ent:
					pos = ent.global_position
					found = true

		if found:
			var key := "%s/%d" % [target_type, idx]
			if not marked_positions.has(key):
				marked_positions[key] = pos
				var marker = MeshInstance3D.new()
				marker.name = "PrefabOverrideMarker"
				marker.mesh = sphere_mesh
				marker.material_override = _override_material
				marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(marker)
				marker.global_position = pos + Vector3(0, 0.5, 0)
				_override_markers.append(marker)


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
