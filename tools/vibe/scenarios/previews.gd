@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The ghost previews: clip, carve, hollow, array and structure.
##
## A preview is the one kind of node the editor puts in the scene that is not
## part of the level. So the whole contract is about what it must *not* do:
## never be counted as a brush, never reach the save, never reach the bake, and
## never outlive the operation it was previewing. Each of those is a thing that
## is easy to get right for the ordinary path and easy to miss when the preview
## is shown for something that does not exist, or with a number nobody expected.


func id() -> String:
	return "previews"


func summary() -> String:
	return "clip, carve, hollow, array and structure ghosts: leaks, bad inputs, and what counts them"


func run() -> void:
	await _a_preview_is_not_part_of_the_level()
	await _a_preview_of_something_that_is_not_there()
	await _preview_inputs_at_their_edges()
	await _a_preview_that_outlives_its_brush()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## Every node under the root, so a preview that parents itself somewhere
## unexpected is still counted.
func _node_count(root: Node3D) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			n += 1
			stack.append(child)
	return n


func _show_all(root: Node3D, brush_id: String) -> void:
	var brush_id_array: Array = [brush_id]
	root.clip_preview.show_preview(brush_id, 0, 0.0)
	root.hollow_preview.show_preview(brush_id, 8.0)
	root.carve_preview.show_preview(brush_id)
	root.array_preview.show_preview(
		brush_id_array, HFDuplicator.linear_placements(2, Vector3(128, 0, 0))
	)
	root.structure_preview.show_preview(
		"stairs",
		{"steps": 8, "step_width": 64.0, "step_height": 16.0, "step_depth": 32.0},
		Transform3D()
	)


func _clear_all(root: Node3D) -> void:
	root.clip_preview.clear()
	root.hollow_preview.clear()
	root.carve_preview.clear()
	root.array_preview.clear()
	root.structure_preview.clear()


## Showing every preview at once, then clearing. The brush count, the saved
## state and the baked output must all be the same on both sides of it.
func _a_preview_is_not_part_of_the_level() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	await frame()

	var before_brushes: int = root.brush_system.get_live_brush_count()
	var before_state := HFVibe.describe_level(root)
	var before_nodes := _node_count(root)

	_show_all(root, _bid(b))
	await frame()
	var during_brushes: int = root.brush_system.get_live_brush_count()
	var during_state := HFVibe.describe_level(root)
	note(
		"nodes under the root",
		"%d idle -> %d with every preview up" % [before_nodes, _node_count(root)]
	)
	note("live brush count", "%d -> %d" % [before_brushes, during_brushes])
	note("array preview copies", root.array_preview.copy_count())
	note("structure preview pieces", root.structure_preview.piece_count())

	if during_brushes != before_brushes:
		flag(
			"a preview is counted as a live brush",
			"%d brushes with no preview up, %d with them up" % [before_brushes, during_brushes]
		)
	diff_levels(before_state, during_state, "showing every preview")

	_clear_all(root)
	await frame()
	var after_nodes := _node_count(root)
	note("nodes after clearing every preview", "%d (idle was %d)" % [after_nodes, before_nodes])
	diff_levels(before_state, HFVibe.describe_level(root), "showing and clearing every preview")
	for problem in HFVibe.check_invariants(root):
		flag("after showing and clearing every preview: %s" % problem)


## Each preview takes a brush id. Handing it one that is not in the level is the
## ordinary case after a delete or an undo, not an exotic one.
func _a_preview_of_something_that_is_not_there() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	await frame()
	var before := HFVibe.describe_level(root)

	_show_all(root, "no_such_brush")
	await frame()
	note(
		"clip preview on a missing brush",
		"level still holds %d" % root.brush_system.get_live_brush_count()
	)
	note("array preview copies", root.array_preview.copy_count())
	diff_levels(before, HFVibe.describe_level(root), "previewing a brush that is not there")

	_clear_all(root)
	await frame()
	for problem in HFVibe.check_invariants(root):
		flag("after previewing a brush that is not there: %s" % problem)


## The numbers the previews take, at the values a SpinBox will not produce but a
## restored state or a keyboard-entered field will.
func _preview_inputs_at_their_edges() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	await frame()
	var bid := _bid(b)
	var before := HFVibe.describe_level(root)

	for thickness in [0.0, -8.0, NAN, INF, 1.0e12]:
		root.hollow_preview.show_preview(bid, thickness)
		await frame()
		note(
			"hollow preview, wall thickness %s" % thickness,
			"level holds %d brushes" % root.brush_system.get_live_brush_count()
		)
	root.hollow_preview.clear()

	for split in [NAN, INF, -1.0e9]:
		root.clip_preview.show_preview(bid, 0, split)
		await frame()
		note(
			"clip preview, split at %s" % split,
			"level holds %d brushes" % root.brush_system.get_live_brush_count()
		)
	root.clip_preview.clear()

	# A negative and a huge array count, through the preview rather than the
	# committed array (#346 covers the committed path).
	for count in [0, -5, 2000]:
		var placements: Array = HFDuplicator.linear_placements(count, Vector3(8, 0, 0))
		var drawn: int = root.array_preview.show_preview([bid], placements)
		note("array preview with %d placements" % count, "drew %d" % drawn)
	root.array_preview.clear()
	await frame()

	diff_levels(before, HFVibe.describe_level(root), "previews at their edges")
	for problem in HFVibe.check_invariants(root):
		flag("after previewing at the edges: %s" % problem)


## The preview is up and the brush it describes is deleted underneath it. This
## is what an undo during a modal operation does.
func _a_preview_that_outlives_its_brush() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	await frame()
	var bid := _bid(b)
	_show_all(root, bid)
	await frame()

	root.delete_brush_by_id(bid)
	await frame()
	note("brushes after deleting the previewed brush", root.brush_system.get_live_brush_count())
	note("array preview still reports", root.array_preview.copy_count())
	note("structure preview still reports", root.structure_preview.piece_count())

	# Whatever the ghosts do, the bake must not pick them up.
	var ok: bool = await root.bake_dirty()
	await frame()
	var baked := 0
	var stack: Array = [root.baked_container]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node == null:
			continue
		for child in node.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
				baked += (child as MeshInstance3D).mesh.get_surface_count()
			stack.append(child)
	note("baking an empty level with ghosts up", "returned %s, %d baked surface(s)" % [ok, baked])
	if baked > 0:
		flag(
			"a ghost preview reached the baked output",
			"the level has no brushes left and the bake produced %d surface(s)" % baked
		)

	_clear_all(root)
	await frame()
	for problem in HFVibe.check_invariants(root):
		flag("after a preview outlived its brush: %s" % problem)
