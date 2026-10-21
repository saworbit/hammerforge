extends GutTest

## HFSpiralStairsBuilder: a tread is an annular wedge, not a copied box.
##
## The point of computing a tread rather than arraying one is that a tread is the
## shape the radius makes it. These assertions check the shape, the climb, and the
## refusals that keep a tread convex.

const HFSpiralStairsBuilderScript = preload("res://addons/hammerforge/hf_spiral_stairs_builder.gd")
const HFBrushSystemScript = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
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
	# A hole wide enough to be worth checking against the default outer radius,
	# which is metres now (#625) rather than the 128 units it used to be. An inner
	# radius past the outer one is refused, and `build()` returns nothing when it
	# is, so the old 40.0 left this test walking an empty array and asserting
	# nothing at all.
	var inner := 0.8
	var treads: Array = _treads({"inner_radius": inner})
	assert_false(treads.is_empty(), "the flight builds, so there is something to check")
	for tread in treads:
		for face in tread:
			for v in face.local_verts:
				var radial := Vector2(v.x, v.z).length()
				assert_true(radial > inner - EPS, "a tread reaches into the newel hole")


func test_the_flight_is_centred_on_its_own_origin_vertically():
	var box: AABB = SolidChecks.structure_bounds(
		HFSpiralStairsBuilderScript.build(_settings({"center_post": true}))
	)
	assert_almost_eq(box.get_center().y, 0.0, EPS)


func test_a_postless_flight_is_centred_too():
	# The post used to fill the gap under the first tread and hide the fact that
	# the treads alone were centred on the climb rather than on themselves.
	var box: AABB = SolidChecks.structure_bounds(
		HFSpiralStairsBuilderScript.build(_settings({"center_post": false}))
	)
	assert_almost_eq(box.get_center().y, 0.0, EPS, "a postless spiral sat above its origin")


func test_a_postless_flight_stays_centred_at_other_rises_and_thicknesses():
	for overrides in [
		{"center_post": false, "rise": 24.0, "tread_thickness": 4.0},
		{"center_post": false, "rise": 12.0, "tread_thickness": 12.0},
		{"center_post": false, "rise": 10.0, "tread_thickness": 20.0, "steps": 6},
	]:
		var box: AABB = SolidChecks.structure_bounds(
			HFSpiralStairsBuilderScript.build(_settings(overrides))
		)
		assert_almost_eq(box.get_center().y, 0.0, EPS, "off centre for %s" % overrides)


func test_a_flight_with_a_post_stays_centred_at_other_rises_and_thicknesses():
	for overrides in [
		{"center_post": true, "rise": 24.0, "tread_thickness": 4.0},
		{"center_post": true, "rise": 10.0, "tread_thickness": 20.0, "steps": 6},
	]:
		var box: AABB = SolidChecks.structure_bounds(
			HFSpiralStairsBuilderScript.build(_settings(overrides))
		)
		assert_almost_eq(box.get_center().y, 0.0, EPS, "off centre for %s" % overrides)


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
	# Twenty metres out, so a tread at the cap is wide enough to be a brush (#1582).
	var cap: float = HFSpiralStairsBuilderScript.MAX_STEP_DEGREES
	var settings := _settings({"degrees_per_step": cap, "outer_radius": 20.0})
	assert_true(HFSpiralStairsBuilderScript.validate(settings).ok)
	settings["degrees_per_step"] = cap + 1.0
	var result = HFSpiralStairsBuilderScript.validate(settings)
	assert_false(result.ok)
	assert_string_contains(str(result.message), "not convex")


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
# No piece thinner than a brush can be (#1582)
# ===========================================================================


## The values worth trying in a float field: its two ends, and one step either
## side of zero where it reaches that far, as a Turn of a degree does.
func _probes(field: Dictionary) -> Array:
	var low := float(field["min"])
	var high := float(field["max"])
	var out: Array = [low, high]
	for value in [float(field["step"]), -float(field["step"])]:
		if value >= low and value <= high:
			out.append(value)
	return out


## How far a size read off float corners this far from the origin can be out. A
## Rise of 1024 puts the top tread six kilometres up, where a float is good to
## about a thousandth.
func _float_slack(box: AABB) -> float:
	var far := maxf(box.position.abs()[box.position.abs().max_axis_index()], 1.0)
	far = maxf(far, box.end.abs()[box.end.abs().max_axis_index()])
	return far * 0.000001


func test_no_setting_the_fields_accept_builds_a_piece_thinner_than_a_brush():
	var smallest: float = HFBrushSystemScript.MIN_BRUSH_EXTENT
	for field: Dictionary in HFSpiralStairsBuilderScript.settings_schema():
		if str(field["type"]) != "float":
			continue
		for value in _probes(field):
			for post in [false, true]:
				for collision in [0, 1]:
					var settings := _settings(
						{field["key"]: value, "center_post": post, "collision": collision}
					)
					var what := (
						"%s = %s, post %s, collision %d" % [field["key"], value, post, collision]
					)
					var check = HFGeneratorSystemScript.can_build("spiral_stairs", settings)
					if not check.ok:
						assert_ne(str(check.message), "", "%s: a refusal says why" % what)
						continue
					for piece in HFGeneratorSystemScript.build_faces("spiral_stairs", settings):
						var box: AABB = SolidChecks.bounds(piece)
						var size := box.size
						assert_true(
							size[size.min_axis_index()] >= smallest - _float_slack(box),
							"%s: a piece %s" % [what, size]
						)


