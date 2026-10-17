extends GutTest

const HFPluginInputRouter = preload("res://addons/hammerforge/plugin_input_router.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self)


func after_all():
	await rig.take_down()


func test_router_passes_on_null_inputs():
	assert_eq(
		HFPluginInputRouter.handle_keyboard(null, null, null, 0, false),
		EditorPlugin.AFTER_GUI_INPUT_PASS
	)


## A key over the viewport reaches the router through the plugin: ] doubles the
## grid, [ halves it, and both are consumed.
func test_plugin_wrapper_delegates_to_router():
	assert_not_null(rig.plugin, rig.error())
	var level = await rig.make_level()
	var dock = rig.plugin.dock
	var grid: float = dock.get_grid_snap()
	assert_eq(rig.forward(PluginRig.key_for("grid_increase")), STOP, "] is consumed")
	assert_eq(dock.get_grid_snap(), grid * 2.0, "and doubles the grid")
	assert_eq(rig.forward(PluginRig.key_for("grid_decrease")), STOP)
	assert_eq(dock.get_grid_snap(), grid, "[ halves it again")
	await rig.leave_level(level)


func test_the_guards_stay_in_the_router():
	# A grep on purpose: it keeps plugin.gd's keyboard callback thin, a boundary
	# the behaviour around it cannot see.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var start := source.find("func _handle_keyboard_input")
	var finish := source.find("func has_cancelable_rmb_gesture", start)
	var block := source.substr(start, finish - start)
	assert_false(block.contains("delete_guard"), "Guards live in the router, not the wrapper")


## An arrow key nudges only what HammerForge owns. A Godot selection gets the key
## back untouched; a mixed one is refused and the key consumed.
func test_router_keeps_nudge_ownership_guard():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO)
	var lamp = rig.native_node()
	rig.select([lamp])
	assert_eq(rig.forward(PluginRig.key(KEY_UP)), PASS, "a Godot selection is Godot's")
	rig.select([box, lamp])
	assert_eq(rig.forward(PluginRig.key(KEY_UP)), STOP, "a mixed one is refused")
	assert_eq(box.global_position, Vector3.ZERO, "and nothing moves")
	assert_eq(lamp.global_position, Vector3.ZERO)
	rig.select([box])
	assert_eq(rig.forward(PluginRig.key(KEY_UP)), STOP)
	assert_eq(box.global_position, Vector3(0, 0, -level.grid_snap), "a brush alone is nudged")
	await rig.leave_level(level)
