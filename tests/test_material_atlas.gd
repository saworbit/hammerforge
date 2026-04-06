extends GutTest

const HFMaterialAtlasScript = preload("res://addons/hammerforge/hf_material_atlas.gd")
const BakerScript = preload("res://addons/hammerforge/baker.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const MatMgrScript = preload("res://addons/hammerforge/material_manager.gd")

var baker: BakerScript


func before_each():
	baker = BakerScript.new()
	add_child_autoqfree(baker)


# ===========================================================================
# HFMaterialAtlas unit tests
# ===========================================================================


func _make_textured_material(color: Color, size: int = 64) -> StandardMaterial3D:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex = ImageTexture.create_from_image(img)
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = color
	return mat


func _make_untextured_material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func test_build_atlas_empty_keys():
	var result = HFMaterialAtlasScript.build_atlas([])
	assert_not_null(result)
	assert_null(result.atlas_material, "Empty input should produce no atlas")
	assert_eq(result.atlased_keys.size(), 0)


func test_build_atlas_single_textured_material():
	var mat = _make_textured_material(Color.RED)
	var result = HFMaterialAtlasScript.build_atlas([mat])
	assert_not_null(result)
	assert_eq(result.atlased_keys.size(), 1)
	assert_not_null(result.atlas_material)
	assert_not_null(result.atlas_material.albedo_texture)
	assert_true(result.rects.has(mat), "Rect should exist for the material")


func test_build_atlas_two_textured_materials():
	var mat_a = _make_textured_material(Color.RED)
	var mat_b = _make_textured_material(Color.BLUE)
	var result = HFMaterialAtlasScript.build_atlas([mat_a, mat_b])
	assert_eq(result.atlased_keys.size(), 2)
	assert_not_null(result.atlas_material)
	# Both materials should have non-overlapping rects.
	var rect_a: Rect2 = result.rects[mat_a]
	var rect_b: Rect2 = result.rects[mat_b]
	assert_false(
		rect_a.intersects(rect_b), "Atlas rects should not overlap: %s vs %s" % [rect_a, rect_b]
	)


func test_build_atlas_untextured_goes_to_fallback():
	var tex_mat = _make_textured_material(Color.RED)
	var plain_mat = _make_untextured_material(Color.GREEN)
	var result = HFMaterialAtlasScript.build_atlas([tex_mat, plain_mat])
	assert_eq(result.atlased_keys.size(), 1, "Only textured material should be atlased")
	assert_eq(result.fallback_keys.size(), 1, "Untextured material should be fallback")
	assert_eq(result.fallback_keys[0], plain_mat)


func test_build_atlas_string_key_goes_to_fallback():
	var result = HFMaterialAtlasScript.build_atlas(["_default"])
	assert_eq(result.atlased_keys.size(), 0)
	assert_eq(result.fallback_keys.size(), 1)


func test_build_atlas_different_texture_sizes():
	var mat_small = _make_textured_material(Color.RED, 32)
	var mat_large = _make_textured_material(Color.BLUE, 128)
	var result = HFMaterialAtlasScript.build_atlas([mat_small, mat_large])
	assert_eq(result.atlased_keys.size(), 2)
	var rect_s: Rect2 = result.rects[mat_small]
	var rect_l: Rect2 = result.rects[mat_large]
	# Large texture rect should occupy more atlas area.
	assert_gt(rect_l.size.x * rect_l.size.y, rect_s.size.x * rect_s.size.y)


# ===========================================================================
# UV remapping
# ===========================================================================


func test_remap_uv_identity():
	# Full atlas rect [0,0,1,1] should pass UV through.
	var rect = Rect2(0, 0, 1, 1)
	var uv = Vector2(0.5, 0.5)
	var remapped = HFMaterialAtlasScript.remap_uv(uv, rect)
	assert_almost_eq(remapped.x, 0.5, 0.001)
	assert_almost_eq(remapped.y, 0.5, 0.001)


func test_remap_uv_sub_rect():
	# Material occupies bottom-left quarter — linear remap, no wrapping.
	var rect = Rect2(0, 0, 0.5, 0.5)
	var uv = Vector2(1.0, 1.0)
	var remapped = HFMaterialAtlasScript.remap_uv(uv, rect)
	# 0.0 + 1.0 * 0.5 = 0.5
	assert_almost_eq(remapped.x, 0.5, 0.001)
	assert_almost_eq(remapped.y, 0.5, 0.001)


func test_remap_uv_mid_sub_rect():
	# UV 0.5 inside a rect at offset 0.25 with size 0.5.
	var rect = Rect2(0.25, 0.25, 0.5, 0.5)
	var uv = Vector2(0.5, 0.5)
	var remapped = HFMaterialAtlasScript.remap_uv(uv, rect)
	# 0.25 + 0.5 * 0.5 = 0.5
	assert_almost_eq(remapped.x, 0.5, 0.001)
	assert_almost_eq(remapped.y, 0.5, 0.001)


# ===========================================================================
# Shelf packing
# ===========================================================================


func test_shelf_pack_single_tile():
	var tiles = [{"key": "a", "image": null, "w": 64, "h": 64}]
	var result = HFMaterialAtlasScript._shelf_pack(tiles)
	assert_true(result["success"])
	assert_gte(result["width"], 64)
	assert_gte(result["height"], 64)
	assert_eq(result["placements"].size(), 1)
	assert_eq(result["placements"][0]["x"], 0)
	assert_eq(result["placements"][0]["y"], 0)


func test_shelf_pack_two_tiles():
	var tiles = [
		{"key": "a", "image": null, "w": 64, "h": 64},
		{"key": "b", "image": null, "w": 64, "h": 64},
	]
	var result = HFMaterialAtlasScript._shelf_pack(tiles)
	assert_true(result["success"])
	assert_eq(result["placements"].size(), 2)
	# Tiles should not overlap.
	var p0 = result["placements"][0]
	var p1 = result["placements"][1]
	var r0 = Rect2i(p0["x"], p0["y"], 64, 64)
	var r1 = Rect2i(p1["x"], p1["y"], 64, 64)
	assert_false(Rect2(r0).intersects(Rect2(r1)), "Placements should not overlap")


func test_shelf_pack_power_of_two_height():
	var tiles = [{"key": "a", "image": null, "w": 100, "h": 100}]
	var result = HFMaterialAtlasScript._shelf_pack(tiles)
	assert_true(result["success"])
	# Height should be power of 2.
	var h: int = result["height"]
	assert_eq(h & (h - 1), 0, "Height %d should be power of 2" % h)


# ===========================================================================
# next_power_of_2
# ===========================================================================


func test_next_power_of_2():
	assert_eq(HFMaterialAtlasScript._next_power_of_2(0), 1)
	assert_eq(HFMaterialAtlasScript._next_power_of_2(1), 1)
	assert_eq(HFMaterialAtlasScript._next_power_of_2(2), 2)
	assert_eq(HFMaterialAtlasScript._next_power_of_2(3), 4)
	assert_eq(HFMaterialAtlasScript._next_power_of_2(5), 8)
	assert_eq(HFMaterialAtlasScript._next_power_of_2(127), 128)
	assert_eq(HFMaterialAtlasScript._next_power_of_2(128), 128)
	assert_eq(HFMaterialAtlasScript._next_power_of_2(129), 256)


# ===========================================================================
# Baker integration: bake_from_faces with atlas
# ===========================================================================


func _make_face(norm: Vector3 = Vector3.UP, mat_idx: int = 0) -> FaceData:
	var face = FaceData.new()
	face.normal = norm
	face.material_idx = mat_idx
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
	)
	return face


