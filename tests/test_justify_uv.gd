extends GutTest

const FaceData = preload("res://addons/hammerforge/face_data.gd")
const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")
const CollationTests = preload("res://tests/test_undo_collation.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")

const LEVEL_PATH := "user://hf_test_justify_uv_groups.hflevel"
const SCENE_PATH := "user://hf_test_justify_uv_groups.tscn"


## The stand-in, answering the two calls the dock's history list makes of the
## editor's manager. With no scene history the list counts its own entries.
class DockUndo:
	extends CollationTests.FakeUndoRedo

	func get_object_history_id(_object: Object) -> int:
		return 0

	func get_history_undo_redo(_id: int) -> UndoRedo:
		return null


var root: LevelRoot
var sys: HFBrushSystem


func before_each():
	HFUndoHelper._reset_collation()
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	sys = root.brush_system


func after_each():
	HFUndoHelper._reset_collation()
	root = null
	sys = null
	for path in [LEVEL_PATH, SCENE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _make_face_with_uvs(uvs: PackedVector2Array) -> FaceData:
	var face = FaceData.new()
	# Build matching local_verts (same count as UVs, 3D positions don't matter for justify)
	var verts = PackedVector3Array()
	for uv in uvs:
		verts.append(Vector3(uv.x, uv.y, 0.0))
	face.local_verts = verts
	face.custom_uvs = uvs
	face.normal = Vector3.FORWARD
	face.uv_scale = Vector2.ONE
	face.uv_offset = Vector2.ZERO
	return face


# ===========================================================================
# _justify_face: direct unit tests on the internal method
# ===========================================================================


func test_justify_fit():
	# Face with UVs spanning 0.2 to 0.6 → after fit should span 0..1
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.2, 0.3), Vector2(0.6, 0.3), Vector2(0.6, 0.8), Vector2(0.2, 0.8)]
		)
	)
	var uv_min = Vector2(0.2, 0.3)
	var uv_max = Vector2(0.6, 0.8)
	sys._justify_face(face, "fit", uv_min, uv_max)
	# After fit: scale should map (0.4, 0.5) → (1.0, 1.0)
	# uv_scale.x should be 1.0 * (1/0.4) = 2.5
	# uv_scale.y should be 1.0 * (1/0.5) = 2.0
	assert_almost_eq(face.uv_scale.x, 2.5, 0.01, "Fit X scale")
	assert_almost_eq(face.uv_scale.y, 2.0, 0.01, "Fit Y scale")
	# custom_uvs should be cleared (forces re-projection)
	assert_eq(face.custom_uvs.size(), 0, "Fit should clear custom_uvs")


func test_justify_center():
	# Face with UVs centered at (0.3, 0.4) → after center, center should be (0.5, 0.5)
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.1, 0.2), Vector2(0.5, 0.2), Vector2(0.5, 0.6), Vector2(0.1, 0.6)]
		)
	)
	var uv_min = Vector2(0.1, 0.2)
	var uv_max = Vector2(0.5, 0.6)
	sys._justify_face(face, "center", uv_min, uv_max)
	# Center of (0.1,0.2)-(0.5,0.6) is (0.3, 0.4). Shift = (0.5-0.3, 0.5-0.4) = (0.2, 0.1)
	assert_almost_eq(face.uv_offset.x, 0.2, 0.01, "Center X offset")
	assert_almost_eq(face.uv_offset.y, 0.1, 0.01, "Center Y offset")


func test_justify_left():
	# UVs from 0.3 to 0.7 in X → after left, min X should be at 0
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.3, 0.0), Vector2(0.7, 0.0), Vector2(0.7, 1.0), Vector2(0.3, 1.0)]
		)
	)
	var uv_min = Vector2(0.3, 0.0)
	var uv_max = Vector2(0.7, 1.0)
	sys._justify_face(face, "left", uv_min, uv_max)
	assert_almost_eq(face.uv_offset.x, -0.3, 0.01, "Left should shift min X to 0")


func test_justify_right():
	# UVs from 0.3 to 0.7 in X → after right, max X should be at 1
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.3, 0.0), Vector2(0.7, 0.0), Vector2(0.7, 1.0), Vector2(0.3, 1.0)]
		)
	)
	var uv_min = Vector2(0.3, 0.0)
	var uv_max = Vector2(0.7, 1.0)
	sys._justify_face(face, "right", uv_min, uv_max)
	assert_almost_eq(face.uv_offset.x, 0.3, 0.01, "Right should shift max X to 1")


