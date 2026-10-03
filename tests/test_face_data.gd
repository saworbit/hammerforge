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
	# CW triangle (from +Z): cross((0,1,0)-(0,0,0), (1,0,0)-(0,0,0)) flipped = (0,0,1)
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)])
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
	assert_eq(restored.uv_projection, FaceData.UVProjection.BOX_UV, "Default uv_projection")
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


# ===========================================================================
# A face normal must not depend on how big the face is (#330)
# ===========================================================================


func test_a_small_face_gets_its_real_normal_not_the_fallback():
	# The degenerate test used to be an absolute floor on the raw cross product,
	# which grows with the square of the face. A 0.01-unit triangle fell under it
	# and was given Vector3.UP, so a small bevel cap faced into the solid
	# whatever winding it had been built with.
	for scale in [1.0, 0.1, 0.01, 0.001]:
		var face = FaceData.new()
		face.local_verts = PackedVector3Array(
			[
				Vector3(32.0, -32.0, 32.0),
				Vector3(32.0 - scale, -32.0, 32.0),
				Vector3(32.0, -32.0, 32.0 - scale),
			]
		)
		face.ensure_geometry()
		assert_almost_eq(
			absf(face.normal.dot(Vector3.UP)), 1.0, 0.0001, "scale %s is flat in Y" % scale
		)
		assert_almost_eq(face.normal.y, 1.0, 0.0001, "scale %s should keep its winding" % scale)


func test_a_face_with_three_points_in_a_line_is_still_called_degenerate():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0)])
	face.ensure_geometry()
	assert_eq(face.normal, Vector3.UP, "collinear points have no plane")


func test_a_face_with_two_points_in_the_same_place_is_degenerate():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3(1, 0, 0)])
	face.ensure_geometry()
	assert_eq(face.normal, Vector3.UP)


# ===========================================================================
# A normal carried through a stretched brush (#884)
# ===========================================================================


## A 45 degree slope, as a wedge has.
func _slope_face() -> FaceData:
	var face = FaceData.new()
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)]
	)
	face.ensure_geometry()
	return face


func test_a_stretched_face_keeps_a_normal_square_to_its_corners():
	var face := _slope_face()
	for stretch in [Vector3(4, 1, 1), Vector3(1, 3, 1), Vector3(2, 0.5, 3)]:
		var basis := Basis(Vector3(0.3, 1, 0.2).normalized(), 0.7).scaled(stretch)
		var n: Vector3 = face.normal_through(basis)
		assert_almost_eq(n.length(), 1.0, 1e-5, "the normal comes back unit length")
		var corners := face.local_verts
		for i in corners.size():
			var edge: Vector3 = basis * (corners[(i + 1) % corners.size()] - corners[i])
			assert_almost_eq(
				n.dot(edge.normalized()),
				0.0,
				1e-5,
				"edge %d at %s leans off the face" % [i, stretch]
			)
		assert_gt(n.dot(basis * face.normal), 0.0, "the normal still faces out at %s" % stretch)


func test_a_turned_or_evenly_scaled_face_keeps_the_normal_it_always_had():
	var face := _slope_face()
	for basis in [
		Basis.IDENTITY,
		Basis(Vector3(0.3, 1, 0.2).normalized(), 0.7),
		Basis(Vector3(-1, 0.4, 0.1).normalized(), 2.0).scaled(Vector3(3, 3, 3)),
		Basis.IDENTITY.scaled(Vector3(-1, 1, 1)),
	]:
		assert_almost_eq(
			face.normal_through(basis), (basis * face.normal).normalized(), Vector3.ONE * 1e-5
		)


func test_a_face_squashed_flat_gets_a_normal_without_an_error():
	var n: Vector3 = _slope_face().normal_through(Basis.IDENTITY.scaled(Vector3(1, 0, 1)))
	assert_true(n.is_finite(), "a flattened brush still gives a finite normal")


# ===========================================================================
# Box UV picks its axis by the way a stretched face really faces (#887)
# ===========================================================================


## The axis Box UV picked before #887: the largest part of the normal carried by
## the basis alone.
static func _axis_by_basis(face: FaceData, basis: Basis) -> int:
	var n := (basis * face.normal).abs()
	if n.x >= n.y and n.x >= n.z:
		return FaceData.UVProjection.PLANAR_X
	if n.y >= n.x and n.y >= n.z:
		return FaceData.UVProjection.PLANAR_Y
	return FaceData.UVProjection.PLANAR_Z


func test_box_uv_picks_a_stretched_slope_s_axis_by_the_way_it_really_faces():
	var face := _slope_face()
	# The slope faces (0, 1, 1). Four times as tall it faces mostly along Z, and
	# four times as deep mostly along Y. The basis alone leans it the other way.
	var tall := Transform3D(Basis.IDENTITY.scaled(Vector3(1, 4, 1)), Vector3.ZERO)
	var deep := Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1, 4)), Vector3.ZERO)
	assert_eq(face._box_projection_axis_in(tall), FaceData.UVProjection.PLANAR_Z)
	assert_eq(face._box_projection_axis_in(deep), FaceData.UVProjection.PLANAR_Y)


func test_box_uv_picks_the_axis_it_always_did_without_a_stretch():
	var face := _slope_face()
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 1), Vector3(1, 0.3, 1), Vector3(1, 1.3, 0), Vector3(0, 1, 0)]
	)
	face.ensure_geometry()
	for basis in [
		Basis.IDENTITY,
		Basis(Vector3(0.3, 1, 0.2).normalized(), 0.7),
		Basis(Vector3(-1, 0.4, 0.1).normalized(), 2.0).scaled(Vector3(3, 3, 3)),
	]:
		assert_eq(
			face._box_projection_axis_in(Transform3D(basis, Vector3.ZERO)),
			_axis_by_basis(face, basis),
			"under %s" % basis
		)
