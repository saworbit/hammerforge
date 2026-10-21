extends GutTest

## HFRingBuilder: a tube polygon swept round an axis, one brush per segment (#1443).
##
## The construction claim is that joining the tube polygon at one angle to the
## same polygon at the next gives flat sides and a convex piece. If it did not, the
## ring would look right in the editor and bake into folded rubbish, so it is
## measured: every face planar, every piece closed, convex and facing outward.

const HFRingBuilderScript = preload("res://addons/hammerforge/hf_ring_builder.gd")
const HFConvexClipScript = preload("res://addons/hammerforge/hf_convex_clip.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")

const EPS := 0.001


func _settings(overrides: Dictionary = {}) -> Dictionary:
	var s: Dictionary = HFRingBuilderScript.default_settings()
	for key in overrides:
		s[key] = overrides[key]
	return s


## The largest distance any of a face's corners sits off the plane of its first
## three.
func _worst_planarity(faces: Array) -> float:
	var worst := 0.0
	for face in faces:
		var verts: PackedVector3Array = face.local_verts
		if verts.size() < 4:
			continue
		var a: Vector3 = verts[0]
		var normal: Vector3 = (verts[1] - a).cross(verts[2] - a)
		if normal.length() < 0.000001:
			continue
		normal = normal.normalized()
		for v in verts:
			worst = maxf(worst, absf(normal.dot(v - a)))
	return worst


## Whether every corner of `face` lies on the half plane through the axis at
## `degrees`.
func _on_angle(face, degrees: float) -> bool:
	var angle := deg_to_rad(degrees)
	var across := Vector3(-sin(angle), 0.0, cos(angle))
	var out := Vector3(cos(angle), 0.0, sin(angle))
	for v in face.local_verts:
		if absf(across.dot(v)) > EPS or out.dot(v) <= 0.0:
			return false
	return true


func _faces_on_angle(piece: Array, degrees: float) -> int:
	var count := 0
	for face in piece:
		if _on_angle(face, degrees):
			count += 1
	return count


# ===========================================================================
# The construction claim
# ===========================================================================


func test_sixteen_by_eight_is_sixteen_convex_brushes():
	var pieces: Array = HFRingBuilderScript.build(
		_settings({"ring_segments": 16, "tube_segments": 8})
	)
	assert_eq(pieces.size(), 16, "one brush per ring segment")
	for piece in pieces:
		var interior: Vector3 = HFConvexClipScript.interior_point(piece)
		assert_true(HFConvexClipScript.is_convex_solid(piece, interior), "a piece is not convex")
		assert_eq(SolidChecks.describe_problem(piece), "", "a piece would not bake")


func test_every_face_of_every_piece_is_planar():
	for piece in HFRingBuilderScript.build(_settings({"ring_segments": 12, "tube_segments": 7})):
		assert_almost_eq(_worst_planarity(piece), 0.0, 0.001, "a piece face is warped")


func test_a_piece_has_two_faces_more_than_the_tube_has_sides():
	for sides in [3, 8, 32]:
		var pieces: Array = HFRingBuilderScript.build(_settings({"tube_segments": sides}))
		for piece in pieces:
			assert_eq(piece.size(), sides + 2, "a piece of a %d sided tube" % sides)
			assert_lte(piece.size(), HFConvexClipScript.MAX_BOOLEAN_PLANES)


func test_the_widest_piece_allowed_is_still_convex():
	# Two segments of 179 degrees, the most a piece may span, on the fattest tube.
	var pieces: Array = HFRingBuilderScript.build(
		_settings({"sweep_degrees": 358.0, "ring_segments": 2, "radius": 1.0, "tube_radius": 0.95})
	)
	assert_eq(pieces.size(), 2)
	for piece in pieces:
		var interior: Vector3 = HFConvexClipScript.interior_point(piece)
		assert_true(HFConvexClipScript.is_convex_solid(piece, interior))
		assert_eq(SolidChecks.describe_problem(piece), "")


func test_a_ring_swept_the_other_way_is_still_solids():
	var pieces: Array = HFRingBuilderScript.build(
		_settings({"sweep_degrees": -270.0, "ring_segments": 6})
	)
	assert_eq(pieces.size(), 6)
	for piece in pieces:
		assert_eq(SolidChecks.describe_problem(piece), "", "a reversed sweep broke a piece")


