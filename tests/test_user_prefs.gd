extends GutTest

const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")
const HFOverlayColors = preload("res://addons/hammerforge/hf_overlay_colors.gd")

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
	HFLog.end_test_capture()
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
	assert_eq(prefs.get_pref("grid_snap"), 0.5, "Default grid snap should be 0.5")
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


## The material browser's Recent row (#1422): newest first, each once, eight at
## most, and a material with no path left out, since nothing could find it again.
func test_recent_materials_put_the_newest_first_once_and_keep_eight():
	assert_eq(prefs.get_recent_materials(), [], "none to begin with")
	for i in range(10):
		assert_true(prefs.add_recent_material("res://mat_%d.tres" % i), "%d goes in" % i)
	var recent := prefs.get_recent_materials()
	assert_eq(recent.size(), HFUserPrefsType.RECENT_MATERIALS_MAX, "eight are kept")
	assert_eq(recent[0], "res://mat_9.tres", "the newest first")
	assert_eq(recent[7], "res://mat_2.tres", "and the two oldest are gone")

	assert_true(prefs.add_recent_material("res://mat_5.tres"), "one already in the row")
	recent = prefs.get_recent_materials()
	assert_eq(recent[0], "res://mat_5.tres", "moves to the front")
	assert_eq(recent.count("res://mat_5.tres"), 1, "and is not in the row twice")
	assert_eq(recent.size(), 8, "so nothing else drops out")

	assert_false(prefs.add_recent_material("res://mat_5.tres"), "the first again changes nothing")
	assert_false(prefs.add_recent_material(""), "and a material with no path is left out")
	assert_eq(prefs.get_recent_materials().size(), 8)


func test_recent_materials_survive_a_restart():
	prefs.add_recent_material("res://stone.tres")
	prefs.add_recent_material("res://brick.tres")
	var parsed = JSON.parse_string(JSON.stringify(prefs.data, "\t"))
	var loaded = HFUserPrefsType.new()
	loaded.data = HFUserPrefsType._validated(parsed)
	assert_eq(
		loaded.get_recent_materials(),
		["res://brick.tres", "res://stone.tres"],
		"the row comes back in the order it was left"
	)


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
	assert_eq(loaded["show_welcome"], true, "and the keys it did not carry come from defaults")


## JSON has one number type, so a float preference can come back as an int.
##
## `_usable()` coerces the other direction too, and no preference in the schema
## is a TYPE_INT any more - `autosave_interval` and `last_tool_id` were the two
## and neither was read by anything - so that half is kept for the next int
## preference rather than exercised here.
func test_json_numbers_are_not_treated_as_the_wrong_type():
	var loaded = HFUserPrefsType._validated({"grid_snap": 8})
	assert_eq(loaded["grid_snap"], 8.0, "8 is the grid snap the user set")


func test_a_key_this_version_does_not_know_is_kept():
	var loaded = HFUserPrefsType._validated({"some_future_pref": "keep me"})
	assert_eq(loaded["some_future_pref"], "keep me", "A newer version's key survives a load")


func test_a_value_below_the_usable_range_is_clamped():
	var loaded = HFUserPrefsType._validated({"grid_snap": 0.0})
	assert_almost_eq(loaded["grid_snap"], 0.001, 0.0001, "A zero grid snap is not a snap")


func test_set_pref_refuses_a_value_the_file_could_not_use():
	prefs.set_pref("grid_snap", "big")
	assert_eq(prefs.get_pref("grid_snap"), 0.5, "A String leaves the grid snap alone")
	prefs.set_pref("grid_snap", -1.0)
	assert_almost_eq(
		prefs.get_pref("grid_snap"), 0.001, 0.0001, "and a negative one is clamped, not written"
	)


