@tool
class_name HFPaintLayer
extends Node

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFHeightmapIO = preload("hf_heightmap_io.gd")
@warning_ignore_restore("shadowed_global_identifier")

const TERRAIN_SLOTS := 4
const TERRAIN_BLEND_SLOTS := 3  # slots 1..3 have explicit weights; slot 0 is implicit base

@export var grid: HFPaintGrid
## Cells per chunk, on both axes.
##
## A chunk allocates its bit, material and blend arrays for the size it was built
## at, while `_cell_to_local()` reduces a cell against *this* number. Change it
## once chunks exist and the two disagree: local coordinates run up to the new
## size against arrays sized for the old one, and the next read is an out of
## bounds index into a PackedByteArray rather than anything the layer can report.
## So a change is refused once there is a chunk to invalidate. Set it on a fresh
## layer, which is what every caller that legitimately sets it already does.
var _chunk_size: int = 32
@export var chunk_size: int = 32:
	set(value):
		if value == _chunk_size:
			return
		if value < 1:
			HFLog.warn(
				"HFPaintLayer: chunk size %d is not a size, keeping %d" % [value, _chunk_size]
			)
			return
		if not _chunks.is_empty():
			(
				HFLog
				. warn(
					(
						"HFPaintLayer '%s': chunk size cannot change from %d to %d once the layer holds paint, keeping %d"
						% [str(layer_id), _chunk_size, value, _chunk_size]
					)
				)
			)
			return
		_chunk_size = value
	get:
		return _chunk_size
@export var layer_id: StringName = &"layer_0"
var display_name: String = ""

# Heights. Where a sculpt has been, the ground is the sculpted samples kept per
# chunk. Everywhere else it is the base: `heightmap`, a noise field, or flat.
# One image read by `posmod(cell, width)` repeated the ground every width, and
# a sculpt landed again a width away (#2007).
var heightmap: Image = null
## The cell `heightmap` is placed at by `set_height_image()`.
var heightmap_origin := Vector2i.ZERO
## A level saved before #2007 has an image with no place, read repeating from
## cell (0, 0) as it was saved. A placed one reads its nearest edge outside it.
var heightmap_repeats := true
var height_scale: float = 10.0
var _height_noise: Dictionary = {}
var _noise: FastNoiseLite = null
var _height_chunks: Dictionary = {}  # Dictionary[Vector2i, Image], FORMAT_RF chunk_size square

# Terrain slot settings (per-layer)
var terrain_slot_paths: Array[String] = ["", "", "", ""]
var terrain_slot_uv_scales: Array[float] = [1.0, 1.0, 1.0, 1.0]
var terrain_slot_tints: Array[Color] = [
	Color(0.35, 0.55, 0.25), Color(0.55, 0.45, 0.3), Color(0.45, 0.5, 0.55), Color(0.5, 0.5, 0.5)
]

# Chunk storage: key -> ChunkData
var _chunks: Dictionary = {}  # Dictionary[Vector2i, HFChunkData]
var _dirty_chunks: Dictionary = {}  # Dictionary[Vector2i, bool] used as set
## Per-cell wall heights created by the paint-then-raise gesture. Cells without
## an override continue to use HFPaintTool.synth_settings.wall_height.
var _wall_heights: Dictionary = {}  # Dictionary[Vector2i, float]


func has_heightmap() -> bool:
	return (
		(heightmap != null and not heightmap.is_empty())
		or _noise != null
		or not _height_chunks.is_empty()
	)


## The height at corner `cell`, with the Height Scale.
func get_height_at(cell: Vector2i) -> float:
	return get_height_sample(cell) * height_scale


## The ground at corner `corner` before the Height Scale: the sculpted sample
## where a sculpt has been, the base everywhere else.
func get_height_sample(corner: Vector2i) -> float:
	if not _height_chunks.is_empty():
		var sculpted: Image = _height_chunks.get(_cell_to_chunk(corner)) as Image
		if sculpted != null:
			var local := _cell_to_local(corner)
			return sculpted.get_pixel(local.x, local.y).r
	return _base_sample(corner)


