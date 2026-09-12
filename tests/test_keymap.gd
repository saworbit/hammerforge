extends GutTest

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

var keymap: HFKeymapType


func before_each():
	keymap = HFKeymapType.load_or_default("")


func after_each():
	keymap = null


# -- Helper: create a fake InputEventKey ----------------------------------------


func _make_key(
	keycode: int, ctrl: bool = false, shift: bool = false, alt: bool = false
) -> InputEventKey:
	var ev = InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	return ev


# -- Tests ----------------------------------------------------------------------


func test_default_bindings_loaded():
	var actions = keymap.get_actions()
	assert_true(actions.size() > 0, "Should have default bindings")
	assert_true("tool_draw" in actions, "Should have tool_draw action")
	assert_true("hollow" in actions, "Should have hollow action")
	assert_true("quick_play" in actions, "Should expose the primary preview workflow")
	assert_true("paint_fill" in actions, "Bucket fill should be a distinct action")


func test_matches_simple_key():
	var ev = _make_key(KEY_D)
	assert_true(keymap.matches("tool_draw", ev), "D should match tool_draw")


func test_matches_ctrl_key():
	var ev = _make_key(KEY_H, true)
	assert_true(keymap.matches("hollow", ev), "Ctrl+H should match hollow")


func test_no_match_wrong_key():
	var ev = _make_key(KEY_Q)
	assert_false(keymap.matches("tool_draw", ev), "Q should not match tool_draw")


func test_no_match_missing_modifier():
	# Hollow requires ctrl; pressing H without ctrl should not match
	var ev = _make_key(KEY_H, false)
	assert_false(keymap.matches("hollow", ev), "H without Ctrl should not match hollow")


func test_no_match_extra_modifier():
	# tool_draw is just D (no modifiers); pressing Ctrl+D should not match tool_draw
	var ev = _make_key(KEY_D, true)
	assert_false(keymap.matches("tool_draw", ev), "Ctrl+D should not match tool_draw")


func test_matches_shift_key():
	var ev = _make_key(KEY_X, false, true)
	assert_true(keymap.matches("clip", ev), "Shift+X should match clip")


func test_matches_ctrl_shift_key():
	var ev = _make_key(KEY_F, true, true)
	assert_true(keymap.matches("move_to_floor", ev), "Ctrl+Shift+F should match move_to_floor")


func test_workflow_shortcuts():
	assert_true(keymap.matches("toggle_operation", _make_key(KEY_Q)))
	assert_true(keymap.matches("toggle_paint_mode", _make_key(KEY_P, false, true)))
	assert_true(keymap.matches("quick_play", _make_key(KEY_ENTER, true)))
	assert_true(keymap.matches("validate_level", _make_key(KEY_ENTER, true, true)))


func test_context_menu_is_unmodified_space_only():
	assert_true(keymap.matches("context_menu", _make_key(KEY_SPACE)))
	assert_false(keymap.matches("context_menu", _make_key(KEY_SPACE, true)))
	assert_false(keymap.matches("context_menu", _make_key(KEY_SPACE, false, true)))
	assert_false(keymap.matches("context_menu", _make_key(KEY_SPACE, false, false, true)))
	var meta_space := _make_key(KEY_SPACE)
	meta_space.meta_pressed = true
	assert_false(keymap.matches("context_menu", meta_space))


func test_bucket_and_blend_have_distinct_shortcuts():
	assert_true(keymap.matches("paint_fill", _make_key(KEY_K)))
	assert_true(keymap.matches("paint_blend", _make_key(KEY_N)))
	assert_false(keymap.matches("paint_blend", _make_key(KEY_K)))


func test_wave_two_paint_actions_are_in_the_customizable_keymap():
	assert_true(keymap.matches("paint_mirror_x", _make_key(KEY_X)))
	assert_true(keymap.matches("paint_mirror_z", _make_key(KEY_Z)))
	assert_true(keymap.matches("paint_raise", _make_key(KEY_Y)))
	assert_true(keymap.matches("paint_room", _make_key(KEY_H)))
	assert_true(keymap.matches("paint_confirm_connector", _make_key(KEY_ENTER)))


func test_display_string_simple():
	var display = keymap.get_display_string("tool_draw")
	assert_eq(display, "D", "tool_draw display should be 'D'")


func test_display_string_ctrl():
	var display = keymap.get_display_string("hollow")
	assert_eq(display, "Ctrl+H", "hollow display should be 'Ctrl+H'")


func test_display_string_shift():
	var display = keymap.get_display_string("clip")
	assert_eq(display, "Shift+X", "clip display should be 'Shift+X'")


