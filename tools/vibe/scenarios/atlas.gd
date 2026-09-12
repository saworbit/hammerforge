@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## `HFMaterialAtlas.build_atlas()` -- the pass that collapses a level's
## materials into one texture so the bake can draw it in one call.
##
## It is a packer, so the interesting input is the one that does not fit. A
## level with a lot of large textures is the ordinary way to get there, and what
## a packer does when it runs out of room is the part nobody exercises.

const Atlas = preload("res://addons/hammerforge/hf_material_atlas.gd")


func id() -> String:
	return "atlas"


func summary() -> String:
	return "the material atlas packer at its size limits, and what a failed pack does to the caller"


func run() -> void:
	await _an_ordinary_pack()
	await _more_texture_than_the_atlas_can_hold()


func _material(size: int, colour: Color) -> StandardMaterial3D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	return mat


func _an_ordinary_pack() -> void:
	var keys: Array = []
	for i in range(6):
		keys.append(_material(128, Color(float(i) / 6.0, 0.4, 0.6)))
	var result = Atlas.build_atlas(keys)
	note("atlased", result.atlased_keys.size())
	note("fallbacks", result.fallback_keys.size())
	var tex: Texture2D = result.atlas_material.albedo_texture if result.atlas_material else null
	note("atlas texture size", tex.get_size() if tex else "none")
	var bad := 0
	for key in result.rects:
		var rect: Rect2 = result.rects[key]
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			bad += 1
		if rect.position.x < 0.0 or rect.end.x > 1.0 or rect.end.y > 1.0:
			bad += 1
	note("rects outside 0-1 or with no area", bad)
	if bad > 0:
		flag("the atlas produced a UV rect that is not inside the atlas", bad)


## Twenty 2048-pixel textures. Each one is clamped to half the maximum atlas
## side, so they are legal tiles; twenty of them are 84 million pixels against
## the 16 million a 4096 atlas holds.
func _more_texture_than_the_atlas_can_hold() -> void:
	var keys: Array = []
	for i in range(20):
		keys.append(_material(2048, Color(float(i) / 20.0, 0.2, 0.2)))
	var result = Atlas.build_atlas(keys)
	if result == null:
		known(
			416,
			"build_atlas() does not survive a pack that does not fit",
			"the call returned nothing at all for 20 two-thousand-pixel textures"
		)
		return
	note("atlased", result.atlased_keys.size())
	note("fallbacks", result.fallback_keys.size())
	var tex: Texture2D = result.atlas_material.albedo_texture if result.atlas_material else null
	note("atlas texture", tex.get_size() if tex else "none")
	if result.atlased_keys.size() < keys.size() and result.fallback_keys.size() == 0:
		known(
			416,
			"a pack that does not fit loses materials without reporting them",
			(
				"_shelf_pack() returns {success: false, width: 0, height: 0, placements: []}"
				+ " when nothing fits at MAX_ATLAS_SIZE, and build_atlas() never looks at"
				+ " `success`: it builds a 0x0 Image, indexes an empty placements array and"
				+ (
					" divides by a zero width. %d of %d materials came back atlased and %d as"
					% [result.atlased_keys.size(), keys.size(), result.fallback_keys.size()]
				)
				+ " fallbacks, so the bake is told the pack worked."
			)
		)
	var bad := 0
	for key in result.rects:
		var rect: Rect2 = result.rects[key]
		if not (
			is_finite(rect.position.x)
			and is_finite(rect.position.y)
			and is_finite(rect.size.x)
			and is_finite(rect.size.y)
		):
			bad += 1
	note("non-finite UV rects", bad)
	if bad > 0:
		known(
			416,
			"a failed atlas pack writes non-finite UV rects",
			(
				"the atlas width comes back 0 and `1.0 / float(atlas_w)` is inf, so every rect"
				+ (
					" built from it is inf or NaN: %d of %d. Those are the UVs the baked mesh gets."
					% [bad, result.rects.size()]
				)
			)
		)
