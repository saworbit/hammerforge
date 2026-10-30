@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Heightmap terrain as a mapper shapes it: Generate Noise over painted ground,
## then the Sculpt buttons.
##
## `heightmap-io` measures what a save does to the heights and `heightmap-convert`
## what Convert to Heightmap makes. Neither sculpts, and neither reads the mesh
## the terrain is built into against the heights it was built from. So: paint,
## sculpt through the paint tool's own input path with a camera looking down,
## and read every chunk's mesh against `get_height_at()` -- at a chunk edge, a
## heightmap's width away, across the origin, through an undo, on a heightmap
## whose samples lie outside 0..1 -- and fire rays down onto the baked terrain.

const HFStroke = preload("res://addons/hammerforge/paint/hf_stroke.gd")


func id() -> String:
	return "terrain-sculpt"


func summary() -> String:
	return "what a sculpt stroke rebuilds against what it changed, and where noise terrain meets itself"


## #2007, #2008 and #2014 are fixed, so each of them flags as new if it comes
## back.
func expected_issues() -> Array[int]:
	return []


func run() -> void:
	await _sculpt_at_a_chunk_edge()
	await _a_sculpt_a_heightmap_away()
	await _a_sculpt_on_noise_and_the_ground_256_cells_on()
	await _noise_across_the_origin()
	await _sculpt_through_undo()
	await _sculpt_above_one()
	await _baked_ground_under_a_ray()


## A flat heightmap of `size` square at `value`, the way an imported one arrives.
func _flat_heightmap(size: int, value: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RF)
	img.fill(Color(value, 0.0, 0.0, 1.0))
	return img


## Fill a rectangle of cells, and take the chunks it dirtied the way a stroke's
## end does, so the next sculpt rebuilds only what it dirties itself.
func _paint_rect(layer, from: Vector2i, to: Vector2i) -> int:
	var n := 0
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			layer.set_cell(Vector2i(x, y), true)
			n += 1
	layer.consume_dirty_chunks()
	return n


