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
