@tool
extends Node3D
class_name DraftBrush

const LevelRootType = preload("level_root.gd")
const BrushShape = LevelRootType.BrushShape
const PrefabFactory = preload("prefab_factory.gd")
const FaceData = preload("face_data.gd")
const MaterialManager = preload("material_manager.gd")
const HFOutlineUtil = preload("hf_outline_util.gd")

@export var shape: int = BrushShape.BOX:
	set = set_shape
@export var size: Vector3 = Vector3(32, 32, 32):
	set = set_size
@export var operation: int = CSGShape3D.OPERATION_UNION:
	set = set_operation
@export var sides: int = 4:
	set = set_sides
# Internal persistent identity. Users should never need to understand or edit
# this in the Inspector; native duplication is reconciled to a fresh ID.
@export_storage var brush_id: String = ""
@export var material_override: Material = null:
	set = set_material_override
@export var faces: Array[FaceData] = []:
	set(value):
		faces = value
		_queue_gizmo_update()

var editor_material: Material = null
var mesh_instance: MeshInstance3D = null
var selected_faces: PackedInt32Array = PackedInt32Array()
var geometry_dirty := true
var _gizmo_update_queued := false
const MAX_PREVIEW_SURFACES := 200
const BASE_MESH_MARKER_META := &"_hammerforge_base_mesh"
const OVERLAY_MARKER_META := &"_hammerforge_visual_overlay"
const OVERLAY_KIND_ADDITIVE := &"additive"
const OVERLAY_KIND_SUBTRACT := &"subtract"
const OVERLAY_KIND_ENTITY := &"entity"
const ADDITIVE_OVERLAY_NAME := &"_AdditiveWireOverlay"
const SUBTRACT_OVERLAY_NAME := &"_SubtractWireOverlay"
const ENTITY_OVERLAY_NAME := &"_BrushEntityOverlay"


func _ready() -> void:
	_ensure_mesh_instance()
	_update_visuals()


func _ensure_mesh_instance() -> void:
	# Node.duplicate() copies children but does not reliably restore this runtime
	# reference. Adopt the copied private base mesh instead of creating a second
	# overlapping MeshInstance3D, then discard only explicitly HammerForge-owned
	# duplicates left by older versions.
	if (
		mesh_instance == null
		or not is_instance_valid(mesh_instance)
		or mesh_instance.get_parent() != self
		or mesh_instance.is_queued_for_deletion()
	):
		mesh_instance = null

	var private_base_meshes: Array[MeshInstance3D] = []
	var legacy_base_mesh: MeshInstance3D = null
	for child in get_children(true):
		if not child is MeshInstance3D or child.is_queued_for_deletion():
			continue
		var candidate := child as MeshInstance3D
		if bool(candidate.get_meta(BASE_MESH_MARKER_META, false)):
			private_base_meshes.append(candidate)
		elif candidate.name == &"Mesh" and legacy_base_mesh == null:
			legacy_base_mesh = candidate

	if mesh_instance == null:
		if not private_base_meshes.is_empty():
			mesh_instance = private_base_meshes[0]
		elif legacy_base_mesh != null:
			mesh_instance = legacy_base_mesh
		else:
			mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "Mesh"
			add_child(mesh_instance)

	mesh_instance.set_meta(BASE_MESH_MARKER_META, true)
	for candidate in private_base_meshes:
		if candidate != mesh_instance:
			_discard_private_visual(candidate)
	if legacy_base_mesh != null and legacy_base_mesh != mesh_instance:
		_discard_private_visual(legacy_base_mesh)
	if mesh_instance.name != &"Mesh":
		mesh_instance.name = "Mesh"


func get_faces() -> Array:
	return faces


## Declare `faces` the authoritative geometry for this brush.
##
## Bevel, inset, and vertex edits change face topology or vertex positions that
## no primitive can reproduce. Until the brush is CUSTOM, the next set_size(),
## sides change, or scene reload runs _rebuild_faces() and replaces the edit
## with a plain primitive. Promoting also drops the box resize handles, which is
## the point: those handles call set_size() and would wipe the edit.
func mark_faces_authoritative() -> void:
	if faces.is_empty() or shape == BrushShape.CUSTOM:
		return
	shape = BrushShape.CUSTOM


func set_selected_faces(indices: PackedInt32Array) -> void:
	selected_faces = indices
	rebuild_preview()


func assign_material_to_faces(mat_idx: int, face_indices: Array[int]) -> void:
	for idx in face_indices:
		if idx < 0 or idx >= faces.size():
			continue
		var face: FaceData = faces[idx]
		face.material_idx = mat_idx
	rebuild_preview()


func set_shape(val: int) -> void:
	shape = val
	# Primitive meshes with a circular cross-section have fewer independent
	# dimensions than Vector3 exposes. Normalize immediately so stored bounds,
	# visible geometry, selection collision, and resize handles all agree.
	set_size(size)
	_queue_gizmo_update()


func set_size(val: Vector3) -> void:
	size = normalized_size_for_shape(shape, val)
	geometry_dirty = true
	_queue_gizmo_update()
	_update_visuals()


static func normalized_size_for_shape(shape_value: int, requested: Vector3) -> Vector3:
	if shape_value == BrushShape.SPHERE:
		var diameter := maxf(0.1, maxf(requested.x, requested.z))
		return Vector3(diameter, diameter, diameter)
	if shape_value in [BrushShape.CYLINDER, BrushShape.CONE, BrushShape.CAPSULE]:
		var diameter := maxf(0.1, maxf(requested.x, requested.z))
		var height := maxf(0.1, requested.y)
		if shape_value == BrushShape.CAPSULE:
			height = maxf(height, diameter)
		return Vector3(diameter, height, diameter)
	return requested


func set_operation(val: int) -> void:
	operation = val
	_update_visuals()


func set_sides(val: int) -> void:
	sides = max(3, val)
	geometry_dirty = true
	_queue_gizmo_update()
	_update_visuals()


func set_material_override(val: Material) -> void:
	material_override = val
	_refresh_preview_visuals()


func set_editor_material(val: Material) -> void:
	editor_material = val
	_refresh_preview_visuals()


