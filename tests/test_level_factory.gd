extends GutTest
## Tests for HFLevelFactory, the dockless entry point for making a LevelRoot
## and for building the starter level the dock's empty-state banner builds.

# A fresh root outside the editor would otherwise bake and spawn a player the
# moment it enters the tree.
const HEADLESS := {"auto_spawn_player": false, "hflevel_autosave_enabled": false}

var parent: Node3D


func before_each():
	parent = Node3D.new()
	parent.name = "SceneRoot"
	add_child_autoqfree(parent)


func after_each():
	parent = null


# ===========================================================================
# make_level_root
# ===========================================================================


func test_make_level_root_returns_named_detached_node():
	var root: LevelRoot = HFLevelFactory.make_level_root()
	assert_not_null(root, "make_level_root should return a node")
	assert_eq(root.name, StringName("LevelRoot"), "Node should be named LevelRoot")
	assert_false(root.is_inside_tree(), "Node should not be parented yet")
	root.free()


# ===========================================================================
# create_level_root
# ===========================================================================


func test_create_level_root_parents_under_the_given_node():
	var root: LevelRoot = HFLevelFactory.create_level_root(parent, null, HEADLESS)
	assert_not_null(root, "Factory should return a root")
	assert_eq(root.get_parent(), parent, "Root should be a child of parent")
	assert_eq(root.name, StringName("LevelRoot"), "Root should be named LevelRoot")


func test_create_level_root_owns_to_parent_when_parent_has_no_owner():
	var root: LevelRoot = HFLevelFactory.create_level_root(parent, null, HEADLESS)
	assert_eq(root.owner, parent, "Owner should fall back to parent")


func test_create_level_root_inherits_the_parents_owner():
	var middle := Node3D.new()
	parent.add_child(middle)
	middle.owner = parent
	var root: LevelRoot = HFLevelFactory.create_level_root(middle, null, HEADLESS)
	assert_eq(root.owner, parent, "Owner should be the parent's own owner")


func test_create_level_root_honours_an_explicit_owner():
	var middle := Node3D.new()
	parent.add_child(middle)
	middle.owner = parent
	var root: LevelRoot = HFLevelFactory.create_level_root(middle, middle, HEADLESS)
	assert_eq(root.owner, middle, "Explicit scene_owner should win")


func test_create_level_root_applies_properties():
	var root: LevelRoot = HFLevelFactory.create_level_root(parent, null, HEADLESS)
	assert_false(root.auto_spawn_player, "Property should be set on the node")
	assert_false(root.hflevel_autosave_enabled, "Property should be set on the node")


func test_create_level_root_ignores_an_unknown_property():
	var props := HEADLESS.duplicate()
	props["no_such_property"] = 1
	var root: LevelRoot = HFLevelFactory.create_level_root(parent, null, props)
	assert_not_null(root, "An unknown property should not stop creation")
	assert_false(root.auto_spawn_player, "Known properties should still be applied")
	assert_push_error("no_such_property", "The typo should be reported, not swallowed")


func test_create_level_root_rejects_a_null_parent():
	assert_null(HFLevelFactory.create_level_root(null), "Null parent should return null")
	assert_push_error("parent is null")


func test_create_level_root_rejects_a_parent_outside_the_tree():
	var detached := Node3D.new()
	assert_null(
		HFLevelFactory.create_level_root(detached, null, HEADLESS),
		"A parent outside the tree should return null"
	)
	assert_push_error("inside the scene tree")
	detached.free()


# ===========================================================================
# create_starter
# ===========================================================================


func test_create_starter_builds_floor_sun_and_spawn():
	var root: LevelRoot = HFLevelFactory.create_starter(parent, null, HEADLESS)
	assert_not_null(root, "Factory should return a root")

	var floor_node := root.get_node_or_null("TempFloor")
	assert_not_null(floor_node, "Starter level should have a floor")
	assert_true(floor_node is CSGBox3D, "Floor should be a CSGBox3D")

	var sun := root.get_node_or_null("DefaultSun")
	assert_not_null(sun, "Starter level should have a sun light")
	assert_true(sun is DirectionalLight3D, "Sun should be a DirectionalLight3D")

	if root.spawn_system:
		assert_not_null(root.spawn_system.get_active_spawn(), "Starter level should have a spawn")


func test_create_starter_owns_its_children_so_the_scene_can_be_saved():
	var root: LevelRoot = HFLevelFactory.create_starter(parent, null, HEADLESS)
	var floor_node := root.get_node_or_null("TempFloor")
	var sun := root.get_node_or_null("DefaultSun")
	assert_eq(floor_node.owner, parent, "Floor should be owned by the scene root")
	assert_eq(sun.owner, parent, "Sun should be owned by the scene root")


func test_create_starter_is_repeatable_on_the_same_root():
	var root: LevelRoot = HFLevelFactory.create_starter(parent, null, HEADLESS)
	var before := root.get_child_count()
	root.create_new_level()
	assert_eq(root.get_child_count(), before, "A second call should not duplicate the fixtures")


func test_create_starter_rejects_a_null_parent():
	assert_null(HFLevelFactory.create_starter(null), "Null parent should return null")
	assert_push_error("parent is null")