func test_neighbouring_pieces_share_their_meeting_face():
	var pieces: Array = HFRingBuilderScript.build(_settings({"ring_segments": 4}))
	var first_keys := {}
	for face in pieces[0]:
		for v in face.local_verts:
			first_keys[SolidChecks.key(v)] = true
	var shared := 0
	for face in pieces[1]:
		var all_shared := true
		for v in face.local_verts:
			if not first_keys.has(SolidChecks.key(v)):
				all_shared = false
				break
		if all_shared:
			shared += 1
	assert_eq(shared, 1, "consecutive pieces must share exactly one whole face")


# ===========================================================================
# The dimensions it claims
# ===========================================================================


func test_every_corner_lies_on_the_tube():
	var radius := 4.0
	var tube := 1.25
	var pieces: Array = HFRingBuilderScript.build(
		_settings({"radius": radius, "tube_radius": tube, "tube_segments": 9})
	)
	for piece in pieces:
		for face in piece:
			for v in face.local_verts:
				var out := Vector2(v.x, v.z).length()
				assert_almost_eq(Vector2(out - radius, v.y).length(), tube, EPS)


func test_a_quarter_ring_ends_on_its_start_and_end_angles():
	var pieces: Array = HFRingBuilderScript.build(
		_settings({"sweep_degrees": 90.0, "ring_segments": 4, "start_degrees": 0.0})
	)
	assert_eq(pieces.size(), 4)
	assert_eq(_faces_on_angle(pieces[0], 0.0), 1, "the first piece ends on zero degrees")
	assert_eq(_faces_on_angle(pieces[3], 90.0), 1, "the last piece ends on ninety")
	for piece in pieces:
		for face in piece:
			for v in face.local_verts:
				assert_gte(v.x, -EPS, "a quarter ring stays in its quarter")
				assert_gte(v.z, -EPS, "a quarter ring stays in its quarter")


func test_the_start_angle_turns_the_ring():
	var pieces: Array = HFRingBuilderScript.build(
		_settings({"sweep_degrees": 90.0, "ring_segments": 3, "start_degrees": 30.0})
	)
	assert_eq(_faces_on_angle(pieces[0], 30.0), 1, "it begins at the start angle")
	assert_eq(_faces_on_angle(pieces[2], 120.0), 1, "and ends a sweep later")


func test_the_ring_is_centred_on_its_own_origin():
	var box: AABB = SolidChecks.structure_bounds(HFRingBuilderScript.build(_settings()))
	assert_almost_eq(box.get_center().x, 0.0, EPS)
	assert_almost_eq(box.get_center().y, 0.0, EPS)
	assert_almost_eq(box.get_center().z, 0.0, EPS)


# ===========================================================================
# Refusals
# ===========================================================================


func test_a_tube_radius_at_or_past_the_radius_is_refused():
	for tube in [2.0, 2.5]:
		var settings := _settings({"radius": 2.0, "tube_radius": tube})
		var result = HFRingBuilderScript.validate(settings)
		assert_false(result.ok, "a tube radius of %s on a ring of 2" % tube)
		assert_ne(result.fix_hint, "")
		assert_eq(HFRingBuilderScript.build(settings).size(), 0, "and nothing is built")
	assert_true(HFRingBuilderScript.validate(_settings({"radius": 2.0, "tube_radius": 1.95})).ok)


func test_a_piece_of_half_a_turn_or_more_is_refused():
	var settings := _settings({"sweep_degrees": 360.0, "ring_segments": 2})
	var result = HFRingBuilderScript.validate(settings)
	assert_false(result.ok, "180 degrees per piece cannot be a convex brush")
	assert_true(result.fix_hint.contains("ring segments"), result.fix_hint)
	assert_eq(HFRingBuilderScript.build(settings).size(), 0)
	assert_false(
		HFRingBuilderScript.validate(_settings({"sweep_degrees": 200.0, "ring_segments": 1})).ok
	)
	assert_true(
		HFRingBuilderScript.validate(_settings({"sweep_degrees": 360.0, "ring_segments": 3})).ok
	)


func test_a_tube_outside_three_to_thirty_two_sides_is_refused():
	assert_false(HFRingBuilderScript.validate(_settings({"tube_segments": 2})).ok)
	assert_false(HFRingBuilderScript.validate(_settings({"tube_segments": 33})).ok)
	assert_true(HFRingBuilderScript.validate(_settings({"tube_segments": 3})).ok)
	assert_true(HFRingBuilderScript.validate(_settings({"tube_segments": 32})).ok)


