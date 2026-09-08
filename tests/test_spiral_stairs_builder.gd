extends GutTest

## HFSpiralStairsBuilder: a tread is an annular wedge, not a copied box.
##
## The point of computing a tread rather than arraying one is that a tread is the
## shape the radius makes it. These assertions check the shape, the climb, and the
## refusals that keep a tread convex.

const HFSpiralStairsBuilderScript = preload("res://addons/hammerforge/hf_spiral_stairs_builder.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")

const EPS := 0.001


func _settings(overrides: Dictionary = {}) -> Dictionary:
	var s: Dictionary = HFSpiralStairsBuilderScript.default_settings()
	for key in overrides:
		s[key] = overrides[key]
	return s


func _treads(overrides: Dictionary = {}) -> Array:
	var settings := _settings(overrides)
	settings["center_post"] = false
	return HFSpiralStairsBuilderScript.build(settings)


# ===========================================================================
# Shape and count
# ===========================================================================


func test_the_tread_count_is_what_was_asked_for():
	assert_eq(_treads({"steps": 12}).size(), 12)
	assert_eq(_treads({"steps": 1}).size(), 1)


func test_the_newel_post_is_one_more_piece():
	var without: int = _treads({"steps": 6}).size()
	var with_post: Array = HFSpiralStairsBuilderScript.build(
		_settings({"steps": 6, "center_post": true})
	)
	assert_eq(with_post.size(), without + 1, "the post is a piece of the structure")


func test_every_tread_is_a_closed_convex_solid_facing_outward():
	for tread in _treads():
		assert_eq(SolidChecks.describe_problem(tread), "", "a tread would not bake")


func test_the_newel_post_is_a_solid_too():
	var pieces: Array = HFSpiralStairsBuilderScript.build(_settings({"center_post": true}))
	var post: Array = pieces[pieces.size() - 1]
	assert_eq(SolidChecks.describe_problem(post), "", "the post would not bake")
	assert_eq(
		post.size(),
		HFSpiralStairsBuilderScript.POST_SIDES + 2,
		"a prism is its sides plus two ends"
	)


func test_treads_that_meet_at_the_axis_are_still_solids():
	# With no hole down the middle the inner corners collapse onto the axis, and
	# the general eight-corner case has to come back as the wedge that is there.
	for tread in _treads({"inner_radius": 0.0, "center_post": false}):
		assert_eq(SolidChecks.describe_problem(tread), "", "a tread meeting the axis is broken")
		assert_eq(tread.size(), 5, "a wedge is five faces, not six")


# ===========================================================================
# The dimensions it claims
# ===========================================================================


func test_the_flight_climbs_by_the_rise_each_tread():
	var treads: Array = _treads({"steps": 8, "rise": 20.0, "tread_thickness": 5.0})
	for i in range(1, treads.size()):
		var previous: AABB = SolidChecks.bounds(treads[i - 1])
		var current: AABB = SolidChecks.bounds(treads[i])
		assert_almost_eq(current.end.y - previous.end.y, 20.0, EPS, "tread %d is off" % i)


func test_the_treads_reach_the_radius_they_were_given():
	var treads: Array = _treads({"outer_radius": 200.0, "steps": 12, "degrees_per_step": 30.0})
	var box: AABB = SolidChecks.structure_bounds(treads)
	# Twelve treads of thirty degrees is a full turn, so the flight spans the
	# diameter in both horizontal directions.
	assert_almost_eq(box.size.x, 400.0, 0.5)
	assert_almost_eq(box.size.z, 400.0, 0.5)


func test_no_tread_reaches_inside_the_hole_down_the_middle():
	var treads: Array = _treads({"inner_radius": 40.0})
	for tread in treads:
		for face in tread:
			for v in face.local_verts:
				var radial := Vector2(v.x, v.z).length()
				assert_true(radial > 40.0 - EPS, "a tread reaches into the newel hole")


