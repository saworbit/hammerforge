extends GutTest

## HFStairsBuilder: one description, one brush per step.
##
## The assertions are about the properties a flight has to have — the right number
## of steps, each one a closed convex solid facing outward, each one exactly a
## tread further on and a rise higher than the last — rather than about particular
## coordinates, which any reasonable ordering choice would change.

const HFStairsBuilderScript = preload("res://addons/hammerforge/hf_stairs_builder.gd")
const HFBrushSystemScript = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
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


func test_an_open_flight_is_centred_on_its_own_origin_too():
	# An open flight starts at the underside of its first tread, so it does not
	# span the whole climb. Centring on the climb left it half a tread high.
	var box: AABB = SolidChecks.structure_bounds(
		HFStairsBuilderScript.build(_settings({"fill": 1}))
	)
	assert_almost_eq(box.get_center().y, 0.0, EPS, "an open flight sat above its placement point")


func test_an_open_flight_stays_centred_at_other_rises_and_thicknesses():
	for overrides in [
		{"fill": 1, "rise": 24.0, "tread_thickness": 4.0},
		{"fill": 1, "rise": 12.0, "tread_thickness": 12.0},
		{"fill": 1, "rise": 10.0, "tread_thickness": 20.0, "steps": 6},
	]:
		var box: AABB = SolidChecks.structure_bounds(
			HFStairsBuilderScript.build(_settings(overrides))
		)
		assert_almost_eq(box.get_center().y, 0.0, EPS, "off centre for %s" % overrides)


func test_an_open_flight_still_reaches_the_same_top_step():
	# Centring moves the flight, it does not change how tall it is.
	var flight: Array = HFStairsBuilderScript.build(_settings({"fill": 1}))
	var box: AABB = SolidChecks.structure_bounds(flight)
	var settings := _settings()
	var rise: float = settings["rise"]
	var thickness: float = settings["tread_thickness"]
	var steps: int = settings["steps"]
	assert_almost_eq(
		box.size.y, float(steps) * rise - (rise - thickness), EPS, "the flight changed height"
	)


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
	# A slab deeper than the whole climb is refused, and `build()` returns nothing
	# when it is. At the old scale five 16 unit rises were an 80 unit climb and a
	# 6 unit slab sat well inside it; in metres (#625) the same five steps climb
	# 1.0, so the old thickness silently left this test with nothing to walk.
	var flight: Array = HFStairsBuilderScript.build(
		_settings({"steps": 5, "fill": 1, "tread_thickness": 0.12})
	)
	assert_eq(flight.size(), 5, "the flight builds, so there is something to check")
	for step in flight:
		assert_almost_eq(SolidChecks.bounds(step).size.y, 0.12, EPS, "a tread is the wrong depth")


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


# ===========================================================================
# An existing level's stairs build exactly as they did (#1410)
# ===========================================================================


func test_a_flight_from_before_turns_existed_builds_the_same_corners():
	# A structure is recognised as untouched by a hash of its corners, so a flight
	# saved before these settings existed has to come out a rounding for a
	# rounding the same, or every step of it would read as edited by hand.
	for overrides in [{}, {"fill": 1}, {"steps": 13, "rise": 0.17, "tread": 0.27}]:
		var settings := _settings(overrides)
		var flight: Array = HFStairsBuilderScript.build(settings)
		var steps: int = settings["steps"]
		assert_eq(flight.size(), steps)
		var half_width: float = float(settings["width"]) * 0.5
		var tread: float = settings["tread"]
		var rise: float = settings["rise"]
		var thickness: float = settings["tread_thickness"]
		var open_treads := int(settings["fill"]) == 1
		var lowest := (rise - thickness) if open_treads else 0.0
		var y_shift := -(lowest + float(steps) * rise) * 0.5
		var z_shift := -float(steps) * tread * 0.5
		for i in steps:
			var top := float(i + 1) * rise + y_shift
			var bottom := (top - thickness) if open_treads else y_shift
			var near := float(i) * tread + z_shift
			var far := float(i + 1) * tread + z_shift
			var was: Array = HFStairsBuilderScript._box_faces(
				Vector3(-half_width, bottom, near), Vector3(half_width, top, far)
			)
			for f in was.size():
				assert_eq(
					flight[i][f].local_verts,
					was[f].local_verts,
					"step %d moved for %s" % [i, overrides]
				)


# ===========================================================================
# The height from the floor heights (#1410)
# ===========================================================================


