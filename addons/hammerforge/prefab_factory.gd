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
            brush = sphere
        LevelRootType.BrushShape.CONE:
            var cone = CSGCylinder3D.new()
            cone.cone = true
            cone.height = size.y
            cone.radius = max(size.x, size.z) * 0.5
            cone.sides = 16
            brush = cone
        LevelRootType.BrushShape.PYRAMID:
            var pyramid = CSGPolygon3D.new()
            pyramid.mode = CSGPolygon3D.MODE_SPIN
            pyramid.spin_degrees = 360.0
            pyramid.spin_sides = safe_sides
            var base_radius = max(size.x, size.z) * 0.5
            pyramid.polygon = PackedVector2Array([
                Vector2(0.0, 0.0),
                Vector2(base_radius, 0.0),
                Vector2(0.0, size.y)
            ])
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
            var radius = max(size.x, size.z) * 0.5
            capsule_mesh.radius = max(0.1, radius)
            capsule_mesh.height = max(0.1, size.y - capsule_mesh.radius * 2.0)
            var capsule = CSGMesh3D.new()
            capsule.mesh = capsule_mesh
            brush = capsule
        LevelRootType.BrushShape.TORUS:
            var torus_mesh = TorusMesh.new()
            var outer_radius = max(size.x, size.z) * 0.5
            var pipe_radius = max(0.1, min(size.x, size.z, size.y) * 0.15)
            torus_mesh.ring_radius = max(0.1, outer_radius - pipe_radius)
            torus_mesh.pipe_radius = pipe_radius
            var torus = CSGMesh3D.new()
            torus.mesh = torus_mesh
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
    brush.set_meta("prefab_size", size)
    return brush

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
    brush.scale = Vector3(
        size.x / 2.0,
        size.y / 2.0,
        size.z / 2.0
    )
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
