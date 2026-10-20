extends GutTest
## What the plugin stand-in gives the real plugin that otherwise only the editor
## gives it (#1296).
##
## The dock finds its level through the tree's edited scene root, which the
## editor sets for the scene in front and nothing sets headless. So the stand-in
## sets it to the scene the test hands it, and clears it when the plugin goes,
## before the test frees that scene. And the fake selection lets go of a node
## that was freed while selected, as the editor's does.

const PluginStandIn = preload("res://tests/support/plugin_stand_in.gd")
const EditorPluginStandIn = preload("res://tests/support/editor_plugin_stand_in.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")

var scene_root: Node3D
var plugin: Node


func after_each():
	PluginStandIn.teardown(plugin)
	plugin = null
	if scene_root and is_instance_valid(scene_root):
		remove_child(scene_root)
		scene_root.free()
	scene_root = null
	await get_tree().process_frame
	await get_tree().process_frame


func _bring_up() -> void:
	scene_root = Node3D.new()
	scene_root.name = "EditedScene"
	add_child(scene_root)
	plugin = PluginStandIn.build(self, scene_root)
	await get_tree().process_frame


func _level() -> Node:
	var root = LevelRootScript.new()
	root.name = "LevelRoot"
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	scene_root.add_child(root)
	root.owner = scene_root
	return root


func test_the_dock_adopts_a_level_in_the_edited_scene_on_its_next_frame():
	# Every action routed through the dock, Quick Play, the bakes and Create
	# Structure among them, used to find no level and do nothing.
	await _bring_up()
	assert_not_null(plugin, PluginStandIn.error())
	assert_eq(get_tree().edited_scene_root, scene_root, "the test's scene is the one in front")
	assert_null(plugin.dock.level_root, "no level yet")
	var root = _level()
	await get_tree().process_frame
	assert_eq(plugin.dock.level_root, root, "the dock found it the way it does in the editor")
	var brushes: int = root.draft_brushes_node.get_child_count()
	plugin._dispatch_viewport_action("create_arch", [])
	await get_tree().process_frame
	assert_gt(root.draft_brushes_node.get_child_count(), brushes, "Create Structure reached it")


func test_the_edited_scene_root_is_cleared_when_the_plugin_goes():
	# The tree keeps a bare pointer; a scene freed while still registered would
	# be read by the next dock built in the run.
	await _bring_up()
	assert_not_null(plugin, PluginStandIn.error())
	PluginStandIn.teardown(plugin)
	plugin = null
	assert_null(get_tree().edited_scene_root)


func test_the_selection_lets_go_of_a_node_freed_while_selected():
	# Selected out of the tree, the node never says it is leaving, so the
	# selection still held it when it was freed. The clear stopped on the first
	# such node, with the rest still selected, and every later clear did too.
	var selection = EditorPluginStandIn.FakeSelection.new()
	var gone := Node.new()
	var kept := Node.new()
	add_child(kept)
	selection.add_node(gone)
	selection.add_node(kept)
	gone.free()
	var errors_before := get_errors().size()
	selection.clear()
	assert_eq(get_errors().size(), errors_before, "the clear raised nothing")
	assert_eq(selection._nodes, [], "and let go of both")
	selection.add_node(kept)
	assert_eq(selection.get_selected_nodes(), [kept], "so the next selection takes")
	selection.clear()
	remove_child(kept)
	kept.free()
