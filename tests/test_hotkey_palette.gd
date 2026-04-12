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
