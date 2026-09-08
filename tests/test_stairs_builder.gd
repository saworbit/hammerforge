extends GutTest

## HFStairsBuilder: one description, one brush per step.
##
## The assertions are about the properties a flight has to have — the right number
## of steps, each one a closed convex solid facing outward, each one exactly a
## tread further on and a rise higher than the last — rather than about particular
## coordinates, which any reasonable ordering choice would change.

const HFStairsBuilderScript = preload("res://addons/hammerforge/hf_stairs_builder.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")

const EPS := 0.001


func _settings(overrides: Dictionary = {}) -> Dictionary:
	var s: Dictionary = HFStairsBuilderScript.default_settings()
	for key in overrides:
		s[key] = overrides[key]
	return s


# ===========================================================================
# Shape and count
# ===========================================================================


func test_the_step_count_is_what_was_asked_for():
	assert_eq(HFStairsBuilderScript.build(_settings({"steps": 8})).size(), 8)
	assert_eq(HFStairsBuilderScript.build(_settings({"steps": 1})).size(), 1)
	assert_eq(HFStairsBuilderScript.build(_settings({"steps": 24})).size(), 24)


func test_every_step_is_a_closed_convex_solid_facing_outward():
	for step in HFStairsBuilderScript.build(_settings()):
		assert_eq(SolidChecks.describe_problem(step), "", "a step would not bake")


func test_every_step_is_a_six_faced_box():
	for step in HFStairsBuilderScript.build(_settings()):
		assert_eq(step.size(), 6, "a step is bounded by six faces")


func test_open_treads_are_solids_too():
	var flight: Array = HFStairsBuilderScript.build(_settings({"fill": 1}))
	assert_eq(flight.size(), 8)
	for step in flight:
		assert_eq(SolidChecks.describe_problem(step), "", "a floating tread would not bake")


# ===========================================================================
# The dimensions it claims
# ===========================================================================


func test_the_flight_spans_the_climb_and_the_run_it_was_given():
	var flight: Array = HFStairsBuilderScript.build(
		_settings({"steps": 10, "rise": 16.0, "tread": 32.0, "width": 96.0})
	)
	var box: AABB = SolidChecks.structure_bounds(flight)
	assert_almost_eq(box.size.y, 160.0, EPS, "ten steps of 16 is a 160 climb")
	assert_almost_eq(box.size.z, 320.0, EPS, "ten steps of 32 is a 320 run")
	assert_almost_eq(box.size.x, 96.0, EPS, "the flight is as wide as it was told to be")


func test_the_flight_is_centred_on_its_own_origin():
	# Every other generator is, so placing one on a selection puts the middle of
	# the structure where the user was looking rather than a corner of it.
	var box: AABB = SolidChecks.structure_bounds(HFStairsBuilderScript.build(_settings()))
	var centre: Vector3 = box.get_center()
	assert_almost_eq(centre.x, 0.0, EPS)
	assert_almost_eq(centre.y, 0.0, EPS)
	assert_almost_eq(centre.z, 0.0, EPS)


func test_each_step_is_exactly_one_tread_on_and_one_rise_up():
	var flight: Array = HFStairsBuilderScript.build(
		_settings({"steps": 6, "rise": 12.0, "tread": 40.0})
	)
	for i in range(1, flight.size()):
		var previous: AABB = SolidChecks.bounds(flight[i - 1])
		var current: AABB = SolidChecks.bounds(flight[i])
		assert_almost_eq(
			current.position.z - previous.position.z, 40.0, EPS, "step %d is off in run" % i
		)
		assert_almost_eq(current.end.y - previous.end.y, 12.0, EPS, "step %d is off in rise" % i)


func test_a_solid_flight_reaches_the_floor_under_every_step():
	var flight: Array = HFStairsBuilderScript.build(_settings({"steps": 5, "fill": 0}))
	var base: float = SolidChecks.structure_bounds(flight).position.y
	for step in flight:
		assert_almost_eq(SolidChecks.bounds(step).position.y, base, EPS, "a solid step floats")


