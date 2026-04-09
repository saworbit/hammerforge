@tool
extends Node
class_name Baker

const DEFAULT_UV2_TEXEL_SIZE := 0.1
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
const MaterialManager = preload("material_manager.gd")
const HFMaterialAtlasScript = preload("hf_material_atlas.gd")


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
	var unwrap_uv0_flag = bool(options.get("unwrap_uv0", false))
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

	var collision_mode: int = int(options.get("collision_mode", 0))
	var convex_clean: bool = bool(options.get("convex_clean", true))
	var convex_simplify: float = float(options.get("convex_simplify", 0.0))

	if merge_meshes:
		var merged = _merge_entries(entries, use_thread_pool)
		if merged:
			merged = _postprocess_mesh(
				merged, generate_lods, unwrap_uv2, uv2_texel_size, unwrap_uv0_flag
			)
			if merged:
				var mesh_inst = MeshInstance3D.new()
				mesh_inst.name = "BakedMesh_0"
				mesh_inst.mesh = merged
				mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if material_override:
					mesh_inst.material_override = material_override
				result.add_child(mesh_inst)
				if collision_mode >= 1:
					# Build per-entry convex hulls even when visual meshes are merged
					var per_entry_verts: Array = _collect_entry_verts(entries)
					var shapes: Array = build_convex_collision_shapes(
						per_entry_verts, convex_clean, convex_simplify
					)
					if shapes.is_empty():
						var col := CollisionShape3D.new()
						col.shape = merged.create_trimesh_shape()
						static_body.add_child(col)
					else:
						for shape in shapes:
							var col := CollisionShape3D.new()
							col.shape = shape
							static_body.add_child(col)
				else:
					var col := CollisionShape3D.new()
					col.shape = merged.create_trimesh_shape()
					static_body.add_child(col)
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

		var processed = _postprocess_mesh(
			mesh, generate_lods, unwrap_uv2, uv2_texel_size, unwrap_uv0_flag
		)
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

		if collision_mode >= 1:
			var mesh_verts: PackedVector3Array = _extract_mesh_verts(processed, mesh_xform)
			var shapes: Array = build_convex_collision_shapes(
				[mesh_verts], convex_clean, convex_simplify
			)
			if shapes.is_empty():
				var col := CollisionShape3D.new()
				col.shape = processed.create_trimesh_shape()
				col.transform = mesh_xform
				static_body.add_child(col)
			else:
				for shape in shapes:
					var col := CollisionShape3D.new()
					col.shape = shape
					static_body.add_child(col)
		else:
			var col := CollisionShape3D.new()
			col.shape = processed.create_trimesh_shape()
			col.transform = mesh_xform
			static_body.add_child(col)

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
	options: Dictionary = {}
) -> Node3D:
	if brushes.is_empty():
		return null
	var use_atlas: bool = bool(options.get("use_atlas", false))
	var collision_mode: int = int(options.get("collision_mode", 0))
	var groups: Dictionary = {}
	var per_brush_verts: Array = []
	for brush in brushes:
		if brush is DraftBrush:
			collect_brush_face_groups(brush, material_manager, material_override, use_atlas, groups)
			if collision_mode >= 1:
				var snap = snapshot_brush_faces(
					brush, material_manager, material_override, use_atlas
				)
				per_brush_verts.append(snap.get("hull_verts", PackedVector3Array()))
	if collision_mode >= 1 and not per_brush_verts.is_empty():
		options["per_brush_verts"] = per_brush_verts
	return build_mesh_from_groups(groups, collision_layer, collision_mask, options)


func _add_group_surface(
	combined_mesh: ArrayMesh, surface_materials: Array[Material], group: Dictionary
) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat: Material = group.get("material", null)
	var verts: PackedVector3Array = group.get("verts", PackedVector3Array())
	var uvs: PackedVector2Array = group.get("uvs", PackedVector2Array())
	var normals: PackedVector3Array = group.get("normals", PackedVector3Array())
	for i in range(verts.size()):
		if normals.size() > i:
			st.set_normal(normals[i])
		if uvs.size() > i:
			st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	var surface_mesh = st.commit()
	if not surface_mesh or surface_mesh.get_surface_count() == 0:
		return
	var arrays = surface_mesh.surface_get_arrays(0)
	combined_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface_materials.append(mat)


