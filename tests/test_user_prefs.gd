extends GutTest

const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")

var prefs: HFUserPrefsType

## The file tests below write the real preferences path, which is a developer's
## own file when the suite runs locally. It is moved aside for the run and put
## back afterwards.
const BACKUP_PATH := "user://hammerforge_prefs.json.test_backup"


func before_each():
	prefs = HFUserPrefsType.new()
	prefs.persistence_enabled = false
	prefs.data = HFUserPrefsType._defaults()
	_move(HFUserPrefsType.PREFS_PATH, BACKUP_PATH)


func after_each():
	prefs = null
	for leftover in [
		HFUserPrefsType.PREFS_PATH,
		HFUserPrefsType.PREFS_PATH + ".unreadable",
		HFUserPrefsType.PREFS_PATH + ".writing",
		HFUserPrefsType.PREFS_PATH + ".previous",
	]:
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(leftover))
	_move(BACKUP_PATH, HFUserPrefsType.PREFS_PATH)


func _move(from_path: String, to_path: String) -> void:
	if not FileAccess.file_exists(from_path):
		return
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path)
	)


# -- Tests ----------------------------------------------------------------------


func test_defaults_loaded():
	assert_eq(prefs.get_pref("grid_snap"), 16.0, "Default grid snap should be 16.0")
	assert_eq(prefs.get_pref("autosave_interval"), 300, "Default autosave interval should be 300")
	assert_eq(prefs.get_pref("show_hud"), true, "Default show_hud should be true")
	assert_eq(prefs.get_pref("show_welcome"), true, "Default show_welcome should be true")
	assert_eq(
		prefs.get_pref("power_user_overlays"),
		false,
		"Power-user overlays must stay off until opted in"
	)
	assert_eq(
		prefs.get_pref("hints_dismissed"),
		{},
		"Default hints_dismissed should be an empty dictionary"
	)


func test_power_user_overlays_helper_defaults_false():
	assert_false(
		prefs.is_power_user_overlays_enabled(),
		"Core-loop default must hide radial/coach/replay overlays"
	)


