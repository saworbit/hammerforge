extends GutTest

## Two bake switches that reached the baker intact and produced nothing, with no
## feedback in between: **Generate LODs** (#611) and **Use atlas** (#623).

const BakerScript = preload("res://addons/hammerforge/baker.gd")
const HFMaterialAtlas = preload("res://addons/hammerforge/hf_material_atlas.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")

var baker


func before_each():
	baker = BakerScript.new()
	add_child_autoqfree(baker)
	HFLog.end_test_capture()


func after_each():
	HFLog.end_test_capture()


## A triangle soup: every corner a loose vertex and no index array, which is what
## the CSG merge path hands the finishing pass. Built by de-indexing a sphere,
## because a simplifier is required to keep border edges and an open sheet is all
## border - a closed solid is what a bake actually produces.
func _soup_mesh(with_uv2: bool = false) -> ArrayMesh:
	var source := SphereMesh.new()
	source.radial_segments = 32
	source.rings = 16
	var arrays: Array = source.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in indices:
		st.set_normal(normals[i])
		st.set_uv(uvs[i])
		if with_uv2:
			st.set_uv2(uvs[i] * 0.5)
		st.add_vertex(verts[i])
	return st.commit()


func _index_count(mesh: ArrayMesh, surface: int = 0) -> int:
	var idx = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
	return (idx as PackedInt32Array).size() if idx is PackedInt32Array else 0


# ===========================================================================
# Generate LODs (#611)
# ===========================================================================


func test_an_unindexed_surface_gets_lods_now():
	var mesh := _soup_mesh()
	assert_eq(_index_count(mesh), 0, "the input really is a triangle soup")
	var out: ArrayMesh = baker._mesh_with_lods(mesh)
	var importer := ImporterMesh.from_mesh(out)
	assert_gt(
		importer.get_surface_lod_count(0),
		0,
		"the simplifier had nothing to collapse while the surface had no indices"
	)


func test_indexing_the_surface_also_shrinks_it():
	var mesh := _soup_mesh()
	var before: int = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var out: ArrayMesh = baker._mesh_with_lods(mesh)
	var after: int = out.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	assert_lt(after, before, "welding the duplicated corners is worth doing on its own")
	assert_gt(_index_count(out), 0)


func test_an_already_indexed_surface_is_handed_back_untouched():
	var st := SurfaceTool.new()
	st.create_from(_soup_mesh(), 0)
	st.index()
	var indexed: ArrayMesh = st.commit()
	var before_verts: int = indexed.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var out: ArrayMesh = baker._indexed(indexed)
	assert_eq(out, indexed, "nothing that already works goes through SurfaceTool a second time")
	assert_eq(out.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), before_verts)


func test_indexing_keeps_the_surface_material():
	var mesh := _soup_mesh()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.RED
	mesh.surface_set_material(0, material)
	var out: ArrayMesh = baker._indexed(mesh)
	assert_eq(out.surface_get_material(0), material, "the face materials have to survive")


func test_indexing_keeps_a_lightmap_uv2():
	# The finishing pass unwraps UV2 before it generates LODs, so the indexing step
	# sits between them and must not drop what the unwrap just produced.
	var mesh := _soup_mesh(true)
	var out: ArrayMesh = baker._indexed(mesh)
	var uv2 = out.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	assert_true(uv2 is PackedVector2Array and (uv2 as PackedVector2Array).size() > 0)


# ===========================================================================
# Use atlas (#623)
# ===========================================================================


func _group(material: Material, tiling: bool) -> Dictionary:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var span := 64.0 if tiling else 1.0
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]:
		verts.append(Vector3(corner.x, 0, corner.y))
		uvs.append(corner * span)
		normals.append(Vector3.UP)
	return {"material": material, "verts": verts, "uvs": uvs, "normals": normals, "tiling": tiling}


func _groups(count: int, tiling: bool) -> Dictionary:
	var out: Dictionary = {}
	for i in count:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(float(i) / float(count), 0.5, 0.5)
		out[m] = _group(m, tiling)
	return out


func test_tiling_uvs_are_what_excludes_an_ordinary_face():
	var wall := PackedVector2Array([Vector2(0, 0), Vector2(64, 0), Vector2(64, 64)])
	assert_true(
		HFMaterialAtlas.group_has_tiling_uvs(wall),
		"HammerForge maps world units into UV space, so a 64-unit face is 0..64"
	)
	var unit := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	assert_false(HFMaterialAtlas.group_has_tiling_uvs(unit))


func test_an_atlas_that_could_not_be_built_says_so():
	HFLog.begin_test_capture(["Atlas"])
	var result = baker.build_mesh_from_groups(_groups(6, true), 1, 1, {"use_atlas": true})
	if result:
		add_child_autoqfree(result)
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_not_null(result, "the bake still produces geometry")
	assert_string_contains(baker.last_atlas_report, "skipped")
	assert_string_contains(baker.last_atlas_report, "tiling UVs")
	assert_eq(warnings.size(), 1, "a switch that did nothing is worth one warning")


func test_an_atlas_that_was_built_says_what_it_packed():
	var result = baker.build_mesh_from_groups(_groups(4, false), 1, 1, {"use_atlas": true})
	if result:
		add_child_autoqfree(result)
	assert_not_null(result)
	assert_string_contains(baker.last_atlas_report, "packed")
	assert_string_contains(baker.last_atlas_report, "of 4")


func test_a_bake_with_the_atlas_off_reports_nothing_about_it():
	var off = baker.build_mesh_from_groups(_groups(4, false), 1, 1, {})
	if off:
		add_child_autoqfree(off)
	assert_eq(baker.last_atlas_report, "", "a switch nobody touched has nothing to say")


func test_one_material_group_cannot_be_atlased_and_says_why():
	HFLog.begin_test_capture(["Atlas"])
	var single = baker.build_mesh_from_groups(_groups(1, false), 1, 1, {"use_atlas": true})
	if single:
		add_child_autoqfree(single)
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_string_contains(baker.last_atlas_report, "one material group")
	assert_eq(warnings.size(), 1)
