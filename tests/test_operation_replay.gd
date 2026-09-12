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
	replay._on_entry_clicked(0)
	replay._on_replay_pressed()
	assert_eq(received, [0])


# ===========================================================================
# Replay follows the selection, not the hover (#438)
# ===========================================================================


func test_hovering_an_entry_does_not_raise_the_replay_button():
	replay.record_operation("Draw Brush")
	assert_false(replay._replay_btn.visible)
	replay._on_entry_hovered(0)
	assert_false(
		replay._replay_btn.visible,
		"The button is in the header, so reaching for it would be what hides it"
	)


func test_clicking_an_entry_raises_the_replay_button():
	replay.record_operation("Draw Brush")
	replay._on_entry_clicked(0)
	assert_true(replay._replay_btn.visible)


func test_the_replay_button_survives_the_pointer_leaving_the_entry():
	var received := []
	replay.replay_requested.connect(func(idx): received.append(idx))
	replay.record_operation("Draw Brush")
	replay.record_operation("Clip Brush")
	replay._on_entry_clicked(1)
	replay._on_entry_unhovered()
	assert_true(replay._replay_btn.visible, "Moving towards the button must not hide it")
	replay._on_replay_pressed()
	assert_eq(received, [1], "And pressing it replays the entry that was clicked")


func test_a_second_click_moves_the_selection():
	var received := []
	replay.replay_requested.connect(func(idx): received.append(idx))
	replay.record_operation("Draw Brush")
	replay.record_operation("Clip Brush")
	replay._on_entry_clicked(1)
	replay._on_entry_clicked(0)
	replay._on_replay_pressed()
	assert_eq(received, [0])


func test_the_detail_line_goes_back_to_the_selected_entry_after_a_hover():
	replay.record_operation("Draw Brush")
	replay.record_operation("Clip Brush")
	replay._on_entry_clicked(0)
	replay._on_entry_hovered(1)
	assert_true(replay._detail_label.text.begins_with("Clip Brush"))
	replay._on_entry_unhovered()
	assert_true(
		replay._detail_label.text.begins_with("Draw Brush"),
		"With nothing hovered the line describes the selection"
	)


func test_clearing_the_timeline_drops_the_selection():
	var received := []
	replay.replay_requested.connect(func(idx): received.append(idx))
	replay.record_operation("Draw Brush")
	replay._on_entry_clicked(0)
	replay.clear()
	assert_false(replay._replay_btn.visible)
	replay._on_replay_pressed()
	assert_eq(received, [], "There is nothing to replay to")


func test_hiding_the_panel_drops_the_selection():
	replay.record_operation("Draw Brush")
	replay._on_entry_clicked(0)
	replay.toggle_visible()  # shown
	replay.toggle_visible()  # hidden again
	assert_false(replay._replay_btn.visible)


func test_the_selection_follows_an_entry_pushed_off_the_front():
	var received := []
	replay.replay_requested.connect(func(idx): received.append(idx))
	for i in range(HFOperationReplay.MAX_ENTRIES):
		replay.record_operation("Draw Brush", i)
	replay._on_entry_clicked(5)
	replay.record_operation("Clip Brush", 99)
	replay._on_replay_pressed()
	assert_eq(received, [4], "The entry the mapper picked moved down one")


# ===========================================================================
# The glyph names the operation, not the noun it was performed on (#437)
# ===========================================================================


func test_clear_brushes_is_drawn_as_destruction():
	assert_eq(HFOperationReplay._get_icon_for_action("Clear Brushes"), "x")
	assert_eq(
		HFOperationReplay._get_color_for_action("Clear Brushes"),
		HFOperationReplay._get_color_for_action("Delete Selection"),
		"The one entry a mapper most needs to find is not drawn as a creation"
	)


func test_the_two_material_operations_look_the_same():
	assert_eq(
		HFOperationReplay._get_icon_for_action("Apply Brush Material"),
		HFOperationReplay._get_icon_for_action("Assign Face Material")
	)
	assert_eq(HFOperationReplay._get_icon_for_action("Apply Brush Material"), "M")


func test_bevel_and_prefab_do_not_fall_through_to_the_same_glyph():
	var bevel := HFOperationReplay._get_icon_for_action("Bevel Edge")
	var prefab := HFOperationReplay._get_icon_for_action("Place Prefab: door")
	assert_ne(bevel, prefab)
	assert_ne(bevel, "*", "Neither falls through to the catch-all")
	assert_ne(prefab, "*")


func test_move_and_redo_do_not_share_a_glyph():
	assert_ne(
		HFOperationReplay._get_icon_for_action("Move Selection"),
		HFOperationReplay._get_icon_for_action("Redo")
	)


func test_a_plain_creation_still_gets_the_create_glyph_and_colour():
	assert_eq(HFOperationReplay._get_icon_for_action("Draw Brush"), "+")
	assert_eq(HFOperationReplay._get_color_for_action("Draw Brush"), Color(0.3, 0.7, 1.0, 0.9))


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
