@tool
extends Node
class_name MaterialManager

@export var materials: Array[Material] = []

func get_material(index: int) -> Material:
	if index >= 0 and index < materials.size():
		return materials[index]
	return null

func add_material(material: Material) -> int:
	if material == null:
		return -1
	materials.append(material)
	return materials.size() - 1

func remove_material(index: int) -> void:
	if index < 0 or index >= materials.size():
		return
	materials.remove_at(index)

func clear() -> void:
	materials.clear()

func get_material_names() -> Array[String]:
	var names: Array[String] = []
	for mat in materials:
		if mat == null:
			names.append("<null>")
			continue
		var label = mat.resource_name
		if label == "":
			label = mat.resource_path.get_file()
		if label == "":
			label = "Material"
		names.append(label)
	return names