func test_the_thinnest_piece_is_the_brush_minimum():
	assert_eq(HFSpiralStairsBuilderScript.MIN_PIECE, HFBrushSystemScript.MIN_BRUSH_EXTENT)


func test_a_tread_too_narrow_across_is_refused_and_says_why():
	# Two metres out, a degree of turn is a tread 0.035 across.
	var result = HFSpiralStairsBuilderScript.validate(_settings({"degrees_per_step": 1.0}))
	assert_false(result.ok)
	assert_string_contains(str(result.message), "thinner than a brush can be")
	assert_true(HFSpiralStairsBuilderScript.validate(_settings({"degrees_per_step": 3.0})).ok)


func test_a_tread_turning_nearly_half_a_turn_is_a_sliver_and_is_refused():
	# Its corners are all there is to it, so at 179 degrees the two ends lie almost
	# along one line and the tread between them is 0.015 deep.
	assert_false(HFSpiralStairsBuilderScript.validate(_settings({"degrees_per_step": 179.0})).ok)


func test_a_newel_post_too_thin_is_refused_and_says_why():
	var result = HFSpiralStairsBuilderScript.validate(
		_settings({"center_post": true, "inner_radius": 0.03})
	)
	assert_false(result.ok)
	assert_string_contains(str(result.message), "newel post")
	assert_string_contains(str(result.fix_hint), "post off")
	assert_true(
		(
			HFSpiralStairsBuilderScript
			. validate(_settings({"center_post": true, "inner_radius": 0.06}))
			. ok
		)
	)


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


# ===========================================================================
# Ramp collision (#1416)
# ===========================================================================


func test_steps_collision_lays_no_ramp():
	assert_eq(HFSpiralStairsBuilderScript.ramp_collision(_settings()), {})


func test_a_ramp_is_a_sloped_piece_per_tread_and_a_flat_one_over_the_top():
	var settings := _settings({"collision": 1, "steps": 6})
	var ramp: Dictionary = HFSpiralStairsBuilderScript.ramp_collision(settings)
	assert_eq(ramp["pieces"].size(), 7, "six slopes up to the six treads, then the top one flat")
	assert_eq(Array(ramp["covers"]), range(6), "every tread, and not the newel post")
	var pieces: Array = HFSpiralStairsBuilderScript.build(settings)
	for k in 6:
		var tread: AABB = SolidChecks.bounds(pieces[k])
		var slope := _bounds(ramp["pieces"][k])
		assert_almost_eq(slope.end.y, tread.end.y, EPS, "slope %d rises to its tread's top" % k)
		assert_almost_eq(slope.end.y - _start_height(ramp["pieces"][k]), 0.2, EPS, "a riser")
	var top := _bounds(ramp["pieces"][6])
	assert_almost_eq(top.end.y, SolidChecks.bounds(pieces[5]).end.y, EPS, "flat at the top tread")
	assert_almost_eq(_start_height(ramp["pieces"][6]), top.end.y, EPS, "flat")


func test_the_first_slope_starts_on_the_floor():
	var settings := _settings({"collision": 1})
	var ramp: Dictionary = HFSpiralStairsBuilderScript.ramp_collision(settings)
	var first_tread: AABB = SolidChecks.bounds(HFSpiralStairsBuilderScript.build(settings)[0])
	assert_almost_eq(
		_bounds(ramp["pieces"][0]).position.y, first_tread.end.y - 0.2, EPS, "a riser below"
	)


func test_neighbouring_pieces_meet_at_the_same_height():
	for overrides in [{}, {"degrees_per_step": -45.0, "inner_radius": 0.0, "center_post": false}]:
		var settings := _settings({"collision": 1})
		settings.merge(overrides, true)
		var pieces: Array = HFSpiralStairsBuilderScript.ramp_collision(settings)["pieces"]
		for k in range(1, pieces.size()):
			# Each top corner where this piece ends is a top corner the next one starts
			# from, at the same height.
			var ends := _highest(pieces[k - 1])
			var met := 0
			for end in ends:
				for start in pieces[k]:
					var beside := Vector2(start.x, start.z).distance_to(Vector2(end.x, end.z))
					if beside <= EPS and absf(start.y - end.y) <= EPS:
						met += 1
						break
			assert_gt(ends.size(), 0)
			assert_eq(met, ends.size(), "%s: piece %d starts where %d ends" % [overrides, k, k - 1])


func test_the_slope_is_measured_along_the_walking_line():
	var ramp: Dictionary = HFSpiralStairsBuilderScript.ramp_collision(
		_settings(
			{
				"collision": 1,
				"outer_radius": 2.0,
				"inner_radius": 0.5,
				"degrees_per_step": 20.0,
				"rise": 0.2
			}
		)
	)
	var walking := 1.25 * deg_to_rad(20.0)
	assert_almost_eq(float(ramp["slope_degrees"]), rad_to_deg(atan2(0.2, walking)), 0.0001)


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


## How high a piece's top starts: its lowest top corner, the near end of its slope.
func _start_height(points: PackedVector3Array) -> float:
	var tops: Array = []
	for p in points:
		tops.append(p.y)
	tops.sort()
	# Each corner of the span is written as a top and a bottom: the upper half are tops.
	return tops[tops.size() / 2]


## Every point at a piece's greatest height.
func _highest(points: PackedVector3Array) -> Array:
	var top := _bounds(points).end.y
	var out: Array = []
	for p in points:
		if absf(p.y - top) <= EPS:
			out.append(p)
	return out
