@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What an evening of editing leaves behind.
##
## Every other scenario builds a level, asks its question and quits. A mapper
## keeps one editor open for hours and does thousands of operations in it, and
## the complaint that comes out of that is never "this operation is wrong", it is
## "the editor got slow" or "Godot is using six gigabytes". Both are the same
## shape: something the session allocates and never gives back.
##
## Godot counts this for us. `Performance.OBJECT_NODE_COUNT` is every live node,
## `OBJECT_ORPHAN_NODE_COUNT` is every node outside the tree that nothing freed,
## and `OBJECT_COUNT` covers the `RefCounted` graph as well. A loop that ends
## where it started should leave all three where they started.


func id() -> String:
	return "session-leaks"


func summary() -> String:
	return "whether a long run of ordinary edits gives back the nodes and objects it took"


func run() -> void:
	await _create_and_delete()
	await _bake_over_and_over()
	await _undo_and_redo()
	await _previews_opened_and_cancelled()


func _counts() -> Dictionary:
	return {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}


func _delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in before:
		out[k] = int(after[k]) - int(before[k])
	return out


## Let deferred frees actually land before measuring. `queue_free()` runs at the
## end of the frame, and a count taken on the same frame reads every freed node
## as still alive.
func _settle(frames: int = 8) -> void:
	for _i in frames:
		await frame()


func _create_and_delete() -> void:
	var root: Node3D = await fresh_root()
	await _settle()
	var before := _counts()
	note("before 200 create/delete cycles", before)
	for i in 200:
		var b = box(root, Vector3(1, 1, 1), Vector3(i % 10, 0, i / 10))
		root.delete_brush(b)
	await _settle(16)
	var after := _counts()
	note("after", after)
	note("delta", _delta(before, after))
	note("live brushes the level reports", root.brush_system.get_live_brush_count())
	var d := _delta(before, after)
	if int(d["orphans"]) > 8:
		flag(
			"200 create/delete cycles leave %d orphan node(s)" % int(d["orphans"]),
			(
				"An orphan is a node taken out of the tree and never freed. It holds its "
				+ "meshes and materials with it, so the cost is not one node but everything "
				+ "hanging off it, and nothing in the editor ever collects it. Over an "
				+ "evening of drawing and deleting this is the memory a mapper watches climb."
			)
		)
	elif int(d["nodes"]) > 8:
		flag(
			"200 create/delete cycles leave %d extra live node(s)" % int(d["nodes"]),
			"the level reports %d brushes" % root.brush_system.get_live_brush_count()
		)


func _bake_over_and_over() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(10, 0.2, 10), Vector3(0, -0.1, 0))
	for i in 20:
		box(root, Vector3(1, 2, 1), Vector3(-4.0 + i * 0.5, 1, 0))
	await _settle()
	# One bake first, so the steady state is measured rather than the first-bake
	# allocations.
	await root.bake(false, false)
	await _settle()
	var before := _counts()
	note("before 25 re-bakes of the same level", before)
	for _i in 25:
		await root.bake(false, false)
	await _settle(16)
	var after := _counts()
	note("after", after)
	var d := _delta(before, after)
	note("delta", d)
	if int(d["orphans"]) > 8 or int(d["nodes"]) > 40:
		flag(
			"25 re-bakes of an unchanged level leave %s behind" % d,
			(
				"Each bake replaces the baked container, so the previous one has to go. A "
				+ "mapper bakes dozens of times an evening and this is what each one costs "
				+ "permanently."
			)
		)
	if int(d["resources"]) > 60:
		flag(
			"25 re-bakes leave %d extra live Resource(s)" % int(d["resources"]),
			(
				"the meshes and shapes from the replaced containers are still referenced by "
				+ "something, which is the expensive half of a bake to keep"
			)
		)


func _undo_and_redo() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(4, 0.2, 4), Vector3(0, -0.1, 0))
	await _settle()
	var base: Dictionary = root.capture_state()
	var before := _counts()
	note("before 100 capture/restore round trips", before)
	for i in 100:
		box(root, Vector3(0.5, 0.5, 0.5), Vector3(i % 8, 0.25, 0))
		var step: Dictionary = root.capture_state()
		if step.is_empty():
			flag("capture_state returned nothing mid-session", "iteration %d" % i)
		root.restore_state(base)
	await _settle(16)
	var after := _counts()
	note("after", after)
	var d := _delta(before, after)
	note("delta", d)
	note("brushes after the last restore", root.brush_system.get_live_brush_count())
	if int(d["orphans"]) > 8:
		flag(
			"100 undo round trips leave %d orphan node(s)" % int(d["orphans"]),
			(
				"restore_state() rebuilds the level from a snapshot, so every brush in the "
				+ "level is destroyed and remade on each undo. Anything that does not get "
				+ "freed there accumulates at the rate a mapper presses Ctrl+Z."
			)
		)


func _previews_opened_and_cancelled() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(2, 2, 2))
	await _settle()
	var before := _counts()
	note("before 100 preview show/hide cycles", before)
	for i in 100:
		if root.hollow_preview:
			root.hollow_preview.show_preview(str(b.brush_id), 0.2)
			root.hollow_preview.clear()
	await _settle(16)
	var after := _counts()
	note("after", after)
	var d := _delta(before, after)
	note("delta", d)
	if int(d["orphans"]) > 8 or int(d["nodes"]) > 20:
		flag(
			"100 preview cycles leave %s behind" % d,
			(
				"A ghost is shown and hidden on every mouse move during a hollow, an array or "
				+ "a structure placement, so this is the highest-frequency allocation in the "
				+ "editor by a long way."
			)
		)
