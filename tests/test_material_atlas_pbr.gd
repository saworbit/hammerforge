extends GutTest
## PBR channel packing in HFMaterialAtlas (issue #24).
##
## Before this, `build_atlas()` only inspected `albedo_texture`, so a material's
## normal / roughness / metallic / emission maps were dropped without a word.
## Each slot now gets a parallel atlas over the same placements, or a recorded
## reason in `AtlasResult.skipped_channels` when the per-material settings the
## atlas has to collapse into one value disagree.

const HFMaterialAtlasScript = preload("res://addons/hammerforge/hf_material_atlas.gd")

const TILE := 16

# ===========================================================================
# Fixtures
# ===========================================================================


func _solid_texture(color: Color, size: int = TILE) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## A material with an albedo map (the entry ticket for atlasing) and nothing else.
func _albedo_only(color: Color, size: int = TILE) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _solid_texture(color, size)
	return mat


func _atlas_image(result, slot: String) -> Image:
	var mat: StandardMaterial3D = result.atlas_material
	var tex: Texture2D = null
	match slot:
		"albedo":
			tex = mat.albedo_texture
		HFMaterialAtlasScript.CHANNEL_NORMAL:
			tex = mat.normal_texture
		HFMaterialAtlasScript.CHANNEL_ROUGHNESS:
			tex = mat.roughness_texture
		HFMaterialAtlasScript.CHANNEL_METALLIC:
			tex = mat.metallic_texture
		HFMaterialAtlasScript.CHANNEL_EMISSION:
			tex = mat.emission_texture
	if tex == null:
		return null
	return tex.get_image()


## Build an atlas that is expected to drop a slot, suppressing the warning the
## drop emits so the suite output stays clean. Returns {result, warnings}.
func _build_expecting_skip(keys: Array) -> Dictionary:
	HFLog.begin_test_capture(["material atlas dropped"])
	var result = HFMaterialAtlasScript.build_atlas(keys)
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	return {"result": result, "warnings": warnings}


## Centre texel of a material's tile in a channel atlas, read through its rect.
func _sample_tile(result, slot: String, mat: StandardMaterial3D) -> Color:
	var img: Image = _atlas_image(result, slot)
	assert_not_null(img, "%s atlas exists" % slot)
	if img == null:
		return Color.TRANSPARENT
	var rect: Rect2 = result.rects[mat]
	var centre := rect.position + rect.size * 0.5
	var x: int = clampi(int(centre.x * img.get_width()), 0, img.get_width() - 1)
	var y: int = clampi(int(centre.y * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(x, y)


# ===========================================================================
# No PBR maps: nothing extra is built
# ===========================================================================


func test_albedo_only_materials_produce_no_pbr_atlases():
	var a := _albedo_only(Color.RED)
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_eq(result.atlased_channels.size(), 0, "no PBR slot was packed")
	assert_eq(result.skipped_channels.size(), 0, "unused slots are not reported as skipped")
	assert_null(result.atlas_material.normal_texture, "no normal atlas")
	assert_null(result.atlas_material.roughness_texture, "no roughness atlas")
	assert_null(result.atlas_material.metallic_texture, "no metallic atlas")
	assert_null(result.atlas_material.emission_texture, "no emission atlas")


func test_albedo_atlas_still_built_alongside_pbr():
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_almost_eq(_sample_tile(result, "albedo", a).r, 1.0, 0.02, "tile A albedo is red")
	assert_almost_eq(_sample_tile(result, "albedo", b).b, 1.0, 0.02, "tile B albedo is blue")


# ===========================================================================
# Normal maps
# ===========================================================================


func test_normal_map_is_packed_and_assigned():
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_true(
		result.atlased_channels.has(HFMaterialAtlasScript.CHANNEL_NORMAL), "normal slot packed"
	)
	assert_true(result.atlas_material.normal_enabled, "normal mapping enabled on the atlas")
	var packed := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_NORMAL, a)
	assert_almost_eq(packed.r, 0.9, 0.03, "supplier tile keeps its normal X")
	assert_almost_eq(packed.g, 0.1, 0.03, "supplier tile keeps its normal Y")


func test_material_without_a_normal_map_gets_a_flat_tile():
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	var flat := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_NORMAL, b)
	assert_almost_eq(flat.r, 0.5, 0.02, "non-supplier tile is a flat normal in X")
	assert_almost_eq(flat.g, 0.5, 0.02, "non-supplier tile is a flat normal in Y")


