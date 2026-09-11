@tool
extends Node
class_name MaterialManager

@export var materials: Array[Material] = []

## Path to the last saved/loaded material library (for auto-reload).
var _library_path := ""


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


# ---------------------------------------------------------------------------
# Material Library Persistence
# ---------------------------------------------------------------------------


## Save the current material palette to a JSON file.
## Stores the resource_path of each material so they can be reloaded.
func save_library(path: String) -> int:
	var paths: Array = []
	for mat in materials:
		if mat and mat.resource_path != "":
			paths.append(mat.resource_path)
		else:
			paths.append("")
	var json = JSON.stringify({"version": 1, "materials": paths})
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ERR_CANT_OPEN
	file.store_string(json)
	_library_path = path
	return OK


## Load a material palette from a JSON file.
func load_library(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var text = file.get_as_text()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	var mat_paths: Array = parsed.get("materials", [])
	materials.clear()
	for mat_path in mat_paths:
		var p := str(mat_path)
		if p == "" or not ResourceLoader.exists(p):
			# Preserve slot with null placeholder so indices stay stable.
			materials.append(null)
			continue
		var res = ResourceLoader.load(p)
		if res is Material:
			materials.append(res)
		else:
			materials.append(null)
	_library_path = path
	return true


## Returns the path of the last saved/loaded library, or empty string.
func get_library_path() -> String:
	return _library_path
