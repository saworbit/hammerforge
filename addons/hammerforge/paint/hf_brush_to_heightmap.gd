@tool
class_name HFBrushToHeightmap
extends RefCounted

## Converts selected brushes into a heightmap paint layer.
##
## Rasterizes each brush's top face onto a grid, writing height values
## into a new (or existing) paint layer. The original brushes can optionally
## be removed after conversion.

const DraftBrush = preload("../brush_instance.gd")


class ConvertSettings:
	## Target resolution: world units per heightmap cell.
	var cell_size: float = 1.0
	## Extra margin (in cells) around the brush bounding box.
	var margin_cells: int = 2
	## If true, remove the source brushes after conversion.
	var remove_sources: bool = false
	## Height scale divisor — heightmap stores normalised values; this
	## converts world-space Y back to 0-1 for the Image.
	var height_scale: float = 10.0
	## Optional existing layer to merge into (null = create new).
	var target_layer: HFPaintLayer = null


class ConvertResult:
	var layer: HFPaintLayer = null
	var heightmap: Image = null
	var cell_min: Vector2i = Vector2i.ZERO
	var cell_max: Vector2i = Vector2i.ZERO
	var brush_count: int = 0
	var error: String = ""


## Convert an array of DraftBrush nodes into a heightmap layer.
func convert(brushes: Array, settings: ConvertSettings) -> ConvertResult:
	var result := ConvertResult.new()
	if brushes.is_empty():
		result.error = "No brushes provided"
		return result

	# --- 1. Compute world-space AABB of all brushes ---
	var aabb := AABB()
	var first := true
	for brush in brushes:
		if not is_instance_valid(brush):
			continue
		var b_aabb := _get_brush_aabb(brush)
		if first:
			aabb = b_aabb
			first = false
		else:
			aabb = aabb.merge(b_aabb)

	if first:
		result.error = "No valid brushes"
		return result

	# --- 2. Determine grid extents ---
	var cs: float = maxf(settings.cell_size, 0.01)
	var margin := settings.margin_cells
	var cell_min := Vector2i(
		floori(aabb.position.x / cs) - margin, floori(aabb.position.z / cs) - margin
	)
	var cell_max := Vector2i(ceili(aabb.end.x / cs) + margin, ceili(aabb.end.z / cs) + margin)
	var width := cell_max.x - cell_min.x
	var height := cell_max.y - cell_min.y
	if width <= 0 or height <= 0:
		result.error = "Degenerate brush bounds"
		return result

	# --- 3. Create raw heightmap (world-space heights, local coords) ---
	# raw_heights stores world-relative height at local image offset (x, y)
	# where local (x, y) maps to absolute cell (cell_min.x + x, cell_min.y + y).
	var raw_heights: PackedFloat32Array = PackedFloat32Array()
	raw_heights.resize(width * height)
	for i in range(raw_heights.size()):
		raw_heights[i] = 0.0

	# --- 4. Rasterize brush top faces ---
	var y_min := aabb.position.y

	for brush in brushes:
		if not is_instance_valid(brush):
			continue
		_rasterize_brush(brush, raw_heights, width, height, cell_min, cs, y_min)

	# --- 5. Build the heightmap Image ---
	# HFPaintLayer.get_height_at(cell) reads pixel at posmod(cell.x, img_w),
	# posmod(cell.y, img_h). We must write each cell's height to the pixel
	# index that get_height_at will read it from — i.e. the posmod position.
	var hs: float = maxf(settings.height_scale, 0.01)
	var img := Image.create(width, height, false, Image.FORMAT_RF)
	for ly in range(height):
		for lx in range(width):
			var abs_x := cell_min.x + lx
			var abs_y := cell_min.y + ly
			var px := posmod(abs_x, width)
			var py := posmod(abs_y, height)
			var raw_h: float = raw_heights[ly * width + lx]
			img.set_pixel(px, py, Color(raw_h / hs, 0, 0, 1))

	# --- 6. Build / update paint layer ---
	var layer: HFPaintLayer = settings.target_layer
	if layer == null:
		layer = HFPaintLayer.new()
		layer.layer_id = &"converted_%d" % Time.get_ticks_usec()
		layer.display_name = "Converted Terrain"
		layer.grid = HFPaintGrid.new()
		layer.grid.cell_size = cs
		layer.grid.layer_y = y_min

	layer.heightmap = img
	layer.height_scale = hs

	# Fill cells so the layer renders
	for ly in range(height):
		for lx in range(width):
			var raw_h: float = raw_heights[ly * width + lx]
			if raw_h > 0.001:
				var cell := cell_min + Vector2i(lx, ly)
				layer.set_cell(cell, true)

	result.layer = layer
	result.heightmap = img
	result.cell_min = cell_min
	result.cell_max = cell_max
	result.brush_count = brushes.size()
	return result


## Get the world-space AABB for a brush node.
func _get_brush_aabb(brush: Node3D) -> AABB:
	var size: Vector3 = brush.get("size") if brush.get("size") else Vector3.ONE
	var half := size * 0.5
	var pos := brush.global_position
	return AABB(pos - half, size)


## Rasterize a single brush's height contribution into raw_heights array.
func _rasterize_brush(
	brush: Node3D,
	raw_heights: PackedFloat32Array,
	img_w: int,
	img_h: int,
	cell_min: Vector2i,
	cs: float,
	y_min: float
) -> void:
	var b_aabb := _get_brush_aabb(brush)

	# Determine which local offsets this brush covers
	var bx_min := floori(b_aabb.position.x / cs) - cell_min.x
	var bz_min := floori(b_aabb.position.z / cs) - cell_min.y
	var bx_max := ceili(b_aabb.end.x / cs) - cell_min.x
	var bz_max := ceili(b_aabb.end.z / cs) - cell_min.y

	bx_min = clampi(bx_min, 0, img_w - 1)
	bz_min = clampi(bz_min, 0, img_h - 1)
	bx_max = clampi(bx_max, 0, img_w - 1)
	bz_max = clampi(bz_max, 0, img_h - 1)

	var top_y := b_aabb.end.y

	for ly in range(bz_min, bz_max + 1):
		for lx in range(bx_min, bx_max + 1):
			# World position of cell center
			var world_x := (cell_min.x + lx + 0.5) * cs
			var world_z := (cell_min.y + ly + 0.5) * cs
			# Check if this XZ point is inside the brush footprint
			if (
				world_x >= b_aabb.position.x
				and world_x <= b_aabb.end.x
				and world_z >= b_aabb.position.z
				and world_z <= b_aabb.end.z
			):
				var idx := ly * img_w + lx
				var h := top_y - y_min
				# Take the maximum height (union of brush tops)
				if h > raw_heights[idx]:
					raw_heights[idx] = h
