extends GutTest
## Alt+1 to Alt+9 apply the context toolbar's favourites by number (#1439).
##
## Favourite N is the Nth starred material in palette order, the order the strip
## on the context toolbar shows and the Favorites view numbers. It goes on the
## selected faces, or else the selected brushes, as one undo step either way. The
## strip's own buttons used to commit once per brush, so three brushes took three
## Ctrl+Z to take back.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFMaterialBrowserScript = preload("res://addons/hammerforge/ui/hf_material_browser.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func before_each() -> void:
	# The stand-in's preferences outlive each test's level, and so would its stars.
	var prefs = rig.plugin._user_prefs
	prefs.set_favorite_materials([])
	prefs.set_pref("recent_materials", [])
	rig.plugin.dock.material_browser.set_user_prefs(prefs)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


## A level whose palette holds `count` materials, each with a path of its own so
## it can be starred, and the dock's browser showing it.
func _level(count := 5) -> Node:
	var level = await rig.make_level()
	var stamp := Time.get_ticks_usec()
	var mats: Array = []
	for i in count:
		var mat := StandardMaterial3D.new()
		mat.resource_name = "fav_mat_%d" % i
		mat.resource_path = "res://hf_apply_favorite_%d/mat_%d.tres" % [stamp, i]
		mats.append(mat)
	level.set_materials(mats)
	rig.plugin.dock._sync_materials_from_root()
	return level


func _star(level: Node, slots: Array) -> void:
	for slot in slots:
		rig.plugin.dock.material_browser.add_favorite(level.get_materials()[slot].resource_path)


func _alt(digit: int) -> int:
	return rig.forward(PluginRig.key(KEY_0 + digit, false, false, true))


func _face_idx(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.is_equal_approx(normal):
			return i
	return -1


func _toasts_containing(text: String) -> int:
	var count := 0
	for toast in rig.toasts():
		if str(toast).contains(text):
			count += 1
	return count


# ---------------------------------------------------------------------------
# The keys
# ---------------------------------------------------------------------------


func test_alt_3_paints_four_selected_faces_with_favourite_3_and_one_undo_restores_them() -> void:
	var level = await _level()
	# Stars in palette order 0, 2, 3, 4: favourite 3 is slot 3.
	_star(level, [4, 0, 3, 2])
	var a = rig.box(level, "a", Vector3(-4, 0, 0))
	var b = rig.box(level, "b", Vector3(4, 0, 0))
	var picked := []
	for brush in [a, b]:
		for normal in [Vector3.UP, Vector3.FORWARD]:
			var face := _face_idx(brush, normal)
			level.toggle_face_selection(brush, face, true, false)
			picked.append([brush.brush_id, face])
	var steps: int = rig.undo().step_count()

	assert_eq(_alt(3), STOP, "Alt+3 is HammerForge's")

	for entry in picked:
		var brush = level.find_brush_by_id(entry[0])
		assert_eq(int(brush.faces[entry[1]].material_idx), 3, "%s takes favourite 3" % str(entry))
	assert_eq(rig.undo().step_count(), steps + 1, "as one step")
	assert_true(rig.undo().press_undo(), "Ctrl+Z")
	for entry in picked:
		var brush = level.find_brush_by_id(entry[0])
		assert_eq(int(brush.faces[entry[1]].material_idx), -1, "%s is as it was" % str(entry))
	await rig.leave_level(level)


func test_alt_3_paints_three_selected_brushes_in_one_undo_step() -> void:
	var level = await _level()
	_star(level, [0, 1, 2])
	var brushes := [
		rig.box(level, "a", Vector3(-6, 0, 0)),
		rig.box(level, "b", Vector3(0, 0, 0)),
		rig.box(level, "c", Vector3(6, 0, 0)),
	]
	rig.select(brushes)
	await rig.frame()
	var favourite: Material = level.get_materials()[2]
	var steps: int = rig.undo().step_count()

	assert_eq(_alt(3), STOP)

	for id in ["a", "b", "c"]:
		assert_eq(level.find_brush_by_id(id).material_override, favourite, "%s is painted" % id)
	assert_eq(rig.undo().step_count(), steps + 1, "the three are one step")
	assert_true(rig.undo().press_undo(), "Ctrl+Z")
	for id in ["a", "b", "c"]:
		assert_null(level.find_brush_by_id(id).material_override, "one Ctrl+Z takes %s back" % id)
	await rig.leave_level(level)


## The context toolbar's own buttons go the same way: one step for the selection.
func test_a_strip_button_on_three_brushes_is_one_undo_step() -> void:
	var level = await _level()
	_star(level, [1])
	var brushes := [
		rig.box(level, "a", Vector3(-6, 0, 0)),
		rig.box(level, "b", Vector3(0, 0, 0)),
		rig.box(level, "c", Vector3(6, 0, 0)),
	]
	rig.select(brushes)
	await rig.frame()
	var steps: int = rig.undo().step_count()
	rig.plugin._context_toolbar.material_quick_apply.emit(1)
	for id in ["a", "b", "c"]:
		assert_eq(level.find_brush_by_id(id).material_override, level.get_materials()[1])
	assert_eq(rig.undo().step_count(), steps + 1, "one step, not one a brush")
	await rig.leave_level(level)


func test_alt_digit_during_a_draw_types_a_size_and_changes_no_material() -> void:
	var level = await _level()
	_star(level, [0, 1, 2])
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	rig.select([a])
	await rig.frame()
	var steps: int = rig.undo().step_count()
	var dock = rig.plugin.dock
	dock.tool_draw.button_pressed = true
	var start := rig.camera.unproject_position(Vector3(4, 0, 4))
	var drag := rig.camera.unproject_position(Vector3(6, 0, 6))
	rig.forward(PluginRig.motion(start))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, start))
	rig.forward(PluginRig.motion(drag, MOUSE_BUTTON_MASK_LEFT))
	assert_true(level.input_state.is_dragging(), "a draw is under way")

	assert_eq(_alt(3), STOP)

	assert_eq(rig.plugin.numeric_buffer, "3", "the digit is a typed size")
	assert_null(a.material_override, "and no material changed")
	assert_eq(rig.undo().step_count(), steps, "nothing was recorded")
	rig.plugin.numeric_buffer = ""
	rig.escape_to_idle(level)
	dock.tool_select.button_pressed = true
	await rig.leave_level(level)


