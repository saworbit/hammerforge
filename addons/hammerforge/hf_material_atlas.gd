@tool
extends RefCounted
class_name HFMaterialAtlas
## Packs multiple StandardMaterial3D textures into a single atlas texture, then
## remaps face UVs so the entire baked level can render with one draw call.
##
## The albedo atlas defines the layout. Every PBR slot that at least one packed
## material supplies (normal, roughness, metallic, emission) gets a parallel
## atlas using the *same* placements, so one set of remapped UVs addresses all of
## them. A slot with no supplier is skipped entirely and costs nothing.
##
## A slot is only atlased when the per-material settings it collapses into a
## single value are compatible; see [method _channel_blocker]. Incompatible slots
## are recorded in `AtlasResult.skipped_channels` with a reason rather than being
## dropped silently.

const MAX_ATLAS_SIZE := 4096
const MIN_TILE_SIZE := 64
## Padding pixels around each tile to prevent mipmap bleed between neighbours.
const GUTTER := 2

## PBR texture slots that can be packed alongside albedo.
const CHANNEL_NORMAL := "normal"
const CHANNEL_ROUGHNESS := "roughness"
const CHANNEL_METALLIC := "metallic"
const CHANNEL_EMISSION := "emission"
const PBR_CHANNELS: Array = [CHANNEL_NORMAL, CHANNEL_ROUGHNESS, CHANNEL_METALLIC, CHANNEL_EMISSION]

## Tangent-space "no perturbation" normal. Godot rebuilds Z from XY, so only the
## red and green channels carry information.
const FLAT_NORMAL := Color(0.5, 0.5, 1.0, 1.0)

## Tolerance for comparing per-material scalars that the atlas collapses into one.
const SCALAR_EPSILON := 0.0001


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
	## PBR slot names packed alongside albedo and assigned to atlas_material.
	var atlased_channels: Array = []
	## PBR slot name -> reason it could not be packed. Only slots that at least
	## one packed material supplied a texture for appear here.
	var skipped_channels: Dictionary = {}


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
		_fill_gutter(atlas_img, img, content_x, content_y, tile["w"], tile["h"])

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
	_build_pbr_channels(result, tiles, placements, atlas_w, atlas_h)
	return result


# ---------------------------------------------------------------------------
# PBR channel atlases
# ---------------------------------------------------------------------------


## Pack each supplied PBR slot into its own atlas mirroring the albedo layout,
## and assign the results to `result.atlas_material`.
static func _build_pbr_channels(
	result: AtlasResult, tiles: Array, placements: Array, atlas_w: int, atlas_h: int
) -> void:
	if result.atlas_material == null:
		return
	for channel in PBR_CHANNELS:
		var suppliers: Array = []
		for tile in tiles:
			if _channel_texture(tile["key"], channel) != null:
				suppliers.append(tile["key"])
		if suppliers.is_empty():
			# Nobody uses this slot: no atlas, no report, no cost.
			continue
		var blocker: String = _channel_blocker(tiles, suppliers, channel)
		if blocker != "":
			_record_skip(result, channel, blocker)
			continue
		var channel_img: Image = _compose_channel_atlas(
			tiles, placements, atlas_w, atlas_h, channel
		)
		if channel_img == null:
			_record_skip(result, channel, "a supplied texture could not be read")
			continue
		var channel_tex := ImageTexture.create_from_image(channel_img)
		_apply_channel(result.atlas_material, channel, channel_tex, suppliers[0])
		result.atlased_channels.append(channel)


## Record a slot the atlas cannot carry, and say so in the editor log. The whole
## point of #24 was that these were vanishing silently.
static func _record_skip(result: AtlasResult, channel: String, reason: String) -> void:
	result.skipped_channels[channel] = reason
	(
		HFLog
		. warn(
			(
				"HammerForge: material atlas dropped the %s channel — %s. That slot renders from the atlas material's scalar instead."
				% [channel, reason]
			)
		)
	)


## The texture a material supplies for `channel`, or null when it supplies none.
## A disabled feature counts as supplying nothing.
static func _channel_texture(key, channel: String) -> Texture2D:
	if not (key is StandardMaterial3D):
		return null
	var std: StandardMaterial3D = key
	match channel:
		CHANNEL_NORMAL:
			return std.normal_texture if std.normal_enabled else null
		CHANNEL_ROUGHNESS:
			return std.roughness_texture
		CHANNEL_METALLIC:
			return std.metallic_texture
		CHANNEL_EMISSION:
			return std.emission_texture if std.emission_enabled else null
	return null


