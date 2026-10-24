extends GutTest

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DockType = preload("res://addons/hammerforge/dock.gd")

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


## Preferences that are never written: the real file is a developer's own, and
## other checkouts run their suites against it at the same time.
func _prefs() -> HFUserPrefs:
	var prefs := HFUserPrefs.new()
	prefs.persistence_enabled = false
	prefs.data = HFUserPrefs._defaults()
	return prefs


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


## An empty slot used to be left out of the Palette view, so every later slot
## seemed to move up one, though faces still index the palette by slot (#1422).
func test_an_empty_palette_slot_shows_as_a_marker_where_it_stands():
	_manager.add_material(_make_material("first"))
	_manager.materials.append(null)
	_manager.add_material(_make_material("valid"))
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	assert_eq(_browser._cell_to_palette_index, [0, -1, 2], "the empty slot keeps its place")
	var marker := _browser._grid.get_child(1)
	assert_eq(_marker_text(marker), "!", "shown as a marker")
	assert_string_contains(marker.tooltip_text, "Slot 1 is empty", "naming its slot")
	assert_has(_labels_of(marker), "Slot 1", "under the marker as well")

	watch_signals(_browser)
	_browser._on_cell_pressed(1)
	_browser._on_cell_mouse_entered(1)
	assert_signal_not_emitted(_browser, "material_selected", "there is nothing to select")
	assert_signal_not_emitted(_browser, "material_hovered", "or to preview")
	assert_null(_browser._get_drag_data_for_index(Vector2.ZERO, 1), "or to drag")
	assert_eq(_browser.get_selected_index(), -1)

	_browser._search_text = "valid"
	_browser.rebuild()
	assert_eq(_browser._cell_to_palette_index, [2], "a search narrows to materials")


func _marker_text(cell: Node) -> String:
	var mark := cell.find_child("Mark", true, false) as Label
	return mark.text if mark else ""


func _labels_of(cell: Node) -> Array:
	var out: Array = []
	for node in cell.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return out


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


## A material built in the session and not written to disk has an empty
## `resource_path`, and that is what a favourite was keyed on - so every unsaved
## material shared one key. Starring one starred the lot, and un-starring any one
## of them cleared them all.
func test_a_material_with_no_path_cannot_be_starred():
	assert_false(_browser.add_favorite(""), "and the caller is told, so it can say why")
	assert_false(_browser.is_favorite(""), "Nothing is starred")
	var unsaved_a = _make_material("built_in_session_a")
	var unsaved_b = _make_material("built_in_session_b")
	_manager.add_material(unsaved_a)
	_manager.add_material(unsaved_b)
	assert_eq(_browser.get_favorite_infos(10).size(), 0, "so neither comes back as a favourite")


## A star only earns its keep across sessions, and the browser is built fresh by
## the dock - so every one was gone at the next theme change or project reload.
func test_a_star_outlives_the_browser():
	var prefs := _prefs()
	_browser.set_user_prefs(prefs)
	_browser.add_favorite("res://kept.tres")

	var rebuilt = HFMaterialBrowser.new()
	add_child_autofree(rebuilt)
	rebuilt.set_user_prefs(prefs)
	assert_true(rebuilt.is_favorite("res://kept.tres"), "A freshly built browser has it")

	_browser.remove_favorite("res://kept.tres")
	var after_removal = HFMaterialBrowser.new()
	add_child_autofree(after_removal)
	after_removal.set_user_prefs(prefs)
	assert_false(after_removal.is_favorite("res://kept.tres"), "and un-starring outlives it too")


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


# ---------------------------------------------------------------------------
# One label for a material (#1463)
# ---------------------------------------------------------------------------


func _tile_text(cell: int) -> String:
	var tile := _browser._grid.get_child(cell)
	for node in tile.find_children("*", "Label", true, false):
		return (node as Label).text
	return ""


func test_a_material_is_labelled_by_its_name_then_its_file():
	assert_eq(MaterialManager.material_label(_make_material("brick")), "brick", "its name first")
	assert_eq(
		MaterialManager.material_label(_make_material("brick", "res://hf_label_named/stone.tres")),
		"brick",
		"even when it has a file",
	)
	assert_eq(
		MaterialManager.material_label(_make_material("", "res://hf_label_unnamed/stone.tres")),
		"stone",
		"then its file's name, without the extension",
	)
	assert_eq(
		MaterialManager.material_label(_make_material("")),
		"Material",
		"and an unsaved material with no name",
	)
	assert_eq(MaterialManager.material_label(null), "Material", "as an empty slot is")


