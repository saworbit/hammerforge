extends GutTest
## Core-loop freeze: power-user overlays stay off until opted in.

const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
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