func test_a_file_that_will_not_parse_is_kept_rather_than_overwritten():
	var path: String = HFUserPrefsType.PREFS_PATH
	var kept := path + ".unreadable"
	var damaged := '{"grid_snap": 64.0, "recent_files": ["res://a.tscn", "res://'
	var file = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "The test can write the prefs file")
	file.store_string(damaged)
	file.close()

	var loaded = HFUserPrefsType.load_prefs()
	assert_eq(loaded.get_pref("grid_snap"), 0.5, "The defaults are in use")
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


# -- The settings each tool was last used with (#1406) --------------------------

const HFToolRegistryType = preload("res://addons/hammerforge/hf_tool_registry.gd")
const PathToolType = preload("res://addons/hammerforge/hf_path_tool.gd")
const PolygonToolType = preload("res://addons/hammerforge/hf_polygon_tool.gd")
const DecalToolType = preload("res://addons/hammerforge/hf_decal_tool.gd")

## What each tool was left at: a value of every Path setting, Side included,
## Polygon's Auto-close Dist, and the Decal's three, none of them its default.
const LEFT_AT := {
	"Path":
	{
		"path_width": 3.0,
		"path_height": 3.5,
		"path_side": 1,
		"miter_joints": false,
		"path_extra": 2,
		"stair_step_height": 0.3,
		"railing_height": 1.2,
		"railing_thickness": 0.15,
		"railing_post_spacing": 3.0,
		"trim_width": 0.4,
		"trim_height": 0.2,
		"trim_material_idx": 5,
	},
	"Polygon": {"auto_close_threshold": 2.5},
	"Decal": {"texture": "res://textures/crack.png", "size": 3.0, "fade": 30.0},
}


## The preferences as the next session reads them: through the file's text and
## the schema, and never onto the disk.
func _restarted(from: HFUserPrefsType) -> HFUserPrefsType:
	var reread := HFUserPrefsType.new()
	reread.persistence_enabled = false
	reread.data = HFUserPrefsType._validated(JSON.parse_string(JSON.stringify(from.data, "\t")))
	return reread


## The built-in tools that keep settings, registered and kept in `store`, by name.
func _tools_kept_in(store: HFUserPrefsType) -> Dictionary:
	var registry := HFToolRegistryType.new()
	var tools := {"Path": PathToolType.new(), "Polygon": PolygonToolType.new()}
	tools["Decal"] = DecalToolType.new()
	for tool in tools.values():
		registry.register_tool(tool)
	registry.keep_settings_in(store)
	tools["registry"] = registry
	return tools


func test_every_tool_setting_survives_a_restart():
	var tools := _tools_kept_in(prefs)
	for tool_name in LEFT_AT:
		var tool = tools[tool_name]
		for key in LEFT_AT[tool_name]:
			tool.set_setting(key, LEFT_AT[tool_name][key])
	tools["Polygon"]._remembered_height = 3.5

	var next := _tools_kept_in(_restarted(prefs))
	for tool_name in LEFT_AT:
		for key in LEFT_AT[tool_name]:
			assert_eq(
				next[tool_name].get_setting(key),
				LEFT_AT[tool_name][key],
				"%s %s comes back as it was left" % [tool_name, key]
			)
	assert_eq(next["Path"].get_setting("path_side"), PathToolType.PathSide.LEFT, "Side too")
	assert_eq(
		next["Polygon"]._starting_height(), 3.5, "and a polygon starts at the last one's height"
	)


func test_a_tool_setting_set_from_its_list_keeps_the_choice_by_index():
	var tools := _tools_kept_in(prefs)
	tools["Path"].set_setting("path_side", "Right")
	assert_eq(tools["Path"].get_setting("path_side"), PathToolType.PathSide.RIGHT)
	assert_eq(prefs.get_tool_settings("Path")["path_side"], 2, "the file holds the index")


