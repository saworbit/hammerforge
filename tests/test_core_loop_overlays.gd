extends GutTest
## Core-loop freeze: power-user overlays stay off until opted in.

const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const HFPluginOverlays = preload("res://addons/hammerforge/plugin_overlays.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")
const HFConsoleControlsType = preload("res://addons/hammerforge/ui/hf_console_controls.gd")
const HFQuickPropertyType = preload("res://addons/hammerforge/ui/hf_quick_property.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")


func test_should_install_overlays_false_without_prefs():
	assert_false(
		HammerForgePlugin.should_install_power_user_overlays(null),
		"Missing prefs must not install radial/coach/replay overlays"
	)


func test_should_install_overlays_follows_pref():
	var prefs = HFUserPrefsType.new()
	prefs.persistence_enabled = false
	prefs.data = HFUserPrefsType._defaults()
	assert_false(HammerForgePlugin.should_install_power_user_overlays(prefs))
	prefs.set_pref("power_user_overlays", true)
	assert_true(HammerForgePlugin.should_install_power_user_overlays(prefs))


func test_unavailable_overlay_hint_names_both_places_that_carry_the_switch():
	# The toast is the only thing the reader has to go on after a key press did
	# nothing, so it names the dock — the shorter trip from the viewport — and
	# the Console, where every other HammerForge setting now lives.
	var hint := HammerForgePlugin.power_user_overlay_unavailable_message()
	assert_string_contains(hint, "Power-user overlays")
	assert_string_contains(hint, "Settings")
	assert_string_contains(hint, "Console")


func test_the_console_really_does_carry_the_switch_the_hint_points_at():
	# If the toggle is ever dropped from the Controls tab, the toast starts
	# sending people somewhere it is not.
	var found := false
	for group in HFConsoleControlsType.GROUPS:
		for spec in group["rows"]:
			if str(spec.get("pref", "")) == "power_user_overlays":
				found = true
	assert_true(found, "The hint points at the Console's Controls tab")


func test_the_dock_really_does_carry_the_switch_the_hint_points_at():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/ui/manage_tab_builder.gd")
	assert_string_contains(
		source,
		'_make_check("Power-user overlays"',
		"The hint points at Test -> Settings in the dock"
	)


## Each overlay callback plugin.gd owns reaches the overlay module and does its
## job: the power-user overlays come and go with the switch, a coach mark shows
## for an action and for a tool, G G opens the grid popup and its commit sets the
## grid, vertex mode draws its handles and leaving it takes them away, and the
## marquee state is kept for the viewport to draw.
func test_overlay_callbacks_delegate_to_the_overlay_module():
	var rig := PluginRig.new()
	await rig.bring_up(self)
	assert_not_null(rig.plugin, rig.error())
	var plugin: Node = rig.plugin
	var level = await rig.make_level()

	plugin._on_dock_power_user_overlays_changed(true)
	assert_not_null(plugin._coach_marks, "the switch installs the coach marks")
	assert_not_null(plugin._operation_replay, "the replay")
	assert_not_null(plugin._radial_menu, "and the radial menu")
	plugin._show_coach_mark_for_action("hollow")
	assert_eq(plugin._coach_marks.get_current_tool_key(), "hollow", "a coach mark for Hollow")
	plugin._show_coach_mark_for_tool_id(100)
	assert_eq(plugin._coach_marks.get_current_tool_key(), "measure", "and one for Measure")
	plugin._on_dock_power_user_overlays_changed(false)
	assert_null(plugin._coach_marks, "turning it off takes them away")
	assert_null(plugin._operation_replay)
	assert_null(plugin._radial_menu)

	var grid: float = plugin.dock.get_grid_snap()
	rig.forward(PluginRig.key(KEY_G))
	rig.forward(PluginRig.key(KEY_G))
	assert_true(plugin._quick_property.is_active(), "G G opens the quick property popup")
	assert_eq(plugin._quick_property._type, HFQuickPropertyType.PropertyType.GRID_SNAP, "for grid")
	plugin._quick_property.hide_popup()
	plugin._on_quick_property_committed(HFQuickPropertyType.PropertyType.GRID_SNAP, [4.0])
	assert_eq(plugin.dock.get_grid_snap(), 4.0, "and its commit sets the grid")
	plugin.dock._apply_grid_snap(grid)

	rig.select([rig.box(level, "v", Vector3.ZERO)])
	plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	plugin._update_vertex_overlay(level, rig.camera)
	var handles = plugin._vertex_overlay_mesh
	assert_true(is_instance_valid(handles) and handles.get_parent() == level, "handles are drawn")
	plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	assert_null(plugin._vertex_overlay_mesh, "and leaving vertex mode clears them")

	plugin._update_marquee_overlay(Vector2(10, 20), Vector2(110, 90), true)
	assert_true(plugin._marquee_overlay_active, "the marquee is kept for the viewport to draw")
	assert_eq(plugin._marquee_overlay_origin, Vector2(10, 20))
	assert_eq(plugin._marquee_overlay_current, Vector2(110, 90))
	plugin._update_marquee_overlay(Vector2.ZERO, Vector2.ZERO, false)
	assert_false(plugin._marquee_overlay_active)

	await rig.leave_level(level)
	await rig.take_down()


func test_the_viewport_draw_hook_draws_the_marquee_through_the_module():
	# A grep, because what it draws is canvas commands, which a test cannot read
	# back. The marquee state it draws from is checked above.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_true(source.contains("HFPluginOverlays.draw_marquee_overlay"))


func test_overlay_module_is_null_safe():
	HFPluginOverlays.show_quick_property(null, 0, [])
	HFPluginOverlays.on_quick_property_committed(null, 0, [])
	HFPluginOverlays.show_coach_mark_for_action(null, "clip")
	HFPluginOverlays.show_coach_mark_for_tool_id(null, 100)
	HFPluginOverlays.install_power_user_overlays(null)
	HFPluginOverlays.teardown_power_user_overlays(null)
	HFPluginOverlays.update_vertex_overlay(null, null)
	HFPluginOverlays.ensure_vertex_overlay(null, null)
	HFPluginOverlays.clear_vertex_overlay(null)
	HFPluginOverlays.update_marquee_overlay(null, Vector2.ZERO, Vector2.ZERO, false)
	HFPluginOverlays.draw_marquee_overlay(null, null)
	pass_test("Overlay entry points tolerate a missing coordinator")
