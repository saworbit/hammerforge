@tool
class_name HFPaintLayer
extends Node

const TERRAIN_SLOTS := 4
const TERRAIN_BLEND_SLOTS := 3  # slots 1..3 have explicit weights; slot 0 is implicit base

@export var grid: HFPaintGrid
@export var chunk_size: int = 32
@export var layer_id: StringName = &"layer_0"

# Heightmap data (optional; null = flat layer)
var heightmap: Image = null
var height_scale: float = 10.0

# Terrain slot settings (per-layer)
var terrain_slot_paths: Array[String] = ["", "", "", ""]
var terrain_slot_uv_scales: Array[float] = [1.0, 1.0, 1.0, 1.0]
var terrain_slot_tints: Array[Color] = [
	Color(0.35, 0.55, 0.25),
	Color(0.55, 0.45, 0.3),
	Color(0.45, 0.5, 0.55),
	Color(0.5, 0.5, 0.5)
]

# Chunk storage: key -> ChunkData
var _chunks: Dictionary = {}  # Dictionary[Vector2i, HFChunkData]
var _dirty_chunks: Dictionary = {}  # Dictionary[Vector2i, bool] used as set

signal layer_changed(dirty_chunks: Array[Vector2i])


func has_heightmap() -> bool:
	return heightmap != null and not heightmap.is_empty()


func get_height_at(cell: Vector2i) -> float:
	if not has_heightmap():
		return 0.0
	var w := heightmap.get_width()
	var h := heightmap.get_height()
	var px := posmod(cell.x, w)
	var py := posmod(cell.y, h)
	return heightmap.get_pixel(px, py).r * height_scale


func get_height_at_uv(u: float, v: float) -> float:
	if not has_heightmap():
		return 0.0
	var w := heightmap.get_width()
	var h := heightmap.get_height()
	var px := clampi(int(u * w), 0, w - 1)
	var py := clampi(int(v * h), 0, h - 1)
	return heightmap.get_pixel(px, py).r * height_scale


func set_cell(cell: Vector2i, filled: bool) -> void:
	var cid := _cell_to_chunk(cell)
	var chunk: HFChunkData = _get_or_create_chunk(cid)
	var local := _cell_to_local(cell)
	if chunk.set_bit(local, filled):
		_mark_dirty(cid)
		_mark_dirty_neighbours(cid)


func get_cell(cell: Vector2i) -> bool:
	var cid := _cell_to_chunk(cell)
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	if chunk == null:
		return false
	return chunk.get_bit(_cell_to_local(cell))


func set_cell_material(cell: Vector2i, mat_id: int) -> void:
	var cid := _cell_to_chunk(cell)
	var chunk: HFChunkData = _get_or_create_chunk(cid)
	var local := _cell_to_local(cell)
	chunk.set_material(local, mat_id)
	_mark_dirty(cid)


func get_cell_material(cell: Vector2i) -> int:
	var cid := _cell_to_chunk(cell)
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	if chunk == null:
		return 0
	return chunk.get_material(_cell_to_local(cell))


func set_cell_blend(cell: Vector2i, weight: float) -> void:
	var cid := _cell_to_chunk(cell)
	var chunk: HFChunkData = _get_or_create_chunk(cid)
	var local := _cell_to_local(cell)
	chunk.set_blend(local, weight)
	_mark_dirty(cid)


func get_cell_blend(cell: Vector2i) -> float:
	var cid := _cell_to_chunk(cell)
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	if chunk == null:
		return 0.0
	return chunk.get_blend(_cell_to_local(cell))


func set_cell_blend_slot(cell: Vector2i, slot: int, weight: float) -> void:
	if slot == 1:
		set_cell_blend(cell, weight)
		return
	if slot < 1 or slot > 3:
		return
	var cid := _cell_to_chunk(cell)
	var chunk: HFChunkData = _get_or_create_chunk(cid)
	var local := _cell_to_local(cell)
	chunk.set_blend_slot(local, slot, weight)
	_mark_dirty(cid)


func get_cell_blend_slot(cell: Vector2i, slot: int) -> float:
	if slot == 1:
		return get_cell_blend(cell)
	if slot < 1 or slot > 3:
		return 0.0
	var cid := _cell_to_chunk(cell)
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	if chunk == null:
		return 0.0
	return chunk.get_blend_slot(_cell_to_local(cell), slot)


func consume_dirty_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in _dirty_chunks.keys():
		out.append(k)
	_dirty_chunks.clear()
	return out


func get_chunk_ids() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in _chunks.keys():
		out.append(k)
	return out