func test_a_zero_or_more_than_full_sweep_is_refused():
	assert_false(HFRingBuilderScript.validate(_settings({"sweep_degrees": 0.0})).ok)
	assert_false(HFRingBuilderScript.validate(_settings({"sweep_degrees": 400.0})).ok)
	assert_false(HFRingBuilderScript.validate(_settings({"sweep_degrees": -400.0})).ok)


func test_a_zero_radius_tube_or_segment_count_is_refused():
	assert_false(HFRingBuilderScript.validate(_settings({"radius": 0.0})).ok)
	assert_false(HFRingBuilderScript.validate(_settings({"tube_radius": 0.0})).ok)
	assert_false(HFRingBuilderScript.validate(_settings({"ring_segments": 0})).ok)


func test_a_thin_tube_builds():
	# Its pieces are built from their faces and keep them at any size (#1603).
	assert_true(HFRingBuilderScript.validate(_settings({"tube_radius": 0.05})).ok)
	assert_true(
		HFRingBuilderScript.validate(_settings({"ring_segments": 3, "tube_radius": 0.06})).ok
	)


func test_a_piece_that_is_a_sliver_along_the_ring_is_refused_and_says_why():
	# 128 pieces round a ring of 0.1 are 0.007 along it.
	var settings := _settings({"radius": 0.1, "tube_radius": 0.05, "ring_segments": 128})
	var result = HFRingBuilderScript.validate(settings)
	assert_false(result.ok)
	assert_string_contains(str(result.message), "piece 0.0072 across is a sliver")
	assert_string_contains(str(result.fix_hint), "fewer Ring Segments")
	settings["radius"] = 0.2
	assert_true(HFRingBuilderScript.validate(settings).ok)


func test_a_piece_nearly_half_a_turn_is_a_sliver_and_asks_for_more_segments():
	var result = HFRingBuilderScript.validate(
		_settings({"ring_segments": 2, "sweep_degrees": 358.0})
	)
	assert_false(result.ok)
	assert_string_contains(str(result.message), "0.0081")
	assert_string_contains(str(result.fix_hint), "more Ring Segments")


func test_a_short_piece_of_a_square_tube_is_a_box_and_is_held_to_a_box_minimum():
	# Eight pieces of a four-sided tube in ten degrees: those near an axis are square
	# to it, so the brush system makes them box brushes, which it widens to 0.1 and
	# rebuilds at that size (#1605).
	var result = HFRingBuilderScript.validate(
		_settings(
			{"tube_segments": 4, "ring_segments": 8, "sweep_degrees": 10.0, "tube_radius": 0.05}
		)
	)
	assert_false(result.ok)
	assert_string_contains(str(result.message), "is a box 0.0662 across")
	assert_string_contains(str(result.fix_hint), "fewer Ring Segments")


# ===========================================================================
# Schema
# ===========================================================================


func test_the_schema_describes_exactly_the_settings_the_builder_uses():
	var schema: Array = HFRingBuilderScript.settings_schema()
	var defaults: Dictionary = HFRingBuilderScript.default_settings()
	assert_eq(schema.size(), defaults.size())
	for field in schema:
		assert_true(defaults.has(field["key"]), "%s is described but never used" % field["key"])
		assert_true(str(field.get("tooltip", "")) != "", "%s has no tooltip" % field["key"])


func test_the_tube_segment_field_offers_three_to_thirty_two():
	for field in HFRingBuilderScript.settings_schema():
		if field["key"] == "tube_segments":
			assert_eq(int(field["min"]), 3)
			assert_eq(int(field["max"]), 32)
			return
	fail_test("the schema has no tube_segments field")


func test_the_defaults_build_a_closed_ring():
	assert_true(HFRingBuilderScript.validate({}).ok)
	var pieces: Array = HFRingBuilderScript.build({})
	assert_eq(pieces.size(), int(HFRingBuilderScript.default_settings()["ring_segments"]))
	assert_eq(float(HFRingBuilderScript.default_settings()["sweep_degrees"]), 360.0)


# ===========================================================================
# On a level: refused before anything is built, Update and Detach
# ===========================================================================


func _level() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	# A face is painted by palette slot, so the palette needs one to name.
	root.add_material_to_palette(StandardMaterial3D.new())
	return root


func _only_generator(root: LevelRoot) -> String:
	assert_eq(root.generator_count(), 1, "one ring was built")
	return str(root.generator_system.generators.keys()[0])


func _pieces(root: LevelRoot, generator_id: String) -> Array:
	var out: Array = []
	for brush_id in root.generator_system.generator_for_id(generator_id).brush_ids:
		out.append(root.brush_system.find_brush_by_id(str(brush_id)))
	return out


