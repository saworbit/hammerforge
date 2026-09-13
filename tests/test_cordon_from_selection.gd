extends GutTest

## What Set Cordon from Selection leaves behind.
##
## The button puts an AABB on the level and then copies the six numbers into the
## cordon spins. Each assignment clamps to the control's range and fires
## `value_changed`, which reads all six spins straight back onto the level - so
## without a guard the cordon the selection produced is replaced by whatever the
## spins could hold, and the cordon is what decides which geometry gets baked.

const DockScene = preload("res://addons/hammerforge/dock.tscn")


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _dock(root: LevelRoot) -> Node:
	var dock := DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	return dock


func _room_at(root: LevelRoot, centre: Vector3, brush_id: String) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": LevelRoot.BrushShape.BOX,
				"size": Vector3(256, 256, 256),
				"center": centre,
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": brush_id,
			}
		)
	)


func test_the_cordon_contains_the_selection_it_was_set_from() -> void:
	var root := _fresh_root()
	var dock := _dock(root)
	# Quake-family maps run well past 4096 per axis, and the structure builders'
	# own schemas take a width or radius up to 4096 for one piece of geometry, so
	# this is a level rather than a stress test.
	var far := Vector3(12000, 0, 0)
	var brush := _room_at(root, far, "cordon_far_room")
	dock._selection_nodes = [brush]

	dock._on_cordon_from_selection()
	var cordon: AABB = root.cordon_aabb
	assert_true(
		cordon.has_point(far),
		"the cordon must contain the brush it was set from, not a slab at the spin limit"
	)
	assert_gt(cordon.size.x, 0.0, "and it must not be zero width")


func test_the_spins_and_the_level_agree_after_the_button() -> void:
	var root := _fresh_root()
	var dock := _dock(root)
	var brush := _room_at(root, Vector3(12000, 0, 0), "cordon_agree_room")
	dock._selection_nodes = [brush]

	dock._on_cordon_from_selection()
	var cordon: AABB = root.cordon_aabb
	assert_almost_eq(dock.cordon_min_x.value, cordon.position.x, 0.01, "min x")
	assert_almost_eq(dock.cordon_max_x.value, cordon.end.x, 0.01, "max x")
	assert_almost_eq(dock.cordon_min_y.value, cordon.position.y, 0.01, "min y")
	assert_almost_eq(dock.cordon_max_z.value, cordon.end.z, 0.01, "max z")


func test_the_spin_range_covers_the_coordinates_a_level_holds() -> void:
	var root := _fresh_root()
	var dock := _dock(root)
	assert_gte(
		dock.cordon_max_x.max_value,
		HFDockVisgroupHandler.CORDON_LIMIT,
		"the control has to be able to show a room a level can contain"
	)
	assert_gt(
		dock.cordon_max_x.max_value,
		4096.0,
		"one structure builder piece can be 4096 across on its own"
	)


func test_the_button_leaves_a_cordon_that_bakes_something() -> void:
	var root := _fresh_root()
	var dock := _dock(root)
	var brush := _room_at(root, Vector3(12000, 0, 0), "cordon_bake_room")
	dock._selection_nodes = [brush]

	dock._on_cordon_from_selection()
	assert_true(root.cordon_enabled, "the button turns the cordon on, which is the point of it")
	# Which makes the cordon being right the difference between baking the room
	# and baking nothing at all.
	assert_true(
		root.cordon_aabb.intersects(AABB(Vector3(12000 - 128, -128, -128), Vector3.ONE * 256)),
		"the enabled cordon overlaps the geometry it was built from"
	)
