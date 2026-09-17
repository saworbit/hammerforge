extends GutTest

## UVs are projected from where a vertex is in the level, not from where it is in
## its brush (#652), and texture lock is what keeps a texture on a brush across a
## move (#653).

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")

const PANEL_AT_ORIGIN := Vector2(-64.0, 64.0)


## A 128 wide panel in the XY plane, centred on its own brush, sitting `at_x`.
func _panel(at_x: float) -> FaceData:
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(
		[
			Vector3(-64, -64, 0),
			Vector3(64, -64, 0),
			Vector3(64, 64, 0),
			Vector3(-64, 64, 0),
		]
	)
	face.uv_projection = FaceData.UVProjection.PLANAR_Z
	face.uv_scale = Vector2.ONE
	face.uv_offset = Vector2.ZERO
	face.ensure_geometry()
	face.world_transform = Transform3D(Basis.IDENTITY, Vector3(at_x, 0, 0))
	return face


## The span of u the face covers, as (lowest, highest).
func _u_span(face: FaceData, space: Variant = null) -> Vector2:
	var uvs: PackedVector2Array = (
		face._project_uvs_for_vertices(face.local_verts)
		if space == null
		else face._project_uvs_in_space(face.local_verts, space)
	)
	var lo := uvs[0].x
	var hi := uvs[0].x
	for uv in uvs:
		lo = minf(lo, uv.x)
		hi = maxf(hi, uv.x)
	return Vector2(lo, hi)


func _assert_span(face: FaceData, want: Vector2, what: String) -> void:
	var got := _u_span(face)
	assert_almost_eq(got.x, want.x, 0.001, "%s: u starts at %.2f" % [what, want.x])
	assert_almost_eq(got.y, want.y, 0.001, "%s: u ends at %.2f" % [what, want.y])


# ===========================================================================
# Projection
# ===========================================================================


func test_a_panel_projects_from_where_it_is_in_the_level():
	_assert_span(_panel(0.0), PANEL_AT_ORIGIN, "a panel at the origin")
	_assert_span(_panel(128.0), Vector2(64.0, 192.0), "the same panel at x=128")
	_assert_span(_panel(256.0), Vector2(192.0, 320.0), "the same panel at x=256")


func test_two_panels_in_a_row_meet_without_a_seam():
	var left := _panel(0.0)
	var right := _panel(128.0)
	assert_almost_eq(
		_u_span(right).x,
		_u_span(left).y,
		0.001,
		"the second panel's texture starts where the first one's ends"
	)


func test_a_cylindrical_projection_stays_in_the_brushs_own_space():
	# Its angle is measured about the brush's own axis. Taking that in world
	# space would spin the texture as the brush moved.
	var here := _panel(0.0)
	var there := _panel(512.0)
	here.uv_projection = FaceData.UVProjection.CYLINDRICAL
	there.uv_projection = FaceData.UVProjection.CYLINDRICAL
	assert_almost_eq(
		_u_span(there).x, _u_span(here).x, 0.001, "moving the brush does not turn the texture"
	)


# ===========================================================================
# Which axis Box UV resolves to
# ===========================================================================


func _yawed_wall() -> FaceData:
	var face := _panel(0.0)
	face.uv_projection = FaceData.UVProjection.BOX_UV
	face.world_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO)
	return face


func test_box_uv_resolves_its_axis_in_the_space_it_projects_in():
	var face := _yawed_wall()
	assert_eq(
		face._box_projection_axis_in(Transform3D.IDENTITY),
		FaceData.UVProjection.PLANAR_Z,
		"the panel faces along Z in its brush"
	)
	assert_eq(
		face._box_projection_axis_in(face.world_transform),
		FaceData.UVProjection.PLANAR_X,
		"and along X in the level once the brush is yawed a quarter turn"
	)


func test_a_yawed_wall_still_has_a_texture_across_it():
	# Resolving in the brush's space kept PLANAR_Z, which reads world (x, y) --
	# and a wall yawed a quarter turn sits at one x, so every vertex got the same
	# u and the texture smeared into a line.
	var span := _u_span(_yawed_wall())
	assert_almost_eq(span.y - span.x, 128.0, 0.001, "the wall's own width, in world units")


# ===========================================================================
# Texture lock
# ===========================================================================