## One click of a sculpt tool at the centre of `cell`, through the paint tool's
## own press and release, from a camera looking straight down at it.
func _sculpt(root: Node3D, cell: Vector2i, tool_id: int, radius: float) -> void:
	var layer = root.paint_layers.get_active_layer()
	var cs: float = layer.grid.cell_size
	var target := Vector3((cell.x + 0.5) * cs, layer.grid.layer_y, (cell.y + 0.5) * cs)
	var cam := Camera3D.new()
	_tree.get_root().add_child(cam)
	cam.global_position = target + Vector3(0, 40, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	var centre: Vector2 = cam.get_viewport().get_visible_rect().size * 0.5
	var tool = root.paint_tool
	tool.tool = tool_id
	tool.sculpt_radius = radius
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = centre
	tool.handle_input(cam, press, centre)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = centre
	tool.handle_input(cam, release, centre)
	tool.tool = HFStroke.Tool.PAINT
	cam.queue_free()


## Every terrain chunk node, by its chunk tag.
func _chunk_nodes(root: Node3D) -> Dictionary:
	var out: Dictionary = {}
	var holder = root.paint_tool.reconciler.heightmap_floors_root
	for child in holder.get_children():
		if child is MeshInstance3D and child.has_meta("hf_chunk"):
			out[str(child.get_meta("hf_chunk"))] = child
	return out


## Vertices of a chunk's mesh, in world space, whose height disagrees with the
## layer's heightmap at that corner by more than a millimetre.
func _stale_vertices(layer, node: MeshInstance3D) -> Array:
	var bad: Array = []
	if node.mesh == null:
		return bad
	var arrays: Array = node.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cs: float = layer.grid.cell_size
	var seen: Dictionary = {}
	for v in verts:
		var world: Vector3 = node.global_transform * v
		var corner := Vector2i(roundi(world.x / cs), roundi(world.z / cs))
		if seen.has(corner):
			continue
		seen[corner] = true
		var want: float = layer.grid.layer_y + layer.get_height_at(corner)
		if absf(world.y - want) > 0.001:
			bad.append([corner, snappedf(world.y, 0.001), snappedf(want, 0.001)])
	return bad


## The height of every corner the terrain meshes hold, by corner, in world space.
func _mesh_heights(nodes: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for tag in nodes:
		var node: MeshInstance3D = nodes[tag]
		if node.mesh == null:
			continue
		var verts: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var world: Vector3 = node.global_transform * v
			out[Vector2i(roundi(world.x), roundi(world.z))] = snappedf(world.y, 0.001)
	return out


## A sculpt whose brush reaches the first column of a chunk changes the corners
## that chunk shares with the one before it. Is the one before it rebuilt?
func _sculpt_at_a_chunk_edge() -> void:
	note("-- a sculpt that reaches the first column of a chunk --")
	var root: Node3D = await fresh_root("SculptEdge")
	root.grid_snap = 1.0
	await frame()
	var layer = root.paint_layers.get_active_layer()
	layer.heightmap = _flat_heightmap(64, 0.2)
	layer.height_scale = 4.0
	note("chunk size", layer.chunk_size)
	note("cells painted", _paint_rect(layer, Vector2i(16, 0), Vector2i(48, 8)))
	root.paint_system.regenerate_paint_layers()
	await frame()
	var nodes := _chunk_nodes(root)
	note("terrain chunks before", nodes.keys())
	for tag in nodes:
		var stale := _stale_vertices(layer, nodes[tag])
		if not stale.is_empty():
			note("chunk %s disagrees with the heights before any sculpt" % tag, stale.slice(0, 4))

	# Radius 3, the dock's default, at cell 35 reaches cells 32..38: the first
	# column of chunk 1, whose corners at x = 32 are also the last corners of
	# chunk 0. Four dabs on the one spot, as a mapper builds a mound up.
	for _i in 4:
		_sculpt(root, Vector2i(35, 4), HFStroke.Tool.SCULPT_RAISE, 3.0)
	await frame()
	note("height at corner (32, 4) after the sculpt", layer.get_height_at(Vector2i(32, 4)))
	note("height at corner (35, 4) after the sculpt", layer.get_height_at(Vector2i(35, 4)))
	nodes = _chunk_nodes(root)
	var per_chunk: Dictionary = {}
	for tag in nodes:
		per_chunk[tag] = _stale_vertices(layer, nodes[tag])
	for tag in per_chunk:
		note("chunk %s corners that disagree with the heightmap" % tag, per_chunk[tag].size())
	var left: Array = per_chunk.get("0,0", [])
	if not left.is_empty():
		flag(
			"a sculpt at a chunk's first column leaves the chunk before it on the old heights",
			(
				(
					"Four dabs of Raise, radius 3, at cell (35, 4) on 32-cell chunks change the"
					+ " heightmap at x = 32..38. Chunk 1,0 is rebuilt; chunk 0,0, whose last quads end on"
					+ " the x = 32 corners, is not, so %d of its corners stand at the old height:"
					+ " %s ([corner, mesh y, heightmap y]). The two chunks part along x = 32 with"
					+ " a step and a see-through slit, in the editor and in a bake taken now,"
					+ " until something rebuilds the whole layer"
				)
				% [left.size(), str(left.slice(0, 4))]
			)
		)
	# What a full rebuild makes of the same heights.
	root.paint_system.regenerate_paint_layers()
	await frame()
	nodes = _chunk_nodes(root)
	var after_full := 0
	for tag in nodes:
		after_full += _stale_vertices(layer, nodes[tag]).size()
	note("corners that disagree after a full rebuild", after_full)
	await drop_root(root)


## A heightmap with no place, as a level saved before #2007 has, reads repeating
## every `width` cells. A sculpt wrote its pixels, and so moved the ground at
## every cell that read them; it keeps its own samples per chunk now.
func _a_sculpt_a_heightmap_away() -> void:
	note("-- a sculpt, and the ground a heightmap's width away --")
	var root: Node3D = await fresh_root("SculptFar")
	root.grid_snap = 1.0
	await frame()
	var layer = root.paint_layers.get_active_layer()
	layer.heightmap = _flat_heightmap(64, 0.2)
	layer.height_scale = 4.0
	_paint_rect(layer, Vector2i(0, 0), Vector2i(90, 4))
	root.paint_system.regenerate_paint_layers()
	await frame()
	var here := Vector2i(10, 2)
	var there := Vector2i(10 + 64, 2)
	var before_there: float = layer.get_height_at(there)
	_sculpt(root, here, HFStroke.Tool.SCULPT_RAISE, 2.0)
	await frame()
	var after_here: float = layer.get_height_at(here)
	var after_there: float = layer.get_height_at(there)
	note("height at %s after the sculpt" % here, after_here)
	note("height at %s, 64 cells away, before / after" % there, [before_there, after_there])
	var nodes := _chunk_nodes(root)
	var stale_far: Array = _stale_vertices(layer, nodes["2,0"]) if nodes.has("2,0") else []
	note("corners of chunk 2,0 off the heightmap after the sculpt", stale_far.size())
	if not is_equal_approx(before_there, after_there):
		flag(
			"a sculpt also raises the ground a heightmap's width away, unseen until a rebuild",
			(
				(
					"Raise at cell %s on a 64-pixel heightmap moved the ground at cell %s from"
					+ " %.3f to %.3f: HFPaintLayer.get_height_at() and the sculpt both wrap the"
					+ " cell with posmod, so every cell 64 apart reads and writes one pixel. The"
					+ " stroke rebuilds only the chunks round the cursor, so %d corners of chunk"
					+ " 2,0 stay at the old height until the layer is rebuilt (an undo, a load),"
					+ " and then the second hill appears. Generate Noise makes a 256-pixel map, so"
					+ " on painted ground wider than 256 cells every sculpt lands twice"
				)
				% [here, there, before_there, after_there, stale_far.size()]
			)
		)
	await drop_root(root)


## Generate Noise made a 256 square map, so on ground wider than 256 cells every
## sculpt landed twice (#2007).
func _a_sculpt_on_noise_and_the_ground_256_cells_on() -> void:
	note("-- a sculpt on noise ground, and the ground 256 cells on --")
	var root: Node3D = await fresh_root("SculptNoiseFar")
	root.grid_snap = 1.0
	await frame()
	root.generate_heightmap_noise({})
	root.set_heightmap_scale(4.0)
	var layer = root.paint_layers.get_active_layer()
	_paint_rect(layer, Vector2i(0, 0), Vector2i(300, 4))
	root.paint_system.regenerate_paint_layers()
	await frame()
	var here := Vector2i(10, 2)
	var there := Vector2i(10 + 256, 2)
	var before_here: float = layer.get_height_at(here)
	var before_there: float = layer.get_height_at(there)
	_sculpt(root, here, HFStroke.Tool.SCULPT_RAISE, 2.0)
	await frame()
	note("height at %s before / after" % here, [before_here, layer.get_height_at(here)])
	note("height at %s before / after" % there, [before_there, layer.get_height_at(there)])
	var nodes := _chunk_nodes(root)
	var stale: Array = []
	for tag in nodes:
		stale.append_array(_stale_vertices(layer, nodes[tag]))
	note("terrain corners off the ground after the sculpt", stale.size())
	if not is_equal_approx(before_there, layer.get_height_at(there)):
		flag(
			"a sculpt on noise ground also lands 256 cells on",
			(
				"Raise at %s moved the ground at %s from %.3f to %.3f"
				% [here, there, before_there, layer.get_height_at(there)]
			)
		)
	if not stale.is_empty():
		flag("a sculpt on noise ground leaves terrain corners on the old height", stale.slice(0, 6))
	await drop_root(root)


## Generate Noise made a 256 square map that was not seamless, and the terrain
## read it with posmod, so cell -1 read pixel 255 next to cell 0 reading pixel 0.
## The layer samples the noise itself now (#2007). Ground painted round the
## origin is where a level starts.
func _noise_across_the_origin() -> void:
	note("-- Generate Noise over ground painted across the origin --")
	var root: Node3D = await fresh_root("NoiseOrigin")
	root.grid_snap = 1.0
	await frame()
	root.generate_heightmap_noise({})
	await frame()
	root.set_heightmap_scale(4.0)
	var layer = root.paint_layers.get_active_layer()
	note("noise", layer.get_height_noise())
	_paint_rect(layer, Vector2i(-16, -16), Vector2i(15, 15))
	root.paint_system.regenerate_paint_layers()
	await frame()
	# The rise across each cell edge, x then z, in world units over one cell.
	var worst_across := 0.0
	var worst_elsewhere := 0.0
	var worst_at := Vector2i.ZERO
	for z in range(-16, 17):
		for x in range(-15, 17):
			var step := absf(
				layer.get_height_at(Vector2i(x, z)) - layer.get_height_at(Vector2i(x - 1, z))
			)
			if x == 0:
				if step > worst_across:
					worst_across = step
					worst_at = Vector2i(x, z)
			else:
				worst_elsewhere = maxf(worst_elsewhere, step)
	for x in range(-16, 17):
		for z in range(-15, 17):
			var step := absf(
				layer.get_height_at(Vector2i(x, z)) - layer.get_height_at(Vector2i(x, z - 1))
			)
			if z == 0:
				if step > worst_across:
					worst_across = step
					worst_at = Vector2i(x, z)
			else:
				worst_elsewhere = maxf(worst_elsewhere, step)
	var cs: float = layer.grid.cell_size
	note(
		"steepest one-cell rise across x = 0 or z = 0",
		(
			"%.3f units at corner %s (%.0f degrees)"
			% [worst_across, worst_at, rad_to_deg(atan(worst_across / cs))]
		)
	)
	note(
		"steepest one-cell rise anywhere else",
		"%.3f units (%.0f degrees)" % [worst_elsewhere, rad_to_deg(atan(worst_elsewhere / cs))]
	)
	# The same thing read off the mesh the bake takes, not the heightmap.
	var nodes := _chunk_nodes(root)
	note("terrain chunks", nodes.keys())
	var mesh_y := _mesh_heights(nodes)
	var below := worst_at - (Vector2i(0, 1) if worst_at.y == 0 else Vector2i(1, 0))
	note(
		"the mesh at corners %s and %s" % [below, worst_at],
		[mesh_y.get(below, "<none>"), mesh_y.get(worst_at, "<none>")]
	)
	if worst_across > worst_elsewhere * 3.0 and worst_across > 0.25:
		flag(
			"noise terrain painted across the origin has a ridge along x = 0 and z = 0",
			(
				(
					"Ground painted from -16 to 15 at height scale 4 after Generate Noise rises"
					+ " %.2f units over one cell at %s (%.0f degrees) where the noise elsewhere"
					+ " never rises more than %.2f (%.0f degrees), a straight wall or trench"
					+ " along both axes through the level's origin"
				)
				% [
					worst_across,
					worst_at,
					rad_to_deg(atan(worst_across / cs)),
					worst_elsewhere,
					rad_to_deg(atan(worst_elsewhere / cs)),
				]
			)
		)
	await drop_root(root)


## Undo of a sculpt is a whole-level restore of the state captured before it.
func _sculpt_through_undo() -> void:
	note("-- a sculpt, undone and redone --")
	var root: Node3D = await fresh_root("SculptUndo")
	root.grid_snap = 1.0
	await frame()
	var layer = root.paint_layers.get_active_layer()
	layer.heightmap = _flat_heightmap(64, 0.3)
	layer.height_scale = 4.0
	_paint_rect(layer, Vector2i(0, 0), Vector2i(20, 20))
	root.paint_system.regenerate_paint_layers()
	await frame()
	var probe: Array[Vector2i] = [Vector2i(8, 8), Vector2i(10, 10), Vector2i(12, 9)]
	var read := func(l) -> Array:
		var out: Array = []
		for c in probe:
			out.append(snappedf(l.get_height_at(c), 0.000001))
		return out
	var before_heights: Array = read.call(layer)
	var before: Dictionary = root.capture_undo_state()
	_sculpt(root, Vector2i(10, 10), HFStroke.Tool.SCULPT_RAISE, 3.0)
	_sculpt(root, Vector2i(10, 10), HFStroke.Tool.SCULPT_SMOOTH, 3.0)
	await frame()
	var sculpted: Array = read.call(layer)
	var after: Dictionary = root.capture_undo_state()
	note("heights before / after the sculpt", [before_heights, sculpted])
	root.restore_state(before)
	await frame()
	var undone: Array = read.call(root.paint_layers.get_active_layer())
	root.restore_state(after)
	await frame()
	var redone: Array = read.call(root.paint_layers.get_active_layer())
	note("after undo / redo", [undone, redone])
	if undone != before_heights:
		flag("undo of a sculpt does not put the heights back", [before_heights, undone])
	if redone != sculpted:
		flag("redo of a sculpt does not put the sculpt back", [sculpted, redone])
	var nodes := _chunk_nodes(root)
	var stale := 0
	for tag in nodes:
		stale += _stale_vertices(root.paint_layers.get_active_layer(), nodes[tag]).size()
	note("corners off the heightmap after redo", stale)
	await drop_root(root)


## A heightmap is a float image and a save keeps samples outside 0..1 (#445): an
## imported EXR in metres, or Convert to Heightmap under brushes taller than the
## Height Scale, holds them. The sculpt clamps whatever it writes to 0..1.
func _sculpt_above_one() -> void:
	note("-- sculpting a heightmap whose samples lie outside 0..1 --")
	var root: Node3D = await fresh_root("SculptRange")
	root.grid_snap = 1.0
	await frame()
	var layer = root.paint_layers.get_active_layer()
	# Ground at 2 m, read as a metre-valued EXR is read: Height Scale 1.
	var img := _flat_heightmap(64, 2.0)
	for y in range(30, 40):
		for x in range(30, 40):
			img.set_pixel(x, y, Color(-0.5, 0.0, 0.0, 1.0))
	layer.heightmap = img
	layer.height_scale = 1.0
	_paint_rect(layer, Vector2i(0, 0), Vector2i(45, 45))
	root.paint_system.regenerate_paint_layers()
	await frame()
	var high := Vector2i(10, 10)
	var low := Vector2i(35, 35)
	var high_before: float = layer.get_height_at(high)
	var low_before: float = layer.get_height_at(low)
	_sculpt(root, high, HFStroke.Tool.SCULPT_RAISE, 3.0)
	_sculpt(root, low, HFStroke.Tool.SCULPT_LOWER, 3.0)
	await frame()
	var high_after: float = layer.get_height_at(high)
	var low_after: float = layer.get_height_at(low)
	note("Raise at %s: ground before / after" % high, [high_before, high_after])
	note("Lower at %s: ground before / after" % low, [low_before, low_after])
	if high_after < high_before or low_after > low_before:
		flag(
			"Raise lowers, and Lower raises, ground whose heightmap lies outside 0..1",
			(
				(
					"A heightmap at 2.0 (and -0.5 in a pit), Height Scale 1, as a metre-valued"
					+ " EXR imports. One click of Raise at %s took the ground from %.2f to %.2f"
					+ " and one click of Lower at %s took it from %.2f to %.2f: the whole brush"
					+ " disc snaps to the limit. HFPaintTool._apply_terrain_brush() clamps every"
					+ " sculpted sample to 0..1 (new_val = clamp(new_val, 0.0, 1.0)), though the"
					+ " heightmap is a float image whose saves keep values outside that range"
					+ " (#445) and Import takes EXR"
				)
				% [high, high_before, high_after, low, low_before, low_after]
			)
		)
	await drop_root(root)


## The bake turns each terrain chunk into a trimesh. A ray straight down at a
## point inside a cell should meet the triangle the heights there describe.
func _baked_ground_under_a_ray() -> void:
	note("-- the baked terrain under a ray, against the heights --")
	var root: Node3D = await fresh_root("SculptBake")
	root.grid_snap = 1.0
	await frame()
	root.generate_heightmap_noise({"seed": 3})
	root.set_heightmap_scale(4.0)
	var layer = root.paint_layers.get_active_layer()
	# Away from cell 0, where the map meets itself, and from the other cases.
	_paint_rect(layer, Vector2i(100, 100), Vector2i(115, 115))
	root.paint_system.regenerate_paint_layers()
	await frame()
	_sculpt(root, Vector2i(108, 108), HFStroke.Tool.SCULPT_RAISE, 3.0)
	await frame()
	await root.bake(false, false)
	for _i in 3:
		await _tree.physics_frame
	var space := root.get_world_3d().direct_space_state
	var worst := 0.0
	var misses := 0
	var rays := 0
	for z in range(101, 115, 3):
		for x in range(101, 115, 3):
			var u := 0.7
			var v := 0.3
			var h00: float = layer.get_height_at(Vector2i(x, z))
			var h10: float = layer.get_height_at(Vector2i(x + 1, z))
			var h11: float = layer.get_height_at(Vector2i(x + 1, z + 1))
			var want: float = layer.grid.layer_y + h00 * (1.0 - u) + h10 * (u - v) + h11 * v
			var at := Vector3(x + u, 0.0, z + v)
			var query := PhysicsRayQueryParameters3D.create(
				at + Vector3.UP * 50, at + Vector3.DOWN * 50
			)
			var hit := space.intersect_ray(query)
			rays += 1
			if hit.is_empty():
				misses += 1
				continue
			worst = maxf(worst, absf((hit["position"] as Vector3).y - want))
	note(
		"rays down onto the baked terrain",
		"%d, %d missed, worst height error %.4f" % [rays, misses, worst]
	)
	if misses > 0 or worst > 0.01:
		flag(
			"the baked terrain is not where the heightmap puts it",
			"%d of %d rays missed, worst error %.4f units" % [misses, rays, worst]
		)
	await drop_root(root)
