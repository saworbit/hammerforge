@tool
extends Resource
class_name BrushPreset

enum BrushShape { BOX, CYLINDER }

@export var shape: int = BrushShape.BOX
@export var size: Vector3 = Vector3(32.0, 32.0, 32.0)
@export var operation: int = CSGShape3D.OPERATION_UNION
