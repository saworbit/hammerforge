extends GutTest

## A face's sculpt saved with the scene (#854).
##
## The default `scene_contents` keeps the brushes in the `.tscn`, and reopening
## the scene does not read the `.hflevel`. A sculpt has to travel in the scene
## as a sub-resource of its face, the way the face's UVs and paint layers do.
##
## These write the scene to disk and load it with the cache ignored. A
## `PackedScene` held in memory hands back the same FaceData objects, so it
## would keep a sculpt that never reached the file.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

const PATH := "user://test_sculpt_scene_save.tscn"
const TOP := 2


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _box(root: LevelRoot) -> DraftBrush:
	return (
		(
			root
			. create_brush_from_info(
				{
					"shape": root.BrushShape.BOX,
					"size": Vector3(32, 32, 32),
					"transform": Transform3D.IDENTITY,
					"operation": CSGShape3D.OPERATION_UNION,
				}
			)
		)
		as DraftBrush
	)


## The owners the editor assigns. Headless there is no edited scene, so without
## them `pack()` writes an empty scene.
func _own(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


## Save the level the way Ctrl+S does, and open the file again.
func _save_and_reopen(root: LevelRoot) -> LevelRoot:
	_own(root)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	assert_eq(ResourceSaver.save(packed, PATH), OK, "the scene saves")
	var loaded := (
		ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var copy := loaded.instantiate() as LevelRoot
	add_child_autoqfree(copy)
	return copy


func _find(root: LevelRoot, brush_id: String) -> DraftBrush:
	return root.find_brush_by_id(brush_id) as DraftBrush


func _sculpt(root: LevelRoot, brush: DraftBrush) -> Resource:
	assert_true(root.create_displacement(brush.brush_id, TOP, 2), "the top face takes a sculpt")
	var sculpt: Resource = brush.faces[TOP].displacement
	sculpt.set_distance(1, 1, 5.0)
	sculpt.set_distance(0, 2, -1.5)
	sculpt.set_alpha(2, 0, 0.75)
	sculpt.set_offset(1, 2, Vector3(0.0, 0.6, 0.8))
	sculpt.elevation = 2.5
	sculpt.sew_group = 3
	sculpt.flip_diagonals = true
	return sculpt


func test_a_sculpt_comes_back_from_the_saved_scene():
	var root := _fresh_root()
	var brush := _box(root)
	var sculpt := _sculpt(root, brush)

	var copy := _save_and_reopen(root)
	var reopened := _find(copy, brush.brush_id)
	assert_not_null(reopened, "the brush comes back")
	if reopened == null:
		return
	assert_ne(reopened.faces[TOP], brush.faces[TOP], "the face was read from the file")
	var back: Resource = reopened.faces[TOP].displacement
	assert_not_null(back, "the sculpt is still on its face")
	if back == null:
		return
	assert_eq(back.power, sculpt.power, "power")
	assert_eq(back.distances, sculpt.distances, "every height")
	assert_eq(back.get_distance(1, 1), 5.0, "the height that was set")
	assert_eq(back.alphas, sculpt.alphas, "every blend value")
	assert_eq(back.offsets, sculpt.offsets, "every custom offset")
	assert_eq(back.elevation, 2.5, "elevation")
	assert_eq(back.sew_group, 3, "sew group")
	assert_true(back.flip_diagonals, "flip_diagonals")
	for i in reopened.faces.size():
		if i != TOP:
			assert_null(reopened.faces[i].displacement, "face %d stays flat" % i)


func test_a_scene_with_no_sculpt_writes_no_displacement():
	var root := _fresh_root()
	_box(root)
	_save_and_reopen(root)
	var text := FileAccess.get_file_as_string(PATH)
	assert_true(text.contains("local_verts"), "the faces are in the file")
	assert_false(
		text.contains("displacement"), "a face with no sculpt writes nothing new to the scene"
	)


func test_a_brush_duplicated_after_the_reload_has_its_own_sculpt():
	var root := _fresh_root()
	var brush := _box(root)
	_sculpt(root, brush)

	var copy := _save_and_reopen(root)
	var source := _find(copy, brush.brush_id)
	assert_not_null(source, "the brush comes back")
	if source == null or source.faces[TOP].displacement == null:
		fail_test("the reopened brush has no sculpt to share")
		return
	# Godot's own Duplicate, then the repair HammerForge runs when it sees two
	# brushes with one id.
	var twin := source.duplicate() as DraftBrush
	copy.draft_brushes_node.add_child(twin)
	copy.reconcile_external_brush_structure()
	assert_ne(twin.brush_id, source.brush_id, "the copy gets its own id")

	var mine: Resource = source.faces[TOP].displacement
	var theirs: Resource = twin.faces[TOP].displacement
	assert_not_null(theirs, "the copy has the sculpt")
	if theirs == null:
		return
	assert_ne(theirs, mine, "but not the same resource")
	assert_eq(theirs.distances, mine.distances, "with the same heights")
	theirs.set_distance(1, 1, -4.0)
	assert_eq(mine.get_distance(1, 1), 5.0, "sculpting the copy leaves the source alone")