func has_chunk(cid: Vector2i) -> bool:
	return _chunks.has(cid)


func get_chunk_bits(cid: Vector2i) -> PackedByteArray:
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	if chunk == null:
		return PackedByteArray()
	return chunk.bits.duplicate()


func set_chunk_bits(cid: Vector2i, bits: PackedByteArray) -> void:
	var chunk: HFChunkData = _get_or_create_chunk(cid)
	chunk.bits = bits.duplicate()
	_mark_dirty(cid)
	_mark_dirty_neighbours(cid)


func get_chunk_material_ids(cid: Vector2i) -> PackedByteArray:
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	if chunk == null:
		return PackedByteArray()
	return chunk.material_ids.duplicate()


func set_chunk_material_ids(cid: Vector2i, data: PackedByteArray) -> void:
	var chunk: HFChunkData = _get_or_create_chunk(cid)
	chunk.material_ids = data.duplicate()
	_mark_dirty(cid)


func get_chunk_blend_weights(cid: Vector2i) -> PackedByteArray:
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	if chunk == null:
		return PackedByteArray()
	return chunk.blend_weights.duplicate()


func set_chunk_blend_weights(cid: Vector2i, data: PackedByteArray) -> void:
	var chunk: HFChunkData = _get_or_create_chunk(cid)
	chunk.blend_weights = data.duplicate()
	_mark_dirty(cid)


func get_chunk_blend_weights_slot(cid: Vector2i, slot: int) -> PackedByteArray:
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	if chunk == null:
		return PackedByteArray()
	return chunk.get_blend_weights_slot(slot).duplicate()


func set_chunk_blend_weights_slot(cid: Vector2i, slot: int, data: PackedByteArray) -> void:
	var chunk: HFChunkData = _get_or_create_chunk(cid)
	chunk.set_blend_weights_slot(slot, data)
	_mark_dirty(cid)


func clear_chunks() -> void:
	_chunks.clear()
	_dirty_chunks.clear()


func remove_chunk(cid: Vector2i) -> bool:
	if not _chunks.has(cid):
		return false
	_chunks.erase(cid)
	_dirty_chunks.erase(cid)
	return true


func remove_chunks_in_range(min_chunk: Vector2i, max_chunk: Vector2i) -> Array[Vector2i]:
	var removed: Array[Vector2i] = []
	for cid in _chunks.keys():
		var c := cid as Vector2i
		if c.x < min_chunk.x or c.x > max_chunk.x:
			continue
		if c.y < min_chunk.y or c.y > max_chunk.y:
			continue
		removed.append(c)
	for cid in removed:
		_chunks.erase(cid)
		_dirty_chunks.erase(cid)
	return removed


func get_memory_bytes() -> int:
	var total := 0
	for chunk in _chunks.values():
		if chunk == null:
			continue
		total += chunk.bits.size()
		total += chunk.material_ids.size()
		total += chunk.blend_weights.size()
		total += chunk.blend_weights_2.size()
		total += chunk.blend_weights_3.size()
	if has_heightmap() and heightmap:
		var data := heightmap.get_data()
		if data:
			total += data.size()
	return total


func get_terrain_slot_textures() -> Array:
	_ensure_terrain_slots()
	var out: Array = []
	for path in terrain_slot_paths:
		if path == "" or not ResourceLoader.exists(path):
			out.append(null)
		else:
			out.append(load(path))
	return out


func get_terrain_slot_uv_scales() -> Array[float]:
	_ensure_terrain_slots()
	return terrain_slot_uv_scales.duplicate()


func get_terrain_slot_tints() -> Array[Color]:
	_ensure_terrain_slots()
	return terrain_slot_tints.duplicate()


func _cell_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(chunk_size)), floori(float(cell.y) / float(chunk_size))
	)


func _cell_to_local(cell: Vector2i) -> Vector2i:
	var lx := int(posmod(cell.x, chunk_size))
	var ly := int(posmod(cell.y, chunk_size))
	return Vector2i(lx, ly)


func _get_or_create_chunk(cid: Vector2i) -> HFChunkData:
	var c: HFChunkData = _chunks.get(cid) as HFChunkData
	if c == null:
		c = HFChunkData.new(chunk_size)
		_chunks[cid] = c
	return c


func _mark_dirty(cid: Vector2i) -> void:
	_dirty_chunks[cid] = true


func _mark_dirty_neighbours(cid: Vector2i) -> void:
	# walls can span chunk boundaries, so include neighbours
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			_dirty_chunks[Vector2i(cid.x + dx, cid.y + dy)] = true


