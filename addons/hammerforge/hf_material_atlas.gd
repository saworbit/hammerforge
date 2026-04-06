@tool
extends RefCounted
class_name HFMaterialAtlas
## Packs multiple StandardMaterial3D albedo textures into a single atlas texture,
## then remaps face UVs so the entire baked level can render with one draw call.

const MAX_ATLAS_SIZE := 4096
const MIN_TILE_SIZE := 64
## Padding pixels around each tile to prevent mipmap bleed between neighbours.
const GUTTER := 2


## Result returned by build_atlas().
## rects: Dictionary[Material, Rect2] — normalized UV rect per material in the atlas.
## atlas_material: StandardMaterial3D — single material with the packed atlas texture.
## atlased_keys: Array[Material] — materials that were successfully packed.
## fallback_keys: Array — material keys that could NOT be atlased (ShaderMaterial, etc.).
class AtlasResult:
	var rects: Dictionary = {}  # material_key -> Rect2 (normalized 0-1)
	var atlas_material: StandardMaterial3D = null
	var atlased_keys: Array = []
	var fallback_keys: Array = []


## Build an atlas from the unique materials used in a face bake.
## material_keys: Array of material keys (Material or "_default") from the grouping pass.
## exclude_keys: set of keys (Dictionary key->true) that must NOT be atlased (e.g. tiling).
## Returns AtlasResult.
static func build_atlas(material_keys: Array, exclude_keys: Dictionary = {}) -> AtlasResult:
	var result = AtlasResult.new()
	# Separate atlasable (StandardMaterial3D with albedo texture) from fallbacks.
	var tiles: Array = []  # Array of {key, image, w, h}
	for key in material_keys:
		if exclude_keys.has(key):
			result.fallback_keys.append(key)
			continue
		if key is StandardMaterial3D:
			var std: StandardMaterial3D = key
			var tex: Texture2D = std.albedo_texture
			if tex:
				var img: Image = tex.get_image()
				if img:
					img = img.duplicate()
					# Clamp oversized textures to keep atlas manageable.
					var tw: int = img.get_width()
					var th: int = img.get_height()
					if tw > MAX_ATLAS_SIZE / 2 or th > MAX_ATLAS_SIZE / 2:
						var scale_factor: float = float(MAX_ATLAS_SIZE / 2) / float(maxi(tw, th))
						img.resize(
							maxi(MIN_TILE_SIZE, int(tw * scale_factor)),
							maxi(MIN_TILE_SIZE, int(th * scale_factor))
						)
						tw = img.get_width()
						th = img.get_height()
					tiles.append({"key": key, "image": img, "w": tw, "h": th})
					continue
		# Not atlasable — shader material, null, string key, or no texture.
		result.fallback_keys.append(key)

	if tiles.is_empty():
		return result

	# Sort tiles by height descending for better shelf packing.
	tiles.sort_custom(func(a, b): return a["h"] > b["h"])

	# Shelf-pack with gutter added to each tile dimension.
	var padded_tiles: Array = []
	for tile in tiles:
		(
			padded_tiles
			. append(
				{
					"key": tile["key"],
					"image": tile["image"],
					"w": tile["w"] + GUTTER * 2,
					"h": tile["h"] + GUTTER * 2,
				}
			)
		)

	# Determine atlas dimensions via shelf-packing.
	var pack_result: Dictionary = _shelf_pack(padded_tiles)
	var atlas_w: int = pack_result["width"]
	var atlas_h: int = pack_result["height"]
	var placements: Array = pack_result["placements"]  # Array of {x, y} per tile index

	# Blit tiles onto atlas image with gutter padding.
	var atlas_img = Image.create(atlas_w, atlas_h, false, Image.FORMAT_RGBA8)
	for i in range(tiles.size()):
		var tile = tiles[i]
		var pos = placements[i]
		var img: Image = tile["image"]
		# Ensure matching format before blit.
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		# Tile content is placed at (pos + GUTTER) inside the padded cell.
		var content_x: int = pos["x"] + GUTTER
		var content_y: int = pos["y"] + GUTTER
		atlas_img.blit_rect(img, Rect2i(0, 0, tile["w"], tile["h"]), Vector2i(content_x, content_y))
		# Extend edge pixels into the gutter to prevent mipmap bleed.
		_fill_gutter(atlas_img, content_x, content_y, tile["w"], tile["h"])

	# Build normalized rects inset by half a texel so sampling stays inside
	# the actual tile content and never reaches the gutter.  For very small
	# tiles (1-2 px) the inset is clamped so the rect never collapses to zero.
	var inv_w: float = 1.0 / float(atlas_w)
	var inv_h: float = 1.0 / float(atlas_h)
	for i in range(tiles.size()):
		var tile = tiles[i]
		var pos = placements[i]
		var cx: float = float(pos["x"] + GUTTER)
		var cy: float = float(pos["y"] + GUTTER)
		var tw: float = float(tile["w"])
		var th: float = float(tile["h"])
		# Inset at most 1/4 of the tile extent per side so the rect keeps
		# at least half its original size even for 1px tiles.
		var inset_u: float = minf(0.5 * inv_w, tw * inv_w * 0.25)
		var inset_v: float = minf(0.5 * inv_h, th * inv_h * 0.25)
		var rect = Rect2(
			cx * inv_w + inset_u,
			cy * inv_h + inset_v,
			tw * inv_w - inset_u * 2.0,
			th * inv_h - inset_v * 2.0,
		)
		result.rects[tile["key"]] = rect
		result.atlased_keys.append(tile["key"])

	# Create atlas material.
	var atlas_tex = ImageTexture.create_from_image(atlas_img)
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = atlas_tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	result.atlas_material = mat
	return result


