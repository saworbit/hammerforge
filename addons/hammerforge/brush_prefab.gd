@tool
extends Resource
class_name BrushPrefab

const LevelRootType = preload("level_root.gd")

@export var shape_type: int = LevelRootType.BrushShape.BOX
@export var default_size := Vector3(32, 32, 32)
@export var sides: int = 4
@export var inner_radius: float = 8.0