func test_normal_scale_is_carried_across():
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	a.normal_scale = 0.4
	var b := _albedo_only(Color.BLUE)
	b.normal_enabled = true
	b.normal_texture = _solid_texture(Color(0.2, 0.8, 1.0, 1.0))
	b.normal_scale = 0.4
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_almost_eq(result.atlas_material.normal_scale, 0.4, 0.001, "shared normal_scale kept")


func test_conflicting_normal_scale_skips_the_channel_with_a_reason():
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	a.normal_scale = 1.0
	var b := _albedo_only(Color.BLUE)
	b.normal_enabled = true
	b.normal_texture = _solid_texture(Color(0.2, 0.8, 1.0, 1.0))
	b.normal_scale = 0.25
	var result = _build_expecting_skip([a, b])["result"]
	assert_false(
		result.atlased_channels.has(HFMaterialAtlasScript.CHANNEL_NORMAL), "normal not packed"
	)
	var reason: String = result.skipped_channels.get(HFMaterialAtlasScript.CHANNEL_NORMAL, "")
	assert_string_contains(reason, "normal_scale", "the reason names the conflicting property")


func test_disabled_normal_mapping_is_not_treated_as_a_supplier():
	var a := _albedo_only(Color.RED)
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	a.normal_enabled = false
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_eq(result.atlased_channels.size(), 0, "a disabled feature supplies nothing")
	assert_null(result.atlas_material.normal_texture, "no normal atlas built")


# ===========================================================================
# Roughness and metallic
# ===========================================================================


func test_roughness_map_is_packed():
	var a := _albedo_only(Color.RED)
	a.roughness_texture = _solid_texture(Color(0.2, 0.2, 0.2, 1.0))
	var b := _albedo_only(Color.BLUE)
	b.roughness = 0.75
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_true(
		result.atlased_channels.has(HFMaterialAtlasScript.CHANNEL_ROUGHNESS), "roughness packed"
	)
	var supplied := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_ROUGHNESS, a)
	assert_almost_eq(supplied.r, 0.2, 0.03, "supplier tile keeps its roughness map")
	var scalar := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_ROUGHNESS, b)
	assert_almost_eq(scalar.r, 0.75, 0.03, "non-supplier tile encodes its roughness scalar")


func test_scalar_tiles_are_written_to_every_colour_channel():
	# The atlas material carries one TextureChannel selector; a constant tile has
	# to read the same through any of them.
	var a := _albedo_only(Color.RED)
	a.roughness_texture = _solid_texture(Color(0.2, 0.2, 0.2, 1.0))
	a.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	var b := _albedo_only(Color.BLUE)
	b.roughness = 0.6
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	var scalar := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_ROUGHNESS, b)
	assert_almost_eq(scalar.r, 0.6, 0.03, "red carries the scalar")
	assert_almost_eq(scalar.g, 0.6, 0.03, "green carries the scalar")
	assert_almost_eq(scalar.b, 0.6, 0.03, "blue carries the scalar")


func test_roughness_texture_channel_is_carried_across():
	var a := _albedo_only(Color.RED)
	a.roughness_texture = _solid_texture(Color(0.2, 0.4, 0.6, 1.0))
	a.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_eq(
		result.atlas_material.roughness_texture_channel,
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN,
		"selector carried onto the atlas material"
	)