## Update the semantic brush-entity classification and refresh its visual cue
## immediately. Production code should use this instead of mutating the
## metadata directly so tie/untie, restore, and geometry operations cannot
## leave a stale tint or overlay behind.
func set_brush_entity_class(entity_class: String) -> void:
	var normalized := entity_class.strip_edges()
	if normalized.is_empty():
		if has_meta("brush_entity_class"):
			remove_meta("brush_entity_class")
	else:
		set_meta("brush_entity_class", normalized)
	_refresh_preview_visuals()


func clear_editor_material() -> void:
	editor_material = null
	_refresh_preview_visuals()


func _refresh_preview_visuals() -> void:
	if not is_inside_tree():
		return
	_ensure_mesh_instance()
	# Custom/painted geometry needs its surfaces rebuilt so material changes are
	# reflected per face. Primitive previews can keep their mesh and only refresh
	# the override, avoiding unnecessary geometry churn.
	if _should_use_face_preview():
		rebuild_preview()
	else:
		_apply_material(true)


func _update_visuals() -> void:
	if not is_inside_tree():
		return
	_ensure_mesh_instance()
	var build = _build_base_mesh()
	var base_mesh: Mesh = build.get("mesh", null)
	var mesh_scale: Vector3 = build.get("scale", Vector3.ONE)
	# CUSTOM faces loaded from a scene are already the authoritative geometry.
	# geometry_dirty is transient and defaults true on every reload; rebuilding
	# here would replace a saved polygon/merge/path brush with the fallback box.
	var preserve_custom_faces := shape == BrushShape.CUSTOM and not faces.is_empty()
	if (geometry_dirty and not preserve_custom_faces) or faces.is_empty():
		_rebuild_faces(base_mesh, mesh_scale)
		geometry_dirty = false
	rebuild_preview(base_mesh, mesh_scale)


func rebuild_preview(base_mesh: Mesh = null, mesh_scale: Vector3 = Vector3.ONE) -> void:
	_queue_gizmo_update()
	if not mesh_instance:
		return
	if faces.is_empty():
		mesh_instance.scale = mesh_scale
		mesh_instance.mesh = base_mesh
		_apply_material(true)
		return
	if not _should_use_face_preview():
		var build = (
			_build_base_mesh() if base_mesh == null else {"mesh": base_mesh, "scale": mesh_scale}
		)
		mesh_instance.scale = build.get("scale", Vector3.ONE)
		mesh_instance.mesh = build.get("mesh", null)
		_apply_material(true)
		return
	mesh_instance.scale = Vector3.ONE
	var mesh = ArrayMesh.new()
	var material_manager = _resolve_material_manager()
	var use_paint := _can_use_paint_preview()
	var groups: Dictionary = {}
	for face in faces:
		if face == null:
			continue
		face.ensure_geometry()
		var tri = face.triangulate()
		var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
		var uvs: PackedVector2Array = tri.get("uvs", PackedVector2Array())
		if verts.is_empty():
			continue
		var mat = _material_for_face(face, material_manager, use_paint)
		var key = mat if use_paint else _material_group_key(face, mat)
		if not groups.has(key):
			groups[key] = {
				"material": mat,
				"verts": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"normals": PackedVector3Array()
			}
		var group = groups[key]
		for i in range(verts.size()):
			group["verts"].append(verts[i])
			group["uvs"].append(uvs[i] if uvs.size() > i else Vector2.ZERO)
			group["normals"].append(face.normal)
	if groups.size() > MAX_PREVIEW_SURFACES:
		mesh_instance.mesh = base_mesh
		_apply_material()
		return
	var surface_count := 0
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
		st.commit(mesh)
		surface_count += 1
	mesh_instance.mesh = mesh if surface_count > 0 else base_mesh
	mesh_instance.material_override = null
	_sync_visual_overlays()


## Geometry setters and face rebuilds often cascade through several preview
## methods in one frame. Coalesce them into one editor gizmo invalidation so
## outlines, filled collision and handles refresh without redraw storms.
func _queue_gizmo_update() -> void:
	if _gizmo_update_queued or not is_inside_tree() or not Engine.is_editor_hint():
		return
	_gizmo_update_queued = true
	call_deferred("_flush_gizmo_update")


func _flush_gizmo_update() -> void:
	if not _gizmo_update_queued:
		return
	_gizmo_update_queued = false
	if is_inside_tree() and Engine.is_editor_hint():
		update_gizmos()


## Handle drags need immediate feedback. Let the gizmo plugin consume a queued
## deferred refresh so the same geometry change is not redrawn twice.
func _refresh_editor_gizmo_now() -> void:
	_gizmo_update_queued = false
	if is_inside_tree() and Engine.is_editor_hint():
		update_gizmos()


func _rebuild_faces(base_mesh: Mesh, mesh_scale: Vector3) -> void:
	var old_faces = faces
	var next_faces: Array[FaceData] = []
	if shape == BrushShape.BOX:
		next_faces = _build_box_faces()
	elif base_mesh:
		next_faces = _faces_from_mesh(base_mesh, mesh_scale)
	_transfer_face_data(old_faces, next_faces)
	faces = next_faces


func _transfer_face_data(old_faces: Array, new_faces: Array) -> void:
	if old_faces.size() != new_faces.size():
		return
	for i in range(new_faces.size()):
		var old_face = old_faces[i]
		var new_face = new_faces[i]
		if old_face == null or new_face == null:
			continue
		new_face.material_idx = old_face.material_idx
		new_face.uv_projection = old_face.uv_projection
		new_face.uv_scale = old_face.uv_scale
		new_face.uv_offset = old_face.uv_offset
		new_face.uv_rotation = old_face.uv_rotation
		if old_face.custom_uvs.size() == new_face.local_verts.size():
			new_face.custom_uvs = old_face.custom_uvs
		if old_face.paint_layers.size() > 0:
			new_face.paint_layers = old_face.paint_layers.duplicate(true)
		# Displacement stores per-vertex offsets against the face corners, not
		# absolute positions, so it survives a resize unchanged. The old face is
		# discarded right after this, so hand the resource over rather than copy.
		new_face.displacement = old_face.displacement


