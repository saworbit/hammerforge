@tool
class_name HFSweepSelect
extends RefCounted
## Sweep select (#1886): hold the sweep key and drag in the Select tool, and every
## brush the cursor passes over joins the selection, the moment it is passed. A
## rectangle takes everything inside it, so the trim along one wall or a run of
## pillars took a Shift+click on each, and a missed click picked the wrong brush.
##
## If the first brush passed over was selected already, the sweep takes brushes
## out instead. Each point picks the front brush, as a click does, so nothing
## behind it is taken, and a hidden or locked one is passed by. One member of a
## group takes the whole group, as a click does. In Face Select the same drag adds
## or removes faces. Escape or a right click during the drag puts the selection
## back as it was before it.

var active := false
## Whether this sweep takes out what it passes over, decided by the first thing
## it passes.
var removing := false
var faces := false
var _decided := false
var _before_nodes: Array = []
var _before_faces: Dictionary = {}
## What it has passed over already: a node, a group's name, or a face.
var _passed: Dictionary = {}


func begin(face_mode: bool, selection: Array, face_selection: Dictionary) -> void:
	active = true
	faces = face_mode
	removing = false
	_decided = false
	_before_nodes = selection.duplicate()
	_before_faces = face_selection.duplicate(true)
	_passed.clear()


## Take or leave what is under `position`. True when the selection changed.
func sweep(plugin: Object, root: Node, camera: Camera3D, position: Vector2) -> bool:
	if not active or root == null or camera == null:
		return false
	if faces:
		return _sweep_face(plugin, root, camera, position)
	return _sweep_brush(plugin, root, camera, position)


func _sweep_brush(plugin: Object, root: Node, camera: Camera3D, position: Vector2) -> bool:
	var brush = root.pick_brush(camera, position, false)
	if brush == null or not is_instance_valid(brush):
		return false
	var visgroups = root.get("visgroup_system")
	if visgroups and visgroups.is_locked(brush):
		return false
	var unit := ""
	if visgroups:
		unit = str(visgroups.selection_unit_of(brush))
	var key: Variant = unit if unit != "" else brush
	if _passed.has(key):
		return false
	_passed[key] = true
	var nodes: Array = visgroups.group_members_deep(unit) if unit != "" else [brush]
	var selection: Array = plugin.get("hf_selection")
	if not _decided:
		removing = selection.has(brush)
		_decided = true
	var changed := false
	for node in nodes:
		if removing and selection.has(node):
			selection.erase(node)
			changed = true
		elif not removing and not selection.has(node):
			selection.append(node)
			changed = true
	if changed:
		plugin.call("_apply_hf_selection", plugin.call("get_editor_interface").get_selection())
	return changed


func _sweep_face(plugin: Object, root: Node, camera: Camera3D, position: Vector2) -> bool:
	var hit: Dictionary = root.pick_face(camera, position)
	var brush = hit.get("brush")
	var index := int(hit.get("face_idx", -1))
	if brush == null or index < 0:
		return false
	var visgroups = root.get("visgroup_system")
	if visgroups and visgroups.is_locked(brush):
		return false
	var brush_key: String = plugin.call("_face_key_for", brush)
	var key := "%s:%d" % [brush_key, index]
	if _passed.has(key):
		return false
	_passed[key] = true
	var picked: Dictionary = (root.face_selection as Dictionary).duplicate(true)
	var indices: Array = picked.get(brush_key, []).duplicate()
	if not _decided:
		removing = indices.has(index)
		_decided = true
	if removing == indices.has(index):
		if removing:
			indices.erase(index)
		else:
			indices.append(index)
	else:
		return false
	if indices.is_empty():
		picked.erase(brush_key)
	else:
		picked[brush_key] = indices
	plugin.call("_apply_face_selection", root, picked)
	return true


## Put the selection back as it was before the sweep, and end it.
func cancel(plugin: Object, root: Node) -> void:
	if not active:
		return
	active = false
	if faces:
		if root != null and is_instance_valid(root):
			plugin.call("_apply_face_selection", root, _before_faces.duplicate(true))
		return
	var selection: Array = plugin.get("hf_selection")
	selection.clear()
	for node in _before_nodes:
		if is_instance_valid(node):
			selection.append(node)
	plugin.call("_apply_hf_selection", plugin.call("get_editor_interface").get_selection())


func finish() -> void:
	active = false
	_passed.clear()