func test_a_total_of_3_in_16_steps_gives_risers_of_0_1875():
	var settings := _settings({"height_from": 1, "total": 3.0, "steps": 16})
	assert_eq(HFStairsBuilderScript.climb(settings), {"steps": 16, "rise": 0.1875})
	var flight: Array = HFStairsBuilderScript.build(settings)
	assert_eq(flight.size(), 16)
	var base: float = SolidChecks.structure_bounds(flight).position.y
	for i in flight.size():
		assert_almost_eq(
			SolidChecks.bounds(flight[i]).end.y - base, 0.1875 * float(i + 1), EPS, "step %d" % i
		)
	assert_almost_eq(SolidChecks.structure_bounds(flight).size.y, 3.0, EPS, "it reaches the floor")


func test_fit_with_a_0_2_rise_and_a_3_total_takes_15_steps():
	var settings := _settings({"height_from": 2, "total": 3.0, "rise": 0.2, "steps": 99})
	assert_eq(HFStairsBuilderScript.climb(settings), {"steps": 15, "rise": 0.2})
	assert_eq(HFStairsBuilderScript.build(settings).size(), 15, "Steps is not what Fit reads")


func test_fit_takes_the_fewest_steps_that_keep_every_riser_under_the_rise():
	var shape: Dictionary = HFStairsBuilderScript.climb(
		_settings({"height_from": 2, "total": 3.1, "rise": 0.2})
	)
	assert_eq(shape["steps"], 16, "15 risers of 0.2 fall short of 3.1")
	assert_almost_eq(float(shape["rise"]), 3.1 / 16.0, 0.000001)
	assert_lte(float(shape["rise"]), 0.2)


func test_total_reads_the_total_and_not_the_rise():
	var flight: Array = HFStairsBuilderScript.build(
		_settings({"height_from": 1, "total": 2.0, "steps": 8, "rise": 0.9})
	)
	assert_almost_eq(SolidChecks.structure_bounds(flight).size.y, 2.0, EPS)


func test_fit_past_the_step_cap_is_refused_and_says_how_many():
	var result = HFStairsBuilderScript.validate(
		_settings({"height_from": 2, "total": 100.0, "rise": 0.5})
	)
	assert_false(result.ok)
	assert_string_contains(str(result.message), "200 steps")


func test_the_summary_says_what_the_height_came_to():
	var text: String = HFStairsBuilderScript.summary(
		_settings({"height_from": 1, "total": 3.0, "steps": 16})
	)
	assert_string_contains(text, "16 steps")
	assert_string_contains(text, "0.1875")
	assert_string_contains(text, "climb 3")
	assert_eq(HFStairsBuilderScript.summary(_settings({"steps": 0})), "", "nothing it cannot build")


# ===========================================================================
# Turns and landings (#1410)
# ===========================================================================

const TURNS := {"L left": 1, "L right": 2, "U left": 3, "U right": 4}


## The pieces of a turned stair, which every test below reads the same way.
func _turned(turn: int, fill := 0, overrides := {}) -> Dictionary:
	var settings := _settings({"turn": turn, "fill": fill, "steps": 9, "before_landing": 4})
	settings.merge(overrides, true)
	var pieces: Array = HFStairsBuilderScript.build(settings)
	var before: int = settings["before_landing"]
	var boxes: Array = []
	for piece in pieces:
		boxes.append(SolidChecks.bounds(piece))
	return {
		"settings": settings,
		"pieces": pieces,
		"boxes": boxes,
		"first": boxes.slice(0, before - 1),
		"landing": boxes[before - 1] if boxes.size() >= before else AABB(),
		"second": boxes.slice(before, int(settings["steps"])),
	}


## How much two boxes share, by volume. Touching is none.
func _overlap(a: AABB, b: AABB) -> float:
	var shared := a.intersection(b)
	return shared.size.x * shared.size.y * shared.size.z


func _assert_no_two_overlap(boxes: Array, what: String) -> void:
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			assert_almost_eq(
				_overlap(boxes[i], boxes[j]), 0.0, 0.000001, "%s: %d and %d overlap" % [what, i, j]
			)


