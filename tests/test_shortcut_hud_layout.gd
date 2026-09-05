extends GutTest
## The shortcut HUD lives in the 3D viewport toolbar, which is a BoxContainer.
## These pin the two layout faults that made it overlap the context toolbar:
## a Control that reported no minimum size, and three labels sharing one
## MarginContainer rect.

const HUD_SCENE = preload("res://addons/hammerforge/shortcut_hud.tscn")
const ShortcutHUD = preload("res://addons/hammerforge/shortcut_hud.gd")


func _hud() -> Control:
	var hud = HUD_SCENE.instantiate()
	add_child_autofree(hud)
	return hud


# --- the overlap ---------------------------------------------------------


func test_hud_reserves_the_space_it_draws_into():
	# A zero minimum is what let the panel spill across the context toolbar:
	# a BoxContainer sizes children to their minimum and lays out the next one
	# immediately after.
	var hud := _hud()
	var minimum: Vector2 = hud.get_combined_minimum_size()
	assert_gt(minimum.x, 0.0, "A zero-width slot is what caused the overlap")
	assert_gt(minimum.y, 0.0, "A zero-height slot leaves the panel drawing outside it")


func test_hud_reserves_a_fixed_width():
	# Fixed, so the toolbar does not reflow every time the shortcut text changes.
	var hud := _hud()
	assert_almost_eq(hud.get_combined_minimum_size().x, ShortcutHUD.HUD_WIDTH, 0.5)


func test_hud_minimum_height_covers_its_panel():
	var hud := _hud()
	var panel: Control = hud.get_node("Panel")
	assert_almost_eq(hud.get_combined_minimum_size().y, panel.get_combined_minimum_size().y, 0.5)


func test_labels_share_a_row_rather_than_one_margin_rect():
	# MarginContainer hands every child the same rect, so three labels in it draw
	# on top of each other.
	var hud := _hud()
	var margin: Control = hud.get_node("Panel/Margin")
	assert_eq(margin.get_child_count(), 1, "The margin holds the row, not the labels")
	var row: Control = margin.get_child(0)
	assert_true(row is HBoxContainer)
	assert_gte(row.get_child_count(), 3, "Shortcut line, hint and grid all live in the row")


# --- one line, full text on the tooltip ----------------------------------


func test_row_shows_one_line():
	var hud := _hud()
	hud.update_context({"tool": 0, "mode": 0})
	assert_false(hud.label.text.contains("\n"), "The toolbar gives the HUD one line")
	assert_ne(hud.label.text, "")


func test_full_shortcut_list_stays_on_the_tooltip():
	var hud := _hud()
	hud.update_context({"tool": 0, "mode": 0})
	var full: String = hud._build_shortcuts_text({"tool": 0, "mode": 0})
	assert_true(full.contains("\n"), "This mode really does have more than one line")
	assert_eq(hud.tooltip_text, full, "Nothing is lost, it is one hover away")


func test_primary_line_takes_the_first_real_line():
	assert_eq(ShortcutHUD.primary_line("first\nsecond\nthird"), "first")
	assert_eq(ShortcutHUD.primary_line("\n\nafter blanks"), "after blanks")
	assert_eq(ShortcutHUD.primary_line(""), "")
	assert_eq(ShortcutHUD.primary_line("   "), "")


func test_primary_line_matches_the_first_line_of_the_built_text():
	var hud := _hud()
	var full: String = hud._build_shortcuts_text({"tool": 1, "mode": 0})
	assert_eq(ShortcutHUD.primary_line(full), full.split("\n", false)[0].strip_edges())


# --- hint replaces the line rather than stacking under it ----------------


func test_a_hint_replaces_the_shortcut_line():
	var hud := _hud()
	hud.update_context({"tool": 0, "mode": 0})
	hud._show_hint("do the thing")
	assert_true(hud._hint_label.visible)
	assert_false(hud.label.visible, "Two lines would double the toolbar height")


func test_hiding_a_hint_restores_the_shortcut_line():
	var hud := _hud()
	hud.update_context({"tool": 0, "mode": 0})
	hud._show_hint("do the thing")
	hud._hide_hint()
	assert_false(hud._hint_label.visible)
	assert_true(hud.label.visible)


func test_hint_text_carries_no_layout_newline():
	var hud := _hud()
	hud._show_hint("do the thing")
	assert_eq(hud._hint_label.text, "do the thing", "The leading newline was a stacking hack")


func test_grid_indicator_still_updates():
	var hud := _hud()
	hud.update_grid_snap(16.0)
	assert_eq(hud._grid_label.text, "Grid: 16")
	hud.update_grid_snap(0.125)
	assert_eq(hud._grid_label.text, "Grid: 0.125")


func test_fractional_grid_snaps_render_as_numbers():
	# GDScript has no %g. It printed the specifier verbatim and raised an engine
	# error every time the grid was set to anything but a whole number.
	var hud := _hud()
	for pair in [[0.125, "Grid: 0.125"], [0.5, "Grid: 0.5"], [2.5, "Grid: 2.5"]]:
		hud.update_grid_snap(pair[0])
		assert_eq(hud._grid_label.text, pair[1])
