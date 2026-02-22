@tool
extends RefCounted
class_name HFVisgroupSystem

const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")

var root: Node3D

# Visgroups: name -> { "visible": bool, "color": Color }
var visgroups: Dictionary = {}

# Groups: name -> true (registry only; membership stored on nodes via meta)
var groups: Dictionary = {}


func _init(level_root: Node3D) -> void:
	root = level_root


# ===========================================================================
# Visgroup CRUD
# ===========================================================================


func create_visgroup(vg_name: String, color: Color = Color.WHITE) -> void:
	if vg_name == "":
		return
	if not visgroups.has(vg_name):
		visgroups[vg_name] = {"visible": true, "color": color}


func remove_visgroup(vg_name: String) -> void:
	visgroups.erase(vg_name)
	for node in _all_managed_nodes():
		_remove_visgroup_meta(node, vg_name)
	refresh_visibility()


func rename_visgroup(old_name: String, new_name: String) -> void:
	if old_name == "" or new_name == "" or old_name == new_name:
		return
	if not visgroups.has(old_name):
		return
	visgroups[new_name] = visgroups[old_name]
	visgroups.erase(old_name)
	for node in _all_managed_nodes():
		var vgs: PackedStringArray = node.get_meta("visgroups", PackedStringArray())
		var idx = _find_in_packed(vgs, old_name)
		if idx >= 0:
			vgs[idx] = new_name
			node.set_meta("visgroups", vgs)


func set_visgroup_visible(vg_name: String, visible: bool) -> void:
	if not visgroups.has(vg_name):
		return
	visgroups[vg_name]["visible"] = visible
	refresh_visibility()


func set_visgroup_color(vg_name: String, color: Color) -> void:
	if not visgroups.has(vg_name):
		return
	visgroups[vg_name]["color"] = color


func get_visgroup_names() -> PackedStringArray:
	var out = PackedStringArray()
	for key in visgroups.keys():
		out.append(str(key))
	return out


func is_visgroup_visible(vg_name: String) -> bool:
	if not visgroups.has(vg_name):
		return true
	return bool(visgroups[vg_name].get("visible", true))


# ===========================================================================
# Visgroup membership
# ===========================================================================


func add_to_visgroup(node: Node, vg_name: String) -> void:
	if not node or vg_name == "":
		return
	if not visgroups.has(vg_name):
		create_visgroup(vg_name)
	var vgs: PackedStringArray = node.get_meta("visgroups", PackedStringArray())
	if _find_in_packed(vgs, vg_name) < 0:
		vgs.append(vg_name)
		node.set_meta("visgroups", vgs)


func remove_from_visgroup(node: Node, vg_name: String) -> void:
	if not node or vg_name == "":
		return
	_remove_visgroup_meta(node, vg_name)


func get_visgroups_of(node: Node) -> PackedStringArray:
	if not node:
		return PackedStringArray()
	return node.get_meta("visgroups", PackedStringArray())


func get_members_of(vg_name: String) -> Array:
	var out: Array = []
	for node in _all_managed_nodes():
		var vgs: PackedStringArray = node.get_meta("visgroups", PackedStringArray())
		if _find_in_packed(vgs, vg_name) >= 0:
			out.append(node)
	return out


# ===========================================================================
# Visibility refresh
# ===========================================================================


func refresh_visibility() -> void:
	for node in _all_managed_nodes():
		var vgs: PackedStringArray = node.get_meta("visgroups", PackedStringArray())
		if vgs.is_empty():
			continue
		var should_show := true
		for vg_name in vgs:
			if visgroups.has(vg_name) and not bool(visgroups[vg_name].get("visible", true)):
				should_show = false
				break
		node.visible = should_show


# ===========================================================================
# Group CRUD
# ===========================================================================


func create_group(group_name: String) -> void:
	if group_name == "":
		return
	groups[group_name] = true


func remove_group(group_name: String) -> void:
	groups.erase(group_name)
	for node in _all_managed_nodes():
		if str(node.get_meta("group_id", "")) == group_name:
			node.set_meta("group_id", "")


func get_group_names() -> PackedStringArray:
	var out = PackedStringArray()
	for key in groups.keys():
		out.append(str(key))
	return out


# ===========================================================================
# Group membership
# ===========================================================================


func group_selection(group_name: String, nodes: Array) -> void:
	if group_name == "":
		return
	create_group(group_name)
	for node in nodes:
		if node is Node:
			node.set_meta("group_id", group_name)


func ungroup_nodes(nodes: Array) -> void:
	for node in nodes:
		if node is Node:
			var old_group = str(node.get_meta("group_id", ""))
			node.set_meta("group_id", "")
			if old_group != "":
				_cleanup_empty_group(old_group)


func get_group_of(node: Node) -> String:
	if not node:
		return ""
	return str(node.get_meta("group_id", ""))


func get_group_members(group_name: String) -> Array:
	var out: Array = []
	if group_name == "":
		return out
	for node in _all_managed_nodes():
		if str(node.get_meta("group_id", "")) == group_name:
			out.append(node)
	return out


# ===========================================================================
# Serialization
# ===========================================================================


func capture_visgroups() -> Dictionary:
	var out: Dictionary = {}
	for key in visgroups.keys():
		var vg = visgroups[key]
		out[key] = {
			"visible": bool(vg.get("visible", true)),
			"color": [vg.get("color", Color.WHITE).r, vg.get("color", Color.WHITE).g, vg.get("color", Color.WHITE).b, vg.get("color", Color.WHITE).a]
		}
	return out


func restore_visgroups(data: Dictionary) -> void:
	visgroups.clear()
	if not data is Dictionary:
		return
	for key in data.keys():
		var entry = data[key]
		if not entry is Dictionary:
			continue
		var color = Color.WHITE
		var c_arr = entry.get("color", [1, 1, 1, 1])
		if c_arr is Array and c_arr.size() >= 4:
			color = Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]), float(c_arr[3]))
		visgroups[str(key)] = {
			"visible": bool(entry.get("visible", true)),
			"color": color
		}
	refresh_visibility()


func capture_groups() -> Dictionary:
	return groups.duplicate()


func restore_groups(data: Dictionary) -> void:
	groups.clear()
	if data is Dictionary:
		for key in data.keys():
			groups[str(key)] = true


# ===========================================================================
# Helpers
# ===========================================================================


func _all_managed_nodes() -> Array:
	var out: Array = []
	if root.has_method("_iter_pick_nodes"):
		out.append_array(root._iter_pick_nodes())
	if root.get("entities_node"):
		var entities_node = root.get("entities_node")
		if entities_node is Node:
			for child in entities_node.get_children():
				if not out.has(child):
					out.append(child)
	return out


func _remove_visgroup_meta(node: Node, vg_name: String) -> void:
	var vgs: PackedStringArray = node.get_meta("visgroups", PackedStringArray())
	var idx = _find_in_packed(vgs, vg_name)
	if idx >= 0:
		var new_vgs = PackedStringArray()
		for i in range(vgs.size()):
			if i != idx:
				new_vgs.append(vgs[i])
		node.set_meta("visgroups", new_vgs)


func _find_in_packed(arr: PackedStringArray, value: String) -> int:
	for i in range(arr.size()):
		if arr[i] == value:
			return i
	return -1


func _cleanup_empty_group(group_name: String) -> void:
	if group_name == "" or not groups.has(group_name):
		return
	var members = get_group_members(group_name)
	if members.is_empty():
		groups.erase(group_name)
