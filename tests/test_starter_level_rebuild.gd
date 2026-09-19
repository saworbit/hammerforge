extends GutTest

## Building a starter level into a LevelRoot that has been through undo.
##
## Undoing Create Starter Level twice takes the contents and then the LevelRoot
## itself; redoing puts the node back and runs `create_new_level()` on it again.
## But `_ready()` does not run a second time, so the node comes back without any
## of the children `_ready()` built for it, and the rebuild ran against dangling
## references: the floor and the sun came back, because those are plain
## `get_node_or_null()`-or-create, and the player spawn did not, because it needs
## the entities container (#772).


func _root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


## What undoing the LevelRoot away and redoing it back leaves behind: the node,
## with none of the children `_ready()` gave it.
func _strip_children(root: LevelRoot) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	await get_tree().process_frame


func test_a_starter_level_has_a_player_spawn() -> void:
	var root := _root()
	root.create_new_level()
	assert_not_null(
		root.spawn_system.get_active_spawn(), "Create Starter Level makes floor, sun and spawn"
	)


func test_a_starter_level_rebuilt_after_undo_still_has_a_player_spawn() -> void:
	var root := _root()
	root.create_new_level()
	await _strip_children(root)

	root.create_new_level()

	assert_not_null(
		root.spawn_system.get_active_spawn(),
		"redo puts the spawn back too, not just the floor and the sun"
	)


func test_a_starter_level_rebuilt_after_undo_still_has_its_floor_and_sun() -> void:
	# These two already survived, and have to keep surviving.
	var root := _root()
	root.create_new_level()
	await _strip_children(root)

	root.create_new_level()

	assert_not_null(root.get_node_or_null("TempFloor"), "the floor comes back")
	assert_not_null(root.get_node_or_null("DefaultSun"), "and the sun")


func test_a_rebuilt_level_gets_its_containers_back() -> void:
	# The reason the spawn went missing: it needs somewhere to be parented.
	var root := _root()
	root.create_new_level()
	await _strip_children(root)

	root.create_new_level()

	assert_not_null(root.entities_node, "the entities container is rebuilt")
	assert_true(
		is_instance_valid(root.entities_node), "and is a live node rather than a freed reference"
	)
	assert_not_null(root.draft_brushes_node, "and so is the one brushes go in")
	assert_true(is_instance_valid(root.draft_brushes_node), "and it is live too")
