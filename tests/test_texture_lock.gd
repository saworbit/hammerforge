extends GutTest

const FaceData = preload("res://addons/hammerforge/face_data.gd")

# ===========================================================================
# adjust_uvs_for_transform — position compensation
# ===========================================================================


func test_planar_z_position_offset_compensated():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	face.uv_scale = Vector2.ONE
	face.uv_offset = Vector2.ZERO
	face.normal = Vector3.BACK
	# Move brush 10 units in X, 5 in Y
	face.adjust_uvs_for_transform(Vector3(10, 5, 0), Vector3.ONE)
	# PLANAR_Z projects (x, y) → UV, so offset should cancel the move
	assert_almost_eq(face.uv_offset.x, -10.0, 0.001, "X offset should compensate")
	assert_almost_eq(face.uv_offset.y, -5.0, 0.001, "Y offset should compensate")


func test_planar_y_position_offset_compensated():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Y
	face.uv_scale = Vector2.ONE
	face.uv_offset = Vector2.ZERO
	face.normal = Vector3.UP
	# Move 4 in X, 3 in Z
	face.adjust_uvs_for_transform(Vector3(4, 0, 3), Vector3.ONE)
	assert_almost_eq(face.uv_offset.x, -4.0, 0.001)
	assert_almost_eq(face.uv_offset.y, -3.0, 0.001)


func test_planar_x_position_offset_compensated():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_X
	face.uv_scale = Vector2.ONE
	face.uv_offset = Vector2.ZERO
	face.normal = Vector3.RIGHT
	# Move 2 in Z, 7 in Y
	face.adjust_uvs_for_transform(Vector3(0, 7, 2), Vector3.ONE)
	assert_almost_eq(face.uv_offset.x, -2.0, 0.001, "Z → UV.x for PLANAR_X")
	assert_almost_eq(face.uv_offset.y, -7.0, 0.001, "Y → UV.y for PLANAR_X")


func test_position_compensation_scales_with_uv_scale():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	face.uv_scale = Vector2(2.0, 0.5)
	face.uv_offset = Vector2.ZERO
	face.normal = Vector3.BACK
	face.adjust_uvs_for_transform(Vector3(3, 4, 0), Vector3.ONE)
	# offset = -(delta * uv_scale) → -(3*2, 4*0.5) = (-6, -2)
	assert_almost_eq(face.uv_offset.x, -6.0, 0.001)
	assert_almost_eq(face.uv_offset.y, -2.0, 0.001)


# ===========================================================================
# adjust_uvs_for_transform — size compensation
# ===========================================================================


func test_size_change_adjusts_uv_scale():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	face.uv_scale = Vector2(1.0, 1.0)
	face.uv_offset = Vector2.ZERO
	face.normal = Vector3.BACK
	# Double X, halve Y (PLANAR_Z uses x, y axes)
	face.adjust_uvs_for_transform(Vector3.ZERO, Vector3(2.0, 0.5, 1.0))
	# inv_size = (1/2, 1/0.5) = (0.5, 2.0)
	assert_almost_eq(face.uv_scale.x, 0.5, 0.001, "UV scale X should halve")
	assert_almost_eq(face.uv_scale.y, 2.0, 0.001, "UV scale Y should double")


func test_no_size_change_preserves_uv_scale():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	face.uv_scale = Vector2(3.0, 4.0)
	face.uv_offset = Vector2.ZERO
	face.normal = Vector3.BACK
	face.adjust_uvs_for_transform(Vector3.ZERO, Vector3.ONE)
	assert_almost_eq(face.uv_scale.x, 3.0, 0.001)
	assert_almost_eq(face.uv_scale.y, 4.0, 0.001)


func test_planar_y_size_change():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Y
	face.uv_scale = Vector2(1.0, 1.0)
	face.uv_offset = Vector2.ZERO
	face.normal = Vector3.UP
	# Triple X, Z stays same (PLANAR_Y uses x, z axes)
	face.adjust_uvs_for_transform(Vector3.ZERO, Vector3(3.0, 1.0, 1.0))
	assert_almost_eq(face.uv_scale.x, 1.0 / 3.0, 0.01, "UV.x should inverse-scale with X")
	assert_almost_eq(face.uv_scale.y, 1.0, 0.001, "UV.y unchanged for Z=1")


# ===========================================================================
# Box UV resolves to planar axis
# ===========================================================================


func test_box_uv_delegates_to_planar():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.BOX_UV
	face.uv_scale = Vector2.ONE
	face.uv_offset = Vector2.ZERO
	face.normal = Vector3.UP  # Should resolve to PLANAR_Y
	face.adjust_uvs_for_transform(Vector3(5, 0, 0), Vector3.ONE)
	# PLANAR_Y projects (x, z), so X movement should affect offset.x
	assert_almost_eq(face.uv_offset.x, -5.0, 0.001)


# ===========================================================================
# Cylindrical is skipped
# ===========================================================================