func _build_base_mesh() -> Dictionary:
	var mesh: Mesh = null
	var mesh_scale := Vector3.ONE
	match shape:
		BrushShape.BOX:
			var box = BoxMesh.new()
			box.size = size
			mesh = box
		BrushShape.CYLINDER:
			var cyl = CylinderMesh.new()
			cyl.height = size.y
			var radius = max(size.x, size.z) * 0.5
			cyl.top_radius = radius
			cyl.bottom_radius = radius
			mesh = cyl
		BrushShape.CONE:
			var cone = CylinderMesh.new()
			cone.height = size.y
			cone.bottom_radius = max(size.x, size.z) * 0.5
			cone.top_radius = 0.0
			mesh = cone
		BrushShape.WEDGE:
			mesh = _build_wedge_mesh()
		BrushShape.SPHERE:
			var sphere = SphereMesh.new()
			sphere.radius = max(size.x, size.z) * 0.5
			sphere.height = sphere.radius * 2.0
			mesh = sphere
		BrushShape.ELLIPSOID:
			var ellipsoid = SphereMesh.new()
			var base_radius = max(size.x, size.z) * 0.5
			ellipsoid.radius = max(0.1, base_radius)
			ellipsoid.height = ellipsoid.radius * 2.0
			mesh = ellipsoid
			var denom = max(0.1, ellipsoid.radius * 2.0)
			mesh_scale = Vector3(size.x / denom, size.y / denom, size.z / denom)
		BrushShape.CAPSULE:
			var capsule = CapsuleMesh.new()
			capsule.radius = max(size.x, size.z) * 0.5
			capsule.height = max(0.1, size.y)
			mesh = capsule
		BrushShape.TORUS:
			var torus = TorusMesh.new()
			# Godot 4 exposes inner/outer radii. Fit a stable canonical torus to
			# the requested brush bounds so X/Y/Z dimensions remain predictable.
			torus.outer_radius = 1.0
			torus.inner_radius = 0.5
			mesh = torus
			var torus_size := torus.get_aabb().size
			mesh_scale = Vector3(
				size.x / max(0.1, torus_size.x),
				size.y / max(0.1, torus_size.y),
				size.z / max(0.1, torus_size.z)
			)
		BrushShape.PYRAMID:
			mesh = PrefabFactory._pyramid_mesh(size, sides)
		BrushShape.PRISM_TRI:
			mesh = _build_prism_mesh(3)
		BrushShape.PRISM_PENT:
			mesh = _build_prism_mesh(5)
		BrushShape.TETRAHEDRON:
			mesh = _mesh_from_prefab_data(PrefabFactory._tetrahedron_data(), size)
		BrushShape.OCTAHEDRON:
			mesh = _mesh_from_prefab_data(PrefabFactory._octahedron_data(), size)
		BrushShape.ICOSAHEDRON:
			mesh = _mesh_from_prefab_data(PrefabFactory._icosahedron_data(), size)
		BrushShape.DODECAHEDRON:
			mesh = _mesh_from_prefab_data(PrefabFactory._dodecahedron_data(), size)
		_:
			var fallback = BoxMesh.new()
			fallback.size = size
			mesh = fallback
	return {"mesh": mesh, "scale": mesh_scale}


func _build_wedge_mesh() -> ArrayMesh:
	var half := size * 0.5
	var vertices := [
		Vector3(-half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, -half.z),
		Vector3(-half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z),
		Vector3(half.x, -half.y, half.z),
		Vector3(-half.x, half.y, half.z),
	]
	# Clockwise winding as seen from outside, matching FaceData's convention.
	var faces := [
		PackedInt32Array([0, 1, 2]),
		PackedInt32Array([3, 5, 4]),
		PackedInt32Array([0, 3, 4, 1]),
		PackedInt32Array([0, 2, 5, 3]),
		PackedInt32Array([2, 1, 4, 5]),
	]
	return PrefabFactory._mesh_from_faces(vertices, faces)


## Single semantic outline source shared by idle hover and the native selection
## gizmo. Curved primitives use a few readable profiles; generated polyhedra
## keep real creases while dropping coplanar triangulation diagonals.
func get_editor_outline_lines() -> PackedVector3Array:
	var outline_size := normalized_size_for_shape(shape, size)
	match shape:
		BrushShape.BOX:
			return HFOutlineUtil.box_lines(outline_size)
		BrushShape.CYLINDER:
			return HFOutlineUtil.cylinder_lines(outline_size)
		BrushShape.SPHERE:
			return HFOutlineUtil.sphere_lines(outline_size)
		BrushShape.CONE:
			return HFOutlineUtil.cone_lines(outline_size)
		BrushShape.ELLIPSOID:
			return HFOutlineUtil.ellipsoid_lines(outline_size)
		BrushShape.CAPSULE:
			return HFOutlineUtil.capsule_lines(outline_size)
		BrushShape.TORUS:
			return HFOutlineUtil.torus_lines(outline_size)
		BrushShape.PYRAMID:
			return HFOutlineUtil.mesh_line_vertices(_generate_wire_mesh())
		BrushShape.CUSTOM:
			var custom_lines := HFOutlineUtil.semantic_face_lines(faces)
			return custom_lines if not custom_lines.is_empty() else HFOutlineUtil.box_lines(size)
		_:
			var semantic_lines := HFOutlineUtil.semantic_face_lines(faces)
			if not semantic_lines.is_empty():
				return semantic_lines
			return HFOutlineUtil.mesh_line_vertices(_generate_wire_mesh())


func _build_prism_mesh(edge_count: int) -> ArrayMesh:
	var count = max(3, edge_count)
	var half_z = size.z * 0.5
	var base: Array = []
	var top: Array = []
	var profile := PrefabFactory._regular_polygon_points(count, Vector2(size.x, size.y) * 0.5)
	for point in profile:
		base.append(Vector3(point.x, point.y, -half_z))
		top.append(Vector3(point.x, point.y, half_z))
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Clockwise from outside, matching FaceData's convention. The profile runs
	# counter-clockwise in XY, so the sides and the +Z cap take the reversed
	# order and the -Z cap takes the profile order.
	for i in range(count):
		var b0: Vector3 = base[i]
		var b1: Vector3 = base[(i + 1) % count]
		var t0: Vector3 = top[i]
		var t1: Vector3 = top[(i + 1) % count]
		st.add_vertex(b0)
		st.add_vertex(t1)
		st.add_vertex(b1)
		st.add_vertex(b0)
		st.add_vertex(t0)
		st.add_vertex(t1)
	for i in range(1, count - 1):
		st.add_vertex(top[0])
		st.add_vertex(top[i + 1])
		st.add_vertex(top[i])
		st.add_vertex(base[0])
		st.add_vertex(base[i])
		st.add_vertex(base[i + 1])
	st.generate_normals()
	return st.commit()


