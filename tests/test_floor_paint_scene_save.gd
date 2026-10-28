extends GutTest

## Floor paint saved with the scene (#1854).
##
## A paint layer is a node and the scene writes it (#665), but its cells, its
## heightmap, its terrain slots and its wall heights are plain vars, so a level
## reopened from its `.tscn` had every layer and no paint on any of them. They
## travel in `LevelRoot.live_registries` now, the capture the `.hflevel` writes.
##
## These write the scene to disk and load it with the cache ignored, as Ctrl+S
## and a reopen do.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const PATH := "user://test_floor_paint_scene_save.tscn"
## The `.hflevel` a streamed level saves its regions beside.
const LEVEL := "user://test_floor_paint_scene_save_streamed.hflevel"
## Region (0, 0) and region (2, 2) at 64 cells a region: far enough apart that
## only one is loaded at a time.
const NEAR := Vector2i(1, 1)
const FAR := Vector2i(150, 150)


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var dir := ProjectSettings.globalize_path(LEVEL.get_basename() + ".hfregions")
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))
		DirAccess.remove_absolute(dir)
	var level_file := ProjectSettings.globalize_path(LEVEL)
	for path in [level_file, level_file + ".previous"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


## The owners the editor assigns. Headless there is no edited scene, so without
## them `pack()` writes an empty scene.
func _own(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


func _save_and_reopen(root: LevelRoot) -> LevelRoot:
	_own(root)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	assert_eq(ResourceSaver.save(packed, PATH), OK, "the scene saves")
	var loaded := (
		ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var copy := loaded.instantiate() as LevelRoot
	copy.hflevel_autosave_enabled = false
	add_child_autoqfree(copy)
	return copy


func _layer(root: LevelRoot, index: int) -> HFPaintLayer:
	return root.paint_layers.layers[index] if index < root.paint_layers.layers.size() else null


func test_painted_cells_come_back_from_the_saved_scene():
	var root := _fresh_root()
	var first := _layer(root, 0)
	first.set_cell(Vector2i(2, 3), true)
	first.set_cell(Vector2i(40, -7), true)
	first.set_cell_material(Vector2i(2, 3), 2)
	first.set_wall_height(Vector2i(2, 3), 4.5)

	var copy := _save_and_reopen(root)
	var reopened := _layer(copy, 0)
	assert_not_null(reopened, "the layer comes back")
	if reopened == null:
		return
	assert_eq(reopened.filled_cell_count(), 2, "with both painted cells")
	assert_true(reopened.get_cell(Vector2i(40, -7)), "in the chunk far from the first")
	assert_eq(reopened.get_cell_material(Vector2i(2, 3)), 2, "and the material painted on one")
	assert_almost_eq(reopened.get_wall_height(Vector2i(2, 3), 0.0), 4.5, 0.001, "and its wall")


func test_a_second_layer_keeps_its_settings_and_stays_active():
	var root := _fresh_root()
	var second: HFPaintLayer = root.paint_layers.create_layer(&"upper", 3.0)
	second.display_name = "Upper floor"
	second.set_cell(Vector2i(0, 0), true)
	second.set_terrain_slot_uv_scale(1, 2.5)
	var heights := Image.create(4, 4, false, Image.FORMAT_RF)
	heights.set_pixel(1, 1, Color(0.5, 0, 0))
	second.heightmap = heights
	second.height_scale = 6.0
	root.set_active_paint_layer(1)

	var copy := _save_and_reopen(root)
	assert_eq(copy.paint_layers.layers.size(), 2, "two layers, not three")
	assert_eq(copy.paint_layers.active_layer_index, 1, "the layer in use is still the one in use")
	var reopened := _layer(copy, 1)
	if reopened == null:
		return
	assert_eq(reopened.display_name, "Upper floor", "its name")
	assert_eq(reopened.filled_cell_count(), 1, "its cell")
	assert_almost_eq(reopened.get_terrain_slot_uv_scales()[1], 2.5, 0.001, "its terrain slot")
	assert_true(reopened.has_heightmap(), "its heightmap")
	assert_almost_eq(reopened.get_height_at(Vector2i(1, 1)), 3.0, 0.01, "at its height scale")


## A layer's Height Scale is its own before it has a heightmap. It was written
## only beside one, so a value set first went back to 10 at the next undo or
## reopen, and the heightmap imported afterwards took 10 (#2030).
func test_a_height_scale_set_before_a_heightmap_is_kept():
	var root := _fresh_root()
	root.set_heightmap_scale(3.0)
	assert_false(_layer(root, 0).has_heightmap(), "fixture: no heightmap")
	var before: Dictionary = root.capture_undo_state()
	_layer(root, 0).set_cell(Vector2i(1, 1), true)
	root.restore_state(before)
	assert_almost_eq(_layer(root, 0).height_scale, 3.0, 0.0001, "through an undo")

	var copy := _save_and_reopen(root)
	assert_almost_eq(_layer(copy, 0).height_scale, 3.0, 0.0001, "through the scene")

	assert_eq(root.save_hflevel(LEVEL, true), OK, "the level saves")
	await _drain_save(root)
	var loaded := _fresh_root()
	assert_true(loaded.load_hflevel(LEVEL), "the level loads")
	assert_almost_eq(_layer(loaded, 0).height_scale, 3.0, 0.0001, "through the .hflevel")


## A scene saved before this carries no floor paint, and opening it must not
## clear what it does hold: the layer nodes, and the floor built from them.
func test_a_scene_from_before_keeps_its_layers_and_its_floor():
	var root := _fresh_root()
	root.paint_layers.create_layer(&"second", 1.0)
	_layer(root, 0).set_cell(Vector2i(1, 1), true)
	root.paint_system.regenerate_paint_layers()
	assert_gt(root.generated_floors.get_child_count(), 0, "fixture: the cell built a floor")
	_own(root)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	# The scene as a build from before wrote it: the same, less the floor paint.
	var bundled: Dictionary = packed.get("_bundled")
	var taken := 0
	for value in bundled["variants"]:
		if value is Dictionary and (value as Dictionary).erase("floor_paint"):
			taken += 1
	assert_eq(taken, 1, "fixture: the scene carried the paint")
	packed.set("_bundled", bundled)

	var copy := packed.instantiate() as LevelRoot
	add_child_autoqfree(copy)
	assert_eq(copy.paint_layers.layers.size(), 2, "both layer nodes it holds")
	assert_gt(copy.generated_floors.get_child_count(), 0, "and the floor built before the save")


## A streamed level keeps its cells in its region files. The scene carries the
## index of them, as the `.hflevel` does, and not the cells.
func test_a_streamed_level_carries_its_region_index_rather_than_its_cells():
	var root := _fresh_root()
	_layer(root, 0).set_cell(Vector2i(1, 1), true)
	root.paint_system.region_streaming_enabled = true
	var paint: Dictionary = root.live_registries.get("floor_paint", {})
	assert_true(paint.has("terrain_regions"), "the region index")
	for entry in paint.get("paint_layers", []):
		assert_eq((entry["chunks"] as Array).size(), 0, "and no cells")


## A streamed level painted near and far and saved, with FAR's region streamed
## out, so its paint is in its file and nowhere else.
func _streamed_and_saved() -> LevelRoot:
	var root := _fresh_root()
	root.hflevel_compress = false
	var sys := root.paint_system
	sys.region_streaming_enabled = true
	sys.set_region_size_cells(64)
	sys.region_manager.streaming_radius = 0
	sys._sync_region_manager()
	sys.set_region_base_path(LEVEL)
	for at in [NEAR, FAR]:
		_layer(root, 0).set_cell(at, true)
		sys.region_manager.mark_loaded(sys.region_manager.region_id_from_cell(at))
	assert_true(sys._unload_region(sys.region_manager.region_id_from_cell(FAR)), "FAR streams out")
	assert_eq(root.save_hflevel(LEVEL, true), OK, "the level saves")
	await _drain_save(root)
	return root


func _drain_save(level: LevelRoot) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return


func _far_file(root: LevelRoot) -> String:
	var region: Vector2i = root.paint_system.region_manager.region_id_from_cell(FAR)
	var dir := ProjectSettings.globalize_path(LEVEL.get_basename() + ".hfregions")
	return dir.path_join("region_%d_%d.hfr" % [region.x, region.y])


## The scene knows the level file its region files sit beside, so a reopened
## scene streams its paint back in. It had no folder and streamed in nothing
## (#2006).
func test_a_reopened_streamed_scene_streams_its_paint_back_in():
	var root := await _streamed_and_saved()
	var copy := _save_and_reopen(root)
	var sys := copy.paint_system
	assert_eq(
		sys.region_manager.region_base_path,
		root.paint_system.region_manager.region_base_path,
		"the reopened scene finds the region folder"
	)
	assert_true(_layer(copy, 0).get_cell(NEAR), "the near paint is there")
	sys._ensure_regions_for_cell(FAR)
	assert_true(_layer(copy, 0).get_cell(FAR), "and the far region streams back in")
	var index: Dictionary = sys.capture_region_index()
	assert_eq((index["regions"] as Array).size(), 2, "the index still names both regions")


## The save after a reopen wrote over the level's own region folder with nothing
## and cleared it (#2006).
func test_a_save_after_reopening_keeps_the_region_files():
	var root := await _streamed_and_saved()
	var copy := _save_and_reopen(root)
	assert_eq(copy.save_hflevel(LEVEL, true), OK, "the reopened level saves")
	await _drain_save(copy)
	assert_true(FileAccess.file_exists(_far_file(copy)), "FAR's region file is still there")
	var loaded := _fresh_root()
	assert_true(loaded.load_hflevel(LEVEL), "the level loads")
	loaded.paint_system._ensure_regions_for_cell(FAR)
	assert_true(_layer(loaded, 0).get_cell(FAR), "with its far paint")


## A level that names regions it has not loaded, and has lost the folder they are
## in, as a scene from before #2006 reopens, refuses the save rather than
## clearing the folder it was given.
func test_a_level_that_lost_its_region_folder_refuses_to_clear_one():
	var root := await _streamed_and_saved()
	root.paint_system.region_manager.region_base_path = ""
	assert_eq(
		root.paint_system.carry_region_files_to(LEVEL), ERR_FILE_NOT_FOUND, "the carry refuses"
	)
	assert_true(FileAccess.file_exists(_far_file(root)), "FAR's region file is still there")


## A scene that keeps only its bake loads the `.hflevel` instead (#645).
func test_a_bake_only_scene_carries_no_paint():
	var root := _fresh_root()
	_layer(root, 0).set_cell(Vector2i(1, 1), true)
	root.scene_contents = root.SceneContents.BAKE_ONLY
	assert_eq(root.live_registries, {}, "nothing beside the bake")
