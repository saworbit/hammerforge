extends GutTest

## HFArchBuilder: one description, one brush per voussoir.
##
## The assertions are about the properties every segment has to have — closed,
## convex, wound clockwise from outside, meeting its neighbour — rather than about
## specific vertex coordinates, which change with any reasonable ordering choice.

const HFArchBuilderScript = preload("res://addons/hammerforge/hf_arch_builder.gd")
const HFConvexClipScript = preload("res://addons/hammerforge/hf_convex_clip.gd")

const EPS := 0.001


func _settings(overrides: Dictionary = {}) -> Dictionary:
	var s: Dictionary = HFArchBuilderScript.default_settings()
	for key in overrides:
		s[key] = overrides[key]
	return s


func _centroid(faces: Array) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for face in faces:
		for v in face.local_verts:
			total += v
			count += 1
	return total / float(count) if count > 0 else Vector3.ZERO


func _key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 100.0), roundi(point.y * 100.0), roundi(point.z * 100.0)]


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
		var face_centre := Vector3.ZERO
		for v in verts:
			face_centre += v
		face_centre /= float(verts.size())
		var to_face: Vector3 = face_centre - centre
		if to_face.length() < 0.000001:
			continue
		counted += 1
		if normal.normalized().dot(to_face.normalized()) > 0.0:
			outward += 1
	return float(outward) / float(counted) if counted > 0 else -1.0


func _bounds(faces: Array) -> AABB:
	var bounds := AABB()
	var seeded := false
	for face in faces:
		for v in face.local_verts:
			if seeded:
				bounds = bounds.expand(v)
			else:
				bounds = AABB(v, Vector3.ZERO)
				seeded = true
	return bounds


# ===========================================================================
# Shape and count
# ===========================================================================


func test_the_segment_count_is_what_was_asked_for():
	assert_eq(HFArchBuilderScript.build(_settings({"segments": 8})).size(), 8)
	assert_eq(HFArchBuilderScript.build(_settings({"segments": 3})).size(), 3)


func test_every_segment_is_a_six_faced_wedge():
	for segment in HFArchBuilderScript.build(_settings()):
		assert_eq(segment.size(), 6, "a voussoir is bounded by six faces")


func test_every_segment_is_a_closed_solid():
	for segment in HFArchBuilderScript.build(_settings()):
		assert_eq(_open_edge_count(segment), 0, "a segment has an open edge")


func test_every_segment_faces_outward():
	for segment in HFArchBuilderScript.build(_settings()):
		assert_almost_eq(_outward_ratio(segment), 1.0, 0.0001, "a segment would bake inside out")


func test_a_full_ring_closes():
	var segments: Array = HFArchBuilderScript.build(
		_settings({"arc_degrees": 360.0, "segments": 12})
	)
	assert_eq(segments.size(), 12)
	for segment in segments:
		assert_eq(_open_edge_count(segment), 0)
		assert_almost_eq(_outward_ratio(segment), 1.0, 0.0001)


func test_neighbouring_segments_share_their_meeting_face():
	# The radial face at the end of one segment is the radial face at the start of
	# the next, or the arch has gaps in it.
	var segments: Array = HFArchBuilderScript.build(_settings({"segments": 4}))
	var first_keys := {}
	for face in segments[0]:
		for v in face.local_verts:
			first_keys[_key(v)] = true
	var shared := 0
	for face in segments[1]:
		var all_shared := true
		for v in face.local_verts:
			if not first_keys.has(_key(v)):
				all_shared = false
				break
		if all_shared:
			shared += 1
	assert_eq(shared, 1, "consecutive segments must share exactly one whole face")


# ===========================================================================
# Dimensions
# ===========================================================================


func test_a_half_arch_spans_the_diameter_and_stands_one_radius_tall():
	var segments: Array = HFArchBuilderScript.build(
		_settings({"radius": 128.0, "arc_degrees": 180.0, "segments": 16})
	)
	var bounds := AABB()
	var seeded := false
	for segment in segments:
		var segment_bounds := _bounds(segment)
		if seeded:
			bounds = bounds.merge(segment_bounds)
		else:
			bounds = segment_bounds
			seeded = true
	assert_almost_eq(bounds.size.x, 256.0, 1.0, "a half arch is two radii wide")
	assert_almost_eq(bounds.size.y, 128.0, 1.0, "and one radius tall")


func test_depth_is_respected():
	var segments: Array = HFArchBuilderScript.build(_settings({"depth": 48.0}))
	assert_almost_eq(_bounds(segments[0]).size.z, 48.0, EPS)