## A material saved without a name of its own reads the same in the grid, on the
## Active Material button, in the favourites strip and in the dock's toasts. The
## button, the strip and the toasts kept the extension the grid drops, so one
## material read "brick" in one place and "brick.tres" in the next.
func test_a_saved_material_reads_the_same_everywhere_it_is_named():
	var path := "user://hf_material_label_%d.tres" % Time.get_ticks_usec()
	assert_eq(ResourceSaver.save(StandardMaterial3D.new(), path), OK, "the material is saved")
	var saved := ResourceLoader.load(path) as Material
	assert_not_null(saved, "and loads back")
	if saved == null:
		return
	_manager.add_material(saved)
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	var tile := _tile_text(0)
	assert_eq(tile, path.get_file().get_basename(), "the grid names it by its file")

	# The level keeps the Active Material (#1405), so the dock needs one first.
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	var dock = DockType.new()
	autofree(dock)
	dock.level_root = root
	var button := Button.new()
	autofree(button)
	dock.active_material_button = button
	dock._on_material_file_selected(path)
	assert_eq(button.text, "Active Material: %s" % tile, "the button names it the same")

	_browser.add_favorite(path)
	var favourites: Array = _browser.get_favorite_infos(5)
	assert_eq(favourites.size(), 1, "the starred material is a favourite")
	if favourites.size() == 1:
		assert_eq(str(favourites[0]["name"]), tile, "and the favourites strip names it the same")

	var slot: int = root.material_manager.add_material(saved)
	assert_eq(dock._material_display_name(slot), tile, "and so do the toasts")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------------------
# Recent materials, missing favourites, numbers, Active Material (#1422, #1439)
# ---------------------------------------------------------------------------


func _palette_of(names: Array) -> Array:
	var stamp := Time.get_ticks_usec()
	var out: Array = []
	for mat_name in names:
		var mat := _make_material(str(mat_name), "res://hf_browser_%d/%s.tres" % [stamp, mat_name])
		_manager.add_material(mat)
		out.append(mat)
	return out


func test_the_recent_row_lists_what_was_used_newest_first():
	var mats := _palette_of(["brick", "stone", "wood"])
	var prefs := _prefs()
	_browser.set_material_manager(_manager)
	_browser.set_user_prefs(prefs)
	assert_false(_browser._recent_row.visible, "the row is hidden while nothing has been used")

	prefs.add_recent_material(mats[0].resource_path)
	prefs.add_recent_material(mats[2].resource_path)
	prefs.add_recent_material(mats[0].resource_path)
	_browser.refresh_recent()
	assert_true(_browser._recent_row.visible, "and shows once something has")
	assert_eq(
		_browser.get_recent_paths(),
		[mats[0].resource_path, mats[2].resource_path],
		"newest first, each once"
	)

	watch_signals(_browser)
	var wood_button := _browser._recent_cells.get_child(1) as Button
	wood_button.pressed.emit()
	assert_signal_emitted_with_parameters(_browser, "material_selected", [2])
	assert_eq(_browser.get_selected_index(), 2, "a click selects it, as a grid cell does")


func test_the_recent_row_leaves_out_a_material_whose_file_is_gone():
	_palette_of(["brick"])
	var prefs := _prefs()
	prefs.add_recent_material("res://hf_browser_gone/never_saved.tres")
	prefs.add_recent_material(_manager.materials[0].resource_path)
	_browser.set_material_manager(_manager)
	_browser.set_user_prefs(prefs)
	assert_eq(_browser.get_recent_paths(), [_manager.materials[0].resource_path])


func test_a_recent_material_the_palette_does_not_hold_asks_to_be_added():
	var path := "user://hf_browser_recent_%d.tres" % Time.get_ticks_usec()
	assert_eq(ResourceSaver.save(StandardMaterial3D.new(), path), OK, "the material is saved")
	var prefs := _prefs()
	prefs.add_recent_material(path)
	_browser.set_material_manager(_manager)
	_browser.set_user_prefs(prefs)
	assert_eq(_browser.get_recent_paths(), [path], "it is in the row")
	watch_signals(_browser)
	(_browser._recent_cells.get_child(0) as Button).pressed.emit()
	assert_signal_not_emitted(_browser, "material_add_requested", "not while the click is sent")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(_browser, "material_add_requested", [path])
	assert_signal_not_emitted(_browser, "material_selected", "with no slot to select yet")
	_browser._recent_loaded.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A starred material whose file was moved used to vanish from the Favorites view