func test_every_turn_builds_both_flights_and_a_landing_of_convex_boxes():
	for label in TURNS:
		for fill in [0, 1]:
			var stair := _turned(TURNS[label], fill)
			var what := "%s, fill %d" % [label, fill]
			assert_eq(stair["pieces"].size(), 9, "%s: the landing stands in for one step" % what)
			for piece in stair["pieces"]:
				assert_eq(SolidChecks.describe_problem(piece), "", what)
				assert_eq(piece.size(), 6, "%s: every piece is a box" % what)
			_assert_no_two_overlap(stair["boxes"], what)


func test_the_landing_meets_the_first_flight_with_no_gap():
	for label in TURNS:
		for fill in [0, 1]:
			var stair := _turned(TURNS[label], fill)
			var last: AABB = stair["first"][-1]
			var landing: AABB = stair["landing"]
			var what := "%s, fill %d" % [label, fill]
			assert_almost_eq(
				landing.position.z, last.end.z, EPS, "%s: a gap after the flight" % what
			)
			assert_almost_eq(
				landing.end.y - last.end.y,
				float(stair["settings"]["rise"]),
				EPS,
				"%s: the landing is the top of the next riser" % what
			)
			assert_lte(landing.position.x, last.position.x + EPS, what)
			assert_gte(landing.end.x, last.end.x - EPS, "%s: it spans the flight" % what)


func test_the_second_flight_leaves_the_landing_with_no_gap_the_way_it_turns():
	var rise: float = _settings()["rise"]
	for label in TURNS:
		for fill in [0, 1]:
			var stair := _turned(TURNS[label], fill)
			var landing: AABB = stair["landing"]
			var second: Array = stair["second"]
			var first_step: AABB = second[0]
			var what := "%s, fill %d" % [label, fill]
			assert_almost_eq(first_step.end.y - landing.end.y, rise, EPS, what)
			match label:
				"L left":
					assert_almost_eq(first_step.position.x, landing.end.x, EPS, what)
					assert_gt(second[-1].position.x, first_step.position.x, "%s climbs +X" % what)
				"L right":
					assert_almost_eq(first_step.end.x, landing.position.x, EPS, what)
					assert_lt(second[-1].position.x, first_step.position.x, "%s climbs -X" % what)
				_:
					assert_almost_eq(first_step.end.z, landing.position.z, EPS, what)
					assert_lt(second[-1].position.z, first_step.position.z, "%s comes back" % what)
			# Wholly beside the landing along the edge it leaves from.
			if label.begins_with("L"):
				assert_gte(first_step.position.z, landing.position.z - EPS, what)
				assert_lte(first_step.end.z, landing.end.z + EPS, what)
			else:
				assert_gte(first_step.position.x, landing.position.x - EPS, what)
				assert_lte(first_step.end.x, landing.end.x + EPS, what)
			for k in range(1, second.size()):
				assert_almost_eq(second[k].end.y - second[k - 1].end.y, rise, EPS, what)


func test_a_u_turn_comes_back_beside_the_first_flight_across_the_gap():
	var stair := _turned(TURNS["U left"], 0, {"gap": 0.4})
	var first: AABB = stair["first"][0]
	var back: AABB = stair["second"][0]
	assert_almost_eq(back.position.x - first.end.x, 0.4, EPS, "the gap between the flights")
	assert_almost_eq(back.size.x, first.size.x, EPS, "both flights are the width")
	var landing: AABB = stair["landing"]
	assert_almost_eq(landing.position.x, first.position.x, EPS, "the landing spans both flights")
	assert_almost_eq(landing.end.x, back.end.x, EPS, "and the gap between them")


func test_a_turn_leaves_the_first_flight_where_the_straight_flight_has_it():
	# What an Update that changes the turn relies on to rebuild in place.
	var straight: Array = HFStairsBuilderScript.build(_settings({"steps": 9}))
	for label in TURNS:
		var stair := _turned(TURNS[label])
		for i in (stair["first"] as Array).size():
			assert_eq(
				stair["first"][i], SolidChecks.bounds(straight[i]), "%s: step %d" % [label, i]
			)


func test_a_landing_needs_a_flight_on_each_side_of_it():
	for before in [9, 12]:
		var result = HFStairsBuilderScript.validate(
			_settings({"turn": 1, "steps": 9, "before_landing": before})
		)
		assert_false(result.ok, "a landing after %d of 9 risers" % before)
	assert_true(
		HFStairsBuilderScript.validate(_settings({"turn": 1, "steps": 9, "before_landing": 8})).ok
	)
	assert_true(
		HFStairsBuilderScript.validate(_settings({"turn": 1, "steps": 9, "before_landing": 1})).ok,
		"a landing on the first riser is a turn at the foot"
	)
	assert_eq(
		HFStairsBuilderScript.build(_settings({"turn": 1, "steps": 9, "before_landing": 1})).size(),
		9
	)