func _make_brush_with_faces(
	parent: Node3D, face_list: Array, mat_override: Material = null
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = Vector3(4, 4, 4)
	if mat_override:
		b.material_override = mat_override
	parent.add_child(b)
	b.global_position = Vector3.ZERO
	var typed: Array[FaceData] = []
	for f in face_list:
		typed.append(f)
	b.faces = typed
	b.geometry_dirty = false
	return b


func test_atlas_bake_reduces_surfaces():
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var mat_a = _make_textured_material(Color.RED)
	var mat_b = _make_textured_material(Color.BLUE)
	mat_mgr.add_material(mat_a)
	mat_mgr.add_material(mat_b)

	var parent = Node3D.new()
	add_child_autoqfree(parent)
	var face_a = _make_face(Vector3.UP, 0)
	var face_b = _make_face(Vector3.DOWN, 1)
	var brush = _make_brush_with_faces(parent, [face_a, face_b])

	# Without atlas: 2 surfaces.
	var result_no_atlas = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {})
	assert_not_null(result_no_atlas)
	add_child_autoqfree(result_no_atlas)
	var mi_no: MeshInstance3D = null
	for child in result_no_atlas.get_children():
		if child is MeshInstance3D:
			mi_no = child
	assert_not_null(mi_no)
	assert_eq(mi_no.mesh.get_surface_count(), 2, "Without atlas: two surfaces")

	# With atlas: 1 surface.
	var result_atlas = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {"use_atlas": true})
	assert_not_null(result_atlas)
	add_child_autoqfree(result_atlas)
	var mi_at: MeshInstance3D = null
	for child in result_atlas.get_children():
		if child is MeshInstance3D:
			mi_at = child
	assert_not_null(mi_at)
	assert_eq(mi_at.mesh.get_surface_count(), 1, "With atlas: single surface")
	# Vertex count should be same total.
	var verts_no: int = 0
	for s in range(mi_no.mesh.get_surface_count()):
		var arrays = mi_no.mesh.surface_get_arrays(s)
		verts_no += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var arrays_at = mi_at.mesh.surface_get_arrays(0)
	var verts_at: int = (arrays_at[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_eq(verts_at, verts_no, "Atlas mesh should have same total vertex count")


func test_atlas_bake_mixed_textured_and_plain():
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var mat_tex = _make_textured_material(Color.RED)
	var mat_plain = _make_untextured_material(Color.GREEN)
	mat_mgr.add_material(mat_tex)
	mat_mgr.add_material(mat_plain)

	var parent = Node3D.new()
	add_child_autoqfree(parent)
	var face_a = _make_face(Vector3.UP, 0)
	var face_b = _make_face(Vector3.DOWN, 1)
	var brush = _make_brush_with_faces(parent, [face_a, face_b])

	# With atlas but only one textured material: atlas not worth it (< 2 atlasable).
	# Both groups should remain as separate surfaces.
	var result = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {"use_atlas": true})
	assert_not_null(result)
	add_child_autoqfree(result)
	var mi: MeshInstance3D = null
	for child in result.get_children():
		if child is MeshInstance3D:
			mi = child
	assert_not_null(mi)
	assert_eq(
		mi.mesh.get_surface_count(), 2, "One textured + one plain = atlas skipped, two surfaces"
	)


func test_atlas_bake_three_textured_one_plain():
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var mat_a = _make_textured_material(Color.RED)
	var mat_b = _make_textured_material(Color.BLUE)
	var mat_c = _make_textured_material(Color.GREEN)
	var mat_plain = _make_untextured_material(Color.WHITE)
	mat_mgr.add_material(mat_a)
	mat_mgr.add_material(mat_b)
	mat_mgr.add_material(mat_c)
	mat_mgr.add_material(mat_plain)

	var parent = Node3D.new()
	add_child_autoqfree(parent)
	var faces: Array = [
		_make_face(Vector3.UP, 0),
		_make_face(Vector3.DOWN, 1),
		_make_face(Vector3.LEFT, 2),
		_make_face(Vector3.RIGHT, 3),
	]
	var brush = _make_brush_with_faces(parent, faces)

	var result = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {"use_atlas": true})
	assert_not_null(result)
	add_child_autoqfree(result)
	var mi: MeshInstance3D = null
	for child in result.get_children():
		if child is MeshInstance3D:
			mi = child
	assert_not_null(mi)
	# 3 textured atlas into 1 surface + 1 plain fallback = 2 surfaces total.
	assert_eq(mi.mesh.get_surface_count(), 2, "3 textured (atlased) + 1 plain = 2 surfaces")


