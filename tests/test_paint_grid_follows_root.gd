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


func test_grid_snap_still_reaches_every_layer_with_no_paint():
	root.paint_layers.create_layer(&"upper", 32.0)
	root.grid_snap = 8.0
	for layer in root.paint_layers.layers:
		assert_eq(layer.grid.cell_size, 8.0, "An empty layer's cell size follows the snap")
	assert_eq(root.paint_layers.base_grid.cell_size, 8.0, "and so does a new layer's")


# ---------------------------------------------------------------------------
# A painted layer keeps its cell size (#2011)
# ---------------------------------------------------------------------------

const LEVEL := "user://hf_test_paint_cell_size.hflevel"


func after_each():
	if FileAccess.file_exists(LEVEL):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEVEL))


## The box the generated floors of layer_0 cover, counting those whose centre is
## short of `below_x` on X.
func _floor_bounds(level: LevelRoot, below_x: float = INF) -> AABB:
	var out := AABB()
	var first := true
	for child in level.paint_tool.reconciler.floors_root.get_children():
		if str(child.get_meta("hf_layer", "")) != "layer_0":
			continue
		if child.global_position.x >= below_x:
			continue
		var size: Vector3 = child.size
		var box := AABB(child.global_position - size * 0.5, size)
		out = box if first else out.merge(box)
		first = false
	return out


func _assert_room_is_4_by_4(level: LevelRoot, why: String) -> void:
	var room := _floor_bounds(level, 3.5)
	assert_almost_eq(room.size.x, 4.0, 0.001, why)
	assert_almost_eq(room.size.z, 4.0, 0.001, why)


func _finish_saving(level: LevelRoot) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return


func test_a_snap_change_leaves_a_painted_floor_its_size():
	# An 8 x 8 cell room at the starting snap of 0.5 is a 4 x 4 floor. The snap
	# was written into every layer's cell size, and cells are kept by index, so
	# the next build of that chunk laid the same room 1 x 1 at 0.125.
	assert_eq(root.grid_snap, 0.5)
	root.paint_system.paint_cells(0, Vector2i(0, 0), Vector2i(7, 7), true)
	_assert_room_is_4_by_4(root, "as laid")
	root.grid_snap = 0.125
	assert_eq(root.paint_layers.layers[0].grid.cell_size, 0.5, "the layer keeps its size")
	root.paint_system.paint_cells(0, Vector2i(31, 31), Vector2i(31, 31), true)
	_assert_room_is_4_by_4(root, "after one more cell in its chunk")
	root.restore_state(root.capture_undo_state())
	_assert_room_is_4_by_4(root, "after an undo, which builds every layer again")
	root.add_paint_layer()
	assert_eq(root.paint_layers.layers[1].grid.cell_size, 0.125, "a new layer takes the snap")


func test_a_saved_level_opens_with_its_floors_at_their_size_and_keeps_it():
	root.paint_system.paint_cells(0, Vector2i(0, 0), Vector2i(7, 7), true)
	assert_eq(root.save_hflevel(LEVEL, true), OK)
	await _finish_saving(root)
	var other: LevelRoot = LevelRootType.new()
	other.auto_spawn_player = false
	other.hflevel_autosave_enabled = false
	add_child_autoqfree(other)
	other.grid_snap = 2.0
	assert_true(other.load_hflevel(LEVEL))
	_assert_room_is_4_by_4(other, "as it opens")
	other.grid_snap = 0.125
	other.paint_system.paint_cells(0, Vector2i(31, 31), Vector2i(31, 31), true)
	_assert_room_is_4_by_4(other, "after a snap change and one more cell")