func test_justify_top():
	# UVs from 0.2 to 0.8 in Y → after top, min Y should be at 0
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.0, 0.2), Vector2(1.0, 0.2), Vector2(1.0, 0.8), Vector2(0.0, 0.8)]
		)
	)
	var uv_min = Vector2(0.0, 0.2)
	var uv_max = Vector2(1.0, 0.8)
	sys._justify_face(face, "top", uv_min, uv_max)
	assert_almost_eq(face.uv_offset.y, -0.2, 0.01, "Top should shift min Y to 0")


func test_justify_bottom():
	# UVs from 0.2 to 0.8 in Y → after bottom, max Y should be at 1
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.0, 0.2), Vector2(1.0, 0.2), Vector2(1.0, 0.8), Vector2(0.0, 0.8)]
		)
	)
	var uv_min = Vector2(0.0, 0.2)
	var uv_max = Vector2(1.0, 0.8)
	sys._justify_face(face, "bottom", uv_min, uv_max)
	assert_almost_eq(face.uv_offset.y, 0.2, 0.01, "Bottom should shift max Y to 1")


# ===========================================================================
# Justify: zero-size UV range is a no-op
# ===========================================================================


func test_justify_zero_range_noop():
	# All UVs at same point → range is zero → should not crash or change anything
	var face = _make_face_with_uvs(
		PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5)])
	)
	var original_scale = face.uv_scale
	var original_offset = face.uv_offset
	sys._justify_face(face, "fit", Vector2(0.5, 0.5), Vector2(0.5, 0.5))
	assert_eq(face.uv_scale, original_scale, "Zero-range fit should not change scale")
	assert_eq(face.uv_offset, original_offset, "Zero-range fit should not change offset")


# ===========================================================================
# justify_selected_faces via face_selection
# ===========================================================================


func test_justify_selected_faces_empty_selection():
	root.face_selection = {}
	# Should not crash
	sys.justify_selected_faces("center", false)
	assert_true(true, "Empty selection should not crash")


func test_justify_clears_custom_uvs():
	# All justify modes should clear custom_uvs to force re-projection
	var modes = ["fit", "center", "left", "right", "top", "bottom"]
	for mode in modes:
		var face = _make_face_with_uvs(
			PackedVector2Array(
				[Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.9, 0.9), Vector2(0.1, 0.9)]
			)
		)
		sys._justify_face(face, mode, Vector2(0.1, 0.1), Vector2(0.9, 0.9))
		assert_eq(face.custom_uvs.size(), 0, "Mode '%s' should clear custom_uvs" % mode)


func test_justify_preserves_existing_offset():
	# Center justify should ADD to existing offset, not replace
	var face = _make_face_with_uvs(
		PackedVector2Array(
			[Vector2(0.0, 0.0), Vector2(0.4, 0.0), Vector2(0.4, 0.4), Vector2(0.0, 0.4)]
		)
	)
	face.uv_offset = Vector2(0.1, 0.1)  # Pre-existing offset
	sys._justify_face(face, "center", Vector2(0.0, 0.0), Vector2(0.4, 0.4))
	# Center of (0,0)-(0.4,0.4) is (0.2, 0.2). Shift = (0.3, 0.3)
	# Final offset = (0.1 + 0.3, 0.1 + 0.3) = (0.4, 0.4)
	assert_almost_eq(face.uv_offset.x, 0.4, 0.01, "Center should add to existing offset X")
	assert_almost_eq(face.uv_offset.y, 0.4, 0.01, "Center should add to existing offset Y")


# ===========================================================================
# Texture groups: faces that stay one surface after edits (#1437)
# ===========================================================================

const EPS := 0.0001
## A panel's size: 32 along the wall, 64 high, 8 deep.
const PANEL := Vector3(32, 64, 8)


## A wall of `count` panels side by side along X, their fronts in one plane at
## z = 4, the first standing at x = 0.
func _wall(count := 3) -> Array:
	var panels: Array = []
	for i in count:
		var panel := (
			root.create_brush_from_info(
				{"size": PANEL, "center": Vector3(i * 32.0, 0, 0), "brush_id": "p%d" % i}
			)
			as DraftBrush
		)
		panel.sync_face_world_transform()
		panels.append(panel)
	return panels


static func _front_idx(panel: DraftBrush) -> int:
	for i in panel.faces.size():
		if (panel.faces[i] as FaceData).normal.is_equal_approx(Vector3.BACK):
			return i
	return -1


