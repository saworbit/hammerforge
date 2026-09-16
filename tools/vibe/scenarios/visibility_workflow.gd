@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Hiding things, and what stays hidden.
##
## A mapper hides the roof to work on the floor, hides a whole wing to bake a
## test of one room, and cordons off the part they are working on. Each of those
## is a different mechanism -- visgroups, the cordon, per-brush visibility -- and
## the question for all three is the same: which of the operations downstream of
## it agree that the thing is hidden. A brush that is invisible in the viewport
## and present in the `.map` is the shape of bug that survives a whole project.


func id() -> String:
	return "visibility-workflow"


func summary() -> String:
	return "which operations agree that a hidden brush is hidden: bake, save, export, select, validate"


func run() -> void:
	await _a_hidden_visgroup_through_every_surface()
	await _hiding_survives_a_round_trip()
	await _a_group_that_loses_a_member()


func _two_rooms(root: Node3D) -> Dictionary:
	var kept: Array = []
	var hidden: Array = []
	for i in 4:
		kept.append(box(root, Vector3(128, 128, 16), Vector3(0, 64, i * 128.0)))
	for i in 4:
		hidden.append(box(root, Vector3(128, 128, 16), Vector3(1024, 64, i * 128.0)))
	return {"kept": kept, "hidden": hidden}


