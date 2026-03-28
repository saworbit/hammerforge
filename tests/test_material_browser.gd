extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

var _manager: MaterialManager
var _browser: HFMaterialBrowser


func _make_material(mat_name: String, path: String = "") -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.resource_name = mat_name
	if path != "":
		mat.resource_path = path
	return mat


func before_each() -> void:
	_manager = MaterialManager.new()
	add_child_autofree(_manager)
	_browser = HFMaterialBrowser.new()
	add_child_autofree(_browser)


# ---------------------------------------------------------------------------
# Grid building
# ---------------------------------------------------------------------------


func test_empty_manager_produces_empty_grid():
	_browser.set_material_manager(_manager)
	assert_eq(_browser._cell_to_palette_index.size(), 0, "Empty palette = no cells")


func test_palette_view_shows_all_materials():
	_manager.add_material(_make_material("brick"))
	_manager.add_material(_make_material("stone"))
	_manager.add_material(_make_material("wood"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	assert_eq(_browser._cell_to_palette_index.size(), 3, "Should show 3 materials in palette view")


func test_null_material_skipped():
	_manager.materials.append(null)
	_manager.add_material(_make_material("valid"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	assert_eq(_browser._cell_to_palette_index.size(), 1, "Null materials should be skipped")
	assert_eq(_browser._cell_to_palette_index[0], 1, "Index should point to the valid material")


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------


func test_set_selected_index():
	_manager.add_material(_make_material("a"))
	_manager.add_material(_make_material("b"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	_browser.set_selected_index(1)
	assert_eq(_browser.get_selected_index(), 1, "Selected index should update")


func test_on_cell_pressed_emits_signal():
	_manager.add_material(_make_material("a"))
	_manager.add_material(_make_material("b"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	watch_signals(_browser)
	_browser._on_cell_pressed(1)
	assert_signal_emitted(_browser, "material_selected", "Should emit material_selected")


func test_on_cell_pressed_sets_selection():
	_manager.add_material(_make_material("a"))
	_manager.add_material(_make_material("b"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	_browser._on_cell_pressed(1)
	assert_eq(
		_browser.get_selected_index(),
		_browser._cell_to_palette_index[1],
		"Should set selected to palette index of cell 1",
	)


# ---------------------------------------------------------------------------
# Favorites
# ---------------------------------------------------------------------------


func test_add_favorite():
	_browser.add_favorite("res://test.tres")
	assert_true(_browser.is_favorite("res://test.tres"), "Should be marked favorite")


func test_remove_favorite():
	_browser.add_favorite("res://test.tres")
	_browser.remove_favorite("res://test.tres")
	assert_false(_browser.is_favorite("res://test.tres"), "Should no longer be favorite")


func test_favorites_view_filters_to_starred():
	var m1 = _make_material("fav")
	m1.resource_path = "res://fav_mat.tres"
	var m2 = _make_material("nope")
	m2.resource_path = "res://nope_mat.tres"
	_manager.add_material(m1)
	_manager.add_material(m2)
	_browser.add_favorite("res://fav_mat.tres")
	_browser._view_mode = HFMaterialBrowser.ViewMode.FAVORITES
	_browser.set_material_manager(_manager)
	assert_eq(_browser._cell_to_palette_index.size(), 1, "Only favorites should appear")
	assert_eq(_browser._cell_to_palette_index[0], 0, "Should be first material")


# ---------------------------------------------------------------------------
# Filters
# ---------------------------------------------------------------------------


func test_search_filter():
	_manager.add_material(_make_material("brick_red"))
	_manager.add_material(_make_material("stone_blue"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	# Apply search
	_browser._search_text = "brick"
	_browser.rebuild()
	assert_eq(_browser._cell_to_palette_index.size(), 1, "Only 'brick' material should pass filter")


func test_search_case_insensitive():
	_manager.add_material(_make_material("Brick_Red"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	_browser._search_text = "brick"
	_browser.rebuild()
	assert_eq(_browser._cell_to_palette_index.size(), 1, "Search should be case-insensitive")


# ---------------------------------------------------------------------------
# Hover signals
# ---------------------------------------------------------------------------


func test_mouse_entered_emits_hovered():
	_manager.add_material(_make_material("a"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	watch_signals(_browser)
	_browser._on_cell_mouse_entered(0)
	assert_signal_emitted(_browser, "material_hovered", "Should emit material_hovered")


func test_mouse_exited_emits_hover_ended():
	var mgr = MaterialManager.new()
	add_child_autofree(mgr)
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(mgr)
	watch_signals(_browser)
	_browser._on_cell_mouse_exited()
	assert_signal_emitted(_browser, "material_hover_ended", "Should emit material_hover_ended")


# ---------------------------------------------------------------------------
# Double-click
# ---------------------------------------------------------------------------


func test_double_click_emits_signal():
	_manager.add_material(_make_material("a"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	watch_signals(_browser)
	# Simulate double-click via gui_input handler
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	_browser._on_cell_gui_input(ev, 0)
	assert_signal_emitted(
		_browser, "material_double_clicked", "Double-click should emit material_double_clicked"
	)


func test_double_click_updates_selection():
	_manager.add_material(_make_material("a"))
	_manager.add_material(_make_material("b"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	_browser._on_cell_gui_input(ev, 1)
	assert_eq(
		_browser.get_selected_index(),
		_browser._cell_to_palette_index[1],
		"Double-click should update selected index",
	)


# ---------------------------------------------------------------------------
# Context menu signal
# ---------------------------------------------------------------------------


func test_right_click_emits_context_menu():
	_manager.add_material(_make_material("a"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	watch_signals(_browser)
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.global_position = Vector2(100, 200)
	_browser._on_cell_gui_input(ev, 0)
	assert_signal_emitted(
		_browser, "material_context_menu", "Right-click should emit context menu signal"
	)


# ---------------------------------------------------------------------------
# Drag data
# ---------------------------------------------------------------------------


func test_drag_data_for_index_returns_dict():
	_manager.add_material(_make_material("a"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	var data = _browser._get_drag_data_for_index(Vector2.ZERO, 0)
	assert_not_null(data, "Drag data should not be null")
	assert_true(data is Dictionary, "Drag data should be a Dictionary")
	assert_eq(data.get("type"), "hammerforge_material", "Type should be hammerforge_material")
	assert_eq(data.get("index"), 0, "Index should match palette index")


func test_drag_data_invalid_index_returns_null():
	var mgr = MaterialManager.new()
	add_child_autofree(mgr)
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(mgr)
	var data = _browser._get_drag_data_for_index(Vector2.ZERO, 99)
	assert_null(data, "Invalid cell index should return null")


func test_drag_data_emits_signal():
	_manager.add_material(_make_material("a"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	watch_signals(_browser)
	_browser._get_drag_data_for_index(Vector2.ZERO, 0)
	assert_signal_emitted(
		_browser, "material_drag_started", "Drag should emit material_drag_started"
	)


# ---------------------------------------------------------------------------
# Boundary / guard tests
# ---------------------------------------------------------------------------


func test_cell_pressed_out_of_range_no_crash():
	var mgr = MaterialManager.new()
	add_child_autofree(mgr)
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(mgr)
	# Should not crash on out-of-range
	_browser._on_cell_pressed(-1)
	_browser._on_cell_pressed(999)
	assert_true(true, "Out-of-range cell press should not crash")


func test_gui_input_out_of_range_no_crash():
	var mgr = MaterialManager.new()
	add_child_autofree(mgr)
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(mgr)
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	_browser._on_cell_gui_input(ev, -1)
	_browser._on_cell_gui_input(ev, 999)
	assert_true(true, "Out-of-range gui_input should not crash")


func test_rebuild_without_manager_no_crash():
	_browser.rebuild()
	assert_true(true, "Rebuild without manager should not crash")


# ---------------------------------------------------------------------------
# View mode switching
# ---------------------------------------------------------------------------


func test_view_mode_palette():
	_manager.add_material(_make_material("one"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	assert_eq(_browser._cell_to_palette_index.size(), 1, "Palette shows all materials")


func test_view_mode_favorites_empty_when_none_starred():
	_manager.add_material(_make_material("one"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.FAVORITES
	_browser.set_material_manager(_manager)
	assert_eq(
		_browser._cell_to_palette_index.size(), 0, "Favorites view empty when nothing starred"
	)
