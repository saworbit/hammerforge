@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether the bake ever actually chunks a level.
##
## Chunking is the answer to a big map: cut the level into boxes, run a CSG tree
## per box, and never hand Godot one combiner with four thousand children. The
## dock has a Chunk Size spin, `get_recommended_chunk_size()` suggests a value,
## `get_level_health()` says "Consider Chunking" above fifty nodes, and
## `bake_dry_run()` reports a chunk count.
##
## `bake_chunked()` opens with a bail-out:
##
##     if _chunking_has_cross_boundary_interactions(chunks):
##         return await bake_single(layer, options)
##
## and that predicate is true as soon as any two brushes assigned to *different*
## chunks have intersecting world AABBs. Two walls meeting at a corner is two
## intersecting AABBs. So the question is not whether chunking is correct, it is
## whether any level a person would build ever reaches it.


func id() -> String:
	return "bake-chunking"


func summary() -> String:
	return "whether a level a mapper would build ever reaches the chunked bake"


func run() -> void:
	await _the_default_size_against_the_recommended_one()
	await _a_grid_of_separated_pillars()
	await _the_same_pillars_joined_by_a_floor()
	await _a_room_and_a_corridor()
	await _what_the_dry_run_tells_the_mapper()


func _chunk_report(root: Node3D, label: String) -> Dictionary:
	var dry: Dictionary = root.bake_dry_run()
	var report := {
		"brushes": root.get_live_brush_count(),
		"chunk_size": root.bake_chunk_size,
		"recommended": root.get_recommended_chunk_size(),
		"chunk_count": root.get_bake_chunk_count(),
		"health": root.get_level_health().get("label", "?"),
		"dry_chunks": dry.get("chunk_count", -1),
	}
	note(label, report)
	return report


func _the_default_size_against_the_recommended_one() -> void:
	note("-- the chunk size a level starts with --")
	var root: Node3D = await fresh_root()
	note("bake_chunk_size default", root.bake_chunk_size)
	# Forty brushes over a 2000-unit span: the point where the dock starts
	# saying "Consider Chunking".
	for i in 40:
		box(root, Vector3(2, 2, 2), Vector3((i % 8) * 8, 0, (i / 8) * 8))
		await frame()
	var r := _chunk_report(root, "40 separated 2-cubes over 56x24 units")
	if (
		float(r["recommended"]) > 0.0
		and absf(float(r["recommended"]) - float(r["chunk_size"])) > 1.0
	):
		known(
			656,
			"the default chunk size is nothing like the recommended one",
			(
				(
					"a level starts at bake_chunk_size=%s and `get_recommended_chunk_size()` "
					+ "says %s for this level. Nothing applies the recommendation, and at %s "
					+ "units every brush a mapper draws at the default 128 size spans a "
					+ "chunk boundary"
				)
				% [r["chunk_size"], r["recommended"], r["chunk_size"]]
			)
		)


## The best case for chunking: pillars with clear air between them, at a chunk
## size that fits each pillar inside one chunk.
func _a_grid_of_separated_pillars() -> void:
	note("-- 25 pillars, 16 apart, chunk size 8 --")
	var root: Node3D = await fresh_root()
	root.bake_chunk_size = 8.0
	for i in 25:
		box(root, Vector3(2, 4, 2), Vector3((i % 5) * 16, 2, (i / 5) * 16))
		await frame()
	var r := _chunk_report(root, "separated pillars")
	if int(r["chunk_count"]) <= 1:
		flag(
			"even 25 pillars with 14 units of air between them bake as one chunk",
			"get_bake_chunk_count() says %s" % r["chunk_count"]
		)
	else:
		note("chunking reached with fully separated brushes", r["chunk_count"])
	var ok = await root.bake(true, false, 1)
	await frame()
	note("bake returned", ok)
	note("bake_use_face_materials", root.bake_use_face_materials)
	var chunks_made := _chunk_nodes(root)
	note("BakedChunk_ nodes in the result", chunks_made)
	if chunks_made == 0 and int(r["chunk_count"]) > 1:
		known(
			656,
			"the bake ignores the chunk size on the path every level uses",
			(
				(
					"bake_dry_run() promises %s chunks and the bake makes 0. "
					+ "`bake_chunked()` is only reached from the `else` of the "
					+ "`use_face_material_path` branch in `_bake_impl()`, and "
					+ "`bake_use_face_materials` defaults to true, so the Chunk Size spin, "
					+ "`get_recommended_chunk_size()` and the dry run's chunk count all "
					+ "describe a code path a default level never takes"
				)
				% r["chunk_count"]
			)
		)
	# The same level with face materials off, which is the only way in.
	root.bake_use_face_materials = false
	var ok2 = await root.bake(true, false, 1)
	await frame()
	note("with bake_use_face_materials off: bake returned", ok2)
	note("with bake_use_face_materials off: BakedChunk_ nodes", _chunk_nodes(root))


