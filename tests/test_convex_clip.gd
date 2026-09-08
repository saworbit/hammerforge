extends GutTest

## HFConvexClip: splitting a convex solid by an arbitrary plane.
##
## This is the load-bearing geometry for Clip and Carve, so the assertions here
## are about the properties a brush has to keep — closed, convex, and wound
## clockwise from outside — rather than about specific vertex coordinates.
## Winding is checked against an unsplit control, because a broken winding *check*
## and a broken winding are otherwise indistinguishable.

const HFConvexClipScript = preload("res://addons/hammerforge/hf_convex_clip.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")

const EPS := 0.001

# ===========================================================================
# Fixtures
# ===========================================================================


## A quad wound clockwise from outside, whichever order the corners arrive in.
func _quad(corners: Array, outward: Vector3) -> FaceDataScript:
	var face = FaceDataScript.new()
	var verts := PackedVector3Array(corners)
	face.local_verts = verts
	face.ensure_geometry()
	if face.normal.dot(outward) < 0.0:
		var flipped := PackedVector3Array()
		for i in range(verts.size() - 1, -1, -1):
			flipped.append(verts[i])
		face.local_verts = flipped
		face.ensure_geometry()
	return face


func _box_faces(size: Vector3, centre: Vector3 = Vector3.ZERO) -> Array:
	var h: Vector3 = size * 0.5
	var lo: Vector3 = centre - h
	var hi: Vector3 = centre + h
	return [
		_quad(
			[
				Vector3(hi.x, lo.y, lo.z),
				Vector3(hi.x, lo.y, hi.z),
				Vector3(hi.x, hi.y, hi.z),
				Vector3(hi.x, hi.y, lo.z)
			],
			Vector3.RIGHT
		),
		_quad(
			[
				Vector3(lo.x, lo.y, lo.z),
				Vector3(lo.x, lo.y, hi.z),
				Vector3(lo.x, hi.y, hi.z),
				Vector3(lo.x, hi.y, lo.z)
			],
			Vector3.LEFT
		),
		_quad(
			[
				Vector3(lo.x, hi.y, lo.z),
				Vector3(lo.x, hi.y, hi.z),
				Vector3(hi.x, hi.y, hi.z),
				Vector3(hi.x, hi.y, lo.z)
			],
			Vector3.UP
		),
		_quad(
			[
				Vector3(lo.x, lo.y, lo.z),
				Vector3(lo.x, lo.y, hi.z),
				Vector3(hi.x, lo.y, hi.z),
				Vector3(hi.x, lo.y, lo.z)
			],
			Vector3.DOWN
		),
		_quad(
			[
				Vector3(lo.x, lo.y, hi.z),
				Vector3(lo.x, hi.y, hi.z),
				Vector3(hi.x, hi.y, hi.z),
				Vector3(hi.x, lo.y, hi.z)
			],
			Vector3.BACK
		),
		_quad(
			[
				Vector3(lo.x, lo.y, lo.z),
				Vector3(lo.x, hi.y, lo.z),
				Vector3(hi.x, hi.y, lo.z),
				Vector3(hi.x, lo.y, lo.z)
			],
			Vector3.FORWARD
		),
	]


## A triangular prism: a box with the +X/+Y edge collapsed. Not symmetric about
## any axis, which is what makes it a useful second shape.
func _wedge_faces(size: Vector3) -> Array:
	var h: Vector3 = size * 0.5
	return [
		_quad(
			[
				Vector3(-h.x, -h.y, -h.z),
				Vector3(-h.x, -h.y, h.z),
				Vector3(h.x, -h.y, h.z),
				Vector3(h.x, -h.y, -h.z)
			],
			Vector3.DOWN
		),
		_quad(
			[
				Vector3(-h.x, -h.y, -h.z),
				Vector3(-h.x, -h.y, h.z),
				Vector3(-h.x, h.y, h.z),
				Vector3(-h.x, h.y, -h.z)
			],
			Vector3.LEFT
		),
		_quad(
			[
				Vector3(-h.x, h.y, -h.z),
				Vector3(-h.x, h.y, h.z),
				Vector3(h.x, -h.y, h.z),
				Vector3(h.x, -h.y, -h.z)
			],
			Vector3(h.y, h.x, 0).normalized()
		),
		_quad(
			[Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z)],
			Vector3.BACK
		),
		_quad(
			[Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z)],
			Vector3.FORWARD
		),
	]


