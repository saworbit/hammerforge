@tool
extends Node
class_name MaterialManager

@export var materials: Array[Material] = []

## Path to the last saved/loaded material library (for auto-reload).
var _library_path := ""

## Paths from the last `load_library()` that did not resolve, in slot order.
## Their slots are still in `materials`, holding null, because `FaceData`
## `material_idx` indexes this array and compacting it would repaint the level.
var _missing_paths: Array[String] = []
var _dropped_slots: Array[int] = []


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
##
## A library records each slot's `resource_path`, so a material with no path
## cannot be recorded. That is every material made in the editor session through
## the Materials tab's Add button: the slot is written as an empty string and
## comes back `null`. The load side says so per slot and in a summary; this used
## to write the empty string in silence and report `OK`, so the first anyone
## heard of it was a load that restored nothing.
##
## Returns `ERR_SKIP` when the palette had materials and none of them could be
## recorded, because that file restores nothing. `get_dropped_save_slots()` has
## the slot numbers either way.
func save_library(path: String) -> int:
	var paths: Array = []
	_dropped_slots.clear()
	var recorded := 0
	for index in materials.size():
		var mat: Material = materials[index]
		if mat and mat.resource_path != "":
			paths.append(mat.resource_path)
			recorded += 1
		else:
			paths.append("")
			if mat != null:
				_dropped_slots.append(index)
	var json = JSON.stringify({"version": 1, "materials": paths})
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ERR_CANT_OPEN
	file.store_string(json)
	file.close()
	_library_path = path
	if not _dropped_slots.is_empty():
		HFLog.warn(
			(
				(
					"%s: %d of %d materials have no resource path and were saved as empty slots. "
					+ "A material created in the editor has to be saved to disk before a library "
					+ "can reference it."
				)
				% [path, _dropped_slots.size(), materials.size()]
			)
		)
	if recorded == 0 and not materials.is_empty():
		return ERR_SKIP
	return OK


## Slot numbers from the last `save_library()` that held a material with no
## resource path, and so were written as empty. The save-side counterpart to
## `get_missing_library_paths()`.
func get_dropped_save_slots() -> Array[int]:
	return _dropped_slots.duplicate()


## Load a material palette from a JSON file.
func load_library(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	var mat_paths: Array = parsed.get("materials", [])
	materials.clear()
	_missing_paths.clear()
	for mat_path in mat_paths:
		var p := str(mat_path)
		if p == "" or not ResourceLoader.exists(p):
			# Preserve slot with null placeholder so indices stay stable.
			materials.append(null)
			_missing_paths.append(p)
			continue
		var res = ResourceLoader.load(p)
		if res is Material:
			materials.append(res)
		else:
			materials.append(null)
			_missing_paths.append(p)
	_library_path = path
	if not _missing_paths.is_empty():
		# Preserving the slots is right; saying nothing about them is not. The
		# level's own validator reports one issue per null entry, but only if
		# somebody runs it, and the natural moment to say so is the load.
		for missing in _missing_paths:
			HFLog.warn(
				(
					"%s: material '%s' could not be found. Its palette slot is empty."
					% [path, missing if missing != "" else "<blank path>"]
				)
			)
		HFLog.warn(
			(
				"%s: %d of %d materials in this library could not be found."
				% [path, _missing_paths.size(), materials.size()]
			)
		)
	return true


## Paths from the last `load_library()` that did not resolve. Empty when every
## material was found, and after a load that failed before it read any.
func get_missing_library_paths() -> Array[String]:
	return _missing_paths.duplicate()


## How many palette slots hold no material. The status board reports this beside
## the loaded count, because a palette of unresolved slots is not an empty
## palette: those slots are the ones every face indexes.
func get_missing_count() -> int:
	var missing := 0
	for mat in materials:
		if mat == null:
			missing += 1
	return missing


## Returns the path of the last saved/loaded library, or empty string.
func get_library_path() -> String:
	return _library_path