## The same pillars with a floor under them, which is the first thing anyone
## adds. One floor brush intersects every pillar, and the pillars are in
## different chunks.
func _the_same_pillars_joined_by_a_floor() -> void:
	note("-- the same pillars, plus one floor slab under them --")
	var root: Node3D = await fresh_root()
	root.bake_chunk_size = 8.0
	for i in 25:
		box(root, Vector3(2, 4, 2), Vector3((i % 5) * 16, 2, (i / 5) * 16))
		await frame()
	box(root, Vector3(80, 0.5, 80), Vector3(32, -0.25, 32))
	await frame()
	var r := _chunk_report(root, "pillars on a floor")
	if int(r["chunk_count"]) <= 1:
		flag(
			"adding a floor under the pillars drops the bake back to one chunk",
			(
				"one slab's world AABB intersects every pillar's, and the pillars are "
				+ "assigned to different chunks, so `_chunking_has_cross_boundary_"
				+ "interactions()` is true and `bake_chunked()` calls `bake_single()`. "
				+ "A floor is in every level"
			)
		)


## And the shape a level actually is: a room with walls that meet.
func _a_room_and_a_corridor() -> void:
	note("-- two hollowed rooms and a corridor, at the recommended chunk size --")
	var root: Node3D = await fresh_root()
	var a = box(root, Vector3(8, 3, 8), Vector3(0, 1.5, 0))
	await frame()
	root.hollow_brush_by_id(a.brush_id, 0.25)
	await frame()
	var b = box(root, Vector3(8, 3, 8), Vector3(0, 1.5, -16))
	await frame()
	root.hollow_brush_by_id(b.brush_id, 0.25)
	await frame()
	for i in 4:
		box(root, Vector3(2, 0.25, 8), Vector3(0, i * 1.0, -8))
		await frame()
	root.bake_chunk_size = maxf(1.0, root.get_recommended_chunk_size())
	var r := _chunk_report(root, "two rooms and a corridor, chunk size set to the recommendation")
	if int(r["chunk_count"]) <= 1:
		flag(
			"a level made of rooms and a corridor cannot be chunked at any size",
			(
				(
					"brushes that touch is what a room is: six walls meeting at twelve "
					+ "edges. Set the chunk size to whatever `get_recommended_chunk_size()` "
					+ "returns (%s here) and the count is still %s"
				)
				% [r["chunk_size"], r["chunk_count"]]
			)
		)
	# And sweep every size, so the report is not about one unlucky number.
	var sizes: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0]
	var counts: Array[String] = []
	for size in sizes:
		root.bake_chunk_size = size
		counts.append("%s->%s" % [size, root.get_bake_chunk_count()])
	note("chunk count at every size", ", ".join(counts))


## What a mapper following the dock's own advice would see.
func _what_the_dry_run_tells_the_mapper() -> void:
	note("-- the numbers the dock puts in front of the mapper --")
	var root: Node3D = await fresh_root()
	for i in 120:
		box(root, Vector3(2, 2, 2), Vector3((i % 12) * 6, 0, (i / 12) * 6))
		await frame()
	note("brushes", root.get_live_brush_count())
	note("health", root.get_level_health())
	note("recommended chunk size", root.get_recommended_chunk_size())
	root.bake_chunk_size = root.get_recommended_chunk_size()
	note("bake_chunk_size after taking the advice", root.bake_chunk_size)
	if not is_equal_approx(root.bake_chunk_size, root.get_recommended_chunk_size()):
		flag(
			"the recommended chunk size is outside the range the property accepts",
			(
				(
					"get_recommended_chunk_size() returned %s and setting it left the "
					+ "property at %s"
				)
				% [root.get_recommended_chunk_size(), root.bake_chunk_size]
			)
		)
	note("chunk count at the recommended size", root.get_bake_chunk_count())


func _chunk_nodes(root: Node3D) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if str(child.name).begins_with("BakedChunk_"):
				n += 1
			stack.append(child)
	return n