func test_texture_lock_keeps_the_texture_on_a_brush_that_moves():
	var face := _panel(0.0)
	face.world_transform = Transform3D(Basis.IDENTITY, Vector3(128, 0, 0))
	face.adjust_uvs_for_transform(Vector3(128, 0, 0), Vector3.ONE)
	_assert_span(face, PANEL_AT_ORIGIN, "with texture lock on, the texture travels with the brush")


func test_without_texture_lock_the_texture_stays_where_it_was_in_the_level():
	var face := _panel(0.0)
	face.world_transform = Transform3D(Basis.IDENTITY, Vector3(128, 0, 0))
	_assert_span(face, Vector2(64.0, 192.0), "with texture lock off, the brush slides under it")


# ===========================================================================
# Migration from before the change
# ===========================================================================


func test_a_saved_face_records_the_new_uv_format_version():
	assert_eq(int(FaceData.new().to_dict().get("uv_format_version", 0)), 2)


func _loaded_at(offset: Vector2, version: int, at_x: float) -> FaceData:
	var face := _panel(0.0)
	face.uv_offset = offset
	var data := face.to_dict()
	data["uv_format_version"] = version
	var loaded := FaceData.from_dict(data)
	loaded.world_transform = Transform3D(Basis.IDENTITY, Vector3(at_x, 0, 0))
	loaded.migrate_uvs_to_world_space()
	return loaded


func test_an_offset_set_by_hand_before_the_change_still_puts_the_texture_there():
	# Under v1 an offset measured from the brush, so this panel read
	# u[-63.75..64.25] wherever the brush was. It still does.
	_assert_span(
		_loaded_at(Vector2(0.25, 0.0), 1, 128.0),
		PANEL_AT_ORIGIN + Vector2(0.25, 0.25),
		"a hand set offset survives the move to world space"
	)


func test_a_face_nobody_had_positioned_takes_the_new_projection():
	# Migrating this one would put the panels of a wall back on the same patch
	# of texture, which is the thing #652 is about.
	_assert_span(
		_loaded_at(Vector2.ZERO, 1, 128.0),
		Vector2(64.0, 192.0),
		"an untouched face gets the fix rather than the old placement"
	)


func test_a_face_saved_since_the_change_is_not_migrated_again():
	_assert_span(
		_loaded_at(Vector2(0.25, 0.0), 2, 128.0),
		Vector2(64.25, 192.25),
		"a v2 face is already in world space"
	)


func test_migrating_twice_does_nothing_the_second_time():
	var face := _loaded_at(Vector2(0.25, 0.0), 1, 128.0)
	var once := _u_span(face)
	face.migrate_uvs_to_world_space()
	assert_almost_eq(_u_span(face).x, once.x, 0.001, "the second call is a no-op")


# ===========================================================================
# The brush is what tells a face where it is
# ===========================================================================


func _placed_brush(at_x: float) -> DraftBrush:
	var brush: DraftBrush = autoqfree(DraftBrush.new())
	brush.size = Vector3(128, 128, 16)
	brush.position = Vector3(at_x, 0, 0)
	return brush


func test_faces_restored_onto_a_placed_brush_are_told_where_it_is():
	# `apply_serialized_faces()` appends into `faces` rather than assigning it,
	# so the setter that normally does this never fires.
	var source := _placed_brush(0.0)
	source.faces = source._build_box_faces()
	var moved := _placed_brush(128.0)
	moved.apply_serialized_faces(source.serialize_faces())
	assert_gt(moved.faces.size(), 0, "the faces came back")
	for face in moved.faces:
		assert_almost_eq(
			face.world_transform.origin.x, 128.0, 0.001, "every restored face knows the brush moved"
		)


func test_a_level_saved_before_the_change_textures_the_same_after_it():
	var placed := _placed_brush(128.0)
	placed.faces = placed._build_box_faces()
	var want: Array[Vector2] = []
	for face in placed.faces:
		face.uv_offset = Vector2(0.25, -0.5)
		# What v1 rendered: projected from the brush's own vertices.
		want.append(_u_span(face, Transform3D.IDENTITY))
	var data := placed.serialize_faces()
	for entry in data:
		entry["uv_format_version"] = 1
	var reloaded := _placed_brush(128.0)
	reloaded.apply_serialized_faces(data)
	assert_eq(reloaded.faces.size(), want.size(), "every face came back")
	for i in reloaded.faces.size():
		var got := _u_span(reloaded.faces[i])
		assert_almost_eq(got.x, want[i].x, 0.001, "face %d textures where it did before" % i)
		assert_almost_eq(got.y, want[i].y, 0.001, "face %d covers what it did before" % i)