func test_a_kept_tool_setting_out_of_range_loads_clamped_with_a_warning():
	prefs.data[HFUserPrefsType.TOOL_SETTINGS] = {
		"Path": {"path_width": 900.0, "path_height": 0.0, "path_extra": 9.0},
		"Decal": {"size": "big"},
	}
	var tools := _tools_kept_in(_restarted(prefs))
	assert_eq(tools["Path"].get_setting("path_width"), 64.0, "held to Width's largest")
	assert_push_warning("user://hammerforge_prefs.json: 'tool_settings/Path/path_width' is 900")
	assert_eq(tools["Path"].get_setting("path_height"), 0.5, "and Height to its smallest")
	assert_push_warning("'tool_settings/Path/path_height' is 0")
	assert_eq(tools["Path"].get_setting("path_extra"), 3, "an option past the end is the last")
	assert_push_warning("'tool_settings/Path/path_extra' is 9")
	assert_eq(tools["Decal"].get_setting("size"), 2.0, "and a word where a size goes is not")
	assert_push_warning("'tool_settings/Decal/size' is a String")


func test_putting_a_kept_setting_back_does_not_write_the_file_again():
	prefs.data[HFUserPrefsType.TOOL_SETTINGS] = {"Path": {"path_width": 900.0}}
	_tools_kept_in(prefs)
	assert_eq(
		prefs.get_tool_settings("Path")["path_width"],
		900.0,
		"the file is left as it was until the mapper changes the setting"
	)
	assert_push_warning("path_width")


func test_a_setting_the_schema_does_not_name_is_not_kept():
	var tools := _tools_kept_in(prefs)
	tools["Path"].set_setting("scratch", 4.0)
	assert_false(prefs.get_tool_settings("Path").has("scratch"))


func test_a_number_is_held_to_both_ends_of_its_rule():
	var rule := {"type": TYPE_FLOAT, "min": 0.5, "max": 4.0}
	assert_eq(HFUserPrefsType.held_to("a", rule, 2.0, 1.0), 2.0)
	assert_eq(HFUserPrefsType.held_to("a", rule, 9.0, 1.0), 4.0)
	assert_push_warning("'a' is 9.0, above the largest usable value 4.0")
	assert_eq(HFUserPrefsType.held_to("a", rule, 0.0, 1.0), 0.5)
	assert_push_warning("'a' is 0.0, below the smallest usable value 0.5")
	var whole := {"type": TYPE_INT, "min": 3, "max": 64.0}
	assert_eq(HFUserPrefsType.held_to("b", whole, 99.0, 4), 64, "a whole number stays whole")
	assert_push_warning("'b' is 99")


func test_the_build_tab_and_the_structure_section_survive_a_restart():
	prefs.set_build_settings({"shape": "CYLINDER", "sides_round": 24, "cutout": true})
	prefs.set_build_settings({"hollow_thickness": 0.2})
	prefs.set_structure_type("stairs")
	prefs.set_structure_fields("arch", {"radius": 3.0})
	var back := _restarted(prefs)
	var build := back.get_build_settings()
	assert_eq(build["shape"], "CYLINDER")
	assert_eq(build["sides_round"], 24.0, "a number reads back as JSON has it")
	assert_eq(build["cutout"], true)
	assert_almost_eq(float(build["hollow_thickness"]), 0.2, 0.000001)
	var structure := back.get_structure_settings()
	assert_eq(structure["type"], "stairs")
	assert_eq(structure["fields"]["arch"]["radius"], 3.0)


func test_a_kept_section_of_the_wrong_type_falls_back_to_none():
	var loaded = HFUserPrefsType._validated(
		{"tool_settings": [], "build_settings": "cylinder", "structure_settings": 3}
	)
	assert_eq(loaded["tool_settings"], {})
	assert_eq(loaded["build_settings"], {})
	assert_eq(loaded["structure_settings"], {})
	assert_push_warning_count(3)


