extends GutTest

## Validate checks stairs, ramps and doorways built from brushes against the
## playtest player (#1046).
##
## Its two movement checks measured only the connectors the bake builds between
## paint layers, against the navmesh agent, and only with navmesh on. A level
## whose brush stairs had 0.5 m risers, over the player's 0.4 m step, passed
## clean; the player got up them only walking straight at them.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFPlayerMetrics = preload("res://addons/hammerforge/hf_player_metrics.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


## A box at `center`, then carried by `turn`, as if turned with the rest of a group.
func _box(
	size: Vector3, center: Vector3, subtract := false, turn := Transform3D.IDENTITY
) -> DraftBrush:
	var info := {
		"shape": LevelRootType.BrushShape.BOX,
		"size": size,
		"transform": turn * Transform3D(Basis.IDENTITY, center),
		"operation": CSGShape3D.OPERATION_SUBTRACTION if subtract else CSGShape3D.OPERATION_UNION,
	}
	return root.create_brush_from_info(info) as DraftBrush


## A turn of `degrees` about the vertical through the origin.
func _turn(degrees: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3.ZERO)


func _wedge(size: Vector3, center: Vector3, yaw_degrees := 0.0) -> DraftBrush:
	var info := {
		"shape": LevelRootType.BrushShape.WEDGE,
		"size": size,
		"transform": Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), center),
		"operation": CSGShape3D.OPERATION_UNION,
	}
	return root.create_brush_from_info(info) as DraftBrush


## `count` solid steps along +z, each `rise` taller than the last, standing on y 0.
func _stairs(count: int, rise: float, run := 0.7, turn := Transform3D.IDENTITY) -> Array:
	var steps: Array = []
	for i in count:
		var top := rise * (i + 1)
		var center := Vector3(0, top * 0.5, run * (i + 0.5))
		steps.append(_box(Vector3(2, top, run), center, false, turn))
	return steps


func _findings(kind: String) -> Array:
	var found: Array = []
	for finding in root.validate_level(false).get("findings", []):
		if str(finding.get("type", "")) == kind:
			found.append(finding)
	return found


# ---------------------------------------------------------------------------
# Stairs
# ---------------------------------------------------------------------------


func test_stairs_with_risers_over_the_player_s_step_are_reported():
	var steps := _stairs(5, 0.5)
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 1, "one flight, one finding")
	if found.size() != 1:
		return
	assert_eq(found[0]["node"], steps[0], "from the first step")
	assert_eq(found[0]["other_node"], steps[4], "to the last")
	assert_string_contains(found[0]["message"], "0.50")
	var step: float = HFPlayerMetrics.standing()["step_height"]
	assert_string_contains(found[0]["message"], "%.2f" % step, "against the player's own step")


func test_stairs_the_player_can_walk_up_say_nothing():
	_stairs(5, 0.25)
	assert_eq(_findings("steep_stairs"), [])


func test_one_ledge_is_not_a_flight_of_stairs():
	# A crate beside a box is not stairs, whatever the difference in height.
	_stairs(2, 0.5)
	assert_eq(_findings("steep_stairs"), [])


func test_a_wall_beside_a_floor_is_not_a_step():
	_box(Vector3(8, 0.2, 8), Vector3(0, 0.1, 0))
	_box(Vector3(8, 3, 0.3), Vector3(0, 1.5, 4.15))
	_box(Vector3(8, 6, 0.3), Vector3(0, 3, 4.45))
	assert_eq(_findings("steep_stairs"), [])


# ---------------------------------------------------------------------------
# Doorways
# ---------------------------------------------------------------------------


## A wall 6 m long along x, 3 m high and 0.3 m thick, standing on y 0.
func _wall(turn := Transform3D.IDENTITY) -> DraftBrush:
	return _box(Vector3(6, 3, 0.3), Vector3(0, 1.5, 0), false, turn)


## A cut through the wall, `width` along x, from `bottom` up `height`.
func _cut(width: float, height: float, bottom := 0.0, turn := Transform3D.IDENTITY) -> DraftBrush:
	return _box(Vector3(width, height, 1), Vector3(0, bottom + height * 0.5, 0), true, turn)


func test_a_doorway_the_player_fits_through_says_nothing():
	_wall()
	_cut(1.0, 2.2)
	assert_eq(_findings("small_doorway"), [])