func _centroid(faces: Array) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for face in faces:
		for v in face.local_verts:
			total += v
			count += 1
	return total / float(count) if count > 0 else Vector3.ZERO


## Signed volume by the divergence theorem. Sign follows winding, so the
## magnitude is the volume and the sign is a winding check in its own right.
func _volume(faces: Array) -> float:
	var origin := _centroid(faces)
	var total := 0.0
	for face in faces:
		var verts: PackedVector3Array = face.local_verts
		for i in range(1, verts.size() - 1):
			var a: Vector3 = verts[0] - origin
			var b: Vector3 = verts[i] - origin
			var c: Vector3 = verts[i + 1] - origin
			total += a.dot(b.cross(c)) / 6.0
	return absf(total)


## Fraction of faces wound clockwise as seen from outside the solid.
func _outward_ratio(faces: Array) -> float:
	if faces.is_empty():
		return -1.0
	var centre := _centroid(faces)
	var outward := 0
	var counted := 0
	for face in faces:
		var verts: PackedVector3Array = face.local_verts
		if verts.size() < 3:
			continue
		var a: Vector3 = verts[0]
		var normal: Vector3 = (verts[2] - a).cross(verts[1] - a)
		if normal.length() < 0.000001:
			continue
		var to_face: Vector3 = _face_centre(face) - centre
		if to_face.length() < 0.000001:
			continue
		counted += 1
		if normal.normalized().dot(to_face.normalized()) > 0.0:
			outward += 1
	return float(outward) / float(counted) if counted > 0 else -1.0


func _face_centre(face) -> Vector3:
	var total := Vector3.ZERO
	for v in face.local_verts:
		total += v
	return total / float(face.local_verts.size())


func _key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 100.0), roundi(point.y * 100.0), roundi(point.z * 100.0)]


## Every edge of a closed solid is shared by exactly two faces.
func _open_edge_count(faces: Array) -> int:
	var counts := {}
	for face in faces:
		var verts: PackedVector3Array = face.local_verts
		var n := verts.size()
		for i in n:
			var a := _key(verts[i])
			var b := _key(verts[(i + 1) % n])
			var edge: String = a + "|" + b if a < b else b + "|" + a
			counts[edge] = int(counts.get(edge, 0)) + 1
	var open := 0
	for edge in counts:
		if counts[edge] != 2:
			open += 1
	return open


# ===========================================================================
# Controls — if these fail, nothing below proves anything
# ===========================================================================


func test_the_box_fixture_is_closed_and_wound_outward():
	var faces := _box_faces(Vector3(32, 32, 32))
	assert_eq(_open_edge_count(faces), 0, "the fixture box must be closed")
	assert_almost_eq(_outward_ratio(faces), 1.0, 0.0001, "the fixture box must face outward")


func test_the_wedge_fixture_is_closed_and_wound_outward():
	var faces := _wedge_faces(Vector3(32, 32, 32))
	assert_eq(_open_edge_count(faces), 0, "the fixture wedge must be closed")
	assert_almost_eq(_outward_ratio(faces), 1.0, 0.0001, "the fixture wedge must face outward")


func test_the_box_fixture_has_the_volume_it_claims():
	assert_almost_eq(_volume(_box_faces(Vector3(32, 16, 8))), 32.0 * 16.0 * 8.0, 1.0)


# ===========================================================================
# Splitting a box
# ===========================================================================


func test_a_box_split_down_the_middle_gives_two_halves():
	var result = HFConvexClipScript.split(
		_box_faces(Vector3(32, 32, 32)), Plane(Vector3.RIGHT, 0.0)
	)
	assert_eq(result["front"].size(), 6, "front half of a box is still six faces")
	assert_eq(result["back"].size(), 6, "back half of a box is still six faces")


