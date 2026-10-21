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


func test_grid_position_chords_are_distinct_from_nudging():
	for pair in [
		["grid_up", KEY_PAGEUP],
		["grid_down", KEY_PAGEDOWN],
		["grid_reset", KEY_HOME],
		["grid_align", KEY_END]
	]:
		assert_true(keymap.matches(pair[0], _make_key(pair[1], false, false, true)))
		assert_false(keymap.matches(pair[0], _make_key(pair[1])))
		assert_false(keymap.matches(pair[0], _make_key(pair[1], true)))
		assert_false(HFKeymapType.godot_3d_uses(_make_key(pair[1], false, false, true)))


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
	# Seven chords are shared on purpose - E is extrude, erase and edge mode; R is
	# rotate and ramp; X, Y and Z are axis locks and paint mirrors; Ctrl+B snaps
	# the selection or its vertices - and the input router gates each family on
	# its mode, so none of those can both fire.
	for action in keymap.get_actions():
		assert_eq(
			Array(keymap.conflicts_for(action)),
			[],
			"'%s' should not clash with anything that fires in the same mode" % action
		)


func test_intersect_is_ctrl_shift_i_and_clashes_with_nothing():
	assert_true(keymap.matches("intersect", _make_key(KEY_I, true, true)), "Ctrl+Shift+I")
	assert_false(keymap.matches("intersect", _make_key(KEY_I, true)), "not Ctrl+I")
	assert_eq(keymap.get_display_string("intersect"), "Ctrl+Shift+I")
	assert_eq(Array(keymap.conflicts_for("intersect")), [], "no other action fires on it")
	assert_false(
		HFKeymapType.godot_3d_uses(_make_key(KEY_I, true, true)), "Godot's 3D editor leaves it free"
	)


func test_apply_picked_look_is_alt_t_and_clashes_with_nothing():
	var alt_t := _make_key(KEY_T, false, false, true)
	assert_true(keymap.matches("apply_picked_look", alt_t), "Alt+T")
	assert_false(keymap.matches("apply_picked_look", _make_key(KEY_T)), "not T, the picker")
	assert_false(keymap.matches("apply_picked_look", _make_key(KEY_T, false, true)), "nor Shift+T")
	assert_eq(keymap.get_display_string("apply_picked_look"), "Alt+T")
	assert_eq(Array(keymap.conflicts_for("apply_picked_look")), [], "no other action fires on it")
	assert_false(HFKeymapType.godot_3d_uses(alt_t), "Godot's 3D editor leaves it free")


## Alt+1 to Alt+9 apply the context toolbar's favourites by number (#1439).
func test_apply_favorite_n_is_alt_n_and_clashes_with_nothing():
	for slot in range(1, 10):
		var action := "apply_favorite_%d" % slot
		var keycode: int = KEY_0 + slot
		var alt_digit := _make_key(keycode, false, false, true)
		assert_true(keymap.matches(action, alt_digit), "%s is Alt+%d" % [action, slot])
		assert_false(keymap.matches(action, _make_key(keycode)), "not the bare digit, a typed size")
		assert_false(keymap.matches(action, _make_key(keycode, true)), "nor Ctrl+%d" % slot)
		assert_eq(keymap.get_display_string(action), "Alt+%d" % slot)
		assert_eq(Array(keymap.conflicts_for(action)), [], "%s clashes with nothing" % action)
		assert_false(
			HFKeymapType.godot_3d_uses(alt_digit), "Godot's 3D editor leaves Alt+%d free" % slot
		)
		assert_eq(HFKeymapType.get_action_label(action), "Apply Favorite %d" % slot)
		assert_eq(HFKeymapType.get_category(action), "Tools", "listed beside Apply Last Texture")