func test_conflicting_roughness_channel_skips_with_a_reason():
	var a := _albedo_only(Color.RED)
	a.roughness_texture = _solid_texture(Color(0.2, 0.2, 0.2, 1.0))
	a.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var b := _albedo_only(Color.BLUE)
	b.roughness_texture = _solid_texture(Color(0.8, 0.8, 0.8, 1.0))
	b.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	var result = _build_expecting_skip([a, b])["result"]
	assert_false(
		result.atlased_channels.has(HFMaterialAtlasScript.CHANNEL_ROUGHNESS), "roughness skipped"
	)
	var reason: String = result.skipped_channels.get(HFMaterialAtlasScript.CHANNEL_ROUGHNESS, "")
	assert_string_contains(reason, "roughness_texture_channel", "the reason names the conflict")


func test_non_identity_roughness_multiplier_skips_when_untextured_materials_are_packed():
	# The atlas holds one multiplier. A constant tile for the untextured material
	# would be scaled by it, so packing would silently change that material.
	var a := _albedo_only(Color.RED)
	a.roughness_texture = _solid_texture(Color(0.5, 0.5, 0.5, 1.0))
	a.roughness = 0.5
	var b := _albedo_only(Color.BLUE)
	var result = _build_expecting_skip([a, b])["result"]
	var reason: String = result.skipped_channels.get(HFMaterialAtlasScript.CHANNEL_ROUGHNESS, "")
	assert_string_contains(reason, "not 1.0", "the reason explains the multiplier constraint")


func test_non_identity_roughness_multiplier_is_fine_when_every_material_supplies_a_map():
	var a := _albedo_only(Color.RED)
	a.roughness_texture = _solid_texture(Color(0.5, 0.5, 0.5, 1.0))
	a.roughness = 0.5
	var b := _albedo_only(Color.BLUE)
	b.roughness_texture = _solid_texture(Color(0.9, 0.9, 0.9, 1.0))
	b.roughness = 0.5
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_true(
		result.atlased_channels.has(HFMaterialAtlasScript.CHANNEL_ROUGHNESS),
		"a shared multiplier is representable"
	)
	assert_almost_eq(result.atlas_material.roughness, 0.5, 0.001, "multiplier carried across")


func test_metallic_map_is_packed():
	var a := _albedo_only(Color.RED)
	a.metallic_texture = _solid_texture(Color(0.9, 0.9, 0.9, 1.0))
	a.metallic = 1.0
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_true(
		result.atlased_channels.has(HFMaterialAtlasScript.CHANNEL_METALLIC), "metallic packed"
	)
	var supplied := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_METALLIC, a)
	assert_almost_eq(supplied.r, 0.9, 0.03, "supplier tile keeps its metallic map")
	var scalar := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_METALLIC, b)
	assert_almost_eq(scalar.r, 0.0, 0.03, "a non-metallic material encodes 0")


func test_metallic_default_multiplier_of_zero_blocks_packing():
	# StandardMaterial3D.metallic defaults to 0, which would zero out the map.
	# Packing must not paper over that authoring mistake.
	var a := _albedo_only(Color.RED)
	a.metallic_texture = _solid_texture(Color(0.9, 0.9, 0.9, 1.0))
	var b := _albedo_only(Color.BLUE)
	var result = _build_expecting_skip([a, b])["result"]
	var reason: String = result.skipped_channels.get(HFMaterialAtlasScript.CHANNEL_METALLIC, "")
	assert_string_contains(reason, "not 1.0", "the zero multiplier is reported")


# ===========================================================================
# Emission
# ===========================================================================


func test_emission_map_is_packed():
	var a := _albedo_only(Color.RED)
	a.emission_enabled = true
	a.emission_texture = _solid_texture(Color(0.8, 0.4, 0.1, 1.0))
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_true(
		result.atlased_channels.has(HFMaterialAtlasScript.CHANNEL_EMISSION), "emission packed"
	)
	assert_true(result.atlas_material.emission_enabled, "emission enabled on the atlas")
	var supplied := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_EMISSION, a)
	assert_almost_eq(supplied.r, 0.8, 0.03, "supplier tile keeps its emission map")


