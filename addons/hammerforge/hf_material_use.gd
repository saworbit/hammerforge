@tool
extends RefCounted
## Which materials the open level uses, and where (#1725).
##
## In a project with hundreds of materials nothing showed which ones the level
## used, and there was no way back from a material to its faces. The counts are
## worked out once per change to the level's faces and kept on the level, so the
## browser can ask on every redraw without walking every face each time.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const HFBrushSystemType = preload("systems/hf_brush_system.gd")
@warning_ignore_restore("shadowed_global_identifier")


## `{palette slot: faces using it}` for every brush in the level, cut or solid.
## Worked out again only after `invalidate()`, which every face change makes
## through `LevelRoot.tag_brush_dirty()`, or when the number of brushes moved.
## Kept in the level's `material_use_cache`, which is never saved.
static func counts(root: Node) -> Dictionary:
	if root == null or not (root.get("material_use_cache") is Dictionary):
		return {}
	var cache: Dictionary = root.material_use_cache
	var brushes := _brushes(root)
	if int(cache.get("brushes", -1)) == brushes.size():
		return cache["counts"]
	var out: Dictionary = {}
	for brush in brushes:
		for face in brush.faces:
			if face == null:
				continue
			var slot := int(face.material_idx)
			out[slot] = int(out.get(slot, 0)) + 1
	cache["brushes"] = brushes.size()
	cache["counts"] = out
	cache["passes"] = int(cache.get("passes", 0)) + 1
	return out


## Forget the counts; the next `counts()` works them out again.
static func invalidate(root: Node) -> void:
	if root != null and root.get("material_use_cache") is Dictionary:
		(root.material_use_cache as Dictionary).erase("brushes")


## How many times the counts were worked out, for the tests.
static func passes(root: Node) -> int:
	if root == null or not (root.get("material_use_cache") is Dictionary):
		return 0
	return int(root.material_use_cache.get("passes", 0))


## The faces of visible, unlocked brushes using `slot`, keyed as
## `LevelRoot.face_selection` is.
static func faces_using(root: Node, slot: int) -> Dictionary:
	var out: Dictionary = {}
	for brush in _brushes(root):
		if not _pickable(root, brush):
			continue
		var indices: Array = []
		for i in brush.faces.size():
			var face = brush.faces[i]
			if face != null and int(face.material_idx) == slot:
				indices.append(i)
		if not indices.is_empty():
			out[_face_key(root, brush)] = indices
	return out


## The visible, unlocked brushes with a face using `slot`.
static func brushes_using(root: Node, slot: int) -> Array:
	var out: Array = []
	for brush in _brushes(root):
		if not _pickable(root, brush):
			continue
		for face in brush.faces:
			if face != null and int(face.material_idx) == slot:
				out.append(brush)
				break
	return out


static func _brushes(root: Node) -> Array:
	var out: Array = []
	for container in [root.get("draft_brushes_node"), root.get("pending_node")]:
		if container == null:
			continue
		for child in container.get_children():
			if child is DraftBrush:
				out.append(child)
	return out


static func _pickable(root: Node, brush: DraftBrush) -> bool:
	if not brush.is_visible_in_tree():
		return false
	var locks = root.get("visgroup_system")
	return locks == null or not locks.is_locked(brush)


static func _face_key(_root: Node, brush: DraftBrush) -> String:
	return HFBrushSystemType.face_key(brush)
