extends GutTest
## The dock's four tabs fit the dock's width: none is wider than the narrowest
## dock, so none scrolls sideways, and none sits in a column narrower than the
## dock it is in.
##
## Before, each tab's content stayed at its own minimum width. The Test tab was a
## 204 px column in a 388 px dock, and the Build, Paint and Objects tabs needed
## 312, 477 and 870 px, so they scrolled sideways and clipped their right edge.

const DockScene = preload("res://addons/hammerforge/dock.tscn")

var holder: Control
var dock: HammerForgeDock


func before_each() -> void:
	holder = Control.new()
	add_child_autoqfree(holder)
	dock = DockScene.instantiate()
	holder.add_child(dock)
	# The scene's own offsets would make the dock 320 px wider than its holder.
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await wait_process_frames(1)
	# Every section open and shown, including the ones that only appear for a
	# selection, so a wide row anywhere in a tab counts.
	for section in dock._all_sections.values():
		section.visible = true
		section.set_expanded(true)


func after_each() -> void:
	dock = null
	holder = null


func _tab_scroll(index: int) -> ScrollContainer:
	return dock.main_tabs.get_child(index) as ScrollContainer


func _show_tab(index: int, width: float) -> void:
	holder.size = Vector2(width, 900)
	dock.main_tabs.current_tab = index
	await wait_process_frames(3)


func test_no_tab_is_wider_than_the_narrowest_dock() -> void:
	var floor_width: float = dock.get_node("Margin/VBox").custom_minimum_size.x
	for index in dock.main_tabs.get_tab_count():
		await _show_tab(index, floor_width)
		var content: Control = _tab_scroll(index).get_child(0)
		assert_lte(
			content.get_combined_minimum_size().x,
			floor_width,
			"%s needs more width than the dock's minimum" % dock.main_tabs.get_tab_title(index),
		)


func test_no_tab_scrolls_sideways() -> void:
	for width in [260.0, 400.0]:
		for index in dock.main_tabs.get_tab_count():
			await _show_tab(index, width)
			assert_false(
				_tab_scroll(index).get_h_scroll_bar().visible,
				(
					"%s shows a horizontal scrollbar at %d px"
					% [dock.main_tabs.get_tab_title(index), width]
				),
			)


func test_every_tab_fills_the_dock_width() -> void:
	for index in dock.main_tabs.get_tab_count():
		await _show_tab(index, 400.0)
		var scroll := _tab_scroll(index)
		var content: Control = scroll.get_child(0)
		var room := scroll.size.x
		if scroll.get_v_scroll_bar().visible:
			room -= scroll.get_v_scroll_bar().size.x
		assert_almost_eq(
			content.size.x,
			room,
			1.0,
			"%s sits in a column narrower than the dock" % dock.main_tabs.get_tab_title(index),
		)


func test_material_browser_columns_follow_its_width() -> void:
	var manager := MaterialManager.new()
	add_child_autofree(manager)
	HFPrototypeTextures.load_all_into(manager)
	var browser_holder := VBoxContainer.new()
	add_child_autoqfree(browser_holder)
	var browser := HFMaterialBrowser.new()
	browser_holder.add_child(browser)
	browser.set_material_manager(manager)
	for width in [240.0, 480.0]:
		browser_holder.size = Vector2(width, 600)
		await wait_process_frames(3)
		assert_lte(
			browser.get_combined_minimum_size().x,
			width,
			"150 thumbnails must not hold the browser wider than %d px" % width,
		)
		var grid: GridContainer = browser._grid
		assert_lte(grid.get_combined_minimum_size().x, width, "a row of thumbnails fits")
	assert_gt(browser._grid.columns, 3, "a wide browser shows more than three a row")


## The dock with a level open, the 150 prototypes in its palette, and only
## Materials open on the Paint tab. A level is what a mapper paints with: without
## one the dock puts its 115 px "no level" banner over the tabs instead.
func _paint_tab_with_only_materials_open(height: float) -> HFMaterialBrowser:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	HFPrototypeTextures.load_all_into(root.material_manager)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	dock.material_browser.set_material_manager(root.material_manager)
	for section_name in dock._all_sections:
		dock._all_sections[section_name].set_expanded(section_name == "Materials")
	await _show_tab(dock.paint_tab.get_index(), 400.0)
	holder.size = Vector2(400, height)
	await wait_process_frames(3)
	return dock.material_browser


