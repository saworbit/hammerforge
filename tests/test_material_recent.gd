extends GutTest
## The material browser's Recent row fills from every route that applies a
## material (#1422).
##
## Each route says so through the level's `material_used` signal once it has
## applied, and the dock puts the material first in the row, kept in the user's
## preferences beside the favourites. An undo or a redo is not a use.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginDropHandlerScript = preload("res://addons/hammerforge/plugin_drop_handler.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func before_each() -> void:
	var prefs = rig.plugin._user_prefs
	prefs.set_favorite_materials([])
	prefs.set_pref("recent_materials", [])
	rig.plugin.dock.material_browser.set_user_prefs(prefs)
	rig.plugin.dock._picked_look = null


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


func _level(count := 4) -> Node:
	var level = await rig.make_level()
	var stamp := Time.get_ticks_usec()
	var mats: Array = []
	for i in count:
		var mat := StandardMaterial3D.new()
		mat.resource_name = "recent_mat_%d" % i
		mat.resource_path = "res://hf_material_recent_%d/mat_%d.tres" % [stamp, i]
		mats.append(mat)
	level.set_materials(mats)
	rig.plugin.dock._sync_materials_from_root()
	return level


func _path(level: Node, slot: int) -> String:
	return level.get_materials()[slot].resource_path


func _recent() -> Array:
	return rig.plugin._user_prefs.get_recent_materials()


func _face_idx(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.is_equal_approx(normal):
			return i
	return -1


func _select_top(level: Node, brush: Node) -> void:
	level.toggle_face_selection(brush, _face_idx(brush, Vector3.UP), true, false)


# ---------------------------------------------------------------------------
# The routes
# ---------------------------------------------------------------------------


func test_a_face_assign_puts_the_material_first_once() -> void:
	var level = await _level()
	var a = rig.box(level, "a", Vector3.ZERO)
	_select_top(level, a)
	var dock = rig.plugin.dock
	for slot in [1, 2, 1]:
		dock._selected_material_index = slot
		dock._on_material_assign()
	assert_eq(_recent(), [_path(level, 1), _path(level, 2)], "newest first, each once")
	assert_eq(
		dock.material_browser.get_recent_paths(), _recent(), "and the browser's row shows them"
	)
	assert_true(dock.material_browser._recent_row.visible)
	await rig.leave_level(level)


func test_a_paint_click_on_a_brush_is_a_use() -> void:
	var level = await _level()
	var a = rig.box(level, "a", Vector3.ZERO)
	rig.plugin._paint_brush_with_undo(level, a, level.get_materials()[3])
	assert_eq(_recent(), [_path(level, 3)])
	await rig.leave_level(level)


func test_a_drop_from_the_browser_is_a_use() -> void:
	var level = await _level()
	rig.box(level, "a", Vector3.ZERO)
	var aim := rig.camera.unproject_position(Vector3(0, 2, 0))
	# The drop casts from the camera the viewport last reported.
	rig.forward(PluginRig.motion(aim))
	HFPluginDropHandlerScript.handle_material_drop(
		rig.plugin, aim, {"type": "hammerforge_material", "index": 2}
	)
	assert_eq(_recent(), [_path(level, 2)])
	await rig.leave_level(level)


func test_a_favourite_on_brushes_is_a_use() -> void:
	var level = await _level()
	rig.plugin.dock.material_browser.add_favorite(_path(level, 1))
	var a = rig.box(level, "a", Vector3.ZERO)
	rig.select([a])
	await rig.frame()
	assert_eq(rig.forward(PluginRig.key(KEY_1, false, false, true)), STOP)
	assert_eq(_recent(), [_path(level, 1)])
	await rig.leave_level(level)


func test_apply_last_texture_and_apply_picked_look_are_uses() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	src.faces[_face_idx(src, Vector3.UP)].material_idx = 3
	src.rebuild_preview()
	var aim := rig.camera.unproject_position(Vector3(0, 2, 0))
	rig.forward(PluginRig.motion(aim))
	rig.forward(PluginRig.key_for("texture_picker"))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, aim))
	assert_eq(_recent(), [], "a pick is not a use")
	_select_top(level, a)

	rig.forward(PluginRig.key_for("apply_last_texture"))
	assert_eq(_recent(), [_path(level, 3)], "Shift+T is")

	rig.plugin._user_prefs.set_pref("recent_materials", [])
	rig.forward(PluginRig.key_for("apply_picked_look"))
	assert_eq(_recent(), [_path(level, 3)], "and so is Alt+T")
	await rig.leave_level(level)


func test_undo_and_redo_leave_the_row_alone() -> void:
	var level = await _level()
	var a = rig.box(level, "a", Vector3.ZERO)
	_select_top(level, a)
	var dock = rig.plugin.dock
	dock._selected_material_index = 1
	dock._on_material_assign()
	dock._selected_material_index = 2
	dock._on_material_assign()
	var row := _recent()
	assert_true(rig.undo().press_undo())
	assert_true(rig.undo().press_redo())
	assert_eq(_recent(), row, "taking a paint back and forth is not using it again")
	await rig.leave_level(level)


func test_a_material_with_no_path_is_left_out() -> void:
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new()])
	rig.plugin.dock._sync_materials_from_root()
	var a = rig.box(level, "a", Vector3.ZERO)
	_select_top(level, a)
	rig.plugin.dock._selected_material_index = 0
	rig.plugin.dock._on_material_assign()
	assert_eq(_recent(), [], "nothing could find it again")
	await rig.leave_level(level)


## A Recent material the open level's palette does not hold is added to it, as
## one undo step, and selected.
func test_a_recent_material_from_another_level_is_added_and_selected() -> void:
	var path := "user://hf_material_recent_other_%d.tres" % Time.get_ticks_usec()
	var saved := StandardMaterial3D.new()
	saved.resource_name = "from_another_level"
	assert_eq(ResourceSaver.save(saved, path), OK)
	var level = await _level(2)
	var dock = rig.plugin.dock
	rig.plugin._user_prefs.add_recent_material(path)
	dock.material_browser.refresh_recent()
	assert_eq(dock.material_browser.get_recent_paths(), [path], "the row shows it")
	var steps: int = rig.undo().step_count()

	(dock.material_browser._recent_cells.get_child(0) as Button).pressed.emit()
	await rig.frame()

	var slot: int = dock.material_browser.palette_slot_of(path)
	assert_eq(slot, 2, "it joins the palette")
	assert_eq(dock._selected_material_index, slot, "and is the selected material")
	assert_eq(rig.undo().step_count(), steps + 1, "as one step")
	await rig.leave_level(level)
	dock.material_browser._recent_loaded.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
