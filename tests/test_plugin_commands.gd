extends GutTest

const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")
const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self)


func after_all():
	await rig.take_down()


func test_tool_switch_aliases_share_one_list():
	assert_true("extrude_up" in HFPluginCommands.TOOL_SWITCH_ACTIONS)
	assert_true("tool_extrude_up" in HFPluginCommands.TOOL_SWITCH_ACTIONS)
	assert_true("tool_draw" in HFPluginCommands.TOOL_SWITCH_ACTIONS)
	assert_true("tool_select" in HFPluginCommands.TOOL_SWITCH_ACTIONS)


func test_execute_is_a_noop_without_plugin_or_action():
	HFPluginCommands.execute(null, "delete")
	HFPluginCommands.execute(self, "")
	assert_true(true, "Null plugin or empty action must not crash")


## Just enough plugin for `execute()` to run an arm that needs no dock, and a
## record of the two calls every run that gets past the command table ends with.
class RecordingPlugin:
	extends RefCounted

	var active_root = null
	var dock = null
	var calls: Array = []

	func _get_level_root():
		return null

	func _show_coach_mark_for_action(action: String) -> void:
		calls.append("coach:" + action)

	func _update_hud_context() -> void:
		calls.append("hud")


func test_an_id_the_command_table_lacks_runs_nothing_and_says_so():
	var plugin := RecordingPlugin.new()
	HFLog.begin_test_capture(["no_such_command"])
	HFPluginCommands.execute(plugin, "no_such_command")
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(plugin.calls, [], "nothing past the table ran")
	assert_eq(warnings.size(), 1)
	assert_string_contains(str(warnings), "no_such_command")
	# The guard-only id is in the table, but no arm runs it.
	HFLog.begin_test_capture(["apply_context_material"])
	HFPluginCommands.execute(plugin, "apply_context_material")
	HFLog.end_test_capture()
	assert_eq(plugin.calls, [], "a guard-only id is not dispatched")


func test_an_id_in_the_command_table_runs_its_arm():
	var plugin := RecordingPlugin.new()
	HFPluginCommands.execute(plugin, "toggle_grid")
	assert_eq(plugin.calls, ["coach:toggle_grid", "hud"])


## The three surfaces that reach the shared dispatcher, each by the signal it
## fires when a user picks an action on it.
const SURFACES := ["context toolbar", "command palette", "viewport menu"]


func _invoke(surface: String, action: String) -> void:
	match surface:
		"context toolbar":
			rig.plugin._context_toolbar.action_requested.emit(action, [])
		"command palette":
			rig.plugin._hotkey_palette.action_invoked.emit(action)
		"viewport menu":
			rig.plugin._viewport_context_menu.action_requested.emit(action, [])


## Each surface asks the selection-scope guard before it hands the action to the
## shared dispatcher: Delete on a brush selected together with a Godot node
## deletes neither, and on the brush alone it deletes the brush.
func test_every_surface_guards_before_the_shared_dispatch():
	assert_not_null(rig.plugin, rig.error())
	for surface in SURFACES:
		var root = await rig.make_level()
		var brush = rig.box(root, "a", Vector3.ZERO)
		var lamp = rig.native_node()
		rig.select([brush, lamp])
		_invoke(surface, "delete")
		assert_not_null(root.find_brush_by_id("a"), "%s refused a mixed selection" % surface)
		assert_true(is_instance_valid(lamp), "%s left the Godot node alone" % surface)
		assert_has(rig.toasts(), "Edit HammerForge and Godot nodes separately", surface)
		rig.select([brush])
		_invoke(surface, "delete")
		assert_null(root.find_brush_by_id("a"), "%s ran Delete on the brush alone" % surface)
		await rig.leave_level(root)


func test_palette_root_guard_is_unchanged():
	assert_true(HammerForgePlugin.hotkey_palette_action_requires_existing_root("delete"))
	assert_false(HammerForgePlugin.hotkey_palette_action_requires_existing_root("tool_draw"))