func test_non_emitting_material_gets_a_black_tile():
	var a := _albedo_only(Color.RED)
	a.emission_enabled = true
	a.emission_texture = _solid_texture(Color(0.8, 0.4, 0.1, 1.0))
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	var dark := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_EMISSION, b)
	assert_almost_eq(dark.r, 0.0, 0.02, "a non-emitter stays black in red")
	assert_almost_eq(dark.g, 0.0, 0.02, "a non-emitter stays black in green")
	assert_almost_eq(dark.b, 0.0, 0.02, "a non-emitter stays black in blue")


func test_untextured_emitter_is_baked_into_its_tile():
	# The supplier leaves `emission` at Godot's default black, which is neutral
	# under the default ADD operator, so b's flat tint packs faithfully.
	var a := _albedo_only(Color.RED)
	a.emission_enabled = true
	a.emission_texture = _solid_texture(Color(0.8, 0.8, 0.8, 1.0))
	var b := _albedo_only(Color.BLUE)
	b.emission_enabled = true
	b.emission = Color(0.0, 0.5, 0.0)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_true(
		result.atlased_channels.has(HFMaterialAtlasScript.CHANNEL_EMISSION), "emission packed"
	)
	var tint := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_EMISSION, b)
	assert_almost_eq(tint.g, 0.5, 0.03, "the untextured emitter's tint lives in its tile")
	assert_almost_eq(tint.r, 0.0, 0.03, "and only in the channel it set")


func test_untextured_emitter_blocks_a_tinted_emission_atlas():
	# Under the default ADD operator the tint is added to the map, so anything
	# other than black would leak into the untextured emitter's flat tile.
	var a := _albedo_only(Color.RED)
	a.emission_enabled = true
	a.emission_texture = _solid_texture(Color(0.8, 0.8, 0.8, 1.0))
	a.emission = Color(1.0, 0.0, 0.0)
	var b := _albedo_only(Color.BLUE)
	b.emission_enabled = true
	b.emission = Color(0.0, 0.5, 0.0)
	var result = _build_expecting_skip([a, b])["result"]
	var reason: String = result.skipped_channels.get(HFMaterialAtlasScript.CHANNEL_EMISSION, "")
	assert_string_contains(reason, "tint", "the reason explains the tint conflict")


func test_multiply_operator_treats_white_as_the_neutral_tint():
	# EMISSION_OP_MULTIPLY multiplies tint by map, so white is the identity there
	# even though black is the identity for the default ADD operator.
	var a := _albedo_only(Color.RED)
	a.emission_enabled = true
	a.emission_texture = _solid_texture(Color(0.8, 0.8, 0.8, 1.0))
	a.emission = Color.WHITE
	a.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	var b := _albedo_only(Color.BLUE)
	b.emission_enabled = true
	b.emission = Color(0.0, 0.5, 0.0)
	b.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_true(
		result.atlased_channels.has(HFMaterialAtlasScript.CHANNEL_EMISSION),
		"a white tint is neutral under MULTIPLY"
	)
	assert_eq(
		result.atlas_material.emission_operator,
		BaseMaterial3D.EMISSION_OP_MULTIPLY,
		"the operator is carried across"
	)


func test_black_tint_blocks_a_multiply_emission_atlas():
	var a := _albedo_only(Color.RED)
	a.emission_enabled = true
	a.emission_texture = _solid_texture(Color(0.8, 0.8, 0.8, 1.0))
	a.emission = Color.BLACK
	a.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	var b := _albedo_only(Color.BLUE)
	b.emission_enabled = true
	b.emission = Color(0.0, 0.5, 0.0)
	b.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	var result = _build_expecting_skip([a, b])["result"]
	var reason: String = result.skipped_channels.get(HFMaterialAtlasScript.CHANNEL_EMISSION, "")
	assert_string_contains(reason, "tint", "black is not neutral under MULTIPLY")


