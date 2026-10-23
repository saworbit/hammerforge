@tool
extends RefCounted
class_name HFVisgroupSystem

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")
const HFBakeSplit = preload("../hf_bake_split.gd")
@warning_ignore_restore("shadowed_global_identifier")

var root: Node3D

# Visgroups: name -> { "visible": bool, "cast_shadow": int, "bake": bool }.
# `cast_shadow` is how the visgroup's brushes cast shadows when they do not say
# themselves, or HFBakeSplit.LEVEL_DEFAULT (#1444). `bake` false leaves its
# members out of every bake and export while they stay visible and editable
# (#1732).
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
		visgroups[stripped] = _record(true)


## A visgroup's record. Every place that makes one comes here, so a field added
## to it reaches each of them.
static func _record(
	visible: bool, cast_shadow: int = HFBakeSplit.LEVEL_DEFAULT, bake: bool = true
) -> Dictionary:
	return {"visible": visible, "cast_shadow": cast_shadow, "bake": bake}


func remove_visgroup(vg_name: String) -> void:
	visgroups.erase(vg_name)
	if root and root.get("current_visgroup") == vg_name:
		root.current_visgroup = ""
	for node in _all_member_nodes():
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
	if root and root.get("current_visgroup") == old_name:
		root.current_visgroup = new_name
	for node in _all_member_nodes():
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


## How this visgroup's brushes cast shadows when they do not say themselves:
## one of `GeometryInstance3D.ShadowCastingSetting`, or `LEVEL_DEFAULT` to leave
## it to the level. False when nothing changed, or there is no such visgroup.
func set_visgroup_cast_shadow(vg_name: String, value: int) -> bool:
	if not visgroups.has(vg_name):
		return false
	if value != HFBakeSplit.LEVEL_DEFAULT and not HFBakeSplit.is_cast_shadow(value):
		return false
	if get_visgroup_cast_shadow(vg_name) == value:
		return false
	visgroups[vg_name]["cast_shadow"] = value
	return true


func get_visgroup_cast_shadow(vg_name: String) -> int:
	if not visgroups.has(vg_name):
		return HFBakeSplit.LEVEL_DEFAULT
	var value: Variant = visgroups[vg_name].get("cast_shadow", HFBakeSplit.LEVEL_DEFAULT)
	return int(value) if HFBakeSplit.is_cast_shadow(value) else HFBakeSplit.LEVEL_DEFAULT


## The Cast Shadows choices of the visgroups `node` is in, as `[name, setting]`
## pairs in the order of the visgroup list, the one the dock shows. The first
## decides for a brush that does not choose itself; more than one that differ is
## something Check Issues names.
func cast_shadow_overrides_of(node: Node) -> Array:
	var out: Array = []
	if not node:
		return out
	var member_of := get_visgroups_of(node)
	if member_of.is_empty():
		return out
	for vg_name in visgroups.keys():
		if _find_in_packed(member_of, str(vg_name)) < 0:
			continue
		var value := get_visgroup_cast_shadow(str(vg_name))
		if value != HFBakeSplit.LEVEL_DEFAULT:
			out.append([str(vg_name), value])
	return out


## Whether this visgroup's members go into a bake (#1732). False when it is left
## out; true for a name that is no visgroup.
func visgroup_bakes(vg_name: String) -> bool:
	if not visgroups.has(vg_name):
		return true
	return bool(visgroups[vg_name].get("bake", true))


## Leave this visgroup's members out of every bake and export, or put them back.
## False when nothing changed, or there is no such visgroup.
func set_visgroup_bakes(vg_name: String, bakes: bool) -> bool:
	if not visgroups.has(vg_name) or visgroup_bakes(vg_name) == bakes:
		return false
	visgroups[vg_name]["bake"] = bakes
	return true


## Whether a visgroup leaves `node` out of the bake: it is in one that is. The
## bake asks this for every brush through `brush_bakes()`, so the preview, a
## partial and a full bake agree.
func is_left_out_of_bake(node: Node) -> bool:
	for vg_name in get_visgroups_of(node):
		if not visgroup_bakes(vg_name):
			return true
	return false


## How many brushes and entities a visgroup leaves out of the bake, for an
## export to say it left them out.
func left_out_count() -> int:
	var count := 0
	for node in _all_managed_nodes():
		if is_left_out_of_bake(node):
			count += 1
	return count


## The visgroup new work joins, or "" for none (#1732). The level keeps it, as
## `LevelRoot.current_visgroup`, beside its settings rather than in its undo state,
## so undoing an edit never changes where the next brush goes.
func get_current_visgroup() -> String:
	var current := str(root.get("current_visgroup")) if root else ""
	return current if visgroups.has(current) else ""