func test_the_two_halves_volumes_sum_to_the_original():
	var faces := _box_faces(Vector3(32, 16, 8))
	var whole := _volume(faces)
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 4.0))
	var sum: float = _volume(result["front"]) + _volume(result["back"])
	assert_almost_eq(sum, whole, 1.0, "a cut must not create or destroy volume")


func test_both_halves_are_closed():
	var result = HFConvexClipScript.split(
		_box_faces(Vector3(32, 32, 32)), Plane(Vector3.RIGHT, 4.0)
	)
	assert_eq(_open_edge_count(result["front"]), 0, "front half has an open edge")
	assert_eq(_open_edge_count(result["back"]), 0, "back half has an open edge")


func test_both_halves_are_wound_outward():
	var result = HFConvexClipScript.split(
		_box_faces(Vector3(32, 32, 32)), Plane(Vector3.RIGHT, 4.0)
	)
	assert_almost_eq(
		_outward_ratio(result["front"]), 1.0, 0.0001, "front half would bake inside out"
	)
	assert_almost_eq(_outward_ratio(result["back"]), 1.0, 0.0001, "back half would bake inside out")


func test_an_off_centre_cut_splits_the_volume_where_asked():
	var faces := _box_faces(Vector3(32, 32, 32))
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 8.0))
	# The plane sits 8 units along +X, so the front slab is 8 thick and the back 24.
	assert_almost_eq(_volume(result["front"]), 8.0 * 32.0 * 32.0, 1.0)
	assert_almost_eq(_volume(result["back"]), 24.0 * 32.0 * 32.0, 1.0)


# ===========================================================================
# Arbitrary planes
# ===========================================================================


func test_a_diagonal_cut_produces_two_closed_solids():
	var faces := _box_faces(Vector3(32, 32, 32))
	var result = HFConvexClipScript.split(faces, Plane(Vector3(1, 1, 0).normalized(), 0.0))
	assert_gt(result["front"].size(), 3)
	assert_gt(result["back"].size(), 3)
	assert_eq(_open_edge_count(result["front"]), 0, "diagonal front half has an open edge")
	assert_eq(_open_edge_count(result["back"]), 0, "diagonal back half has an open edge")
	assert_almost_eq(_outward_ratio(result["front"]), 1.0, 0.0001)
	assert_almost_eq(_outward_ratio(result["back"]), 1.0, 0.0001)


func test_a_corner_to_corner_cut_halves_the_volume():
	var faces := _box_faces(Vector3(32, 32, 32))
	var whole := _volume(faces)
	var result = HFConvexClipScript.split(faces, Plane(Vector3(1, 1, 0).normalized(), 0.0))
	assert_almost_eq(_volume(result["front"]), whole * 0.5, 1.0)
	assert_almost_eq(_volume(result["back"]), whole * 0.5, 1.0)


func test_an_arbitrary_angled_cut_conserves_volume():
	var faces := _box_faces(Vector3(48, 24, 16))
	var whole := _volume(faces)
	var plane := Plane(Vector3(0.4, 0.7, -0.3).normalized(), 2.0)
	var result = HFConvexClipScript.split(faces, plane)
	var sum: float = _volume(result["front"]) + _volume(result["back"])
	assert_almost_eq(sum, whole, 1.0)
	assert_eq(_open_edge_count(result["front"]), 0)
	assert_eq(_open_edge_count(result["back"]), 0)


func test_a_wedge_splits_cleanly():
	var faces := _wedge_faces(Vector3(32, 32, 32))
	var whole := _volume(faces)
	var result = HFConvexClipScript.split(faces, Plane(Vector3.BACK, 0.0))
	var sum: float = _volume(result["front"]) + _volume(result["back"])
	assert_almost_eq(sum, whole, 1.0, "an asymmetric solid must still conserve volume")
	assert_almost_eq(_outward_ratio(result["front"]), 1.0, 0.0001)
	assert_almost_eq(_outward_ratio(result["back"]), 1.0, 0.0001)


# ===========================================================================
# Planes that do not cut
# ===========================================================================


