@tool
extends Node

@export var grid_x: int = 10
@export var grid_z: int = 10
@export var spacing: float = 4.0
@export var brush_size: Vector3 = Vector3(3, 3, 3)
@export var regenerate: bool = false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	var root = _find_level_root()
	if not root:
		return
	if not root.draft_brushes_node:
		return
	# Avoid regenerating if content already exists unless forced.
	if not regenerate and root.draft_brushes_node.get_child_count() > 0:
		return
	# Clear previous stress brushes only.
	for child in root.draft_brushes_node.get_children():
		if child and child.has_meta("hf_stress"):
			child.queue_free()
	regenerate = false
	for x in range(grid_x):
		for z in range(grid_z):
			var center = Vector3(float(x) * spacing, brush_size.y * 0.5, float(z) * spacing)
			var info = {
				"shape": root.BrushShape.BOX,
				"size": brush_size,
				"center": center,
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": root._next_brush_id()
			}
			var brush = root.create_brush_from_info(info)
			if brush:
				brush.set_meta("hf_stress", true)


func _find_level_root() -> Node:
	var current: Node = get_parent()
	while current:
		if current.has_method("bake") and current.has_method("create_brush_from_info"):
			return current
		current = current.get_parent()
	return null
