@tool
extends CSGBox3D
class_name BrushInstance3D

@export var brush_size: Vector3 = Vector3(32, 32, 32)
@export var brush_operation: int = CSGShape3D.OPERATION_UNION

func _ready():
    size = brush_size
    operation = brush_operation
    if not material_override:
        material_override = StandardMaterial3D.new()
    material_override.albedo_color = Color(0.3, 0.6, 1.0, 0.35)
    material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material_override.roughness = 0.6

func set_brush_size(value: Vector3) -> void:
    brush_size = value
    size = value

func set_brush_operation(value: int) -> void:
    brush_operation = value
    operation = value