func test_a_plane_that_misses_leaves_the_solid_whole_in_front():
	var faces := _box_faces(Vector3(32, 32, 32))
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, -100.0))
	assert_eq(result["back"].size(), 0, "nothing is behind a plane the solid clears")
	assert_eq(result["front"].size(), 6)


func test_a_plane_that_misses_leaves_the_solid_whole_behind():
	var faces := _box_faces(Vector3(32, 32, 32))
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 100.0))
	assert_eq(result["front"].size(), 0)
	assert_eq(result["back"].size(), 6)


func test_a_plane_lying_on_a_face_does_not_shave_a_sliver():
	var faces := _box_faces(Vector3(32, 32, 32))
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 16.0))
	assert_eq(result["front"].size(), 0, "a plane on the surface has nothing in front of it")
	assert_eq(result["back"].size(), 6, "the solid stays whole")


func test_an_empty_face_set_returns_empty_halves():
	var result = HFConvexClipScript.split([], Plane(Vector3.RIGHT, 0.0))
	assert_eq(result["front"].size(), 0)
	assert_eq(result["back"].size(), 0)


func test_a_grazing_cut_is_dropped_rather_than_emitted_as_a_sliver():
	# A plane a hair inside the +X face leaves too little to bound a volume.
	var faces := _box_faces(Vector3(32, 32, 32))
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 16.0 - 0.0005))
	assert_eq(result["front"].size(), 0, "a sub-epsilon shaving must not become a brush")


# ===========================================================================
# The cap
# ===========================================================================


func test_the_cut_surface_is_added_to_both_halves():
	var faces := _box_faces(Vector3(32, 32, 32))
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 0.0))
	# A face counts as the cut surface only if *every* vertex is on the plane;
	# the four side faces each touch it with two.
	var front_caps := _count_on_plane(result["front"])
	var back_caps := _count_on_plane(result["back"])
	assert_eq(front_caps, 1, "the front half needs exactly one cut surface")
	assert_eq(back_caps, 1, "the back half needs exactly one cut surface")


func test_the_two_caps_are_wound_in_opposite_directions():
	var faces := _box_faces(Vector3(32, 32, 32))
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 0.0))
	var front_cap = _cap_of(result["front"])
	var back_cap = _cap_of(result["back"])
	assert_not_null(front_cap)
	assert_not_null(back_cap)
	var front_normal := _computed_normal(front_cap)
	var back_normal := _computed_normal(back_cap)
	assert_almost_eq(front_normal.dot(back_normal), -1.0, 0.001, "the caps must face each other")
	assert_almost_eq(front_normal.dot(Vector3.LEFT), 1.0, 0.001, "the front cap faces -X")


func _count_on_plane(faces: Array) -> int:
	var found := 0
	for face in faces:
		var all_on := true
		for v in face.local_verts:
			if absf(v.x) > EPS:
				all_on = false
				break
		if all_on:
			found += 1
	return found


func _cap_of(faces: Array):
	for face in faces:
		var on_plane := true
		for v in face.local_verts:
			if absf(v.x) > EPS:
				on_plane = false
				break
		if on_plane:
			return face
	return null


func _computed_normal(face) -> Vector3:
	var a: Vector3 = face.local_verts[0]
	return (face.local_verts[2] - a).cross(face.local_verts[1] - a).normalized()


func test_the_cap_is_planar():
	var faces := _box_faces(Vector3(32, 32, 32))
	var result = HFConvexClipScript.split(faces, Plane(Vector3(1, 1, 0).normalized(), 0.0))
	var plane := Plane(Vector3(1, 1, 0).normalized(), 0.0)
	for face in result["front"]:
		var all_on := true
		for v in face.local_verts:
			if absf(plane.distance_to(v)) > EPS:
				all_on = false
				break
		if all_on:
			assert_eq(face.local_verts.size(), 4, "a box cut diagonally caps with a quad")
			return
	fail_test("no cap face found on the diagonal cut")


# ===========================================================================
# Face data carried through the cut
# ===========================================================================