func test_the_flight_is_centred_on_its_own_origin_vertically():
	var box: AABB = SolidChecks.structure_bounds(
		HFSpiralStairsBuilderScript.build(_settings({"center_post": true}))
	)
	assert_almost_eq(box.get_center().y, 0.0, EPS)


func test_turning_the_other_way_mirrors_rather_than_breaks():
	var clockwise: Array = _treads({"degrees_per_step": -30.0})
	assert_eq(clockwise.size(), 12)
	for tread in clockwise:
		assert_eq(
			SolidChecks.describe_problem(tread), "", "a tread turning the other way is broken"
		)


func test_a_flat_fan_is_allowed_because_it_is_a_platform():
	var fan: Array = _treads({"rise": 0.0, "steps": 6})
	assert_eq(fan.size(), 6)
	var box: AABB = SolidChecks.structure_bounds(fan)
	assert_almost_eq(box.size.y, float(_settings()["tread_thickness"]), EPS)


# ===========================================================================
# Refusals
# ===========================================================================


func test_a_tread_turning_too_far_to_stay_convex_is_refused():
	var cap: float = HFSpiralStairsBuilderScript.MAX_STEP_DEGREES
	assert_true(HFSpiralStairsBuilderScript.validate(_settings({"degrees_per_step": cap})).ok)
	assert_false(
		HFSpiralStairsBuilderScript.validate(_settings({"degrees_per_step": cap + 1.0})).ok
	)


func test_treads_that_do_not_turn_are_refused():
	var result = HFSpiralStairsBuilderScript.validate(_settings({"degrees_per_step": 0.0}))
	assert_false(result.ok)
	assert_true(str(result.fix_hint).contains("30"), "the refusal must suggest a turn that works")


func test_an_inner_radius_that_swallows_the_tread_is_refused():
	assert_false(
		(
			HFSpiralStairsBuilderScript
			. validate(_settings({"outer_radius": 100.0, "inner_radius": 100.0}))
			. ok
		)
	)
	assert_true(
		(
			HFSpiralStairsBuilderScript
			. validate(_settings({"outer_radius": 100.0, "inner_radius": 99.0}))
			. ok
		)
	)


func test_a_post_with_nothing_to_occupy_is_refused_rather_than_skipped():
	# Silently dropping the post would leave the user pressing a checkbox that
	# does nothing.
	var result = HFSpiralStairsBuilderScript.validate(
		_settings({"center_post": true, "inner_radius": 0.0})
	)
	assert_false(result.ok)
	assert_true(str(result.fix_hint).contains("inner radius"), str(result.fix_hint))
	assert_true(
		(
			HFSpiralStairsBuilderScript
			. validate(_settings({"center_post": false, "inner_radius": 0.0}))
			. ok
		),
		"without a post, no radius is needed"
	)


func test_a_negative_rise_is_refused():
	assert_false(HFSpiralStairsBuilderScript.validate(_settings({"rise": -1.0})).ok)
	assert_true(HFSpiralStairsBuilderScript.validate(_settings({"rise": 0.0})).ok)


func test_a_refused_flight_builds_nothing():
	assert_eq(HFSpiralStairsBuilderScript.build(_settings({"steps": 0})).size(), 0)


# ===========================================================================
# Schema
# ===========================================================================


func test_the_schema_describes_exactly_the_settings_the_builder_uses():
	var schema: Array = HFSpiralStairsBuilderScript.settings_schema()
	var defaults: Dictionary = HFSpiralStairsBuilderScript.default_settings()
	assert_eq(schema.size(), defaults.size())
	for field in schema:
		assert_true(defaults.has(field["key"]), "%s is described but never used" % field["key"])
		assert_true(str(field.get("tooltip", "")) != "", "%s has no tooltip" % field["key"])


func test_the_defaults_build_a_staircase():
	assert_true(HFSpiralStairsBuilderScript.validate({}).ok)
	assert_eq(HFSpiralStairsBuilderScript.build({}).size(), 13, "twelve treads and a post")
