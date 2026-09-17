extends GutTest

## Box UV resolves against a face's normal in the level, so a turn can move a
## face from one planar axis to another. The three do not share a handedness, so
## the move is folded into `uv_scale` rather than left to mirror the face (#684).

const FaceData = preload("res://addons/hammerforge/face_data.gd")


## A 128 wide panel facing `normal`, laid out at `start` and then turned to `end`.
func _panel_facing(normal: Vector3) -> FaceData:
	var face := FaceData.new()
	var a := normal.cross(Vector3.UP)
	if a.length() < 0.001:
		a = normal.cross(Vector3.BACK)
	a = a.normalized()
	var b := normal.cross(a).normalized()
	face.local_verts = PackedVector3Array(
		[
			(-a - b) * 64.0,
			(a - b) * 64.0,
			(a + b) * 64.0,
			(-a + b) * 64.0,
		]
	)
	face.uv_projection = FaceData.UVProjection.BOX_UV
	face.uv_scale = Vector2.ONE
	face.ensure_geometry()
	# Whatever winding produced, the projection only reads which axis dominates.
	face.normal = normal
	return face


func _lay_out_then_turn(face: FaceData, turn: Basis) -> void:
	face.world_transform = Transform3D.IDENTITY
	face.reconcile_box_uv_axis()
	face.world_transform = Transform3D(turn, Vector3.ZERO)
	face.reconcile_box_uv_axis()


func _rot(axis: Vector3, degrees: float) -> Basis:
	return Basis(axis, deg_to_rad(degrees))


# ===========================================================================
# Which of the two axes the turn reverses
# ===========================================================================


func test_a_yaw_that_takes_a_wall_from_planar_z_to_planar_x_reverses_u():
	var face := _panel_facing(Vector3.BACK)
	_lay_out_then_turn(face, _rot(Vector3.UP, 90.0))
	assert_almost_eq(face.uv_scale.x, -1.0, 0.001, "U is reversed")
	assert_almost_eq(face.uv_scale.y, 1.0, 0.001, "V is left alone")


func test_a_roll_that_takes_a_floor_from_planar_y_to_planar_z_reverses_v():
	var face := _panel_facing(Vector3.UP)
	_lay_out_then_turn(face, _rot(Vector3.RIGHT, 90.0))
	assert_almost_eq(face.uv_scale.x, 1.0, 0.001, "U is left alone")
	assert_almost_eq(face.uv_scale.y, -1.0, 0.001, "V is reversed")


func test_a_yaw_that_takes_a_wall_from_planar_x_to_planar_z_reverses_neither():
	# The two left handed axes agree with each other, so this pair never flips.
	var face := _panel_facing(Vector3.RIGHT)
	_lay_out_then_turn(face, _rot(Vector3.UP, 90.0))
	assert_almost_eq(face.uv_scale.x, 1.0, 0.001)
	assert_almost_eq(face.uv_scale.y, 1.0, 0.001)


func test_a_turn_that_keeps_the_face_in_its_own_plane_is_left_alone():
	# adjust_uvs_for_rotation() is what answers for that case.
	var face := _panel_facing(Vector3.BACK)
	_lay_out_then_turn(face, _rot(Vector3.BACK, 90.0))
	assert_almost_eq(face.uv_scale.x, 1.0, 0.001)
	assert_almost_eq(face.uv_scale.y, 1.0, 0.001)


func test_an_off_axis_turn_is_left_alone_rather_than_guessed_at():
	# No planar projection holds the result, so a sign is not the answer.
	var face := _panel_facing(Vector3.BACK)
	_lay_out_then_turn(face, _rot(Vector3(1, 1, 1).normalized(), 37.0))
	assert_almost_eq(face.uv_scale.x, 1.0, 0.001)
	assert_almost_eq(face.uv_scale.y, 1.0, 0.001)


func test_a_face_on_an_explicit_axis_never_moves_between_them():
	var face := _panel_facing(Vector3.BACK)
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	_lay_out_then_turn(face, _rot(Vector3.UP, 90.0))
	assert_almost_eq(face.uv_scale.x, 1.0, 0.001)
	assert_almost_eq(face.uv_scale.y, 1.0, 0.001)


# ===========================================================================
# Nothing on disk changes meaning
# ===========================================================================


func test_the_first_orientation_a_face_is_told_is_its_layout():
	# A level saved with a yawed brush reopens at that orientation. If the first
	# reading were treated as a turn away from the identity, every such face
	# would flip on load.
	var face := _panel_facing(Vector3.BACK)
	face.world_transform = Transform3D(_rot(Vector3.UP, 90.0), Vector3.ZERO)
	face.reconcile_box_uv_axis()
	assert_almost_eq(face.uv_scale.x, 1.0, 0.001, "nothing was reconciled")
	assert_almost_eq(face.uv_scale.y, 1.0, 0.001)


func test_turning_back_undoes_the_flip():
	var face := _panel_facing(Vector3.BACK)
	_lay_out_then_turn(face, _rot(Vector3.UP, 90.0))
	assert_almost_eq(face.uv_scale.x, -1.0, 0.001, "reversed by the turn")
	face.world_transform = Transform3D.IDENTITY
	face.reconcile_box_uv_axis()
	assert_almost_eq(face.uv_scale.x, 1.0, 0.001, "and put back by the turn back")


func test_a_repeated_reading_of_the_same_orientation_does_nothing():
	var face := _panel_facing(Vector3.BACK)
	_lay_out_then_turn(face, _rot(Vector3.UP, 90.0))
	for i in 5:
		face.reconcile_box_uv_axis()
	assert_almost_eq(face.uv_scale.x, -1.0, 0.001, "flipped once, not five times")


# ===========================================================================
# What the face ends up showing
# ===========================================================================


## World direction of increasing U across the face.
func _u_direction(face: FaceData) -> Vector3:
	var verts: PackedVector3Array = face.local_verts
	var uvs: PackedVector2Array = face._project_uvs_for_vertices(verts)
	var basis: Basis = face.world_transform.basis
	var v0: Vector3 = basis * verts[0]
	var e1: Vector3 = basis * verts[1] - v0
	var e2: Vector3 = basis * verts[2] - v0
	var n: Vector3 = e1.cross(e2)
	var m := Basis(Vector3(e1.x, e2.x, n.x), Vector3(e1.y, e2.y, n.y), Vector3(e1.z, e2.z, n.z))
	if absf(m.determinant()) < 0.000001:
		return Vector3.ZERO
	var g: Vector3 = m.inverse() * Vector3(uvs[1].x - uvs[0].x, uvs[2].x - uvs[0].x, 0.0)
	return g.normalized() if g.length() > 0.0 else Vector3.ZERO


func test_a_yawed_wall_carries_its_texture_round_instead_of_mirroring_it():
	var face := _panel_facing(Vector3.BACK)
	face.world_transform = Transform3D.IDENTITY
	face.reconcile_box_uv_axis()
	var before := _u_direction(face)
	assert_ne(before, Vector3.ZERO, "the wall has a measurable U direction")
	var turn := _rot(Vector3.UP, 90.0)
	face.world_transform = Transform3D(turn, Vector3.ZERO)
	face.reconcile_box_uv_axis()
	var after := _u_direction(face)
	var carried := (turn * before).normalized()
	assert_almost_eq(
		after.dot(carried), 1.0, 0.001, "U went round with the wall rather than reversing"
	)
