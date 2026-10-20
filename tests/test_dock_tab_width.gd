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


## The dock with the 150 prototypes loaded and only Materials open on the Paint tab.
func _paint_tab_with_only_materials_open(height: float) -> HFMaterialBrowser:
	var manager := MaterialManager.new()
	add_child_autofree(manager)
	HFPrototypeTextures.load_all_into(manager)
	dock.material_browser.set_material_manager(manager)
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


## At least four rows of thumbnails in a dock about 1000 px tall. Before, the
## grid was held at 180 px, two rows and eight of the 150 prototypes, however
## tall the dock was (#1332).
func test_the_material_browser_shows_four_rows_in_a_tall_dock() -> void:
	var browser := await _paint_tab_with_only_materials_open(1000.0)
	var rows := _thumbnail_rows(browser)
	assert_gte(rows, 4, "%d px of grid shows %d rows" % [int(browser._scroll.size.y), rows])


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
