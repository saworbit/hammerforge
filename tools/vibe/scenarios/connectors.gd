@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Auto-connectors and the paint grid they are laid out on.
##
## The connector generator runs twice per stroke in the editor -- once for the
## live ghost and once at bake -- so what it costs per stroke matters as much as
## what it produces. And everything it produces is addressed in grid cells, so
## the grid's own agreement with the level it belongs to is the thing underneath
## all of it.

const AutoConnector = preload("res://addons/hammerforge/paint/hf_auto_connector.gd")


func id() -> String:
	return "connectors"


func summary() -> String:
	return "what the live connector path costs per stroke, and whether the paint grid follows the level"


func run() -> void:
	await _what_the_live_path_scans()
	await _does_the_grid_follow_the_level()


func _two_levels(root: Node3D, half: int) -> void:
	var mgr = root.paint_layers
	var lower = mgr.get_active_layer()
	var upper = mgr.create_layer(&"upper", 32.0)
	for y in range(-half, half):
		for x in range(-half, 0):
			lower.set_cell(Vector2i(x, y), true)
		for x in range(0, half):
			upper.set_cell(Vector2i(x, y), true)


## The comment on defs_for_touched_cells says it does not scan. Time it.
func _what_the_live_path_scans() -> void:
	var root: Node3D = await fresh_root()
	var gen = AutoConnector.new()

	for half in [8, 32, 64]:
		var probe_root: Node3D = await fresh_root("Level_%d" % int(half))
		_two_levels(probe_root, int(half))
		var painted: int = int(half) * int(half) * 2

		var started := Time.get_ticks_usec()
		var segments = gen.detect_boundaries(probe_root.paint_layers)
		var scan_us := Time.get_ticks_usec() - started

		# One cell touched, the way a single click reaches the live ghost path.
		var touched := {Vector2i(-1, 0): true}
		started = Time.get_ticks_usec()
		var defs = gen.defs_for_touched_cells(probe_root.paint_layers, 0, touched)
		var live_us := Time.get_ticks_usec() - started

		note(
			"%d painted cells" % painted,
			(
				"detect_boundaries %d segments in %d ms; defs_for_touched_cells for ONE cell %d ms, %d def(s)"
				% [segments.size(), scan_us / 1000, live_us / 1000, defs.size()]
			)
		)
		if live_us > scan_us * 0.5 and int(half) >= 64:
			known(
				441,
				"the live connector path costs a full-level scan for every stroke",
				(
					"defs_for_touched_cells() is documented as 'the live-ghost path; it does "
					+ "not scan or rebuild geometry', and its first statement is "
					+ "detect_boundaries(layers), which walks every chunk of every layer. "
					+ (
						"With %d painted cells one touched cell took %d ms against %d ms for "
						% [painted, live_us / 1000, scan_us / 1000]
					)
					+ "the full scan it claims to avoid -- the same work, then a filter. "
					+ "HFPaintTool calls it on every committed stroke"
				)
			)
	root.queue_free()


## The grid each layer carries against the level root it belongs to.
func _does_the_grid_follow_the_level() -> void:
	var root: Node3D = await fresh_root()
	var mgr = root.paint_layers
	var layer = mgr.get_active_layer()
	note("root position", root.global_position)
	note("base grid origin", mgr.base_grid.origin)
	note("layer grid origin", layer.grid.origin)

	var cell := Vector2i(4, 4)
	var before: Vector3 = layer.grid.uv_to_world(layer.grid.cell_center_uv(cell))
	note("world position of cell (4,4)", before)

	root.global_position = Vector3(1024, 0, 1024)
	root._sync_paint_grid_from_root()
	await frame()
	note("after moving the root to (1024, 0, 1024)")
	note("  base grid origin", mgr.base_grid.origin)
	note("  layer grid origin", layer.grid.origin)
	var after: Vector3 = layer.grid.uv_to_world(layer.grid.cell_center_uv(cell))
	note("  world position of cell (4,4)", after)

	if mgr.base_grid.origin != layer.grid.origin:
		known(
			442,
			"moving the level root moves the paint grid but not the grid any layer is using",
			(
				"_sync_paint_grid_from_root() writes global_position into "
				+ "paint_layers.base_grid, and create_layer() gave every layer its own "
				+ (
					"base_grid.duplicate(). So base_grid.origin is now %s while the live "
					% str(mgr.base_grid.origin)
				)
				+ (
					"layer's grid is still %s, and cell (4,4) still resolves to %s. "
					% [str(layer.grid.origin), str(after)]
				)
				+ "_set_grid_snap() has the same shape and does remember to push cell_size "
				+ "into every layer grid; origin and layer_y are not pushed anywhere. "
				+ "Painted floors, heightmap sampling and the auto-connectors all read the "
				+ "layer grid, so the whole floor-paint layer stays behind at the level's "
				+ "old position"
			)
		)

	# A new layer made after the move does pick the move up, so two layers in one
	# level end up on two different grids.
	var fresh = mgr.create_layer(&"after_move", 0.0)
	note("layer created after the move: grid origin", fresh.grid.origin)
	if fresh.grid.origin != layer.grid.origin:
		known(
			442,
			"two paint layers in one level sit on two different grid origins",
			(
				(
					"the layer made before the move has origin %s and the one made after has %s. "
					% [str(layer.grid.origin), str(fresh.grid.origin)]
				)
				+ "HFAutoConnector.detect_boundaries() compares cells between layers by cell "
				+ "coordinate and reads each layer's own grid for the height, so a boundary "
				+ "between these two is computed from coordinates that do not mean the same "
				+ "thing"
			)
		)
