extends GutTest

## The timed autosave waits for a pause in editing, never longer than twice the
## interval, and leaves an unchanged level alone (#1736).

const HFAutosaveScheduler = preload("res://addons/hammerforge/systems/hf_autosave_scheduler.gd")
const HFInputState = preload("res://addons/hammerforge/input_state.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")


class CountingRoot:
	extends LevelRoot

	var saves := 0

	func save_hflevel(path: String = "", force: bool = false, autosave: bool = false) -> int:
		if autosave:
			saves += 1
		return OK


var root: CountingRoot
var scheduler: HFAutosaveScheduler
var now := 0


func before_each() -> void:
	root = CountingRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = true
	root.hflevel_autosave_minutes = 1
	add_child_autoqfree(root)
	scheduler = root.autosave_scheduler
	now = 0
	scheduler.clock = func() -> int: return now


func after_each() -> void:
	HFAutosaveScheduler.editor_state = Callable()
	scheduler = null


## Poll at `ms`. A waiting autosave looks again every quarter second, so polls
## here are further apart than that.
func _at(ms: int) -> void:
	now = ms
	scheduler.poll()


func test_a_timer_mid_drag_waits_for_the_drag_to_end_and_a_pause():
	watch_signals(root)
	root.input_state.mode = HFInputState.Mode.DRAG_BASE
	scheduler.on_timer()
	assert_eq(root.saves, 0, "not mid drag")
	assert_true(scheduler.waiting)
	assert_signal_emitted_with_parameters(root, "autosave_waiting", [true])
	_at(1000)
	assert_eq(root.saves, 0, "still dragging")
	root.input_state.mode = HFInputState.Mode.IDLE
	_at(1500)
	_at(2800)
	assert_eq(root.saves, 0, "not two seconds since the drag ended")
	_at(3200)
	assert_eq(root.saves, 1, "two seconds after it")
	assert_false(scheduler.waiting)
	assert_signal_emitted_with_parameters(root, "autosave_waiting", [false])


func test_a_change_during_the_wait_starts_the_pause_again():
	root.input_state.mode = HFInputState.Mode.DRAG_BASE
	scheduler.on_timer()
	root.input_state.mode = HFInputState.Mode.IDLE
	_at(500)
	root.create_brush_from_info({"size": Vector3(2, 2, 2), "center": Vector3(0, 1, 0)})
	_at(1800)
	_at(2600)
	assert_eq(root.saves, 0, "the brush moved the pause on")
	_at(3900)
	assert_eq(root.saves, 1)


func test_editing_that_never_pauses_still_saves_within_twice_the_interval():
	root.input_state.mode = HFInputState.Mode.SURFACE_PAINT
	scheduler.on_timer()
	_at(60000)
	assert_eq(root.saves, 0, "one interval in")
	_at(120001)
	assert_eq(root.saves, 1, "twice the interval")


func test_an_unchanged_level_is_not_captured():
	scheduler.on_timer()
	assert_eq(root.saves, 1, "the first timer saves")
	scheduler.on_timer()
	assert_eq(root.saves, 1, "nothing changed since")
	root.create_brush_from_info({"size": Vector3(2, 2, 2), "center": Vector3(0, 1, 0)})
	scheduler.on_timer()
	assert_eq(root.saves, 2, "a new brush is a change")


func test_the_editor_says_when_a_gesture_is_open_and_when_its_history_moved():
	var state := {"gesture": true, "version": 3}
	HFAutosaveScheduler.editor_state = func(_level: Node) -> Dictionary: return state
	scheduler.on_timer()
	assert_true(scheduler.waiting, "a gesture only the plugin sees")
	state["gesture"] = false
	_at(2500)
	assert_eq(root.saves, 1)
	scheduler.on_timer()
	assert_eq(root.saves, 1, "nothing changed")
	state["version"] = 4
	scheduler.on_timer()
	assert_eq(root.saves, 2, "an undo step is a change")


func test_a_failed_autosave_is_tried_again():
	scheduler.on_timer()
	scheduler.forget_saved()
	scheduler.on_timer()
	assert_eq(root.saves, 2)


func test_turning_autosave_off_ends_a_wait():
	root.input_state.mode = HFInputState.Mode.DRAG_BASE
	scheduler.on_timer()
	root.hflevel_autosave_enabled = false
	_at(1000)
	assert_false(scheduler.waiting)
	assert_eq(root.saves, 0)


func test_the_status_line_says_an_autosave_is_waiting():
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock._on_autosave_waiting(true)
	assert_eq(dock.status_label.text, "Autosave waiting for a pause")
	dock._on_autosave_waiting(false)
	assert_eq(dock.status_label.text, "Ready")
	dock._set_status("Baking...")
	dock._on_autosave_waiting(false)
	assert_eq(dock.status_label.text, "Baking...", "a later message is left alone")


func test_the_plugin_answers_for_the_editor_and_lets_go_when_it_closes():
	var rig = load("res://tests/support/plugin_rig.gd").new()
	await rig.bring_up(self, true)
	assert_not_null(rig.plugin, rig.error())
	if rig.plugin == null:
		return
	assert_true(HFAutosaveScheduler.editor_state.is_valid(), "set as the plugin starts")
	var level = await rig.make_level()
	var state: Dictionary = HFAutosaveScheduler.editor_state.call(level)
	assert_false(state["gesture"], "nothing open")
	var before := int(state["version"])
	rig.plugin._vertex_drag_active = true
	assert_true(HFAutosaveScheduler.editor_state.call(level)["gesture"], "a vertex drag")
	rig.plugin._vertex_drag_active = false
	var undo = rig.undo()
	undo.create_action("Probe")
	undo.add_do_property(level, "bake_chunk_size", 32.0)
	undo.add_undo_property(level, "bake_chunk_size", level.bake_chunk_size)
	undo.commit_action()
	assert_gt(int(HFAutosaveScheduler.editor_state.call(level)["version"]), before, "a step")
	await rig.take_down()
	assert_false(HFAutosaveScheduler.editor_state.is_valid(), "and let go as it closes")


func test_a_tool_with_points_placed_has_work_in_progress():
	var polygon = load("res://addons/hammerforge/hf_polygon_tool.gd").new()
	assert_false(polygon.has_work_in_progress())
	polygon._polygon_points.append(Vector3.ZERO)
	assert_true(polygon.has_work_in_progress())
	var path = load("res://addons/hammerforge/hf_path_tool.gd").new()
	assert_false(path.has_work_in_progress())
	path._waypoints.append(Vector3.ZERO)
	assert_true(path.has_work_in_progress())
	var clip = load("res://addons/hammerforge/hf_clip_tool.gd").new()
	assert_false(clip.has_work_in_progress())
	clip._points.append(Vector3.ZERO)
	assert_true(clip.has_work_in_progress())