func _mesh_from_prefab_data(data: Dictionary, target_size: Vector3) -> Mesh:
	var vertices: Array = data.get("vertices", [])
	var faces: Array = data.get("faces", [])
	var mesh = PrefabFactory._mesh_from_faces(vertices, faces)
	return _scale_mesh(mesh, target_size)


func _scale_mesh(mesh: Mesh, target_size: Vector3) -> Mesh:
	if mesh == null:
		return null
	var aabb = mesh.get_aabb()
	var base_size = aabb.size
	if base_size.x <= 0.0 or base_size.y <= 0.0 or base_size.z <= 0.0:
		return mesh
	var scale = Vector3(
		target_size.x / base_size.x, target_size.y / base_size.y, target_size.z / base_size.z
	)
	var out = ArrayMesh.new()
	var surface_count = mesh.get_surface_count()
	for surface in range(surface_count):
		var arrays = mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.size() > 0:
			var scaled = PackedVector3Array()
			scaled.resize(verts.size())
			for i in range(verts.size()):
				var v = verts[i]
				scaled[i] = Vector3(v.x * scale.x, v.y * scale.y, v.z * scale.z)
			arrays[Mesh.ARRAY_VERTEX] = scaled
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(surface), arrays)
	return out


## Quantisation used to decide whether two mesh vertices are the same point and
## whether two triangles sit on the same plane. A thousandth of a unit is finer
## than any brush dimension the editor works in and coarse enough to absorb the
## float error a CSG mesh arrives with.
const MERGE_QUANTUM := 1000.0


func _faces_from_mesh(mesh: Mesh, mesh_scale: Vector3) -> Array[FaceData]:
	var out: Array[FaceData] = []
	if mesh == null:
		return out
	var triangles: Array = []
	var surface_count = mesh.get_surface_count()
	for surface in range(surface_count):
		var arrays = mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs := PackedVector2Array()
		var uv_data = arrays[Mesh.ARRAY_TEX_UV]
		if uv_data is PackedVector2Array:
			uvs = uv_data
		var indices := PackedInt32Array()
		var index_data = arrays[Mesh.ARRAY_INDEX]
		if index_data is PackedInt32Array:
			indices = index_data
		if indices.is_empty():
			for i in range(0, verts.size(), 3):
				if i + 2 >= verts.size():
					break
				var tri_uvs := PackedVector2Array()
				if uvs.size() >= i + 3:
					tri_uvs = PackedVector2Array([uvs[i], uvs[i + 1], uvs[i + 2]])
				triangles.append(
					{
						"verts":
						PackedVector3Array(
							[
								_scale_vec3(verts[i], mesh_scale),
								_scale_vec3(verts[i + 1], mesh_scale),
								_scale_vec3(verts[i + 2], mesh_scale)
							]
						),
						"uvs": tri_uvs
					}
				)
		else:
			for i in range(0, indices.size(), 3):
				if i + 2 >= indices.size():
					break
				var ia = indices[i]
				var ib = indices[i + 1]
				var ic = indices[i + 2]
				if ia >= verts.size() or ib >= verts.size() or ic >= verts.size():
					continue
				var indexed_uvs := PackedVector2Array()
				if uvs.size() > max(ia, max(ib, ic)):
					indexed_uvs = PackedVector2Array([uvs[ia], uvs[ib], uvs[ic]])
				triangles.append(
					{
						"verts":
						PackedVector3Array(
							[
								_scale_vec3(verts[ia], mesh_scale),
								_scale_vec3(verts[ib], mesh_scale),
								_scale_vec3(verts[ic], mesh_scale)
							]
						),
						"uvs": indexed_uvs
					}
				)
	out.append_array(_merge_coplanar_triangles(triangles))
	return out


## One FaceData per flat surface, not one per mesh triangle. A CSG mesh gives a
## cylinder cap as a fan and a prism side as a pair of triangles, and storing
## each of those as its own face meant a sphere carried 4,224 faces, cost 129 KB
## in a .hflevel and 424 ms to save, and asked the user to pick one of 4,224
## slivers when they wanted to put a material on a side.
##
## Triangles merge only when they share a plane AND an edge, so two flat regions
## that happen to be coplanar stay two faces. A run whose boundary is not exactly
## one closed loop keeps its triangles, which is the safe answer for a surface
## with a hole or a pinch in it. The genuinely curved shapes barely collapse at
## all, because almost none of their triangles share a plane.
##
## Positions are indexed to integer ids up front. Every lookup after that is an
## integer, which is what keeps the pass off the critical path on a 4,000
## triangle sphere.
func _merge_coplanar_triangles(triangles: Array) -> Array[FaceData]:
	var out: Array[FaceData] = []
	if triangles.is_empty():
		return out
	var id_of: Dictionary = {}
	var point_of: Array[Vector3] = []
	var uv_of: Dictionary = {}
	var tri_ids: Array = []
	for tri in triangles:
		var tri_verts: PackedVector3Array = tri["verts"]
		var tri_uvs: PackedVector2Array = tri["uvs"]
		var ids := PackedInt32Array()
		for corner in range(3):
			var key: Vector3i = _merge_key(tri_verts[corner])
			var id: int = id_of.get(key, -1)
			if id < 0:
				id = point_of.size()
				id_of[key] = id
				point_of.append(tri_verts[corner])
			ids.append(id)
			if tri_uvs.size() == 3 and not uv_of.has(id):
				uv_of[id] = tri_uvs[corner]
		tri_ids.append(ids)
	var stride: int = point_of.size() + 1
	var plane_groups: Dictionary = {}
	for index in range(triangles.size()):
		var plane_key: Vector4i = _plane_key(triangles[index]["verts"], index)
		if not plane_groups.has(plane_key):
			plane_groups[plane_key] = []
		plane_groups[plane_key].append(index)
	for plane_key in plane_groups:
		for island in _edge_connected_islands(tri_ids, plane_groups[plane_key], stride):
			var polygon: PackedInt32Array = _boundary_loop(tri_ids, island, stride)
			if polygon.size() >= 3:
				out.append(_face_from_ids(polygon, point_of, uv_of))
				continue
			for index in island:
				out.append(_face_from_ids(tri_ids[index], point_of, uv_of))
	return out


static func _merge_key(v: Vector3) -> Vector3i:
	return Vector3i(
		roundi(v.x * MERGE_QUANTUM), roundi(v.y * MERGE_QUANTUM), roundi(v.z * MERGE_QUANTUM)
	)