func test_atlas_disabled_does_not_reduce():
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var mat_a = _make_textured_material(Color.RED)
	var mat_b = _make_textured_material(Color.BLUE)
	mat_mgr.add_material(mat_a)
	mat_mgr.add_material(mat_b)

	var parent = Node3D.new()
	add_child_autoqfree(parent)
	var brush = _make_brush_with_faces(
		parent,
		[
			_make_face(Vector3.UP, 0),
			_make_face(Vector3.DOWN, 1),
		]
	)

	var result = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {"use_atlas": false})
	assert_not_null(result)
	add_child_autoqfree(result)
	var mi: MeshInstance3D = null
	for child in result.get_children():
		if child is MeshInstance3D:
			mi = child
	assert_not_null(mi)
	assert_eq(mi.mesh.get_surface_count(), 2, "Atlas disabled: separate surfaces")


# ===========================================================================
# Tiling UV detection (group_has_tiling_uvs)
# ===========================================================================


func test_group_has_tiling_uvs_within_range():
	var uvs = PackedVector2Array([Vector2(0, 0), Vector2(0.5, 0.5), Vector2(1.0, 1.0)])
	assert_false(HFMaterialAtlasScript.group_has_tiling_uvs(uvs))


func test_group_has_tiling_uvs_exceeds_range():
	var uvs = PackedVector2Array([Vector2(0, 0), Vector2(2.0, 0.5)])
	assert_true(HFMaterialAtlasScript.group_has_tiling_uvs(uvs))