func test_refused_settings_build_nothing_on_a_level():
	var root := _level()
	for bad in [{"tube_radius": 3.0}, {"sweep_degrees": 360.0, "ring_segments": 2}]:
		var result: HFOpResult = root.create_generator("ring", _settings(bad), Transform3D.IDENTITY)
		assert_false(result.ok, "%s is refused" % str(bad))
		assert_false(root.can_build_generator("ring", _settings(bad)).ok, "and the dock is told")
	assert_eq(root.generator_count(), 0, "no record is left")
	assert_eq(root._iter_managed_brush_nodes().size(), 0, "and no brush")


func test_changing_the_tube_radius_rebuilds_in_place_and_keeps_face_materials():
	var root := _level()
	var at := Transform3D(Basis.IDENTITY, Vector3(20, 4, -8))
	assert_true(root.create_generator("ring", _settings({"ring_segments": 8}), at).ok)
	var generator_id := _only_generator(root)
	var first: Array = _pieces(root, generator_id)
	var side := 4
	root.assign_material_to_faces_by_id(str(first[2].brush_id), [side], 0)
	first[2].faces[0].uv_scale = Vector2(2, 3)
	var whole := StandardMaterial3D.new()
	first[5].material_override = whole

	var thicker := _settings({"ring_segments": 8, "tube_radius": 0.8})
	assert_true(root.regenerate_generator(generator_id, thicker).ok)

	var rebuilt: Array = _pieces(root, generator_id)
	assert_eq(rebuilt.size(), 8, "the same pieces again")
	assert_eq(rebuilt[2].faces[side].material_idx, 0, "the painted side keeps its paint")
	assert_eq(rebuilt[2].faces[side + 1].material_idx, -1, "and its neighbour stays plain")
	assert_almost_eq(rebuilt[2].faces[0].uv_scale.y, 3.0, EPS, "an end face keeps its UVs")
	assert_eq(rebuilt[5].material_override, whole, "a piece keeps its whole-brush material")
	var box := AABB(rebuilt[0].global_position, Vector3.ZERO)
	for piece in rebuilt:
		box = box.expand(piece.global_position)
	assert_almost_eq(box.get_center().y, 4.0, 0.01, "rebuilt where it stood")
	assert_almost_eq(
		Vector2(box.get_center().x, box.get_center().z).distance_to(Vector2(20, -8)), 0.0, 0.01
	)


func test_changing_the_tube_sides_names_a_painted_piece_at_risk():
	var root := _level()
	assert_true(
		root.create_generator("ring", _settings({"ring_segments": 4}), Transform3D.IDENTITY).ok
	)
	var generator_id := _only_generator(root)
	var piece = _pieces(root, generator_id)[1]
	root.assign_material_to_faces_by_id(str(piece.brush_id), [3], 0)
	var at_risk: PackedStringArray = root.generator_appearance_at_risk(
		generator_id, _settings({"ring_segments": 4, "tube_segments": 12})
	)
	assert_eq(Array(at_risk), [str(piece.brush_id)], "its faces no longer line up one for one")


func test_a_piece_can_be_hollowed_and_carved_with_as_the_torus_brush_cannot():
	var root := _level()
	assert_true(
		root.create_generator("ring", _settings({"ring_segments": 8}), Transform3D.IDENTITY).ok
	)
	var piece = _pieces(root, _only_generator(root))[0]
	assert_true(root.can_hollow_brush(str(piece.brush_id), 0.1).ok, "Hollow takes a ring piece")
	root.create_brush_from_info(
		{"size": Vector3.ONE, "center": piece.global_position, "brush_id": "under_the_ring"}
	)
	assert_true(root.can_carve_brush(str(piece.brush_id)).ok, "and Carve takes one as a carver")


func test_detach_leaves_the_pieces_as_plain_brushes():
	var root := _level()
	assert_true(
		root.create_generator("ring", _settings({"ring_segments": 5}), Transform3D.IDENTITY).ok
	)
	var generator_id := _only_generator(root)
	var pieces: Array = _pieces(root, generator_id)
	assert_true(root.generator_system.detach(generator_id))
	assert_eq(root.generator_count(), 0, "the record is gone")
	for piece in pieces:
		assert_true(is_instance_valid(piece), "every piece is still there")
		assert_false(piece.has_meta(HFGeneratorSystemScript.GENERATOR_META), "and is nobody's")
