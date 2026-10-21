extends GutTest

## create_brush_from_info() is the single door into the level for undo restore,
## duplication, prefab instancing, .map import and .hflevel load. A size it
## cannot build has to be refused there rather than becoming a brush that looks
## fine in the tree and bakes to nothing.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFBrushSystemType = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFPathTool = preload("res://addons/hammerforge/hf_path_tool.gd")
const HFPolygonTool = preload("res://addons/hammerforge/hf_polygon_tool.gd")

## A piece as thin as a Path trim 0.05 tall, half the floor a size is held to.
const THIN := Vector3(2, 0.05, 2)
const NEAR := Vector3(0.0001, 0.0001, 0.0001)
const WARNED := "cannot be built"
const SCENE_PATH := "user://test_brush_size_guard.tscn"
const LEVEL_PATH := "user://test_brush_size_guard.hflevel"

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	HFLog.end_test_capture()
	for path in [SCENE_PATH, LEVEL_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _make(size) -> DraftBrush:
	return root.create_brush_from_info({"size": size, "center": Vector3.ZERO}) as DraftBrush


func test_a_negative_size_is_built_the_right_way_out():
	var brush := _make(Vector3(-32, 32, 32))

	assert_not_null(brush, "The brush is still created")
	assert_eq(brush.size, Vector3(32, 32, 32), "at the size it asked for, the right way round")
	assert_gt(brush.global_transform.basis.determinant(), 0.0, "with a basis that does not invert")


func test_every_face_normal_agrees_with_its_own_vertices():
	var brush := _make(Vector3(-32, 32, 32))

	for face in brush.faces:
		# FaceData winds clockwise seen from outside, so (c - a) x (b - a) is the
		# outward normal. A negative determinant used to flip one and not the
		# other.
		var a: Vector3 = face.local_verts[0]
		var b: Vector3 = face.local_verts[1]
		var c: Vector3 = face.local_verts[2]
		var from_verts: Vector3 = (c - a).cross(b - a).normalized()
		assert_gt(from_verts.dot(face.normal), 0.9, "The stored normal should match the winding")


func test_a_zero_size_becomes_a_brush_with_volume():
	var brush := _make(Vector3.ZERO)

	assert_not_null(brush, "The brush is still created")
	assert_gt(brush.size.x, 0.0, "with an x extent")
	assert_gt(brush.size.y, 0.0, "a y extent")
	assert_gt(brush.size.z, 0.0, "and a z extent")


func test_a_partly_zero_size_only_moves_the_axis_that_was_wrong():
	var brush := _make(Vector3(64, 0, 16))

	assert_eq(brush.size.x, 64.0, "A good axis is left alone")
	assert_eq(brush.size.z, 16.0, "and so is the other one")
	assert_gt(brush.size.y, 0.0, "while the bad one gets the floor")


func test_a_good_size_is_untouched():
	var brush := _make(Vector3(48, 16, 8))

	assert_eq(brush.size, Vector3(48, 16, 8), "A usable size passes straight through")


func test_a_size_that_is_not_a_vector3_still_builds_something():
	var brush := root.create_brush_from_info({"size": "not a size"}) as DraftBrush

	assert_not_null(brush, "A junk size should not produce a null brush")
	assert_gt(brush.size.x, 0.0, "and the brush should have volume")


func test_the_validator_finds_nothing_to_fix_after_a_bad_size():
	_make(Vector3(-32, 32, 32))
	_make(Vector3.ZERO)

	var report: Dictionary = root.validate_level(false)

	var brush_issues: Array = []
	for issue in report["issues"]:
		if str(issue).contains("brush"):
			brush_issues.append(str(issue))
	assert_eq(brush_issues, [], "Validate should have nothing to say about a brush now")


func test_the_validator_calls_an_inverted_brush_inverted():
	var brush := _make(Vector3(32, 32, 32))
	# Reach past the guard, the way a brush that predates it would look.
	brush.size = Vector3(-32, 32, 32)

	var report: Dictionary = root.validate_level(false)

	var found := false
	for issue in report["issues"]:
		if str(issue).begins_with("Inverted brush"):
			found = true
	assert_true(found, "A negative size is inverted, not zero-size")


func test_the_validator_still_calls_a_zero_brush_zero_size():
	var brush := _make(Vector3(32, 32, 32))
	brush.size = Vector3(0, 32, 32)

	var report: Dictionary = root.validate_level(false)

	var found := false
	for issue in report["issues"]:
		if str(issue).begins_with("Zero-size brush"):
			found = true
	assert_true(found, "A zero extent is still zero-size")


# ===========================================================================
# Two brushes in the same place (#702)
# ===========================================================================


func _issues() -> Array:
	return (root.validate_level(false) as Dictionary).get("issues", [])


func _lines_about(text: String) -> Array:
	return _issues().filter(func(line: String) -> bool: return line.contains(text))


func test_a_duplicate_left_in_place_is_reported():
	# Ctrl+D and then a drag that did not take. The copy is exactly on the
	# original, nothing looks wrong in the viewport, and the level gets doubled
	# triangles and z-fighting on every coincident face.
	var first := _make(Vector3(4, 1, 4))
	var second := _make(Vector3(4, 1, 4))
	assert_not_null(first)
	assert_not_null(second)
	var said := _lines_about("occupy the same space")
	assert_eq(said.size(), 1, "one pair, one line: %s" % str(_issues()))
	assert_true(str(said[0]).contains("2 brushes"), "and it says how many: %s" % said[0])


func test_ordinary_intersecting_brushes_are_not_reported():
	# Brushes are meant to intersect. The check has to be the narrow one or it
	# fires on every wall meeting every floor.
	_make(Vector3(4, 1, 4))
	var moved := _make(Vector3(4, 1, 4))
	moved.global_position = Vector3(1, 0, 0)
	assert_eq(_lines_about("occupy the same space"), [], "an overlap is not a duplicate")


func test_brushes_of_different_size_in_one_place_are_not_reported():
	_make(Vector3(4, 1, 4))
	_make(Vector3(2, 1, 2))
	assert_eq(_lines_about("occupy the same space"), [], "different solids, same centre")


func test_three_in_one_place_are_one_line():
	_make(Vector3(4, 1, 4))
	_make(Vector3(4, 1, 4))
	_make(Vector3(4, 1, 4))
	var said := _lines_about("occupy the same space")
	assert_eq(said.size(), 1, "one group, one line")
	assert_true(str(said[0]).contains("3 brushes"))


# ===========================================================================
# A brush built from its own faces (#1592)
# ===========================================================================


## A CUSTOM brush's info with the faces of a box `size` across, the shape a Path
## trim piece or a thin Polygon slab has.
func _custom_info(size: Vector3) -> Dictionary:
	var faces: Array = []
	for face in DraftBrush.generated_faces(DraftBrush.BrushShape.BOX, size, 4):
		faces.append(face.to_dict())
	return {
		"shape": DraftBrush.BrushShape.CUSTOM,
		"size": size,
		"center": Vector3(0, 3, 0),
		"faces": faces,
	}


## How far a brush's faces reach on each axis, which is what is built.
func _extent(brush: DraftBrush) -> Vector3:
	return DraftBrush._vertex_bounds(brush.faces).size


## The size warnings HFLog has taken since `begin_test_capture()`.
func _size_warnings() -> Array:
	return HFLog.get_captured_warnings().filter(
		func(line: String) -> bool: return line.contains(WARNED)
	)


func _only_brush(level: LevelRoot) -> DraftBrush:
	var brushes := level.draft_brushes_node.get_children().filter(
		func(child: Node) -> bool: return child is DraftBrush
	)
	assert_eq(brushes.size(), 1, "one brush in the level")
	return brushes[0] as DraftBrush


## The owners the editor assigns. Headless there is no edited scene, so without
## them `pack()` writes an empty scene.
func _own(node: Node) -> void:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child in current.get_children():
			child.owner = node
			stack.append(child)


func _save_and_reopen_scene() -> LevelRoot:
	_own(root)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	assert_eq(ResourceSaver.save(packed, SCENE_PATH), OK, "the scene saves")
	var loaded := (
		ResourceLoader.load(SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var copy := loaded.instantiate() as LevelRoot
	add_child_autoqfree(copy)
	return copy


func _uv_scales(brush: DraftBrush) -> Array:
	var out: Array = []
	for face in brush.faces:
		out.append(face.uv_scale)
	return out


func test_a_thin_custom_brush_keeps_its_size_and_is_not_warned_about():
	HFLog.begin_test_capture([WARNED])
	var brush := root.create_brush_from_info(_custom_info(THIN)) as DraftBrush

	assert_not_null(brush, "the piece is made")
	assert_almost_eq(brush.size, THIN, NEAR, "its size says how thick its faces are")
	assert_almost_eq(_extent(brush), THIN, NEAR, "and its faces are as they were given")
	assert_eq(_size_warnings(), [], "nothing says it cannot be built")


func test_a_thin_box_still_gets_the_floor_and_the_warning():
	HFLog.begin_test_capture([WARNED])
	var box := (
		root.create_brush_from_info({"shape": DraftBrush.BrushShape.BOX, "size": THIN})
		as DraftBrush
	)

	assert_eq(box.size, Vector3(2, 0.1, 2), "a box is built from its size, so it gets the floor")
	assert_almost_eq(_extent(box).y, 0.1, 0.0001, "and is built that thick")
	assert_eq(_size_warnings().size(), 1, "with the warning that says so")


func test_a_custom_brush_with_no_faces_is_built_from_its_size_and_gets_the_floor():
	HFLog.begin_test_capture([WARNED])
	var info := _custom_info(THIN)
	info.erase("faces")
	var brush := root.create_brush_from_info(info) as DraftBrush

	assert_eq(brush.size, Vector3(2, 0.1, 2), "with no faces its size is what builds it")
	assert_almost_eq(_extent(brush).y, 0.1, 0.0001, "and it is built that thick")
	assert_eq(_size_warnings().size(), 1, "with the warning")


func test_a_zero_side_on_a_custom_brush_is_still_put_right():
	HFLog.begin_test_capture([WARNED])
	var info := _custom_info(THIN)
	info["size"] = Vector3(2, 0, 2)
	var brush := root.create_brush_from_info(info) as DraftBrush

	assert_eq(brush.size, Vector3(2, 0.1, 2), "no faces have a zero side, so it gets the floor")
	assert_eq(_size_warnings().size(), 1, "and the warning")
	assert_almost_eq(_extent(brush), THIN, NEAR, "while its faces stay as given")


func test_a_thin_custom_brush_keeps_its_faces_through_undo_a_load_and_a_reopen():
	HFLog.begin_test_capture([WARNED])
	root.create_brush_from_info(_custom_info(THIN))

	root.restore_state(root.capture_state(true))
	var restored := _only_brush(root)
	assert_almost_eq(restored.size, THIN, NEAR, "an undo step puts its size back")
	assert_almost_eq(_extent(restored), THIN, NEAR, "and its faces")

	assert_eq(HFLevelIO.save_to_path(LEVEL_PATH, root._capture_hflevel_state()), OK)
	assert_true(root.load_hflevel(LEVEL_PATH), "the level loads")
	var loaded := _only_brush(root)
	assert_almost_eq(loaded.size, THIN, NEAR, "an .hflevel keeps its size")
	assert_almost_eq(_extent(loaded), THIN, NEAR, "and its faces")

	var reopened := _only_brush(_save_and_reopen_scene())
	assert_almost_eq(reopened.size, THIN, NEAR, "a saved scene keeps its size")
	assert_almost_eq(_extent(reopened), THIN, NEAR, "and its faces")
	assert_eq(_size_warnings(), [], "and none of it says it cannot be built")


func test_a_nudge_leaves_a_thin_custom_brush_and_its_texture_alone():
	HFLog.begin_test_capture([WARNED])
	root.texture_lock = true
	var brush := root.create_brush_from_info(_custom_info(THIN)) as DraftBrush
	var scales := _uv_scales(brush)
	var start := brush.global_position

	root.nudge_brushes_by_id([brush.brush_id], Vector3(1, 0, 0))

	assert_eq(brush.global_position, start + Vector3(1, 0, 0), "the piece moves")
	assert_almost_eq(brush.size, THIN, NEAR, "at the size it was")
	assert_eq(_uv_scales(brush), scales, "Texture Lock reads no stretch into a move")
	assert_eq(_size_warnings(), [], "and nothing says it cannot be built")


func test_a_piece_apply_rotation_and_scale_left_thin_keeps_its_texture_on_a_nudge():
	HFLog.begin_test_capture([WARNED])
	root.texture_lock = true
	var brush := root.create_brush_from_info(_custom_info(Vector3(2, 2, 2))) as DraftBrush
	brush.global_transform = Transform3D(Basis.from_scale(Vector3(1, 0.025, 1)), Vector3(0, 3, 0))
	root.transform_system.apply_rotation_and_scale([brush.brush_id])
	assert_almost_eq(brush.size, THIN, NEAR, "the fold leaves the size its faces have")
	var scales := _uv_scales(brush)

	root.nudge_brushes_by_id([brush.brush_id], Vector3(1, 0, 0))

	assert_almost_eq(brush.size, THIN, NEAR, "a nudge keeps it")
	assert_eq(_uv_scales(brush), scales, "and keeps the texture on its sides")
	assert_eq(_size_warnings(), [], "with no warning")


func test_validate_still_finds_a_custom_sliver_and_passes_a_thin_piece():
	HFLog.begin_test_capture([WARNED])
	var sliver := root.create_brush_from_info(_custom_info(Vector3(2, 0.005, 2))) as DraftBrush
	var thin := root.create_brush_from_info(_custom_info(THIN)) as DraftBrush
	thin.global_position = Vector3(10, 3, 0)

	var degenerate: Array = []
	for issue in root.validation_system.check_bake_issues():
		if str(issue.get("type", "")) == "degenerate":
			degenerate.append(issue["node"])

	assert_eq(degenerate, [sliver], "a piece 0.005 thick is too thin, and only that one")


func test_a_path_trim_0_05_tall_builds_without_a_warning():
	HFLog.begin_test_capture([WARNED])
	var tool = HFPathTool.new()
	tool.root = root
	tool.set_setting("path_extra", HFPathTool.PathExtra.TRIM)
	tool.set_setting("trim_height", 0.05)
	tool._phase = tool.Phase.PLACING_WAYPOINTS
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(8, 0, 0)])

	assert_true(tool._build_path(), "the path builds")

	var trims: Array = []
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush and absf(_extent(child).y - 0.05) < 0.0001:
			trims.append(child)
	assert_eq(trims.size(), 2, "a trim strip along each edge")
	for trim: DraftBrush in trims:
		assert_almost_eq(trim.size.y, 0.05, 0.0001, "%s is as tall as its faces" % trim.name)
	assert_eq(_size_warnings(), [], "and none of them says it cannot be built")
	await get_tree().process_frame


func test_a_polygon_slab_0_05_wide_builds_without_a_warning():
	HFLog.begin_test_capture([WARNED])
	var tool = HFPolygonTool.new()
	tool._ground_y = 0.0
	tool._height = 1.0
	var info: Dictionary = tool._brush_info(
		PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 0.05)])
	)

	var brush := root.create_brush_from_info(info) as DraftBrush

	assert_almost_eq(brush.size, Vector3(4, 1, 0.05), NEAR, "its size is its faces' size")
	assert_almost_eq(_extent(brush).z, 0.05, 0.0001, "and its faces are as drawn")
	assert_eq(_size_warnings(), [], "nothing says it cannot be built")