## Collect triangulated face geometry from a single brush into material groups.
## Call once per brush; pass the same [param groups] dictionary across all brushes
## so that faces sharing a material key are merged into a single group.
func collect_brush_face_groups(
	brush: DraftBrush,
	material_manager: MaterialManager,
	material_override: Material,
	use_atlas: bool,
	groups: Dictionary
) -> void:
	var faces: Array = brush.get_faces()
	if faces.is_empty():
		return
	_collect_face_groups(
		faces,
		brush.global_transform.basis,
		brush.global_transform.origin,
		brush.material_override,
		material_manager,
		material_override,
		use_atlas,
		groups
	)


## Low-level face-group collector that operates on already-extracted data rather
## than a live brush node.  Used by [method collect_brush_face_groups] and by
## [code]HFBakeSystem[/code] when processing pre-snapshotted brush state.
func _collect_face_groups(
	faces: Array,
	basis: Basis,
	origin: Vector3,
	brush_material: Material,
	material_manager: MaterialManager,
	material_override: Material,
	use_atlas: bool,
	groups: Dictionary
) -> void:
	for face in faces:
		if face == null:
			continue
		face.ensure_geometry()
		var tri = face.triangulate()
		var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
		var uvs: PackedVector2Array = tri.get("uvs", PackedVector2Array())
		if verts.is_empty():
			continue
		var mat = _resolve_face_material(face, material_manager, brush_material, material_override)
		var face_tiles: bool = use_atlas and HFMaterialAtlasScript.group_has_tiling_uvs(uvs)
		var key = mat if mat != null else "_default"
		if face_tiles:
			key = [key, "_tiling"]
		if not groups.has(key):
			groups[key] = {
				"material": mat,
				"verts": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"normals": PackedVector3Array(),
				"tiling": face_tiles,
			}
		var group = groups[key]
		var tri_normals: PackedVector3Array = tri.get("normals", PackedVector3Array())
		for i in range(verts.size()):
			var v = origin + basis * verts[i]
			group["verts"].append(v)
			group["uvs"].append(uvs[i] if uvs.size() > i else Vector2.ZERO)
			if tri_normals.size() > i:
				group["normals"].append((basis * tri_normals[i]).normalized())
			else:
				group["normals"].append((basis * face.normal).normalized())


## Synchronously capture a brush's face geometry and resolved materials into plain
## data (PackedArrays and Materials) that is fully independent of live nodes.
## Returns a dictionary with "records" (per-face tri results), "basis", and "origin".
func snapshot_brush_faces(
	brush: DraftBrush,
	material_manager: MaterialManager,
	material_override: Material,
	use_atlas: bool
) -> Dictionary:
	var faces: Array = brush.get_faces()
	var records: Array = []
	var brush_material: Material = brush.material_override
	for face in faces:
		if face == null:
			continue
		face.ensure_geometry()
		var tri = face.triangulate()
		var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
		var uvs: PackedVector2Array = tri.get("uvs", PackedVector2Array())
		if verts.is_empty():
			continue
		var mat = _resolve_face_material(face, material_manager, brush_material, material_override)
		var face_tiles: bool = use_atlas and HFMaterialAtlasScript.group_has_tiling_uvs(uvs)
		var tri_normals: PackedVector3Array = tri.get("normals", PackedVector3Array())
		(
			records
			. append(
				{
					"verts": verts,
					"uvs": uvs,
					"normals": tri_normals,
					"face_normal": face.normal,
					"material": mat,
					"tiling": face_tiles,
				}
			)
		)
	# Collect all unique world-space vertices for convex hull collision
	var basis: Basis = brush.global_transform.basis
	var origin: Vector3 = brush.global_transform.origin
	var hull_verts := PackedVector3Array()
	for rec in records:
		var verts: PackedVector3Array = rec["verts"]
		for v in verts:
			hull_verts.append(origin + basis * v)
	return {
		"records": records,
		"basis": basis,
		"origin": origin,
		"hull_verts": hull_verts,
	}


