@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Editing the paint layer list of a level that already has paint on it.
##
## `paint-grid` mints ids and `paint-multilayer` paints two layers once. A
## mapper's layer list changes under paint: layers are renamed, added and
## removed, each removal is undone, the grid snap changes between strokes,
## Enter confirms connectors between floors that are then edited round, and the
## Height Scale and Layer Y spins move a layer. This does each of those to a
## painted level and reads the cells, the generated floors, the confirmed
## connectors and the layer settings back after every step, undo included.

const HFAutoConnector = preload("res://addons/hammerforge/paint/hf_auto_connector.gd")


func id() -> String:
	return "paint-layers-edit"


func summary() -> String:
	return "rename, add and remove painted layers, change the grid under them, and undo each"


func expected_issues() -> Array[int]:
	return [2009, 2011, 2012, 2013]


func run() -> void:
	await _remove_and_undo()
	await _grid_snap_under_paint()
	await _connectors_after_a_removal()
	await _a_name_add_hands_out_again()
	await _layer_settings_and_undo()


## Every layer as a comparable row: id, shown name, height, cells and wall
## heights, in list order.
func _layers(root: Node3D) -> Array:
	var out: Array = []
	for layer in root.paint_layers.layers:
		(
			out
			. append(
				[
					str(layer.layer_id),
					root.paint_system.paint_layer_name(layer),
					snappedf(layer.grid.layer_y, 0.001),
					layer.filled_cell_count(),
					layer.get_wall_height_entries().size(),
				]
			)
		)
	return out


## How many generated floor and wall nodes each layer has.
func _generated(root: Node3D) -> Dictionary:
	var out: Dictionary = {}
	var rec = root.paint_tool.reconciler
	for holder in [rec.floors_root, rec.walls_root, rec.heightmap_floors_root]:
		if holder == null:
			continue
		for child in holder.get_children():
			if child.has_meta("hf_layer"):
				var key := str(child.get_meta("hf_layer"))
				out[key] = int(out.get(key, 0)) + 1
	return out


## The world box the generated floors of one layer cover, counting only the
## floors whose centre is nearer the origin on X than `below_x`.
func _floor_bounds(root: Node3D, layer_id: String, below_x: float = INF) -> AABB:
	var rec = root.paint_tool.reconciler
	var out := AABB()
	var first := true
	for child in rec.floors_root.get_children():
		if str(child.get_meta("hf_layer", "")) != layer_id:
			continue
		if child.global_position.x >= below_x:
			continue
		var size: Vector3 = child.size
		var box := AABB(child.global_position - size * 0.5, size)
		out = box if first else out.merge(box)
		first = false
	return out


func _paint(root: Node3D, index: int, from: Vector2i, to: Vector2i) -> void:
	var done: Dictionary = root.paint_system.paint_cells(index, from, to, true)
	if not done["ok"]:
		flag("paint_cells refused a plain rectangle", done["error"])