func test_conflicting_emission_operator_skips_with_a_reason():
	var a := _albedo_only(Color.RED)
	a.emission_enabled = true
	a.emission_texture = _solid_texture(Color(0.8, 0.8, 0.8, 1.0))
	var b := _albedo_only(Color.BLUE)
	b.emission_enabled = true
	b.emission_texture = _solid_texture(Color(0.2, 0.2, 0.2, 1.0))
	b.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	var result = _build_expecting_skip([a, b])["result"]
	var reason: String = result.skipped_channels.get(HFMaterialAtlasScript.CHANNEL_EMISSION, "")
	assert_string_contains(reason, "emission_operator", "the reason names the conflict")


func test_conflicting_emission_energy_skips_with_a_reason():
	var a := _albedo_only(Color.RED)
	a.emission_enabled = true
	a.emission_texture = _solid_texture(Color(0.8, 0.8, 0.8, 1.0))
	a.emission_energy_multiplier = 1.0
	var b := _albedo_only(Color.BLUE)
	b.emission_enabled = true
	b.emission_texture = _solid_texture(Color(0.2, 0.2, 0.2, 1.0))
	b.emission_energy_multiplier = 4.0
	var result = _build_expecting_skip([a, b])["result"]
	var reason: String = result.skipped_channels.get(HFMaterialAtlasScript.CHANNEL_EMISSION, "")
	assert_string_contains(reason, "energy", "the reason names the conflicting property")


# ===========================================================================
# Layout, gutters and source handling
# ===========================================================================


func test_channel_atlases_share_the_albedo_layout():
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	var b := _albedo_only(Color.BLUE)
	b.normal_enabled = true
	b.normal_texture = _solid_texture(Color(0.2, 0.8, 1.0, 1.0))
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	var albedo: Image = _atlas_image(result, "albedo")
	var normal: Image = _atlas_image(result, HFMaterialAtlasScript.CHANNEL_NORMAL)
	assert_eq(normal.get_width(), albedo.get_width(), "same atlas width")
	assert_eq(normal.get_height(), albedo.get_height(), "same atlas height")
	# The same UV rect must address the same material in both atlases.
	assert_almost_eq(_sample_tile(result, "albedo", a).r, 1.0, 0.02, "A is red in albedo")
	var normal_a := _sample_tile(result, HFMaterialAtlasScript.CHANNEL_NORMAL, a)
	assert_almost_eq(normal_a.r, 0.9, 0.03, "and A's normal sits at the same rect")


func test_channel_atlas_gutter_extends_the_tile_edge():
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	var result = HFMaterialAtlasScript.build_atlas([a])
	var normal: Image = _atlas_image(result, HFMaterialAtlasScript.CHANNEL_NORMAL)
	var gutter: int = HFMaterialAtlasScript.GUTTER
	var edge := normal.get_pixel(gutter, gutter)
	assert_almost_eq(
		normal.get_pixel(gutter - 1, gutter).r, edge.r, 0.01, "left gutter matches the edge"
	)
	assert_almost_eq(
		normal.get_pixel(gutter, gutter - 1).r, edge.r, 0.01, "top gutter matches the edge"
	)
	assert_almost_eq(
		normal.get_pixel(gutter - 1, gutter - 1).r, edge.r, 0.01, "corner matches the edge"
	)


func test_pbr_source_of_a_different_size_is_resampled_to_the_tile():
	var a := _albedo_only(Color.RED, TILE)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0), TILE * 4)
	var b := _albedo_only(Color.BLUE, TILE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	var albedo: Image = _atlas_image(result, "albedo")
	var normal: Image = _atlas_image(result, HFMaterialAtlasScript.CHANNEL_NORMAL)
	assert_eq(normal.get_size(), albedo.get_size(), "oversized source did not grow the atlas")
	assert_almost_eq(
		_sample_tile(result, HFMaterialAtlasScript.CHANNEL_NORMAL, a).r,
		0.9,
		0.03,
		"the resampled normal still lands in the tile"
	)


func test_non_rgba8_pbr_source_is_converted():
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.0))
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = ImageTexture.create_from_image(img)
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_almost_eq(
		_sample_tile(result, HFMaterialAtlasScript.CHANNEL_NORMAL, a).r,
		0.9,
		0.03,
		"an RGB8 normal map is packed"
	)