## Append pre-snapshotted face records (from [method snapshot_brush_faces]) into
## material groups.  Performs only world-space transforms and array appends — no
## live node or FaceData access, safe to call between frame yields.
func collect_snapshot_groups(snapshot: Dictionary, use_atlas: bool, groups: Dictionary) -> void:
	var records: Array = snapshot.get("records", [])
	var basis: Basis = snapshot.get("basis", Basis.IDENTITY)
	var origin: Vector3 = snapshot.get("origin", Vector3.ZERO)
	for rec in records:
		var mat: Material = rec["material"]
		var face_tiles: bool = rec["tiling"]
		var key = mat if mat != null else "_default"
		if face_tiles:
			key = [key, "_tiling"]
		if not groups.has(key):
			groups[key] = {
				"material": mat,
				"verts": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"normals": PackedVector3Array(),
				"tiling": face_tiles,
			}
		var group = groups[key]
		var verts: PackedVector3Array = rec["verts"]
		var uvs: PackedVector2Array = rec["uvs"]
		var tri_normals: PackedVector3Array = rec["normals"]
		var face_normal: Vector3 = rec["face_normal"]
		for i in range(verts.size()):
			group["verts"].append(origin + basis * verts[i])
			group["uvs"].append(uvs[i] if uvs.size() > i else Vector2.ZERO)
			if tri_normals.size() > i:
				group["normals"].append((basis * tri_normals[i]).normalized())
			else:
				group["normals"].append((basis * face_normal).normalized())