static func _front(panel: DraftBrush) -> FaceData:
	var idx := _front_idx(panel)
	return panel.faces[idx] if idx >= 0 else null


func _panel(index: int) -> DraftBrush:
	return root.find_brush_by_id("p%d" % index) as DraftBrush


func _select_fronts(panels: Array) -> void:
	root.clear_face_selection()
	for panel in panels:
		root.toggle_face_selection(panel, _front_idx(panel), true, false)


## Three panels linked into one surface and fitted across it.
func _linked_fitted_wall() -> Array:
	var panels := _wall(3)
	_select_fronts(panels)
	assert_eq(root.link_selected_faces(), 3, "three faces linked")
	root.justify_selected_faces("fit", false)
	return panels


## The UV a panel's front shows at a point of the level on it.
static func _uv_at(panel: DraftBrush, world: Vector3) -> Vector2:
	panel.sync_face_world_transform()
	var local: Vector3 = panel.global_transform.affine_inverse() * world
	return _front(panel).shown_uvs_at(PackedVector3Array([local]))[0]


## The UV bounds of every panel's front together.
static func _bounds(panels: Array) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for panel in panels:
		(panel as DraftBrush).sync_face_world_transform()
		for uv in _front(panel).shown_uvs():
			low = low.min(uv)
			high = high.max(uv)
	return Rect2(low, high - low)


func _assert_one_mapping(panels: Array, what: String) -> void:
	var first := _front(panels[0])
	for panel in panels:
		var face := _front(panel)
		assert_ne(face.uv_group, 0, "%s: %s is linked" % [what, panel.brush_id])
		assert_eq(face.uv_group, first.uv_group, "%s: %s is in the group" % [what, panel.brush_id])
		assert_almost_eq(face.uv_scale, first.uv_scale, Vector2(EPS, EPS), "%s: scale" % what)
		assert_almost_eq(face.uv_offset, first.uv_offset, Vector2(EPS, EPS), "%s: offset" % what)
		assert_almost_eq(face.uv_rotation, first.uv_rotation, EPS, "%s: rotation" % what)


func _assert_fitted(panels: Array, what: String) -> void:
	var bounds := _bounds(panels)
	assert_almost_eq(bounds.position, Vector2.ZERO, Vector2(EPS, EPS), "%s: from 0" % what)
	assert_almost_eq(bounds.end, Vector2.ONE, Vector2(EPS, EPS), "%s: to 1" % what)


func _assert_seam(left: DraftBrush, right: DraftBrush, world: Vector3, what: String) -> void:
	assert_almost_eq(
		_uv_at(right, world), _uv_at(left, world), Vector2(EPS, EPS), "%s at %s" % [what, world]
	)


func test_link_lays_one_mapping_on_the_faces_and_fit_spans_them_all():
	var panels := _linked_fitted_wall()
	_assert_one_mapping(panels, "linked")
	_assert_fitted(panels, "fitted as one")
	for panel in panels:
		assert_eq(_front(panel).uv_group_justify, "fit", "the group keeps the mode")


func test_three_linked_fitted_panels_stay_one_texture_after_one_is_moved():
	root.texture_lock = true
	var panels := _linked_fitted_wall()
	var middle: DraftBrush = panels[1]

	root.set_brush_transform_by_id("p1", PANEL, middle.global_position + Vector3(0, 8, 0))

	panels = [_panel(0), _panel(1), _panel(2)]
	_assert_one_mapping(panels, "after the move")
	_assert_fitted(panels, "fitted again to the taller surface")
	# The seams the moved panel shares with each neighbour, where they overlap.
	_assert_seam(panels[0], panels[1], Vector3(16, 20, 4), "left seam")
	_assert_seam(panels[1], panels[2], Vector3(48, 20, 4), "right seam")


func test_resizing_one_linked_panel_refits_the_group_across_the_new_bounds():
	root.texture_lock = true
	var panels := _linked_fitted_wall()

	# The right panel grows to the right, so the wall runs from x = -16 to 112.
	root.set_brush_transform_by_id("p2", Vector3(64, 64, 8), Vector3(80, 0, 0))

	panels = [_panel(0), _panel(1), _panel(2)]
	_assert_one_mapping(panels, "after the resize")
	_assert_fitted(panels, "fitted across the wider wall")
	assert_almost_eq(
		_uv_at(panels[2], Vector3(112, 0, 4)).x, 1.0, EPS, "the texture ends at the new edge"
	)


