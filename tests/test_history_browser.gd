extends GutTest

const HFHistoryBrowserScript = preload("res://addons/hammerforge/ui/hf_history_browser.gd")

var browser: HFHistoryBrowser


func before_each():
	browser = HFHistoryBrowserScript.new()
	add_child(browser)


func after_each():
	browser.queue_free()
	browser = null


func test_initial_empty():
	assert_eq(browser.get_entry_count(), 0)


func test_record_entry():
	browser.record_entry("Create Brush", 1)
	assert_eq(browser.get_entry_count(), 1)


func test_record_multiple_entries():
	browser.record_entry("Create Brush", 1)
	browser.record_entry("Move Brush", 2)
	browser.record_entry("Delete Brush", 3)
	assert_eq(browser.get_entry_count(), 3)


func test_max_entries_cap():
	for i in range(40):
		browser.record_entry("Action %d" % i, i)
	assert_eq(browser.get_entry_count(), browser.MAX_ENTRIES)


func test_clear():
	browser.record_entry("Create Brush", 1)
	browser.record_entry("Move Brush", 2)
	browser.clear()
	assert_eq(browser.get_entry_count(), 0)


func test_undo_button_exists():
	var btn: Button = browser.get_undo_button()
	assert_not_null(btn)
	assert_eq(btn.text, "Undo")


func test_redo_button_exists():
	var btn: Button = browser.get_redo_button()
	assert_not_null(btn)
	assert_eq(btn.text, "Redo")


func test_navigate_signal_declared():
	assert_true(browser.has_signal("navigate_requested"))


func test_entry_has_icon_and_color():
	browser.record_entry("Create Brush", 1)
	var entry: Dictionary = browser._entries[0]
	assert_has(entry, "icon_char")
	assert_has(entry, "color")
	assert_eq(entry["icon_char"], "+")  # "create" maps to "+"


func test_entry_delete_icon():
	browser.record_entry("Delete Brush", 1)
	var entry: Dictionary = browser._entries[0]
	assert_eq(entry["icon_char"], "x")


func test_entry_carve_icon():
	browser.record_entry("Carve Selection", 1)
	var entry: Dictionary = browser._entries[0]
	assert_eq(entry["icon_char"], "#")


func test_thumbnail_is_null_in_headless():
	# In headless test mode, thumbnail capture returns null (no viewport)
	browser.record_entry("Test", 1)
	var entry: Dictionary = browser._entries[0]
	# Thumbnail may be null in headless — that's expected
	assert_has(entry, "thumbnail")


func test_hidden_browser_skips_thumbnail_capture():
	browser.visible = false
	browser.record_entry("Create Brush", 1)
	assert_eq(browser.get_entry_count(), 1)
	assert_null(browser._entries[0]["thumbnail"], "Hidden history should not GPU-readback")


func test_record_entry_appends_without_dropping_existing_rows():
	browser.record_entry("Create Brush", 1)
	browser.record_entry("Move Brush", 2)
	assert_eq(browser._list.get_child_count(), 2)


# ===========================================================================
# Hover preview must not disturb the dock layout (#142)
# ===========================================================================


func _thumbnail() -> ImageTexture:
	var img := Image.create(browser.THUMB_WIDTH, browser.THUMB_HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return ImageTexture.create_from_image(img)


func _record_with_thumbnail(action_name: String, version: int) -> void:
	browser.record_entry(action_name, version)
	browser._entries[browser._entries.size() - 1]["thumbnail"] = _thumbnail()
	browser._rebuild_list()


func test_preview_is_outside_the_box_layout():
	assert_true(
		browser._preview_rect.top_level,
		"An in-flow preview makes the container reserve space for it"
	)


func test_showing_the_preview_does_not_change_the_container_height():
	_record_with_thumbnail("Create Brush", 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var before := browser.get_combined_minimum_size().y
	browser._on_row_hovered(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var during := browser.get_combined_minimum_size().y
	browser._on_row_unhovered()
	await get_tree().process_frame
	await get_tree().process_frame
	var after := browser.get_combined_minimum_size().y
	assert_true(browser._preview_rect.visible == false)
	assert_almost_eq(during, before, 0.001, "Hovering must not grow the panel")
	assert_almost_eq(after, before, 0.001, "Unhovering must not shrink it back")


func test_hover_shows_the_thumbnail():
	_record_with_thumbnail("Create Brush", 1)
	browser._on_row_hovered(0)
	assert_true(browser._preview_rect.visible)
	assert_not_null(browser._preview_rect.texture)
	browser._on_row_unhovered()
	assert_false(browser._preview_rect.visible)


func test_preview_anchor_follows_the_hovered_row():
	browser.size = Vector2(240, 300)
	_record_with_thumbnail("Create Brush", 1)
	_record_with_thumbnail("Move Brush", 2)
	await get_tree().process_frame
	await get_tree().process_frame
	var first := browser._preview_anchor_for_row(0)
	var second := browser._preview_anchor_for_row(1)
	assert_ne(first.y, second.y, "The preview tracks the row the cursor is on")
	assert_almost_eq(first.x, second.x, 0.001, "Both sit off the same edge of the panel")


func test_preview_anchor_sits_clear_of_the_panel():
	browser.size = Vector2(240, 300)
	_record_with_thumbnail("Create Brush", 1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gte(
		browser._preview_anchor_for_row(0).x,
		browser.global_position.x + browser.size.x,
		"The preview must not sit on top of the list it describes"
	)


func test_preview_is_pulled_back_inside_the_window():
	var bounds := Vector2(800, 600)
	var clamped := browser._clamp_preview_position(Vector2(780, 590), bounds)
	assert_almost_eq(clamped.x, 800.0 - browser.THUMB_WIDTH * 2, 0.001)
	assert_almost_eq(clamped.y, 600.0 - browser.THUMB_HEIGHT * 2, 0.001)


func test_preview_clamp_leaves_a_position_that_already_fits():
	var clamped := browser._clamp_preview_position(Vector2(100, 50), Vector2(800, 600))
	assert_eq(clamped, Vector2(100, 50))


func test_preview_clamp_pins_to_origin_when_there_is_no_room():
	var clamped := browser._clamp_preview_position(Vector2(40, 40), Vector2(64, 64))
	assert_eq(clamped, Vector2.ZERO, "A window too small to hold it must not push it off-screen")


func test_hovering_an_entry_without_a_thumbnail_shows_nothing():
	browser.record_entry("No Thumb", 1)
	browser._on_row_hovered(0)
	assert_false(browser._preview_rect.visible)