## Two painted layers, the top one with raised walls; remove each in turn and undo.
func _remove_and_undo() -> void:
	note("-- remove a painted layer, then undo and redo --")
	var root: Node3D = await fresh_root("LayersRemove")
	root.grid_snap = 1.0
	await frame()
	_paint(root, 0, Vector2i(0, 0), Vector2i(7, 7))
	root.rename_paint_layer(0, "Ground")
	root.add_paint_layer()
	root.paint_system.set_layer_y(3.0)
	_paint(root, 1, Vector2i(2, 2), Vector2i(5, 5))
	root.paint_system.raise_cells(1, Vector2i(2, 2), Vector2i(5, 5), 1.5)
	root.rename_paint_layer(1, "Balcony")
	await frame()
	var start: Array = _layers(root)
	var start_gen: Dictionary = _generated(root)
	note("layers", start)
	note("generated nodes by layer", start_gen)

	for index in [1, 0]:
		root.set_active_paint_layer(index)
		var before: Dictionary = root.capture_undo_state()
		root.remove_active_paint_layer()
		await frame()
		var after: Dictionary = root.capture_undo_state()
		var removed: Array = _layers(root)
		note("after removing index %d" % index, [removed, _generated(root)])
		root.restore_state(before)
		await frame()
		var undone: Array = _layers(root)
		var undone_gen: Dictionary = _generated(root)
		note("after undo", [undone, undone_gen, "active %d" % root.get_active_paint_layer_index()])
		if undone != start:
			flag(
				"undoing the removal of paint layer %d does not give the layers back" % index,
				[start, undone]
			)
		if undone_gen != start_gen:
			flag(
				"undoing the removal of paint layer %d does not rebuild its floors" % index,
				[start_gen, undone_gen]
			)
		if root.get_active_paint_layer_index() != index:
			flag(
				"undoing a layer removal leaves a different layer active",
				(
					"layer %d was active and removed; after undo layer %d is"
					% [index, root.get_active_paint_layer_index()]
				)
			)
		root.restore_state(after)
		await frame()
		if _layers(root) != removed:
			flag(
				"redoing the removal of paint layer %d gives a different list" % index,
				[removed, _layers(root)]
			)
		root.restore_state(before)
		await frame()
	await drop_root(root)


## Paint is stored by cell, and a cell's size in the world is the layer grid's
## cell size, which `LevelRoot._set_grid_snap()` writes into every layer.
func _grid_snap_under_paint() -> void:
	note("-- the grid snap changed after a floor is painted --")
	var root: Node3D = await fresh_root("LayersSnap")
	await frame()
	var start_snap: float = root.grid_snap
	note("grid snap a level starts with", start_snap)
	var layer = root.paint_layers.get_active_layer()
	note("paint cell size a level starts with", layer.grid.cell_size)
	var lid := str(layer.layer_id)
	_paint(root, 0, Vector2i(0, 0), Vector2i(7, 7))
	await frame()
	var laid: AABB = _floor_bounds(root, lid)
	note("an 8 x 8 cell room, as laid", laid)

	# The mapper tightens the snap to place a detail brush. Nothing is repainted.
	root.grid_snap = 0.125
	await frame()
	note("paint cell size after the snap changed", layer.grid.cell_size)
	note("the room's floor right after the change", _floor_bounds(root, lid))

	# One more cell, in the far corner of the same chunk. The room's floors are
	# the ones whose centre is short of x = 3.5, whichever size the room is now.
	_paint(root, 0, Vector2i(31, 31), Vector2i(31, 31))
	await frame()
	var after_stroke: AABB = _floor_bounds(root, lid, 3.5)
	note("the room's floor after one more cell in its chunk", after_stroke)

	# And through an undo, which rebuilds every layer.
	root.restore_state(root.capture_undo_state())
	await frame()
	var after_undo: AABB = _floor_bounds(root, lid, 3.5)
	note("the room's floor after a restore_state", after_undo)
	if (
		not after_stroke.size.is_equal_approx(laid.size)
		or not after_undo.size.is_equal_approx(laid.size)
	):
		known(
			2011,
			"changing the grid snap resizes every floor already painted",
			(
				(
					"An 8 x 8 cell room painted at the starting snap %s laid a floor %s."
					+ " Setting the snap to 0.125 sets every paint layer's cell size to it"
					+ " (LevelRoot._sync_paint_grid_from_root), and cells are stored by index,"
					+ " so the next stroke anywhere in that chunk rebuilds the same room as %s"
					+ " and an undo, a load or a scene reopen as %s. Nothing was repainted and"
					+ " nothing says the floor moved; heightmap terrain scales the same way"
				)
				% [start_snap, laid.size, after_stroke.size, after_undo.size]
			)
		)
	await drop_root(root)


