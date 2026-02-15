@tool
class_name HFPaintLayer
extends Node

@export var grid: HFPaintGrid
@export var chunk_size: int = 32
@export var layer_id: StringName = &"layer_0"

# Heightmap data (optional; null = flat layer)
var heightmap: Image = null
var height_scale: float = 10.0

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


func clear_chunks() -> void:
	_chunks.clear()
	_dirty_chunks.clear()


func get_memory_bytes() -> int:
	var total := 0
	for chunk in _chunks.values():
		if chunk == null:
			continue
		total += chunk.bits.size()
		total += chunk.material_ids.size()
		total += chunk.blend_weights.size()
	if has_heightmap() and heightmap:
		var data := heightmap.get_data()
		if data:
			total += data.size()
	return total


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
