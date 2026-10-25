extends GutTest

## What a snap found, shown and steppable (#1691). A snapped point looked the
## same whatever it was on, the nearest candidate always won, and turning a snap
## off for one click meant a trip to the dock.

const HFSnapSystemType = preload("res://addons/hammerforge/hf_snap_system.gd")
const HFPluginSnapFeedbackType = preload("res://addons/hammerforge/plugin_snap_feedback.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const Rig = preload("res://tests/support/plugin_rig.gd")

const GRID := HFSnapSystemType.SnapMode.GRID
const VERTEX := HFSnapSystemType.SnapMode.VERTEX
const CENTER := HFSnapSystemType.SnapMode.CENTER
const EDGE := HFSnapSystemType.SnapMode.EDGE
const PERP := HFSnapSystemType.SnapMode.PERPENDICULAR

## Near the box's top corner at (1, 2, 1): the grid point (1, 2, 0.75) is 0.14
## away and the corner 0.18.
const NEAR_CORNER := Vector3(0.9, 2.0, 0.85)

var root: LevelRoot
var snap


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.grid_snap = 0.25
	snap = root.snap_system
	snap.snap_threshold = 0.5
	var box = DraftBrush.new()
	box.size = Vector3(2, 2, 2)
	box.brush_id = "box"
	root.draft_brushes_node.add_child(box)
	box.global_position = Vector3(0, 1, 0)


func after_each() -> void:
	root = null
	snap = null


func _modes(modes: int) -> void:
	snap.enabled_modes = modes


## A pointer query, as the viewport makes one: what it snapped and what it shows.
func _hover(point: Vector3) -> Dictionary:
	snap.begin_pointer_event()
	var landed: Vector3 = snap.snap_point(point, root.grid_snap)
	snap.end_pointer_event(true)
	return {"point": landed, "kind": str(snap.shown_pick.get("kind", ""))}


func test_each_candidate_says_what_it_is_on():
	_modes(VERTEX)
	assert_eq(_hover(Vector3(0.95, 2.0, 0.95))["kind"], "vertex")
	_modes(EDGE)
	var midpoint := _hover(Vector3(0.05, 2.0, 0.95))
	assert_eq(midpoint["kind"], "midpoint")
	assert_almost_eq(midpoint["point"], Vector3(0, 2, 1), Vector3.ONE * 0.001)
	_modes(CENTER)
	assert_eq(_hover(Vector3(0.1, 1.1, 0.0))["kind"], "centre")
	_modes(PERP)
	var foot := _hover(Vector3(0.95, 2.0, 0.4))
	assert_eq(foot["kind"], "perpendicular")
	assert_almost_eq(foot["point"], Vector3(1, 2, 0.4), Vector3.ONE * 0.001)
	_modes(GRID)
	assert_eq(_hover(NEAR_CORNER)["kind"], "grid")


func test_the_nearest_still_wins_until_tab_is_pressed():
	_modes(GRID | VERTEX)
	var first := _hover(NEAR_CORNER)
	assert_eq(first["kind"], "grid", "the grid point is nearer")
	assert_almost_eq(first["point"], Vector3(1, 2, 0.75), Vector3.ONE * 0.001)
	assert_true(snap.can_step(), "two kinds are in reach")


func test_tab_steps_through_the_kinds_and_the_click_takes_the_one_shown():
	_modes(GRID | VERTEX)
	_hover(NEAR_CORNER)
	assert_true(snap.step_choice())
	var stepped := _hover(NEAR_CORNER)
	assert_eq(stepped["kind"], "vertex", "Tab moves to the vertex")
	assert_almost_eq(stepped["point"], Vector3(1, 2, 1), Vector3.ONE * 0.001)
	# The click snaps the same point again and takes what is shown.
	snap.begin_pointer_event()
	assert_almost_eq(snap.snap_point(NEAR_CORNER, 0.25), Vector3(1, 2, 1), Vector3.ONE * 0.001)
	snap.end_pointer_event(false)
	assert_true(snap.step_choice())
	assert_eq(_hover(NEAR_CORNER)["kind"], "grid", "and round again")


func test_a_tab_step_lets_go_once_the_pointer_moves_away_or_a_pick_is_taken():
	_modes(GRID | VERTEX)
	_hover(NEAR_CORNER)
	snap.step_choice()
	_hover(Vector3(-3, 0, -3))
	assert_eq(_hover(NEAR_CORNER)["kind"], "grid", "moving off lets the step go")
	snap.step_choice()
	snap.pick_taken()
	assert_eq(_hover(NEAR_CORNER)["kind"], "grid", "a pick spends it")


func test_tab_has_nothing_to_step_with_one_kind_or_none_shown():
	_modes(GRID)
	_hover(NEAR_CORNER)
	assert_false(snap.step_choice(), "one kind only")
	_modes(GRID | VERTEX)
	snap.snap_point(NEAR_CORNER, 0.25)
	snap.shown_pick = {}
	assert_false(snap.step_choice(), "nothing shown")


func test_a_snap_outside_a_pointer_event_never_shows():
	_modes(GRID)
	snap.snap_point(NEAR_CORNER, 0.25)
	assert_eq(snap.shown_pick, {}, "a drop or a palette command is not marked")
	_hover(NEAR_CORNER)
	assert_false(snap.shown_pick.is_empty())
	snap.begin_pointer_event()
	snap.end_pointer_event(true)
	assert_eq(snap.shown_pick, {}, "a motion that snaps nothing takes the mark down")


func test_a_one_pick_limit_asks_for_one_kind_once():
	_modes(GRID)
	assert_true(snap.limit_next_pick("vertex"))
	var limited := _hover(NEAR_CORNER)
	assert_eq(limited["kind"], "vertex", "vertex snap was off and the limit asks for it")
	snap.pick_taken()
	assert_eq(_hover(NEAR_CORNER)["kind"], "grid", "then the running modes return")
	assert_eq(snap.next_pick_limit(), "")
	assert_false(snap.limit_next_pick("nonsense"), "a kind with no limit is refused")


func test_grid_only_snaps_to_the_grid_with_grid_off():
	_modes(VERTEX)
	snap.limit_next_pick("grid")
	var limited := _hover(NEAR_CORNER)
	assert_eq(limited["kind"], "grid")
	assert_almost_eq(limited["point"], Vector3(1, 2, 0.75), Vector3.ONE * 0.001)


func test_each_kind_has_its_own_marker_shape_and_label():
	var shapes := {
		"vertex": "square",
		"midpoint": "triangle",
		"centre": "circle",
		"perpendicular": "right angle",
		"grid": "cross",
		"line": "diamond",
		"guide": "bar",
		"guides": "x",
		"guide edge": "bowtie",
	}
	assert_eq(HFPluginSnapFeedbackType.SHAPES, shapes)
	var seen := {}
	for kind in shapes:
		var lines: PackedVector2Array = HFPluginSnapFeedbackType.marker_lines(kind)
		assert_gt(lines.size(), 0, "%s draws lines" % kind)
		assert_eq(lines.size() % 2, 0, "in pairs")
		assert_false(seen.has(lines), "%s is drawn unlike the others" % kind)
		seen[lines] = true
	assert_eq(HFPluginSnapFeedbackType.label_text("vertex"), "Vertex")
	assert_eq(HFPluginSnapFeedbackType.label_text("perpendicular"), "Perpendicular")
	assert_eq(HFPluginSnapFeedbackType.label_text("vertex", "vertex"), "Vertex only")


func test_the_labels_can_be_turned_off():
	var prefs := HFUserPrefs.new()
	assert_true(bool(prefs.get_pref("snap_labels", false)), "on by default")
	var found := false
	for group in load("res://addons/hammerforge/ui/hf_console_controls.gd").GROUPS:
		for row in group["rows"]:
			found = found or str(row.get("pref", "")) == "snap_labels"
	assert_true(found, "the Controls have a switch for them")


func test_the_drawing_runs_over_the_viewport():
	_modes(GRID | VERTEX)
	_hover(NEAR_CORNER)
	var plugin := PluginStub.new()
	plugin.active_root = root
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.look_at_from_position(Vector3(4, 6, 6), Vector3(1, 2, 1))
	plugin.last_3d_camera = camera
	var overlay := Control.new()
	overlay.size = Vector2(400, 300)
	add_child_autofree(overlay)
	var drawn := []
	overlay.draw.connect(
		func():
			HFPluginSnapFeedbackType.draw(plugin, overlay)
			drawn.append(true)
	)
	overlay.queue_redraw()
	await get_tree().process_frame
	assert_eq(drawn, [true], "the marker and label draw without an error")
	plugin.free()


class PluginStub:
	extends Object
	var active_root: Node = null
	var last_3d_camera: Camera3D = null
	var _user_prefs = null


# ---------------------------------------------------------------------------
# Through the real plugin
# ---------------------------------------------------------------------------


## The rig's camera looks at the origin through the middle of the view, so the
## middle hits the ground there. A box beside it has a corner 7 cm away.
func _rig_with_a_corner_by_the_origin() -> Array:
	var rig = Rig.new()
	await rig.bring_up(self)
	if rig.plugin == null:
		return [rig, null]
	var level = await rig.make_level()
	rig.box(level, "corner", Vector3(1.05, 1, 1.05), Vector3(2, 2, 2))
	level.snap_system.enabled_modes = GRID | VERTEX
	return [rig, level]


func test_tab_in_the_viewport_steps_the_draw_s_start_to_the_vertex():
	var made: Array = await _rig_with_a_corner_by_the_origin()
	var rig = made[0]
	var level = made[1]
	assert_not_null(rig.plugin, rig.error())
	if level == null:
		return
	rig.forward(Rig.motion(Vector2(400, 300)))
	var snap_system = level.snap_system
	assert_eq(str(snap_system.shown_pick.get("kind", "")), "grid", "the draw start is on the grid")
	assert_eq(rig.forward(Rig.key(KEY_TAB)), EditorPlugin.AFTER_GUI_INPUT_STOP, "Tab is taken")
	assert_eq(str(snap_system.shown_pick.get("kind", "")), "vertex", "and steps to the vertex")
	assert_almost_eq(
		level.draw_hover.shown.get("point", Vector3.INF),
		Vector3(0.05, 0, 0.05),
		Vector3.ONE * 0.001,
		"the draw would start on the vertex"
	)
	await rig.leave_level(level)
	await rig.take_down()


func test_polygon_path_and_measure_show_the_marker_too():
	var made: Array = await _rig_with_a_corner_by_the_origin()
	var rig = made[0]
	var level = made[1]
	assert_not_null(rig.plugin, rig.error())
	if level == null:
		return
	for tool_id in [102, 103, 100]:
		rig.plugin._activate_external_tool(tool_id, level)
		level.snap_system.shown_pick = {}
		rig.forward(Rig.motion(Vector2(400, 302)))
		rig.forward(Rig.motion(Vector2(400, 300)))
		assert_false(level.snap_system.shown_pick.is_empty(), "tool %d shows the snap" % tool_id)
	rig.plugin._deactivate_external_tool()
	await rig.leave_level(level)
	await rig.take_down()


func test_tab_with_no_snap_shown_is_left_alone():
	var rig = Rig.new()
	await rig.bring_up(self)
	assert_not_null(rig.plugin, rig.error())
	if rig.plugin == null:
		return
	var level = await rig.make_level()
	level.snap_system.shown_pick = {}
	assert_false(
		HFPluginSnapFeedbackType.step(rig.plugin, Rig.key(KEY_TAB)), "nothing to step, so it passes"
	)
	await rig.leave_level(level)
	await rig.take_down()


func test_a_limit_command_runs_from_the_palette():
	var rig = Rig.new()
	await rig.bring_up(self)
	assert_not_null(rig.plugin, rig.error())
	if rig.plugin == null:
		return
	var level = await rig.make_level()
	HFPluginCommands.execute(rig.plugin, "snap_next_midpoint")
	assert_eq(level.snap_system.next_pick_limit(), "midpoint")
	rig.forward(Rig.click(MOUSE_BUTTON_LEFT, false))
	assert_eq(level.snap_system.next_pick_limit(), "", "a left release spends it")
	await rig.leave_level(level)
	await rig.take_down()
