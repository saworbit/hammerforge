@tool
extends Node3D
class_name DraftBrush

const LevelRootType = preload("level_root.gd")
const BrushShape = LevelRootType.BrushShape

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
        _:
            var box = BoxMesh.new()
            box.size = size
            mesh_instance.mesh = box
    _apply_material()

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