func test_a_doorway_narrower_than_the_player_is_reported():
	var wall := _wall()
	var cut := _cut(0.5, 2.2)
	var found := _findings("small_doorway")
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(found[0]["node"], cut)
		assert_eq(found[0]["other_node"], wall)
		assert_eq(int(found[0]["severity"]), 1, "nobody gets through it")


func test_a_doorway_too_low_even_crouched_is_a_warning():
	_wall()
	_cut(1.0, 0.6)
	var found := _findings("small_doorway")
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(int(found[0]["severity"]), 1)


func test_a_crawl_space_is_said_but_not_warned_about():
	# A crawl space is a thing a level means; it only has to be said.
	_wall()
	_cut(1.0, 1.2)
	var found := _findings("small_doorway")
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(int(found[0]["severity"]), 0, "an info: the player crouches through")
		assert_string_contains(found[0]["message"], "crouch")


func test_a_window_is_not_a_doorway():
	_wall()
	_cut(1.0, 1.0, 1.2)
	assert_eq(_findings("small_doorway"), [])


# ---------------------------------------------------------------------------
# Ramps
# ---------------------------------------------------------------------------


## A wedge 2 m long and `rise` m high whose slope climbs toward -x, with its
## high end at x = -1.
func _ramp(rise: float) -> DraftBrush:
	return _wedge(Vector3(2, rise, 2), Vector3(0, rise * 0.5, 0))


func test_a_ramp_steeper_than_the_player_walks_onto_a_landing_is_reported():
	var ramp := _ramp(3.0)
	var landing := _box(Vector3(2, 3, 2), Vector3(-2, 1.5, 0))
	var found := _findings("steep_ramp")
	assert_eq(found.size(), 1, "56 degrees, up to a floor")
	if found.size() == 1:
		assert_eq(found[0]["node"], ramp)
		assert_eq(found[0]["other_node"], landing)


func test_a_steep_wedge_with_nothing_at_its_top_is_not_a_ramp():
	# A buttress or a roof is a steep wedge too.
	_ramp(3.0)
	assert_eq(_findings("steep_ramp"), [])


func test_a_ramp_the_player_walks_up_says_nothing():
	_ramp(1.0)
	_box(Vector3(2, 1, 2), Vector3(-2, 0.5, 0))
	assert_eq(_findings("steep_ramp"), [])


# ---------------------------------------------------------------------------
# Turned brushes (#1087)
# ---------------------------------------------------------------------------


func test_a_flight_turned_30_degrees_is_still_stairs():
	# The checks read boxes square to the world, so a flight turned as a group
	# to any angle but a quarter turn was never looked at.
	var steps := _stairs(5, 0.5, 0.7, _turn(30.0))
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 1, "one flight, one finding")
	if found.size() != 1:
		return
	assert_eq(found[0]["node"], steps[0], "from the first step")
	assert_eq(found[0]["other_node"], steps[4], "to the last")
	assert_string_contains(found[0]["message"], "0.50")


func test_a_turned_flight_the_player_walks_up_says_nothing():
	_stairs(5, 0.25, 0.7, _turn(30.0))
	assert_eq(_findings("steep_stairs"), [])


func test_a_doorway_through_a_wall_turned_45_degrees_is_measured():
	var wall := _wall(_turn(45.0))
	var cut := _cut(0.5, 2.2, 0.0, _turn(45.0))
	var found := _findings("small_doorway")
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(found[0]["node"], cut)
		assert_eq(found[0]["other_node"], wall)
		assert_string_contains(found[0]["message"], "0.50 m wide", "across the wall, not the world")


func test_a_doorway_the_player_fits_through_a_turned_wall_says_nothing():
	_wall(_turn(45.0))
	_cut(1.0, 2.2, 0.0, _turn(45.0))
	assert_eq(_findings("small_doorway"), [])


func test_a_turned_ramp_onto_a_turned_landing_is_reported():
	var turn := _turn(30.0)
	var ramp := _wedge(Vector3(2, 3, 2), Vector3(0, 1.5, 0), 30.0)
	var landing := _box(Vector3(2, 3, 2), Vector3(-2, 1.5, 0), false, turn)
	var found := _findings("steep_ramp")
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(found[0]["node"], ramp)
		assert_eq(found[0]["other_node"], landing)


