extends GutTest

const HFHotkeyPalette = preload("res://addons/hammerforge/ui/hf_hotkey_palette.gd")
const HFKeymap = preload("res://addons/hammerforge/hf_keymap.gd")

var palette: HFHotkeyPalette
var keymap: HFKeymap


func before_each():
	palette = HFHotkeyPalette.new()
	keymap = HFKeymap.load_or_default()
	add_child(palette)
	palette.populate(keymap)


func after_each():
	palette.queue_free()
	palette = null
	keymap = null


# ===========================================================================
# Population
# ===========================================================================


func test_entries_populated():
	assert_gt(palette._entries.size(), 0)


func test_all_actions_have_buttons():
	for entry in palette._entries:
		assert_not_null(entry["button"])
		assert_true(entry["button"] is Button)


func test_categories_present():
	var cats := {}
	for entry in palette._entries:
		cats[entry["category"]] = true
	assert_true(cats.has("Tools"))
	assert_true(cats.has("Editing"))


# ===========================================================================
# Search filtering
# ===========================================================================


func test_search_filters_entries():
	palette._on_search_changed("hollow")
	var visible_count := 0
	for entry in palette._entries:
		if entry["button"].visible:
			visible_count += 1
	assert_eq(visible_count, 1)


func test_empty_search_shows_all():
	palette._on_search_changed("hollow")
	palette._on_search_changed("")
	var visible_count := 0
	for entry in palette._entries:
		if entry["button"].visible:
			visible_count += 1
	assert_eq(visible_count, palette._entries.size())


func test_search_by_binding():
	palette._on_search_changed("ctrl+h")
	var visible_count := 0
	for entry in palette._entries:
		if entry["button"].visible:
			visible_count += 1
	assert_gt(visible_count, 0)


# ===========================================================================
# Gray-out / availability
# ===========================================================================


func test_hollow_disabled_without_selection():
	(
		palette
		. update_state(
			{
				"brush_count": 0,
				"entity_count": 0,
				"paint_mode": false,
				"vertex_mode": false,
				"input_mode": 0,
				"tool": 0,
			}
		)
	)
	var hollow_entry = null
	for entry in palette._entries:
		if entry["action"] == "hollow":
			hollow_entry = entry
			break
	assert_not_null(hollow_entry)
	assert_true(hollow_entry["button"].disabled)


func test_hollow_enabled_with_brush_selection():
	(
		palette
		. update_state(
			{
				"brush_count": 1,
				"entity_count": 0,
				"paint_mode": false,
				"vertex_mode": false,
				"input_mode": 0,
				"tool": 0,
			}
		)
	)
	var hollow_entry = null
	for entry in palette._entries:
		if entry["action"] == "hollow":
			hollow_entry = entry
			break
	assert_not_null(hollow_entry)
	assert_false(hollow_entry["button"].disabled)


func test_mixed_selection_disables_managed_actions_but_keeps_tool_switches():
	(
		palette
		. update_state(
			{
				"brush_count": 1,
				"entity_count": 0,
				"face_count": 2,
				"mixed_selection": true,
				"paint_mode": false,
				"vertex_mode": false,
				"input_mode": 0,
				"tool": 1,
			}
		)
	)
	for action in ["delete", "hollow", "select_similar", "apply_last_texture", "selection_filter"]:
		var entry = _entry_for(action)
		assert_not_null(entry)
		if entry:
			assert_true(entry["button"].disabled, "%s must reject a mixed selection" % action)
	var draw_entry = _entry_for("tool_draw")
	assert_not_null(draw_entry)
	if draw_entry:
		assert_false(draw_entry["button"].disabled)


func test_paint_tools_disabled_outside_paint():
	(
		palette
		. update_state(
			{
				"brush_count": 0,
				"entity_count": 0,
				"paint_mode": false,
				"vertex_mode": false,
				"input_mode": 0,
				"tool": 0,
			}
		)
	)
	for entry in palette._entries:
		if entry["action"] == "paint_bucket":
			assert_true(entry["button"].disabled)
			return
	fail_test("paint_bucket entry not found")


func test_paint_tools_enabled_in_paint_mode():
	(
		palette
		. update_state(
			{
				"brush_count": 0,
				"entity_count": 0,
				"paint_mode": true,
				"vertex_mode": false,
				"input_mode": 0,
				"tool": 0,
			}
		)
	)
	for entry in palette._entries:
		if entry["action"] == "paint_bucket":
			assert_false(entry["button"].disabled)
			return
	fail_test("paint_bucket entry not found")


