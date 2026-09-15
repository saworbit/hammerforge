@tool
class_name HFBrushToHeightmap
extends RefCounted

## Converts selected brushes into a heightmap paint layer.
##
## Rasterizes each brush's top face onto a grid, writing height values
## into a new (or existing) paint layer. The original brushes can optionally
## be removed after conversion.

const DraftBrush = preload("../brush_instance.gd")

## The widest grid a conversion will build, a side. 2048 square is 4M cells and
## matches the region size ceiling the Paint tab already uses.
const MAX_GRID_DIMENSION := 2048


class ConvertSettings:
	## Target resolution: world units per heightmap cell.
	var cell_size: float = 1.0
	## Extra margin (in cells) around the brush bounding box.
	var margin_cells: int = 2
	## If true, remove the source brushes after conversion. Needs `source_root`,
	## because a brush has to go out through the brush system for its cross
	## references, its visgroup membership and the face selection to go with it.
	var remove_sources: bool = false
	## The level the brushes belong to. Only read when `remove_sources` is set.
	var source_root: Node = null
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
	## The cell size the grid was actually built at, which is the requested one
	## unless the selection was too large to rasterise at it.
	var cell_size_used: float = 0.0
	## Empty unless something about the conversion is worth telling the mapper.
	var notice: String = ""
	## How many source brushes were removed, which is zero unless asked for.
	var removed_sources: int = 0


## Convert an array of DraftBrush nodes into a heightmap layer.
func convert(brushes: Array, settings: ConvertSettings) -> ConvertResult:
	var result := ConvertResult.new()
	if brushes.is_empty():
		result.error = "No brushes provided"
		return result

	# --- 1. Compute world-space AABB of additive brushes (mesh bounds, including displacements) ---
	var aabb := AABB()
	var first := true
	var used := 0
	for brush in brushes:
		if not is_instance_valid(brush):
			continue
		if not _is_additive_brush(brush):
			continue
		used += 1
		var b_aabb := _get_brush_aabb(brush)
		if first:
			aabb = b_aabb
			first = false
		else:
			aabb = aabb.merge(b_aabb)

	if first:
		result.error = "No additive brushes to convert"
		return result

	# --- 2. Determine grid extents ---
	var margin := settings.margin_cells
	var requested_cs: float = maxf(settings.cell_size, 0.01)
	var cs := _cell_size_within_cap(aabb, requested_cs, margin)
	if cs > requested_cs:
		result.notice = (
			"Selection is %d units across; converting at cell size %s rather than %s to stay within %dx%d."
			% [
				int(roundf(maxf(aabb.size.x, aabb.size.z))),
				String.num(cs, 3),
				String.num(requested_cs, 3),
				MAX_GRID_DIMENSION,
				MAX_GRID_DIMENSION,
			]
		)
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
		if not _is_additive_brush(brush):
			continue
		_rasterize_brush(brush, raw_heights, width, height, cell_min, cs, y_min)

	# --- 5. Build the heightmap Image ---
	# HFPaintLayer.get_height_at(cell) reads pixel at posmod(cell.x, img_w),
	# posmod(cell.y, img_h). We must write each cell's height to the pixel
	# index that get_height_at will read it from — i.e. the posmod position.
	var hs: float = maxf(settings.height_scale, 0.01)
	var img := Image.create(width, height, false, Image.FORMAT_RF)
	if img == null:
		result.error = "Could not allocate a %dx%d heightmap" % [width, height]
		return result
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
	result.brush_count = used
	result.cell_size_used = cs
	if settings.remove_sources:
		result.removed_sources = _remove_sources(brushes, settings.source_root)
	return result


## The cell size this selection can be rasterised at.
##
## The grid is the selection's extent divided by the cell size, and the cell size
## comes from the level's grid snap - a number set for an unrelated reason, how
## far a brush moves when it is dragged. Nothing in the Convert to Heightmap
## button says it is also the resolution knob, and the cost is quadratic: a
## 512 unit brush at a snap of 0.1 is a 5124 x 5124 grid, about 210 MB across the
## float array and the image, rasterised twice on the main thread with no
## progress and no way to stop. The cell size widens to fit rather than the
## operation being refused, and the caller says which one it used.
static func _cell_size_within_cap(bounds: AABB, cell_size: float, margin: int) -> float:
	var cs := cell_size
	var span := maxf(bounds.size.x, bounds.size.z)
	if span <= 0.0:
		return cs
	for _attempt in range(8):
		var cells := ceili(span / cs) + 2 * margin + 1
		if cells <= MAX_GRID_DIMENSION:
			return cs
		cs *= float(cells) / float(MAX_GRID_DIMENSION)
	return cs


## Take the rasterised brushes out of the level.
##
## Through the brush system rather than `queue_free()`, so the brush cache, the
## face selection and the cross references go with them. The non-additive brushes
## were never read, so they stay.
static func _remove_sources(brushes: Array, source_root: Node) -> int:
	if source_root == null or not source_root.has_method("delete_brush"):
		HFLog.warn(
			"HFBrushToHeightmap: remove_sources needs a source_root, keeping the source brushes"
		)
		return 0
	var removed := 0
	for brush in brushes:
		if not is_instance_valid(brush):
			continue
		if not _is_additive_brush(brush):
			continue
		source_root.call("delete_brush", brush)
		removed += 1
	return removed


static func _is_additive_brush(brush: Node3D) -> bool:
	var op: Variant = brush.get("operation")
	if op == null:
		return true
	return int(op) != CSGShape3D.OPERATION_SUBTRACTION


## World AABB from the authored mesh (displacements included) when present.
func _get_brush_aabb(brush: Node3D) -> AABB:
	if brush is DraftBrush:
		var draft := brush as DraftBrush
		if (
			draft.mesh_instance
			and is_instance_valid(draft.mesh_instance)
			and draft.mesh_instance.mesh
		):
			return draft.mesh_instance.global_transform * draft.mesh_instance.mesh.get_aabb()
		var half_size := draft.size * 0.5
		return AABB(draft.global_position - half_size, draft.size)
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
