@tool
extends Node3D
class_name DraftBrush

const LevelRootType = preload("level_root.gd")
const BrushShape = LevelRootType.BrushShape
const PrefabFactory = preload("prefab_factory.gd")

@export var shape: int = BrushShape.BOX: set = set_shape
@export var size: Vector3 = Vector3(32, 32, 32): set = set_size
@export var operation: int = CSGShape3D.OPERATION_UNION: set = set_operation
@export var sides: int = 4: set = set_sides
@export var brush_id: String = ""
@export var material_override: Material = null: set = set_material_override

var editor_material: Material = null
var mesh_instance: MeshInstance3D = null

func _ready() -> void:
    if not mesh_instance:
        mesh_instance = MeshInstance3D.new()
        mesh_instance.name = "Mesh"
        add_child(mesh_instance)
    _update_visuals()

func set_shape(val: int) -> void:
    shape = val
    _update_visuals()

func set_size(val: Vector3) -> void:
    size = val
    _update_visuals()

func set_operation(val: int) -> void:
    operation = val
    _update_visuals()

func set_sides(val: int) -> void:
    sides = max(3, val)
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
    if not mesh_instance:
        mesh_instance = MeshInstance3D.new()
        mesh_instance.name = "Mesh"
        add_child(mesh_instance)
    mesh_instance.scale = Vector3.ONE
    match shape:
        BrushShape.BOX:
            var box = BoxMesh.new()
            box.size = size
            mesh_instance.mesh = box
        BrushShape.CYLINDER:
            var cyl = CylinderMesh.new()
            cyl.height = size.y
            var radius = max(size.x, size.z) * 0.5
            cyl.top_radius = radius
            cyl.bottom_radius = radius
            mesh_instance.mesh = cyl
        BrushShape.CONE:
            var cone = CylinderMesh.new()
            cone.height = size.y
            cone.bottom_radius = max(size.x, size.z) * 0.5
            cone.top_radius = 0.0
            mesh_instance.mesh = cone
        BrushShape.SPHERE:
            var sphere = SphereMesh.new()
            sphere.radius = max(size.x, size.z) * 0.5
            mesh_instance.mesh = sphere
        BrushShape.ELLIPSOID:
            var ellipsoid = SphereMesh.new()
            var base_radius = max(size.x, size.z) * 0.5
            ellipsoid.radius = max(0.1, base_radius)
            mesh_instance.mesh = ellipsoid
            var denom = max(0.1, base_radius * 2.0)
            mesh_instance.scale = Vector3(
                size.x / denom,
                size.y / denom,
                size.z / denom
            )
        BrushShape.CAPSULE:
            var capsule = CapsuleMesh.new()
            capsule.radius = max(size.x, size.z) * 0.5
            capsule.height = max(0.1, size.y)
            mesh_instance.mesh = capsule
        BrushShape.TORUS:
            var torus = TorusMesh.new()
            var ring = max(size.x, size.z) * 0.25
            torus.ring_radius = max(0.1, ring)
            torus.pipe_radius = max(0.05, ring * 0.5)
            mesh_instance.mesh = torus
        BrushShape.PYRAMID, BrushShape.PRISM_TRI, BrushShape.PRISM_PENT, BrushShape.TETRAHEDRON, BrushShape.OCTAHEDRON, BrushShape.DODECAHEDRON, BrushShape.ICOSAHEDRON:
            var draft_mesh = _generate_draft_mesh()
            if draft_mesh:
                mesh_instance.mesh = draft_mesh
            else:
                var fallback = BoxMesh.new()
                fallback.size = size
                mesh_instance.mesh = fallback
        _:
            var box_fallback = BoxMesh.new()
            box_fallback.size = size
            mesh_instance.mesh = box_fallback
    _apply_material()

func _generate_draft_mesh() -> ArrayMesh:
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

func _apply_material() -> void:
    if not mesh_instance:
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
