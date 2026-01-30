@tool
extends Node
class_name PrefabFactory

const LevelRootType = preload("level_root.gd")

static func create_prefab(type: int, size: Vector3, sides: int = 4) -> CSGShape3D:
    var brush: CSGShape3D = null
    var safe_sides = max(3, sides)
    match type:
        LevelRootType.BrushShape.CYLINDER:
            var cylinder = CSGCylinder3D.new()
            cylinder.height = size.y
            cylinder.radius = max(size.x, size.z) * 0.5
            cylinder.sides = 16
            brush = cylinder
        LevelRootType.BrushShape.SPHERE, LevelRootType.BrushShape.ELLIPSOID:
            var sphere = CSGSphere3D.new()
            var radius = max(size.x, size.z) * 0.5
            sphere.radius = max(0.1, radius)
            if type == LevelRootType.BrushShape.ELLIPSOID:
                sphere.scale = Vector3(
                    size.x / max(0.1, radius * 2.0),
                    size.y / max(0.1, radius * 2.0),
                    size.z / max(0.1, radius * 2.0)
                )
                sphere.set_meta("prefab_ellipsoid", true)
                sphere.set_meta("prefab_size", Vector3(radius * 2.0, radius * 2.0, radius * 2.0))
            brush = sphere
        LevelRootType.BrushShape.CONE:
            var cone = CSGCylinder3D.new()
            cone.cone = true
            cone.height = size.y
            cone.radius = max(size.x, size.z) * 0.5
            cone.sides = 16
            brush = cone
        LevelRootType.BrushShape.PYRAMID:
            var pyramid_mesh = _pyramid_mesh(size, safe_sides)
            var pyramid = CSGMesh3D.new()
            pyramid.mesh = pyramid_mesh
            pyramid.set_meta("sides", safe_sides)
            brush = pyramid
        LevelRootType.BrushShape.WEDGE:
            var wedge = CSGPolygon3D.new()
            wedge.polygon = PackedVector2Array([
                Vector2(0.0, 0.0),
                Vector2(size.x, 0.0),
                Vector2(0.0, size.y)
            ])
            wedge.depth = size.z
            brush = wedge
        LevelRootType.BrushShape.PRISM_TRI:
            var prism_tri = CSGPolygon3D.new()
            prism_tri.polygon = _regular_polygon_points(3, Vector2(size.x * 0.5, size.y * 0.5))
            prism_tri.depth = size.z
            prism_tri.set_meta("sides", 3)
            brush = prism_tri
        LevelRootType.BrushShape.PRISM_PENT:
            var prism_pent = CSGPolygon3D.new()
            prism_pent.polygon = _regular_polygon_points(5, Vector2(size.x * 0.5, size.y * 0.5))
            prism_pent.depth = size.z
            prism_pent.set_meta("sides", 5)
            brush = prism_pent
        LevelRootType.BrushShape.CAPSULE:
            var capsule_mesh = CapsuleMesh.new()
            capsule_mesh.radius = 0.5
            capsule_mesh.height = 1.0
            var capsule = CSGMesh3D.new()
            capsule.mesh = capsule_mesh
            _apply_mesh_scale(capsule, size)
            brush = capsule
        LevelRootType.BrushShape.TORUS:
            var torus_mesh = TorusMesh.new()
            torus_mesh.ring_radius = 1.0
            torus_mesh.pipe_radius = 0.25
            var torus = CSGMesh3D.new()
            torus.mesh = torus_mesh
            _apply_mesh_scale(torus, size)
            brush = torus
        LevelRootType.BrushShape.TETRAHEDRON:
            brush = _platonic_brush(_tetrahedron_data(), size)
        LevelRootType.BrushShape.OCTAHEDRON:
            brush = _platonic_brush(_octahedron_data(), size)
        LevelRootType.BrushShape.ICOSAHEDRON:
            brush = _platonic_brush(_icosahedron_data(), size)
        LevelRootType.BrushShape.DODECAHEDRON:
            brush = _platonic_brush(_dodecahedron_data(), size)
        _:
            var box = CSGBox3D.new()
            box.size = size
            brush = box

    if not brush:
        var fallback = CSGBox3D.new()
        fallback.size = size
        brush = fallback

    brush.use_collision = true
    brush.set_meta("prefab_shape", type)
    if not brush.has_meta("prefab_size"):
        brush.set_meta("prefab_size", size)
    return brush

static func _apply_mesh_scale(node: CSGMesh3D, target_size: Vector3) -> void:
    if not node or not node.mesh:
        return
    var base_size = node.mesh.get_aabb().size
    if base_size.x <= 0.0 or base_size.y <= 0.0 or base_size.z <= 0.0:
        return
    node.scale = Vector3(
        target_size.x / base_size.x,
        target_size.y / base_size.y,
        target_size.z / base_size.z
    )
    node.set_meta("prefab_size", base_size)

static func _regular_polygon_points(sides: int, radius: Vector2) -> PackedVector2Array:
    var points := PackedVector2Array()
    var count = max(3, sides)
    for i in range(count):
        var angle = TAU * float(i) / float(count)
        points.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
    return points

static func _platonic_brush(data: Dictionary, size: Vector3) -> CSGMesh3D:
    var mesh = _mesh_from_faces(data["vertices"], data["faces"])
    var brush = CSGMesh3D.new()
    brush.mesh = mesh
    _apply_mesh_scale(brush, size)
    return brush

static func _mesh_from_faces(vertices: Array, faces: Array) -> ArrayMesh:
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for face in faces:
        var count = face.size()
        if count < 3:
            continue
        for i in range(1, count - 1):
            st.add_vertex(vertices[face[0]])
            st.add_vertex(vertices[face[i]])
            st.add_vertex(vertices[face[i + 1]])
    st.generate_normals()
    return st.commit()

