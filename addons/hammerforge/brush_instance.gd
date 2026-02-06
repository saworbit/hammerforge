@tool
extends Node3D
class_name DraftBrush

const LevelRootType = preload("level_root.gd")
const BrushShape = LevelRootType.BrushShape
const PrefabFactory = preload("prefab_factory.gd")
const FaceData = preload("face_data.gd")
const MaterialManager = preload("material_manager.gd")

@export var shape: int = BrushShape.BOX: set = set_shape
@export var size: Vector3 = Vector3(32, 32, 32): set = set_size
@export var operation: int = CSGShape3D.OPERATION_UNION: set = set_operation
@export var sides: int = 4: set = set_sides
@export var brush_id: String = ""
@export var material_override: Material = null: set = set_material_override
@export var faces: Array[FaceData] = []

var editor_material: Material = null
var mesh_instance: MeshInstance3D = null
var selected_faces: PackedInt32Array = PackedInt32Array()
var geometry_dirty := true
const MAX_PREVIEW_SURFACES := 200

func _ready() -> void:
    _ensure_mesh_instance()
    _update_visuals()

func _ensure_mesh_instance() -> void:
    if not mesh_instance:
        mesh_instance = MeshInstance3D.new()
        mesh_instance.name = "Mesh"
        add_child(mesh_instance)

func get_faces() -> Array:
    return faces

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
    geometry_dirty = true
    _update_visuals()

func set_size(val: Vector3) -> void:
    size = val
    geometry_dirty = true
    _update_visuals()

func set_operation(val: int) -> void:
    operation = val
    _update_visuals()

func set_sides(val: int) -> void:
    sides = max(3, val)
    geometry_dirty = true
    _update_visuals()

func set_material_override(val: Material) -> void:
    material_override = val
    _apply_material()

func set_editor_material(val: Material) -> void:
    editor_material = val
    _apply_material()

func clear_editor_material() -> void:
    editor_material = null
    _apply_material()

func _update_visuals() -> void:
    if not is_inside_tree():
        return
    _ensure_mesh_instance()
    var build = _build_base_mesh()
    var base_mesh: Mesh = build.get("mesh", null)
    var mesh_scale: Vector3 = build.get("scale", Vector3.ONE)
    if geometry_dirty or faces.is_empty():
        _rebuild_faces(base_mesh, mesh_scale)
        geometry_dirty = false
    rebuild_preview(base_mesh, mesh_scale)

func rebuild_preview(base_mesh: Mesh = null, mesh_scale: Vector3 = Vector3.ONE) -> void:
    if not mesh_instance:
        return
    if faces.is_empty():
        mesh_instance.scale = mesh_scale
        mesh_instance.mesh = base_mesh
        _apply_material(true)
        return
    if not _should_use_face_preview():
        var build = _build_base_mesh() if base_mesh == null else { "mesh": base_mesh, "scale": mesh_scale }
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
        BrushShape.SPHERE:
            var sphere = SphereMesh.new()
            sphere.radius = max(size.x, size.z) * 0.5
            mesh = sphere
        BrushShape.ELLIPSOID:
            var ellipsoid = SphereMesh.new()
            var base_radius = max(size.x, size.z) * 0.5
            ellipsoid.radius = max(0.1, base_radius)
            mesh = ellipsoid
            var denom = max(0.1, base_radius * 2.0)
            mesh_scale = Vector3(
                size.x / denom,
                size.y / denom,
                size.z / denom
            )
        BrushShape.CAPSULE:
            var capsule = CapsuleMesh.new()
            capsule.radius = max(size.x, size.z) * 0.5
            capsule.height = max(0.1, size.y)
            mesh = capsule
        BrushShape.TORUS:
            var torus = TorusMesh.new()
            var ring = max(size.x, size.z) * 0.25
            torus.ring_radius = max(0.1, ring)
            torus.pipe_radius = max(0.05, ring * 0.5)
            mesh = torus
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
    return { "mesh": mesh, "scale": mesh_scale }

func _build_prism_mesh(edge_count: int) -> ArrayMesh:
    var count = max(3, edge_count)
    var rx = size.x * 0.5
    var ry = size.y * 0.5
    var half_z = size.z * 0.5
    var base: Array = []
    var top: Array = []
    for i in range(count):
        var angle = TAU * float(i) / float(count)
        var x = cos(angle) * rx
        var y = sin(angle) * ry
        base.append(Vector3(x, y, -half_z))
        top.append(Vector3(x, y, half_z))
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in range(count):
        var b0: Vector3 = base[i]
        var b1: Vector3 = base[(i + 1) % count]
        var t0: Vector3 = top[i]
        var t1: Vector3 = top[(i + 1) % count]
        st.add_vertex(b0)
        st.add_vertex(b1)
        st.add_vertex(t1)
        st.add_vertex(b0)
        st.add_vertex(t1)
        st.add_vertex(t0)
    for i in range(1, count - 1):
        st.add_vertex(top[0])
        st.add_vertex(top[i])
        st.add_vertex(top[i + 1])
        st.add_vertex(base[0])
        st.add_vertex(base[i + 1])
        st.add_vertex(base[i])
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
        target_size.x / base_size.x,
        target_size.y / base_size.y,
        target_size.z / base_size.z
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

