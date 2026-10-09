extends GutTest

## Bake profiles: the bake options, named and switched in one step.
##
## The shipping guide has a table of what to turn on for a shipped level and a
## checklist line saying to do it, and doing it meant flipping each checkbox by
## hand, then flipping them back to edit again. A profile is that set of values
## with a name. It decides how the level is built and never what goes into it,
## so the visibility switch and the cordons are left where the mapper put them.

var root: LevelRoot


func before_each():
	root = _level()


func after_each():
	HFLog.end_test_capture()
	root = null


func _level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


## A value the setting can hold that is not the one it holds.
func _other(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL:
			return not value
		TYPE_INT:
			return value + 1
		TYPE_FLOAT:
			return value * 0.5 if value > 0.0 else 1.0
	return null


func test_a_profile_carries_every_setting_that_decides_how_the_level_is_built():
	var names := HFBakeSystem.profile_setting_names()
	for name in HFBakeSystem.BAKE_SETTING_NAMES:
		if name in HFBakeSystem.SCOPE_SETTING_NAMES:
			assert_false(name in names, "%s decides what is baked, so a profile leaves it" % name)
		else:
			assert_true(name in names, "%s decides how the level is built" % name)
	for name in HFBakeSystem.SCOPE_SETTING_NAMES:
		# A name kept out that is not a bake setting at all keeps nothing out.
		assert_true(name in HFBakeSystem.BAKE_SETTING_NAMES, "%s is a bake setting" % name)


func test_a_profile_never_decides_what_goes_into_the_bake():
	var names := HFBakeSystem.profile_setting_names()
	assert_false("bake_visible_only" in names, "the visibility switch is a working view")
	for name in names:
		assert_false(name.begins_with("cordon_"), "%s is a cordon, which is the mapper's" % name)


func test_every_profile_setting_is_a_value_a_saved_profile_can_hold():
	# Saved profiles go to the preferences file as JSON. A setting that is not a
	# switch or a number has to be kept out of profiles or taught to them.
	for name in HFBakeSystem.profile_setting_names():
		var kind := typeof(root.get(name))
		assert_true(
			kind in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT],
			"%s is a %s, which a profile cannot carry" % [name, type_string(kind)]
		)


func test_the_built_in_profiles_name_profile_settings_with_the_level_types():
	assert_eq(
		HFBakeProfiles.built_in_names(),
		PackedStringArray(["Editing", "Shipping"]),
		"Editing and Shipping, the two columns of the shipping guide's table"
	)
	var names := HFBakeSystem.profile_setting_names()
	for profile in HFBakeProfiles.built_in_names():
		var values := HFBakeProfiles.built_in(profile)
		assert_false(values.is_empty(), "%s sets something" % profile)
		for key in values:
			assert_true(key in names, "%s sets %s, a profile setting" % [profile, key])
			assert_eq(
				typeof(values[key]),
				typeof(root.get(key)),
				"%s gives %s a value of the level's type" % [profile, key]
			)
	assert_eq(
		HFBakeProfiles.built_in("Editing").keys(),
		HFBakeProfiles.built_in("Shipping").keys(),
		"both switch the same options, so going back and forth loses nothing"
	)


func test_shipping_turns_on_what_every_shipped_level_wants_and_leaves_the_rest():
	root.bake_navmesh = true
	root.bake_lightmap_uv2 = false
	root.bake_generate_occluders = true
	root.bake_visible_only = true
	root.cordon_enabled = true
	root.apply_bake_options(HFBakeProfiles.built_in("Shipping"))
	assert_true(root.bake_merge_meshes, "one draw call instead of one per brush")
	assert_true(root.bake_generate_lods, "bake time once, frame time forever")
	assert_true(root.bake_navmesh, "only a game with pathfinding wants a navmesh: left alone")
	assert_false(root.bake_lightmap_uv2, "only baked lighting wants UV2: left alone")
	assert_true(root.bake_generate_occluders, "only interiors want occluders: left alone")
	assert_true(root.bake_visible_only, "what goes into the bake is not a profile's")
	assert_true(root.cordon_enabled, "nor are the cordons")


func test_editing_turns_them_back_off():
	root.apply_bake_options(HFBakeProfiles.built_in("Shipping"))
	root.apply_bake_options(HFBakeProfiles.built_in("Editing"))
	assert_false(root.bake_merge_meshes)
	assert_false(root.bake_generate_lods)


func test_a_new_level_is_on_editing():
	assert_eq(HFBakeProfiles.current(root, {}), "Editing", "the defaults are tuned for editing")


func test_the_level_reads_as_the_profile_it_was_switched_to():
	root.apply_bake_options(HFBakeProfiles.built_in("Shipping"))
	assert_eq(HFBakeProfiles.current(root, {}), "Shipping")


func test_an_option_changed_by_hand_reads_as_custom():
	root.apply_bake_options(HFBakeProfiles.built_in("Shipping"))
	root.bake_generate_lods = false
	assert_eq(HFBakeProfiles.current(root, {}), "", "neither profile, so neither name")