func test_group_has_tiling_uvs_negative():
	var uvs = PackedVector2Array([Vector2(-0.5, 0.5)])
	assert_true(HFMaterialAtlasScript.group_has_tiling_uvs(uvs))


func test_group_has_tiling_uvs_small_epsilon():
	# Just inside tolerance — should NOT flag as tiling.
	var uvs = PackedVector2Array([Vector2(1.005, -0.005)])
	assert_false(HFMaterialAtlasScript.group_has_tiling_uvs(uvs))


# ===========================================================================
# Exclude keys from atlas
# ===========================================================================


func test_build_atlas_exclude_keys():
	var mat_a = _make_textured_material(Color.RED)
	var mat_b = _make_textured_material(Color.BLUE)
	var excluded: Dictionary = {mat_a: true}
	var result = HFMaterialAtlasScript.build_atlas([mat_a, mat_b], excluded)
	assert_eq(result.atlased_keys.size(), 1, "Only non-excluded material atlased")
	assert_eq(result.fallback_keys.size(), 1, "Excluded material in fallback")
	assert_true(result.atlased_keys.has(mat_b))
	assert_true(result.fallback_keys.has(mat_a))


# ===========================================================================
# Gutter and UV inset
# ===========================================================================


func test_atlas_rects_are_inset():
	# Build atlas with known tile sizes; verify rects are inset from tile edges.
	var mat = _make_textured_material(Color.RED, 64)
	var result = HFMaterialAtlasScript.build_atlas([mat])
	assert_eq(result.atlased_keys.size(), 1)
	var rect: Rect2 = result.rects[mat]
	# With GUTTER=2 on a 64px tile in a 68px padded cell, the content starts at
	# pixel 2. The rect should be inset by half a texel beyond that, so
	# rect.position.x > 0 and rect.end.x < 1 (or < tile_extent).
	assert_gt(rect.position.x, 0.0, "Rect should be inset from left edge")
	assert_gt(rect.position.y, 0.0, "Rect should be inset from top edge")
	assert_lt(rect.end.x, 1.0, "Rect should be inset from right edge")
	assert_lt(rect.end.y, 1.0, "Rect should be inset from bottom edge")