func test_an_open_flight_is_slabs_of_the_thickness_asked_for():
	var flight: Array = HFStairsBuilderScript.build(
		_settings({"steps": 5, "fill": 1, "tread_thickness": 6.0})
	)
	for step in flight:
		assert_almost_eq(SolidChecks.bounds(step).size.y, 6.0, EPS, "a tread is the wrong depth")


func test_steps_meet_their_neighbour_rather_than_leaving_a_gap():
	var flight: Array = HFStairsBuilderScript.build(_settings({"steps": 4, "tread": 32.0}))
	for i in range(1, flight.size()):
		var previous: AABB = SolidChecks.bounds(flight[i - 1])
		var current: AABB = SolidChecks.bounds(flight[i])
		assert_almost_eq(current.position.z, previous.end.z, EPS, "a gap between steps")


# ===========================================================================
# Refusals — each on its own boundary, and not one step inside it
# ===========================================================================


func test_a_flight_of_no_steps_is_refused():
	assert_false(HFStairsBuilderScript.validate(_settings({"steps": 0})).ok)
	assert_true(HFStairsBuilderScript.validate(_settings({"steps": 1})).ok)


func test_a_flight_longer_than_the_cap_is_refused_and_says_the_cap():
	var cap: int = HFStairsBuilderScript.MAX_STEPS
	assert_true(HFStairsBuilderScript.validate(_settings({"steps": cap})).ok)
	var result = HFStairsBuilderScript.validate(_settings({"steps": cap + 1}))
	assert_false(result.ok)
	assert_true(str(result.fix_hint).contains(str(cap)), "the refusal must name the cap")


func test_a_flight_with_no_size_is_refused():
	for key in ["width", "tread", "rise"]:
		var result = HFStairsBuilderScript.validate(_settings({key: 0.0}))
		assert_false(result.ok, "%s of zero must be refused" % key)
		assert_true(str(result.message).contains(key.replace("_", " ")), str(result.message))


func test_a_floating_tread_deeper_than_the_whole_climb_is_refused():
	# It would be one slab pretending to be a staircase.
	var settings := _settings({"fill": 1, "steps": 4, "rise": 10.0, "tread_thickness": 41.0})
	assert_false(HFStairsBuilderScript.validate(settings).ok)
	settings["tread_thickness"] = 40.0
	assert_true(HFStairsBuilderScript.validate(settings).ok)


func test_thickness_is_only_judged_when_it_is_used():
	# A solid flight has no floating treads, so its thickness is irrelevant and
	# must not refuse the flight.
	var settings := _settings({"fill": 0, "steps": 2, "rise": 10.0, "tread_thickness": 999.0})
	assert_true(HFStairsBuilderScript.validate(settings).ok)


func test_a_refused_flight_builds_nothing():
	assert_eq(HFStairsBuilderScript.build(_settings({"steps": 0})).size(), 0)


# ===========================================================================
# The schema is the description the dock builds from
# ===========================================================================


func test_the_schema_describes_exactly_the_settings_the_builder_uses():
	var schema: Array = HFStairsBuilderScript.settings_schema()
	var defaults: Dictionary = HFStairsBuilderScript.default_settings()
	assert_eq(schema.size(), defaults.size(), "every field is a setting and the other way round")
	for field in schema:
		assert_true(defaults.has(field["key"]), "%s is described but never used" % field["key"])
		assert_true(str(field.get("label", "")) != "", "%s has no label" % field["key"])
		assert_true(str(field.get("tooltip", "")) != "", "%s has no tooltip" % field["key"])


func test_the_defaults_build_a_staircase():
	assert_true(HFStairsBuilderScript.validate({}).ok, "the defaults must be buildable")
	assert_eq(HFStairsBuilderScript.build({}).size(), 8)
