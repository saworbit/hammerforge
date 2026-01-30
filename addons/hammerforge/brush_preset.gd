@tool
extends Resource
class_name BrushPreset

const LevelRootType = preload("level_root.gd")

@export var shape: int = LevelRootType.BrushShape.BOX
@export var size: Vector3 = Vector3(32.0, 32.0, 32.0)
@export var sides: int = 4
@export var operation: int = CSGShape3D.OPERATION_UNION
