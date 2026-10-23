extends GutTest

## The arrows move along what the view shows, and Shift with an arrow duplicates
## and moves (#1716).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFViewAxes = preload("res://addons/hammerforge/hf_view_axes.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func after_each():
	if rig.plugin and rig.plugin._user_prefs:
		rig.plugin._user_prefs.set_pref("nudge_follows_view", true)


func _camera(from: Vector3, to: Vector3, up: Vector3, orthogonal: bool) -> Camera3D:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.projection = (
		Camera3D.PROJECTION_ORTHOGONAL if orthogonal else Camera3D.PROJECTION_PERSPECTIVE
	)
	camera.look_at_from_position(from, to, up)
	return camera


func _moves(camera: Camera3D) -> Array:
	var out: Array = []
	for key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN]:
		out.append(HFViewAxes.nudge_direction(key, camera))
	return out


const FIXED_MOVES := [
	Vector3(0, 0, -1),
	Vector3(0, 0, 1),
	Vector3(-1, 0, 0),
	Vector3(1, 0, 0),
	Vector3.UP,
	Vector3.DOWN
]


func test_top_view_moves_exactly_as_before():
	var top := _camera(Vector3(0, 20, 0), Vector3.ZERO, Vector3.FORWARD, true)
	assert_eq(_moves(top), FIXED_MOVES)


func test_front_view_up_is_up():
	var front := _camera(Vector3(0, 1, 20), Vector3(0, 1, 0), Vector3.UP, true)
	assert_eq(HFViewAxes.nudge_direction(KEY_UP, front), Vector3.UP)
	assert_eq(HFViewAxes.nudge_direction(KEY_DOWN, front), Vector3.DOWN)
	assert_eq(HFViewAxes.nudge_direction(KEY_RIGHT, front), Vector3.RIGHT)


func test_a_perspective_view_facing_x_moves_up_along_x():
	var facing_x := _camera(Vector3(-10, 4, 0), Vector3(10, 0, 0), Vector3.UP, false)
	assert_eq(HFViewAxes.nudge_direction(KEY_UP, facing_x), Vector3.RIGHT)
	assert_eq(HFViewAxes.nudge_direction(KEY_DOWN, facing_x), Vector3.LEFT)
	assert_eq(HFViewAxes.nudge_direction(KEY_RIGHT, facing_x), Vector3.BACK, "right of +X is +Z")
	assert_eq(HFViewAxes.nudge_direction(KEY_PAGEUP, facing_x), Vector3.UP, "Page Up stays up")


func test_the_readout_names_the_axis_and_the_step():
	assert_eq(HFViewAxes.describe(Vector3(0, 0.25, 0)), "+Y 0.25 m")
	assert_eq(HFViewAxes.describe(Vector3(-0.5, 0, 0)), "-X 0.5 m")


func test_a_key_moves_along_the_view_and_the_setting_brings_back_the_fixed_way():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3(0, 1, 0))
	rig.select([box])
	rig.camera.look_at_from_position(Vector3(-10, 6, 0), Vector3(10, 0, 0))
	var step: float = level.grid_snap
	assert_eq(rig.forward(PluginRig.key(KEY_UP)), STOP)
	assert_almost_eq(box.global_position, Vector3(step, 1, 0), Vector3.ONE * 0.0001, "along +X")
	assert_eq(rig.plugin._nudge_readout[0], HFViewAxes.describe(Vector3(step, 0, 0)), "and says so")
	rig.plugin._user_prefs.set_pref("nudge_follows_view", false)
	assert_eq(rig.forward(PluginRig.key(KEY_UP)), STOP)
	assert_almost_eq(box.global_position, Vector3(step, 1, -step), Vector3.ONE * 0.0001, "-Z")
	rig.camera.look_at_from_position(Vector3(0, 12, 16), Vector3.ZERO)
	rig.select([])
	await rig.leave_level(level)


func test_shift_arrow_duplicates_and_moves_and_again_makes_a_row():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3(0, 1, 0))
	rig.select([box])
	rig.camera.look_at_from_position(Vector3(0, 20, 0.001), Vector3.ZERO)
	var step: float = level.grid_snap
	var steps: int = rig.undo().step_count()
	assert_eq(rig.forward(PluginRig.key(KEY_RIGHT, false, true)), STOP)
	assert_eq(rig.undo().step_count(), steps + 1, "one undo step")
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Duplicate and Move")
	assert_eq(rig.forward(PluginRig.key(KEY_RIGHT, false, true)), STOP)
	var xs: Array = level._iter_managed_brush_nodes().map(
		func(b): return snappedf(b.global_position.x, 0.001)
	)
	xs.sort()
	assert_eq(xs, [0.0, snappedf(step, 0.001), snappedf(step * 2.0, 0.001)], "a row of three")
	rig.undo().press_undo()
	assert_eq(level._iter_managed_brush_nodes().size(), 2, "undo takes the last copy back")
	rig.camera.look_at_from_position(Vector3(0, 12, 16), Vector3.ZERO)
	rig.select([])
	await rig.leave_level(level)
