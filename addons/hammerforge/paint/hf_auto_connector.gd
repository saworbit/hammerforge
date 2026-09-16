@tool
class_name HFAutoConnector
extends RefCounted

## Auto-detects height-level boundaries between paint layers and generates
## connector geometry (ramps or stairs) to bridge them during bake.

const HFConnectorTool = preload("hf_connector_tool.gd")

enum ConnectorMode { RAMP, STAIRS, AUTO }

## Minimum height difference (world units) to consider two adjacent cells as
## needing a connector.  Anything below this is treated as co-planar.
const MIN_HEIGHT_DIFF := 0.1


## Result returned for each detected connector segment.
class ConnectorSegment:
	var from_layer_index: int
	var to_layer_index: int
	var from_cell: Vector2i
	var to_cell: Vector2i
	var height_diff: float  # absolute
	var direction: Vector2i  # unit step (1,0), (-1,0), (0,1), (0,-1)


## Settings controlling auto-connector behaviour.
class Settings:
	var mode: int = ConnectorMode.RAMP
	var stair_step_height: float = 0.25
	var width_cells: int = 2
	## Height threshold above which AUTO mode picks stairs over ramp.
	var stair_threshold: float = 2.0


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


## Scan all layer pairs and return connector segments where a filled cell in
## one layer neighbours an unfilled cell that is filled in another layer at a
## different height.
func detect_boundaries(layers: HFPaintLayerManager) -> Array[ConnectorSegment]:
	var segments: Array[ConnectorSegment] = []
	if layers.layers.size() < 2:
		return segments

	# Collect all filled cells per layer with their world-Y height.
	var layer_cells: Array = []  # Array[Dictionary{Vector2i -> float}]
	for layer in layers.layers:
		var cells: Dictionary = {}
		for cid in layer.get_chunk_ids():
			var size: int = layer.chunk_size
			var origin := Vector2i(cid.x * size, cid.y * size)
			for ly in range(size):
				for lx in range(size):
					var cell := origin + Vector2i(lx, ly)
					if layer.get_cell(cell):
						cells[cell] = layer.grid.layer_y + layer.get_height_at(cell)
		layer_cells.append(cells)

	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	# Track already-paired cell edges to avoid duplicate connectors.
	var paired: Dictionary = {}  # "fromIdx_toIdx_cell" -> true

	for i in range(layers.layers.size()):
		var cells_i: Dictionary = layer_cells[i]
		for cell: Vector2i in cells_i:
			for dir in directions:
				var neighbour := cell + dir
				# Only interested if the neighbour is NOT filled in this layer.
				if cells_i.has(neighbour):
					continue
				# Check if neighbour is filled in any other layer.
				for j in range(layers.layers.size()):
					if j == i:
						continue
					var cells_j: Dictionary = layer_cells[j]
					if not cells_j.has(neighbour):
						continue
					var h_i: float = cells_i[cell]
					var h_j: float = cells_j[neighbour]
					var diff := absf(h_j - h_i)
					if diff < MIN_HEIGHT_DIFF:
						continue
					# Canonical key prevents A→B and B→A duplicates.
					# Include both cell coords so corner/T-junction edges
					# sharing the same source cell aren't collapsed.
					var lo: int = mini(i, j)
					var hi: int = maxi(i, j)
					var c_lo: Vector2i = cell if i < j else neighbour
					var c_hi: Vector2i = neighbour if i < j else cell
					var key := "%d_%d_%d_%d_%d_%d" % [lo, hi, c_lo.x, c_lo.y, c_hi.x, c_hi.y]
					if paired.has(key):
						continue
					paired[key] = true
					var seg := ConnectorSegment.new()
					seg.from_layer_index = i
					seg.to_layer_index = j
					seg.from_cell = cell
					seg.to_cell = neighbour
					seg.height_diff = diff
					seg.direction = dir
					segments.append(seg)
	return segments


## Group adjacent segments that share the same layer pair and perpendicular
## direction into contiguous runs.  Returns arrays of ConnectorSegment.
func group_segments(segments: Array[ConnectorSegment]) -> Array:
	if segments.is_empty():
		return []

	# Key: "fromLayer_toLayer_dirX_dirY" → Array[ConnectorSegment]
	var buckets: Dictionary = {}
	for seg in segments:
		var k := (
			"%d_%d_%d_%d"
			% [seg.from_layer_index, seg.to_layer_index, seg.direction.x, seg.direction.y]
		)
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(seg)

	var groups: Array = []
	for k: String in buckets:
		var bucket: Array = buckets[k]
		# Sort by perpendicular axis for flood-grouping.
		var dir_segs: Array = bucket
		if dir_segs.is_empty():
			continue
		var first_dir: Vector2i = dir_segs[0].direction
		# Perpendicular axis: if direction is (1,0) or (-1,0), group by y; else by x.
		var by_perp: bool = first_dir.x != 0  # true → sort/group by y
		# Build a set for flood fill.
		var cell_set: Dictionary = {}
		for seg in dir_segs:
			cell_set[seg.from_cell] = seg
		var visited: Dictionary = {}
		for seg in dir_segs:
			if visited.has(seg.from_cell):
				continue
			# Flood fill along perpendicular axis.
			var group: Array = []
			var queue: Array[Vector2i] = [seg.from_cell]
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				if visited.has(c):
					continue
				if not cell_set.has(c):
					continue
				visited[c] = true
				group.append(cell_set[c])
				var step := Vector2i(0, 1) if by_perp else Vector2i(1, 0)
				queue.append(c + step)
				queue.append(c - step)
			if not group.is_empty():
				groups.append(group)
	return groups


