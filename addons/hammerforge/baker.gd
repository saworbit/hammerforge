@tool
extends Node
class_name Baker

const DEFAULT_UV2_TEXEL_SIZE := 0.1
const FaceData = preload("face_data.gd")
const MaterialManager = preload("material_manager.gd")


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
			if merged:
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
		if not processed:
			continue

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


func bake_from_faces(
	brushes: Array,
	material_manager: MaterialManager,
	material_override: Material = null,
	collision_layer: int = 1,
	collision_mask: int = 1,
	_options: Dictionary = {}
) -> Node3D:
	if brushes.is_empty():
		return null
	var result = Node3D.new()
	result.name = "BakedGeometry"

	var static_body = StaticBody3D.new()
	static_body.name = "FaceCollision"
	static_body.collision_layer = collision_layer
	static_body.collision_mask = collision_mask
	result.add_child(static_body)

	var groups: Dictionary = {}
	for brush in brushes:
		if brush == null or not brush.has_method("get_faces"):
			continue
		var faces: Array = brush.call("get_faces")
		if faces.is_empty():
			continue
		var basis: Basis = brush.global_transform.basis
		var origin: Vector3 = brush.global_transform.origin
		var brush_material: Material = (
			brush.get("material_override") if brush.has_method("get") else null
		)
		for face in faces:
			if face == null:
				continue
			face.ensure_geometry()
			var tri = face.triangulate()
			var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
			var uvs: PackedVector2Array = tri.get("uvs", PackedVector2Array())
			if verts.is_empty():
				continue
			var mat = _resolve_face_material(
				face, material_manager, brush_material, material_override
			)
			var key = mat if mat != null else "_default"
			if not groups.has(key):
				groups[key] = {
					"material": mat,
					"verts": PackedVector3Array(),
					"uvs": PackedVector2Array(),
					"normals": PackedVector3Array()
				}
			var group = groups[key]
			for i in range(verts.size()):
				var v = origin + basis * verts[i]
				group["verts"].append(v)
				group["uvs"].append(uvs[i] if uvs.size() > i else Vector2.ZERO)
				group["normals"].append((basis * face.normal).normalized())

	var mesh_count := 0
	for group in groups.values():
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mat: Material = group.get("material", null)
		if mat:
			st.set_material(mat)
		var verts: PackedVector3Array = group.get("verts", PackedVector3Array())
		var uvs: PackedVector2Array = group.get("uvs", PackedVector2Array())
		var normals: PackedVector3Array = group.get("normals", PackedVector3Array())
		for i in range(verts.size()):
			if normals.size() > i:
				st.set_normal(normals[i])
			if uvs.size() > i:
				st.set_uv(uvs[i])
			st.add_vertex(verts[i])
		var mesh = st.commit()
		if not mesh:
			continue
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "BakedMesh_%d" % mesh_count
		mesh_inst.mesh = mesh
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		result.add_child(mesh_inst)
		var collision = CollisionShape3D.new()
		collision.shape = mesh.create_trimesh_shape()
		static_body.add_child(collision)
		mesh_count += 1

	if mesh_count == 0:
		return null
	return result


func _resolve_face_material(
	face: FaceData, material_manager: MaterialManager, brush_material: Material, fallback: Material
) -> Material:
	var base: Material = null
	if material_manager and face.material_idx >= 0:
		base = material_manager.get_material(face.material_idx)
	if base == null and brush_material:
		base = brush_material
	if base == null and fallback:
		base = fallback
	var painted = face.get_painted_albedo()
	if painted:
		var tex = ImageTexture.create_from_image(painted)
		if not tex:
			return base
		var mat = StandardMaterial3D.new()
		if base is StandardMaterial3D:
			var base_std := base as StandardMaterial3D
			mat.roughness = base_std.roughness
			mat.metallic = base_std.metallic
			mat.albedo_color = base_std.albedo_color
		mat.albedo_texture = tex
		return mat
	return base


func _postprocess_mesh(
	mesh: Mesh, generate_lods: bool, unwrap_uv2: bool, uv2_texel_size: float
) -> Mesh:
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
			list.append({"mesh": mesh, "transform": mesh_xform})
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