## Fill the GUTTER-pixel border around a tile by copying edge pixels outward.
## Prevents colour bleed from neighbouring tiles when mipmaps are sampled.
static func _fill_gutter(atlas: Image, cx: int, cy: int, tw: int, th: int) -> void:
	# Top and bottom horizontal strips.
	for x in range(tw):
		var top_pixel: Color = atlas.get_pixel(cx + x, cy)
		var bot_pixel: Color = atlas.get_pixel(cx + x, cy + th - 1)
		for g in range(1, GUTTER + 1):
			atlas.set_pixel(cx + x, cy - g, top_pixel)
			atlas.set_pixel(cx + x, cy + th - 1 + g, bot_pixel)
	# Left and right vertical strips (including corners).
	for y in range(-GUTTER, th + GUTTER):
		var sample_y: int = clampi(cy + y, cy, cy + th - 1)
		var left_pixel: Color = atlas.get_pixel(cx, sample_y)
		var right_pixel: Color = atlas.get_pixel(cx + tw - 1, sample_y)
		for g in range(1, GUTTER + 1):
			atlas.set_pixel(cx - g, cy + y, left_pixel)
			atlas.set_pixel(cx + tw - 1 + g, cy + y, right_pixel)


## Remap a UV coordinate from [0,1] material space into atlas sub-rect space.
## Faces with tiling UVs (outside 0..1) are excluded from the atlas entirely,
## so this is a simple linear scale+offset — no wrapping.
static func remap_uv(uv: Vector2, rect: Rect2) -> Vector2:
	return Vector2(
		rect.position.x + uv.x * rect.size.x,
		rect.position.y + uv.y * rect.size.y,
	)


## Check whether a group's UVs tile (any component outside 0..1).
## Returns true if any vertex UV would require hardware texture repeat.
static func group_has_tiling_uvs(uvs: PackedVector2Array) -> bool:
	for uv in uvs:
		if uv.x < -0.01 or uv.x > 1.01 or uv.y < -0.01 or uv.y > 1.01:
			return true
	return false


# ---------------------------------------------------------------------------
# Shelf bin-packing
# ---------------------------------------------------------------------------


## Simple shelf packer. Returns {width, height, placements} where placements
## is an array of {x, y} dicts matching the input tile order.
static func _shelf_pack(tiles: Array) -> Dictionary:
	# Estimate initial width from total area.
	var total_area := 0
	for tile in tiles:
		total_area += tile["w"] * tile["h"]
	var side: int = _next_power_of_2(int(ceil(sqrt(float(total_area)))))
	# Try packing at increasing widths until everything fits.
	var atlas_w: int = maxi(side, MIN_TILE_SIZE)
	while atlas_w <= MAX_ATLAS_SIZE:
		var pack = _try_shelf_pack(tiles, atlas_w)
		if pack["success"]:
			return pack
		atlas_w *= 2
	# Fallback: very wide single row (shouldn't happen for reasonable input).
	return _try_shelf_pack(tiles, MAX_ATLAS_SIZE)


static func _try_shelf_pack(tiles: Array, max_width: int) -> Dictionary:
	var placements: Array = []
	placements.resize(tiles.size())
	var shelf_x := 0
	var shelf_y := 0
	var shelf_h := 0
	for i in range(tiles.size()):
		var tw: int = tiles[i]["w"]
		var th: int = tiles[i]["h"]
		if shelf_x + tw > max_width:
			# New shelf row.
			shelf_y += shelf_h
			shelf_x = 0
			shelf_h = 0
		if shelf_x + tw > max_width:
			return {"success": false, "width": 0, "height": 0, "placements": []}
		placements[i] = {"x": shelf_x, "y": shelf_y}
		shelf_x += tw
		shelf_h = maxi(shelf_h, th)
	var total_h: int = _next_power_of_2(shelf_y + shelf_h)
	if total_h > MAX_ATLAS_SIZE:
		return {"success": false, "width": 0, "height": 0, "placements": []}
	return {"success": true, "width": max_width, "height": total_h, "placements": placements}


static func _next_power_of_2(v: int) -> int:
	if v <= 0:
		return 1
	v -= 1
	v |= v >> 1
	v |= v >> 2
	v |= v >> 4
	v |= v >> 8
	v |= v >> 16
	return v + 1
