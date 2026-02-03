@tool
extends Node
class_name Baker

const DEFAULT_UV2_TEXEL_SIZE := 0.1

func bake_from_csg(
	csg_node: CSGCombiner3D,
	material_override: Material = null,
	collision_layer: int = 1,
	collision_mask: int = 1,
	options: Dictionary = {}
) -> Node3D:
	if not csg_node:
		return null

	var entries = csg_node.get_meshes()
	if entries.is_empty():
		return null

	var merge_meshes = bool(options.get("merge_meshes", false))
	var generate_lods = bool(options.get("generate_lods", false))
	var unwrap_uv2 = bool(options.get("unwrap_uv2", false))
	var uv2_texel_size = float(options.get("uv2_texel_size", DEFAULT_UV2_TEXEL_SIZE))
	var use_thread_pool = bool(options.get("use_thread_pool", true))

	var result = Node3D.new()
	result.name = "BakedGeometry"

	var static_body = StaticBody3D.new()
	static_body.name = "FloorCollision"
	static_body.collision_layer = collision_layer
	static_body.collision_mask = collision_mask
	result.add_child(static_body)

	if merge_meshes:
		var merged = _merge_entries(entries, use_thread_pool)
		if merged:
			merged = _postprocess_mesh(merged, generate_lods, unwrap_uv2, uv2_texel_size)
			var mesh_inst = MeshInstance3D.new()
			mesh_inst.name = "BakedMesh_0"
			mesh_inst.mesh = merged
			mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if material_override:
				mesh_inst.material_override = material_override
			result.add_child(mesh_inst)
			var collision = CollisionShape3D.new()
			collision.shape = merged.create_trimesh_shape()
			static_body.add_child(collision)
			return result

	var mesh_count := 0
	for entry in entries:
		var mesh: Mesh = null
		var mesh_xform := Transform3D.IDENTITY
		if entry is Mesh:
			mesh = entry
		elif entry is Array:
			if entry.size() > 0 and entry[0] is Mesh:
				mesh = entry[0]
			if entry.size() > 1 and entry[1] is Transform3D:
				mesh_xform = entry[1]
		if not mesh:
			continue

		var processed = _postprocess_mesh(mesh, generate_lods, unwrap_uv2, uv2_texel_size)

		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "BakedMesh_%d" % mesh_count
		mesh_inst.mesh = processed
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_inst.transform = mesh_xform
		if material_override:
			mesh_inst.material_override = material_override
		result.add_child(mesh_inst)

		var collision = CollisionShape3D.new()
		collision.shape = processed.create_trimesh_shape()
		collision.transform = mesh_xform
		static_body.add_child(collision)

		mesh_count += 1

	if mesh_count == 0:
		return null

	return result

func _postprocess_mesh(mesh: Mesh, generate_lods: bool, unwrap_uv2: bool, uv2_texel_size: float) -> Mesh:
	if not mesh:
		return null
	var result = mesh
	if unwrap_uv2 and result.has_method("lightmap_unwrap"):
		var unwrapped = result.call("lightmap_unwrap", Transform3D.IDENTITY, uv2_texel_size)
		if unwrapped is Mesh:
			result = unwrapped
	if generate_lods and result.has_method("generate_lods"):
		result.call("generate_lods")
	return result

func _merge_entries(entries: Array, _use_thread_pool: bool) -> ArrayMesh:
	var mesh_entries = _collect_mesh_entries(entries)
	if mesh_entries.is_empty():
		return null
	return _merge_entries_worker(mesh_entries)

func _collect_mesh_entries(entries: Array) -> Array:
	var list: Array = []
	for entry in entries:
		var mesh: Mesh = null
		var mesh_xform := Transform3D.IDENTITY
		if entry is Mesh:
			mesh = entry
		elif entry is Array:
			if entry.size() > 0 and entry[0] is Mesh:
				mesh = entry[0]
			if entry.size() > 1 and entry[1] is Transform3D:
				mesh_xform = entry[1]
		if mesh:
			list.append({ "mesh": mesh, "transform": mesh_xform })
	return list

func _merge_entries_worker(mesh_entries: Array) -> ArrayMesh:
	var merged = ArrayMesh.new()
	for entry in mesh_entries:
		var mesh: Mesh = entry.get("mesh", null)
		var xform: Transform3D = entry.get("transform", Transform3D.IDENTITY)
		if not mesh:
			continue
		var surface_count = mesh.get_surface_count()
		for surface in range(surface_count):
			var arrays = mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			var primitive = mesh.surface_get_primitive_type(surface)
			var transformed = _transform_arrays(arrays, xform)
			merged.add_surface_from_arrays(primitive, transformed)
	return merged if merged.get_surface_count() > 0 else null

func _transform_arrays(arrays: Array, xform: Transform3D) -> Array:
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	for i in range(arrays.size()):
		out[i] = arrays[i]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() > 0:
		var new_verts = PackedVector3Array()
		new_verts.resize(verts.size())
		for i in range(verts.size()):
			new_verts[i] = xform * verts[i]
		out[Mesh.ARRAY_VERTEX] = new_verts
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() > 0:
		var new_normals = PackedVector3Array()
		new_normals.resize(normals.size())
		var basis = xform.basis
		for i in range(normals.size()):
			new_normals[i] = (basis * normals[i]).normalized()
		out[Mesh.ARRAY_NORMAL] = new_normals
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	if tangents.size() > 0:
		var new_tangents = PackedFloat32Array()
		new_tangents.resize(tangents.size())
		var basis_t = xform.basis
		for i in range(0, tangents.size(), 4):
			var t = Vector3(tangents[i], tangents[i + 1], tangents[i + 2])
			t = (basis_t * t).normalized()
			new_tangents[i] = t.x
			new_tangents[i + 1] = t.y
			new_tangents[i + 2] = t.z
			new_tangents[i + 3] = tangents[i + 3]
		out[Mesh.ARRAY_TANGENT] = new_tangents
	return out