func test_tool_switches_always_enabled():
	(
		palette
		. update_state(
			{
				"brush_count": 0,
				"entity_count": 0,
				"paint_mode": false,
				"vertex_mode": false,
				"input_mode": 0,
				"tool": 0,
			}
		)
	)
	for entry in palette._entries:
		if entry["action"] == "tool_draw":
			assert_false(entry["button"].disabled)
			return
	fail_test("tool_draw entry not found")


func test_vertex_tools_disabled_outside_vertex_mode():
	(
		palette
		. update_state(
			{
				"brush_count": 0,
				"entity_count": 0,
				"paint_mode": false,
				"vertex_mode": false,
				"input_mode": 0,
				"tool": 0,
			}
		)
	)
	for entry in palette._entries:
		if entry["action"] == "vertex_merge":
			assert_true(entry["button"].disabled)
			return
	fail_test("vertex_merge entry not found")


func test_vertex_tools_enabled_in_vertex_mode():
	(
		palette
		. update_state(
			{
				"brush_count": 0,
				"entity_count": 0,
				"paint_mode": false,
				"vertex_mode": true,
				"input_mode": 0,
				"tool": 0,
			}
		)
	)
	for entry in palette._entries:
		if entry["action"] == "vertex_merge":
			assert_false(entry["button"].disabled)
			return
	fail_test("vertex_merge entry not found")


# ===========================================================================
# Toggle visibility
# ===========================================================================


func test_toggle_visible():
	assert_false(palette.visible)
	palette.toggle_visible()
	assert_true(palette.visible)
	palette.toggle_visible()
	assert_false(palette.visible)


# ===========================================================================
# Action invocation signal
# ===========================================================================


func test_action_invoked_signal():
	var received := []
	palette.action_invoked.connect(func(action): received.append(action))
	palette._on_entry_pressed("hollow")
	assert_eq(received, ["hollow"])
	assert_false(palette.visible)


func _entry_for(action: String):
	for entry in palette._entries:
		if entry["action"] == action:
			return entry
	return null


# ===========================================================================
# Row layout
#
# The binding used to be anchored with PRESET_CENTER_RIGHT, which puts a
# control's top-left corner on that point rather than aligning its right edge
# to it. Every binding therefore began at the row's right edge and ran past it,
# and the scroll container clipped all but the first character or two: "Ctrl+K"
# rendered as "Ctr". Caught by looking at the editor, not by these tests.
# ===========================================================================


func _binding_label(btn: Button) -> Label:
	for child in btn.get_children():
		if child is Label:
			return child
	return null


func test_binding_label_stays_inside_its_row():
	# Rows sit at their own minimum width until the palette gets a real layout
	# pass, and a binding trivially "fits" a row narrower than itself. Give each
	# row the width it has in the palette and measure against that.
	for entry in palette._entries:
		var btn: Button = entry["button"]
		btn.size = Vector2(300, 26)
		var bind := _binding_label(btn)
		assert_not_null(bind, "Every row carries its binding")
		assert_lte(
			bind.position.x + bind.size.x,
			btn.size.x,
			"Binding '%s' runs off the right of its row and gets clipped" % entry["binding"]
		)
		assert_gte(bind.position.x, 0.0, "Binding '%s' starts left of its row" % entry["binding"])


func test_binding_label_follows_a_row_that_changes_width():
	var btn: Button = palette._entries[0]["button"]
	var bind := _binding_label(btn)
	for width in [200.0, 320.0, 640.0]:
		btn.size = Vector2(width, 26)
		assert_almost_eq(
			bind.position.x + bind.size.x,
			width - HFHotkeyPalette.BIND_INSET,
			0.01,
			"The binding should hold its inset from the right edge at width %s" % width
		)


func test_binding_label_is_right_aligned_with_an_inset():
	var entry = palette._entries[0]
	var btn: Button = entry["button"]
	var bind: Label = null
	for child in btn.get_children():
		if child is Label:
			bind = child
			break
	assert_eq(bind.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
	assert_eq(bind.anchor_right, 1.0, "Follows the row's right edge as the palette resizes")
	assert_almost_eq(bind.offset_right, -HFHotkeyPalette.BIND_INSET, 0.01)


func test_binding_label_does_not_swallow_the_row_click():
	for entry in palette._entries:
		for child in entry["button"].get_children():
			if child is Label:
				assert_eq(child.mouse_filter, Control.MOUSE_FILTER_IGNORE)
