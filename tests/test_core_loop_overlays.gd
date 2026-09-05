extends GutTest
## Core-loop freeze: power-user overlays stay off until opted in.

const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const HFPluginOverlays = preload("res://addons/hammerforge/plugin_overlays.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")
const HFConsoleControlsType = preload("res://addons/hammerforge/ui/hf_console_controls.gd")


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
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/manage_tab_builder.gd"
	)
	assert_string_contains(
		source,
		'_make_check("Power-user overlays"',
		"The hint points at Test -> Settings in the dock"
	)


func test_overlay_callbacks_delegate_to_the_overlay_module():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for method_name in [
		"handle_double_tap",
		"show_quick_property",
		"on_quick_property_committed",
		"show_coach_mark_for_action",
		"show_coach_mark_for_tool_id",
		"install_power_user_overlays",
		"teardown_power_user_overlays",
		"update_vertex_overlay",
		"ensure_vertex_overlay",
		"clear_vertex_overlay",
		"update_marquee_overlay",
		"draw_marquee_overlay",
	]:
		assert_true(source.contains("HFPluginOverlays.%s" % method_name))


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