func test_linking_a_fourth_face_joins_it_to_the_surface_with_no_seam():
	var panels := _linked_fitted_wall()
	var fourth := (
		root.create_brush_from_info({"size": PANEL, "center": Vector3(96, 0, 0), "brush_id": "p3"})
		as DraftBrush
	)
	fourth.sync_face_world_transform()
	var before := _front(panels[0]).to_dict()
	_select_fronts([panels[2], fourth])

	root.link_selected_faces()

	_assert_one_mapping([panels[0], panels[1], panels[2], fourth], "four linked")
	_assert_seam(panels[2], fourth, Vector3(80, 10, 4), "the new seam")
	assert_eq(_front(panels[0]).to_dict(), before, "the surface it joined is as it was")


func test_duplicating_a_linked_panel_extends_the_surface_with_no_seam():
	var panels := _linked_fitted_wall()
	var info: Dictionary = root.build_duplicate_info(panels[2], Vector3(32, 0, 0))
	info["brush_id"] = "p3"
	var copy := root.create_brush_from_info(info) as DraftBrush
	copy.sync_face_world_transform()

	_assert_one_mapping([panels[0], panels[1], panels[2], copy], "with the copy")
	_assert_seam(panels[2], copy, Vector3(80, 10, 4), "the copy's seam")


func test_unlink_leaves_the_faces_showing_what_they_showed():
	var panels := _linked_fitted_wall()
	var shown: Array = []
	for panel in panels:
		shown.append(_front(panel).shown_uvs())
	_select_fronts([panels[1]])

	assert_eq(root.unlink_selected_faces(), 1, "one face left its surface")

	assert_eq(_front(panels[1]).uv_group, 0, "the middle is on its own")
	assert_ne(_front(panels[0]).uv_group, 0, "the others are still linked")
	for i in panels.size():
		assert_eq(_front(panels[i]).shown_uvs(), shown[i], "panel %d shows what it showed" % i)


func test_select_group_selects_every_linked_face():
	var panels := _linked_fitted_wall()
	_select_fronts([panels[1]])

	assert_eq(root.select_texture_group(), 3)

	for panel in panels:
		assert_has(root.face_selection.get(panel.brush_id, []), _front_idx(panel), panel.brush_id)


func test_an_edit_to_one_linked_face_is_an_edit_to_the_surface():
	var panels := _linked_fitted_wall()
	_select_fronts([panels[0]])
	root.edit_selected_face_uvs("scale_up")
	_assert_one_mapping(panels, "after x2 on one face")
	root.set_face_uv_params("p2", _front_idx(panels[2]), Vector2(3, 3), Vector2(0.5, 0.25), 0.2)
	_assert_one_mapping(panels, "after a typed value on another")


## Lock the visgroup of the third panel of `_linked_fitted_wall()`.
func _lock_third(panels: Array) -> void:
	root.create_visgroup("Done")
	root.add_selection_to_visgroup("Done", [panels[2]])
	root.visgroup_system.set_visgroup_locked("Done", true)


## A face of the group on a locked brush keeps its mapping when another face of
## it is scaled, and the faces that may change still change as one (#1978).
func test_an_edit_to_a_linked_face_leaves_its_mate_on_a_locked_brush_alone():
	var panels := _linked_fitted_wall()
	_lock_third(panels)
	var locked_before := _front(panels[2]).to_dict()
	var scale_before := _front(panels[0]).uv_scale
	_select_fronts([panels[0]])

	root.edit_selected_face_uvs("scale_up")

	assert_ne(_front(panels[0]).uv_scale, scale_before, "the picked face is scaled")
	_assert_one_mapping([panels[0], panels[1]], "the unlocked faces, as one")
	assert_eq(_front(panels[2]).to_dict(), locked_before, "the locked face keeps its mapping")


func test_a_refit_after_a_move_leaves_a_face_on_a_locked_brush_alone():
	root.texture_lock = true
	var panels := _linked_fitted_wall()
	_lock_third(panels)
	var locked_before := _front(panels[2]).to_dict()
	var free_before := _front(panels[0]).to_dict()

	root.set_brush_transform_by_id("p1", PANEL, panels[1].global_position + Vector3(0, 8, 0))

	assert_ne(_front(_panel(0)).to_dict(), free_before, "the unlocked faces are fitted again")
	assert_eq(_front(_panel(2)).to_dict(), locked_before, "the locked face is not")


