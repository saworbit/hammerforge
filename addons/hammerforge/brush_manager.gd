@tool
extends Node
class_name BrushManager

var brushes: Array = []


func add_brush(brush: Node3D) -> void:
	brushes.append(brush)


func remove_brush(brush: Node3D) -> void:
	brushes.erase(brush)


func clear_brushes() -> void:
	# List mirror only. HFBrushSystem owns node lifetime.
	brushes.clear()
