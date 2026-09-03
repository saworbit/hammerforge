extends GutTest
## Core-loop freeze: power-user overlays stay off until opted in.

const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const HFPluginOverlays = preload("res://addons/hammerforge/plugin_overlays.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")


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


func test_unavailable_overlay_hint_points_at_settings():
	var hint := HammerForgePlugin.power_user_overlay_unavailable_message()
	assert_string_contains(hint, "Power-user overlays")
	assert_string_contains(hint, "Settings")


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