func test_cylindrical_skipped():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.CYLINDRICAL
	face.uv_scale = Vector2(2.0, 3.0)
	face.uv_offset = Vector2(1.0, 1.0)
	face.normal = Vector3.UP
	face.adjust_uvs_for_transform(Vector3(10, 10, 10), Vector3(2, 2, 2))
	# Should be unchanged
	assert_almost_eq(face.uv_scale.x, 2.0, 0.001)
	assert_almost_eq(face.uv_scale.y, 3.0, 0.001)
	assert_almost_eq(face.uv_offset.x, 1.0, 0.001)
	assert_almost_eq(face.uv_offset.y, 1.0, 0.001)


# ===========================================================================
# Combined move + resize
# ===========================================================================


func test_combined_move_and_resize():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	face.uv_scale = Vector2(1.0, 1.0)
	face.uv_offset = Vector2.ZERO
	face.normal = Vector3.BACK
	# Move 5 in X, double size in X
	face.adjust_uvs_for_transform(Vector3(5, 0, 0), Vector3(2.0, 1.0, 1.0))
	# Offset: -(5 * 1.0) = -5 (applied before scale change)
	# Scale: 1.0 * (1/2) = 0.5
	assert_almost_eq(face.uv_offset.x, -5.0, 0.001)
	assert_almost_eq(face.uv_scale.x, 0.5, 0.001)


# ===========================================================================
# adjust_uvs_for_transform — rotated faces (#141)
# ===========================================================================


func _planar_z_face(rotation: float, scale: Vector2 = Vector2.ONE) -> FaceData:
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	face.uv_scale = scale
	face.uv_offset = Vector2.ZERO
	face.uv_rotation = rotation
	face.normal = Vector3.BACK
	return face


## Texture lock means a world point keeps its texel. After moving the brush by
## d, the vertex now at projected q must get the UV the vertex at q - d had.
func _assert_texture_stays_pinned(
	face: FaceData, pos_delta: Vector3, probe: Vector2, msg: String
) -> void:
	var delta_2d := Vector2(pos_delta.x, pos_delta.y)
	var before: Vector2 = face._apply_uv_transform(probe - delta_2d)
	face.adjust_uvs_for_transform(pos_delta, Vector3.ONE)
	var after: Vector2 = face._apply_uv_transform(probe)
	assert_almost_eq(after.x, before.x, 0.001, "%s (u)" % msg)
	assert_almost_eq(after.y, before.y, 0.001, "%s (v)" % msg)


func test_rotated_face_keeps_its_texture_pinned():
	_assert_texture_stays_pinned(
		_planar_z_face(PI / 2.0), Vector3(2, 0, 0), Vector2(3, 1), "90 degree face"
	)


func test_rotated_and_scaled_face_keeps_its_texture_pinned():
	_assert_texture_stays_pinned(
		_planar_z_face(PI / 3.0, Vector2(2.0, 0.5)),
		Vector3(5, -3, 0),
		Vector2(-1, 4),
		"60 degree face with non-uniform scale"
	)


func test_unrotated_face_keeps_its_texture_pinned():
	_assert_texture_stays_pinned(
		_planar_z_face(0.0), Vector3(2, 0, 0), Vector2(3, 1), "unrotated face"
	)


func test_quarter_turn_moves_the_offset_onto_the_other_axis():
	var face = _planar_z_face(PI / 2.0)
	face.adjust_uvs_for_transform(Vector3(2, 0, 0), Vector3.ONE)
	# (2, 0) rotated a quarter turn is (0, 2), so the compensation lands on v.
	assert_almost_eq(face.uv_offset.x, 0.0, 0.001, "A rotated move must not stay on u")
	assert_almost_eq(face.uv_offset.y, -2.0, 0.001)


func test_rotated_compensation_matches_the_carve_system_math():
	# hf_carve_system.gd already rotates the delta before scaling. The two must
	# agree or a carved face drifts away from the brush it came from.
	var rotation := PI / 5.0
	var scale := Vector2(1.5, 0.75)
	var pos_delta := Vector3(4, -2, 0)
	var face = _planar_z_face(rotation, scale)
	face.adjust_uvs_for_transform(pos_delta, Vector3.ONE)
	var carve_delta := Vector2(pos_delta.x, pos_delta.y).rotated(rotation) * scale
	assert_almost_eq(face.uv_offset.x, -carve_delta.x, 0.001)
	assert_almost_eq(face.uv_offset.y, -carve_delta.y, 0.001)


func test_rotation_does_not_disturb_size_compensation():
	var face = _planar_z_face(PI / 2.0)
	face.adjust_uvs_for_transform(Vector3.ZERO, Vector3(2.0, 0.5, 1.0))
	assert_almost_eq(face.uv_scale.x, 0.5, 0.001)
	assert_almost_eq(face.uv_scale.y, 2.0, 0.001)