func test_excluded_material_does_not_contribute_a_channel():
	# Tiling materials never reach the atlas, so their PBR maps must not either.
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	var b := _albedo_only(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([a, b], {a: true})
	assert_true(result.fallback_keys.has(a), "the excluded material fell back")
	assert_eq(result.atlased_channels.size(), 0, "its normal map did not build an atlas")


func test_string_material_keys_are_ignored_by_channel_detection():
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	var result = HFMaterialAtlasScript.build_atlas([a, "_default"])
	assert_true(result.fallback_keys.has("_default"), "the string key fell back")
	assert_true(
		result.atlased_channels.has(HFMaterialAtlasScript.CHANNEL_NORMAL),
		"the real material still packs its normal map"
	)


func test_multiple_channels_pack_together():
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = _solid_texture(Color(0.9, 0.1, 1.0, 1.0))
	a.roughness_texture = _solid_texture(Color(0.3, 0.3, 0.3, 1.0))
	a.metallic_texture = _solid_texture(Color(0.7, 0.7, 0.7, 1.0))
	a.metallic = 1.0
	a.emission_enabled = true
	a.emission_texture = _solid_texture(Color(0.6, 0.6, 0.6, 1.0))
	var b := _albedo_only(Color.BLUE)
	b.normal_enabled = true
	b.normal_texture = _solid_texture(Color(0.2, 0.8, 1.0, 1.0))
	b.roughness_texture = _solid_texture(Color(0.9, 0.9, 0.9, 1.0))
	b.metallic_texture = _solid_texture(Color(0.1, 0.1, 0.1, 1.0))
	b.metallic = 1.0
	b.emission_enabled = true
	b.emission_texture = _solid_texture(Color(0.2, 0.2, 0.2, 1.0))
	var result = HFMaterialAtlasScript.build_atlas([a, b])
	assert_eq(result.atlased_channels.size(), 4, "all four slots packed")
	assert_eq(result.skipped_channels.size(), 0, "nothing skipped")
	assert_almost_eq(
		_sample_tile(result, HFMaterialAtlasScript.CHANNEL_ROUGHNESS, b).r,
		0.9,
		0.03,
		"B keeps its roughness"
	)
	assert_almost_eq(
		_sample_tile(result, HFMaterialAtlasScript.CHANNEL_EMISSION, a).r,
		0.6,
		0.03,
		"A keeps its emission"
	)


func test_a_dropped_channel_is_reported_in_the_editor_log():
	# Recording the reason is only half the fix; #24 was about slots vanishing
	# with no word to the user.
	var a := _albedo_only(Color.RED)
	a.roughness_texture = _solid_texture(Color(0.2, 0.2, 0.2, 1.0))
	a.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var b := _albedo_only(Color.BLUE)
	b.roughness_texture = _solid_texture(Color(0.8, 0.8, 0.8, 1.0))
	b.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	var captured: Array = _build_expecting_skip([a, b])["warnings"]
	assert_eq(captured.size(), 1, "exactly one warning for one dropped slot")
	assert_string_contains(str(captured[0]), "roughness", "the warning names the slot")


func test_unreadable_supplied_texture_drops_the_slot():
	# A texture that yields no image is a real failure. Substituting a flat tile
	# would ship a bake that looks subtly wrong, so the whole slot is dropped.
	var a := _albedo_only(Color.RED)
	a.normal_enabled = true
	a.normal_texture = PlaceholderTexture2D.new()
	var b := _albedo_only(Color.BLUE)
	var bundle := _build_expecting_skip([a, b])
	var result = bundle["result"]
	assert_null(result.atlas_material.normal_texture, "no normal atlas was assigned")
	var reason: String = result.skipped_channels.get(HFMaterialAtlasScript.CHANNEL_NORMAL, "")
	assert_string_contains(reason, "could not be read", "the reason explains the failure")
	assert_almost_eq(
		_sample_tile(result, "albedo", a).r, 1.0, 0.02, "albedo still atlases normally"
	)