## Generate connector meshes for all detected boundaries.
## Returns an array of dictionaries: {"mesh": ArrayMesh, "transform": Transform3D}.
func generate_connectors(layers: HFPaintLayerManager, settings: Settings = null) -> Array:
	if not settings:
		settings = Settings.new()
	var segments := detect_boundaries(layers)
	var groups := group_segments(segments)
	return generate_definitions(defs_from_groups(groups, settings), layers)


## Boundary segments that touch one of `cells` in layer `layer_index`.
##
## The same answer `detect_boundaries()` gives filtered down to these cells, at
## the cost of the cells rather than the cost of the level. The full scan walks
## every cell of every chunk of every layer to build a dictionary from scratch,
## then compares each filled cell against every other layer; this walks the
## handful of cells a stroke touched and their four neighbours.
##
## `test_auto_connector.gd` asserts the two agree, which is what keeps this from
## drifting away from the scan it stands in for.
func boundaries_for_cells(
	layers: HFPaintLayerManager, layer_index: int, cells: Dictionary
) -> Array[ConnectorSegment]:
	var segments: Array[ConnectorSegment] = []
	if layers == null or layers.layers.size() < 2:
		return segments
	if layer_index < 0 or layer_index >= layers.layers.size():
		return segments
	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	var paired: Dictionary = {}
	for cell: Vector2i in cells:
		for dir in directions:
			var neighbour: Vector2i = cell + dir
			# The touched cell as the source of a boundary.
			_collect_segments_at(layers, layer_index, cell, neighbour, dir, paired, segments)
			# And as the destination: a cell next door in another layer whose own
			# unfilled neighbour is this one.
			for j in range(layers.layers.size()):
				if j == layer_index:
					continue
				_collect_segments_at(layers, j, neighbour, cell, -dir, paired, segments)
	return segments


## One cell, one direction: the boundary test `detect_boundaries()` runs in its
## innermost loop, against the layers directly rather than a prebuilt map.
func _collect_segments_at(
	layers: HFPaintLayerManager,
	i: int,
	cell: Vector2i,
	neighbour: Vector2i,
	dir: Vector2i,
	paired: Dictionary,
	out: Array[ConnectorSegment]
) -> void:
	var layer_i: HFPaintLayer = layers.layers[i]
	if layer_i == null or not layer_i.get_cell(cell):
		return
	# Only interested if the neighbour is NOT filled in this layer.
	if layer_i.get_cell(neighbour):
		return
	var h_i: float = layer_i.grid.layer_y + layer_i.get_height_at(cell)
	for j in range(layers.layers.size()):
		if j == i:
			continue
		var layer_j: HFPaintLayer = layers.layers[j]
		if layer_j == null or not layer_j.get_cell(neighbour):
			continue
		var h_j: float = layer_j.grid.layer_y + layer_j.get_height_at(neighbour)
		var diff := absf(h_j - h_i)
		if diff < MIN_HEIGHT_DIFF:
			continue
		var lo: int = mini(i, j)
		var hi: int = maxi(i, j)
		var c_lo: Vector2i = cell if i < j else neighbour
		var c_hi: Vector2i = neighbour if i < j else cell
		var key := "%d_%d_%d_%d_%d_%d" % [lo, hi, c_lo.x, c_lo.y, c_hi.x, c_hi.y]
		if paired.has(key):
			continue
		paired[key] = true
		var seg := ConnectorSegment.new()
		seg.from_layer_index = i
		seg.to_layer_index = j
		seg.from_cell = cell
		seg.to_cell = neighbour
		seg.height_diff = diff
		seg.direction = dir
		out.append(seg)


## Return connector definitions only for boundaries touched by the latest paint
## footprint. This is the live-ghost path; it does not scan or rebuild geometry.
func defs_for_touched_cells(
	layers: HFPaintLayerManager,
	touched_layer_index: int,
	touched_cells: Dictionary,
	settings: Settings = null
) -> Array:
	if touched_cells.is_empty():
		return []
	if settings == null:
		settings = Settings.new()
	var touched := boundaries_for_cells(layers, touched_layer_index, touched_cells)
	return defs_from_groups(group_segments(touched), settings)


func defs_from_groups(groups: Array, settings: Settings) -> Array:
	var definitions: Array = []

	for group: Array in groups:
		if group.is_empty():
			continue
		# Use midpoint of the group as connector endpoints.
		var mid_idx: int = group.size() / 2
		var rep: ConnectorSegment = group[mid_idx]
		var def := HFConnectorTool.ConnectorDef.new()
		def.from_layer_index = rep.from_layer_index
		def.to_layer_index = rep.to_layer_index
		def.from_cell = rep.from_cell
		def.to_cell = rep.to_cell
		def.width_cells = settings.width_cells

		# Choose connector type.
		var use_stairs := false
		match settings.mode:
			ConnectorMode.RAMP:
				use_stairs = false
			ConnectorMode.STAIRS:
				use_stairs = true
			ConnectorMode.AUTO:
				use_stairs = rep.height_diff >= settings.stair_threshold

		if use_stairs:
			def.connector_type = HFConnectorTool.ConnectorType.STAIRS
			def.stair_step_height = settings.stair_step_height
		else:
			def.connector_type = HFConnectorTool.ConnectorType.RAMP
		definitions.append(def)
	return definitions


func generate_definitions(definitions: Array, layers: HFPaintLayerManager) -> Array:
	var tool := HFConnectorTool.new()
	var results: Array = []
	for definition in definitions:
		if not definition is HFConnectorTool.ConnectorDef:
			continue
		var def := definition as HFConnectorTool.ConnectorDef

		var mesh: ArrayMesh = tool.generate_connector(def, layers)
		if mesh:
			results.append({"mesh": mesh, "transform": Transform3D.IDENTITY, "definition": def})
	return results