static func _pyramid_mesh(size: Vector3, sides: int) -> ArrayMesh:
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var count = max(3, sides)
    var rx = size.x * 0.5
    var rz = size.z * 0.5
    var apex = Vector3(0.0, size.y, 0.0)
    var base_center = Vector3.ZERO
    var base: Array = []
    for i in range(count):
        var angle = TAU * float(i) / float(count)
        base.append(Vector3(cos(angle) * rx, 0.0, sin(angle) * rz))
    # side faces
    for i in range(count):
        var v0: Vector3 = base[i]
        var v1: Vector3 = base[(i + 1) % count]
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(apex)
    # base faces (clockwise to face down)
    for i in range(1, count - 1):
        st.add_vertex(base_center)
        st.add_vertex(base[i + 1])
        st.add_vertex(base[i])
    st.generate_normals()
    return st.commit()

static func _normalize_vertices(vertices: Array) -> Array:
    var normalized: Array = []
    for v in vertices:
        var vec: Vector3 = v
        normalized.append(vec.normalized())
    return normalized

static func _tetrahedron_data() -> Dictionary:
    var vertices = _normalize_vertices([
        Vector3(1, 1, 1),
        Vector3(-1, -1, 1),
        Vector3(-1, 1, -1),
        Vector3(1, -1, -1)
    ])
    var faces = [
        PackedInt32Array([0, 1, 2]),
        PackedInt32Array([0, 3, 1]),
        PackedInt32Array([0, 2, 3]),
        PackedInt32Array([1, 3, 2])
    ]
    return { "vertices": vertices, "faces": faces }

static func _octahedron_data() -> Dictionary:
    var vertices = _normalize_vertices([
        Vector3(1, 0, 0),
        Vector3(-1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, -1, 0),
        Vector3(0, 0, 1),
        Vector3(0, 0, -1)
    ])
    var faces = [
        PackedInt32Array([0, 2, 4]),
        PackedInt32Array([2, 1, 4]),
        PackedInt32Array([1, 3, 4]),
        PackedInt32Array([3, 0, 4]),
        PackedInt32Array([2, 0, 5]),
        PackedInt32Array([1, 2, 5]),
        PackedInt32Array([3, 1, 5]),
        PackedInt32Array([0, 3, 5])
    ]
    return { "vertices": vertices, "faces": faces }

static func _icosahedron_data() -> Dictionary:
    var phi = (1.0 + sqrt(5.0)) * 0.5
    var vertices = _normalize_vertices([
        Vector3(-1, phi, 0),
        Vector3(1, phi, 0),
        Vector3(-1, -phi, 0),
        Vector3(1, -phi, 0),
        Vector3(0, -1, phi),
        Vector3(0, 1, phi),
        Vector3(0, -1, -phi),
        Vector3(0, 1, -phi),
        Vector3(phi, 0, -1),
        Vector3(phi, 0, 1),
        Vector3(-phi, 0, -1),
        Vector3(-phi, 0, 1)
    ])
    var faces = [
        PackedInt32Array([0, 11, 5]),
        PackedInt32Array([0, 5, 1]),
        PackedInt32Array([0, 1, 7]),
        PackedInt32Array([0, 7, 10]),
        PackedInt32Array([0, 10, 11]),
        PackedInt32Array([1, 5, 9]),
        PackedInt32Array([5, 11, 4]),
        PackedInt32Array([11, 10, 2]),
        PackedInt32Array([10, 7, 6]),
        PackedInt32Array([7, 1, 8]),
        PackedInt32Array([3, 9, 4]),
        PackedInt32Array([3, 4, 2]),
        PackedInt32Array([3, 2, 6]),
        PackedInt32Array([3, 6, 8]),
        PackedInt32Array([3, 8, 9]),
        PackedInt32Array([4, 9, 5]),
        PackedInt32Array([2, 4, 11]),
        PackedInt32Array([6, 2, 10]),
        PackedInt32Array([8, 6, 7]),
        PackedInt32Array([9, 8, 1])
    ]
    return { "vertices": vertices, "faces": faces }

static func _dodecahedron_data() -> Dictionary:
    var icosa = _icosahedron_data()
    var vertices: Array = icosa["vertices"]
    var faces: Array = icosa["faces"]
    var centers: Array = []
    for face in faces:
        var center = (vertices[face[0]] + vertices[face[1]] + vertices[face[2]]) / 3.0
        centers.append(center.normalized())
    var dodeca_faces: Array = []
    for vertex_index in range(vertices.size()):
        var face_indices: Array = []
        for face_index in range(faces.size()):
            var face = faces[face_index]
            if face.has(vertex_index):
                face_indices.append(face_index)
        var normal = vertices[vertex_index].normalized()
        var axis_x = normal.cross(Vector3.UP)
        if axis_x.length() < 0.001:
            axis_x = normal.cross(Vector3.RIGHT)
        axis_x = axis_x.normalized()
        var axis_y = normal.cross(axis_x).normalized()
        face_indices.sort_custom(func(a, b):
            var va = centers[a]
            var vb = centers[b]
            var pa = va - normal * va.dot(normal)
            var pb = vb - normal * vb.dot(normal)
            var angle_a = atan2(pa.dot(axis_y), pa.dot(axis_x))
            var angle_b = atan2(pb.dot(axis_y), pb.dot(axis_x))
            return angle_a < angle_b
        )
        dodeca_faces.append(PackedInt32Array(face_indices))
    return { "vertices": centers, "faces": dodeca_faces }