func test_an_l_landing_shallower_than_the_flight_is_wide_is_refused():
	var result = HFStairsBuilderScript.validate(
		_settings({"turn": 1, "width": 2.0, "landing": 1.9})
	)
	assert_false(result.ok)
	assert_string_contains(str(result.fix_hint), "2")
	assert_true(
		HFStairsBuilderScript.validate(_settings({"turn": 1, "width": 2.0, "landing": 2.0})).ok
	)
	assert_true(
		HFStairsBuilderScript.validate(_settings({"turn": 3, "width": 2.0, "landing": 0.5})).ok,
		"a U landing spans the flights, so its depth is its own"
	)


func test_a_deeper_l_landing_leaves_the_second_flight_at_its_far_end():
	var stair := _turned(TURNS["L left"], 0, {"landing": 2.5})
	var landing: AABB = stair["landing"]
	var first_step: AABB = stair["second"][0]
	assert_almost_eq(landing.size.z, 2.5, EPS)
	assert_almost_eq(first_step.end.z, landing.end.z, EPS)
	_assert_no_two_overlap(stair["boxes"], "a deep L landing")


func test_a_negative_gap_is_refused():
	assert_false(HFStairsBuilderScript.validate(_settings({"turn": 3, "gap": -0.1})).ok)


# ===========================================================================
# Nosing (#1410)
# ===========================================================================


func test_nosing_adds_one_convex_slab_per_solid_step():
	var settings := _settings({"steps": 6, "nosing": 0.12, "tread_thickness": 0.1})
	var pieces: Array = HFStairsBuilderScript.build(settings)
	assert_eq(pieces.size(), 12, "a step and its nosing")
	var boxes: Array = []
	for piece in pieces:
		assert_eq(SolidChecks.describe_problem(piece), "")
		boxes.append(SolidChecks.bounds(piece))
	_assert_no_two_overlap(boxes, "a nosed flight")
	for i in 6:
		var step: AABB = boxes[i]
		var nosing: AABB = boxes[6 + i]
		assert_almost_eq(
			nosing.end.z, step.position.z, EPS, "it hangs off the riser of step %d" % i
		)
		assert_almost_eq(nosing.size.z, 0.12, EPS)
		assert_almost_eq(nosing.end.y, step.end.y, EPS, "level with the tread")
		assert_almost_eq(nosing.size.y, 0.1, EPS, "one slab thick")
		assert_almost_eq(nosing.size.x, step.size.x, EPS, "the width of the step")


func test_nosing_leaves_the_steps_where_they_were():
	# So an Update that turns it on carries every step's look across.
	var plain: Array = HFStairsBuilderScript.build(_settings({"steps": 6}))
	var nosed: Array = HFStairsBuilderScript.build(_settings({"steps": 6, "nosing": 0.1}))
	for i in 6:
		assert_eq(SolidChecks.bounds(nosed[i]), SolidChecks.bounds(plain[i]), "step %d" % i)


func test_nosing_lengthens_each_open_tread_instead():
	var plain: Array = HFStairsBuilderScript.build(_settings({"steps": 6, "fill": 1}))
	var nosed: Array = HFStairsBuilderScript.build(
		_settings({"steps": 6, "fill": 1, "nosing": 0.04})
	)
	assert_eq(nosed.size(), 6, "an open tread is one slab either way")
	var boxes: Array = []
	for i in 6:
		var was: AABB = SolidChecks.bounds(plain[i])
		var now: AABB = SolidChecks.bounds(nosed[i])
		assert_almost_eq(now.position.z, was.position.z - 0.04, EPS, "it grows forward")
		assert_almost_eq(now.end.z, was.end.z, EPS)
		boxes.append(now)
	_assert_no_two_overlap(boxes, "nosed open treads")


func test_nosing_on_a_turned_stair_stays_clear_of_the_landing():
	for label in TURNS:
		for fill in [0, 1]:
			var settings := _settings(
				{
					"turn": TURNS[label],
					"fill": fill,
					"steps": 9,
					"nosing": 0.1 if fill == 0 else 0.04
				}
			)
			var pieces: Array = HFStairsBuilderScript.build(settings)
			var what := "%s, fill %d" % [label, fill]
			assert_eq(pieces.size(), 17 if fill == 0 else 9, "%s: no nosing on the landing" % what)
			var boxes: Array = []
			for piece in pieces:
				assert_eq(SolidChecks.describe_problem(piece), "", what)
				boxes.append(SolidChecks.bounds(piece))
			_assert_no_two_overlap(boxes, what)