func test_the_opening_is_the_radius_less_the_wall_thickness():
	var segments: Array = HFArchBuilderScript.build(
		_settings({"radius": 100.0, "wall_thickness": 20.0, "arc_degrees": 360.0, "segments": 64})
	)
	var nearest := INF
	var furthest := 0.0
	for segment in segments:
		for face in segment:
			for v in face.local_verts:
				var distance := Vector2(v.x, v.y).length()
				nearest = minf(nearest, distance)
				furthest = maxf(furthest, distance)
	assert_almost_eq(furthest, 100.0, 0.5, "the outside sits on the radius")
	assert_almost_eq(nearest, 80.0, 0.5, "the opening is the radius less the thickness")


func test_the_start_angle_turns_the_arch():
	var flat: Array = HFArchBuilderScript.build(
		_settings({"arc_degrees": 90.0, "segments": 4, "start_degrees": 0.0})
	)
	var turned: Array = HFArchBuilderScript.build(
		_settings({"arc_degrees": 90.0, "segments": 4, "start_degrees": 90.0})
	)
	assert_gt(_centroid(flat[0]).x, 0.0, "an arch starting at zero degrees begins on +X")
	assert_gt(_centroid(turned[0]).y, 0.0, "a quarter turn later it begins on +Y")


func test_a_negative_arc_sweeps_the_other_way():
	var forward: Array = HFArchBuilderScript.build(_settings({"arc_degrees": 90.0, "segments": 4}))
	var backward: Array = HFArchBuilderScript.build(
		_settings({"arc_degrees": -90.0, "segments": 4})
	)
	assert_gt(_centroid(forward[3]).y, 0.0)
	assert_lt(_centroid(backward[3]).y, 0.0)
	for segment in backward:
		assert_almost_eq(
			_outward_ratio(segment), 1.0, 0.0001, "sweeping backwards must not invert the winding"
		)


# ===========================================================================
# Refusals
# ===========================================================================


func test_a_zero_segment_arch_is_refused():
	var result = HFArchBuilderScript.validate(_settings({"segments": 0}))
	assert_false(result.ok)
	assert_ne(result.fix_hint, "")
	assert_eq(HFArchBuilderScript.build(_settings({"segments": 0})).size(), 0)


func test_a_thickness_at_or_past_the_radius_is_refused():
	assert_false(
		HFArchBuilderScript.validate(_settings({"radius": 100.0, "wall_thickness": 100.0})).ok
	)
	assert_false(
		HFArchBuilderScript.validate(_settings({"radius": 100.0, "wall_thickness": 140.0})).ok
	)


func test_a_zero_radius_or_depth_is_refused():
	assert_false(HFArchBuilderScript.validate(_settings({"radius": 0.0})).ok)
	assert_false(HFArchBuilderScript.validate(_settings({"depth": 0.0})).ok)


func test_a_zero_arc_is_refused():
	assert_false(HFArchBuilderScript.validate(_settings({"arc_degrees": 0.0})).ok)


func test_more_than_a_full_turn_is_refused():
	assert_false(HFArchBuilderScript.validate(_settings({"arc_degrees": 400.0})).ok)


func test_a_segment_spanning_half_a_turn_is_refused():
	# A voussoir that wide is not convex, and every brush here is convex.
	var result = HFArchBuilderScript.validate(_settings({"arc_degrees": 360.0, "segments": 2}))
	assert_false(result.ok, "180 degrees per segment cannot be a convex brush")
	assert_true(result.fix_hint.contains("segments"), result.fix_hint)


func test_a_valid_arch_passes_validation():
	assert_true(HFArchBuilderScript.validate(_settings()).ok)


func test_settings_fall_back_to_the_defaults():
	var built: Array = HFArchBuilderScript.build({})
	assert_eq(built.size(), int(HFArchBuilderScript.default_settings()["segments"]))


func test_unknown_settings_keys_are_ignored():
	assert_true(HFArchBuilderScript.validate(_settings({"nonsense": 5})).ok)


# ===========================================================================
# The winding safeguard the generator relies on
# ===========================================================================


func test_orient_faces_outward_flips_only_what_points_inward():
	var builder := HFArchBuilderScript.build(_settings({"segments": 2, "arc_degrees": 90.0}))
	var segment: Array = builder[0]
	# Reverse one face deliberately, then let the safeguard put it back.
	var victim = segment[0]
	var reversed_verts := PackedVector3Array()
	for i in range(victim.local_verts.size() - 1, -1, -1):
		reversed_verts.append(victim.local_verts[i])
	victim.local_verts = reversed_verts
	victim.ensure_geometry()
	assert_lt(_outward_ratio(segment), 1.0, "the fixture must actually be broken first")
	HFConvexClipScript.orient_faces_outward(segment, HFConvexClipScript.interior_point(segment))
	assert_almost_eq(_outward_ratio(segment), 1.0, 0.0001, "the safeguard must repair it")
