@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a level restore resets, and what it leaves behind.
##
## `restore_state()` is the one operation that has to put the whole level back --
## brushes, entities, materials, selection, and every counter and registry the
## subsystems keep on the side. A subsystem it forgets does not fail loudly; it
## carries state from the level the editor had open before into the one it has
## open now, and the first symptom is something else breaking much later.
##
## #369 found this shape in the prefab system's instance counter. This scenario
## asks the same question of the rest of them.


func id() -> String:
	return "lifecycle"


func summary() -> String:
	return "what survives a restore_state that should not: counters, registries and selection"


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func run() -> void:
	await _the_brush_id_counter_after_a_restore()
	await _registries_across_a_restore_of_a_different_level()
	await _face_selection_after_the_brush_is_gone()


## `restore_state()` takes the counter from the state: `root._brush_id_counter =
## int(state.get("id_counter", 0))`. Nothing reconciles it against the ids it
## went on to restore.
func _the_brush_id_counter_after_a_restore() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	box(root, Vector3(64, 64, 64), Vector3(128, 0, 0))
	await frame()

	var state: Dictionary = root.capture_state()
	note("id_counter the capture recorded", state.get("id_counter", "<absent>"))

	# An older save, a partial write, or a hand edit. Zero is also what
	# `state.get("id_counter", 0)` hands back for a state with no such key.
	var poisoned: Dictionary = state.duplicate(true)
	poisoned["id_counter"] = 0
	root.restore_state(poisoned)
	await frame()

	var restored_ids: Array = []
	for b in root.draft_brushes_node.get_children():
		restored_ids.append(_bid(b))
	note("brush ids after the restore", restored_ids)
	note("_brush_id_counter now", root._brush_id_counter)

	var fresh := box(root, Vector3(32, 32, 32), Vector3(256, 0, 0))
	await frame()
	var new_id := _bid(fresh)
	note("id issued to the next new brush", new_id)
	note("live brush count", root.brush_system.get_live_brush_count())

	if restored_ids.has(new_id):
		flag(
			"restore_state trusts the saved brush id counter, so the next new brush reuses a live id",
			(
				"the restored level holds %s and the next brush created was given '%s', which is already one of them. Brush ids address a brush everywhere -- face selection, visgroup membership, generator records, the dirty set, undo -- so two brushes answering to one id means every one of those resolves to whichever comes first. #369 is the same defect in the prefab instance counter."
				% [restored_ids, new_id]
			)
		)
	for problem in HFVibe.check_invariants(root):
		flag("after restoring with a stale id counter: %s" % problem)


## Restoring level B into an editor that had level A open. Anything the restore
## does not reset is A's, in B.
func _registries_across_a_restore_of_a_different_level() -> void:
	# Level B, captured first.
	var b_root: Node3D = await fresh_root("LevelB")
	box(b_root, Vector3(32, 32, 32))
	b_root.create_visgroup("OnlyInB")
	await frame()
	var b_state: Dictionary = b_root.capture_state()

	# Level A, with its own registries, then B restored over it.
	var root: Node3D = await fresh_root("LevelA")
	box(root, Vector3(64, 64, 64))
	root.create_visgroup("OnlyInA")
	root.visgroup_system.group_selection("GroupInA", root.draft_brushes_node.get_children())
	root.prefab_system.register_instance("res://a.hfprefab", [], [])
	root.set_materials(
		[StandardMaterial3D.new(), StandardMaterial3D.new(), StandardMaterial3D.new()]
	)
	await frame()

	root.restore_state(b_state)
	await frame()

	var visgroups := Array(root.get_visgroup_names())
	var groups := Array(root.visgroup_system.get_group_names())
	var instances: int = root.prefab_system.get_all_instances().size()
	var palette: int = root.get_materials().size()
	note("visgroups after restoring a different level", visgroups)
	note("groups after restoring a different level", groups)
	note("prefab instances after restoring a different level", instances)
	note("palette size after restoring a different level", palette)
	note("brushes", root.brush_system.get_live_brush_count())

	if visgroups.has("OnlyInA"):
		flag(
			"a visgroup from the previous level survives restoring a different one",
			"the restored level knows only 'OnlyInB'; the registry holds %s" % [visgroups]
		)
	if groups.has("GroupInA"):
		flag(
			"a group from the previous level survives restoring a different one",
			"the group registry holds %s after loading a level that has no groups" % [groups]
		)
	if instances > 0:
		flag(
			"a prefab instance record from the previous level survives restoring a different one",
			(
				"%d instance(s) still registered after loading a level with none -- every one of them is tagged onto brush ids that belong to a different level now"
				% instances
			)
		)
	for problem in HFVibe.check_invariants(root):
		flag("after restoring a different level: %s" % problem)


## `validate()` has a check for "Face selection contains N invalid indices",
## which says a stale selection is a state the level can reach. Deleting the
## selected brush is the obvious way.
func _face_selection_after_the_brush_is_gone() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	await frame()
	var bid := _bid(b)
	root.face_selection = {bid: [0, 1, 2]}
	root._apply_face_selection()
	await frame()
	note("face selection", root.face_selection)

	root.delete_brush_by_id(bid)
	await frame()
	note("face selection after deleting the brush", root.face_selection)
	var report: Dictionary = root.validate_level(false)
	note("what the validator says", report.get("issues", []))

	if root.face_selection.has(bid):
		flag(
			"deleting a brush leaves its faces in the selection",
			(
				"face_selection still holds an entry for '%s' after the brush was deleted; validate_level reports %s. Every face operation walks this dictionary, so the stale entry is looked up on each one."
				% [bid, report.get("issues", [])]
			)
		)
	for problem in HFVibe.check_invariants(root):
		flag("after deleting a brush with faces selected: %s" % problem)