func test_power_user_overlays_helper_reads_pref():
	prefs.set_pref("power_user_overlays", true)
	assert_true(prefs.is_power_user_overlays_enabled())
	prefs.data.erase("power_user_overlays")
	assert_false(
		prefs.is_power_user_overlays_enabled(), "Missing key must fall back to the false default"
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


func test_hint_dismissed_default():
	assert_false(prefs.is_hint_dismissed("draw_idle"), "Hints should not be dismissed by default")


func test_dismiss_hint():
	prefs.dismiss_hint("draw_idle")
	assert_true(prefs.is_hint_dismissed("draw_idle"), "Dismissed hint should return true")
	assert_false(prefs.is_hint_dismissed("select"), "Other hints remain undismissed")


func test_hint_dismissed_roundtrip():
	prefs.dismiss_hint("select")
	prefs.dismiss_hint("paint_floor")
	var json_text = JSON.stringify(prefs.data, "\t")
	var parsed = JSON.parse_string(json_text)
	var loaded = HFUserPrefsType.new()
	loaded.data = parsed
	assert_true(loaded.is_hint_dismissed("select"), "select hint should survive roundtrip")
	assert_true(
		loaded.is_hint_dismissed("paint_floor"), "paint_floor hint should survive roundtrip"
	)
	assert_false(loaded.is_hint_dismissed("draw_idle"), "draw_idle should still be undismissed")


# -- What the file is allowed to contain ---------------------------------------


func test_a_wrong_typed_value_falls_back_to_the_default():
	# Each accessor reads its container into a typed local, so one wrong type is
	# not a wrong preference, it is an error on every call that touches it.
	var loaded = (
		HFUserPrefsType
		. _validated(
			{
				"collapsed_sections": "all",
				"recent_files": "res://a.tscn",
				"hints_dismissed": 3,
			}
		)
	)
	assert_eq(loaded["collapsed_sections"], {}, "A String is not a set of sections")
	assert_eq(loaded["recent_files"], [], "nor a list of recent files")
	assert_eq(loaded["hints_dismissed"], {}, "and a number is not a set of dismissals")


func test_the_accessors_work_after_a_wrong_typed_file():
	var broken = HFUserPrefsType.new()
	broken.persistence_enabled = false
	broken.data = HFUserPrefsType._validated(
		{"collapsed_sections": "all", "recent_files": "res://a.tscn", "hints_dismissed": 3}
	)
	assert_null(broken.get_section_collapsed("Bake"), "A section reads without erroring")
	broken.add_recent_file("res://kept.hflevel")
	assert_eq(broken.get_recent_files(), ["res://kept.hflevel"], "A recent file is recorded")
	broken.dismiss_hint("draw_idle")
	assert_true(broken.is_hint_dismissed("draw_idle"), "and a dismissal sticks")


func test_a_good_file_is_left_alone():
	var loaded = HFUserPrefsType._validated(
		{"grid_snap": 64.0, "show_hud": false, "recent_files": ["res://a.hflevel"]}
	)
	assert_eq(loaded["grid_snap"], 64.0)
	assert_eq(loaded["show_hud"], false)
	assert_eq(loaded["recent_files"], ["res://a.hflevel"])
	assert_eq(loaded["autosave_interval"], 300, "and the keys it did not carry come from defaults")


func test_json_numbers_are_not_treated_as_the_wrong_type():
	# JSON has one number type, so an int preference comes back as a float.
	var loaded = HFUserPrefsType._validated({"autosave_interval": 120.0, "grid_snap": 8})
	assert_eq(loaded["autosave_interval"], 120, "120.0 is the interval the user set")
	assert_eq(loaded["grid_snap"], 8.0, "and 8 is the grid snap they set")


func test_a_key_this_version_does_not_know_is_kept():
	var loaded = HFUserPrefsType._validated({"some_future_pref": "keep me"})
	assert_eq(loaded["some_future_pref"], "keep me", "A newer version's key survives a load")


func test_a_value_below_the_usable_range_is_clamped():
	var loaded = HFUserPrefsType._validated({"autosave_interval": -1, "grid_snap": 0.0})
	assert_eq(loaded["autosave_interval"], 0, "A negative interval is not an interval")
	assert_almost_eq(loaded["grid_snap"], 0.001, 0.0001, "and a zero grid snap is not a snap")


func test_set_pref_refuses_a_value_the_file_could_not_use():
	prefs.set_pref("autosave_interval", -1)
	assert_eq(prefs.get_pref("autosave_interval"), 0, "Clamped rather than written as -1")
	prefs.set_pref("grid_snap", "big")
	assert_eq(prefs.get_pref("grid_snap"), 16.0, "and a String leaves the grid snap alone")


func test_a_file_that_will_not_parse_is_kept_rather_than_overwritten():
	var path: String = HFUserPrefsType.PREFS_PATH
	var kept := path + ".unreadable"
	var damaged := '{"grid_snap": 64.0, "recent_files": ["res://a.tscn", "res://'
	var file = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "The test can write the prefs file")
	file.store_string(damaged)
	file.close()

	var loaded = HFUserPrefsType.load_prefs()
	assert_eq(loaded.get_pref("grid_snap"), 16.0, "The defaults are in use")
	assert_true(FileAccess.file_exists(kept), "and the damaged file is kept, not thrown away")
	var recovered = FileAccess.open(kept, FileAccess.READ)
	assert_eq(recovered.get_as_text(), damaged, "with what was in it")
	recovered.close()


func test_save_does_not_truncate_the_file_it_is_replacing():
	# `FileAccess.WRITE` truncates first, so a crash mid-write left half a file.
	# This writes beside the destination and moves it into place.
	var path: String = HFUserPrefsType.PREFS_PATH
	var writer = HFUserPrefsType.new()
	writer.data = HFUserPrefsType._defaults()
	writer.set_pref("grid_snap", 32.0)
	writer.save()
	assert_true(FileAccess.file_exists(path), "The file is written")
	assert_false(FileAccess.file_exists(path + ".writing"), "and the temporary is not left behind")
	var back = HFUserPrefsType.load_prefs()
	assert_eq(back.get_pref("grid_snap"), 32.0, "and reads back")
