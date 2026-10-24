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


## A scene that keeps only its bake loads the `.hflevel` instead (#645).
func test_a_bake_only_scene_carries_no_paint():
	var root := _fresh_root()
	_layer(root, 0).set_cell(Vector2i(1, 1), true)
	root.scene_contents = root.SceneContents.BAKE_ONLY
	assert_eq(root.live_registries, {}, "nothing beside the bake")
