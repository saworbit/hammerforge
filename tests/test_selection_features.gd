extends GutTest

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
const HFContextToolbar = preload("res://addons/hammerforge/ui/hf_context_toolbar.gd")
const HFSelectionFilter = preload("res://addons/hammerforge/ui/hf_selection_filter.gd")

# ===========================================================================
# Keymap tests for new bindings
# ===========================================================================

var keymap: HFKeymapType


func before_each():
	keymap = HFKeymapType.load_or_default("")


func after_each():
	keymap = null


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


func test_apply_last_texture_binding():
	var ev = _make_key(KEY_T, false, true)
	assert_true(keymap.matches("apply_last_texture", ev), "Shift+T should match apply_last_texture")


func test_apply_last_texture_no_shift():
	var ev = _make_key(KEY_T)
	assert_false(
		keymap.matches("apply_last_texture", ev), "T alone should not match apply_last_texture"
	)


func test_select_similar_binding():
	var ev = _make_key(KEY_S, false, true)
	assert_true(keymap.matches("select_similar", ev), "Shift+S should match select_similar")


func test_selection_filter_binding():
	var ev = _make_key(KEY_F, false, true)
	assert_true(keymap.matches("selection_filter", ev), "Shift+F should match selection_filter")


func test_texture_picker_unchanged():
	var ev = _make_key(KEY_T)
	assert_true(keymap.matches("texture_picker", ev), "T should still match texture_picker")


func test_new_actions_have_labels():
	assert_ne(
		HFKeymapType.get_action_label("apply_last_texture"),
		"apply_last_texture",
		"apply_last_texture should have a human label",
	)
	assert_ne(
		HFKeymapType.get_action_label("select_similar"),
		"select_similar",
		"select_similar should have a human label",
	)
	assert_ne(
		HFKeymapType.get_action_label("selection_filter"),
		"selection_filter",
		"selection_filter should have a human label",
	)


func test_new_actions_have_categories():
	assert_eq(
		HFKeymapType.get_category("apply_last_texture"),
		"Tools",
		"apply_last_texture should be in Tools category",
	)
	assert_eq(
		HFKeymapType.get_category("select_similar"),
		"Selection",
		"select_similar should be in Selection category",
	)
	assert_eq(
		HFKeymapType.get_category("selection_filter"),
		"Selection",
		"selection_filter should be in Selection category",
	)


func test_new_bindings_in_actions_list():
	var actions = keymap.get_actions()
	assert_true("apply_last_texture" in actions, "actions should include apply_last_texture")
	assert_true("select_similar" in actions, "actions should include select_similar")
	assert_true("selection_filter" in actions, "actions should include selection_filter")


func test_display_strings():
	assert_eq(keymap.get_display_string("apply_last_texture"), "Shift+T")
	assert_eq(keymap.get_display_string("select_similar"), "Shift+S")
	assert_eq(keymap.get_display_string("selection_filter"), "Shift+F")


# ===========================================================================
# Context toolbar label tests
# ===========================================================================


func test_toolbar_brush_label_count():
	var tb = HFContextToolbar.new()
	add_child(tb)
	(
		tb
		. update_state(
			{
				"has_root": true,
				"brush_count": 3,
				"entity_count": 0,
				"face_count": 0,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	assert_true(tb._label.text.contains("3"), "Label should show brush count")
	assert_true(tb._label.text.contains("selected"), "Label should say 'selected'")
	tb.queue_free()


func test_toolbar_face_label_shows_brush_count():
	var tb = HFContextToolbar.new()
	add_child(tb)
	(
		tb
		. update_state(
			{
				"has_root": true,
				"brush_count": 2,
				"entity_count": 0,
				"face_count": 5,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	assert_true(tb._label.text.contains("5"), "Label should show face count")
	assert_true(tb._label.text.contains("2"), "Label should show brush count in face context")
	tb.queue_free()


func test_toolbar_entity_selected_label():
	var tb = HFContextToolbar.new()
	add_child(tb)
	(
		tb
		. update_state(
			{
				"has_root": true,
				"brush_count": 0,
				"entity_count": 2,
				"face_count": 0,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	assert_true(tb._label.text.contains("2"), "Label should show entity count")
	assert_true(tb._label.text.contains("selected"), "Label should say selected")
	tb.queue_free()


# ===========================================================================
# Selection filter helpers (does not need tree — pure logic)
# ===========================================================================


func test_size_similar_identical():
	var sf = HFSelectionFilter.new()
	assert_true(
		sf._size_similar(Vector3(10, 20, 30), Vector3(10, 20, 30), 0.2),
		"Identical sizes should be similar",
	)
	sf.free()


func test_size_similar_within_tolerance():
	var sf = HFSelectionFilter.new()
	# 10% difference on each axis — well within 20% tolerance
	assert_true(
		sf._size_similar(Vector3(10, 20, 30), Vector3(11, 22, 33), 0.2),
		"Sizes within 20% should be similar",
	)
	sf.free()


func test_size_similar_beyond_tolerance():
	var sf = HFSelectionFilter.new()
	assert_false(
		sf._size_similar(Vector3(10, 20, 30), Vector3(20, 40, 60), 0.2),
		"Sizes at 100% difference should not be similar",
	)
	sf.free()


func test_size_similar_ignores_orientation():
	var sf = HFSelectionFilter.new()
	# Same dimensions in different order
	assert_true(
		sf._size_similar(Vector3(10, 20, 30), Vector3(30, 10, 20), 0.2),
		"Orientation-swapped sizes should be similar",
	)
	sf.free()
