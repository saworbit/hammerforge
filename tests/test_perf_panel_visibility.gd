extends GutTest

## The Performance section used to recompute its readouts every thirty editor
## frames whether or not anybody could see them, and it is created collapsed. The
## work behind those readouts walks every brush, every face and every paint layer,
## so these tests hold the section shut and check that nothing is written.

const DockScene = preload("res://addons/hammerforge/dock.tscn")

const SENTINEL := "untouched"

var dock: HammerForgeDock


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = null


func after_each() -> void:
	dock = null


func _perf_section():
	return dock._all_sections.get("Performance")


## Mark every readout so a refresh is visible as the mark being overwritten.
func _mark_readouts() -> void:
	dock.perf_vertex_value.text = SENTINEL
	dock.perf_brushes_value.text = SENTINEL
	dock.perf_paint_mem_value.text = SENTINEL
	dock.perf_bake_chunks_value.text = SENTINEL
	dock.perf_chunk_rec_value.text = SENTINEL


func _idle(frames: int) -> void:
	for i in range(frames):
		dock._process(1.0 / 60.0)


func _show_manage_tab() -> void:
	for index in dock.main_tabs.get_tab_count():
		if dock.main_tabs.get_tab_control(index) == dock.manage_tab:
			dock.main_tabs.current_tab = index
			return
	fail_test("The Manage tab should be one of the main tabs")


# ===========================================================================
# The section starts shut
# ===========================================================================


func test_performance_section_is_registered_and_starts_collapsed() -> void:
	var section = _perf_section()
	assert_not_null(section, "The dock should keep a reference to the Performance section")
	assert_false(section.is_expanded(), "It is created collapsed")


func test_collapsed_section_is_not_refreshed_on_the_frame_path() -> void:
	_mark_readouts()
	_idle(90)
	assert_eq(dock.perf_vertex_value.text, SENTINEL, "A collapsed panel should not be recomputed")
	assert_eq(dock.perf_brushes_value.text, SENTINEL)
	assert_eq(dock.perf_paint_mem_value.text, SENTINEL)
	assert_eq(dock.perf_bake_chunks_value.text, SENTINEL)
	assert_eq(dock.perf_chunk_rec_value.text, SENTINEL)


func test_footer_brush_count_keeps_updating_while_the_section_is_shut() -> void:
	dock.perf_label.text = SENTINEL
	_idle(31)
	assert_eq(
		dock.perf_label.text,
		"Live Brushes: 0",
		"The footer label is always on screen, so it still refreshes"
	)


# ===========================================================================
# Opening it
# ===========================================================================


func test_expanding_the_section_refreshes_it_at_once() -> void:
	_show_manage_tab()
	_mark_readouts()
	_perf_section().set_expanded(true)
	assert_eq(dock.perf_vertex_value.text, "0", "Opening the panel should fill it in")


func test_open_section_refreshes_on_the_frame_path() -> void:
	_show_manage_tab()
	_perf_section().set_expanded(true)
	_mark_readouts()
	_idle(31)
	assert_eq(dock.perf_vertex_value.text, "0", "An open panel still refreshes")


func test_closing_the_section_stops_the_refresh_again() -> void:
	_show_manage_tab()
	_perf_section().set_expanded(true)
	_perf_section().set_expanded(false)
	_mark_readouts()
	_idle(90)
	assert_eq(dock.perf_vertex_value.text, SENTINEL, "Shut again means quiet again")


# ===========================================================================
# Visible means visible
# ===========================================================================


func test_expanded_section_on_another_tab_does_not_count_as_visible() -> void:
	_show_manage_tab()
	_perf_section().set_expanded(true)
	dock.main_tabs.current_tab = 0
	assert_false(
		dock._is_perf_panel_visible(),
		"An open section on a tab nobody is on is still not on screen"
	)
	_mark_readouts()
	_idle(90)
	assert_eq(dock.perf_vertex_value.text, SENTINEL, "So it should not be recomputed")


func test_returning_to_the_tab_makes_it_visible_again() -> void:
	_show_manage_tab()
	_perf_section().set_expanded(true)
	dock.main_tabs.current_tab = 0
	_show_manage_tab()
	assert_true(dock._is_perf_panel_visible(), "Back on the tab, with the section open")
	_mark_readouts()
	_idle(31)
	assert_eq(dock.perf_vertex_value.text, "0", "And the numbers come back")