## A collapsed triangle has no plane, so it gets a key of its own keyed on the
## triangle index and can never drag a real surface into its group.
static func _plane_key(tri_verts: PackedVector3Array, index: int) -> Vector4i:
	var normal: Vector3 = (tri_verts[2] - tri_verts[0]).cross(tri_verts[1] - tri_verts[0])
	if normal.length() < 0.000001:
		return Vector4i(0, 0, 0, -index - 1)
	normal = normal.normalized()
	return Vector4i(
		roundi(normal.x * MERGE_QUANTUM),
		roundi(normal.y * MERGE_QUANTUM),
		roundi(normal.z * MERGE_QUANTUM),
		roundi(normal.dot(tri_verts[0]) * MERGE_QUANTUM)
	)


## Split a set of coplanar triangles into runs that actually touch. Two flat
## regions on one plane are two faces, not one.
func _edge_connected_islands(tri_ids: Array, members: Array, stride: int) -> Array:
	if members.size() <= 1:
		return [members]
	var by_edge: Dictionary = {}
	for index in members:
		var ids: PackedInt32Array = tri_ids[index]
		for corner in range(3):
			var edge: int = _undirected_edge(ids[corner], ids[(corner + 1) % 3], stride)
			if not by_edge.has(edge):
				by_edge[edge] = []
			by_edge[edge].append(index)
	var islands: Array = []
	var seen: Dictionary = {}
	for start in members:
		if seen.has(start):
			continue
		var island: Array = []
		var queue: Array = [start]
		seen[start] = true
		while not queue.is_empty():
			var index: int = queue.pop_back()
			island.append(index)
			var ids: PackedInt32Array = tri_ids[index]
			for corner in range(3):
				var edge: int = _undirected_edge(ids[corner], ids[(corner + 1) % 3], stride)
				for neighbour in by_edge[edge]:
					if not seen.has(neighbour):
						seen[neighbour] = true
						queue.append(neighbour)
		islands.append(island)
	return islands


static func _undirected_edge(a: int, b: int, stride: int) -> int:
	if a <= b:
		return a * stride + b
	return b * stride + a


## Walk the outside edge of a run of coplanar triangles. Returns an empty array
## when the boundary is not exactly one closed loop, which is the signal to keep
## the triangles as they are.
func _boundary_loop(tri_ids: Array, island: Array, stride: int) -> PackedInt32Array:
	var directed: Dictionary = {}
	for index in island:
		var ids: PackedInt32Array = tri_ids[index]
		for corner in range(3):
			directed[ids[corner] * stride + ids[(corner + 1) % 3]] = [
				ids[corner], ids[(corner + 1) % 3]
			]
	var next_of: Dictionary = {}
	var boundary_count := 0
	for key in directed:
		var edge: Array = directed[key]
		if directed.has(edge[1] * stride + edge[0]):
			continue
		if next_of.has(edge[0]):
			# Two boundary edges leaving one vertex is a pinch, not a loop.
			return PackedInt32Array()
		next_of[edge[0]] = edge[1]
		boundary_count += 1
	if boundary_count < 3:
		return PackedInt32Array()
	var start: int = next_of.keys()[0]
	var loop := PackedInt32Array()
	var cursor: int = start
	for _step in range(boundary_count):
		loop.append(cursor)
		if not next_of.has(cursor):
			return PackedInt32Array()
		cursor = next_of[cursor]
	if cursor != start:
		return PackedInt32Array()
	return loop


## A cap fan and a split quad both leave points sitting mid-edge on the boundary.
## They carry no shape, and keeping them puts the vertex count straight back up.
static func _drop_collinear(loop: PackedVector3Array) -> PackedVector3Array:
	var count: int = loop.size()
	if count < 4:
		return loop
	var kept := PackedVector3Array()
	for i in range(count):
		var previous: Vector3 = loop[(i - 1 + count) % count]
		var current: Vector3 = loop[i]
		var next_point: Vector3 = loop[(i + 1) % count]
		var into: Vector3 = current - previous
		var out_of: Vector3 = next_point - current
		if into.length() < 0.0001 or out_of.length() < 0.0001:
			continue
		if into.normalized().cross(out_of.normalized()).length() > 0.0001:
			kept.append(current)
	if kept.size() >= 3:
		return kept
	return loop


func _face_from_ids(ids: PackedInt32Array, point_of: Array[Vector3], uv_of: Dictionary) -> FaceData:
	var polygon := PackedVector3Array()
	for id in ids:
		polygon.append(point_of[id])
	var trimmed: PackedVector3Array = _drop_collinear(polygon)
	var face = FaceData.new()
	face.local_verts = trimmed
	if trimmed.size() == polygon.size():
		var face_uvs := PackedVector2Array()
		for id in ids:
			if not uv_of.has(id):
				face_uvs = PackedVector2Array()
				break
			face_uvs.append(uv_of[id])
		face.custom_uvs = face_uvs
	face.ensure_geometry()
	return face