## The samples at the corners from `from` to `from + size - 1`, row by row. A
## heightmap floor reads a chunk's corners once rather than four times a cell,
## and a sculpt reads its brush's box once. It goes a chunk at a time, so each
## chunk is looked up once rather than once a corner.
func get_height_samples(from: Vector2i, size: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(size.x * size.y)
	var first := _cell_to_chunk(from)
	var last := _cell_to_chunk(from + size - Vector2i.ONE)
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var cid := Vector2i(cx, cy)
			var start := cid * chunk_size
			var lo := Vector2i(maxi(from.x, start.x), maxi(from.y, start.y))
			var hi := Vector2i(
				mini(from.x + size.x, start.x + chunk_size),
				mini(from.y + size.y, start.y + chunk_size)
			)
			var sculpted: Image = _height_chunks.get(cid) as Image
			for y in range(lo.y, hi.y):
				var row := (y - from.y) * size.x - from.x
				for x in range(lo.x, hi.x):
					out[row + x] = (
						sculpted.get_pixel(x - start.x, y - start.y).r
						if sculpted != null
						else _base_sample(Vector2i(x, y))
					)
	return out


## Sculpt the sample at corner `corner`. The chunk is filled from the base before
## its first change, so no height beside the change moves. False when the sample
## already held `value`.
func set_height_sample(corner: Vector2i, value: float) -> bool:
	var cid := _cell_to_chunk(corner)
	var local := _cell_to_local(corner)
	var sculpted: Image = _height_chunks.get(cid) as Image
	if sculpted == null:
		if _base_sample(corner) == value:
			return false
		sculpted = _base_chunk(cid)
		_height_chunks[cid] = sculpted
	if sculpted.get_pixel(local.x, local.y).r == value:
		return false
	sculpted.set_pixel(local.x, local.y, Color(value, 0, 0))
	return true


## Give the layer `img` as its ground, its top left pixel on cell `origin`. Past
## the image a corner reads the nearest edge, so nothing repeats. The sculpts and
## any noise go, as they always went with a new heightmap.
##
## Kept with each cell's pixel at `posmod(cell, size)`, as a build from before
## #2007 reads it, so that build shows the ground right inside the image.
func set_height_image(img: Image, origin: Vector2i) -> void:
	clear_heights()
	if img == null or img.is_empty():
		return
	heightmap = _placed(img, origin)
	heightmap_origin = origin
	heightmap_repeats = false


## Give the layer a noise field as its ground, sampled at each corner, so it goes
## on in every direction without repeating. `settings` as
## `HFHeightmapIO.noise_settings()` reads them. The sculpts and any image go.
func set_height_noise(settings: Dictionary) -> void:
	clear_heights()
	_height_noise = HFHeightmapIO.noise_settings(settings)
	_noise = HFHeightmapIO.make_noise(_height_noise)


## The noise the ground is, as a save writes it, or empty.
func get_height_noise() -> Dictionary:
	return _height_noise.duplicate()


## Flat ground: no image, no noise, no sculpt.
func clear_heights() -> void:
	heightmap = null
	heightmap_origin = Vector2i.ZERO
	heightmap_repeats = true
	_height_noise = {}
	_noise = null
	_height_chunks.clear()


func get_height_chunk_ids() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cid: Vector2i in _height_chunks:
		out.append(cid)
	return out


## The sculpted samples of chunk `cid`, a copy, or null where nothing is sculpted.
func get_height_chunk(cid: Vector2i) -> Image:
	var sculpted: Image = _height_chunks.get(cid) as Image
	if sculpted == null:
		return null
	var copy := Image.new()
	copy.copy_from(sculpted)
	return copy


## Put back the sculpted samples of chunk `cid`. False, keeping nothing, for an
## image that is not this layer's chunk size square.
func set_height_chunk(cid: Vector2i, img: Image) -> bool:
	if img == null or img.get_width() != chunk_size or img.get_height() != chunk_size:
		return false
	var copy := Image.new()
	copy.copy_from(img)
	if copy.get_format() != Image.FORMAT_RF:
		copy.convert(Image.FORMAT_RF)
	_height_chunks[cid] = copy
	_mark_dirty(cid)
	_mark_dirty_neighbours(cid)
	return true


func _base_sample(corner: Vector2i) -> float:
	if _noise != null:
		# Through a Color's 32 bit channel, as a kept sample is, so a corner reads
		# the same sculpted, filled or not.
		return Color(_noise.get_noise_2d(corner.x, corner.y) * 0.5 + 0.5, 0, 0).r
	if heightmap == null or heightmap.is_empty():
		return 0.0
	var size := heightmap.get_size()
	var at := corner
	if not heightmap_repeats:
		at = corner.clamp(heightmap_origin, heightmap_origin + size - Vector2i.ONE)
	return heightmap.get_pixel(posmod(at.x, size.x), posmod(at.y, size.y)).r


func _base_chunk(cid: Vector2i) -> Image:
	var img := Image.create(chunk_size, chunk_size, false, Image.FORMAT_RF)
	var first := cid * chunk_size
	for y in range(chunk_size):
		for x in range(chunk_size):
			img.set_pixel(x, y, Color(_base_sample(first + Vector2i(x, y)), 0, 0))
	return img


## `img` with its pixel (x, y) moved to `posmod(origin + (x, y), size)`, in up to
## four blits.
static func _placed(img: Image, origin: Vector2i) -> Image:
	var src := Image.new()
	src.copy_from(img)
	if src.get_format() != Image.FORMAT_RF:
		src.convert(Image.FORMAT_RF)
	var size := src.get_size()
	var shift := Vector2i(posmod(origin.x, size.x), posmod(origin.y, size.y))
	if shift == Vector2i.ZERO:
		return src
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	# Each run of columns and of rows as (first, count): the run that moves on by
	# the shift, and the run that wraps round to the start.
	var columns: Array[Vector2i] = [
		Vector2i(0, size.x - shift.x), Vector2i(size.x - shift.x, shift.x)
	]
	var rows: Array[Vector2i] = [Vector2i(0, size.y - shift.y), Vector2i(size.y - shift.y, shift.y)]
	for column in columns:
		for row in rows:
			if column.y == 0 or row.y == 0:
				continue
			var to := Vector2i((column.x + shift.x) % size.x, (row.x + shift.y) % size.y)
			out.blit_rect(src, Rect2i(column.x, row.x, column.y, row.y), to)
	return out


func set_cell(cell: Vector2i, filled: bool) -> void:
	var cid := _cell_to_chunk(cell)
	# Erasing does not need a chunk. Going through _get_or_create_chunk() on the
	# way out allocated one full of zeros for every stroke over unpainted ground,
	# which is the same leak from the other direction.
	var chunk: HFChunkData = (
		_get_or_create_chunk(cid) if filled else _chunks.get(cid) as HFChunkData
	)
	var local := _cell_to_local(cell)
	var changed: bool = chunk.set_bit(local, filled) if chunk != null else false
	var removed_height := false
	if not filled:
		removed_height = _wall_heights.erase(cell)
	if changed or removed_height:
		# A chunk whose last bit just cleared holds nothing but zeros, and holding
		# it costs memory that get_paint_memory_bytes() reports and, worse, weight
		# in every .hflevel save and every undo snapshot, permanently, for paint
		# the user removed.
		#
		# Dropped before the dirty mark rather than after: remove_chunk() clears
		# the dirty flag too, and the reconciler needs to see this chunk to take
		# its geometry away. Region eviction reconciles removed chunk ids the same
		# way.
		if not filled and chunk != null and chunk.is_empty():
			remove_chunk(cid)
		_mark_dirty(cid)
		_mark_dirty_neighbours(cid)


func get_cell(cell: Vector2i) -> bool:
	var cid := _cell_to_chunk(cell)
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	if chunk == null:
		return false
	return chunk.get_bit(_cell_to_local(cell))


func set_wall_height(cell: Vector2i, height: float) -> void:
	var value := maxf(0.0, height)
	if _wall_heights.has(cell) and is_equal_approx(float(_wall_heights[cell]), value):
		return
	_wall_heights[cell] = value
	var cid := _cell_to_chunk(cell)
	_mark_dirty(cid)
	_mark_dirty_neighbours(cid)


func clear_wall_height(cell: Vector2i) -> void:
	if not _wall_heights.erase(cell):
		return
	var cid := _cell_to_chunk(cell)
	_mark_dirty(cid)
	_mark_dirty_neighbours(cid)


func get_wall_height(cell: Vector2i, fallback: float) -> float:
	return float(_wall_heights.get(cell, fallback))


func get_wall_height_entries() -> Array:
	var out: Array = []
	for cell: Vector2i in _wall_heights:
		out.append({"x": cell.x, "y": cell.y, "height": float(_wall_heights[cell])})
	return out


func get_chunk_wall_height_entries(cid: Vector2i) -> Array:
	var out: Array = []
	for cell: Vector2i in _wall_heights:
		if _cell_to_chunk(cell) == cid:
			out.append({"x": cell.x, "y": cell.y, "height": float(_wall_heights[cell])})
	return out


func restore_wall_height_entries(entries: Array) -> void:
	for entry in entries:
		if not entry is Dictionary:
			continue
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		_wall_heights[cell] = maxf(0.0, float(entry.get("height", 0.0)))


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


## True when the chunk holds no filled cells, or is not there at all.
func is_chunk_empty(cid: Vector2i) -> bool:
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	return chunk == null or chunk.is_empty()


## The first painted cell on each axis: the corner of the painted ground's
## bounds, or cell (0, 0) when nothing is painted.
func painted_corner() -> Vector2i:
	var corner := Vector2i(2147483647, 2147483647)
	for cid: Vector2i in _chunks:
		var chunk: HFChunkData = _chunks[cid] as HFChunkData
		var first := cid * chunk_size
		if chunk == null or chunk.is_empty():
			continue
		if first.x >= corner.x and first.y >= corner.y:
			continue
		for y in range(chunk_size):
			for x in range(chunk_size):
				if chunk.get_bit(Vector2i(x, y)):
					corner = Vector2i(mini(corner.x, first.x + x), mini(corner.y, first.y + y))
	return Vector2i.ZERO if corner.x == 2147483647 else corner


## How many cells are filled, from each chunk's counter rather than its bits.
func filled_cell_count() -> int:
	var total := 0
	for chunk in _chunks.values():
		if chunk != null:
			total += maxi(0, (chunk as HFChunkData).live_bits)
	return total


## One chunk as a save or an undo snapshot writes it: its bits, material ids and
## three blend weight slots, each byte as an int. The region files and the state
## capture both pack chunks through this (#900), and each adds what it keeps
## beside them.
func packed_chunk(cid: Vector2i) -> Dictionary:
	return {
		"cx": cid.x,
		"cy": cid.y,
		"bits": _byte_ints(get_chunk_bits(cid)),
		"material_ids": _byte_ints(get_chunk_material_ids(cid)),
		"blend_weights": _byte_ints(get_chunk_blend_weights(cid)),
		"blend_weights_2": _byte_ints(get_chunk_blend_weights_slot(cid, 2)),
		"blend_weights_3": _byte_ints(get_chunk_blend_weights_slot(cid, 3)),
	}


static func _byte_ints(bytes: PackedByteArray) -> Array:
	var out: Array = []
	for b in bytes:
		out.append(int(b))
	return out


func get_chunk_bits(cid: Vector2i) -> PackedByteArray:
	var chunk: HFChunkData = _chunks.get(cid) as HFChunkData
	if chunk == null:
		return PackedByteArray()
	return chunk.bits.duplicate()


func set_chunk_bits(cid: Vector2i, bits: PackedByteArray) -> void:
	var chunk: HFChunkData = _get_or_create_chunk(cid)
	chunk.bits = bits.duplicate()
	chunk.recount_live_bits()
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
	_wall_heights.clear()


func remove_chunk(cid: Vector2i) -> bool:
	if not _chunks.has(cid):
		return false
	_chunks.erase(cid)
	_dirty_chunks.erase(cid)
	_remove_wall_heights_in_chunk(cid)
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
		_remove_wall_heights_in_chunk(cid)
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
	total += _wall_heights.size() * 12
	for sculpted: Image in _height_chunks.values():
		total += sculpted.get_data_size()
	if heightmap:
		var data := heightmap.get_data()
		if data:
			total += data.size()
	return total


func _remove_wall_heights_in_chunk(cid: Vector2i) -> void:
	var remove: Array[Vector2i] = []
	for cell: Vector2i in _wall_heights:
		if _cell_to_chunk(cell) == cid:
			remove.append(cell)
	for cell in remove:
		_wall_heights.erase(cell)


func get_terrain_slot_textures() -> Array:
	_ensure_terrain_slots()
	var out: Array = []
	for path in terrain_slot_paths:
		if path == "" or not ResourceLoader.exists(path):
			out.append(null)
		else:
			out.append(load(path))
	return out


## Point terrain slot `slot` at `path`. False when nothing changed, so the
## caller can skip the rebuild.
##
## The dock used to write `terrain_slot_paths[i]` straight through - the one
## place in the plugin that wrote a layer's arrays from outside the layer, and
## with nothing bounding the index.
func set_terrain_slot_texture(slot: int, path: String) -> bool:
	_ensure_terrain_slots()
	if slot < 0 or slot >= TERRAIN_SLOTS:
		return false
	if terrain_slot_paths[slot] == path:
		return false
	terrain_slot_paths[slot] = path
	return true


## The UV scale of terrain slot `slot`. False when nothing changed.
func set_terrain_slot_uv_scale(slot: int, value: float) -> bool:
	_ensure_terrain_slots()
	if slot < 0 or slot >= TERRAIN_SLOTS:
		return false
	if not is_finite(value) or is_equal_approx(terrain_slot_uv_scales[slot], value):
		return false
	terrain_slot_uv_scales[slot] = value
	return true


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
	## How many cells are filled. Kept as a counter so "is this chunk empty" is a
	## comparison rather than a scan of every byte on each erase.
	var live_bits: int = 0
	var material_ids: PackedByteArray  # 1 byte per cell (0-255 material index)
	var blend_weights: PackedByteArray  # 1 byte per cell (0-255, normalized to 0.0-1.0)
	var blend_weights_2: PackedByteArray  # slot 2
	var blend_weights_3: PackedByteArray  # slot 3

	func _init(sz: int) -> void:
		size = sz
		var n_cells := size * size
		@warning_ignore("integer_division")
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
			live_bits += 1
		else:
			bits[byte_i] &= ~mask
			live_bits -= 1
		return true

	func is_empty() -> bool:
		return live_bits <= 0

	## Recount from the bytes. Needed whenever the bitset is written whole rather
	## than a cell at a time, which is what a load does.
	func recount_live_bits() -> void:
		var count := 0
		for byte in bits:
			var b: int = byte
			while b != 0:
				count += b & 1
				b >>= 1
		live_bits = count

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