## Put a placed or pasted piece, its brushes by id and its entities, in the
## current visgroup.
func join_current_all(brush_ids: Array, entity_nodes: Array) -> void:
	for brush_id in brush_ids:
		join_current(root.find_brush_by_id(str(brush_id)))
	for entity in entity_nodes:
		if entity is Node and is_instance_valid(entity):
			join_current(entity)


## Put `node`, new work, in the current visgroup, if there is one.
func join_current(node: Node) -> void:
	var current := get_current_visgroup()
	if current != "" and node:
		add_to_visgroup(node, current)
		if not is_visgroup_visible(current):
			node.visible = false


func get_visgroup_names() -> PackedStringArray:
	var out = PackedStringArray()
	for key in visgroups.keys():
		out.append(str(key))
	return out


func is_visgroup_visible(vg_name: String) -> bool:
	if not visgroups.has(vg_name):
		return true
	return bool(visgroups[vg_name].get("visible", true))


## Whether a visgroup hides this node: it is in one that is hidden. The rule
## refresh_visibility() draws by, and the one the bake reads for a committed
## cutter, which the cut hides and refresh_visibility() never reaches (#1245).
func is_hidden_by_visgroups(node: Node) -> bool:
	for vg_name in get_visgroups_of(node):
		if not is_visgroup_visible(vg_name):
			return true
	return false


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
	# A node in no visgroup is a node nothing is hiding, so it is shown. Skipping
	# it left a deleted visgroup's members with the visible = false they were
	# given when it was hidden, and no visgroup left to un-hide them with.
	# Committed cutters are hidden by the cut, not by a visgroup, and
	# _all_managed_nodes() does not reach them.
	for node in _all_managed_nodes():
		node.visible = not is_hidden_by_visgroups(node)


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
# Membership through a rebuild
# ===========================================================================


## The visgroups and group a node is in, as a rebuild carries them over.
##
## A prefab copy's Pull or variant switch and a generator's Update delete nodes and
## make new ones, which are in nothing until they are given back what the old
## ones were in, and a hidden copy or structure showed (#1190, #1201).
func membership_of(node: Node) -> Dictionary:
	var vgs: PackedStringArray = node.get_meta("visgroups", PackedStringArray())
	return {"visgroups": vgs.duplicate(), "group_id": str(node.get_meta("group_id", ""))}


## What every one of `memberships` is in: the visgroups they all name, and the
## group when they are all in one. A node a rebuild adds joins this. Empty when
## there are none.
func shared_membership(memberships: Array) -> Dictionary:
	var shared: Dictionary = {}
	for membership in memberships:
		if shared.is_empty():
			shared = membership.duplicate(true)
			continue
		var common := PackedStringArray()
		for vg_name in shared["visgroups"]:
			if vg_name in membership["visgroups"]:
				common.append(vg_name)
		shared["visgroups"] = common
		if shared["group_id"] != membership["group_id"]:
			shared["group_id"] = ""
	return shared


## Put a node made by a rebuild in the visgroups and group of the one it replaces,
## hidden if one of those visgroups is.
func give_back_membership(node: Node, membership: Dictionary) -> void:
	var vgs: PackedStringArray = membership.get("visgroups", PackedStringArray())
	if not vgs.is_empty():
		node.set_meta("visgroups", vgs.duplicate())
		for vg_name in vgs:
			if not is_visgroup_visible(vg_name):
				node.visible = false
	var group := str(membership.get("group_id", ""))
	if group != "":
		node.set_meta("group_id", group)


# ===========================================================================
# Serialization
# ===========================================================================


func capture_visgroups() -> Dictionary:
	var out: Dictionary = {}
	for key in visgroups.keys():
		out[key] = _record(
			bool(visgroups[key].get("visible", true)),
			get_visgroup_cast_shadow(key),
			visgroup_bakes(key)
		)
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
		var cast: Variant = entry.get("cast_shadow", HFBakeSplit.LEVEL_DEFAULT)
		visgroups[str(key)] = _record(
			bool(entry.get("visible", true)),
			int(cast) if HFBakeSplit.is_cast_shadow(cast) else HFBakeSplit.LEVEL_DEFAULT,
			not (entry.get("bake") is bool) or bool(entry["bake"])
		)
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
			visgroups[stripped] = _record(true)
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


## Every node that can be in a visgroup, committed cuts included. They are not
## drawn or picked, so `_all_managed_nodes()` leaves them out, but the bake reads
## their visgroups (#1245), so a rename or a remove has to reach them too.
func _all_member_nodes() -> Array:
	var out := _all_managed_nodes()
	var committed: Variant = root.get("committed_node")
	if committed is Node:
		for child in (committed as Node).get_children():
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
