@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Groups, as distinct from visgroups.
##
## The two live side by side in `HFVisgroupSystem` and do nearly the same job:
## a name, a membership stored in node meta, a registry, and a serializer. The
## visgroup half has been hardened -- #349 fixed its name guard, and
## `rename_visgroup()` carries a collision check with a paragraph explaining
## what happens without one. The group half sits directly below it in the same
## file. This scenario asks whether the two halves actually agree.


func id() -> String:
	return "groups"


func summary() -> String:
	return "group names, membership after a delete, and where groups differ from visgroups"


func run() -> void:
	await _group_names_at_their_edges()
	await _a_group_whose_last_member_is_deleted()
	await _group_membership_through_a_state_round_trip()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func _group_names_at_their_edges() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system

	var cases: Array = ["", "   ", "\t", "\n", "lights", "lights ", " lights"]
	for name in cases:
		vg.create_group(name)
	var made := Array(vg.get_group_names())
	note("group names after creating %s" % [cases], made)

	for name in cases:
		vg.create_visgroup(name)
	var vg_made := Array(vg.get_visgroup_names())
	note("visgroup names after creating the same list", vg_made)

	var blank: Array = []
	for n in made:
		if str(n).strip_edges() == "":
			blank.append(n)
	if not blank.is_empty():
		known(
			374,
			"a group can be named with nothing but whitespace",
			(
				'created %s; the visgroup half of the same file refuses all of them and got %s -- #349 fixed `if name == ""` for visgroups and left the identical guard in create_group()'
				% [blank, vg_made]
			)
		)

	if made.has("lights") and made.has("lights "):
		known(
			374,
			"group names are not stripped, so two names a keystroke apart are two groups",
			(
				"the registry holds %s; create_visgroup() stores stripped for exactly this reason and produced %s"
				% [made, vg_made]
			)
		)

	# Renaming. Visgroups have one; groups do not.
	note("visgroup_system has rename_visgroup", vg.has_method("rename_visgroup"))
	note("visgroup_system has rename_group", vg.has_method("rename_group"))
	if vg.has_method("rename_visgroup") and not vg.has_method("rename_group"):
		note(
			"groups cannot be renamed at all",
			"the only way to change a group's name is to ungroup and regroup, which loses nothing but is worth saying out loud"
		)


## `ungroup_nodes()` calls `_cleanup_empty_group()`. Deleting the member instead
## is the other way a group empties.
func _a_group_whose_last_member_is_deleted() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var b := box(root, Vector3(64, 64, 64))
	vg.group_selection("Doorway", [b])
	await frame()
	note("groups after grouping one brush", Array(vg.get_group_names()))
	note("members", vg.get_group_members("Doorway").size())

	root.delete_brush_by_id(_bid(b))
	await frame()
	var names := Array(vg.get_group_names())
	var members: int = vg.get_group_members("Doorway").size()
	note("groups after deleting the only member", names)
	note("members now", members)
	if names.has("Doorway") and members == 0:
		flag(
			"a group whose last member is deleted stays in the registry with nothing in it",
			"'Doorway' still lists in get_group_names() with 0 members -- ungroup_nodes() calls _cleanup_empty_group() for the other way a group empties, and the delete path does not, so the group list grows with every deleted group for the life of the level"
		)

	# Same question of the visgroup half, for the comparison.
	var root2: Node3D = await fresh_root()
	var b2 := box(root2, Vector3(64, 64, 64))
	root2.create_visgroup("Trim")
	root2.add_selection_to_visgroup("Trim", [b2])
	await frame()
	root2.delete_brush_by_id(_bid(b2))
	await frame()
	note("visgroups after deleting the only member", Array(root2.get_visgroup_names()))


## A group is only a name on a node. The registry and the membership are two
## separate things, so a round trip can keep one and lose the other.
func _group_membership_through_a_state_round_trip() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var a := box(root, Vector3(64, 64, 64))
	var b := box(root, Vector3(64, 64, 64), Vector3(128, 0, 0))
	vg.group_selection("Arch", [a, b])
	await frame()

	var before_names := Array(vg.get_group_names())
	var before_members: int = vg.get_group_members("Arch").size()

	var state: Dictionary = root.capture_state()
	root.restore_state(state)
	await frame()

	var after_names := Array(vg.get_group_names())
	var after_members: int = vg.get_group_members("Arch").size()
	note("group names", "%s -> %s" % [before_names, after_names])
	note("members of 'Arch'", "%d -> %d" % [before_members, after_members])
	if before_names != after_names:
		flag(
			"a state round trip changed the group registry",
			"%s -> %s" % [before_names, after_names]
		)
	if before_members != after_members:
		flag(
			"a state round trip changed group membership",
			"'Arch' had %d members and has %d" % [before_members, after_members]
		)

	for problem in HFVibe.check_invariants(root):
		flag("after a state round trip with a group: %s" % problem)
