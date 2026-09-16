@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The arithmetic under Floor Paint: the world/cell grid, the layer list, and
## the ids the reconciler builds its node names out of.
##
## `HFPaintGrid` turns a cursor position into a cell and a cell back into world
## space, and everything painted goes through it. `HFPaintLayerManager` keeps
## the layer list and mints the ids `HFHash` prints into every generated node's
## name — the id is identity, not a label, so anything that can make two layers
## share one, or make an id unparseable, reaches the geometry.

const GridType = preload("res://addons/hammerforge/paint/hf_paint_grid.gd")
const ManagerType = preload("res://addons/hammerforge/paint/hf_paint_layer_manager.gd")
const HashType = preload("res://addons/hammerforge/paint/hf_hash.gd")


func id() -> String:
	return "paint-grid"


func summary() -> String:
	return "the paint grid's world/cell arithmetic, the layer list, and the ids it mints"


func run() -> void:
	_grid_round_trip()
	_grid_edges()
	await _layer_ids()
	_hash_ids()


func _grid_round_trip() -> void:
	var grid = GridType.new()
	grid.cell_size = 4.0
	var bad: Array = []
	for point in [
		Vector3(0, 0, 0),
		Vector3(3.9, 0, 3.9),
		Vector3(-0.1, 0, -0.1),
		Vector3(-4.0, 0, 8.0),
		Vector3(101.5, 12.0, -37.25),
	]:
		var cell: Vector2i = grid.world_to_cell(point)
		var centre: Vector3 = grid.uv_to_world(grid.cell_center_uv(cell))
		var back: Vector2i = grid.world_to_cell(centre)
		note("%s -> cell %s -> centre %s -> cell %s" % [point, cell, centre, back])
		if back != cell:
			bad.append("%s: %s became %s" % [point, cell, back])
	if not bad.is_empty():
		flag(
			"a cell's own centre does not land back in that cell",
			(
				(
					"the paint tool stamps at cell centres, so a centre that rounds into the"
					+ " neighbouring cell paints next to the cursor: %s"
				)
				% str(bad)
			)
		)


func _grid_edges() -> void:
	var grid = GridType.new()
	for size in [0.0, -1.0, 0.0001]:
		grid.cell_size = size
		var cell: Vector2i = grid.world_to_cell(Vector3(10, 0, 10))
		note("cell_size %s: world (10,0,10) -> cell %s" % [size, cell])
		if size == 0.0:
			# A zero cell size divides by zero on the way in. Whatever comes out
			# is then used as a Dictionary key and a chunk index.
			if cell != Vector2i.ZERO:
				flag(
					"a zero paint cell size produces a cell index out of a division by zero",
					(
						(
							"world_to_cell divides by cell_size with no guard and returns %s;"
							+ " that value is used as a chunk key and a wall-height key"
						)
						% str(cell)
					)
				)
	grid.cell_size = 4.0
	# A rotated plane is what `basis` is for. A zero basis is not invertible.
	grid.basis = Basis.from_scale(Vector3.ZERO)
	var degenerate: Vector2i = grid.world_to_cell(Vector3(10, 0, 10))
	note("zero-scale basis: world (10,0,10) -> cell %s" % str(degenerate))


func _layer_ids() -> void:
	var manager = ManagerType.new()
	_tree.get_root().add_child(manager)
	await frame()
	manager.clear_layers()
	var a = manager.create_layer(&"floor", 0.0)
	var b = manager.create_layer(&"floor", 8.0)
	var c = manager.create_layer(&"floor", 16.0)
	note("three layers all asked for the id 'floor'", [a.layer_id, b.layer_id, c.layer_id])
	if a.layer_id == b.layer_id or b.layer_id == c.layer_id:
		flag("two paint layers share one id", [a.layer_id, b.layer_id, c.layer_id])

	# A layer id is also a node name and a component of every generated node's
	# id. What a mapper types into Rename is a display name, but the id comes
	# from somewhere too -- so what happens to an id with structure in it is
	# worth knowing.
	var awkward = manager.create_layer(&"a:b:c", 24.0)
	note("id with colons", awkward.layer_id)
	note("node name for it", awkward.name)
	var gid: StringName = HashType.floor_id(
		awkward.layer_id, Vector2i(1, 2), Vector2i(0, 0), Vector2i(4, 4)
	)
	note("floor id built from it", gid)
	note("chunk tag read back out", HashType.chunk_tag_from_id(gid))
	if HashType.chunk_tag_from_id(gid) != "1,2":
		known(
			548,
			"the chunk tag cannot be read back out of a generated node id",
			(
				(
					"`chunk_tag_from_id()` splits on ':' and takes field 4, so a layer id"
					+ " containing a colon shifts every field; the id above reports its chunk"
					+ " as '%s' instead of '1,2', and chunk-scoped cleanup reads that tag"
				)
				% HashType.chunk_tag_from_id(gid)
			)
		)

	note("layers before remove", manager.layers.size())
	manager.set_active_layer(1)
	manager.remove_layer(0)
	await frame()
	note(
		"after removing index 0 with index 1 active",
		[manager.layers.size(), manager.active_layer_index]
	)
	note(
		"active layer is now",
		manager.get_active_layer().layer_id if manager.get_active_layer() else "<none>"
	)
	manager.remove_layer(99)
	manager.set_active_layer(-1)
	note("out-of-range remove and select left the list at", manager.layers.size())
	manager.queue_free()
	await frame()


func _hash_ids() -> void:
	var floor_a: StringName = HashType.floor_id(
		&"layer_0", Vector2i(0, 0), Vector2i(0, 0), Vector2i(4, 4)
	)
	var floor_b: StringName = HashType.floor_id(
		&"layer_0", Vector2i(0, 0), Vector2i(0, 0), Vector2i(4, 4)
	)
	note("the same floor twice", floor_a == floor_b)
	var wall_a: StringName = HashType.wall_id(
		&"layer_0", Vector2i(0, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)
	)
	note("wall id", wall_a)
	note("chunk tag from a wall id", HashType.chunk_tag_from_id(wall_a))
	var short_a: StringName = HashType.short_wall_id(&"layer_0", Vector2i(0, 0), "a")
	var short_b: StringName = HashType.short_wall_id(&"layer_0", Vector2i(0, 0), "b")
	note("two different wall signatures", [short_a, short_b])
	if short_a == short_b:
		flag("two different walls hash to one id", [short_a, short_b])
	note("hash32 of the empty string", HashType.hash32(""))
