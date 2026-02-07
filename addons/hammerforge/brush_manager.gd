@tool
extends Node
class_name BrushManager

var brushes: Array = []


func add_brush(brush: Node3D) -> void:
	brushes.append(brush)


func remove_brush(brush: Node3D) -> void:
	brushes.erase(brush)


func clear_brushes() -> void:
	for brush in brushes:
		if brush.is_inside_tree():
			brush.queue_free()
	brushes.clear()