func test_mirror_copy_is_alt_m_and_clashes_with_nothing():
	assert_true(keymap.matches("mirror_copy", _make_key(KEY_M, false, false, true)), "Alt+M")
	assert_false(keymap.matches("mirror_copy", _make_key(KEY_M, false, true)), "not Shift+M")
	assert_eq(keymap.get_display_string("mirror_copy"), "Alt+M")
	assert_eq(Array(keymap.conflicts_for("mirror_copy")), [], "no other action fires on it")
	assert_false(
		HFKeymapType.godot_3d_uses(_make_key(KEY_M, false, false, true)),
		"Godot's 3D editor leaves it free"
	)


## Beside Clip to Face Plane's Shift+Alt+X, the other command that reads a
## picked face. Ctrl+Shift+T is not free: the router keeps it for Operation
## Replay ahead of every binding.
func test_run_trim_along_faces_is_shift_alt_t_and_clashes_with_nothing():
	var chord := _make_key(KEY_T, false, true, true)
	assert_true(keymap.matches("run_trim_along_faces", chord), "Shift+Alt+T")
	assert_false(
		keymap.matches("run_trim_along_faces", _make_key(KEY_T, false, true)), "not Shift+T"
	)
	assert_false(
		keymap.matches("run_trim_along_faces", _make_key(KEY_T, false, false, true)), "nor Alt+T"
	)
	assert_eq(keymap.get_display_string("run_trim_along_faces"), "Shift+Alt+T")
	assert_eq(
		Array(keymap.conflicts_for("run_trim_along_faces")), [], "no other action fires on it"
	)
	assert_false(HFKeymapType.godot_3d_uses(chord), "Godot's 3D editor leaves it free")
	assert_eq(HFKeymapType.get_category("run_trim_along_faces"), "Editing")


## Draw on Face is L (#1401), which is the paint Line tool only while Paint is on.
func test_draw_on_face_is_l_and_shares_it_only_with_paint_line():
	assert_true(keymap.matches("toggle_draw_on_face", _make_key(KEY_L)), "L")
	assert_false(
		keymap.matches("toggle_draw_on_face", _make_key(KEY_L, false, true)), "not Shift+L"
	)
	assert_eq(keymap.get_display_string("toggle_draw_on_face"), "L")
	assert_eq(HFKeymapType.action_mode("toggle_draw_on_face"), "general")
	assert_eq(HFKeymapType.action_mode("paint_line"), "paint")
	assert_eq(Array(keymap.conflicts_for("toggle_draw_on_face")), [], "no general action has L")
	assert_eq(Array(keymap.conflicts_for("paint_line")), [], "and Paint's L is its own")
	assert_false(HFKeymapType.godot_3d_uses(_make_key(KEY_L)), "Godot's 3D editor leaves L free")
	assert_eq(HFKeymapType.get_action_label("toggle_draw_on_face"), "Draw on Face")


func test_offset_and_the_pivot_commands_are_alt_chords_that_clash_with_nothing():
	for entry in [
		["offset_selection", _make_key(KEY_G, false, false, true), "Alt+G"],
		["pick_pivot", _make_key(KEY_P, false, false, true), "Alt+P"],
		["clear_pivot", _make_key(KEY_P, false, true, true), "Shift+Alt+P"],
	]:
		var action: String = entry[0]
		var chord: InputEventKey = entry[1]
		assert_true(keymap.matches(action, chord), "%s is %s" % [action, entry[2]])
		assert_eq(keymap.get_display_string(action), entry[2])
		assert_eq(Array(keymap.conflicts_for(action)), [], "no other action fires on %s" % action)
		assert_false(HFKeymapType.godot_3d_uses(chord), "Godot's 3D editor leaves %s free" % action)
		assert_eq(HFKeymapType.get_category(action), "Transform", action)
	assert_false(keymap.matches("offset_selection", _make_key(KEY_G)), "not G, the grid double tap")
	assert_false(
		keymap.matches("offset_selection", _make_key(KEY_G, true)), "nor Ctrl+G, which is Group"
	)
	assert_false(keymap.matches("pick_pivot", _make_key(KEY_P, false, true, true)), "nor Clear")