## The constant tile a material without a texture for `channel` contributes.
##
## Scalars are written to every colour channel so the tile reads the same value
## through whichever `TextureChannel` selector the atlas material ends up using.
static func _channel_neutral(key, channel: String) -> Color:
	if not (key is StandardMaterial3D):
		return _default_neutral(channel)
	var std: StandardMaterial3D = key
	match channel:
		CHANNEL_NORMAL:
			return FLAT_NORMAL
		CHANNEL_ROUGHNESS:
			return Color(std.roughness, std.roughness, std.roughness, 1.0)
		CHANNEL_METALLIC:
			return Color(std.metallic, std.metallic, std.metallic, 1.0)
		CHANNEL_EMISSION:
			if not std.emission_enabled:
				return Color(0, 0, 0, 1)
			var lit: Color = std.emission * std.emission_energy_multiplier
			return Color(minf(lit.r, 1.0), minf(lit.g, 1.0), minf(lit.b, 1.0), 1.0)
	return _default_neutral(channel)


static func _default_neutral(channel: String) -> Color:
	if channel == CHANNEL_NORMAL:
		return FLAT_NORMAL
	return Color(0, 0, 0, 1)


## Why `channel` cannot be atlased, or "" when it can.
##
## The atlas material holds one multiplier and one `TextureChannel` selector for
## the whole atlas, so every material supplying a texture has to agree on them.
## Materials supplying no texture contribute a constant tile, which only survives
## intact when that shared multiplier is the identity.
static func _channel_blocker(tiles: Array, suppliers: Array, channel: String) -> String:
	var has_untextured: bool = tiles.size() > suppliers.size()
	var first: StandardMaterial3D = suppliers[0]
	match channel:
		CHANNEL_NORMAL:
			for mat in suppliers:
				if not is_equal_approx(mat.normal_scale, first.normal_scale):
					return "materials disagree on normal_scale"
			return ""
		CHANNEL_ROUGHNESS:
			for mat in suppliers:
				if mat.roughness_texture_channel != first.roughness_texture_channel:
					return "materials disagree on roughness_texture_channel"
				if absf(mat.roughness - first.roughness) > SCALAR_EPSILON:
					return "materials disagree on the roughness multiplier"
			if has_untextured and absf(first.roughness - 1.0) > SCALAR_EPSILON:
				return "roughness multiplier is not 1.0 and untextured materials are packed"
			return ""
		CHANNEL_METALLIC:
			for mat in suppliers:
				if mat.metallic_texture_channel != first.metallic_texture_channel:
					return "materials disagree on metallic_texture_channel"
				if absf(mat.metallic - first.metallic) > SCALAR_EPSILON:
					return "materials disagree on the metallic multiplier"
			if has_untextured and absf(first.metallic - 1.0) > SCALAR_EPSILON:
				return "metallic multiplier is not 1.0 and untextured materials are packed"
			return ""
		CHANNEL_EMISSION:
			for mat in suppliers:
				if not mat.emission.is_equal_approx(first.emission):
					return "materials disagree on the emission colour"
				var delta: float = absf(
					mat.emission_energy_multiplier - first.emission_energy_multiplier
				)
				if delta > SCALAR_EPSILON:
					return "materials disagree on emission_energy_multiplier"
				if mat.emission_operator != first.emission_operator:
					return "materials disagree on emission_operator"
			if _has_untextured_emitter(tiles, suppliers):
				if not first.emission.is_equal_approx(_emission_identity(first.emission_operator)):
					return "an untextured emitter is packed and the emission tint is not neutral"
				if absf(first.emission_energy_multiplier - 1.0) > SCALAR_EPSILON:
					return "an untextured emitter is packed and emission energy is not 1.0"
			return ""
	return "unknown channel"


## The `emission` tint that leaves an emission map unchanged.
##
## Godot combines the tint with the texture per `emission_operator`: ADD does
## `emission + emission_texture`, so black is the neutral value (and is the
## engine default), while MULTIPLY needs white.
static func _emission_identity(operator: int) -> Color:
	if operator == BaseMaterial3D.EMISSION_OP_MULTIPLY:
		return Color.WHITE
	return Color.BLACK


## True when some packed material emits without supplying an emission map. Its
## tint has to survive as a flat tile, which only works when the atlas material's
## own emission is neutral.
static func _has_untextured_emitter(tiles: Array, suppliers: Array) -> bool:
	for tile in tiles:
		var key = tile["key"]
		if suppliers.has(key):
			continue
		if key is StandardMaterial3D and key.emission_enabled:
			return true
	return false


