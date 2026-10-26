@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Named, nested groups (#1723, #1881) and how every way of copying them makes
## new ones (#1897, #1904).
##
## Asks whether Duplicate, Paste and a prefab placed twice each make groups of
## their own; whether every group command comes back through an undo and a redo
## and a `.hflevel`; what a hand-edited cycle does to the walks; and what the
## operations that replace brushes (Merge, Hollow) do to the group the brushes
## were the last of.

const HFPrefab = preload("res://addons/hammerforge/hf_prefab.gd")
const HFPrefabSystem = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")

const SAVE_PATH := "user://vibe_nested_groups.hflevel"
const CLIP_PATH := "user://vibe_nested_groups_clipboard.hfprefab"


func id() -> String:
	return "nested-groups"


func summary() -> String:
	return "nested groups through copies, undo, save and edge cases"


func expected_issues() -> Array[int]:
	return [1975]


func run() -> void:
	await _duplicate_twice()
	await _group_edits_through_undo()
	await _save_and_load()
	await _paste_and_prefab_twice()
	await _hand_edited_cycle()
	await _delete_and_merge_members()
	await _rename_edges()
	for path in [SAVE_PATH, CLIP_PATH, CLIP_PATH.get_basename() + ".map"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## A roof group and a wall group in a house group. `gap` 2 puts each pair face
## to face, so the two can be merged.
func _house(root: Node3D, at: Vector3, gap: float = 4.0) -> Array:
	var vg = root.visgroup_system
	var roof_a := box(root, Vector3(2, 2, 2), at + Vector3(0, 6, 0))
	var roof_b := box(root, Vector3(2, 2, 2), at + Vector3(gap, 6, 0))
	var wall_a := box(root, Vector3(2, 2, 2), at + Vector3(0, 2, 0))
	var wall_b := box(root, Vector3(2, 2, 2), at + Vector3(gap, 2, 0))
	vg.group_units("Roof", [roof_a, roof_b])
	vg.group_units("Walls", [wall_a, wall_b])
	vg.group_units("House", [roof_a, wall_a])
	return [roof_a, roof_b, wall_a, wall_b]


func _chains(root: Node3D, nodes: Array) -> Array:
	var out: Array = []
	for node in nodes:
		out.append(" < ".join(root.visgroup_system.group_chain_of(node)))
	out.sort()
	return out


## The whole group picture, by brush id: the registry in order, the nesting and
## each brush's own group.
func _picture(root: Node3D) -> String:
	var vg = root.visgroup_system
	var members: Array = []
	for b in root.draft_brushes_node.get_children():
		members.append("%s=%s" % [_bid(b), str(b.get_meta("group_id", ""))])
	members.sort()
	return (
		HFVibe
		. canonical(
			{
				"groups": Array(vg.get_group_names()),
				"parents": vg.group_parents,
				"members": members,
			}
		)
	)


func _duplicate(root: Node3D, nodes: Array, shift: Vector3) -> Array:
	var infos: Array = []
	for node in nodes:
		var info: Dictionary = root.build_duplicate_info(node, shift)
		if not info.is_empty():
			infos.append(info)
	var made: Dictionary = root.visgroup_system.regroup_copies(nodes, infos, [])
	root.create_managed_duplicates(infos, [], made)
	var out: Array = []
	for info in infos:
		var b = root.find_brush_by_id(str(info.get("brush_id", "")))
		if b:
			out.append(b)
	return out


func _duplicate_twice() -> void:
	var root: Node3D = await fresh_root()
	var parts := _house(root, Vector3(20, 0, 0))
	var first := _duplicate(root, parts, Vector3(0, 0, 10))
	var second := _duplicate(root, parts, Vector3(0, 0, 20))
	note("Duplicate twice: first copies", _chains(root, first))
	note("Duplicate twice: second copies", _chains(root, second))
	if _chains(root, first) == _chains(root, second):
		flag("two Duplicates of one group share their copy groups", _chains(root, second))
	await drop_root(root)


## Each group command, undone and redone the way the plugin's undo does it:
## capture before, act, capture after, restore one then the other.
func _group_edits_through_undo() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var part_ids: Array = []
	for p in _house(root, Vector3.ZERO):
		part_ids.append(_bid(p))
	var loose_id := _bid(box(root, Vector3(2, 2, 2), Vector3(12, 2, 0)))
	var steps: Array = [
		["group a whole group with a loose brush", "street"],
		["ungroup the outer group", "ungroup"],
		["add the loose brush to Roof", "add"],
		["rename Roof", "rename"],
		["remove a roof brush from Attic with Attic open", "remove"],
		["remove_group Walls", "remove_group"],
	]
	for step in steps:
		var before_state: Dictionary = root.capture_state()
		var before := _picture(root)
		# A restore rebuilds what it changed, so look the nodes up again.
		var parts: Array = []
		for id in part_ids:
			parts.append(root.find_brush_by_id(id))
		var loose: Node = root.find_brush_by_id(loose_id)
		match step[1]:
			"street":
				vg.group_units("Street", [parts[0], loose])
			"ungroup":
				vg.ungroup_units([parts[0]])
			"add":
				vg.add_units_to_group([loose], "Roof")
			"rename":
				vg.rename_group("Roof", "Attic")
			"remove":
				vg.set_open_group("Attic")
				vg.remove_units_from_group([parts[1]], "Attic")
				vg.set_open_group("")
			"remove_group":
				vg.remove_group("Walls")
		await frame()
		var after_state: Dictionary = root.capture_state()
		var after := _picture(root)
		note(step[0], after)
		if before == after:
			note("  -- changed nothing")
		root.restore_state(before_state)
		await frame()
		var undone := _picture(root)
		if undone != before:
			flag(
				"undo of '%s' does not give the groups back" % step[0],
				"%s\n   vs %s" % [undone, before]
			)
		root.restore_state(after_state)
		await frame()
		var redone := _picture(root)
		if redone != after:
			flag(
				"redo of '%s' does not make the groups again" % step[0],
				"%s\n   vs %s" % [redone, after]
			)
		for problem in HFVibe.check_invariants(root):
			flag("after '%s': %s" % [step[0], problem])
	await drop_root(root)


func _save_and_load() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	_house(root, Vector3.ZERO)
	vg.set_open_group("Roof")
	var before := _picture(root)
	root.save_hflevel(SAVE_PATH, true)
	await HFVibe.settle_save(_tree, root)
	await drop_root(root)
	var other: Node3D = await fresh_root("Loaded")
	other.load_hflevel(SAVE_PATH)
	await frame()
	var after := _picture(other)
	note("open group after load", "'%s'" % other.visgroup_system.open_group)
	if before != after:
		flag("a .hflevel round trip changed the groups", "%s\n   vs %s" % [before, after])
	if other.visgroup_system.open_group != "":
		flag("an open group came back open after a load", other.visgroup_system.open_group)
	await drop_root(other)


## Paste and a prefab placed twice: each copy a group of its own.
func _paste_and_prefab_twice() -> void:
	var old_clip: String = HFPrefabSystem.clipboard_path
	var old_stand_in: Variant = HFPrefabSystem.system_clipboard_stand_in
	HFPrefabSystem.clipboard_path = CLIP_PATH
	HFPrefabSystem.system_clipboard_stand_in = ""
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var parts := _house(root, Vector3.ZERO)
	root.prefab_system.copy_to_clipboard(parts, [])
	var first: Dictionary = root.prefab_system.paste_from_clipboard(Vector3(0, 0, 20))
	var second: Dictionary = root.prefab_system.paste_from_clipboard(Vector3(0, 0, 40))
	var first_nodes: Array = []
	for id in first.get("brush_ids", []):
		first_nodes.append(root.find_brush_by_id(id))
	var second_nodes: Array = []
	for id in second.get("brush_ids", []):
		second_nodes.append(root.find_brush_by_id(id))
	note("paste 1 chains", _chains(root, first_nodes))
	note("paste 2 chains", _chains(root, second_nodes))
	if _chains(root, first_nodes) == _chains(root, second_nodes):
		flag("two pastes share their groups", _chains(root, second_nodes))

	var prefab: HFPrefab = HFPrefab.capture_from_selection(
		root.brush_system, root.entity_system, parts, []
	)
	var p1: Dictionary = root.prefab_system.place(
		prefab, "", Transform3D(Basis.IDENTITY, Vector3(30, 0, 0))
	)
	var p2: Dictionary = root.prefab_system.place(
		prefab, "", Transform3D(Basis.IDENTITY, Vector3(60, 0, 0))
	)
	var n1: Array = []
	for id in p1.get("brush_ids", []):
		n1.append(root.find_brush_by_id(id))
	var n2: Array = []
	for id in p2.get("brush_ids", []):
		n2.append(root.find_brush_by_id(id))
	note("prefab 1 chains", _chains(root, n1))
	note("prefab 2 chains", _chains(root, n2))
	if _chains(root, n1) == _chains(root, n2):
		flag("two placements of one prefab share their groups", _chains(root, n2))
	note("groups at the end", Array(vg.get_group_names()))
	await drop_root(root)
	HFPrefabSystem.clipboard_path = old_clip
	HFPrefabSystem.system_clipboard_stand_in = old_stand_in


## A cycle only a hand edit can make: what each walk does with it.
func _hand_edited_cycle() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var a := box(root, Vector3(2, 2, 2), Vector3(0, 2, 0))
	var b := box(root, Vector3(2, 2, 2), Vector3(4, 2, 0))
	var state: Dictionary = root.capture_state()
	state["groups"] = {"A": true, "B": true}
	state["group_order"] = ["A", "B"]
	state["group_parents"] = {"A": "B", "B": "A"}
	root.restore_state(state)
	await frame()
	a = root.find_brush_by_id(_bid(a))
	b = root.find_brush_by_id(_bid(b))
	a.set_meta("group_id", "A")
	b.set_meta("group_id", "B")
	note("cycle kept by restore_group_parents", vg.group_parents)
	note("chain of a", vg.group_chain_of(a))
	note("selection unit of a", vg.selection_unit_of(a))
	note("members deep of A", vg.group_members_deep("A").size())
	note("whole groups of [a]", vg.whole_groups([a]))
	vg.ungroup_units([a])
	note(
		"after ungrouping a's unit",
		HFVibe.canonical([Array(vg.get_group_names()), vg.group_parents])
	)
	await drop_root(root)


## A group whose members go by delete, and a rebuild of a group's last members.
##
## Merge, Hollow, Clip and Carve each delete the brushes they replace before
## they build the replacement, and a delete takes an emptied group out of the
## registry (`_cleanup_brush_references()`). The replacement is then given the
## group's name from the info read before the delete.
func _delete_and_merge_members() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var parts := _house(root, Vector3.ZERO)
	root.delete_brush_by_id(_bid(parts[0]))
	root.delete_brush_by_id(_bid(parts[1]))
	await frame()
	note(
		"after deleting both roof brushes",
		HFVibe.canonical([Array(vg.get_group_names()), vg.group_parents])
	)
	await drop_root(root)

	# 1. Merge the two brushes of an inner group.
	root = await fresh_root()
	vg = root.visgroup_system
	parts = _house(root, Vector3.ZERO, 2.0)
	var walls: Array = [_bid(parts[2]), _bid(parts[3])]
	var before: Dictionary = root.capture_state()
	var result = root.merge_brushes_by_ids([_bid(parts[0]), _bid(parts[1])])
	await frame()
	var merged: Node = null
	for b in root.draft_brushes_node.get_children():
		if not walls.has(_bid(b)):
			merged = b
	var gid := str(merged.get_meta("group_id", "")) if merged else ""
	var house_after: int = vg.group_members_deep("House").size()
	note("merge", result.message if result else null)
	note(
		"after merging Roof's two brushes: groups, parents",
		HFVibe.canonical([Array(vg.get_group_names()), vg.group_parents])
	)
	note(
		"merged brush's group_id, its chain, brushes in House",
		[gid, vg.group_chain_of(merged), house_after]
	)
	root.restore_state(before)
	await frame()
	note(
		"after undoing the merge: groups",
		HFVibe.canonical([Array(vg.get_group_names()), vg.group_parents])
	)
	await drop_root(root)

	# 2. Downstream: a top-level pair merged, then the next two brushes grouped
	# are offered the name the registry no longer has.
	root = await fresh_root()
	vg = root.visgroup_system
	var p1 := box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	var p2 := box(root, Vector3(2, 2, 2), Vector3(2, 1, 0))
	var c1 := box(root, Vector3(2, 2, 2), Vector3(10, 1, 0))
	var c2 := box(root, Vector3(2, 2, 2), Vector3(14, 1, 0))
	var first_name: String = vg.default_group_name([p1, p2])
	vg.group_units(first_name, [p1, p2])
	root.merge_brushes_by_ids([_bid(p1), _bid(p2)])
	await frame()
	var offered: String = vg.default_group_name([c1, c2])
	vg.group_units(vg.unique_group_name(offered), [c1, c2])
	var members: int = vg.get_group_members(offered).size()
	note(
		"'%s' merged, then two other brushes grouped as '%s': its members" % [first_name, offered],
		members
	)

	# 3. Hollow, on a group left with one brush.
	var solo := box(root, Vector3(4, 4, 4), Vector3(30, 2, 0))
	var mate := box(root, Vector3(2, 2, 2), Vector3(36, 1, 0))
	vg.group_units("Solo", [solo, mate])
	root.delete_brush_by_id(_bid(mate))
	root.hollow_brush_by_id(_bid(solo), 0.5)
	await frame()
	var walls_named := 0
	for b in root.draft_brushes_node.get_children():
		if str(b.get_meta("group_id", "")) == "Solo":
			walls_named += 1
	note(
		"Hollow of a group of one: walls naming 'Solo', registry has it",
		[walls_named, vg.groups.has("Solo")]
	)

	if (
		(gid != "" and not vg.groups.has(gid))
		or members != 2
		or (walls_named > 0 and not vg.groups.has("Solo"))
	):
		known(
			1975,
			"Merge, and Hollow of a group's last brush, leave the result naming a group the registry has dropped",
			(
				(
					"merging Roof's two brushes in House: the merged brush carries group_id '%s', which the registry no longer lists, so it is in no group and House holds %d brushes, not 3; "
					+ "merging the pair '%s' and grouping two other brushes, which are offered the same name, gives a group of %d with the merged brush in it; "
					+ "hollowing a group of one gives %d walls naming 'Solo' with no 'Solo' registered. "
					+ "The sources are deleted first, and _cleanup_brush_references() erases the emptied group before the result is given its name"
				)
				% [gid, house_after, first_name, members, walls_named]
			)
		)
	await drop_root(root)


func _rename_edges() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	_house(root, Vector3.ZERO)
	for pair in [
		["Roof", "Roof"],
		["Roof", " Roof "],
		["Roof", "House"],
		["Roof", "roof"],
		["Nope", "X"],
		["Roof", ""]
	]:
		var ok: bool = vg.rename_group(pair[0], pair[1])
		note(
			"rename '%s' -> '%s'" % pair,
			"%s %s" % [ok, HFVibe.canonical([Array(vg.get_group_names()), vg.group_parents])]
		)
	await drop_root(root)
