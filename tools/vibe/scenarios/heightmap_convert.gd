@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Convert to Heightmap: `HFBrushToHeightmap`, and the dock button that drives it.
##
## The converter rasterises the top of every additive brush onto a grid and
## writes the result into a paint layer. Two numbers decide how big that grid is
## -- the world extent of the selection and the cell size -- and the dock takes
## the cell size from the level's grid snap, widened until the grid fits the cap
## (#512). What the grid costs, what comes back out of it, and which of the
## converter's own settings the caller can reach are what this measures.

const BrushToHeightmap = preload("res://addons/hammerforge/paint/hf_brush_to_heightmap.gd")


func id() -> String:
	return "heightmap-convert"


func summary() -> String:
	return "what Convert to Heightmap produces, what it costs, and which settings it honours"


func run() -> void:
	await _round_trip_a_known_height()
	await _remove_sources()
	await _what_the_grid_snap_costs()


func _convert(brushes: Array, settings) -> Variant:
	var converter = BrushToHeightmap.new()
	return converter.convert(brushes, settings)


## A brush of known height in, the same height back out of the layer.
func _round_trip_a_known_height() -> void:
	var root: Node3D = await fresh_root("HeightmapConvert")
	var b = box(root, Vector3(64, 40, 64), Vector3(0, 20, 0))
	await frame()
	var settings = BrushToHeightmap.ConvertSettings.new()
	settings.cell_size = 4.0
	settings.height_scale = 10.0
	var result = _convert([b], settings)
	note("convert error", result.error if result.error != "" else "none")
	if result.error != "":
		return
	note("brushes used", result.brush_count)
	note("heightmap size", result.heightmap.get_size())
	note("cell range", "%s .. %s" % [result.cell_min, result.cell_max])
	var layer = result.layer
	note("layer grid layer_y", layer.grid.layer_y if layer.grid else "no grid")

	# The centre of the brush, in cells.
	var centre_cell := Vector2i(0, 0)
	var read_back: float = layer.get_height_at(centre_cell)
	var expected: float = (
		b.global_position.y + b.size.y * 0.5 - (layer.grid.layer_y if layer.grid else 0.0)
	)
	note("height read back at the centre cell", "%.3f" % read_back)
	note("the brush's top above the layer's floor", "%.3f" % expected)
	if absf(read_back - expected) > maxf(1.0, expected * 0.05):
		flag(
			"a brush converted to a heightmap does not read back at its own height",
			(
				"the layer says %.2f where the brush's top is %.2f above the layer floor"
				% [read_back, expected]
			)
		)


## `ConvertSettings.remove_sources` takes the brushes out through the level the
## caller names in `source_root` (#511), so their references go with them.
func _remove_sources() -> void:
	var root: Node3D = await fresh_root("HeightmapRemoveSources")
	var b = box(root, Vector3(64, 40, 64), Vector3(0, 20, 0))
	await frame()
	var before: int = root.brush_system.get_live_brush_count()
	var settings = BrushToHeightmap.ConvertSettings.new()
	settings.cell_size = 8.0
	settings.remove_sources = true
	settings.source_root = root
	var result = _convert([b], settings)
	await frame()
	var after: int = root.brush_system.get_live_brush_count()
	note("remove_sources with source_root", true)
	note("live brushes", "%d -> %d" % [before, after])
	note("removed_sources reported", result.removed_sources)
	if result.error == "" and (after != before - 1 or result.removed_sources != 1):
		flag(
			"remove_sources with a source_root left the source brush in the level",
			(
				"%d live brushes before and %d after, %d reported removed"
				% [before, after, result.removed_sources]
			)
		)


## What a 512 unit selection costs at three cell sizes.
func _what_the_grid_snap_costs() -> void:
	var root: Node3D = await fresh_root("HeightmapCost")
	var b = box(root, Vector3(512, 64, 512), Vector3(0, 32, 0))
	await frame()
	note("brush footprint", "512 x 512 units")

	var measured: Array = []
	for cell_size in [16.0, 8.0, 4.0]:
		var settings = BrushToHeightmap.ConvertSettings.new()
		settings.cell_size = cell_size
		var start := Time.get_ticks_msec()
		var result = _convert([b], settings)
		var took := Time.get_ticks_msec() - start
		if result.error != "":
			note("cell size %.2f" % cell_size, "error: %s" % result.error)
			continue
		var size: Vector2i = result.heightmap.get_size()
		measured.append([cell_size, size, took])
		note("cell size %.1f" % cell_size, "%dx%d heightmap, %d ms" % [size.x, size.y, took])

	# A finer grid snap widens the cell until the grid fits MAX_GRID_DIMENSION a
	# side, and the dock says the cell size it used (#512). Building a capped grid
	# takes long enough that the cap itself is checked in
	# tests/test_brush_to_heightmap.gd rather than here.
	note("the widest grid a conversion builds, a side", BrushToHeightmap.MAX_GRID_DIMENSION)
	note("the level's own grid_snap", root.get("grid_snap"))
	note("measured", measured)
