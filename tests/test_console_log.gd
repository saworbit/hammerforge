extends GutTest
## HFConsoleLog — the session buffer behind the Console's Log tab.

const HFConsoleLogType = preload("res://addons/hammerforge/hf_console_log.gd")

var log_buffer


func before_each():
	log_buffer = HFConsoleLogType.new()


func after_each():
	log_buffer = null
	HFConsoleLogType.reset_shared()


func test_shared_instance_is_stable():
	var first = HFConsoleLogType.shared()
	assert_not_null(first)
	assert_eq(first, HFConsoleLogType.shared(), "shared() must hand back the same buffer")


func test_reset_shared_starts_a_new_buffer():
	var first = HFConsoleLogType.shared()
	HFConsoleLogType.reset_shared()
	assert_ne(first, HFConsoleLogType.shared())


func test_levels_are_counted_separately():
	log_buffer.debug("d")
	log_buffer.info("i")
	log_buffer.warn("w")
	log_buffer.error("e")
	var counts: Dictionary = log_buffer.counts()
	assert_eq(counts["debug"], 1)
	assert_eq(counts["info"], 1)
	assert_eq(counts["warn"], 1)
	assert_eq(counts["error"], 1)
	assert_eq(log_buffer.size(), 4)


func test_blank_messages_are_dropped():
	log_buffer.info("   ")
	log_buffer.info("")
	assert_eq(log_buffer.size(), 0, "Whitespace-only messages add nothing to read")


func test_muted_buffer_records_nothing():
	log_buffer.muted = true
	log_buffer.error("boom")
	assert_eq(log_buffer.size(), 0)
	assert_eq(log_buffer.counts()["error"], 0)


func test_repeated_message_collapses_into_one_row():
	for i in range(4):
		log_buffer.warn("reconcile skipped", "brush")
	assert_eq(log_buffer.size(), 1, "A repeating warning must not fill the buffer")
	assert_eq(log_buffer.entries()[0]["repeat"], 4)
	assert_eq(log_buffer.counts()["warn"], 4, "Counts still record every occurrence")


func test_different_category_does_not_collapse():
	log_buffer.warn("same text", "bake")
	log_buffer.warn("same text", "paint")
	assert_eq(log_buffer.size(), 2)


func test_capacity_drops_oldest_entries():
	log_buffer.capacity = 4
	for i in range(200):
		log_buffer.info("message %d" % i)
	assert_lt(log_buffer.size(), 100, "Buffer must stay bounded")
	assert_gt(log_buffer.dropped_count(), 0)
	var entries: Array = log_buffer.entries()
	assert_eq(entries[-1]["message"], "message 199", "The newest entry always survives")


func test_over_long_message_is_truncated():
	var huge := "x".repeat(HFConsoleLogType.MAX_MESSAGE_CHARS + 500)
	log_buffer.info(huge)
	var stored: String = log_buffer.entries()[0]["message"]
	assert_lt(stored.length(), huge.length())
	assert_true(stored.ends_with("(truncated)"))


func test_filter_by_level_mask():
	log_buffer.debug("d")
	log_buffer.error("e")
	var errors_only := 1 << HFConsoleLogType.Level.ERROR
	var rows: Array = log_buffer.filtered(errors_only)
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["message"], "e")


func test_filter_by_search_matches_message_and_category():
	log_buffer.info("bake finished", "bake")
	log_buffer.info("brush created", "brush")
	assert_eq(log_buffer.filtered(0xF, "finished").size(), 1)
	assert_eq(log_buffer.filtered(0xF, "BRUSH").size(), 1, "Search is case-insensitive")
	assert_eq(log_buffer.filtered(0xF, "").size(), 2, "Empty search matches everything")


func test_clear_resets_entries_and_counts():
	log_buffer.warn("w")
	log_buffer.clear()
	assert_true(log_buffer.is_empty())
	assert_eq(log_buffer.counts()["warn"], 0)


func test_to_text_renders_one_line_per_entry():
	log_buffer.info("first", "io")
	log_buffer.error("second")
	var text: String = log_buffer.to_text()
	assert_eq(text.split("\n").size(), 2)
	assert_string_contains(text, "[io]")
	assert_string_contains(text, "ERROR")


func test_repeat_count_appears_in_rendered_text():
	log_buffer.warn("twice")
	log_buffer.warn("twice")
	assert_string_contains(log_buffer.to_text(), "(x2)")


func test_bbcode_in_a_message_is_escaped_for_display():
	var escaped: String = HFConsoleLogType.escape_bbcode("brush [b]Wall[/b] failed")
	assert_false(escaped.contains("[b]"), "A bracket in a level name must not style the log")
	assert_string_contains(escaped, "[lb]b]")


func test_appending_from_a_listener_does_not_recurse():
	log_buffer.entry_appended.connect(func(_entry): log_buffer.info("from the listener"))
	log_buffer.info("original")
	assert_eq(log_buffer.size(), 1, "A listener that logs must not reenter append()")


func test_level_name_is_bounded():
	assert_eq(HFConsoleLogType.level_name(HFConsoleLogType.Level.WARN), "WARN")
	assert_eq(HFConsoleLogType.level_name(99), "?")


func test_out_of_range_level_is_clamped_not_crashing():
	log_buffer.append(99, "way out of range")
	assert_eq(log_buffer.entries()[0]["level"], HFConsoleLogType.Level.ERROR)