func test_an_empty_slot_says_which_and_changes_nothing() -> void:
	var level = await _level()
	_star(level, [0, 1])
	var a = rig.box(level, "a", Vector3.ZERO)
	rig.select([a])
	await rig.frame()
	rig.clear_toasts()
	var steps: int = rig.undo().step_count()

	assert_eq(_alt(5), STOP, "the key is still HammerForge's")

	assert_null(a.material_override, "nothing is painted")
	assert_eq(rig.undo().step_count(), steps, "nothing is recorded")
	assert_eq(_toasts_containing("Favorite 5 is empty"), 1, "and the toast names the slot")
	await rig.leave_level(level)


func test_the_palette_runs_apply_favorite() -> void:
	var level = await _level()
	_star(level, [0, 4])
	var a = rig.box(level, "a", Vector3.ZERO)
	rig.select([a])
	await rig.frame()
	rig.plugin._hotkey_palette.action_invoked.emit("apply_favorite_2")
	assert_eq(a.material_override, level.get_materials()[4], "favourite 2 is slot 4")
	await rig.leave_level(level)


## The number on a strip button and on a thumbnail in the Favorites view is the
## same for the same material.
func test_the_strip_and_the_favorites_view_number_a_material_the_same() -> void:
	var level = await _level(12)
	_star(level, [11, 1, 7, 3, 5, 9, 0, 2, 4, 6, 8, 10])
	var a = rig.box(level, "a", Vector3.ZERO)
	rig.select([a])
	await rig.frame()
	rig.plugin._update_hud_context()
	var toolbar = rig.plugin._context_toolbar
	assert_true(toolbar._favorites_strip.visible, "a brush selection shows the strip")
	var strip: Dictionary = {}
	for i in toolbar._favorite_materials.size():
		strip[str(i + 1)] = int(toolbar._favorite_materials[i]["index"])
	assert_eq(strip.size(), HFMaterialBrowserScript.FAVORITE_SLOTS, "nine on the strip")

	var browser = rig.plugin.dock.material_browser
	browser._view_mode = HFMaterialBrowserScript.ViewMode.FAVORITES
	browser.rebuild()
	var numbered := 0
	for cell in browser._grid.get_child_count():
		var badge := browser._grid.get_child(cell).find_child("SlotNumber", false, false) as Label
		if badge == null:
			continue
		numbered += 1
		assert_eq(
			browser._cell_to_palette_index[cell],
			strip.get(badge.text, -1),
			"thumbnail %s is the strip's %s" % [badge.text, badge.text]
		)
	assert_eq(numbered, 9, "the first nine favourites carry a number")
	browser._view_mode = HFMaterialBrowserScript.ViewMode.PROTOTYPES
	browser.rebuild()
	await rig.leave_level(level)