func test_a_nosing_that_would_cut_into_the_step_below_is_refused():
	var settings := _settings({"nosing": 0.1, "rise": 0.2, "tread_thickness": 0.25})
	assert_false(HFStairsBuilderScript.validate(settings).ok)
	settings["tread_thickness"] = 0.2
	assert_true(HFStairsBuilderScript.validate(settings).ok, "level with the riser touches it")
	assert_false(HFStairsBuilderScript.validate(_settings({"nosing": 0.3, "tread": 0.3})).ok)
	assert_false(HFStairsBuilderScript.validate(_settings({"nosing": -0.01})).ok)


func test_a_solid_step_s_nosing_is_no_thinner_than_a_brush_can_be():
	# The brush system widens a thinner brush as it makes it, and the box rebuilds
	# at that size, into the step below, whenever its scene opens.
	assert_eq(HFStairsBuilderScript.MIN_PIECE, HFBrushSystemScript.MIN_BRUSH_EXTENT)
	var result = HFStairsBuilderScript.validate(_settings({"nosing": 0.03}))
	assert_false(result.ok, "0.03 deep")
	assert_string_contains(str(result.fix_hint), "0.1")
	assert_false(
		HFStairsBuilderScript.validate(_settings({"nosing": 0.1, "tread_thickness": 0.05})).ok,
		"0.05 thick"
	)
	assert_true(HFStairsBuilderScript.validate(_settings({"nosing": 0.1})).ok)
	assert_true(
		HFStairsBuilderScript.validate(_settings({"nosing": 0.03, "fill": 1})).ok,
		"an open tread just grows, so its nosing can be any depth"
	)


func test_the_piece_cap_counts_the_nosing_too():
	var settings := _settings({"steps": 80})
	assert_true(HFStairsBuilderScript.validate(settings).ok)
	settings["nosing"] = 0.1
	var result = HFStairsBuilderScript.validate(settings)
	assert_false(result.ok, "160 brushes")
	assert_string_contains(str(result.message), "160 pieces")
	settings["fill"] = 1
	assert_true(HFStairsBuilderScript.validate(settings).ok, "an open tread just grows")


# ===========================================================================
# Ramp collision (#1416)
# ===========================================================================


func test_steps_collision_lays_no_ramp():
	assert_eq(HFStairsBuilderScript.ramp_collision(_settings()), {})
	assert_eq(HFStairsBuilderScript.ramp_collision(_settings({"collision": 1, "steps": 0})), {})


## The height at `z` of the line from `from` to `to`, both along +Z.
func _line_through(from: Vector3, to: Vector3, z: float) -> float:
	return from.y + (to.y - from.y) * (z - from.z) / (to.z - from.z)


## The front of the cloud at its top (the toe) and the front of its highest points.
func _extremes(points: PackedVector3Array) -> Dictionary:
	var toe := points[0]
	var top := points[0]
	for p in points:
		if p.z < toe.z - EPS or (absf(p.z - toe.z) <= EPS and p.y > toe.y):
			toe = p
		if p.y > top.y + EPS or (absf(p.y - top.y) <= EPS and p.z < top.z):
			top = p
	return {"toe": toe, "top": top}


## A ramp over a flight along +Z: from the floor a tread before the first front
## edge, through every front edge, never a riser over a tread and flat at the top.
func _assert_ramp_over(fronts: Array, ramp: PackedVector3Array, rise: float, what: String) -> void:
	var ends := _extremes(ramp)
	var toe: Vector3 = ends["toe"]
	var top: Vector3 = ends["top"]
	var first: AABB = fronts[0]
	assert_almost_eq(toe.y, first.end.y - rise, EPS, "%s: the toe is on the floor" % what)
	for i in fronts.size():
		var tread: AABB = fronts[i]
		var at_front := _line_through(toe, top, tread.position.z)
		assert_almost_eq(at_front, tread.end.y, EPS, "%s: through tread %d's front" % [what, i])
		# Where the next tread starts it is the one underfoot, and a nosed open tread
		# runs on under that one's nosing.
		var back := tread.end.z
		if i + 1 < fronts.size():
			back = minf(back, (fronts[i + 1] as AABB).position.z)
		var at_back := minf(_line_through(toe, top, back), top.y)
		assert_lte(at_back - tread.end.y, rise + EPS, "%s: a riser over tread %d" % [what, i])
	for p in ramp:
		var ceiling := minf(_line_through(toe, top, p.z), top.y)
		assert_lte(p.y, ceiling + EPS, "%s: nothing stands above the slope" % what)