func test_a_whole_face_keeps_its_material_and_uv_settings():
	var faces := _box_faces(Vector3(32, 32, 32))
	faces[0].material_idx = 7
	faces[0].uv_scale = Vector2(2.0, 3.0)
	faces[0].uv_offset = Vector2(5.0, 6.0)
	faces[0].uv_rotation = 0.5
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 4.0))
	var found := false
	for face in result["front"]:
		if face.material_idx == 7:
			found = true
			assert_true(face.uv_scale.is_equal_approx(Vector2(2.0, 3.0)))
			assert_true(face.uv_offset.is_equal_approx(Vector2(5.0, 6.0)))
			assert_almost_eq(face.uv_rotation, 0.5, 0.0001)
	assert_true(found, "the +X face and its material belong to the front half")


func test_a_cut_face_keeps_its_material():
	var faces := _box_faces(Vector3(32, 32, 32))
	faces[2].material_idx = 9  # +Y, which the vertical cut below straddles
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 0.0))
	var front_has := false
	var back_has := false
	for face in result["front"]:
		if face.material_idx == 9:
			front_has = true
	for face in result["back"]:
		if face.material_idx == 9:
			back_has = true
	assert_true(front_has, "both sides of a split face keep the material")
	assert_true(back_has)


func test_custom_uvs_are_interpolated_along_the_cut():
	var faces := _box_faces(Vector3(32, 32, 32))
	# +Y face, four corners, UVs spanning the unit square.
	faces[2].custom_uvs = PackedVector2Array(
		[Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	)
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 0.0))
	for face in result["front"]:
		if face.local_verts.size() >= 3 and face.custom_uvs.size() == face.local_verts.size():
			for uv in face.custom_uvs:
				assert_between(uv.x, -0.001, 1.001, "an interpolated UV left the source range")
				assert_between(uv.y, -0.001, 1.001)
			return
	pass_test("no split face carried custom UVs, which is acceptable")


func test_the_cap_borrows_from_the_face_it_most_resembles():
	var faces := _box_faces(Vector3(32, 32, 32))
	for face in faces:
		face.material_idx = 1
	faces[1].material_idx = 4  # -X face, which the front cap faces
	var result = HFConvexClipScript.split(faces, Plane(Vector3.RIGHT, 0.0))
	var cap = _cap_of(result["front"])
	assert_not_null(cap)
	assert_eq(cap.material_idx, 4, "the front cap looks down -X, so it borrows the -X face")


# ===========================================================================
# sort_coplanar_cw
# ===========================================================================


func test_sort_coplanar_cw_winds_clockwise_from_outside():
	var square := PackedVector3Array(
		[
			Vector3(-1, 0, -1),
			Vector3(1, 0, 1),
			Vector3(-1, 0, 1),
			Vector3(1, 0, -1),
		]
	)
	var sorted: PackedVector3Array = HFConvexClipScript.sort_coplanar_cw(square, Vector3.UP)
	assert_eq(sorted.size(), 4)
	var a: Vector3 = sorted[0]
	var normal: Vector3 = (sorted[2] - a).cross(sorted[1] - a).normalized()
	assert_almost_eq(normal.dot(Vector3.UP), 1.0, 0.001, "the ring must face the normal given")


func test_sort_coplanar_cw_reverses_with_the_normal():
	var square := PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1)]
	)
	var up: PackedVector3Array = HFConvexClipScript.sort_coplanar_cw(square, Vector3.UP)
	var down: PackedVector3Array = HFConvexClipScript.sort_coplanar_cw(square, Vector3.DOWN)
	var a: Vector3 = down[0]
	var normal: Vector3 = (down[2] - a).cross(down[1] - a).normalized()
	assert_almost_eq(normal.dot(Vector3.DOWN), 1.0, 0.001)
	assert_eq(up.size(), down.size())


func test_sort_coplanar_cw_passes_short_rings_through():
	var pair := PackedVector3Array([Vector3.ZERO, Vector3.ONE])
	assert_eq(HFConvexClipScript.sort_coplanar_cw(pair, Vector3.UP).size(), 2)