func test_reset_tool_settings_lets_go_of_every_kept_setting_and_the_tools_follow():
	var tools := _tools_kept_in(prefs)
	tools["Path"].set_setting("path_width", 3.0)
	tools["Polygon"]._remembered_height = 3.5
	prefs.set_build_settings({"shape": "CYLINDER"})
	prefs.set_structure_type("stairs")
	watch_signals(prefs)

	prefs.reset_tool_settings()

	assert_signal_emitted(prefs, "tool_settings_reset")
	assert_eq(prefs.get_tool_settings("Path"), {})
	assert_eq(prefs.get_build_settings(), {})
	assert_eq(prefs.get_structure_settings(), {})
	assert_eq(tools["Path"].get_setting("path_width"), 4.0, "the Path tool is back at its default")
	assert_eq(tools["Polygon"]._remembered_height, 0.0, "and the polygon height forgotten")
	assert_eq(_restarted(prefs).get_tool_settings("Path"), {}, "for the next session too")


func test_letting_go_of_the_store_stops_writing_to_it():
	var tools := _tools_kept_in(prefs)
	tools["registry"].keep_settings_in(null)
	tools["Path"].set_setting("path_width", 3.0)
	assert_eq(prefs.get_tool_settings("Path"), {}, "nothing is written once it is let go of")
	assert_false(
		prefs.tool_settings_reset.is_connected(tools["registry"]._on_settings_reset),
		"and it no longer listens for a reset"
	)


# -- Overlay colours (#1446) ---------------------------------------------------
# None of these reads or writes the preferences file: `prefs` does not save, and
# a file's contents go through `_validated()`.

const OVERLAY_COLOR_KEYS := [
	"color_selected_brush",
	"color_selected_face",
	"color_hover",
	"color_vertex_handle",
	"color_selected_vertex",
	"color_additive_brush",
	"color_subtractive_brush",
	"color_wireframe",
	"color_extrude_up",
	"color_extrude_down",
]


## Relative luminance, from an sRGB colour.
func _luminance(color: Color) -> float:
	return color.srgb_to_linear().get_luminance()


## The WCAG contrast ratio of two luminances: 1 is none, 21 black on white.
func _contrast(a: float, b: float) -> float:
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


func test_the_overlay_colours_are_preferences():
	assert_eq(
		HFOverlayColors.DEFAULTS.keys(), OVERLAY_COLOR_KEYS, "ten, in the order Settings lists them"
	)
	for key in OVERLAY_COLOR_KEYS:
		assert_true(HFUserPrefsType.SCHEMA.has(key), "%s is in the schema" % key)
		var rule: Dictionary = HFUserPrefsType.SCHEMA.get(key, {})
		assert_eq(rule.get("type"), TYPE_STRING, "%s is kept as a hex string" % key)
		assert_true(rule.get("color", false), "and held to being a colour")


func test_the_default_colours_are_the_look_they_replaced():
	# Each as it was written in the file that drew it before #1446.
	var before := {
		"color_selected_brush": Color(1.0, 0.82, 0.2, 0.75),
		"color_selected_face": Color(1.0, 0.55, 0.0, 0.3),
		"color_hover": Color(1.0, 1.0, 0.0, 0.5),
		"color_vertex_handle": Color.WHITE,
		"color_selected_vertex": Color.ORANGE,
		"color_additive_brush": Color(0.2, 0.8, 0.2, 0.35),
		"color_subtractive_brush": Color(1.0, 0.2, 0.2, 0.35),
		"color_wireframe": Color(1.0, 0.8, 0.0, 0.6),
		"color_extrude_up": Color(0.2, 0.8, 0.3, 0.35),
		"color_extrude_down": Color(0.8, 0.2, 0.2, 0.35),
	}
	for key in OVERLAY_COLOR_KEYS:
		var stored = prefs.get_pref(key)
		assert_true(stored is String, "%s defaults to a string" % key)
		# Exactly, not to the eight bits a channel the string keeps.
		assert_eq(HFOverlayColors.from_pref(stored, key), before[key], key)


func test_a_picked_colour_is_kept_as_hex_and_reads_back():
	prefs.set_pref("color_hover", Color(0.0, 0.0, 1.0, 0.5))
	assert_eq(prefs.get_pref("color_hover"), "#0000ff80", "a picker's Color is kept as its string")
	var parsed = JSON.parse_string(JSON.stringify(prefs.data, "\t"))
	var loaded: Dictionary = HFUserPrefsType._validated(parsed)
	assert_eq(loaded["color_hover"], "#0000ff80", "and survives a save and a load")
	var back := HFOverlayColors.from_pref(loaded["color_hover"], "color_hover")
	assert_almost_eq(back.b, 1.0, 0.001)
	assert_almost_eq(back.a, 0.5, 0.01)