func test_atlas_gutter_fills_edge_pixels():
	# Verify that gutter pixels around a tile contain the edge color.
	var img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var tex = ImageTexture.create_from_image(img)
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	var result = HFMaterialAtlasScript.build_atlas([mat])
	assert_not_null(result.atlas_material)
	var atlas_tex: ImageTexture = result.atlas_material.albedo_texture
	var atlas_img: Image = atlas_tex.get_image()
	# The tile is at GUTTER offset. Pixel at (GUTTER-1, GUTTER) should be the
	# edge color extended into the left gutter.
	var gutter: int = HFMaterialAtlasScript.GUTTER
	var gutter_pixel: Color = atlas_img.get_pixel(gutter - 1, gutter)
	var content_pixel: Color = atlas_img.get_pixel(gutter, gutter)
	assert_almost_eq(gutter_pixel.r, content_pixel.r, 0.01, "Gutter should match edge color")
	assert_almost_eq(gutter_pixel.g, content_pixel.g, 0.01)
	assert_almost_eq(gutter_pixel.b, content_pixel.b, 0.01)


# ===========================================================================
# Tiled-face bake integration: faces with UV scale > 1 stay separate
# ===========================================================================


func _make_tiled_face(norm: Vector3, mat_idx: int, scale: Vector2) -> FaceData:
	var face = FaceData.new()
	face.normal = norm
	face.material_idx = mat_idx
	face.uv_scale = scale
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
	)
	return face


func test_atlas_bake_excludes_tiling_faces():
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var mat_a = _make_textured_material(Color.RED)
	var mat_b = _make_textured_material(Color.BLUE)
	mat_mgr.add_material(mat_a)
	mat_mgr.add_material(mat_b)

	var parent = Node3D.new()
	add_child_autoqfree(parent)
	# face_a: normal UVs (scale 1), face_b: tiled UVs (scale 3 = UVs span 0..3).
	var face_a = _make_face(Vector3.UP, 0)
	var face_b = _make_tiled_face(Vector3.DOWN, 1, Vector2(3, 3))
	var brush = _make_brush_with_faces(parent, [face_a, face_b])

	var result = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {"use_atlas": true})
	assert_not_null(result)
	add_child_autoqfree(result)
	var mi: MeshInstance3D = null
	for child in result.get_children():
		if child is MeshInstance3D:
			mi = child
	assert_not_null(mi)
	# mat_b tiles, so only 1 atlasable material — atlas is skipped (< 2).
	# Both surfaces stay separate.
	assert_eq(
		mi.mesh.get_surface_count(),
		2,
		"Tiling material excluded from atlas, stays as separate surface"
	)


func test_atlas_bake_tiled_face_preserves_uv_range():
	# A face with UV scale 2 should produce vertex UVs spanning 0..2 in the baked mesh.
	# This validates that tiling UVs are NOT clamped or wrapped.
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var mat = _make_textured_material(Color.RED)
	mat_mgr.add_material(mat)

	var parent = Node3D.new()
	add_child_autoqfree(parent)
	var face = _make_tiled_face(Vector3.UP, 0, Vector2(2, 2))
	var brush = _make_brush_with_faces(parent, [face])

	# Even with atlas enabled, a single material won't atlas (< 2).
	# The UVs should pass through unmodified.
	var result = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {"use_atlas": true})
	assert_not_null(result)
	add_child_autoqfree(result)
	var mi: MeshInstance3D = null
	for child in result.get_children():
		if child is MeshInstance3D:
			mi = child
	assert_not_null(mi)
	var arrays = mi.mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	# With scale 2 on a unit quad, max UV should be ~2.0.
	var max_u: float = 0.0
	for uv in uvs:
		max_u = maxf(max_u, uv.x)
	assert_gt(max_u, 1.5, "Tiled UVs should exceed 1.0, got %f" % max_u)


# ===========================================================================
# Small-tile inset clamp (1px texture must not collapse to zero-size rect)
# ===========================================================================


func _make_textured_material_sized(color: Color, w: int, h: int) -> StandardMaterial3D:
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex = ImageTexture.create_from_image(img)
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = color
	return mat


func test_atlas_rect_nonzero_for_1px_tile():
	var mat = _make_textured_material_sized(Color.RED, 1, 1)
	var result = HFMaterialAtlasScript.build_atlas([mat])
	assert_eq(result.atlased_keys.size(), 1)
	var rect: Rect2 = result.rects[mat]
	assert_gt(rect.size.x, 0.0, "1px tile rect width must be > 0, got %f" % rect.size.x)
	assert_gt(rect.size.y, 0.0, "1px tile rect height must be > 0, got %f" % rect.size.y)