func test_the_generators_defaults_say_nothing_however_they_are_turned():
	# Each structure well clear of the others, so only its own pieces meet.
	var types := HFGeneratorSystemScript.known_types()
	var turns := [0.0, 30.0, 45.0]
	for i in types.size():
		for j in turns.size():
			var placement := _turn(turns[j])
			placement.origin = Vector3(20.0 * i, 0, 20.0 * j)
			var settings := HFGeneratorSystemScript.default_settings(types[i])
			assert_true(root.generator_system.create(types[i], settings, placement).ok)
	for kind in ["steep_stairs", "small_doorway", "steep_ramp"]:
		assert_eq(_findings(kind), [], kind)


func test_the_stairs_generator_turned_is_measured():
	# The case above says nothing because the defaults are walkable, not because
	# a turned flight goes unread.
	var settings := HFGeneratorSystemScript.default_settings("stairs")
	settings["rise"] = 0.5
	assert_true(root.generator_system.create("stairs", settings, _turn(30.0)).ok)
	assert_eq(_findings("steep_stairs").size(), 1)


# ---------------------------------------------------------------------------
# Spirals of boxes, each turned its own way (#1095)
# ---------------------------------------------------------------------------


## `count` solid treads standing on y 0, 2 m out along the radius from 1 m to 3 m
## and `across` m wide, each `rise` taller than the last and turned `degrees`
## further round the vertical, as a tower stair built of boxes.
func _spiral(count: int, rise: float, degrees := 20.0, across := 0.8) -> Array:
	var steps: Array = []
	for i in count:
		var top := rise * (i + 1)
		var center := Vector3(2, top * 0.5, 0)
		steps.append(_box(Vector3(2, top, across), center, false, _turn(degrees * i)))
	return steps


func test_a_spiral_of_boxes_with_risers_over_the_player_s_step_is_reported():
	# No two treads share a turn, so the check never compared them: a tower stair
	# of 0.5 m risers passed clean.
	var steps := _spiral(6, 0.5)
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 1, "one flight, one finding")
	if found.size() != 1:
		return
	assert_eq(found[0]["node"], steps[0], "from the first step")
	assert_eq(found[0]["other_node"], steps[5], "to the last")
	assert_string_contains(found[0]["message"], str(steps[0].name))
	assert_string_contains(found[0]["message"], str(steps[5].name))
	assert_string_contains(found[0]["message"], "0.50")


func test_a_spiral_turning_the_other_way_is_reported_once():
	var steps := _spiral(6, 0.5, -20.0)
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 1, "one flight, one finding")
	if found.size() == 1:
		assert_eq(found[0]["node"], steps[0])
		assert_eq(found[0]["other_node"], steps[5])


func test_a_spiral_of_boxes_the_player_walks_up_says_nothing():
	_spiral(6, 0.25)
	assert_eq(_findings("steep_stairs"), [])


func test_a_walkable_spiral_whose_treads_reach_two_along_says_nothing():
	# Wide treads in a tight turn overlap the tread two along as well. The player
	# meets the one between first, so that is no 0.5 m step.
	_spiral(6, 0.25, 20.0, 1.2)
	assert_eq(_findings("steep_stairs"), [])


func test_a_post_up_the_middle_is_not_the_spiral_s_last_step():
	# The post stands a step above the top tread, but the way onto it turns back
	# across the flight's, so the flight ends at the top tread.
	var steps := _spiral(6, 0.5)
	_turned_box(Vector3(2.2, 3.5, 2.2), Vector3(0, 1.75, 0), 45.0)
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 1, "one flight, one finding")
	if found.size() == 1:
		assert_eq(found[0]["node"], steps[0])
		assert_eq(found[0]["other_node"], steps[5], "the top tread, not the post")


func test_a_tight_spiral_the_player_walks_up_says_nothing():
	# At 10 degrees a step each tread covers the next one's middle. The step to
	# it was dropped, so the flight jumped to the tread two along and read a
	# walkable 0.25 m riser as 0.5.
	_spiral(8, 0.25, 10.0)
	assert_eq(_findings("steep_stairs"), [])


func test_a_tight_spiral_over_the_player_s_step_is_reported_once_at_its_riser():
	var steps := _spiral(8, 0.5, 10.0)
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 1, "one flight, one finding")
	if found.size() == 1:
		assert_eq(found[0]["node"], steps[0])
		assert_eq(found[0]["other_node"], steps[7])
		assert_string_contains(found[0]["message"], "0.50 m a step")