func test_high_contrast_sets_every_colour_and_reset_puts_them_back():
	prefs.set_overlay_colors(HFOverlayColors.HIGH_CONTRAST)
	for key in OVERLAY_COLOR_KEYS:
		assert_true(HFOverlayColors.HIGH_CONTRAST.has(key), "the preset names %s" % key)
		assert_eq(
			prefs.get_pref(key),
			HFOverlayColors.to_pref(HFOverlayColors.HIGH_CONTRAST.get(key, Color.BLACK)),
			"and sets it"
		)
	prefs.set_overlay_colors(HFOverlayColors.DEFAULTS)
	var defaults := HFUserPrefsType._defaults()
	for key in OVERLAY_COLOR_KEYS:
		assert_eq(prefs.get_pref(key), defaults[key], "%s is back to its default" % key)


func test_a_preset_that_leaves_a_colour_out_sets_it_to_its_default():
	prefs.set_pref("color_hover", Color.RED)
	prefs.set_overlay_colors({"color_wireframe": Color.BLUE})
	assert_eq(prefs.get_pref("color_wireframe"), "#0000ffff")
	assert_eq(
		prefs.get_pref("color_hover"),
		HFUserPrefsType._defaults()["color_hover"],
		"so a preset is always the whole palette"
	)


func test_high_contrast_tells_solids_from_cuts_by_brightness():
	var hc: Dictionary = HFOverlayColors.HIGH_CONTRAST
	var solid := _luminance(hc[HFOverlayColors.ADDITIVE_BRUSH])
	var cut := _luminance(hc[HFOverlayColors.SUBTRACTIVE_BRUSH])
	# Red and green, the pair red-green colour blindness merges, sit at nearly
	# one brightness by default. The preset has to differ in brightness alone.
	assert_gt(_contrast(solid, cut), 2.0, "a solid and a cut differ in brightness")
	var up := _luminance(hc[HFOverlayColors.EXTRUDE_UP])
	var down := _luminance(hc[HFOverlayColors.EXTRUDE_DOWN])
	assert_gt(_contrast(up, down), 2.0, "and so do extruding out and in")
	assert_ne(
		hc[HFOverlayColors.HOVER],
		hc[HFOverlayColors.SELECTED_BRUSH],
		"and hover is not the selection's colour"
	)


func test_a_colour_that_is_not_one_falls_back_with_one_warning():
	HFLog.begin_test_capture(["color_hover", "color_wireframe"])
	var loaded = (
		HFUserPrefsType
		. _validated(
			{
				"color_hover": 3,
				"color_wireframe": "plaid",
				"color_selected_brush": "#00ff00ff",
			}
		)
	)
	var warnings := HFLog.get_captured_warnings()
	var defaults := HFUserPrefsType._defaults()
	assert_eq(loaded["color_hover"], defaults["color_hover"], "a number is not a colour")
	assert_eq(loaded["color_wireframe"], defaults["color_wireframe"], "nor a word")
	assert_eq(loaded["color_selected_brush"], "#00ff00ff", "and a good one is kept")
	assert_eq(warnings.size(), 2, "one warning for each that is not")
	var said := "\n".join(PackedStringArray(warnings))
	assert_string_contains(said, "color_hover")
	assert_string_contains(said, "color_wireframe")


func test_set_pref_refuses_a_colour_it_could_not_read_back():
	HFLog.begin_test_capture(["color_hover"])
	prefs.set_pref("color_hover", "not a colour")
	assert_eq(prefs.get_pref("color_hover"), HFUserPrefsType._defaults()["color_hover"])
	assert_eq(HFLog.get_captured_warnings().size(), 1)