func _build_box_faces() -> Array[FaceData]:
	var half = size * 0.5
	var faces_out: Array[FaceData] = []
	# Quads wound clockwise (as seen from outside the brush) so that
	# triangulate() produces front-facing triangles in Godot's CW convention.
	var quads = [
		# Right (+X)
		[
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, -half.y, -half.z)
		],
		# Left (-X)
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, half.y, -half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		# Top (+Y)
		[
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(-half.x, half.y, -half.z)
		],
		# Bottom (-Y)
		[
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		# Front (+Z)
		[
			Vector3(-half.x, half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(half.x, -half.y, half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		# Back (-Z)
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(-half.x, half.y, -half.z)
		]
	]
	for quad in quads:
		var face = FaceData.new()
		face.local_verts = PackedVector3Array(quad)
		face.ensure_geometry()
		faces_out.append(face)
	return faces_out


func _scale_vec3(value: Vector3, scale: Vector3) -> Vector3:
	return Vector3(value.x * scale.x, value.y * scale.y, value.z * scale.z)


func _resolve_material_manager() -> MaterialManager:
	var current: Node = self
	while current:
		if current is MaterialManager:
			return current as MaterialManager
		if current.has_method("get_material_manager"):
			var mgr = current.call("get_material_manager")
			if mgr is MaterialManager:
				return mgr
		current = current.get_parent()
	return null


func _material_for_face(
	face: FaceData, material_manager: MaterialManager, include_paint: bool = true
) -> Material:
	var base_mat: Material = null
	if material_manager and face.material_idx >= 0:
		base_mat = material_manager.get_material(face.material_idx)
	if base_mat == null and material_override:
		base_mat = material_override
	if base_mat == null and editor_material:
		base_mat = editor_material
	if include_paint:
		var painted = face.get_painted_albedo()
		if painted:
			var tex = ImageTexture.create_from_image(painted)
			var mat = StandardMaterial3D.new()
			if base_mat is StandardMaterial3D:
				var base_std := base_mat as StandardMaterial3D
				mat.roughness = base_std.roughness
				mat.metallic = base_std.metallic
				mat.albedo_color = base_std.albedo_color
			mat.albedo_texture = tex
			return mat
	if base_mat:
		return base_mat
	return _make_default_material()


func _make_default_material() -> Material:
	var base = StandardMaterial3D.new()
	if operation == CSGShape3D.OPERATION_SUBTRACTION:
		base.albedo_color = Color(1.0, 0.2, 0.2, 0.35)
		base.emission = Color(1.0, 0.2, 0.2)
		base.emission_energy = 0.2
	else:
		base.albedo_color = Color(0.2, 0.8, 0.2, 0.35)
		base.emission = Color(0.2, 0.7, 0.2)
		base.emission_energy = 0.1
	base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	base.roughness = 0.6
	return base


func _material_group_key(face: FaceData, mat: Material) -> Variant:
	if mat:
		return mat
	if face.material_idx >= 0:
		return "mat_idx_%d" % face.material_idx
	return "_default"


func _face_has_paint(face: FaceData) -> bool:
	if face == null:
		return false
	for layer in face.paint_layers:
		if layer == null or layer.opacity <= 0.0:
			continue
		if layer.texture:
			return true
		if layer.weight_image and not layer.weight_image.is_empty():
			return true
	return false


func _can_use_paint_preview() -> bool:
	var painted_faces = 0
	for face in faces:
		if _face_has_paint(face):
			painted_faces += 1
	if painted_faces == 0:
		return false
	return faces.size() <= MAX_PREVIEW_SURFACES


func _should_use_face_preview() -> bool:
	# CUSTOM is the authoritative face representation produced by polygon/path,
	# merge, and imported geometry. Falling back to _build_base_mesh() would show
	# a misleading box whenever those faces have no explicit material assigned.
	if shape == BrushShape.CUSTOM and not faces.is_empty():
		return true
	for face in faces:
		if face == null:
			continue
		if face.material_idx >= 0:
			return true
		if _face_has_paint(face):
			return true
	return false


func serialize_faces() -> Array:
	var out: Array = []
	for face in faces:
		if face == null:
			continue
		out.append(face.to_dict())
	return out


## Shapes whose builders wound every face inside out before #313. Their saved
## faces carry the same inversion, and they are all convex, so the centroid
## check the v0 migration already uses resolves them exactly.
const INVERTED_BUILDER_SHAPES := [
	BrushShape.PRISM_TRI,
	BrushShape.PRISM_PENT,
	BrushShape.OCTAHEDRON,
	BrushShape.DODECAHEDRON,
	BrushShape.ICOSAHEDRON,
]


func apply_serialized_faces(data: Array) -> void:
	faces.clear()
	var needs_winding_migration := false
	for entry in data:
		if entry is Dictionary:
			var version := int(entry.get("winding_version", 0))
			if version < 1:
				needs_winding_migration = true
			elif version < 2 and shape in INVERTED_BUILDER_SHAPES:
				needs_winding_migration = true
			faces.append(FaceData.from_dict(entry))
	if needs_winding_migration:
		_migrate_face_winding()
	geometry_dirty = false
	rebuild_preview()


## Godot's native Scene-tree Duplicate copies exported Resource references.
## Give the new brush an independent mutable face graph before either copy can
## be edited through the Inspector, paint tools, or displacement tools.
func make_face_resources_unique() -> void:
	var unique_faces: Array[FaceData] = []
	for source_face in faces:
		if source_face == null:
			continue
		var face_copy := FaceData.new()
		face_copy.material_idx = source_face.material_idx
		face_copy.uv_projection = source_face.uv_projection
		face_copy.uv_scale = source_face.uv_scale
		face_copy.uv_offset = source_face.uv_offset
		face_copy.uv_rotation = source_face.uv_rotation
		face_copy.custom_uvs = source_face.custom_uvs.duplicate()
		face_copy.local_verts = source_face.local_verts.duplicate()
		face_copy.ensure_geometry()
		var unique_layers: Array[FaceData.PaintLayer] = []
		for source_layer in source_face.paint_layers:
			if source_layer == null:
				continue
			var layer_copy := FaceData.PaintLayer.new()
			layer_copy.texture = source_layer.texture
			layer_copy.weight_image = (
				source_layer.weight_image.duplicate() if source_layer.weight_image != null else null
			)
			layer_copy.blend_mode = source_layer.blend_mode
			layer_copy.opacity = source_layer.opacity
			unique_layers.append(layer_copy)
		face_copy.paint_layers = unique_layers
		if source_face.displacement != null:
			face_copy.displacement = source_face.displacement.duplicate(true)
		unique_faces.append(face_copy)
	faces = unique_faces
	geometry_dirty = false
	rebuild_preview()


func _migrate_face_winding() -> void:
	# Old saves used CCW winding for manual faces (box/polygon/path) and CW
	# for mesh-extracted faces, with normals computed by the old cross-product
	# formula.  New code uses CW winding everywhere with a flipped cross
	# product.  To migrate: compute the brush centroid, then for each face
	# check whether the normal points outward (away from centroid).  If not,
	# reverse the face's vertices so the new formula produces the outward
	# normal and triangulate() emits CW front-facing triangles.
	if faces.is_empty():
		return
	var centroid := Vector3.ZERO
	var vert_count := 0
	for face in faces:
		if face == null:
			continue
		for v in face.local_verts:
			centroid += v
			vert_count += 1
	if vert_count == 0:
		return
	centroid /= float(vert_count)
	for face in faces:
		if face == null or face.local_verts.size() < 3:
			continue
		var face_center := Vector3.ZERO
		for v in face.local_verts:
			face_center += v
		face_center /= float(face.local_verts.size())
		var outward_dir: Vector3 = (face_center - centroid).normalized()
		if outward_dir.length() < 0.001:
			continue
		# If the face normal points inward (away from expected outward), reverse
		if face.normal.dot(outward_dir) < 0.0:
			face.local_verts.reverse()
			if face.custom_uvs.size() == face.local_verts.size():
				face.custom_uvs.reverse()
			face.ensure_geometry()


func _generate_wire_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	match shape:
		BrushShape.WEDGE:
			_build_wedge_lines(st, size)
		BrushShape.PYRAMID:
			_build_pyramid_lines(st, size, sides)
		BrushShape.PRISM_TRI:
			_build_prism_lines(st, size, 3)
		BrushShape.PRISM_PENT:
			_build_prism_lines(st, size, 5)
		BrushShape.TETRAHEDRON:
			_build_platonic_lines(st, PrefabFactory._tetrahedron_data(), size)
		BrushShape.OCTAHEDRON:
			_build_platonic_lines(st, PrefabFactory._octahedron_data(), size)
		BrushShape.ICOSAHEDRON:
			_build_platonic_lines(st, PrefabFactory._icosahedron_data(), size)
		BrushShape.DODECAHEDRON:
			_build_platonic_lines(st, PrefabFactory._dodecahedron_data(), size)
		_:
			return null
	return st.commit()


func _build_wedge_lines(st: SurfaceTool, target_size: Vector3) -> void:
	var half := target_size * 0.5
	var back := [
		Vector3(-half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, -half.z),
		Vector3(-half.x, half.y, -half.z),
	]
	var front := [
		Vector3(-half.x, -half.y, half.z),
		Vector3(half.x, -half.y, half.z),
		Vector3(-half.x, half.y, half.z),
	]
	for index in range(3):
		var next := (index + 1) % 3
		_add_line(st, back[index], back[next])
		_add_line(st, front[index], front[next])
		_add_line(st, back[index], front[index])


func _build_pyramid_lines(st: SurfaceTool, target_size: Vector3, edge_count: int) -> void:
	var count = max(3, edge_count)
	var half_y = target_size.y * 0.5
	var apex = Vector3(0.0, half_y, 0.0)
	var base_y = -half_y
	var base: Array = []
	var profile := PrefabFactory._regular_polygon_points(
		count, Vector2(target_size.x, target_size.z) * 0.5
	)
	for point in profile:
		base.append(Vector3(point.x, base_y, point.y))
	for i in range(count):
		var v0: Vector3 = base[i]
		var v1: Vector3 = base[(i + 1) % count]
		_add_line(st, v0, v1)
		_add_line(st, v0, apex)


func _build_prism_lines(st: SurfaceTool, target_size: Vector3, edge_count: int) -> void:
	var count = max(3, edge_count)
	var half_z = target_size.z * 0.5
	var base: Array = []
	var top: Array = []
	var profile := PrefabFactory._regular_polygon_points(
		count, Vector2(target_size.x, target_size.y) * 0.5
	)
	for point in profile:
		base.append(Vector3(point.x, point.y, -half_z))
		top.append(Vector3(point.x, point.y, half_z))
	for i in range(count):
		var b0: Vector3 = base[i]
		var b1: Vector3 = base[(i + 1) % count]
		var t0: Vector3 = top[i]
		var t1: Vector3 = top[(i + 1) % count]
		_add_line(st, b0, b1)
		_add_line(st, t0, t1)
		_add_line(st, b0, t0)


func _build_platonic_lines(st: SurfaceTool, data: Dictionary, target_size: Vector3) -> void:
	if data.is_empty():
		return
	var vertices: Array = data.get("vertices", [])
	var faces: Array = data.get("faces", [])
	if vertices.is_empty():
		return
	var aabb = AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		aabb = aabb.expand(v)
	var base_size = aabb.size
	var scale = Vector3(
		target_size.x / max(0.1, base_size.x),
		target_size.y / max(0.1, base_size.y),
		target_size.z / max(0.1, base_size.z)
	)
	var edges: Dictionary = {}
	for face in faces:
		var count = face.size()
		if count < 2:
			continue
		for i in range(count):
			var a = face[i]
			var b = face[(i + 1) % count]
			var key = _edge_key(a, b)
			if edges.has(key):
				continue
			edges[key] = Vector2i(min(a, b), max(a, b))
	for key in edges.keys():
		var edge: Vector2i = edges[key]
		var v0: Vector3 = vertices[edge.x] * scale
		var v1: Vector3 = vertices[edge.y] * scale
		_add_line(st, v0, v1)


func _edge_key(a: int, b: int) -> String:
	var lo = min(a, b)
	var hi = max(a, b)
	return "%d:%d" % [lo, hi]


func _add_line(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)


func _apply_material(force: bool = false) -> void:
	if not mesh_instance:
		return
	if not force and faces.size() > 0:
		mesh_instance.material_override = null
		_sync_visual_overlays()
		return
	var mat: Material = null
	if material_override:
		mat = material_override
	elif editor_material:
		mat = editor_material
	else:
		var base = StandardMaterial3D.new()
		if operation == CSGShape3D.OPERATION_SUBTRACTION:
			base.albedo_color = Color(1.0, 0.2, 0.2, 0.35)
			base.emission = Color(1.0, 0.2, 0.2)
			base.emission_energy = 0.2
		else:
			base.albedo_color = Color(0.2, 0.8, 0.2, 0.35)
			base.emission = Color(0.2, 0.7, 0.2)
			base.emission_energy = 0.1
		# Apply brush entity class tint — blue for entities
		var bec = str(get_meta("brush_entity_class", ""))
		if bec == "func_detail":
			base.albedo_color = Color(0.3, 0.5, 1.0, 0.35)
			base.emission = Color(0.3, 0.5, 0.9)
			base.emission_energy = 0.15
		elif bec.begins_with("trigger_"):
			base.albedo_color = Color(0.4, 0.55, 1.0, 0.3)
			base.emission = Color(0.4, 0.5, 0.9)
			base.emission_energy = 0.3
		elif bec == "func_wall":
			base.albedo_color = Color(0.25, 0.45, 0.9, 0.25)
			base.emission = Color(0.25, 0.4, 0.8)
			base.emission_energy = 0.1
		elif bec != "":
			base.albedo_color = Color(0.35, 0.5, 0.85, 0.2)
			base.emission = Color(0.3, 0.45, 0.8)
			base.emission_energy = 0.1
		base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		base.roughness = 0.6
		mat = base
	mesh_instance.material_override = mat
	_sync_visual_overlays()


func _sync_visual_overlays() -> void:
	# Overlay nodes used to be queue_free()'d and immediately recreated. During
	# rapid drag rebuilds the queued node kept its name until the frame ended,
	# so Godot auto-renamed every replacement and rendered all of them together.
	# Reuse one live node per semantic overlay and detach stale nodes immediately.
	var has_mesh := mesh_instance != null and mesh_instance.mesh != null
	var brush_entity_class := str(get_meta("brush_entity_class", ""))
	var desired := {
		OVERLAY_KIND_ENTITY: has_mesh and brush_entity_class != "",
		OVERLAY_KIND_SUBTRACT: has_mesh and operation == CSGShape3D.OPERATION_SUBTRACTION,
	}
	var retained: Dictionary = {}

	for child in get_children(true):
		var kind := _visual_overlay_kind(child)
		if kind == &"":
			continue
		var can_reuse := (
			bool(desired.get(kind, false))
			and child is MeshInstance3D
			and not child.is_queued_for_deletion()
			and not retained.has(kind)
		)
		if can_reuse:
			retained[kind] = child
		else:
			_discard_visual_overlay(child)

	# Ordinary additive brushes deliberately have no topology overlay. Godot's
	# editor gizmo already provides a concise selection outline when it is useful.
	if bool(desired[OVERLAY_KIND_ENTITY]):
		var entity_overlay := _ensure_visual_overlay(
			retained, OVERLAY_KIND_ENTITY, ENTITY_OVERLAY_NAME
		)
		_configure_entity_overlay(entity_overlay, brush_entity_class)
	if bool(desired[OVERLAY_KIND_SUBTRACT]):
		var subtract_overlay := _ensure_visual_overlay(
			retained, OVERLAY_KIND_SUBTRACT, SUBTRACT_OVERLAY_NAME
		)
		_configure_subtract_overlay(subtract_overlay)


func _ensure_visual_overlay(
	retained: Dictionary, kind: StringName, canonical_name: StringName
) -> MeshInstance3D:
	var overlay := retained.get(kind, null) as MeshInstance3D
	if overlay == null:
		overlay = MeshInstance3D.new()
		overlay.name = canonical_name
		add_child(overlay, false, Node.INTERNAL_MODE_BACK)
	elif overlay.name != canonical_name:
		overlay.name = canonical_name
	overlay.set_meta(OVERLAY_MARKER_META, kind)
	overlay.mesh = mesh_instance.mesh
	overlay.transform = mesh_instance.transform
	overlay.visible = true
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.owner = null
	return overlay


func _configure_entity_overlay(overlay: MeshInstance3D, brush_entity_class: String) -> void:
	var mat := overlay.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	if brush_entity_class == "func_detail":
		mat.albedo_color = Color(0.2, 0.4, 1.0, 0.12)
	elif brush_entity_class == "func_wall":
		mat.albedo_color = Color(0.2, 0.35, 0.85, 0.08)
	elif brush_entity_class.begins_with("trigger_"):
		mat.albedo_color = Color(0.3, 0.45, 1.0, 0.15)
	else:
		mat.albedo_color = Color(0.3, 0.4, 0.8, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	overlay.material_override = mat


func _configure_subtract_overlay(overlay: MeshInstance3D) -> void:
	# Subtraction is a semantic state, not a request to expose render topology.
	# Reuse the same restrained outline as hover/selection and keep it depth-aware
	# so boxes have twelve edges and curved brushes do not become dense cages.
	overlay.mesh = HFOutlineUtil.line_mesh(get_editor_outline_lines())
	overlay.transform = Transform3D.IDENTITY
	var mat := overlay.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.albedo_color = Color(1.0, 0.25, 0.2, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	overlay.material_override = mat


func _visual_overlay_kind(node: Node) -> StringName:
	if node.has_meta(OVERLAY_MARKER_META):
		var marked_kind := StringName(str(node.get_meta(OVERLAY_MARKER_META)))
		if marked_kind in [OVERLAY_KIND_ADDITIVE, OVERLAY_KIND_SUBTRACT, OVERLAY_KIND_ENTITY]:
			return marked_kind

	var node_name := str(node.name)
	if node_name.begins_with(str(ADDITIVE_OVERLAY_NAME)):
		return OVERLAY_KIND_ADDITIVE
	if node_name.begins_with(str(SUBTRACT_OVERLAY_NAME)):
		return OVERLAY_KIND_SUBTRACT
	if node_name.begins_with(str(ENTITY_OVERLAY_NAME)):
		return OVERLAY_KIND_ENTITY

	# Old add_child() collisions can be assigned an unreadable generated name.
	# Identify only the private, shadowless overlay material signatures so normal
	# MeshInstance3D children are never mistaken for HammerForge overlays.
	if not (node is MeshInstance3D) or node == mesh_instance:
		return &""
	if not node_name.begins_with("@MeshInstance3D@") or node.owner != null:
		return &""
	var overlay := node as MeshInstance3D
	if overlay.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		return &""
	var material := overlay.material_override
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		var shader_code := shader.code if shader != null else ""
		if "vec4(0.2, 0.8, 0.2, 0.5)" in shader_code:
			return OVERLAY_KIND_ADDITIVE
		if "vec4(1.0, 0.25, 0.2, 0.7)" in shader_code:
			return OVERLAY_KIND_SUBTRACT
	elif material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		if (
			standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			and standard.no_depth_test
			and standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
			and standard.cull_mode == BaseMaterial3D.CULL_DISABLED
		):
			return OVERLAY_KIND_ENTITY
	return &""


func _discard_visual_overlay(node: Node) -> void:
	# remove_child() stops rendering now; queue_free() alone leaves the duplicate
	# visible and name-reserved until the end of the frame.
	_discard_private_visual(node)


func _discard_private_visual(node: Node) -> void:
	if node.get_parent() == self:
		remove_child(node)
	if not node.is_queued_for_deletion():
		node.queue_free()


# Compatibility entry points for editor code or third-party tools that called
# the previous private helpers directly.
func _apply_brush_entity_overlay() -> void:
	_sync_visual_overlays()


func _apply_subtract_wireframe_overlay() -> void:
	_sync_visual_overlays()


func _apply_additive_wireframe_overlay() -> void:
	_sync_visual_overlays()