func test_a_spiral_of_two_boxes_is_not_a_flight():
	_spiral(2, 0.5)
	assert_eq(_findings("steep_stairs"), [])


## A box at `center` turned `degrees` about its own vertical.
func _turned_box(size: Vector3, center: Vector3, degrees: float) -> DraftBrush:
	var turn := _turn(degrees)
	turn.origin = Vector3(center.x, 0, center.z)
	return _box(size, Vector3(0, center.y, 0), false, turn)


func test_crates_turned_their_own_ways_on_a_floor_are_not_stairs():
	# The crates meet as a 0.5 m step, but the floor they stand on is not one
	# below the first, so two crates are no flight.
	_box(Vector3(8, 0.2, 8), Vector3(0, 0.1, 0))
	_turned_box(Vector3(1, 0.5, 1), Vector3(2, 0.45, 1), 10.0)
	_turned_box(Vector3(1, 1.0, 1), Vector3(2.8, 0.7, 1), 35.0)
	assert_eq(_findings("steep_stairs"), [])


func test_a_turned_box_at_the_head_of_a_flight_is_not_a_second_flight():
	# It stands a riser above the top step, the way the flight climbs, so the
	# flight goes on up onto it, as it would onto a box square to the world.
	var steps := _stairs(5, 0.5)
	var head := _turned_box(Vector3(2, 3, 0.7), Vector3(0, 1.5, 3.85), 20.0)
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 1, "the flight, once")
	if found.size() == 1:
		assert_eq(found[0]["node"], steps[0])
		assert_eq(found[0]["other_node"], head, "the flight's last step up is onto it")


# ---------------------------------------------------------------------------
# A flight that turns partway (#1104)
# ---------------------------------------------------------------------------


## `count` solid steps along +z as `_stairs` lays them, the first `square` of them
## square to the world and each after that turned `degrees` more about its own
## middle. The steps after the first `square` rise by `upper_rise` if it is set.
func _turning_flight(
	count: int, square: int, rise: float, degrees: float, run := 0.7, upper_rise := 0.0
) -> Array:
	var steps: Array = []
	var top := 0.0
	for i in count:
		top += upper_rise if i >= square and upper_rise > 0.0 else rise
		var center := Vector3(0, top * 0.5, run * (i + 0.5))
		var turn := degrees * maxi(i - square + 1, 0)
		steps.append(_turned_box(Vector3(2, top, run), center, turn))
	return steps


## The one steep_stairs finding, or {} after failing the test.
func _one_flight() -> Dictionary:
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 1, "one flight, one finding")
	return found[0] if found.size() == 1 else {}


func test_a_flight_that_turns_partway_is_reported_once():
	# Four steps square to the world, then four each turned 12 degrees more. The
	# square steps and the turned ones were each a flight, so one stair gave two
	# warnings, and Select on each picked a different pair.
	var steps := _turning_flight(8, 4, 0.5, 12.0)
	var finding := _one_flight()
	if finding.is_empty():
		return
	assert_eq(finding["node"], steps[0], "Select picks the foot")
	assert_eq(finding["other_node"], steps[7], "and the head")
	assert_string_contains(finding["message"], str(steps[0].name))
	assert_string_contains(finding["message"], str(steps[7].name))
	assert_string_contains(finding["message"], "0.50 m a step")


func test_a_flight_that_turns_20_degrees_a_step_the_other_way_is_reported_once():
	var steps := _turning_flight(8, 4, 0.5, -20.0)
	var finding := _one_flight()
	if not finding.is_empty():
		assert_eq(finding["node"], steps[0])
		assert_eq(finding["other_node"], steps[7])


func test_a_walkable_flight_that_turns_partway_says_nothing():
	_turning_flight(8, 4, 0.25, 12.0)
	assert_eq(_findings("steep_stairs"), [])


func test_a_flight_that_turns_after_its_second_step_is_reported_from_its_foot():
	# Two square steps are no flight alone, so the flight was read from the
	# second step up.
	var steps := _turning_flight(8, 2, 0.5, 12.0)
	var finding := _one_flight()
	if not finding.is_empty():
		assert_eq(finding["node"], steps[0], "from the first step")
		assert_eq(finding["other_node"], steps[7])


