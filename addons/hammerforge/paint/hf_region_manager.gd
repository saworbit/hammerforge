@tool
class_name HFTerrainRegionManager
extends RefCounted

const DEFAULT_REGION_SIZE_CELLS := 512
const DEFAULT_STREAM_RADIUS := 2

var region_size_cells: int = DEFAULT_REGION_SIZE_CELLS
var streaming_radius: int = DEFAULT_STREAM_RADIUS
var chunk_size: int = 32
var base_grid: HFPaintGrid

var loaded_regions: Dictionary = {}  # Dictionary[Vector2i, bool]
var pinned_regions: Dictionary = {}  # Dictionary[Vector2i, bool]
var dirty_regions: Dictionary = {}  # Dictionary[Vector2i, bool]
var region_index: Dictionary = {}  # Dictionary[Vector2i, Dictionary]
var last_access: Dictionary = {}  # Dictionary[Vector2i, int]

var region_base_path: String = ""


func region_id_from_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(region_size_cells)),
		floori(float(cell.y) / float(region_size_cells))
	)


func region_bounds_cells(region_id: Vector2i) -> Rect2i:
	var min_cell := Vector2i(region_id.x * region_size_cells, region_id.y * region_size_cells)
	return Rect2i(min_cell, Vector2i(region_size_cells, region_size_cells))


func region_bounds_chunks(region_id: Vector2i) -> Rect2i:
	var cell_bounds := region_bounds_cells(region_id)
	var min_cell := cell_bounds.position
	var max_cell := cell_bounds.position + cell_bounds.size - Vector2i.ONE
	var min_chunk := Vector2i(
		floori(float(min_cell.x) / float(chunk_size)), floori(float(min_cell.y) / float(chunk_size))
	)
	var max_chunk := Vector2i(
		floori(float(max_cell.x) / float(chunk_size)), floori(float(max_cell.y) / float(chunk_size))
	)
	var size := Vector2i(max_chunk.x - min_chunk.x + 1, max_chunk.y - min_chunk.y + 1)
	return Rect2i(min_chunk, size)


func region_ids_in_radius(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-streaming_radius, streaming_radius + 1):
		for dx in range(-streaming_radius, streaming_radius + 1):
			out.append(Vector2i(center.x + dx, center.y + dy))
	return out


func mark_loaded(region_id: Vector2i) -> void:
	loaded_regions[region_id] = true
	last_access[region_id] = Time.get_ticks_msec()


func mark_unloaded(region_id: Vector2i) -> void:
	loaded_regions.erase(region_id)
	last_access.erase(region_id)


func mark_dirty(region_id: Vector2i) -> void:
	dirty_regions[region_id] = true
	region_index[region_id] = {"has_data": true}


func clear_dirty(region_id: Vector2i) -> void:
	dirty_regions.erase(region_id)


func is_loaded(region_id: Vector2i) -> bool:
	return loaded_regions.has(region_id)


func is_pinned(region_id: Vector2i) -> bool:
	return pinned_regions.has(region_id)


func set_pinned(region_id: Vector2i, pinned: bool) -> void:
	if pinned:
		pinned_regions[region_id] = true
	else:
		pinned_regions.erase(region_id)


func region_key(region_id: Vector2i) -> String:
	return "%d,%d" % [region_id.x, region_id.y]


func parse_region_key(key: String) -> Vector2i:
	var parts = key.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