## Confirmed connectors name their two layers by list index.
func _connectors_after_a_removal() -> void:
	note("-- a confirmed connector, then a layer below it removed --")
	var root: Node3D = await fresh_root("LayersConnector")
	root.grid_snap = 1.0
	await frame()
	# Layer 0 is a scratch layer the mapper later deletes; 1 and 2 are two floors
	# a connector joins.
	_paint(root, 0, Vector2i(-20, -20), Vector2i(-17, -17))
	root.add_paint_layer()
	root.paint_system.set_layer_y(1.0)
	_paint(root, 1, Vector2i(0, 0), Vector2i(3, 3))
	root.add_paint_layer()
	root.paint_system.set_layer_y(2.0)
	_paint(root, 2, Vector2i(4, 0), Vector2i(7, 3))
	var confirmed: Dictionary = root.paint_system.confirm_connectors(
		2, Vector2i(4, 0), Vector2i(4, 3), 1
	)
	note("confirm_connectors", confirmed.get("connectors", confirmed.get("error")))
	var built_before: Array = _connector_layers(root)
	note("connectors that build, by the layer ids they join", built_before)
	note("auto connectors at bake", root.bake_auto_connectors)
	await root.bake(false, false)
	await frame()
	var baked_before := _baked_connectors(root)
	note("connector meshes in the bake", baked_before)

	root.set_active_paint_layer(0)
	root.remove_active_paint_layer()
	await frame()
	var built_after: Array = _connector_layers(root)
	note("layers after removing the scratch layer", _layers(root))
	note("confirmed connector definitions kept", root.paint_tool.capture_connector_defs())
	note("connectors that build now", built_after)
	await root.bake(false, false)
	await frame()
	var baked_after := _baked_connectors(root)
	note("connector meshes in the bake now", baked_after)
	if built_after != built_before:
		known(
			2009,
			"removing a paint layer drops or moves the confirmed connectors of the layers after it",
			(
				(
					"A connector confirmed between layer_1 (y 1) and layer_2 (y 2) builds as %s."
					+ " Removing layer_0, which it does not touch, leaves the definition saying"
					+ " layers %s, which now name %s, so it builds as %s. ConnectorDef holds"
					+ " from_layer_index / to_layer_index and remove_active_paint_layer() never"
					+ " renumbers them. A bake had %d connector mesh(es) before the removal and"
					+ " has %d after, with auto connectors off as a level starts, and the"
					+ " .hflevel keeps the stale numbers"
				)
				% [
					built_before,
					_def_indices(root),
					_names_at(root, _def_indices(root)),
					built_after,
					baked_before,
					baked_after,
				]
			)
		)
	await drop_root(root)


func _baked_connectors(root: Node3D) -> int:
	var baked := root.get_node_or_null("BakedGeometry")
	if baked == null:
		return -1
	return baked.find_children("AutoConnector_*", "MeshInstance3D", true, false).size()


func _def_indices(root: Node3D) -> Array:
	var out: Array = []
	for d in root.paint_tool.connector_defs:
		out.append([d.from_layer_index, d.to_layer_index])
	return out


func _names_at(root: Node3D, pairs: Array) -> Array:
	var out: Array = []
	var layers: Array = root.paint_layers.layers
	for pair in pairs:
		var names: Array = []
		for i in pair:
			names.append(str(layers[i].layer_id) if i >= 0 and i < layers.size() else "<none>")
		out.append(names)
	return out


## Which confirmed connectors build a mesh, by the ids of the layers they join.
func _connector_layers(root: Node3D) -> Array:
	var out: Array = []
	var gen := HFAutoConnector.new()
	var layers: Array = root.paint_layers.layers
	for d in root.paint_tool.connector_defs:
		var results: Array = gen.generate_definitions([d], root.paint_layers)
		var meshes := 0
		for entry in results:
			if entry.get("mesh") != null:
				meshes += 1
		if meshes == 0:
			continue
		var a: String = str(layers[d.from_layer_index].layer_id)
		var b: String = str(layers[d.to_layer_index].layer_id)
		out.append("%s-%s" % [a, b] if a < b else "%s-%s" % [b, a])
	return out