## Ctrl+] and Ctrl+[ grow and shrink the selection (#1433); the bare brackets
## stay the grid size.
func test_grow_and_shrink_are_ctrl_brackets_and_clash_with_nothing():
	var ctrl_right := _make_key(KEY_BRACKETRIGHT, true)
	var ctrl_left := _make_key(KEY_BRACKETLEFT, true)
	assert_true(keymap.matches("grow_selection", ctrl_right), "Ctrl+]")
	assert_true(keymap.matches("shrink_selection", ctrl_left), "Ctrl+[")
	assert_false(keymap.matches("grow_selection", _make_key(KEY_BRACKETRIGHT)), "not ], the grid")
	assert_false(keymap.matches("grid_increase", ctrl_right), "and the grid keeps to bare ]")
	assert_false(keymap.matches("grid_decrease", ctrl_left), "and bare [")
	assert_eq(keymap.get_display_string("grow_selection"), "Ctrl+]")
	assert_eq(keymap.get_display_string("shrink_selection"), "Ctrl+[")
	for action in ["grow_selection", "shrink_selection"]:
		assert_eq(Array(keymap.conflicts_for(action)), [], "%s clashes with nothing" % action)
		assert_eq(HFKeymapType.get_category(action), "Selection")
	assert_false(HFKeymapType.godot_3d_uses(ctrl_right), "Godot's 3D editor leaves Ctrl+] free")
	assert_false(HFKeymapType.godot_3d_uses(ctrl_left), "and Ctrl+[")


## Alt+X turns Face Select's X-ray on and off (#1432).
func test_face_xray_is_alt_x_and_clashes_with_nothing():
	var alt_x := _make_key(KEY_X, false, false, true)
	assert_true(keymap.matches("toggle_face_xray", alt_x), "Alt+X")
	assert_false(keymap.matches("toggle_face_xray", _make_key(KEY_X)), "not X, the axis lock")
	assert_false(
		keymap.matches("toggle_face_xray", _make_key(KEY_X, false, true, true)),
		"nor Shift+Alt+X, Clip to Face Plane"
	)
	assert_eq(keymap.get_display_string("toggle_face_xray"), "Alt+X")
	assert_eq(Array(keymap.conflicts_for("toggle_face_xray")), [], "no other action fires on it")
	assert_false(HFKeymapType.godot_3d_uses(alt_x), "Godot's 3D editor leaves it free")


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


func test_snap_to_grid_is_ctrl_b_once_in_each_mode():
	# Two actions on one chord: action_mode() keeps a general action out of
	# vertex mode, and the vertex one is the selected vertices' snap (#1398).
	var ctrl_b := _make_key(KEY_B, true)
	var on_chord: Array = []
	for action in keymap.get_actions():
		if keymap.matches(action, ctrl_b):
			on_chord.append(action)
	on_chord.sort()
	assert_eq(on_chord, ["snap_to_grid", "vertex_snap_to_grid"], "nothing else is on Ctrl+B")
	assert_eq(HFKeymapType.action_mode("snap_to_grid"), "general")
	assert_eq(HFKeymapType.action_mode("vertex_snap_to_grid"), "vertex")
	assert_eq(Array(keymap.conflicts_for("snap_to_grid")), [], "so the two never clash")
	assert_eq(Array(keymap.conflicts_for("vertex_snap_to_grid")), [])
	assert_false(keymap.matches("snap_to_grid", _make_key(KEY_B)), "B alone is Paint Brush")
	assert_false(HFKeymapType.godot_3d_uses(ctrl_b), "Godot's 3D editor leaves Ctrl+B alone")
	assert_eq(keymap.get_display_string("snap_to_grid"), "Ctrl+B")
	assert_eq(keymap.get_display_string("vertex_snap_to_grid"), "Ctrl+B")


