extends GutTest

## The material browser knows what the open level uses (#1725): a mark on each
## used material with its face count, a Used only filter and an order by use, a
## search that takes every word, Select Faces and Select Brushes Using This, and
## a thumbnail size that is remembered.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFMaterialUse = preload("res://addons/hammerforge/hf_material_use.gd")

var root: LevelRoot
var dock: Node
var prefs: HFUserPrefs


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	for i in 4:
		var mat := StandardMaterial3D.new()
		mat.resource_name = ["wall_brick_red_02", "floor_stone", "trim_wood", "glass_blue"][i]
		root.add_material_to_palette(mat)
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	prefs = HFUserPrefs.new()
	prefs.persistence_enabled = false
	prefs.data = HFUserPrefs._defaults()
	dock.material_browser.set_user_prefs(prefs)
	dock.material_browser.set_material_manager(root.material_manager)
	dock.material_browser._view_mode = HFMaterialBrowser.ViewMode.PALETTE


func after_each() -> void:
	root = null
	dock = null


func _box(center: Vector3, slot: int) -> DraftBrush:
	var brush: DraftBrush = root.create_brush_from_info(
		{"shape": 0, "size": Vector3.ONE, "center": center}
	)
	for face in brush.faces:
		face.material_idx = slot
	root.tag_brush_dirty(str(brush.brush_id))
	return brush


func _shown_slots() -> Array:
	return Array(dock.material_browser._cell_to_palette_index)


func _marked_slots() -> Array:
	var out: Array = []
	var cells: Array = dock.material_browser._grid.get_children()
	for i in cells.size():
		if cells[i].is_queued_for_deletion():
			continue
		if cells[i].find_child("InUse", false, false) != null:
			out.append(dock.material_browser._cell_to_palette_index[i])
	return out


func test_used_materials_carry_the_mark_and_in_use_shows_just_those():
	_box(Vector3.ZERO, 1)
	_box(Vector3(3, 0, 0), 2)
	_box(Vector3(6, 0, 0), 2)
	dock.material_browser.rebuild()
	assert_eq(_marked_slots(), [1, 2], "the two slots in use are marked")
	assert_eq(dock.material_browser.use_count(2), 12, "slot 2 is on twelve faces")
	dock.material_browser._view_toggle.select(HFMaterialBrowser.ViewMode.IN_USE)
	dock.material_browser._on_view_mode_changed(HFMaterialBrowser.ViewMode.IN_USE)
	assert_eq(_shown_slots(), [2, 1], "In Use shows just those, most used first")


func test_every_word_of_the_search_is_matched_in_any_order():
	assert_true(HFMaterialBrowser.matches_words("brick red", "wall_brick_red_02"))
	assert_true(HFMaterialBrowser.matches_words("red brick", "wall_brick_red_02"))
	assert_false(HFMaterialBrowser.matches_words("brick blue", "wall_brick_red_02"))
	dock.material_browser._on_search_changed("brick red")
	assert_eq(_shown_slots(), [0], "the browser finds wall_brick_red_02 by two words")


func test_select_faces_using_this_picks_exactly_the_visible_unlocked_faces():
	var shown := _box(Vector3.ZERO, 2)
	shown.faces[0].material_idx = 1
	var hidden := _box(Vector3(3, 0, 0), 2)
	var locked := _box(Vector3(6, 0, 0), 2)
	root.create_visgroup("held")
	root.add_selection_to_visgroup("held", [locked])
	root.visgroup_system.set_visgroup_locked("held", true)
	# After the visgroup, which shows every brush again as it applies itself.
	hidden.visible = false
	var other := _box(Vector3(9, 0, 0), 3)
	var total: int = dock.select_faces_using(2)
	assert_eq(total, 5, "the five faces of the visible box that use it")
	assert_eq(root.face_selection.size(), 1, "on that box alone")
	var indices: Array = root.face_selection.values()[0]
	assert_false(indices.has(0), "not the face that uses another material")
	assert_true(dock.is_face_select_mode_enabled(), "in Face Select")
	assert_eq(
		dock.select_brushes_using(2), [shown], "Select Brushes Using This takes the visible one"
	)
	assert_true(is_instance_valid(other))


func test_the_thumbnail_size_changes_live_and_is_remembered():
	dock.material_browser.rebuild()
	dock.material_browser.set_thumb_size(128)
	var first: Control = dock.material_browser._grid.get_child(0)
	assert_eq(first.custom_minimum_size.x, 136.0, "the cells grow at once")
	assert_eq(int(prefs.get_pref("material_thumb_size")), 128, "and the size is kept")
	var again := HFMaterialBrowser.new()
	add_child_autofree(again)
	again.set_user_prefs(prefs)
	assert_eq(again.get_thumb_size(), 128, "a new browser opens at it")
	dock.material_browser.set_thumb_size(1000)
	assert_eq(dock.material_browser.get_thumb_size(), HFMaterialBrowser.THUMB_SIZE_MAX)


func test_a_level_of_5000_faces_is_counted_once_per_change():
	for i in 834:
		_box(Vector3(float(i % 30) * 2.0, 0, float(i / 30) * 2.0), 1)
	HFMaterialUse.invalidate(root)
	var before := HFMaterialUse.passes(root)
	var started := Time.get_ticks_usec()
	dock.material_browser.rebuild()
	var took := (Time.get_ticks_usec() - started) / 1000.0
	assert_eq(dock.material_browser.use_count(1), 5004, "every face counted")
	assert_lt(took, 500.0, "the browser opens without a stall (%.1f ms)" % took)
	for _i in 10:
		dock.material_browser.refresh_use()
	assert_eq(HFMaterialUse.passes(root), before + 1, "redraws use the kept counts")
	var one: DraftBrush = root.draft_brushes_node.get_child(0)
	one.faces[0].material_idx = 2
	root.tag_brush_dirty(str(one.brush_id))
	dock.material_browser.refresh_use()
	assert_eq(HFMaterialUse.passes(root), before + 2, "a face change counts again")
	assert_eq(dock.material_browser.use_count(2), 1)
