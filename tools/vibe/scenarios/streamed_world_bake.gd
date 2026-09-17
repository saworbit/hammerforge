@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Baking a world that is bigger than what is in memory.
##
## Region streaming is the Large Worlds feature: the user guide's own heading.
## A mapper turns it on so a terrain too big to hold at once can be edited, and
## the streamer keeps a neighbourhood resident and writes the rest out to
## `.hfr` files beside the level.
##
## `regions` checks the eviction loop's bookkeeping. The question after that is
## what a bake makes of a world in that state, because the bake collects the
## terrain meshes that are **in the tree** -- and an evicted region has none.


func id() -> String:
	return "streamed-world-bake"


func summary() -> String:
	return "whether a bake of a streamed world covers the parts that are not resident"


const LEVEL := "user://vibe_streamed.hflevel"


func _cleanup(root: Node3D) -> void:
	if FileAccess.file_exists(LEVEL):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEVEL))
	var dir := ProjectSettings.globalize_path("user://vibe_streamed.hfregions")
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func run() -> void:
	await _a_wide_terrain_baked_while_streaming()


func _terrain_nodes(node: Node, out: Array) -> Array:
	if str(node.name).begins_with("HMFloor") or str(node.name).contains("hf_floor"):
		out.append(node)
	for c in node.get_children():
		_terrain_nodes(c, out)
	return out


func _coverage(node: Node) -> AABB:
	var bounds := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh:
			var aabb: AABB = (n as MeshInstance3D).global_transform * n.mesh.get_aabb()
			if first:
				bounds = aabb
				first = false
			else:
				bounds = bounds.merge(aabb)
		for c in n.get_children():
			stack.append(c)
	return bounds


func _a_wide_terrain_baked_while_streaming() -> void:
	var root: Node3D = await fresh_root()
	_cleanup(root)
	var paint = root.paint_system
	var layer = root.paint_layers.get_active_layer()
	var chunk_size: int = root.paint_layers.chunk_size

	# The level has to exist on disk before a region can be written out, which
	# is what the guide says and what the eviction pass needs.
	root.save_hflevel(LEVEL)
	await HFVibe.settle_save(_tree, root, 3000)
	note("level written", HFVibe.file_size(LEVEL))

	# Streaming on, small regions, a small radius: the configuration the feature
	# exists for.
	paint.set_region_streaming_enabled(true)
	paint.set_region_size_cells(64)
	paint.set_region_streaming_radius(1)
	note("streaming enabled", paint.region_streaming_enabled)
	note("region size (cells)", paint.region_manager.region_size_cells)
	note("streaming radius (regions)", paint.region_manager.streaming_radius)

	# Paint a wide strip of ground -- 512 cells across, which at 64 cells a
	# region is eight regions wide, well outside a radius of 1.
	var painted := 0
	for cy in range(-2, 3):
		for cx in range(-256, 256, 8):
			layer.set_cell(Vector2i(cx, cy * 8), true)
			painted += 1
	await frame()
	note("cells painted, spanning", "%d cells over 512 cells of width" % painted)

	# Let the streamer do what it does when the mapper's cursor is at the origin.
	paint.load_initial_regions()
	await frame()
	var loaded: Array = paint.get_loaded_regions()
	note("regions resident after load_initial_regions()", loaded.size())
	note("which ones", loaded.slice(0, 8))

	if root.paint_system.has_method("regenerate_paint_layers"):
		root.paint_system.regenerate_paint_layers()
		for _i in 6:
			await frame()

	var live := _terrain_nodes(root, [])
	note("terrain nodes in the level tree", live.size())
	var live_bounds := _coverage(root)
	note("what the level tree covers", "%s .. %s" % [live_bounds.position, live_bounds.end])

	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		note("nothing baked", true)
		_cleanup(root)
		return
	var baked := _terrain_nodes(container, [])
	note("terrain nodes in the baked container", baked.size())
	var baked_bounds := _coverage(container)
	note("what the bake covers", "%s .. %s" % [baked_bounds.position, baked_bounds.end])

	# The strip is 512 cells wide. Whatever a cell is worth in world units, the
	# bake should cover the same ground the paint does.
	var grid_cell: float = layer.grid.cell_size if layer.grid else 1.0
	var want_width: float = 512.0 * grid_cell
	note("cell size", grid_cell)
	note("the painted strip is this wide, in world units", want_width)
	note("the bake is this wide", baked_bounds.size.x)
	if baked_bounds.size.x + 0.5 < want_width * 0.5:
		flag(
			"a bake of a streamed world covers only the resident regions",
			(
				(
					"Streaming on, regions of 64 cells, radius 1. A strip %.0f units wide was "
					+ "painted and %d region(s) are resident; the bake covers %.0f units. "
					+ "`collect_generated_heightmap_meshes()` collects the terrain that is in "
					+ "the scene tree, and an evicted region has none, so the baked level has "
					+ "holes exactly where the streamer had done its job. Nothing warns: the "
					+ "bake reports success and the missing ground looks like terrain that was "
					+ "never painted.\n\n"
					+ "The Large Worlds feature and the bake are the two halves of the same "
					+ "workflow -- a world too big to hold in memory is exactly the one that "
					+ "has to be baked in pieces -- and the bake has no pass that walks the "
					+ "region index. Loading every region for the duration of a full bake, or "
					+ "baking region by region and streaming as it goes, is what closes it; "
					+ "refusing the bake with a message naming the unloaded regions would at "
					+ "least stop it being silent."
				)
				% [want_width, loaded.size(), baked_bounds.size.x]
			)
		)
	_cleanup(root)
