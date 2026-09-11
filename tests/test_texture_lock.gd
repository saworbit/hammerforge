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


# ===========================================================================
# adjust_uvs_for_rotation — texture lock under a brush turn (#333, #334)
# ===========================================================================


func _rot(axis: Vector3, degrees: float) -> Basis:
	return Basis(axis, deg_to_rad(degrees))


func test_a_turn_across_the_projection_leaves_the_face_alone():
	# A yaw swings a wall around rather than turning it in its own plane. The
	# old code subtracted the yaw anyway, which tipped the texture on its side.
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	face.normal = Vector3.BACK
	assert_false(face.adjust_uvs_for_rotation(_rot(Vector3.UP, 90.0)))
	assert_eq(face.uv_projection, FaceData.UVProjection.PLANAR_Z)
	assert_almost_eq(face.uv_rotation, 0.0, 0.0001)


func test_a_half_turn_across_the_plane_mirrors_v_rather_than_tipping():
	# 180 degrees about X keeps a PLANAR_Z face's plane but puts it the other
	# way up, which the V scale can hold.
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	face.normal = Vector3.BACK
	assert_true(face.adjust_uvs_for_rotation(_rot(Vector3.RIGHT, 180.0)))
	assert_eq(face.uv_projection, FaceData.UVProjection.PLANAR_Z)
	assert_almost_eq(face.uv_scale.y, -1.0, 0.0001)
	assert_almost_eq(face.uv_scale.x, 1.0, 0.0001)


func test_turn_about_the_projection_axis_keeps_the_projection():
	# PLANAR_Y reads (x, z) and PLANAR_Z reads (x, y), so the two counter-turns
	# go opposite ways. That sign used to be assumed to be the same for both.
	var y_face = FaceData.new()
	y_face.uv_projection = FaceData.UVProjection.PLANAR_Y
	y_face.normal = Vector3.UP
	assert_true(y_face.adjust_uvs_for_rotation(_rot(Vector3.UP, 30.0)))
	assert_eq(y_face.uv_projection, FaceData.UVProjection.PLANAR_Y)
	assert_almost_eq(y_face.uv_rotation, deg_to_rad(-30.0), 0.0001)

	var z_face = FaceData.new()
	z_face.uv_projection = FaceData.UVProjection.PLANAR_Z
	z_face.normal = Vector3.BACK
	assert_true(z_face.adjust_uvs_for_rotation(_rot(Vector3.BACK, 30.0)))
	assert_eq(z_face.uv_projection, FaceData.UVProjection.PLANAR_Z)
	assert_almost_eq(z_face.uv_rotation, deg_to_rad(30.0), 0.0001)


func test_turn_that_no_projection_can_express_leaves_the_face_alone():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	face.normal = Vector3.BACK
	face.uv_rotation = 0.25
	face.uv_scale = Vector2(2.0, 3.0)
	assert_false(face.adjust_uvs_for_rotation(_rot(Vector3.UP, 37.0)), "not expressible")
	assert_eq(face.uv_projection, FaceData.UVProjection.PLANAR_Z)
	assert_almost_eq(face.uv_rotation, 0.25, 0.0001)
	assert_almost_eq(face.uv_scale.y, 3.0, 0.0001)


func test_cylindrical_is_still_left_alone():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.CYLINDRICAL
	face.normal = Vector3.UP
	assert_false(face.adjust_uvs_for_rotation(_rot(Vector3.UP, 90.0)))
	assert_eq(face.uv_projection, FaceData.UVProjection.CYLINDRICAL)


func test_uv_rotation_is_wrapped_into_a_turn():
	var face = FaceData.new()
	face.uv_projection = FaceData.UVProjection.PLANAR_Y
	face.normal = Vector3.UP
	for _i in 4:
		face.adjust_uvs_for_rotation(_rot(Vector3.UP, 90.0))
	assert_almost_eq(face.uv_rotation, 0.0, 0.0001, "four quarter turns is no turn")


## The texture did not move: where U increases in the world is where it did.
##
## Solved from the face's own projected UVs rather than from the stored fields,
## so a change that keeps the fields tidy and the texture wrong still fails.
func _world_u_direction(face, basis: Basis) -> Vector3:
	face.custom_uvs = PackedVector2Array()
	face.ensure_custom_uvs()
	var verts: PackedVector3Array = face.local_verts
	var uvs: PackedVector2Array = face.custom_uvs
	if verts.size() < 3:
		return Vector3.ZERO
	var e1: Vector3 = verts[1] - verts[0]
	var e2: Vector3 = verts[2] - verts[0]
	var n := e1.cross(e2)
	if n.length() < 0.000001:
		return Vector3.ZERO
	var m := Basis(Vector3(e1.x, e2.x, n.x), Vector3(e1.y, e2.y, n.y), Vector3(e1.z, e2.z, n.z))
	var rhs := Vector3(uvs[1].x - uvs[0].x, uvs[2].x - uvs[0].x, 0.0)
	var grad := m.inverse() * rhs
	if grad.length() < 0.000001:
		return Vector3.ZERO
	return (basis * grad).normalized()


func test_a_yaw_does_not_tip_any_face_texture():
	var brush: DraftBrush = load("res://addons/hammerforge/brush_instance.gd").new()
	brush.shape = 0
	brush.size = Vector3(128, 64, 32)
	add_child_autoqfree(brush)
	brush.rebuild_preview()
	for face in brush.get_faces():
		face.uv_projection = FaceData.UVProjection.BOX_UV
		face.custom_uvs = PackedVector2Array()

	var before: Array = []
	for face in brush.get_faces():
		before.append(_world_u_direction(face, Basis.IDENTITY))

	var turn := Basis(Vector3.UP, deg_to_rad(90.0))
	for face in brush.get_faces():
		face.adjust_uvs_for_rotation(turn)

	for i in brush.get_faces().size():
		var face = brush.get_faces()[i]
		var was: Vector3 = before[i]
		if was == Vector3.ZERO:
			continue
		var now: Vector3 = _world_u_direction(face, turn)
		if absf(face.normal.dot(Vector3.UP)) > 0.9:
			# Top and bottom turn in their own plane, so the texture stays put.
			assert_almost_eq(now.dot(was), 1.0, 0.0001, "face %d should be locked" % i)
		else:
			# A wall swings around. Its texture goes with it, upright as it was.
			var carried := turn * was
			assert_almost_eq(now.dot(carried), 1.0, 0.0001, "face %d was tipped" % i)
