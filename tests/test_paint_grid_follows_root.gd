extends GutTest

## #442. Every paint layer holds its own copy of the grid, and the level's
## origin was only ever written into the template. A layer left on the old
## origin puts its floor, its connectors and anything scattered on it at a
## world position the brush geometry no longer uses.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func test_moving_the_root_moves_every_layer_grid():
	root.paint_layers.create_layer(&"upper", 32.0)
	root.paint_layers.create_layer(&"roof", 64.0)
	root.global_position = Vector3(1024, 0, 1024)
	root._sync_paint_grid_from_root()
	assert_eq(root.paint_layers.base_grid.origin, Vector3(1024, 0, 1024))
	for layer in root.paint_layers.layers:
		assert_eq(layer.grid.origin, Vector3(1024, 0, 1024), "Layer grid follows the root")


func test_every_layer_grid_agrees_with_the_one_created_after_a_move():
	root.paint_layers.create_layer(&"upper", 32.0)
	root.global_position = Vector3(512, 0, 0)
	root._sync_paint_grid_from_root()
	var late = root.paint_layers.create_layer(&"roof", 64.0)
	var origins := {}
	for layer in root.paint_layers.layers:
		origins[layer.grid.origin] = true
	assert_eq(origins.size(), 1, "One level, one grid origin")
	assert_eq(late.grid.origin, root.paint_layers.base_grid.origin)


func test_each_layer_keeps_its_own_height():
	root.paint_layers.create_layer(&"upper", 32.0)
	root.paint_layers.create_layer(&"roof", 64.0)
	root.global_position = Vector3(1024, 0, 1024)
	root._sync_paint_grid_from_root()
	var heights: Array = []
	for layer in root.paint_layers.layers:
		heights.append(layer.grid.layer_y)
	assert_true(32.0 in heights, "layer_y is the layer's own")
	assert_true(64.0 in heights, "layer_y is the layer's own")


func test_grid_snap_still_reaches_every_layer():
	root.paint_layers.create_layer(&"upper", 32.0)
	root.grid_snap = 8.0
	for layer in root.paint_layers.layers:
		assert_eq(layer.grid.cell_size, 8.0, "Cell size follows the snap")
