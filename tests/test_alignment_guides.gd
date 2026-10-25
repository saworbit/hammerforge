extends GutTest

## Guides from points the mapper rests on, and points built from two others
## (#1692).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFSnapSystemScript = preload("res://addons/hammerforge/hf_snap_system.gd")
const HFPluginSnapFeedbackScript = preload("res://addons/hammerforge/plugin_snap_feedback.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _level() -> Node:
	var level = await rig.make_level()
	level.grid_snap = 1.0
	var snap = level.snap_system
	snap.set_mode(HFSnapSystemScript.SnapMode.VERTEX, true)
	# Off, so a corner on the grid is a vertex and not a grid point.
	snap.set_mode(HFSnapSystemScript.SnapMode.GRID, false)
	snap.snap_threshold = 0.3
	snap.clear_tracked()
	return level


## A snap as the pointer moving over the viewport makes it, so the viewport
## shows the pick.
func _hover(level: Node, point: Vector3) -> Vector3:
	var snap = level.snap_system
	snap.begin_pointer_event()
	var landed: Vector3 = level._snap_point(point)
	snap.end_pointer_event(true)
	return landed


func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func test_resting_on_a_vertex_tracks_it_and_resting_again_lets_it_go():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var snap = level.snap_system
	var corner: Vector3 = _hover(level, Vector3(1.05, 2.0, 1.02))
	assert_eq(corner, Vector3(1, 2, 1), "fixture: on the corner")
	HFPluginSnapFeedbackScript.note_rest(rig.plugin, snap)
	await get_tree().create_timer(HFPluginSnapFeedbackScript.REST_SECONDS + 0.2).timeout
	assert_eq(snap.tracked.size(), 1, "half a second on it tracks it")
	HFPluginSnapFeedbackScript.note_rest(rig.plugin, snap)
	await get_tree().create_timer(HFPluginSnapFeedbackScript.REST_SECONDS + 0.2).timeout
	assert_eq(snap.tracked.size(), 1, "staying on it is the same rest")
	_hover(level, Vector3(8, 0, 8))
	HFPluginSnapFeedbackScript.note_rest(rig.plugin, snap)
	_hover(level, Vector3(1.05, 2.0, 1.02))
	HFPluginSnapFeedbackScript.note_rest(rig.plugin, snap)
	await get_tree().create_timer(HFPluginSnapFeedbackScript.REST_SECONDS + 0.2).timeout
	assert_eq(snap.tracked.size(), 0, "coming back and resting again lets it go")
	await rig.leave_level(level)


func test_a_point_where_guides_from_two_vertices_cross_takes_their_x_and_z():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var snap = level.snap_system
	snap.toggle_tracked(Vector3(1, 0, 4), HFSnapSystemScript.KIND_VERTEX)
	snap.toggle_tracked(Vector3(7, 0, -3), HFSnapSystemScript.KIND_VERTEX)
	var landed: Vector3 = _hover(level, Vector3(7.12, 0, 4.09))
	assert_eq(landed, Vector3(7, 0, 4), "X from one, Z from the other, exactly")
	assert_eq(snap.shown_pick["kind"], HFSnapSystemScript.KIND_GUIDE_CROSS)
	var on_one: Vector3 = _hover(level, Vector3(3.3, 0, 4.1))
	assert_eq(on_one, Vector3(3.3, 0, 4), "near one guide, onto it")
	assert_eq(snap.shown_pick["kind"], HFSnapSystemScript.KIND_GUIDE)
	assert_eq(snap.shown_pick["label"], "Vertex: 2.3 m along +X")
	await rig.leave_level(level)


func test_a_corner_above_guides_a_point_on_the_floor_under_it():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var snap = level.snap_system
	snap.toggle_tracked(Vector3(2, 5, 3), HFSnapSystemScript.KIND_VERTEX)
	assert_eq(_hover(level, Vector3(2.1, 0, 9)), Vector3(2, 0, 9), "in line with it, on the floor")
	await rig.leave_level(level)


func test_a_distance_typed_on_a_guide_puts_the_point_that_far_from_its_source():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var snap = level.snap_system
	snap.toggle_tracked(Vector3(1, 0, 4), HFSnapSystemScript.KIND_VERTEX)
	_hover(level, Vector3(3.3, 0, 4.1))
	for keycode in [KEY_2, KEY_PERIOD, KEY_5]:
		assert_true(HFPluginSnapFeedbackScript.key(rig.plugin, _key(keycode)), "typed")
	assert_eq(snap.guide_text, "2.5")
	assert_true(HFPluginSnapFeedbackScript.key(rig.plugin, _key(KEY_ENTER)))
	assert_eq(_hover(level, Vector3(9, 0, 9)), Vector3(3.5, 0, 4), "2.5 m along +X, wherever")
	snap.pick_taken()
	assert_ne(_hover(level, Vector3(9, 0, 9)), Vector3(3.5, 0, 4), "for one pick")
	await rig.leave_level(level)


func test_a_filtered_point_takes_x_and_z_from_one_pick_and_its_height_from_another():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	rig.box(level, "low", Vector3(0, 1, 0), Vector3(2, 2, 2))
	rig.box(level, "high", Vector3(10, 4, 10), Vector3(2, 2, 2))
	var snap = level.snap_system
	_hover(level, Vector3(1.05, 2.0, 1.02))
	assert_true(HFPluginSnapFeedbackScript.take_xz_here(rig.plugin))
	var landed: Vector3 = _hover(level, Vector3(11.04, 5.0, 11.02))
	assert_eq(landed, Vector3(1, 5, 1), "X and Z from the low corner, Y from the high one")
	assert_true(rig.plugin._cancel_escape_step(level), "Escape drops it")
	assert_eq(_hover(level, Vector3(11.04, 5.0, 11.02)), Vector3(11, 5, 11))
	await rig.leave_level(level)


func test_with_guides_off_or_never_used_snapping_is_as_it_was():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var snap = level.snap_system
	var plain: Vector3 = _hover(level, Vector3(3.1, 0, 4.2))
	var choices: Array = snap.last_choices.duplicate(true)
	snap.toggle_tracked(Vector3(1, 0, 4), HFSnapSystemScript.KIND_VERTEX)
	snap.tracking = false
	assert_eq(_hover(level, Vector3(3.1, 0, 4.2)), plain, "off, no guide")
	assert_eq(snap.last_choices, choices, "and the same choices as with none tracked")
	var prefs = rig.plugin._user_prefs
	var was: bool = prefs.get_pref("snap_tracking", true)
	prefs.set_pref("snap_tracking", false)
	snap.clear_tracked()
	_hover(level, Vector3(1.05, 2.0, 1.02))
	HFPluginSnapFeedbackScript.note_rest(rig.plugin, snap)
	await get_tree().create_timer(HFPluginSnapFeedbackScript.REST_SECONDS + 0.2).timeout
	assert_eq(snap.tracked.size(), 0, "the setting off, a rest tracks nothing")
	prefs.set_pref("snap_tracking", was)
	await rig.leave_level(level)


func test_leaving_the_tool_lets_the_points_go():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	var snap = level.snap_system
	snap.toggle_tracked(Vector3(1, 0, 4), HFSnapSystemScript.KIND_VERTEX)
	rig.plugin._prepare_tool_transition(level)
	assert_eq(snap.tracked.size(), 0)
	await rig.leave_level(level)


func test_eight_points_keep_the_newest_seven():
	var snap := HFSnapSystemScript.new(null)
	for i in 8:
		snap.toggle_tracked(Vector3(i, 0, 0), HFSnapSystemScript.KIND_VERTEX)
	assert_eq(snap.tracked.size(), HFSnapSystemScript.TRACK_MAX)
	assert_eq(snap.tracked[0]["point"], Vector3(1, 0, 0), "the oldest went")


func test_where_a_guide_meets_a_brush_edge_beats_the_guide_alone():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var level = await _level()
	rig.box(level, "slope", Vector3(10, 1, 0), Vector3(4, 2, 4))
	var snap = level.snap_system
	snap.toggle_tracked(Vector3(9.3, 7, -6), HFSnapSystemScript.KIND_VERTEX)
	var landed: Vector3 = _hover(level, Vector3(9.4, 2.0, 2.05))
	assert_eq(landed, Vector3(9.3, 2, 2), "on the box's top edge, level with the vertex in X")
	assert_eq(snap.shown_pick["kind"], HFSnapSystemScript.KIND_GUIDE_EDGE)
	await rig.leave_level(level)