## Build final baked geometry (atlas pass, ArrayMesh, collision) from pre-collected
## material groups.  This is the second phase of a face-based bake — call after
## [method collect_brush_face_groups] has populated [param groups].
func build_mesh_from_groups(
	groups: Dictionary, collision_layer: int = 1, collision_mask: int = 1, options: Dictionary = {}
) -> Node3D:
	if groups.is_empty():
		return null
	var result = Node3D.new()
	result.name = "BakedGeometry"

	var static_body = StaticBody3D.new()
	static_body.name = "FaceCollision"
	static_body.collision_layer = collision_layer
	static_body.collision_mask = collision_mask
	result.add_child(static_body)

	var use_atlas: bool = bool(options.get("use_atlas", false))

	# --- Material atlasing pass ---
	var atlas_result: HFMaterialAtlasScript.AtlasResult = null
	if use_atlas and groups.size() > 1:
		var tiling_keys: Dictionary = {}
		for key in groups:
			if groups[key].get("tiling", false):
				tiling_keys[key] = true
		atlas_result = HFMaterialAtlasScript.build_atlas(groups.keys(), tiling_keys)
		if atlas_result and atlas_result.atlased_keys.size() < 2:
			atlas_result = null

	# Build one ArrayMesh with one surface per material group.
	var combined_mesh = ArrayMesh.new()
	var surface_materials: Array[Material] = []

	if atlas_result and atlas_result.atlas_material:
		var all_verts := PackedVector3Array()
		var all_uvs := PackedVector2Array()
		var all_normals := PackedVector3Array()
		for mat_key in atlas_result.atlased_keys:
			var group: Dictionary = groups[mat_key]
			var rect: Rect2 = atlas_result.rects[mat_key]
			var gv: PackedVector3Array = group.get("verts", PackedVector3Array())
			var gu: PackedVector2Array = group.get("uvs", PackedVector2Array())
			var gn: PackedVector3Array = group.get("normals", PackedVector3Array())
			for i in range(gv.size()):
				all_verts.append(gv[i])
				var uv: Vector2 = gu[i] if gu.size() > i else Vector2.ZERO
				all_uvs.append(HFMaterialAtlasScript.remap_uv(uv, rect))
				all_normals.append(gn[i] if gn.size() > i else Vector3.UP)
		if all_verts.size() > 0:
			var st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in range(all_verts.size()):
				st.set_normal(all_normals[i])
				st.set_uv(all_uvs[i])
				st.add_vertex(all_verts[i])
			var surface_mesh = st.commit()
			if surface_mesh and surface_mesh.get_surface_count() > 0:
				var arrays = surface_mesh.surface_get_arrays(0)
				combined_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				surface_materials.append(atlas_result.atlas_material)
		for fb_key in atlas_result.fallback_keys:
			if not groups.has(fb_key):
				continue
			_add_group_surface(combined_mesh, surface_materials, groups[fb_key])
	else:
		for group in groups.values():
			_add_group_surface(combined_mesh, surface_materials, group)

	if combined_mesh.get_surface_count() == 0:
		return null

	for i in range(surface_materials.size()):
		if surface_materials[i]:
			combined_mesh.surface_set_material(i, surface_materials[i])

	if bool(options.get("unwrap_uv0", false)):
		combined_mesh = _unwrap_uv0(combined_mesh)

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "BakedMesh_0"
	mesh_inst.mesh = combined_mesh
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	result.add_child(mesh_inst)

	var collision_mode: int = int(options.get("collision_mode", 0))
	var per_brush_verts: Array = options.get("per_brush_verts", [])
	var convex_clean: bool = bool(options.get("convex_clean", true))
	var convex_simplify: float = float(options.get("convex_simplify", 0.0))

	if collision_mode >= 1 and not per_brush_verts.is_empty():
		var convex_shapes: Array = build_convex_collision_shapes(
			per_brush_verts, convex_clean, convex_simplify
		)
		if convex_shapes.is_empty():
			var col := CollisionShape3D.new()
			col.shape = combined_mesh.create_trimesh_shape()
			static_body.add_child(col)
		else:
			for shape in convex_shapes:
				var col := CollisionShape3D.new()
				col.shape = shape
				static_body.add_child(col)
	else:
		var col := CollisionShape3D.new()
		col.shape = combined_mesh.create_trimesh_shape()
		static_body.add_child(col)

	return result


## Build convex collision shapes from per-brush vertex clusters.
## [param brush_verts] is an Array of PackedVector3Array, one entry per brush.
## Returns an Array of ConvexPolygonShape3D (one per brush with ≥4 verts).
static func build_convex_collision_shapes(
	brush_verts: Array, convex_clean: bool = true, convex_simplify: float = 0.0
) -> Array:
	var shapes: Array = []
	for verts in brush_verts:
		if not (verts is PackedVector3Array):
			continue
		var pva: PackedVector3Array = verts
		if pva.size() < 4:
			continue
		# Always deduplicate to count truly unique positions — this is the
		# degeneracy guard.  convex_clean controls whether the deduplicated
		# result replaces the working set sent to the shape.
		var unique := PackedVector3Array()
		var seen: Dictionary = {}
		for v in pva:
			var key := Vector3i(
				int(round(v.x * 1000.0)), int(round(v.y * 1000.0)), int(round(v.z * 1000.0))
			)
			if not seen.has(key):
				seen[key] = true
				unique.append(v)
		if unique.size() < 4:
			continue
		var working: PackedVector3Array = unique if convex_clean else pva
		# convex_simplify: reduce point count by merging nearby vertices into a
		# coarser grid.  A value of 0.0 skips simplification; higher values use
		# a proportionally larger grid cell derived from the AABB diagonal.
		if convex_simplify > 0.0 and working.size() > 4:
			var aabb := AABB(working[0], Vector3.ZERO)
			for v in working:
				aabb = aabb.expand(v)
			var cell: float = aabb.get_longest_axis_size() * convex_simplify
			if cell > 0.001:
				var simplified := PackedVector3Array()
				var grid: Dictionary = {}
				for v in working:
					var key := Vector3i(
						int(floor(v.x / cell)), int(floor(v.y / cell)), int(floor(v.z / cell))
					)
					if not grid.has(key):
						grid[key] = true
						simplified.append(v)
				if simplified.size() >= 4:
					working = simplified
		var shape := ConvexPolygonShape3D.new()
		shape.points = working
		shapes.append(shape)
	return shapes


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
	mesh: Mesh,
	generate_lods: bool,
	unwrap_uv2: bool,
	uv2_texel_size: float,
	unwrap_uv0: bool = false
) -> Mesh:
	if not mesh:
		return null
	var result = mesh
	if result is ArrayMesh:
		var arr_mesh := result as ArrayMesh
		if unwrap_uv0:
			arr_mesh = _unwrap_uv0(arr_mesh)
			result = arr_mesh
		if unwrap_uv2:
			var unwrapped = arr_mesh.lightmap_unwrap(Transform3D.IDENTITY, uv2_texel_size)
			if unwrapped is Mesh:
				result = unwrapped
		if generate_lods and result is ArrayMesh:
			(result as ArrayMesh).generate_lods()
	return result


