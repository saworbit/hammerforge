extends GutTest

const HFOperationReplay = preload("res://addons/hammerforge/ui/hf_operation_replay.gd")

var replay: HFOperationReplay


func before_each():
	replay = HFOperationReplay.new()
	add_child(replay)


func after_each():
	replay.free()
	replay = null


# ===========================================================================
# Recording
# ===========================================================================


func test_initially_empty():
	assert_eq(replay.get_entry_count(), 0)


func test_record_operation():
	replay.record_operation("Draw Brush")
	assert_eq(replay.get_entry_count(), 1)


func test_record_multiple():
	replay.record_operation("Draw Brush")
	replay.record_operation("Delete")
	replay.record_operation("Hollow")
	assert_eq(replay.get_entry_count(), 3)


func test_max_entries_enforced():
	for i in range(25):
		replay.record_operation("Op %d" % i)
	assert_eq(replay.get_entry_count(), HFOperationReplay.MAX_ENTRIES)


func test_clear():
	replay.record_operation("Draw Brush")
	replay.record_operation("Delete")
	replay.clear()
	assert_eq(replay.get_entry_count(), 0)


# ===========================================================================
# Visibility
# ===========================================================================


func test_initially_hidden():
	assert_false(replay.visible)


func test_toggle_visible():
	replay.toggle_visible()
	assert_true(replay.visible)
	replay.toggle_visible()
	assert_false(replay.visible)


# ===========================================================================
# Timeline display
# ===========================================================================


func test_timeline_buttons_created():
	replay.record_operation("Draw Brush")
	replay.record_operation("Delete")
	# Timeline container should have buttons
	assert_eq(replay._timeline_container.get_child_count(), 2)


func test_timeline_buttons_have_icons():
	replay.record_operation("Draw Brush")
	var btn: Button = replay._timeline_container.get_child(0)
	assert_eq(btn.text, "+")  # Draw → "+"


func test_delete_icon():
	replay.record_operation("Delete Selection")
	var btn: Button = replay._timeline_container.get_child(0)
	assert_eq(btn.text, "x")


func test_extrude_icon():
	replay.record_operation("Extrude Face")
	var btn: Button = replay._timeline_container.get_child(0)
	assert_eq(btn.text, "^")


func test_carve_icon():
	replay.record_operation("Carve Brush")
	var btn: Button = replay._timeline_container.get_child(0)
	assert_eq(btn.text, "#")


func test_unknown_action_icon():
	replay.record_operation("Unknown Weird Thing")
	var btn: Button = replay._timeline_container.get_child(0)
	assert_eq(btn.text, "*")


# ===========================================================================
# Hover details
# ===========================================================================


func test_hover_shows_detail():
	replay.record_operation("Hollow Brush")
	replay._on_entry_hovered(0)
	assert_true(replay._detail_label.text.begins_with("Hollow Brush"))


func test_unhover_resets_detail():
	replay.record_operation("Hollow Brush")
	replay._on_entry_hovered(0)
	replay._on_entry_unhovered()
	assert_eq(replay._detail_label.text, "Hover an operation to see details")


# ===========================================================================
# Replay signal
# ===========================================================================


func test_replay_signal():
	var received := []
	replay.replay_requested.connect(func(idx): received.append(idx))
	replay.record_operation("Draw Brush")
	replay._hovered_index = 0
	replay._on_replay_pressed()
	assert_eq(received, [0])


func test_replay_button_visible_on_hover():
	replay.record_operation("Draw Brush")
	assert_false(replay._replay_btn.visible)
	replay._on_entry_hovered(0)
	assert_true(replay._replay_btn.visible)


# ===========================================================================
# Version tracking
# ===========================================================================


func test_get_entry_version():
	replay.record_operation("Draw Brush", 5)
	assert_eq(replay.get_entry_version(0), 5)


func test_get_entry_version_default():
	replay.record_operation("Draw Brush")
	assert_eq(replay.get_entry_version(0), -1)


func test_get_entry_version_out_of_bounds():
	assert_eq(replay.get_entry_version(99), -1)
	assert_eq(replay.get_entry_version(-1), -1)


func test_get_entry_version_multiple():
	replay.record_operation("Draw Brush", 3)
	replay.record_operation("Delete", 7)
	replay.record_operation("Hollow", 12)
	assert_eq(replay.get_entry_version(0), 3)
	assert_eq(replay.get_entry_version(1), 7)
	assert_eq(replay.get_entry_version(2), 12)


# ===========================================================================
# Color coding
# ===========================================================================


func test_delete_color_red():
	var color := replay._get_color_for_action("Delete Selection")
	assert_gt(color.r, 0.8)
	assert_lt(color.g, 0.5)


func test_draw_color_blue():
	var color := replay._get_color_for_action("Draw Brush")
	assert_gt(color.b, 0.8)
