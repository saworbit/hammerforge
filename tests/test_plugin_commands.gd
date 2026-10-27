extends GutTest

const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")
const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")
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


## A bridge that keeps what it is asked and says yes.
class AskedBridge:
	extends RefCounted

	var asked: Array = []
	var last_changed := {}

	func handle_for_person(request: Dictionary) -> Dictionary:
		asked.append(request)
		return {"id": request.get("id"), "result": {"label": "Done"}}


## RecordingPlugin with a level and that bridge, as the command line reads them.
class BridgedPlugin:
	extends RecordingPlugin

	var mcp_dispatcher := AskedBridge.new()
	var hf_selection: Array = []
	var level: Node = null

	func _get_level_root():
		return level


## Extrude reads its Direction in its own arm. Rotate has no bridge form, so the
## command line takes no values for it and nor does a key.
const SETTINGS_READ_ELSEWHERE := ["tool_extrude", "rotate_ccw", "rotate_cw"]


## Every command with settings that `execute()` is handed runs with them, through
## the bridge as the command line runs it: what the bridge is asked carries the
## settings given. Only Extrude read them, and a key bound to Hollow with a
## thickness hollowed with the dock's (#1997).
func test_every_command_with_settings_runs_with_those_execute_is_given():
	var plugin := BridgedPlugin.new()
	plugin.level = Node.new()
	add_child_autoqfree(plugin.level)
	var ran := 0
	for id in HFCommandRegistry.dispatched_ids():
		var params: Array = HFCommandRegistry.params(id)
		if params.is_empty():
			continue
		if id in SETTINGS_READ_ELSEWHERE:
			assert_false(HFPluginCommands.takes_settings(id), id)
			continue
		var settings := {}
		for field_def in params:
			settings[str(field_def["key"])] = "given to %s" % id
		plugin.mcp_dispatcher.asked.clear()
		HFPluginCommands.execute(plugin, id, [], settings)
		var asked: Array = plugin.mcp_dispatcher.asked
		assert_eq(asked.size(), 1, "%s went to the bridge" % id)
		if asked.size() == 1:
			assert_eq(asked[0]["method"], "hf_run_command", id)
			assert_eq(asked[0]["params"]["command"], id)
			assert_eq(asked[0]["params"]["params"], settings, "%s took the settings given" % id)
		ran += 1
	assert_gt(ran, 10, "Hollow, Clip, the structures, Replace Material and the paint commands")


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


func _selected_entity(root: Node) -> Node:
	var entity = DraftEntityScript.new()
	entity.entity_type = "light_point"
	root.add_entity(entity)
	rig.select([entity])
	return entity


## Space opens the viewport menu, as a user does, and returns it.
func _open_viewport_menu() -> PopupMenu:
	var menu: PopupMenu = rig.plugin._viewport_context_menu
	assert_eq(
		rig.forward(PluginRig.key_for("context_menu")),
		EditorPlugin.AFTER_GUI_INPUT_STOP,
		"Space opens the viewport menu"
	)
	return menu


## The viewport menu ticks Highlight Connected while the level highlights, and
## picking it then turns the highlight off. Its state never carried the
## highlight, so the item was never ticked and always turned it on (#1450).
func test_the_viewport_menu_turns_highlight_connected_off_as_well_as_on():
	var root = await rig.make_level()
	_selected_entity(root)
	root.set_highlight_connected(true)
	var menu := _open_viewport_menu()
	assert_true(menu._state.get("highlight_connected", false), "the menu knows it is on")
	var item: int = menu.get_item_index(menu._ID_HIGHLIGHT_CONN)
	assert_gt(item, -1, "an entity's menu offers Highlight Connected")
	if item > -1:
		assert_true(menu.is_item_checked(item), "ticked, as the level highlights")
	menu.id_pressed.emit(menu._ID_HIGHLIGHT_CONN)
	assert_false(root.io_visualizer.highlight_connected, "picking it turns the highlight off")
	menu.hide()
	menu = _open_viewport_menu()
	item = menu.get_item_index(menu._ID_HIGHLIGHT_CONN)
	if item > -1:
		assert_false(menu.is_item_checked(item), "unticked once it is off")
	menu.id_pressed.emit(menu._ID_HIGHLIGHT_CONN)
	assert_true(root.io_visualizer.highlight_connected, "and picking it again turns it on")
	menu.hide()
	await rig.leave_level(root)


## The palette and the viewport menu read one state, so a key one command
## surface reads is there for the others with the same value (#1450).
func test_the_palette_and_the_viewport_menu_read_the_same_state():
	var root = await rig.make_level()
	_selected_entity(root)
	root.set_highlight_connected(true)
	var palette = rig.plugin._hotkey_palette
	rig.plugin._on_toggle_hotkey_palette()
	var palette_state: Dictionary = palette._state.duplicate()
	rig.plugin._on_toggle_hotkey_palette()
	await rig.frame()
	palette._search_field.release_focus()
	var menu := _open_viewport_menu()
	assert_gt(palette_state.size(), 10, "the palette was given the state")
	for key in palette_state:
		# The palette's own reading of the tool: vertex editing is a context of
		# its own there.
		if key == "tool":
			continue
		assert_true(menu._state.has(key), "the menu has %s" % key)
		assert_eq(menu._state.get(key), palette_state[key], "with the palette's %s" % key)
	menu.hide()
	await rig.leave_level(root)


func test_palette_root_guard_is_unchanged():
	assert_true(HammerForgePlugin.hotkey_palette_action_requires_existing_root("delete"))
	assert_false(HammerForgePlugin.hotkey_palette_action_requires_existing_root("tool_draw"))


func test_grid_key_dock_and_command_surfaces_move_the_same_plane():
	var root = await rig.make_level()
	root.grid_snap = 0.5
	rig.select([])
	var before: Dictionary = root.capture_state()
	for surface in ["key", "dock", "context toolbar", "command palette"]:
		root.grid_system.run_command("grid_reset")
		match surface:
			"key":
				assert_eq(
					rig.forward(PluginRig.key_for("grid_up")), EditorPlugin.AFTER_GUI_INPUT_STOP
				)
			"dock":
				var button: Button = rig.plugin.dock._grid_command_buttons["grid_up"]
				assert_string_contains(
					button.tooltip_text, rig.plugin._keymap.get_display_string("grid_up")
				)
				button.pressed.emit()
			_:
				_invoke(surface, "grid_up")
		assert_almost_eq(root.grid_plane_origin.y, 0.5, 0.001, surface)
		assert_eq(root.capture_state(), before, "grid positioning changes view state only")
	await rig.leave_level(root)
