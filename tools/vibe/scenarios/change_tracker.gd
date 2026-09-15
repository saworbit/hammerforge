@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## `HFBrushChangeTracker`, which is what notices an edit HammerForge did not make.
##
## Every HammerForge command tags its own brushes dirty on the way out. The
## tracker exists for the edits that come from somewhere else: Godot's own
## Inspector, its transform gizmo, its Scene-tree drag, and native undo. It
## keeps a signature per brush id and re-hashes it each reconcile; whatever moved
## is tagged, and whatever it does not hash is not.
##
## So the measurement is: change one thing about a brush the way the Inspector
## would, reconcile, and see whether the tracker noticed. Anything it misses is
## a brush that keeps its old baked geometry with "Bake Changed" saying there is
## nothing to do.

const Tracker = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")


func id() -> String:
	return "change-tracker"


func summary() -> String:
	return "which native edits the brush change tracker notices, and which it does not"


func run() -> void:
	await _one_change_at_a_time()
	await _entity_metadata_the_bake_reads()
	await _a_brush_dragged_out_of_its_container()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## Apply `mutate`, reconcile, and say whether the brush came back changed.
func _did_it_notice(tracker, root: Node3D, brush: Node, label: String, mutate: Callable) -> bool:
	tracker.reconcile(root)
	mutate.call(brush)
	var changed: PackedStringArray = tracker.reconcile(root)
	var noticed := _bid(brush) in changed
	note("%s" % label, "noticed" if noticed else "NOT noticed")
	return noticed


func _one_change_at_a_time() -> void:
	var root: Node3D = await fresh_root("TrackerLevel")
	var b = box(root, Vector3(64, 64, 64))
	await frame()
	var tracker = Tracker.new()
	tracker.prime(root)

	_did_it_notice(
		tracker, root, b, "moved with the native gizmo", func(n): n.position += Vector3(32, 0, 0)
	)
	_did_it_notice(tracker, root, b, "hidden in the Scene tree", func(n): n.visible = false)
	_did_it_notice(tracker, root, b, "shown again", func(n): n.visible = true)
	_did_it_notice(tracker, root, b, "size changed in the Inspector", func(n): n.size = Vector3(96, 64, 64))
	_did_it_notice(tracker, root, b, "operation changed in the Inspector", func(n): n.operation = 2)
	_did_it_notice(
		tracker,
		root,
		b,
		"a face's material slot changed",
		func(n): n.faces[0].material_idx = 1
	)
	_did_it_notice(
		tracker,
		root,
		b,
		"a face's UV rotation changed",
		func(n): n.faces[0].uv_rotation = 0.5
	)
	_did_it_notice(
		tracker,
		root,
		b,
		"a face vertex moved",
		func(n): n.faces[0].local_verts[0] += Vector3(1, 0, 0)
	)
	_did_it_notice(tracker, root, b, "renamed in the Scene tree", func(n): n.name = "Renamed")


## The bake reads three pieces of metadata off a draft brush that decide what
## the brush becomes in the output: its entity class, its entity name and its
## I/O outputs. Whether the signature covers them.
func _entity_metadata_the_bake_reads() -> void:
	var root: Node3D = await fresh_root("TrackerMeta")
	var b = box(root, Vector3(64, 64, 64))
	await frame()
	var tracker = Tracker.new()
	tracker.prime(root)

	var missed: Array = []
	var cases := [
		[
			"brush entity class set to func_door",
			func(n): n.set_meta("brush_entity_class", "func_door")
		],
		["entity name set", func(n): n.set_meta("entity_name", "door_01")],
		[
			"entity I/O outputs set",
			func(n): n.set_meta("entity_io_outputs", [{"output": "OnOpen", "target": "x"}])
		],
	]
	for case in cases:
		if not _did_it_notice(tracker, root, b, case[0], case[1]):
			missed.append(case[0])

	# Prove these reach the bake rather than only sitting on the node.
	var reads: Array = []
	var bake_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_bake_system.gd"
	)
	for key in ["brush_entity_class", "entity_name", "entity_io_outputs"]:
		if 'get_meta("%s"' % key in bake_source:
			reads.append(key)
	note("metadata hf_bake_system.gd reads off a draft brush", reads)

	if not missed.is_empty() and not reads.is_empty():
		flag(
			"the change tracker does not hash the entity metadata the bake reads",
			(
				"_signature() covers transform, visible, size, shape, operation, sides,"
				+ " material_override and every face, and none of %s," % str(reads)
				+ " which hf_bake_system.gd reads to decide whether a brush becomes an entity,"
				+ " what it is called and what it is wired to. Changing one through Godot's own"
				+ " Inspector metadata panel or restoring one with native undo leaves the brush"
				+ " untagged: %s" % str(missed)
			)
		)


## A native Scene-tree drag out of DraftBrushes, which the tracker undoes.
func _a_brush_dragged_out_of_its_container() -> void:
	var root: Node3D = await fresh_root("TrackerReparent")
	var b = box(root, Vector3(64, 64, 64))
	await frame()
	var tracker = Tracker.new()
	tracker.prime(root)
	var original_parent := b.get_parent()
	note("the brush's parent", original_parent.name)

	var elsewhere := root.get_node_or_null("Entities")
	if elsewhere == null:
		elsewhere = Node3D.new()
		elsewhere.name = "Elsewhere"
		root.add_child(elsewhere)
		await frame()
	b.reparent(elsewhere, true)
	note("dragged under", b.get_parent().name)
	tracker.reconcile(root)
	await frame()
	note("parent after reconcile", b.get_parent().name)
	if b.get_parent() == original_parent:
		note(
			"the tracker puts a brush dragged out of its container back",
			"_recover_illegal_reparents() reparents it to the parent it last had"
		)
	else:
		flag(
			"a brush dragged out of DraftBrushes in the Scene tree stays there",
			"it is no longer in the managed traversal, so nothing in the dock can edit it"
		)