# hf_chunk_data.gd (can live inside hf_paint_layer.gd file if you prefer)
class HFChunkData:
	var size: int
	var bits: PackedByteArray  # bitset, size*size bits
	var material_ids: PackedByteArray  # 1 byte per cell (0-255 material index)
	var blend_weights: PackedByteArray  # 1 byte per cell (0-255, normalized to 0.0-1.0)
	var blend_weights_2: PackedByteArray  # slot 2
	var blend_weights_3: PackedByteArray  # slot 3

	func _init(sz: int) -> void:
		size = sz
		var n_cells := size * size
		var n_bytes := (n_cells + 7) / 8
		bits = PackedByteArray()
		bits.resize(n_bytes)
		for i in range(n_bytes):
			bits[i] = 0
		material_ids = PackedByteArray()
		material_ids.resize(n_cells)
		for i in range(n_cells):
			material_ids[i] = 0
		blend_weights = PackedByteArray()
		blend_weights.resize(n_cells)
		for i in range(n_cells):
			blend_weights[i] = 0
		blend_weights_2 = PackedByteArray()
		blend_weights_2.resize(n_cells)
		for i in range(n_cells):
			blend_weights_2[i] = 0
		blend_weights_3 = PackedByteArray()
		blend_weights_3.resize(n_cells)
		for i in range(n_cells):
			blend_weights_3[i] = 0

	func _idx(local: Vector2i) -> int:
		return local.y * size + local.x

	func get_bit(local: Vector2i) -> bool:
		var i := _idx(local)
		var byte_i := i >> 3
		var mask := 1 << (i & 7)
		return (bits[byte_i] & mask) != 0

	# returns true if changed
	func set_bit(local: Vector2i, v: bool) -> bool:
		var i := _idx(local)
		var byte_i := i >> 3
		var mask := 1 << (i & 7)
		var old := (bits[byte_i] & mask) != 0
		if old == v:
			return false
		if v:
			bits[byte_i] |= mask
		else:
			bits[byte_i] &= ~mask
		return true

	func get_material(local: Vector2i) -> int:
		return material_ids[_idx(local)]

	func set_material(local: Vector2i, mat_id: int) -> void:
		material_ids[_idx(local)] = clampi(mat_id, 0, 255)

	func get_blend(local: Vector2i) -> float:
		return float(blend_weights[_idx(local)]) / 255.0

	func set_blend(local: Vector2i, weight: float) -> void:
		blend_weights[_idx(local)] = clampi(int(weight * 255.0), 0, 255)

	func get_blend_slot(local: Vector2i, slot: int) -> float:
		if slot == 2:
			return float(blend_weights_2[_idx(local)]) / 255.0
		if slot == 3:
			return float(blend_weights_3[_idx(local)]) / 255.0
		return get_blend(local)

	func set_blend_slot(local: Vector2i, slot: int, weight: float) -> void:
		var value := clampi(int(weight * 255.0), 0, 255)
		if slot == 2:
			blend_weights_2[_idx(local)] = value
			return
		if slot == 3:
			blend_weights_3[_idx(local)] = value
			return
		blend_weights[_idx(local)] = value

	func get_blend_weights_slot(slot: int) -> PackedByteArray:
		if slot == 2:
			return blend_weights_2
		if slot == 3:
			return blend_weights_3
		return blend_weights

	func set_blend_weights_slot(slot: int, data: PackedByteArray) -> void:
		if slot == 2:
			blend_weights_2 = data.duplicate()
			return
		if slot == 3:
			blend_weights_3 = data.duplicate()
			return
		blend_weights = data.duplicate()


func _ensure_terrain_slots() -> void:
	while terrain_slot_paths.size() < TERRAIN_SLOTS:
		terrain_slot_paths.append("")
	while terrain_slot_uv_scales.size() < TERRAIN_SLOTS:
		terrain_slot_uv_scales.append(1.0)
	while terrain_slot_tints.size() < TERRAIN_SLOTS:
		terrain_slot_tints.append(Color(0.5, 0.5, 0.5))
	if terrain_slot_paths.size() > TERRAIN_SLOTS:
		terrain_slot_paths.resize(TERRAIN_SLOTS)
	if terrain_slot_uv_scales.size() > TERRAIN_SLOTS:
		terrain_slot_uv_scales.resize(TERRAIN_SLOTS)
	if terrain_slot_tints.size() > TERRAIN_SLOTS:
		terrain_slot_tints.resize(TERRAIN_SLOTS)
