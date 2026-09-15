@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Convert to Heightmap: `HFBrushToHeightmap`, and the dock button that drives it.
##
## The converter rasterises the top of every additive brush onto a grid and
## writes the result into a paint layer. Two numbers decide how big that grid is
## -- the world extent of the selection and the cell size -- and the dock takes
## the cell size straight from the level's grid snap without looking at the
## first number. What the grid costs, what comes back out of it, and which of
## the converter's own settings the caller can reach are what this measures.

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


## `ConvertSettings.remove_sources` is documented on the class -- "The original
## brushes can optionally be removed after conversion".
func _remove_sources() -> void:
	var root: Node3D = await fresh_root("HeightmapRemoveSources")
	var b = box(root, Vector3(64, 40, 64), Vector3(0, 20, 0))
	await frame()
	var before: int = root.brush_system.get_live_brush_count()
	var settings = BrushToHeightmap.ConvertSettings.new()
	settings.cell_size = 8.0
	settings.remove_sources = true
	var result = _convert([b], settings)
	await frame()
	var after: int = root.brush_system.get_live_brush_count()
	note("remove_sources", true)
	note("live brushes", "%d -> %d" % [before, after])
	note("the brush node is still valid", is_instance_valid(b))
	if after == before and result.error == "":
		var source := FileAccess.get_file_as_string(
			"res://addons/hammerforge/paint/hf_brush_to_heightmap.gd"
		)
		var reads := source.count("settings.remove_sources") + source.count("remove_sources:")
		note("mentions of remove_sources in the converter", reads)
		known(
			511,
			"ConvertSettings.remove_sources does nothing",
			(
				"the class comment says 'The original brushes can optionally be removed after"
				+ " conversion' and convert() never reads the field -- it is declared, defaulted,"
				+ " covered by tests/test_brush_to_heightmap.gd for its default value, and"
				+ " setting it true leaves every source brush in the level"
			)
		)


## The dock sets the cell size from the level's grid snap and nothing looks at
## how large the selection is. What the two together ask for.
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

	# What the same selection would ask for at the smaller grid snaps the level
	# will hand over. Projected rather than built, because building it is the
	# problem being reported.
	note("grid_snap is what the dock passes as cell_size", "dock_paint_handler.gd")
	for snap in [1.0, 0.5, 0.25, 0.1]:
		var side := int(ceil(512.0 / snap)) + 4
		var pixels := side * side
		# FORMAT_RF is 4 bytes, and the PackedFloat32Array beside it is another 4.
		var bytes := pixels * 8
		note(
			"grid snap %.2f on this brush" % snap,
			(
				"%dx%d = %d cells, about %.1f MB before the per-cell set_cell() loop"
				% [side, side, pixels, bytes / 1048576.0]
			)
		)
	var snap_floor: Variant = root.get("grid_snap")
	note("the level's own grid_snap", snap_floor)
	known(
		512,
		"Convert to Heightmap sizes its grid from the grid snap with no cap on the result",
		(
			"dock_paint_handler.gd passes level_root.grid_snap straight in as cell_size and"
			+ " nothing looks at how large the selection is. A 512-unit selection at a grid"
			+ " snap of 0.25 asks for a 2052x2052 heightmap -- 4.2M cells, ~34 MB of pixels"
			+ " plus a PackedFloat32Array the same size, then a set_cell() call per filled"
			+ " cell. There is no upper bound, no progress and no refusal; the measured cost"
			+ " is %s" % str(measured)
		)
	)