func _unwrap_uv0(mesh: ArrayMesh) -> ArrayMesh:
	var out = ArrayMesh.new()
	for s_idx in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(s_idx)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		if verts.is_empty():
			continue
		# Generate planar-projected UVs per vertex based on dominant normal axis.
		var new_uvs = PackedVector2Array()
		new_uvs.resize(verts.size())
		for i in range(verts.size()):
			var v: Vector3 = verts[i]
			var n: Vector3 = (
				normals[i] if normals is PackedVector3Array and normals.size() > i else Vector3.UP
			)
			var abs_n = n.abs()
			if abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
				new_uvs[i] = Vector2(v.x, v.z)
			elif abs_n.x >= abs_n.z:
				new_uvs[i] = Vector2(v.z, v.y)
			else:
				new_uvs[i] = Vector2(v.x, v.y)
		arrays[Mesh.ARRAY_TEX_UV] = new_uvs
		var primitive = mesh.surface_get_primitive_type(s_idx)
		out.add_surface_from_arrays(primitive, arrays)
		var mat: Material = mesh.surface_get_material(s_idx)
		if mat:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


func _merge_entries(entries: Array, _use_thread_pool: bool) -> ArrayMesh:
	var mesh_entries = _collect_mesh_entries(entries)
	if mesh_entries.is_empty():
		return null
	return _merge_entries_worker(mesh_entries)


## Extract world-space vertices from a Mesh, applying the given transform.
static func _extract_mesh_verts(
	mesh: Mesh, xform: Transform3D = Transform3D.IDENTITY
) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not mesh:
		return out
	for s_idx in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(s_idx)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			out.append(xform * v)
	return out


## Collect per-entry vertex arrays from CSG output entries for convex hull generation.
func _collect_entry_verts(entries: Array) -> Array:
	var result: Array = []
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
			result.append(_extract_mesh_verts(mesh, mesh_xform))
	return result


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
	# Group surfaces by material to minimize surface count on the merged mesh.
	# Surfaces sharing the same material are concatenated into one surface.
	var mat_groups: Dictionary = {}  # material_key -> { "material", "arrays_list" }
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
			var mat: Material = mesh.surface_get_material(surface)
			var key = mat if mat != null else "_default"
			if not mat_groups.has(key):
				mat_groups[key] = {"material": mat, "arrays_list": []}
			mat_groups[key]["arrays_list"].append(_transform_arrays(arrays, xform))

	var merged = ArrayMesh.new()
	for group in mat_groups.values():
		var combined = _concat_surface_arrays(group["arrays_list"])
		if combined.is_empty():
			continue
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, combined)
		var mat: Material = group["material"]
		if mat:
			merged.surface_set_material(merged.get_surface_count() - 1, mat)
	return merged if merged.get_surface_count() > 0 else null