func test_toggle_paint_mode_is_a_general_action():
	# It turns paint mode on, so it cannot be gated behind paint mode.
	assert_eq(HFKeymapType.action_mode("toggle_paint_mode"), "general")
	assert_eq(HFKeymapType.action_mode("vertex_edit"), "general", "and so is the vertex toggle")


## Repeat Last Brush is Draw's own key with Shift (#1407).
func test_repeat_brush_is_shift_d_and_clashes_with_nothing():
	var shift_d := _make_key(KEY_D, false, true)
	assert_true(keymap.matches("repeat_brush", shift_d), "Shift+D")
	assert_false(keymap.matches("repeat_brush", _make_key(KEY_D)), "not D, which is Draw")
	assert_false(keymap.matches("tool_draw", shift_d), "and Draw does not take Shift+D")
	assert_false(keymap.matches("repeat_brush", _make_key(KEY_D, true)), "nor Ctrl+D, Duplicate")
	assert_eq(keymap.get_display_string("repeat_brush"), "Shift+D")
	assert_eq(Array(keymap.conflicts_for("repeat_brush")), [], "no other action fires on it")
	assert_false(HFKeymapType.godot_3d_uses(shift_d), "Godot's 3D editor leaves it free")
	assert_eq(HFKeymapType.get_action_label("repeat_brush"), "Repeat Last Brush")
	assert_eq(HFKeymapType.get_category("repeat_brush"), "Tools")


## Ctrl and Alt held through a drag are bindings, so the hints name whatever
## they are bound to, but they run no command (#1431, #1399).
func test_the_drag_holds_are_ctrl_and_alt_and_clash_with_nothing():
	assert_eq(keymap.get_display_string("snap_invert_hold"), "Ctrl")
	assert_eq(keymap.get_display_string("snap_vertex_hold"), "Alt")
	for hold in HFKeymapType.HOLDS:
		assert_eq(HFKeymapType.action_mode(hold), "hold", "%s is read, never matched" % hold)
		assert_eq(Array(keymap.conflicts_for(hold)), [], "%s clashes with nothing" % hold)
		assert_true(keymap.has_action(hold), "a hint can name %s" % hold)
		assert_false(keymap.get_actions().has(hold), "but the palette does not list it")
		assert_eq(HFKeymapType.get_action_label(hold), HFKeymapType.HOLDS[hold])
	keymap.set_binding("snap_vertex_hold", KEY_CTRL)
	assert_eq(
		Array(keymap.conflicts_for("snap_vertex_hold")),
		["snap_invert_hold"],
		"two holds on one key are reported"
	)


func test_a_hold_is_read_off_any_event():
	var motion := InputEventMouseMotion.new()
	assert_false(keymap.held("snap_invert_hold", motion))
	motion.ctrl_pressed = true
	assert_true(keymap.held("snap_invert_hold", motion), "a motion with Ctrl down")
	var press := _make_key(KEY_CTRL, true)
	assert_true(keymap.held("snap_invert_hold", press), "Ctrl's own press")
	press.pressed = false
	assert_false(keymap.held("snap_invert_hold", press), "and its release")
	var alt_motion := InputEventMouseMotion.new()
	alt_motion.alt_pressed = true
	assert_true(keymap.held("snap_vertex_hold", alt_motion))
	assert_false(keymap.held("snap_invert_hold", alt_motion))


func test_a_user_file_can_move_a_hold():
	var path := "user://test_keymap_hold_rebind.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"snap_invert_hold": {"keycode": "Shift"}}')
	file.close()
	var loaded := HFKeymapType.load_or_default(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(loaded.get_display_string("snap_invert_hold"), "Shift")
	var motion := InputEventMouseMotion.new()
	motion.shift_pressed = true
	assert_true(loaded.held("snap_invert_hold", motion), "Shift now inverts the grid")
	assert_eq(loaded.get_display_string("snap_vertex_hold"), "Alt", "the other keeps its default")
