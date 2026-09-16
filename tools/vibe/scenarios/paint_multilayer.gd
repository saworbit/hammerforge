@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Floor Paint with more than one layer, which is what the layer list is for:
## a ground floor and a walkway above it, painted over the same ground.
##
## The generated geometry for every layer lands under one pair of container
## nodes, and the reconciler indexes those containers by chunk before deciding
## what to delete. Whether a layer's id is part of that decision is the thing to
## measure -- two layers painted over the same cells are two sets of nodes in
## one chunk.

const ManagerType = preload("res://addons/hammerforge/paint/hf_paint_layer_manager.gd")


func id() -> String:
	return "paint-multilayer"


func summary() -> String:
	return "whether painting on one floor layer keeps the geometry of the layers under it"


func run() -> void:
	await _two_layers_over_one_chunk()


func _generated_counts(root: Node3D) -> Dictionary:
	var out := {"floors": 0, "walls": 0, "by_layer": {}}
	var rec = root.paint_tool.reconciler if root.paint_tool else null
	if rec == null:
		return out
	for holder in [rec.floors_root, rec.walls_root]:
		if holder == null or not is_instance_valid(holder):
			continue
		for child in holder.get_children():
			if not child.has_meta("hf_gid"):
				continue
			var gid := str(child.get_meta("hf_gid"))
			# hf:<kind>:v1:<layer_id>:<chunk>:...
			var parts := gid.split(":")
			var layer_id: String = str(parts[3]) if parts.size() > 3 else "?"
			out["by_layer"][layer_id] = int(out["by_layer"].get(layer_id, 0)) + 1
			if holder == rec.floors_root:
				out["floors"] += 1
			else:
				out["walls"] += 1
	return out


func _paint(layer, from: Vector2i, to: Vector2i) -> void:
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			layer.set_cell(Vector2i(x, y), true)


func _two_layers_over_one_chunk() -> void:
	var root: Node3D = await fresh_root("MultiLayer")
	await frame()
	var manager = root.paint_layers
	note("layers a fresh level starts with", manager.layers.size())
	var ground = manager.get_active_layer()
	note("ground layer id", ground.layer_id)

	# A second layer above the first, painted over the same cells -- a walkway
	# over the floor it crosses, which is what layer_y is for.
	root.paint_system.add_paint_layer()
	await frame()
	var upper = manager.get_active_layer()
	upper.grid.layer_y = 64.0
	note("upper layer id", upper.layer_id)
	note("layers now", manager.layers.size())

	_paint(ground, Vector2i(0, 0), Vector2i(5, 5))
	_paint(upper, Vector2i(2, 2), Vector2i(3, 3))
	var dirty: Array[Vector2i] = []
	for cid in ground.consume_dirty_chunks():
		if not dirty.has(cid):
			dirty.append(cid)
	for cid in upper.consume_dirty_chunks():
		if not dirty.has(cid):
			dirty.append(cid)
	note("chunks both layers touched", dirty)

	root.paint_system._reconcile_dirty_chunks(dirty)
	await frame()
	var counts: Dictionary = _generated_counts(root)
	note("generated nodes after reconciling both layers", counts["by_layer"])
	note("floors / walls", [counts["floors"], counts["walls"]])

	var represented: int = 0
	for layer in manager.layers:
		if int(counts["by_layer"].get(str(layer.layer_id), 0)) > 0:
			represented += 1
	note("layers with any geometry left", "%d of %d" % [represented, manager.layers.size()])
	if represented < manager.layers.size():
		known(
			561,
			"reconciling one paint layer deletes the generated geometry of the others in the same chunk",
			(
				(
					"`HFGeneratedReconciler.reconcile()` indexes every child of the shared"
					+ " floors/walls containers whose `hf_chunk` tag is in scope -- the tag"
					+ " carries the chunk and not the layer -- then frees everything in that"
					+ " index that is not in `want`, and `want` is built from one layer's model."
					+ " `_reconcile_dirty_chunks()` then runs that over every layer in turn, so"
					+ " only the layer reconciled last keeps its geometry in a shared chunk."
					+ " %d of %d layers have geometry left: %s"
				)
				% [represented, manager.layers.size(), str(counts["by_layer"])]
			)
		)

	# And again, to see whether it settles or keeps swapping.
	_paint(upper, Vector2i(4, 4), Vector2i(4, 4))
	var dirty2: Array[Vector2i] = []
	for cid in upper.consume_dirty_chunks():
		dirty2.append(cid)
	root.paint_system._reconcile_dirty_chunks(dirty2)
	await frame()
	note("after a second stroke on the upper layer", _generated_counts(root)["by_layer"])