func _concat_surface_arrays(arrays_list: Array) -> Array:
	if arrays_list.is_empty():
		return []
	if arrays_list.size() == 1:
		return arrays_list[0]

	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	# Initialize from the first entry — packed arrays are value types in Variant
	# containers, so we must duplicate to get a mutable copy.
	var first: Array = arrays_list[0]
	for i in range(Mesh.ARRAY_MAX):
		if first[i] == null:
			continue
		out[i] = _dup_packed(first[i])

	# Append subsequent entries. Packed arrays in a Variant Array are copied on
	# access, so we must extract → append → reassign to actually mutate.
	# IMPORTANT: ARRAY_INDEX values must be rebased by the current vertex count
	# so that indices in later surfaces point at the correct merged vertices.
	# When mixing indexed and non-indexed surfaces, synthesize sequential indices
	# for the non-indexed portion so the merge produces valid indexed geometry.
	for list_idx in range(1, arrays_list.size()):
		var src: Array = arrays_list[list_idx]
		# Track current vertex count before appending (for index rebasing)
		var vert_count := 0
		if out[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			vert_count = (out[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		# Handle ARRAY_INDEX separately due to rebasing + mixed indexed/non-indexed
		var idx_channel: int = Mesh.ARRAY_INDEX
		var out_has_idx: bool = out[idx_channel] is PackedInt32Array
		var src_has_idx: bool = src[idx_channel] is PackedInt32Array
		if out_has_idx or src_has_idx:
			# Ensure out has an index buffer; if first surface was non-indexed,
			# synthesize sequential indices [0, 1, 2, ...] for its vertices.
			if not out_has_idx:
				var synth := PackedInt32Array()
				synth.resize(vert_count)
				for vi in range(vert_count):
					synth[vi] = vi
				out[idx_channel] = synth
			# Get src indices — synthesize if this surface is non-indexed
			var src_indices: PackedInt32Array
			if src_has_idx:
				src_indices = PackedInt32Array(src[idx_channel] as PackedInt32Array)
			else:
				var src_vert_count := 0
				if src[Mesh.ARRAY_VERTEX] is PackedVector3Array:
					src_vert_count = (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				src_indices = PackedInt32Array()
				src_indices.resize(src_vert_count)
				for vi in range(src_vert_count):
					src_indices[vi] = vi
			# Rebase src indices by current vertex count
			if vert_count > 0:
				for vi in range(src_indices.size()):
					src_indices[vi] += vert_count
			out[idx_channel] = _append_packed(out[idx_channel], src_indices)
		# Append all other channels normally
		for i in range(Mesh.ARRAY_MAX):
			if i == idx_channel:
				continue
			if src[i] == null or out[i] == null:
				continue
			out[i] = _append_packed(out[i], src[i])
	return out


static func _dup_packed(v: Variant) -> Variant:
	if v is PackedVector3Array:
		return PackedVector3Array(v)
	if v is PackedVector2Array:
		return PackedVector2Array(v)
	if v is PackedFloat32Array:
		return PackedFloat32Array(v)
	if v is PackedInt32Array:
		return PackedInt32Array(v)
	if v is PackedColorArray:
		return PackedColorArray(v)
	return v


static func _append_packed(dst: Variant, src: Variant) -> Variant:
	if dst is PackedVector3Array and src is PackedVector3Array:
		var arr: PackedVector3Array = dst
		arr.append_array(src)
		return arr
	if dst is PackedVector2Array and src is PackedVector2Array:
		var arr: PackedVector2Array = dst
		arr.append_array(src)
		return arr
	if dst is PackedFloat32Array and src is PackedFloat32Array:
		var arr: PackedFloat32Array = dst
		arr.append_array(src)
		return arr
	if dst is PackedInt32Array and src is PackedInt32Array:
		var arr: PackedInt32Array = dst
		arr.append_array(src)
		return arr
	if dst is PackedColorArray and src is PackedColorArray:
		var arr: PackedColorArray = dst
		arr.append_array(src)
		return arr
	return dst


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