func _thumbnail_rows(browser: HFMaterialBrowser) -> int:
	var cell := float(HFMaterialBrowser.THUMB_SIZE + 22)
	var gap := float(browser._grid.get_theme_constant("v_separation"))
	return int((browser._scroll.size.y + gap) / (cell + gap))


## With only Materials open in a 1000 px dock the Paint tab's content fits, so
## the grid is the one thing to scroll. Before, the palette's seven buttons, the
## status line and a four-row floor under the search made the content 1092 px in
## a 778 px tab, and the face buttons sat below the fold (#1366).
func test_the_paint_tab_does_not_scroll_with_only_materials_open() -> void:
	var browser := await _paint_tab_with_only_materials_open(1000.0)
	var content: Control = dock.paint_tab.get_child(0)
	assert_lte(
		content.get_combined_minimum_size().y,
		dock.paint_tab.size.y,
		"The Paint tab's content fits the tab",
	)
	assert_false(dock.paint_tab.get_v_scroll_bar().visible, "The tab itself has nothing to scroll")
	var rows := _thumbnail_rows(browser)
	assert_gte(rows, 2, "%d px of grid shows %d rows" % [int(browser._scroll.size.y), rows])


## Four rows of thumbnails once the dock is 1200 px tall, with the tab still not
## scrolling. Before #1332 the grid was held at 180 px, two rows and eight of the
## 150 prototypes, however tall the dock was. At 1000 px the seven other section
## headers leave the grid two rows and a bit once the tab fits (#1366).
func test_the_material_browser_shows_four_rows_in_a_tall_dock() -> void:
	var browser := await _paint_tab_with_only_materials_open(1200.0)
	var rows := _thumbnail_rows(browser)
	assert_gte(rows, 4, "%d px of grid shows %d rows" % [int(browser._scroll.size.y), rows])
	assert_false(dock.paint_tab.get_v_scroll_bar().visible, "The tab itself has nothing to scroll")


## A dock too short for the whole tab keeps two rows of grid and lets the tab
## scroll, rather than squeezing the grid to a strip.
func test_a_short_dock_keeps_two_rows_of_thumbnails() -> void:
	var browser := await _paint_tab_with_only_materials_open(700.0)
	var rows := _thumbnail_rows(browser)
	assert_gte(rows, 2, "%d px of grid shows %d rows" % [int(browser._scroll.size.y), rows])


## The palette's own buttons are one click away, under Material Library inside
## Materials. Assign and the face controls stay in view beside the grid, and the
## count of what the grid shows is in the Materials header.
func test_the_library_buttons_are_one_click_away() -> void:
	await _paint_tab_with_only_materials_open(1000.0)
	var library_buttons: Array = [
		dock.material_add,
		dock.material_remove,
		dock.material_load_prototypes,
		dock.material_remove_unused,
		dock.material_clear,
		dock.material_save_library,
		dock.material_load_library,
	]
	for button in library_buttons:
		assert_false(button.is_visible_in_tree(), "%s waits under Material Library" % button.text)
	for control in [dock.material_assign, dock.face_select_mode, dock.face_clear]:
		assert_true(control.is_visible_in_tree(), "%s is in view" % control.text)
	var materials: HFCollapsibleSection = dock._all_sections["Materials"]
	assert_string_contains(materials._header.text, "150 materials")
	var library: HFCollapsibleSection = dock._all_sections["Material Library"]
	assert_true(materials.get_content().is_ancestor_of(library), "Material Library is in Materials")
	library.set_expanded(true)
	for button in library_buttons:
		assert_true(button.is_visible_in_tree(), "%s shows once Library opens" % button.text)


## A tab with height to spare hands it to the grid rather than leaving it empty
## under the last section, so there is one thing to scroll, not two.
func test_the_material_browser_takes_the_height_the_tab_has_left() -> void:
	var browser := await _paint_tab_with_only_materials_open(2000.0)
	assert_gt(
		browser._scroll.size.y,
		browser._scroll.custom_minimum_size.y,
		"The grid is taller than its floor",
	)
	assert_false(dock.paint_tab.get_v_scroll_bar().visible, "The tab itself has nothing to scroll")
