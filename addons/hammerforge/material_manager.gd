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


## Whether the palette already holds exactly these materials, in this order.
##
## By identity rather than by value, because that is the question worth asking:
## the same `Material` object in the same slot paints the same faces the same
## way, and two different objects that happen to look alike would still have to
## be swapped in. A material edited in place is the same object, and the level is
## already showing the edit.
##
## Exists so a restore can tell whether the palette is part of what changed.
## `LevelRoot.set_materials()` ends in a rebuild of every brush preview in the
## level, and an undo was paying for that whether or not the palette had been
## touched (#705).
func palette_matches(other: Array) -> bool:
	if other.size() != materials.size():
		return false
	for i in materials.size():
		if materials[i] != other[i]:
			return false
	return true


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


## Whether `path` holds a library this can read.
##
## Asked before the load is committed as an undo action. `load_library()` only
## refuses on these four things, and all of them can be known without touching
## the palette, so the caller can report a bad file rather than opening an undo
## step for a load that never happened.
##
## It has to refuse exactly what the load refuses, or it answers a different
## question from the one the caller is about to ask: a file this cleared and the
## load then rejected is a pre-flight that passed a file nothing can read.
static func library_is_readable(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed is Dictionary and _material_paths_of(parsed) != null


## The list of paths a parsed library holds, or null when it does not hold one.
##
## `materials` is a list of resource paths. A file with something else under that
## key is not a palette, and assigning it to a typed `Array` is a runtime error
## rather than a refusal: the function unwound, a `-> bool` call handed back
## null, and callers that tested the result got a falsy value by luck rather than
## by design (#739). `status-board` had the detector for this written already and
## never reached it, because the throw unwound the scenario too.
static func _material_paths_of(parsed: Dictionary):
	if not parsed.has("materials"):
		return []
	var raw = parsed["materials"]
	return raw if raw is Array else null


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
	var raw_paths = _material_paths_of(parsed)
	if raw_paths == null:
		HFLog.warn("%s: the 'materials' key is not a list, so this file is not a palette." % path)
		return false
	var mat_paths: Array = raw_paths
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