func _ids(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		out.append(str(n.get_meta("brush_id", n.name)))
	return out


## One visgroup hidden, then ask every downstream surface what it sees.
func _a_hidden_visgroup_through_every_surface() -> void:
	var root: Node3D = await fresh_root()
	var rooms := _two_rooms(root)
	root.create_visgroup("west_wing")
	root.add_selection_to_visgroup("west_wing", rooms["hidden"])
	await frame()
	note("brushes in the level", root.draft_brushes_node.get_child_count())
	root.set_visgroup_visible("west_wing", false)
	await frame()

	var visible_now := 0
	for b in root.draft_brushes_node.get_children():
		if b is Node3D and (b as Node3D).visible:
			visible_now += 1
	note("visible brushes after hiding west_wing", visible_now)
	if visible_now != 4:
		flag("hiding a visgroup left %d of 8 brushes visible" % visible_now)

	# 1. The bake, with the setting that names this exact case.
	root.bake_visible_only = true
	await root.bake()
	await frame()
	var baked_tris := _baked_triangles(root)
	note("bake_visible_only = true: baked triangles", baked_tris)

	var root2: Node3D = await fresh_root("AllVisible")
	_two_rooms(root2)
	await frame()
	root2.bake_visible_only = true
	await root2.bake()
	await frame()
	var all_tris := _baked_triangles(root2)
	note("the same level with nothing hidden: baked triangles", all_tris)
	if baked_tris >= all_tris and all_tris > 0:
		flag(
			"bake_visible_only baked the hidden visgroup anyway",
			"%d triangles hidden vs %d visible-only" % [baked_tris, all_tris]
		)
	else:
		note(
			"  -- the bake honours it",
			"%.0f%% of the triangles" % (100.0 * float(baked_tris) / float(max(1, all_tris)))
		)

	# 2. The `.map` export, which is what leaves the editor.
	var map_path := "user://vibe_hidden.map"
	root.export_map(map_path, "valve220")
	var text := FileAccess.get_file_as_string(map_path)
	var brush_blocks := text.count("{\n")
	note(".map export: text length", text.length())
	note(".map export: brace blocks", brush_blocks)
	var far_faces := 0
	for line in text.split("\n"):
		if line.find("1024") >= 0 or line.find("960") >= 0 or line.find("1088") >= 0:
			far_faces += 1
	note("lines mentioning the hidden wing's coordinates", far_faces)
	if far_faces > 0:
		note(
			"  -- a hidden visgroup still exports",
			(
				"the `.map` is the handoff to another engine, and nothing in the export "
				+ "path asks whether a brush is visible"
			)
		)

	# 3. Validation.
	var report: Dictionary = root.validate_level()
	note("validate_level with a hidden wing", report.get("issues", []).size())

	# 4. The status board's own count.
	if root.has_method("get_live_brush_count"):
		note("live brush count", root.get_live_brush_count())


func _baked_triangles(root: Node3D) -> int:
	if root.baked_container == null:
		return 0
	var total := 0
	for node in _all(root.baked_container, []):
		if node is MeshInstance3D and node.mesh:
			var m: Mesh = node.mesh
			for s in m.get_surface_count():
				var arrays: Array = m.surface_get_arrays(s)
				if arrays[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX].size() > 0:
					total += arrays[Mesh.ARRAY_INDEX].size() / 3
				elif arrays[Mesh.ARRAY_VERTEX] != null:
					total += arrays[Mesh.ARRAY_VERTEX].size() / 3
	return total


func _all(node: Node, out: Array) -> Array:
	out.append(node)
	for c in node.get_children():
		_all(c, out)
	return out


## Hidden through a save, a load and an undo.
func _hiding_survives_a_round_trip() -> void:
	var root: Node3D = await fresh_root()
	var rooms := _two_rooms(root)
	root.create_visgroup("west_wing")
	root.add_selection_to_visgroup("west_wing", rooms["hidden"])
	root.set_visgroup_visible("west_wing", false)
	await frame()
	var before := _visible_count(root)
	note("visible before the round trip", before)

	var path := "user://vibe_hidden.hflevel"
	root.save_hflevel(path)
	await HFVibe.settle_save(_tree, root)
	var root2: Node3D = await fresh_root("Loaded")
	root2.load_hflevel(path)
	await frame()
	var after := _visible_count(root2)
	note("visible after save + load", after)
	note("visgroups after load", root2.get_visgroup_names())
	if after != before:
		flag(
			"a hidden visgroup comes back visible",
			"%d visible before the save, %d after the load" % [before, after]
		)

	# And through the undo path, which rebuilds the level from a snapshot.
	var state: Dictionary = root.capture_state()
	root.set_visgroup_visible("west_wing", true)
	await frame()
	note("visible with the wing shown again", _visible_count(root))
	root.restore_state(state)
	await frame()
	var restored := _visible_count(root)
	note("visible after restore_state of the hidden snapshot", restored)
	if restored != before:
		flag(
			"undoing back to a hidden visgroup does not re-hide it",
			"%d visible in the snapshot, %d after restoring it" % [before, restored]
		)


func _visible_count(root: Node3D) -> int:
	var n := 0
	if root.draft_brushes_node == null:
		return 0
	for b in root.draft_brushes_node.get_children():
		if b is Node3D and (b as Node3D).visible:
			n += 1
	return n


## Groups are the other membership mechanism. What happens to one that loses a
## member, and to a group of one?
func _a_group_that_loses_a_member() -> void:
	var root: Node3D = await fresh_root()
	var brushes: Array = []
	for i in 4:
		brushes.append(box(root, Vector3(64, 64, 64), Vector3(i * 128.0, 32, 0)))
	await frame()
	root.group_selection("east_block", brushes)
	await frame()
	note("group members", root.get_group_members("east_block").size())

	# Delete one member.
	root.delete_brush(brushes[0])
	await frame()
	var remaining: int = root.draft_brushes_node.get_child_count()
	note("brushes after deleting one group member", remaining)
	var still_grouped := 0
	for b in root.draft_brushes_node.get_children():
		if str(b.get_meta("group_id", "")) != "":
			still_grouped += 1
	note("brushes still carrying the group id", still_grouped)
	note("get_group_members after the delete", root.get_group_members("east_block").size())

	# Delete two more, leaving a group of one.
	var live: Array = []
	for b in root.draft_brushes_node.get_children():
		live.append(b)
	root.delete_brush(live[0])
	root.delete_brush(live[1])
	await frame()
	var left := 0
	for b in root.draft_brushes_node.get_children():
		if str(b.get_meta("group_id", "")) != "":
			left += 1
	note("brushes left carrying the group id", left)
	note("get_group_members with one member left", root.get_group_members("east_block").size())
	if left == 1:
		note(
			"a group of one survives",
			(
				"selecting it still expands to 'the group', which is itself; nothing "
				+ "dissolves a group that has stopped being a group"
			)
		)