func test_a_straight_flight_s_ramp_runs_through_the_front_edge_of_every_tread():
	for fill in [0, 1]:
		var settings := _settings({"collision": 1, "fill": fill})
		var ramp: Dictionary = HFStairsBuilderScript.ramp_collision(settings)
		assert_eq(ramp["pieces"].size(), 1, "one piece for one flight")
		assert_eq(Array(ramp["covers"]), range(8), "it stands in for every step")
		var fronts: Array = []
		for step in HFStairsBuilderScript.build(settings):
			fronts.append(SolidChecks.bounds(step))
		_assert_ramp_over(fronts, ramp["pieces"][0], 0.2, "fill %d" % fill)
		var top: Vector3 = _extremes(ramp["pieces"][0])["top"]
		assert_almost_eq(top.y, fronts[-1].end.y, EPS, "flat over the top tread")
		assert_almost_eq(float(ramp["slope_degrees"]), rad_to_deg(atan2(0.2, 0.3)), 0.0001)


func test_a_nosed_flight_s_ramp_runs_through_the_front_of_each_nosing():
	for fill in [0, 1]:
		var settings := _settings(
			{"collision": 1, "fill": fill, "nosing": 0.1 if fill == 0 else 0.03}
		)
		var pieces: Array = HFStairsBuilderScript.build(settings)
		var fronts: Array = []
		for i in 8:
			# The nosing of a solid step comes after the steps; an open tread is its own.
			var front: AABB = SolidChecks.bounds(pieces[8 + i] if fill == 0 else pieces[i])
			fronts.append(front)
		var ramp: Dictionary = HFStairsBuilderScript.ramp_collision(settings)
		_assert_ramp_over(fronts, ramp["pieces"][0], 0.2, "nosed, fill %d" % fill)


func test_a_turned_stair_lays_a_ramp_for_each_flight_and_a_box_for_its_landing():
	for label in TURNS:
		for fill in [0, 1]:
			var stair := _turned(TURNS[label], fill, {"collision": 1})
			var what := "%s, fill %d" % [label, fill]
			var ramp: Dictionary = HFStairsBuilderScript.ramp_collision(stair["settings"])
			assert_eq(ramp["pieces"].size(), 3, what)
			var landing: AABB = stair["landing"]
			var box := AABB(ramp["pieces"][1][0], Vector3.ZERO)
			for p in ramp["pieces"][1]:
				box = box.expand(p)
			assert_eq(box, landing, "%s: the landing's own box" % what)
			# The first flight's slope ends level with the landing, not a lip over it.
			var highest := -INF
			for p in ramp["pieces"][0]:
				highest = maxf(highest, p.y)
			assert_almost_eq(highest, landing.end.y, EPS, what)
			# The second's starts on the landing.
			var toe_points := 0
			for p in ramp["pieces"][2]:
				if absf(p.y - landing.end.y) <= EPS:
					toe_points += 1
					assert_true(
						landing.grow(EPS).has_point(p), "%s: %s is off the landing" % [what, p]
					)
			assert_gt(toe_points, 0, "%s: it starts at the landing's height" % what)


func test_the_first_flight_s_ramp_runs_through_its_fronts_onto_the_landing():
	var stair := _turned(TURNS["L right"], 0, {"collision": 1})
	var fronts: Array = (stair["first"] as Array).duplicate()
	fronts.append(stair["landing"])
	var ramp: Dictionary = HFStairsBuilderScript.ramp_collision(stair["settings"])
	_assert_ramp_over(fronts, ramp["pieces"][0], 0.2, "onto the landing")


func test_a_landing_too_shallow_for_the_second_ramp_to_start_on_is_refused():
	var ramp: Dictionary = HFStairsBuilderScript.ramp_collision(
		_settings({"collision": 1, "turn": 3, "landing": 0.2})
	)
	assert_true(ramp.has("refused"), "the slope would start in the air")
	assert_string_contains(str(ramp.get("refused", "")), "landing")