func test_cap_polygon_deduplicates_repeated_crossings():
	var points := PackedVector3Array(
		[
			Vector3(-1, 0, -1),
			Vector3(-1, 0, -1),
			Vector3(1, 0, -1),
			Vector3(1, 0, 1),
			Vector3(-1, 0, 1),
			Vector3(-1, 0, 1),
		]
	)
	var ring: PackedVector3Array = HFConvexClipScript.cap_polygon(points, Vector3.UP)
	assert_eq(ring.size(), 4, "each corner appears once in the cut ring")


func test_cap_polygon_needs_three_distinct_points():
	var points := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	assert_eq(HFConvexClipScript.cap_polygon(points, Vector3.UP).size(), 0)


# ===========================================================================
# is_axis_aligned_box
# ===========================================================================


func test_a_box_is_recognised_as_a_box():
	var described: Dictionary = HFConvexClipScript.is_axis_aligned_box(
		_box_faces(Vector3(32, 16, 8))
	)
	assert_false(described.is_empty(), "a box must be recognised so it keeps its handles")
	assert_true(described["size"].is_equal_approx(Vector3(32, 16, 8)))
	assert_true(described["center"].is_equal_approx(Vector3.ZERO))


func test_an_offset_box_reports_its_centre():
	var described: Dictionary = HFConvexClipScript.is_axis_aligned_box(
		_box_faces(Vector3(16, 16, 16), Vector3(8, 0, -4))
	)
	assert_false(described.is_empty())
	assert_true(described["center"].is_equal_approx(Vector3(8, 0, -4)))


func test_a_half_box_from_a_real_cut_is_still_a_box():
	var result = HFConvexClipScript.split(
		_box_faces(Vector3(32, 32, 32)), Plane(Vector3.RIGHT, 0.0)
	)
	var described: Dictionary = HFConvexClipScript.is_axis_aligned_box(result["front"])
	assert_false(described.is_empty(), "half a box is a box")
	assert_true(described["size"].is_equal_approx(Vector3(16, 32, 32)))
	assert_true(described["center"].is_equal_approx(Vector3(8, 0, 0)))


func test_a_wedge_is_not_a_box():
	assert_true(
		HFConvexClipScript.is_axis_aligned_box(_wedge_faces(Vector3(32, 32, 32))).is_empty()
	)


func test_a_diagonally_cut_piece_is_not_a_box():
	var result = HFConvexClipScript.split(
		_box_faces(Vector3(32, 32, 32)), Plane(Vector3(1, 1, 0).normalized(), 0.0)
	)
	assert_true(HFConvexClipScript.is_axis_aligned_box(result["front"]).is_empty())


func test_a_face_set_of_the_wrong_size_is_not_a_box():
	var faces := _box_faces(Vector3(32, 32, 32))
	faces.remove_at(0)
	assert_true(HFConvexClipScript.is_axis_aligned_box(faces).is_empty())


# ===========================================================================
# clip_polygon on its own
# ===========================================================================


func test_clip_polygon_keeps_the_requested_side():
	var square := PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, -1)]
	)
	var front = HFConvexClipScript.clip_polygon(
		square, PackedVector2Array(), Plane(Vector3.RIGHT, 0.0), true
	)
	for v in front["verts"]:
		assert_gt(v.x, -EPS, "the front half must not reach behind the plane")


func test_clip_polygon_returns_nothing_for_a_polygon_entirely_behind():
	var square := PackedVector3Array(
		[Vector3(-2, 0, -1), Vector3(-2, 0, 1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]
	)
	var front = HFConvexClipScript.clip_polygon(
		square, PackedVector2Array(), Plane(Vector3.RIGHT, 0.0), true
	)
	assert_eq(front["verts"].size(), 0)


func test_clip_polygon_tolerates_a_degenerate_polygon():
	var line := PackedVector3Array([Vector3.ZERO, Vector3.ONE])
	var result = HFConvexClipScript.clip_polygon(
		line, PackedVector2Array(), Plane(Vector3.RIGHT, 0.0), true
	)
	assert_eq(result["verts"].size(), 0)