func test_justify_and_select_group_leave_out_a_face_on_a_locked_brush():
	var panels := _linked_fitted_wall()
	_lock_third(panels)
	var locked_before := _front(panels[2]).to_dict()
	var free_before := _front(panels[0]).to_dict()
	_select_fronts([panels[0]])

	root.justify_selected_faces("right", false)
	assert_ne(_front(panels[0]).to_dict(), free_before, "Justify moves the unlocked faces")
	assert_eq(_front(panels[2]).to_dict(), locked_before, "and leaves the locked face")

	assert_eq(root.select_texture_group(), 2, "Select Group picks the two unlocked faces")
	assert_false(root.face_selection.has("p2"), "and not the locked one")


func test_a_clipped_linked_panel_stays_part_of_the_surface():
	_linked_fitted_wall()

	assert_true(root.clip_brush_by_id("p2", 1, 16.0).ok, "the right panel is cut across")

	var fronts: Array = []
	for brush in root.get_all_draft_brushes():
		if _front(brush) != null:
			fronts.append(brush)
	assert_eq(fronts.size(), 4, "two panels and the two halves of the third")
	_assert_one_mapping(fronts, "after the cut")
	_assert_fitted(fronts, "fitted as before")


func test_group_ids_survive_a_save_and_reload():
	var panels := _linked_fitted_wall()
	var group_id := _front(panels[0]).uv_group
	assert_eq(HFLevelIO.save_to_path(LEVEL_PATH, root._capture_hflevel_state(), false), OK, "saved")
	root.clear_brushes()

	assert_true(root.load_hflevel(LEVEL_PATH), "and loaded")

	panels = [_panel(0), _panel(1), _panel(2)]
	for panel in panels:
		assert_eq(_front(panel).uv_group, group_id, "%s is in the same group" % panel.brush_id)
		assert_eq(_front(panel).uv_group_justify, "fit", "and remembers the fit")


func test_group_ids_survive_a_saved_scene():
	var panels := _linked_fitted_wall()
	var group_id := _front(panels[0]).uv_group
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	assert_eq(ResourceSaver.save(packed, SCENE_PATH), OK, "the scene saves")
	var loaded := (
		ResourceLoader.load(SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var copy := loaded.instantiate() as LevelRoot
	add_child_autoqfree(copy)

	for i in 3:
		var reopened := copy.find_brush_by_id("p%d" % i) as DraftBrush
		assert_not_null(reopened, "panel %d comes back" % i)
		if reopened == null:
			continue
		assert_ne(_front(reopened), _front(panels[i]), "its faces were read from the file")
		assert_eq(_front(reopened).uv_group, group_id, "panel %d is in the same group" % i)
		assert_eq(_front(reopened).uv_group_justify, "fit", "and remembers the fit")


func _make_dock() -> Node:
	var prefs := HFUserPrefsType.new()
	prefs.persistence_enabled = false
	prefs.data = HFUserPrefsType._defaults()
	prefs.data["show_welcome"] = false
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.set_user_prefs(prefs)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	dock.undo_redo = DockUndo.new()
	return dock


func test_one_undo_takes_back_a_link():
	_select_fronts(_wall(3))
	var dock := _make_dock()
	var undo = dock.undo_redo
	var steps: int = undo.entries.size()

	dock.uv_link_btn.pressed.emit()

	assert_eq(undo.entries.size(), steps + 1, "Link is one step")
	_assert_one_mapping([_panel(0), _panel(1), _panel(2)], "linked")
	undo.undo()
	for i in 3:
		assert_eq(_front(_panel(i)).uv_group, 0, "panel %d is unlinked again" % i)
	await get_tree().process_frame


func test_one_undo_takes_back_an_edit_spread_across_brushes():
	var panels := _linked_fitted_wall()
	var was: Array = []
	for panel in panels:
		was.append(_front(panel).to_dict())
	_select_fronts([panels[0]])
	var dock := _make_dock()
	var undo = dock.undo_redo
	# A value typed for the face on show is a step scoped to that face's brush.
	dock._set_uv_face(panels[0], _front(panels[0]))

	dock.uv_offset_x.value = 0.75

	assert_almost_eq(_front(_panel(2)).uv_offset.x, 0.75, EPS, "the far panel took the edit")
	undo.undo()
	for i in 3:
		assert_eq(_front(_panel(i)).to_dict(), was[i], "panel %d is put back" % i)
	await get_tree().process_frame
