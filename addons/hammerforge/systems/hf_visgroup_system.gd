@tool
extends RefCounted
class_name HFVisgroupSystem

const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")

var root: Node3D

# Visgroups: name -> { "visible": bool }
var visgroups: Dictionary = {}

# Groups: name -> true (registry only; membership stored on nodes via meta)
var groups: Dictionary = {}


func _init(level_root: Node3D) -> void:
	root = level_root


# ===========================================================================
# Visgroup CRUD
# ===========================================================================


func create_visgroup(vg_name: String) -> void:
	# The guard tested the wrong thing: "" was refused and "   " was not, so a
	# visgroup could exist that shows in the dock as a blank row, cannot be told
	# apart from another blank one, and is saved into the `.hflevel` on its
	# members. Stored stripped as well, so "lights" and "lights " are one
	# visgroup rather than two a keystroke apart.
	var stripped := vg_name.strip_edges()
	if stripped == "":
		return
	if not visgroups.has(stripped):
		visgroups[stripped] = {"visible": true}


func remove_visgroup(vg_name: String) -> void:
	visgroups.erase(vg_name)
	for node in _all_managed_nodes():
		_remove_visgroup_meta(node, vg_name)
	refresh_visibility()


## Rename a visgroup. Returns whether it happened.
##
## Refuses a name another visgroup already has. Without that guard, renaming A to
## an existing B overwrote B's record, visibility and all, and then
## rewrote the name on every node that carried A, so the two memberships silently
## became one. The user asked to rename one visgroup and lost a different one,
## and the loss showed up later: B's members were hidden, B's record was gone,
## and the next refresh_visibility() made them visible again with nothing in the
## UI to say why.
##
## Merging two visgroups is a different operation, and one somebody should have
## to ask for by name.
func rename_visgroup(old_name: String, new_name: String) -> bool:
	new_name = new_name.strip_edges()
	if old_name == "" or new_name == "" or old_name == new_name:
		return false
	if not visgroups.has(old_name):
		return false
	if visgroups.has(new_name):
		return false
	visgroups[new_name] = visgroups[old_name]
	visgroups.erase(old_name)
	for node in _all_managed_nodes():
		var vgs: PackedStringArray = node.get_meta("visgroups", PackedStringArray())
		var idx = _find_in_packed(vgs, old_name)
		if idx >= 0:
			vgs[idx] = new_name
			node.set_meta("visgroups", vgs)
	return true


func set_visgroup_visible(vg_name: String, visible: bool) -> void:
	if not visgroups.has(vg_name):
		return
	visgroups[vg_name]["visible"] = visible
	refresh_visibility()


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
			# A node in no visgroup is a node nothing is hiding. Skipping it left
			# a deleted visgroup's members with the visible = false they were
			# given when it was hidden, and no visgroup left to un-hide them
			# with. Committed cutters are hidden by the cut, not by a visgroup,
			# and _all_managed_nodes() does not reach them.
			node.visible = true
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
	# The same guard create_visgroup() got, for the same reasons, and worse here:
	# a group is the unit the editor moves and duplicates together. "Arch" and
	# "Arch " are two groups, so half the brushes the mapper thinks they grouped
	# move without the other half — and the group list looks right, because both
	# rows read "Arch". A group named "   " is a blank row that cannot be told
	# from another blank one. The name is stored in node meta and saved into the
	# `.hflevel`, so it persists.
	var stripped := group_name.strip_edges()
	if stripped == "":
		return
	groups[stripped] = true


func remove_group(group_name: String) -> void:
	group_name = group_name.strip_edges()
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
	# Stripped here as well, or the meta and the registry disagree about which
	# group the node is in. get_group_members() and get_group_of() compare
	# against this meta, so they follow from it.
	var stripped := group_name.strip_edges()
	if stripped == "":
		return
	create_group(stripped)
	for node in nodes:
		if node is Node:
			node.set_meta("group_id", stripped)


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
	group_name = group_name.strip_edges()
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
		out[key] = {"visible": bool(vg.get("visible", true))}
	return out


## The order the mapper made these in.
##
## `capture_visgroups()` and `capture_groups()` both hand back a Dictionary, and
## a level bundle is JSON, where `JSON.stringify` sorts object keys. So every
## name survived a round trip and the list came back alphabetised, and reshuffled
## again the moment a new one was added (#706). The order is not arbitrary: on a
## real map it is roughly the order the level was built, and the thing being
## worked on today ends up at the bottom where it is easy to find.
##
## Recorded beside the registry rather than inside it, so a name can be anything
## - including a name that looks like a bookkeeping key.
func capture_order(registry: Dictionary) -> Array:
	var order: Array = []
	for key in registry.keys():
		order.append(str(key))
	return order


func restore_visgroups(data: Dictionary, order: Array = []) -> void:
	visgroups.clear()
	if not data is Dictionary:
		return
	for key in _ordered_keys(data, order):
		var entry = data[key]
		if not entry is Dictionary:
			continue
		# A "color" key in an older payload is read past. It was carried through
		# every layer - created, stored, saved, loaded, and given a setter - and
		# nothing ever read one, so there is nothing to restore it into.
		visgroups[str(key)] = {"visible": bool(entry.get("visible", true))}
	refresh_visibility()


## `data`'s keys, in `order` first and then whatever `order` did not mention.
##
## A file written before the order was recorded has none, and falls through to
## the dictionary's own iteration, which is what it always did. A name in the
## order that is no longer in the data is skipped rather than resurrected.
func _ordered_keys(data: Dictionary, order: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for key in order:
		var name := str(key)
		if data.has(name) and not seen.has(name):
			seen[name] = true
			out.append(name)
	for key in data.keys():
		var name := str(key)
		if not seen.has(name):
			seen[name] = true
			out.append(name)
	return out


## Put back any visgroup that its own members still name. Returns how many.
##
## Membership is node metadata and has always survived a `.tscn`; the registry
## did not, so a scene saved before `LevelRoot.live_registries` existed reopens
## with brushes claiming a visgroup the dock has never heard of. If that visgroup
## was hidden when the scene was saved, the brushes come back invisible with
## nothing that can show them (#664).
##
## A recovered visgroup is visible. The `visible` flag is not recoverable from
## the members, and of the two directions this is the one that does not leave
## geometry the mapper cannot reach.
func reconcile_visgroups_from_members() -> int:
	var added := 0
	for node in _all_managed_nodes():
		if not is_instance_valid(node):
			continue
		var vgs: PackedStringArray = node.get_meta("visgroups", PackedStringArray())
		for vg_name in vgs:
			var stripped := str(vg_name).strip_edges()
			if stripped == "" or visgroups.has(stripped):
				continue
			visgroups[stripped] = {"visible": true}
			added += 1
	if added > 0:
		refresh_visibility()
	return added


func capture_groups() -> Dictionary:
	return groups.duplicate()


func restore_groups(data: Dictionary, order: Array = []) -> void:
	groups.clear()
	if data is Dictionary:
		for key in _ordered_keys(data, order):
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
