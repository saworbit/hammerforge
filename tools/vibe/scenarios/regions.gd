@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Terrain region streaming: the eviction loop and the bookkeeping under it.
##
## Streaming exists so a level bigger than memory can be edited, which makes the
## eviction loop the one place where paint is deliberately thrown out of memory.
## What it believes it freed, and what it actually freed, had better agree.


func id() -> String:
	return "regions"


func summary() -> String:
	return "what the region eviction loop frees against what it thinks it freed"


func run() -> void:
	await _eviction_when_the_write_fails()
	await _what_mark_unloaded_forgets()


## Spread one painted cell across `chunks` chunks so each region has real data.
func _spread_paint(layer, chunks_per_side: int, chunk_size: int) -> int:
	var made := 0
	var half := chunks_per_side / 2
	for cy in range(-half, half):
		for cx in range(-half, half):
			layer.set_cell(Vector2i(cx * chunk_size, cy * chunk_size), true)
			made += 1
	return made


## A level that has never been saved has no region directory, so every region
## write fails. What does the eviction loop do with that?
func _eviction_when_the_write_fails() -> void:
	var root: Node3D = await fresh_root()
	var paint = root.paint_system
	var layer = root.paint_layers.get_active_layer()
	var chunk_size: int = root.paint_layers.chunk_size

	paint.set_region_size_cells(256)
	paint.set_region_streaming_radius(2)
	note("region base path", "'%s'" % paint.region_manager.region_base_path)

	var chunks := _spread_paint(layer, 40, chunk_size)
	note("chunks painted", chunks)
	await frame()

	paint.set_region_streaming_enabled(true)
	paint._ensure_regions_for_cell(Vector2i.ZERO)
	await frame()
	var loaded_before: int = paint.region_manager.loaded_regions.size()
	var bytes_before: int = paint._total_loaded_bytes()
	note("regions loaded", loaded_before)
	note("bytes the paint system counts as loaded", bytes_before)

	# A budget the level is well over, so the loop has work to do.
	paint.region_memory_budget_mb = 1
	note("budget bytes", 1024 * 1024)
	var heard: Array = []
	var sink := func(text: String, _level: int): heard.append(text)
	root.user_message.connect(sink)
	paint._evict_for_budget(Vector2i.ZERO)
	await frame()
	root.user_message.disconnect(sink)
	note(
		"what the eviction pass said",
		heard[heard.size() - 1] if not heard.is_empty() else "<nothing>"
	)

	var loaded_after: int = paint.region_manager.loaded_regions.size()
	var bytes_after: int = paint._total_loaded_bytes()
	note("regions loaded after the eviction pass", loaded_after)
	note("bytes still loaded", bytes_after)

	var said_over_budget := false
	for text in heard:
		if str(text).contains("budget"):
			said_over_budget = true
	if bytes_after > 1024 * 1024 and loaded_after == loaded_before and not said_over_budget:
		known(
			446,
			"the eviction loop counts memory it did not free and stops with the budget still blown",
			(
				"_unload_region() returns false when the region's paint could not be written "
				+ "-- which is every region while the level has no save path -- and keeps the "
				+ "region loaded, correctly. _evict_for_budget() ignores that return and "
				+ "subtracts _estimate_region_bytes(rid) from its running total anyway, so it "
				+ (
					"decides the budget is met and breaks. %d regions and %d bytes went in, %d "
					% [loaded_before, bytes_before, loaded_after]
				)
				+ (
					"regions and %d bytes came out, against a budget of %d. The loop reports "
					% [bytes_after, 1024 * 1024]
				)
				+ "nothing, and the budget control in the dock quietly does nothing on any "
				+ "level that has not been saved yet"
			)
		)
	root.queue_free()


## What the region manager keeps after a region is marked unloaded.
func _what_mark_unloaded_forgets() -> void:
	var root: Node3D = await fresh_root()
	var mgr = root.paint_system.region_manager
	var rid := Vector2i(3, 4)
	mgr.mark_loaded(rid)
	mgr.mark_dirty(rid)
	note(
		"loaded / dirty / indexed",
		[mgr.is_loaded(rid), mgr.dirty_regions.has(rid), mgr.region_index.has(rid)]
	)
	mgr.mark_unloaded(rid)
	note(
		"after mark_unloaded",
		[mgr.is_loaded(rid), mgr.dirty_regions.has(rid), mgr.region_index.has(rid)]
	)
	if mgr.dirty_regions.has(rid):
		note(
			"a region stays in dirty_regions after it is unloaded",
			(
				"mark_unloaded() erases loaded_regions and last_access and leaves "
				+ "dirty_regions alone. Not a defect on its own -- the unload path saves "
				+ "first -- but it means dirty_regions grows without bound over a session "
				+ "and can never be trusted as 'these regions are loaded and unsaved'"
			)
		)

	# The radius control against what it loads.
	for radius in [0, 2, 8]:
		root.paint_system.set_region_streaming_radius(int(radius))
		note(
			"streaming radius %s" % radius,
			"%d regions in the neighbourhood" % mgr.region_ids_in_radius(Vector2i.ZERO).size()
		)
	root.queue_free()