## Compose one PBR slot into an atlas mirroring the albedo placements.
static func _compose_channel_atlas(
	tiles: Array, placements: Array, atlas_w: int, atlas_h: int, channel: String
) -> Image:
	var atlas := Image.create(atlas_w, atlas_h, false, Image.FORMAT_RGBA8)
	atlas.fill(_default_neutral(channel))
	for i in range(tiles.size()):
		var tile = tiles[i]
		var pos = placements[i]
		var tw: int = tile["w"]
		var th: int = tile["h"]
		var src: Image = _channel_tile_image(tile["key"], channel, tw, th)
		if src == null:
			return null
		var content_x: int = pos["x"] + GUTTER
		var content_y: int = pos["y"] + GUTTER
		atlas.blit_rect(src, Rect2i(0, 0, tw, th), Vector2i(content_x, content_y))
		_fill_gutter(atlas, src, content_x, content_y, tw, th)
	return atlas


## The tile a material contributes to `channel`, resampled to the albedo tile
## size. Materials with no texture for the slot get a constant fill.
##
## Returns null when a material *does* supply a texture that cannot be read, so
## the caller drops the whole slot rather than quietly substituting a flat tile
## and shipping a bake that looks subtly wrong.
static func _channel_tile_image(key, channel: String, tw: int, th: int) -> Image:
	var tex: Texture2D = _channel_texture(key, channel)
	if tex == null:
		var flat := Image.create(tw, th, false, Image.FORMAT_RGBA8)
		flat.fill(_channel_neutral(key, channel))
		return flat
	var source: Image = tex.get_image()
	if source == null or source.is_empty():
		return null
	var img: Image = source.duplicate() as Image
	if img.is_compressed() and img.decompress() != OK:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != tw or img.get_height() != th:
		# Data channels resample bilinearly: Lanczos ringing on a normal or
		# roughness map reads as banding rather than as sharpness.
		var mode: int = Image.INTERPOLATE_BILINEAR
		if channel == CHANNEL_EMISSION:
			mode = Image.INTERPOLATE_LANCZOS
		img.resize(tw, th, mode)
	return img


## Assign a finished channel atlas to the atlas material, carrying across the
## settings `_channel_blocker` verified every supplier agrees on.
static func _apply_channel(
	mat: StandardMaterial3D, channel: String, tex: Texture2D, sample: StandardMaterial3D
) -> void:
	match channel:
		CHANNEL_NORMAL:
			mat.normal_enabled = true
			mat.normal_texture = tex
			mat.normal_scale = sample.normal_scale
		CHANNEL_ROUGHNESS:
			mat.roughness_texture = tex
			mat.roughness_texture_channel = sample.roughness_texture_channel
			mat.roughness = sample.roughness
		CHANNEL_METALLIC:
			mat.metallic_texture = tex
			mat.metallic_texture_channel = sample.metallic_texture_channel
			mat.metallic = sample.metallic
		CHANNEL_EMISSION:
			mat.emission_enabled = true
			mat.emission_texture = tex
			mat.emission = sample.emission
			mat.emission_energy_multiplier = sample.emission_energy_multiplier
			mat.emission_operator = sample.emission_operator


## Fill the GUTTER-pixel border around a tile by copying its edge rows and
## columns outward. Prevents colour bleed from neighbouring tiles when mipmaps
## sample across a tile boundary.
##
## `tile` is the source image that was blitted at (cx, cy) — reading from it
## rather than from the atlas lets the whole border be copied with `blit_rect`
## and `fill_rect`. That is 4 * GUTTER + 4 native calls per tile instead of one
## `get_pixel` / `set_pixel` pair per gutter texel, which matters now that every
## PBR channel builds its own atlas.
static func _fill_gutter(atlas: Image, tile: Image, cx: int, cy: int, tw: int, th: int) -> void:
	if tw <= 0 or th <= 0:
		return
	var right: int = cx + tw - 1
	var bottom: int = cy + th - 1
	for g in range(1, GUTTER + 1):
		atlas.blit_rect(tile, Rect2i(0, 0, tw, 1), Vector2i(cx, cy - g))
		atlas.blit_rect(tile, Rect2i(0, th - 1, tw, 1), Vector2i(cx, bottom + g))
		atlas.blit_rect(tile, Rect2i(0, 0, 1, th), Vector2i(cx - g, cy))
		atlas.blit_rect(tile, Rect2i(tw - 1, 0, 1, th), Vector2i(right + g, cy))
	# Corners take the nearest tile corner texel, matching the clamped sampling
	# the previous per-texel implementation used.
	atlas.fill_rect(Rect2i(cx - GUTTER, cy - GUTTER, GUTTER, GUTTER), tile.get_pixel(0, 0))
	atlas.fill_rect(Rect2i(right + 1, cy - GUTTER, GUTTER, GUTTER), tile.get_pixel(tw - 1, 0))
	atlas.fill_rect(Rect2i(cx - GUTTER, bottom + 1, GUTTER, GUTTER), tile.get_pixel(0, th - 1))
	atlas.fill_rect(Rect2i(right + 1, bottom + 1, GUTTER, GUTTER), tile.get_pixel(tw - 1, th - 1))


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
