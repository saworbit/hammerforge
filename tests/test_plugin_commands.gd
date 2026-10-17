extends GutTest

const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")
const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")


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


func test_palette_and_toolbar_still_guard_before_shared_dispatch():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for method_name in [
		"_on_context_toolbar_action",
		"_on_hotkey_palette_action",
		"_dispatch_viewport_action",
	]:
		var start := source.find("func %s" % method_name)
		var finish := source.find("\nfunc ", start + 1)
		var block := source.substr(start, finish - start)
		assert_true(
			block.contains("_managed_action_surface_allowed(root, action)"),
			"%s must keep the mixed-selection guard" % method_name
		)
		assert_true(
			block.contains("HFPluginCommands.execute"),
			"%s must route through the shared command module" % method_name
		)


func test_palette_root_guard_is_unchanged():
	assert_true(HammerForgePlugin.hotkey_palette_action_requires_existing_root("delete"))
	assert_false(HammerForgePlugin.hotkey_palette_action_requires_existing_root("tool_draw"))