func _faces_from_mesh(mesh: Mesh, mesh_scale: Vector3) -> Array[FaceData]:
    var out: Array[FaceData] = []
    if mesh == null:
        return out
    var surface_count = mesh.get_surface_count()
    for surface in range(surface_count):
        var arrays = mesh.surface_get_arrays(surface)
        if arrays.is_empty():
            continue
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
        var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
        if indices.is_empty():
            for i in range(0, verts.size(), 3):
                if i + 2 >= verts.size():
                    break
                var face = FaceData.new()
                face.local_verts = PackedVector3Array([
                    _scale_vec3(verts[i], mesh_scale),
                    _scale_vec3(verts[i + 1], mesh_scale),
                    _scale_vec3(verts[i + 2], mesh_scale)
                ])
                if uvs.size() >= i + 3:
                    face.custom_uvs = PackedVector2Array([uvs[i], uvs[i + 1], uvs[i + 2]])
                face.ensure_geometry()
                out.append(face)
        else:
            for i in range(0, indices.size(), 3):
                if i + 2 >= indices.size():
                    break
                var ia = indices[i]
                var ib = indices[i + 1]
                var ic = indices[i + 2]
                if ia >= verts.size() or ib >= verts.size() or ic >= verts.size():
                    continue
                var face_tri = FaceData.new()
                face_tri.local_verts = PackedVector3Array([
                    _scale_vec3(verts[ia], mesh_scale),
                    _scale_vec3(verts[ib], mesh_scale),
                    _scale_vec3(verts[ic], mesh_scale)
                ])
                if uvs.size() > max(ia, max(ib, ic)):
                    face_tri.custom_uvs = PackedVector2Array([uvs[ia], uvs[ib], uvs[ic]])
                face_tri.ensure_geometry()
                out.append(face_tri)
    return out

func _build_box_faces() -> Array[FaceData]:
    var half = size * 0.5
    var faces_out: Array[FaceData] = []
    var quads = [
        [Vector3(half.x, -half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(half.x, half.y, half.z), Vector3(half.x, -half.y, half.z)],
        [Vector3(-half.x, -half.y, half.z), Vector3(-half.x, half.y, half.z), Vector3(-half.x, half.y, -half.z), Vector3(-half.x, -half.y, -half.z)],
        [Vector3(-half.x, half.y, -half.z), Vector3(-half.x, half.y, half.z), Vector3(half.x, half.y, half.z), Vector3(half.x, half.y, -half.z)],
        [Vector3(-half.x, -half.y, half.z), Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z), Vector3(half.x, -half.y, half.z)],
        [Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z), Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z)],
        [Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z), Vector3(half.x, -half.y, -half.z), Vector3(-half.x, -half.y, -half.z)]
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

func _material_for_face(face: FaceData, material_manager: MaterialManager, include_paint: bool = true) -> Material:
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
        base.albedo_color = Color(0.3, 0.6, 1.0, 0.35)
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

func apply_serialized_faces(data: Array) -> void:
    faces.clear()
    for entry in data:
        if entry is Dictionary:
            faces.append(FaceData.from_dict(entry))
    geometry_dirty = false
    rebuild_preview()

func _generate_wire_mesh() -> ArrayMesh:
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_LINES)
    match shape:
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

func _build_pyramid_lines(st: SurfaceTool, target_size: Vector3, edge_count: int) -> void:
    var count = max(3, edge_count)
    var rx = target_size.x * 0.5
    var rz = target_size.z * 0.5
    var apex = Vector3(0.0, target_size.y, 0.0)
    var base_y = 0.0
    var base: Array = []
    for i in range(count):
        var angle = TAU * float(i) / float(count)
        base.append(Vector3(cos(angle) * rx, base_y, sin(angle) * rz))
    for i in range(count):
        var v0: Vector3 = base[i]
        var v1: Vector3 = base[(i + 1) % count]
        _add_line(st, v0, v1)
        _add_line(st, v0, apex)

func _build_prism_lines(st: SurfaceTool, target_size: Vector3, edge_count: int) -> void:
    var count = max(3, edge_count)
    var rx = target_size.x * 0.5
    var ry = target_size.y * 0.5
    var half_z = target_size.z * 0.5
    var base: Array = []
    var top: Array = []
    for i in range(count):
        var angle = TAU * float(i) / float(count)
        var x = cos(angle) * rx
        var y = sin(angle) * ry
        base.append(Vector3(x, y, -half_z))
        top.append(Vector3(x, y, half_z))
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
            base.albedo_color = Color(0.3, 0.6, 1.0, 0.35)
        base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        base.roughness = 0.6
        mat = base
    mesh_instance.material_override = mat
