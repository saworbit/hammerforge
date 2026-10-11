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

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


func _box(size: Vector3, center: Vector3, subtract := false) -> DraftBrush:
	var info := {
		"shape": LevelRootType.BrushShape.BOX,
		"size": size,
		"center": center,
		"operation": CSGShape3D.OPERATION_SUBTRACTION if subtract else CSGShape3D.OPERATION_UNION,
	}
	return root.create_brush_from_info(info) as DraftBrush


func _wedge(size: Vector3, center: Vector3, yaw_degrees := 0.0) -> DraftBrush:
	var info := {
		"shape": LevelRootType.BrushShape.WEDGE,
		"size": size,
		"transform": Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), center),
		"operation": CSGShape3D.OPERATION_UNION,
	}
	return root.create_brush_from_info(info) as DraftBrush


## `count` solid steps along +z, each `rise` taller than the last, standing on y 0.
func _stairs(count: int, rise: float, run := 0.7) -> Array:
	var steps: Array = []
	for i in count:
		var top := rise * (i + 1)
		steps.append(_box(Vector3(2, top, run), Vector3(0, top * 0.5, run * (i + 0.5))))
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
func _wall() -> DraftBrush:
	return _box(Vector3(6, 3, 0.3), Vector3(0, 1.5, 0))


## A cut through the wall, `width` along x, from `bottom` up `height`.
func _cut(width: float, height: float, bottom := 0.0) -> DraftBrush:
	return _box(Vector3(width, height, 1), Vector3(0, bottom + height * 0.5, 0), true)


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
# The rows and the bridge
# ---------------------------------------------------------------------------


func test_the_issue_text_still_carries_each_finding():
	_stairs(5, 0.5)
	var report: Dictionary = root.validate_level(false)
	var said := false
	for issue in report.get("issues", []):
		said = said or str(issue).contains("0.50")
	assert_true(said, "the Console and the count read the text")