func test_a_flight_turned_two_steps_at_a_time_is_reported_once():
	# Each pair of steps shares a turn, the next pair turned 12 degrees more, and
	# each step stands ahead of the last the way it faces. A pair is no flight
	# alone, so a whole flight of 0.5 m risers passed clean.
	var steps: Array = []
	var at := Vector3.ZERO
	for i in 8:
		var degrees := 12.0 * floorf(i * 0.5)
		var half_ahead := Basis(Vector3.UP, deg_to_rad(degrees)) * Vector3(0, 0, 0.35)
		at += half_ahead
		var top := 0.5 * (i + 1)
		steps.append(_turned_box(Vector3(2, top, 0.7), Vector3(at.x, top * 0.5, at.z), degrees))
		at += half_ahead
	var finding := _one_flight()
	if not finding.is_empty():
		assert_eq(finding["node"], steps[0])
		assert_eq(finding["other_node"], steps[7])


func test_flights_whose_risers_differ_are_still_two():
	# 0.45 m risers then 0.75 m ones are two flights that meet, not one.
	var steps := _turning_flight(8, 4, 0.45, 12.0, 0.7, 0.75)
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 2, "two flights, two findings")
	var pairs: Array = []
	for finding in found:
		pairs.append([finding["node"], finding["other_node"]])
	assert_has(pairs, [steps[0], steps[3]], "the square flight")
	assert_has(pairs, [steps[3], steps[7]], "the turned flight, from the step they share")


func test_a_straight_flight_beside_a_spiral_is_two_flights():
	# Both kinds of step are followed in one walk, so a level with both still
	# reads each flight once, and the straight one from end to end.
	var straight := _stairs(12, 0.5)
	var spiral := _spiral(18, 0.5)
	for step in spiral:
		step.global_position += Vector3(20, 0, 0)
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 2, "one finding each")
	var pairs: Array = []
	for finding in found:
		pairs.append([finding["node"], finding["other_node"]])
	assert_has(pairs, [straight[0], straight[11]], "the straight flight")
	assert_has(pairs, [spiral[0], spiral[17]], "the spiral")


# ---------------------------------------------------------------------------
# The rows and the bridge
# ---------------------------------------------------------------------------


func test_the_issue_text_still_carries_each_finding():
	_stairs(5, 0.5)
	var report: Dictionary = root.validate_level(false)
	var said := false
	for issue in report.get("issues", []):
		said = said or str(issue).contains("0.50")
	assert_true(said, "the Console and the count read the text")


# ---------------------------------------------------------------------------
# Boxes a little into the next (#1118)
# ---------------------------------------------------------------------------


## `count` steps up +z, each `run` deep and set `on` from the last, so each runs
## `run - on` into the next.
func _overlapping_stairs(count: int, rise: float, run := 0.7, on := 0.6) -> Array:
	var steps: Array = []
	for i in count:
		var top := rise * (i + 1)
		steps.append(_box(Vector3(2, top, run), Vector3(0, top * 0.5, on * i + run * 0.5)))
	return steps


func test_a_steep_flight_of_boxes_a_little_into_each_other_is_reported_once():
	var steps := _overlapping_stairs(5, 0.5)
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 1, "the flight, once")
	if found.size() == 1:
		assert_eq(found[0]["node"], steps[0])
		assert_eq(found[0]["other_node"], steps[4])
		assert_string_contains(str(found[0]["message"]), "0.50 m a step")


func test_a_walkable_flight_of_boxes_a_little_into_each_other_is_not():
	_overlapping_stairs(5, 0.25)
	assert_eq(_findings("steep_stairs"), [])


func test_boxes_into_the_step_after_next_are_still_one_riser_a_step():
	# Each 0.7 m deep and 0.3 m on, so each also reaches into the one two up, a
	# whole metre higher. The player meets the one between first.
	var steps := _overlapping_stairs(6, 0.5, 0.7, 0.3)
	var found := _findings("steep_stairs")
	assert_eq(found.size(), 1, "the flight, once")
	if found.size() == 1:
		assert_eq(found[0]["node"], steps[0])
		assert_eq(found[0]["other_node"], steps[5])
		assert_string_contains(str(found[0]["message"]), "0.50 m a step")


func test_a_stack_of_boxes_each_wholly_over_the_last_is_not_stairs():
	_box(Vector3(4, 0.5, 4), Vector3(0, 0.25, 0))
	_box(Vector3(2, 1.0, 2), Vector3(0, 0.5, 0))
	_box(Vector3(1, 1.5, 1), Vector3(0, 0.75, 0))
	assert_eq(_findings("steep_stairs"), [])