func test_display_string_ctrl_shift():
	var display = keymap.get_display_string("move_to_floor")
	assert_eq(display, "Ctrl+Shift+F", "move_to_floor display should be 'Ctrl+Shift+F'")


func test_workflow_category_and_labels():
	assert_eq(HFKeymapType.get_category("quick_play"), "Workflow")
	assert_eq(HFKeymapType.get_action_label("paint_fill"), "Bucket Fill")
	assert_eq(HFKeymapType.get_action_label("paint_blend"), "Blend")


func test_display_string_names_the_bracket_keys():
	# The guide tells the reader to press [ and ]. The palette used to answer
	# "Key91" and "Key93", which names no key on anybody's keyboard.
	assert_eq(keymap.get_display_string("grid_decrease"), "[")
	assert_eq(keymap.get_display_string("grid_increase"), "]")


func test_no_default_binding_renders_as_a_number():
	for action in keymap.get_all_bindings():
		var display := keymap.get_display_string(action)
		assert_false(
			display.contains("Key"),
			"%s renders as %s, which tells the user nothing" % [action, display]
		)


func test_display_string_unknown():
	var display = keymap.get_display_string("nonexistent_action")
	assert_eq(display, "?", "Unknown action display should be '?'")


func test_set_binding():
	keymap.set_binding("tool_draw", KEY_W)
	var ev = _make_key(KEY_W)
	assert_true(keymap.matches("tool_draw", ev), "After rebinding, W should match tool_draw")
	var ev_old = _make_key(KEY_D)
	assert_false(keymap.matches("tool_draw", ev_old), "After rebinding, D should no longer match")


func test_matches_nonexistent_action():
	var ev = _make_key(KEY_A)
	assert_false(keymap.matches("nonexistent", ev), "Nonexistent action should never match")


func test_data_roundtrip_via_json():
	# Test that keymap data survives JSON serialization (simulates save/load)
	keymap.set_binding("tool_draw", KEY_W, true)

	# Serialize and deserialize via JSON
	var json_text = JSON.stringify(keymap._bindings, "\t")
	var parsed = JSON.parse_string(json_text)

	var loaded = HFKeymapType.new()
	loaded._bindings = parsed

	var ev = _make_key(KEY_W, true)
	assert_true(loaded.matches("tool_draw", ev), "Loaded keymap should match saved binding")


# -- chords two actions can both answer ----------------------------------------


func test_the_shipped_defaults_have_no_conflicts():
	# Six chords are shared on purpose - E is extrude, erase and edge mode; R is
	# rotate and ramp; X, Y and Z are axis locks and paint mirrors - and the
	# input router gates each family on its mode, so none of those can both fire.
	for action in keymap.get_actions():
		assert_eq(
			Array(keymap.conflicts_for(action)),
			[],
			"'%s' should not clash with anything that fires in the same mode" % action
		)


func test_e_is_shared_across_three_modes_without_clashing():
	assert_eq(HFKeymapType.action_mode("tool_extrude"), "general")
	assert_eq(HFKeymapType.action_mode("paint_erase"), "paint")
	assert_eq(HFKeymapType.action_mode("vertex_edge_mode"), "vertex")
	assert_eq(Array(keymap.conflicts_for("paint_erase")), [], "Paint E only fires in paint mode")


func test_rebinding_onto_a_chord_that_fires_in_the_same_mode_is_reported():
	# Hollow onto Ctrl+G, which Group already uses. Both are general actions, so
	# the input router's first hit wins and the other becomes unreachable.
	keymap.set_binding("hollow", KEY_G, true)
	var clashes := keymap.conflicts_for("hollow")
	assert_eq(Array(clashes), ["group"], "The clash is named: %s" % str(clashes))
	assert_eq(Array(keymap.conflicts_for("group")), ["hollow"], "and it is reported both ways")


func test_rebinding_onto_a_chord_used_only_in_another_mode_is_not_a_conflict():
	keymap.set_binding("hollow", KEY_B)
	assert_eq(
		Array(keymap.conflicts_for("hollow")),
		[],
		"Paint Brush is B, but it only fires while paint mode is on"
	)


func test_a_modifier_makes_it_a_different_chord():
	keymap.set_binding("hollow", KEY_G, true, true)
	assert_eq(Array(keymap.conflicts_for("hollow")), [], "Ctrl+Shift+G is not Ctrl+G")


func test_toggle_paint_mode_is_a_general_action():
	# It turns paint mode on, so it cannot be gated behind paint mode.
	assert_eq(HFKeymapType.action_mode("toggle_paint_mode"), "general")
	assert_eq(HFKeymapType.action_mode("vertex_edit"), "general", "and so is the vertex toggle")