## with nothing to say it had been there or where it lived.
func test_a_favourite_whose_file_is_gone_shows_as_a_marker_with_its_path():
	var mats := _palette_of(["brick"])
	var gone := "res://hf_browser_gone_%d/moved.tres" % Time.get_ticks_usec()
	var prefs := _prefs()
	prefs.set_favorite_materials([mats[0].resource_path, gone])
	_browser._view_mode = HFMaterialBrowser.ViewMode.FAVORITES
	_browser.set_material_manager(_manager)
	_browser.set_user_prefs(prefs)
	assert_eq(_browser.missing_favorites(), [gone])
	assert_eq(_browser._cell_to_palette_index, [0, -1], "the starred material, then the marker")
	var marker := _browser._grid.get_child(1)
	assert_eq(_marker_text(marker), "!")
	assert_string_contains(marker.tooltip_text, gone, "the old path is in its tooltip")
	assert_null(_browser._get_drag_data_for_index(Vector2.ZERO, 1), "it cannot be dragged")

	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	_browser._on_cell_gui_input(right, 1)
	var menu := _browser._marker_menu
	assert_not_null(menu, "a right-click opens its menu")
	if menu:
		assert_eq(menu.get_item_text(0), "Remove Favorite")
		menu.hide()
	_browser._on_marker_menu_id_pressed(0)
	assert_false(
		prefs.get_favorite_materials().has(gone), "Remove Favorite takes it out of the prefs"
	)
	assert_true(prefs.get_favorite_materials().has(mats[0].resource_path), "and only it")
	assert_eq(_browser._cell_to_palette_index, [0], "and out of the view")


func test_a_right_click_on_an_empty_slot_opens_nothing():
	_manager.materials.append(null)
	_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE
	_browser.set_material_manager(_manager)
	watch_signals(_browser)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	_browser._on_cell_gui_input(right, 0)
	assert_null(_browser._marker_menu, "an empty slot has nothing to offer")
	assert_signal_not_emitted(_browser, "material_context_menu", "nor the material menu")


## The Favorites view numbers a favourite as the context toolbar's strip does and
## as Alt and its digit apply it (#1439), whatever the filters leave showing.
func test_the_favorites_view_numbers_a_favourite_as_the_strip_does():
	var mats := _palette_of(["brick", "plain", "stone", "wood"])
	var prefs := _prefs()
	prefs.set_favorite_materials(
		[mats[3].resource_path, mats[0].resource_path, mats[2].resource_path]
	)
	_browser._view_mode = HFMaterialBrowser.ViewMode.FAVORITES
	_browser.set_material_manager(_manager)
	_browser.set_user_prefs(prefs)
	var strip: Array = []
	for info in _browser.get_favorite_infos():
		strip.append(int(info["index"]))
	assert_eq(strip, [0, 2, 3], "the strip's order is the palette's")
	var numbers: Array = []
	for cell in _browser._grid.get_children():
		var badge := cell.find_child("SlotNumber", false, false) as Label
		numbers.append(badge.text if badge else "")
	assert_eq(numbers, ["1", "2", "3"], "and the view numbers them the same")

	_browser._search_text = "stone"
	_browser.rebuild()
	var badge := _browser._grid.get_child(0).find_child("SlotNumber", false, false) as Label
	assert_eq(badge.text if badge else "", "2", "a search keeps each favourite's own number")


func test_the_strip_holds_nine_favourites():
	var names: Array = []
	for i in range(11):
		names.append("m%02d" % i)
	var mats := _palette_of(names)
	for mat in mats:
		_browser.add_favorite(mat.resource_path)
	_browser.set_material_manager(_manager)
	assert_eq(HFMaterialBrowser.FAVORITE_SLOTS, 9)
	assert_eq(_browser.get_favorite_infos().size(), 9, "one for each of Alt+1 to Alt+9")


func test_the_material_menu_offers_set_as_active_material():
	var popup := _browser.create_context_popup()
	autofree(popup)
	var index := popup.get_item_index(5)
	assert_ne(index, -1, "the menu has the item")
	if index != -1:
		assert_eq(popup.get_item_text(index), "Set as Active Material")


## Set as Active Material puts the browser's material where the Build tab's file
## dialog puts one, so the button names it and Paint Mode applies it.
func test_set_as_active_material_is_what_the_build_tab_and_paint_mode_use():
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autofree(root)
	var brick := _make_material(
		"brick", "res://hf_browser_active_%d/brick.tres" % Time.get_ticks_usec()
	)
	var slot: int = root.material_manager.add_material(brick)
	var dock = DockType.new()
	autofree(dock)
	dock.level_root = root
	var button := Button.new()
	autofree(button)
	dock.active_material_button = button
	dock._material_context_index = slot
	dock._on_material_context_action(5)
	assert_eq(root.active_material, brick, "the level's Active Material is the browser's pick")
	assert_eq(dock.get_active_material(), brick, "which Paint Mode reads")
	assert_eq(button.text, "Active Material: brick", "and the Build tab's button names it")