func test_a_saved_profile_that_matches_reads_ahead_of_the_built_in_inside_it():
	root.bake_navmesh = true
	var saved := {"Arena": root.capture_bake_options()}
	assert_true(HFBakeProfiles.matches(root, HFBakeProfiles.built_in("Editing")), "fixture")
	assert_eq(HFBakeProfiles.current(root, saved), "Arena", "the one that says more about it")
	root.bake_navmesh = false
	assert_eq(HFBakeProfiles.current(root, saved), "Editing", "and Editing once it no longer does")


func test_an_empty_profile_matches_nothing():
	# Every level agrees with a profile that sets nothing.
	assert_false(HFBakeProfiles.matches(root, {}))
	assert_eq(HFBakeProfiles.current(root, {"Nothing": {}}), "Editing")


func test_a_captured_profile_sets_every_option_on_another_level():
	var other := _level()
	for name in HFBakeSystem.profile_setting_names():
		root.set(name, _other(root.get(name)))
		assert_ne(root.get(name), other.get(name), "fixture: %s differs between the levels" % name)
	other.apply_bake_options(root.capture_bake_options())
	for name in HFBakeSystem.profile_setting_names():
		assert_eq(other.get(name), root.get(name), "%s came across" % name)


func test_switching_profile_asks_for_a_full_rebuild():
	var before: int = root.bake_system.bake_settings_signature()
	root._full_reconcile_needed = false
	root.apply_bake_options(HFBakeProfiles.built_in("Shipping"))
	assert_ne(root.bake_system.bake_settings_signature(), before, "the bake is out of date")
	assert_true(root._full_reconcile_needed, "and the next bake rebuilds rather than skipping")


func test_switching_profile_tells_the_dock():
	watch_signals(root)
	root.apply_bake_options(HFBakeProfiles.built_in("Shipping"))
	assert_signal_emitted(root, "settings_applied", "the dock resyncs its controls on this")


func test_a_profile_read_back_from_the_preferences_file_still_matches():
	root.bake_collision_mode = 2
	root.bake_connector_width = 3
	root.bake_lightmap_texel_size = 0.25
	var text := JSON.stringify({"Arena": root.capture_bake_options()})
	var read: Dictionary = JSON.parse_string(text)
	var other := _level()
	var values := HFBakeProfiles.validated(other, read["Arena"], "Arena")
	assert_eq(typeof(values["bake_collision_mode"]), TYPE_INT, "JSON's one number type, put back")
	other.apply_bake_options(values)
	assert_eq(other.bake_collision_mode, 2)
	assert_eq(other.bake_connector_width, 3)
	assert_true(HFBakeProfiles.matches(other, values), "and the level reads as that profile")


func test_what_a_profile_cannot_set_is_dropped_and_named():
	HFLog.begin_test_capture(["Arena"])
	var values := (
		HFBakeProfiles
		. validated(
			root,
			{
				"bake_merge_meshes": "yes",
				"bake_visible_only": true,
				"cordon_enabled": true,
				"bake_made_up": 1,
				"bake_collision_mode": 1.5,
				"bake_generate_lods": true,
				"bake_chunk_size": 16,
			},
			"Arena"
		)
	)
	assert_eq(
		values,
		{"bake_generate_lods": true, "bake_chunk_size": 16.0},
		"a switch that is not a switch, a setting that is not a profile's and a mode between two modes are gone"
	)
	var warnings := HFLog.get_captured_warnings()
	assert_eq(warnings.size(), 5, "one line for each value dropped")
	for line in warnings:
		assert_string_contains(line, "Arena", "naming the profile it came from")


func test_applying_a_value_of_the_wrong_kind_leaves_the_setting_alone():
	# Undo snapshots are always well formed. A profile from anywhere else goes
	# through validated() first, and the apply holds the same line anyway.
	HFLog.begin_test_capture(["bake_merge_meshes"])
	root.apply_bake_options({"bake_merge_meshes": "yes", "bake_generate_lods": true})
	assert_false(root.bake_merge_meshes, "a string is not a switch")
	assert_true(root.bake_generate_lods, "the usable value still lands")
	assert_eq(HFLog.get_captured_warnings().size(), 1)


func test_a_value_past_a_setting_limit_is_held_to_it():
	root.apply_bake_options({"bake_collision_mode": 99, "bake_lightmap_texel_size": -4.0})
	assert_eq(root.bake_collision_mode, 2, "the level's own setter keeps its range")
	assert_gt(root.bake_lightmap_texel_size, 0.0)


func test_a_profile_name_is_trimmed_and_may_not_take_a_name_the_list_uses():
	assert_eq(HFBakeProfiles.clean_name("  Arena  "), "Arena")
	assert_true(HFBakeProfiles.is_reserved_name("shipping"), "a built-in, whatever the case")
	assert_true(HFBakeProfiles.is_reserved_name("Custom"), "the list's name for no profile")
	assert_false(HFBakeProfiles.is_reserved_name("Shipping 2"))
	assert_eq(HFBakeProfiles.clean_name("x".repeat(80)).length(), HFBakeProfiles.MAX_NAME_LENGTH)


func test_saved_profiles_list_after_the_built_ins_in_name_order():
	var saved := {"zone b": {"bake_navmesh": true}, "Arena": {"bake_navmesh": false}}
	assert_eq(
		HFBakeProfiles.names(saved),
		PackedStringArray(["Editing", "Shipping", "Arena", "zone b"]),
		"built in first, then the saved ones as a person would sort them"
	)
