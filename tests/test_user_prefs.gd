extends GutTest

const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")

var prefs: HFUserPrefsType


func before_each():
	prefs = HFUserPrefsType.new()
	prefs.data = HFUserPrefsType._defaults()


func after_each():
	prefs = null


# -- Tests ----------------------------------------------------------------------


func test_defaults_loaded():
	assert_eq(prefs.get_pref("grid_snap"), 16.0, "Default grid snap should be 16.0")
	assert_eq(prefs.get_pref("autosave_interval"), 300, "Default autosave interval should be 300")
	assert_eq(prefs.get_pref("show_hud"), true, "Default show_hud should be true")
	assert_eq(prefs.get_pref("show_welcome"), true, "Default show_welcome should be true")
	assert_eq(
		prefs.get_pref("hints_dismissed"),
		{},
		"Default hints_dismissed should be an empty dictionary"
	)


func test_get_pref_fallback():
	var val = prefs.get_pref("nonexistent_key", "fallback_value")
	assert_eq(val, "fallback_value", "Missing key should return fallback")


func test_set_and_get_pref():
	prefs.set_pref("grid_snap", 8.0)
	assert_eq(prefs.get_pref("grid_snap"), 8.0, "Should return updated value")


func test_get_pref_uses_default_when_key_missing():
	prefs.data.erase("show_welcome")
	assert_eq(
		prefs.get_pref("show_welcome"),
		true,
		"Missing show_welcome key should fall back to defaults"
	)


func test_section_collapsed():
	prefs.set_section_collapsed("Bake", true)
	assert_eq(prefs.get_section_collapsed("Bake"), true, "Bake section should be collapsed")

	prefs.set_section_collapsed("Bake", false)
	assert_eq(prefs.get_section_collapsed("Bake"), false, "Bake section should be expanded")


func test_section_collapsed_unknown():
	var val = prefs.get_section_collapsed("UnknownSection")
	assert_null(val, "Unknown section should return null")


func test_recent_files_add():
	prefs.add_recent_file("res://map1.hflevel")
	prefs.add_recent_file("res://map2.hflevel")
	var recent = prefs.get_recent_files()
	assert_eq(recent.size(), 2, "Should have 2 recent files")
	assert_eq(recent[0], "res://map2.hflevel", "Most recent should be first")
	assert_eq(recent[1], "res://map1.hflevel", "Older should be second")


func test_recent_files_dedup():
	prefs.add_recent_file("res://map1.hflevel")
	prefs.add_recent_file("res://map2.hflevel")
	prefs.add_recent_file("res://map1.hflevel")
	var recent = prefs.get_recent_files()
	assert_eq(recent.size(), 2, "Duplicate should not increase count")
	assert_eq(recent[0], "res://map1.hflevel", "Re-added file should move to front")


func test_recent_files_max_10():
	for i in range(15):
		prefs.add_recent_file("res://map%d.hflevel" % i)
	var recent = prefs.get_recent_files()
	assert_eq(recent.size(), 10, "Recent files should max out at 10")
	assert_eq(recent[0], "res://map14.hflevel", "Most recent (last added) should be first")


func test_data_roundtrip_via_json():
	# Test that prefs data survives JSON serialization (simulates save/load)
	prefs.set_pref("grid_snap", 4.0)
	prefs.set_pref("show_welcome", false)
	prefs.set_pref("hints_dismissed", {"brush_hint": true, "paint_hint": false})
	prefs.set_section_collapsed("Bake", true)
	prefs.add_recent_file("res://test.hflevel")

	# Serialize and deserialize via JSON (same as save/load)
	var json_text = JSON.stringify(prefs.data, "\t")
	var parsed = JSON.parse_string(json_text)

	var loaded = HFUserPrefsType.new()
	loaded.data = parsed

	assert_eq(loaded.get_pref("grid_snap"), 4.0, "Loaded grid_snap should match saved")
	assert_eq(loaded.get_pref("show_welcome"), false, "Loaded show_welcome should match saved")
	assert_eq(
		loaded.get_pref("hints_dismissed"),
		{"brush_hint": true, "paint_hint": false},
		"Loaded hints_dismissed should match saved"
	)
	assert_eq(loaded.get_section_collapsed("Bake"), true, "Loaded section state should match")
	var recent = loaded.get_recent_files()
	assert_eq(recent.size(), 1, "Loaded recent files should have 1 entry")