## Rename refuses a name another row shows. Does Add?
func _a_name_add_hands_out_again() -> void:
	note("-- a layer renamed to the name Add gives the next layer --")
	var root: Node3D = await fresh_root("LayersNames")
	await frame()
	root.add_paint_layer()
	note("rows", root.get_paint_layer_names())
	note("renaming layer 0 to 'layer_1', which row 1 shows", root.rename_paint_layer(0, "layer_1"))
	note("renaming layer 0 to 'layer_2', which no row shows", root.rename_paint_layer(0, "layer_2"))
	root.add_paint_layer()
	var rows: Array = root.get_paint_layer_names()
	note("rows after Add", rows)
	var counts: Dictionary = {}
	for row in rows:
		counts[row] = int(counts.get(row, 0)) + 1
	for row in counts:
		if counts[row] > 1:
			known(
				2013,
				"Add Layer gives a new layer the name another row already shows",
				(
					(
						"rename_paint_layer() refuses a name another row shows (#321), so"
						+ " 'layer_1' was refused, but 'layer_2' was taken while no row showed it."
						+ " add_paint_layer() then minted the id layer_2, and the new row shows"
						+ " its id: the list reads %s. find_paint_layer('%s'), which the agent"
						+ " bridge and the palette resolve names through, answers %d"
					)
					% [rows, row, root.paint_system.find_paint_layer(str(row))]
				)
			)
	await drop_root(root)


## The Paint tab's Height Scale and Layer Y spins and its Rename button, against
## the undo stack. Each handler's body, and then what an undo and a redo of the
## stroke before them leave of what they set.
func _layer_settings_and_undo() -> void:
	note("-- Height Scale, Layer Y and Rename, then undo and redo the stroke before them --")
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_paint_handler.gd")
	for handler in ["on_height_scale_changed", "on_layer_y_changed", "on_paint_layer_rename"]:
		var start := source.find("static func %s(" % handler)
		var body := source.substr(start, source.find("\n\n\n", start) - start)
		note("%s commits an undo step" % handler, body.contains("_commit"))
	var root: Node3D = await fresh_root("LayersSettings")
	root.grid_snap = 1.0
	await frame()
	root.generate_heightmap_noise({"seed": 5})
	root.paint_system.paint_cells(0, Vector2i(0, 0), Vector2i(7, 7), true)
	# A stroke, recorded as the plugin records one.
	var before: Dictionary = root.capture_undo_state()
	root.paint_system.paint_cells(0, Vector2i(8, 0), Vector2i(9, 7), true)
	var after: Dictionary = root.capture_undo_state()
	# Then the three edits, as the dock makes them.
	root.set_heightmap_scale(2.0)
	root.set_layer_y(1.5)
	root.rename_paint_layer(0, "Hills")
	var read := func() -> Array:
		var layer = root.paint_layers.get_active_layer()
		return [layer.height_scale, layer.grid.layer_y, root.paint_system.paint_layer_name(layer)]
	var set_to: Array = read.call()
	note("height scale, layer y, name as set", set_to)
	root.restore_state(before)
	await frame()
	note("after Ctrl+Z of the stroke", read.call())
	root.restore_state(after)
	await frame()
	var redone: Array = read.call()
	note("after Ctrl+Y of the stroke", redone)
	if redone != set_to:
		known(
			2012,
			"Height Scale, Layer Y and Rename take no undo step, so undo and redo of the stroke before them throws them away",
			(
				(
					"on_height_scale_changed(), on_layer_y_changed() and on_paint_layer_rename()"
					+ " call the level straight, with no _commit_state_action(), while"
					+ " capture_state() holds all three. Set to %s after a paint stroke, one Ctrl+Z"
					+ " (the stroke's step) and one Ctrl+Y give %s: the redo state was captured"
					+ " before them, and no step in the history can bring them back"
				)
				% [set_to, redone]
			)
		)
	await drop_root(root)
