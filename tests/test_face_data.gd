extends GutTest

const FaceData = preload("res://addons/hammerforge/face_data.gd")

# ===========================================================================
# to_dict / from_dict round-trip
# ===========================================================================


func test_round_trip_basic_face():
	var face = FaceData.new()
	face.material_idx = 3
	face.uv_projection = FaceData.UVProjection.PLANAR_Y
	face.uv_scale = Vector2(2.0, 0.5)
	face.uv_offset = Vector2(0.1, -0.3)
	face.uv_rotation = 0.75
	face.normal = Vector3(0.0, 1.0, 0.0)
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
	)
	var data = face.to_dict()
	var restored = FaceData.from_dict(data)
	assert_eq(restored.material_idx, 3, "material_idx round-trip")
	assert_eq(restored.uv_projection, FaceData.UVProjection.PLANAR_Y, "uv_projection round-trip")
	assert_almost_eq(restored.uv_scale.x, 2.0, 0.001, "uv_scale.x round-trip")
	assert_almost_eq(restored.uv_scale.y, 0.5, 0.001, "uv_scale.y round-trip")
	assert_almost_eq(restored.uv_offset.x, 0.1, 0.001, "uv_offset.x round-trip")
	assert_almost_eq(restored.uv_offset.y, -0.3, 0.001, "uv_offset.y round-trip")
	assert_almost_eq(restored.uv_rotation, 0.75, 0.001, "uv_rotation round-trip")
	assert_eq(restored.local_verts.size(), 4, "local_verts count round-trip")


func test_round_trip_custom_uvs():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0)])
	face.custom_uvs = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0)])
	face.normal = Vector3.FORWARD
	var data = face.to_dict()
	var restored = FaceData.from_dict(data)
	assert_eq(restored.custom_uvs.size(), 3, "custom_uvs count")
	assert_almost_eq(restored.custom_uvs[1].x, 1.0, 0.001, "custom_uvs[1].x")
	assert_almost_eq(restored.custom_uvs[2].y, 1.0, 0.001, "custom_uvs[2].y")


func test_round_trip_normal():
	# from_dict calls ensure_geometry() which recomputes normal from local_verts.
	# Normal for this triangle = cross((1,0,0), (0,1,0)) = (0,0,1)
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	face.ensure_geometry()
	var data = face.to_dict()
	var restored = FaceData.from_dict(data)
	assert_almost_eq(restored.normal.x, 0.0, 0.01, "normal.x")
	assert_almost_eq(restored.normal.y, 0.0, 0.01, "normal.y")
	assert_almost_eq(restored.normal.z, 1.0, 0.01, "normal.z")


func test_round_trip_all_projections():
	var projections = [
		FaceData.UVProjection.PLANAR_X,
		FaceData.UVProjection.PLANAR_Y,
		FaceData.UVProjection.PLANAR_Z,
		FaceData.UVProjection.BOX_UV,
		FaceData.UVProjection.CYLINDRICAL,
	]
	for proj in projections:
		var face = FaceData.new()
		face.uv_projection = proj
		face.local_verts = PackedVector3Array(
			[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
		)
		var data = face.to_dict()
		var restored = FaceData.from_dict(data)
		assert_eq(restored.uv_projection, proj, "Projection %d round-trip" % proj)


func test_round_trip_default_values():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	var data = face.to_dict()
	var restored = FaceData.from_dict(data)
	assert_eq(restored.material_idx, -1, "Default material_idx")
	assert_eq(restored.uv_projection, FaceData.UVProjection.PLANAR_Z, "Default uv_projection")
	assert_almost_eq(restored.uv_scale.x, 1.0, 0.001, "Default uv_scale.x")
	assert_almost_eq(restored.uv_offset.x, 0.0, 0.001, "Default uv_offset.x")
	assert_almost_eq(restored.uv_rotation, 0.0, 0.001, "Default uv_rotation")


func test_from_dict_empty():
	var restored = FaceData.from_dict({})
	assert_not_null(restored, "from_dict({}) should return a FaceData")
	assert_eq(restored.material_idx, -1, "Empty dict should use defaults")


# ===========================================================================
# ensure_geometry
# ===========================================================================


func test_ensure_geometry_computes_normal():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
	)
	face.ensure_geometry()
	# Quad on XZ plane → normal should be Y-axis (up or down)
	assert_almost_eq(abs(face.normal.y), 1.0, 0.01, "Flat XZ quad normal should be Y-axis")


func test_ensure_geometry_computes_bounds():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3(-5, -3, -1), Vector3(5, 3, 1), Vector3(0, 0, 0)])
	face.ensure_geometry()
	assert_almost_eq(face.bounds.size.x, 10.0, 0.01, "Bounds width")
	assert_almost_eq(face.bounds.size.y, 6.0, 0.01, "Bounds height")


func test_ensure_geometry_degenerate():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	face.ensure_geometry()
	# Should not crash, normal defaults to UP
	assert_eq(face.normal, Vector3.UP, "Degenerate face normal defaults to UP")


# ===========================================================================
# triangulate
# ===========================================================================


func test_triangulate_triangle():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	var tri = face.triangulate()
	assert_eq(tri["verts"].size(), 3, "Triangle produces 3 verts")


func test_triangulate_quad():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]
	)
	var tri = face.triangulate()
	assert_eq(tri["verts"].size(), 6, "Quad produces 6 verts (2 triangles)")


func test_triangulate_empty():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3.ZERO])
	var tri = face.triangulate()
	assert_eq(tri["verts"].size(), 0, "Single vertex produces no triangles")


# ===========================================================================
# box_projection_axis
# ===========================================================================


func test_box_projection_x():
	var face = FaceData.new()
	face.normal = Vector3(1, 0, 0)
	assert_eq(face._box_projection_axis(), FaceData.UVProjection.PLANAR_X)


func test_box_projection_y():
	var face = FaceData.new()
	face.normal = Vector3(0, 1, 0)
	assert_eq(face._box_projection_axis(), FaceData.UVProjection.PLANAR_Y)


func test_box_projection_z():
	var face = FaceData.new()
	face.normal = Vector3(0, 0, 1)
	assert_eq(face._box_projection_axis(), FaceData.UVProjection.PLANAR_Z)
