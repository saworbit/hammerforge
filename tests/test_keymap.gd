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