func test_atlas_rect_nonzero_for_2px_tile():
	var mat = _make_textured_material_sized(Color.RED, 2, 2)
	var result = HFMaterialAtlasScript.build_atlas([mat])
	assert_eq(result.atlased_keys.size(), 1)
	var rect: Rect2 = result.rects[mat]
	assert_gt(rect.size.x, 0.0, "2px tile rect width must be > 0")
	assert_gt(rect.size.y, 0.0, "2px tile rect height must be > 0")


func test_atlas_1px_remap_produces_distinct_uvs():
	# A face with UVs at 0 and 1 remapped into a 1px tile rect must
	# produce two different atlas UVs, not the same collapsed point.
	var mat = _make_textured_material_sized(Color.RED, 1, 1)
	var result = HFMaterialAtlasScript.build_atlas([mat])
	var rect: Rect2 = result.rects[mat]
	var uv_a = HFMaterialAtlasScript.remap_uv(Vector2(0, 0), rect)
	var uv_b = HFMaterialAtlasScript.remap_uv(Vector2(1, 1), rect)
	var delta: float = (uv_b - uv_a).length()
	assert_gt(delta, 0.0001, "Remapped UVs on 1px tile must differ, delta=%f" % delta)


# ===========================================================================
# Per-face tiling split: non-tiled faces of a mixed material can atlas
# ===========================================================================


func test_atlas_bake_splits_tiling_faces_per_material():
	# Same material on two faces: one tiles (scale 3), one doesn't (scale 1).
	# A third material is fully non-tiling.
	# Expected: the non-tiling face of mat_a + mat_b atlas into 1 surface,
	# the tiling face of mat_a stays as a separate surface = 2 total.
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var mat_a = _make_textured_material(Color.RED)
	var mat_b = _make_textured_material(Color.BLUE)
	mat_mgr.add_material(mat_a)
	mat_mgr.add_material(mat_b)

	var parent = Node3D.new()
	add_child_autoqfree(parent)
	# face_1: mat_a, non-tiling
	var face_1 = _make_face(Vector3.UP, 0)
	# face_2: mat_a, tiling (scale 3)
	var face_2 = _make_tiled_face(Vector3.DOWN, 0, Vector2(3, 3))
	# face_3: mat_b, non-tiling
	var face_3 = _make_face(Vector3.LEFT, 1)
	var brush = _make_brush_with_faces(parent, [face_1, face_2, face_3])

	var result = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {"use_atlas": true})
	assert_not_null(result)
	add_child_autoqfree(result)
	var mi: MeshInstance3D = null
	for child in result.get_children():
		if child is MeshInstance3D:
			mi = child
	assert_not_null(mi)
	# non-tiling mat_a + mat_b = 1 atlas surface, tiling mat_a = 1 fallback = 2 total.
	assert_eq(
		mi.mesh.get_surface_count(),
		2,
		"Non-tiling faces atlas together, tiling face stays separate"
	)


func test_atlas_bake_all_tiling_same_material_no_atlas():
	# Every face of two materials tiles — nothing is atlasable, so we get
	# one surface per material key (tiling sub-groups for each).
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var mat_a = _make_textured_material(Color.RED)
	var mat_b = _make_textured_material(Color.BLUE)
	mat_mgr.add_material(mat_a)
	mat_mgr.add_material(mat_b)

	var parent = Node3D.new()
	add_child_autoqfree(parent)
	var face_a = _make_tiled_face(Vector3.UP, 0, Vector2(2, 2))
	var face_b = _make_tiled_face(Vector3.DOWN, 1, Vector2(4, 4))
	var brush = _make_brush_with_faces(parent, [face_a, face_b])

	var result = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {"use_atlas": true})
	assert_not_null(result)
	add_child_autoqfree(result)
	var mi: MeshInstance3D = null
	for child in result.get_children():
		if child is MeshInstance3D:
			mi = child
	assert_not_null(mi)
	assert_eq(mi.mesh.get_surface_count(), 2, "All tiling: no atlas possible, 2 separate surfaces")
