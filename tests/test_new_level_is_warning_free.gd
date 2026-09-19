extends GutTest

## A brand new level should not arrive with a warning already on it.
##
## The Scene dock puts a yellow triangle on any node whose configuration
## warnings are non-empty, and Godot's warning counter picks it up. One that is
## always there is worse than none: it trains the mapper to ignore the triangle,
## and it makes "the plugin enables with nothing wrong" harder to check than it
## should be (#774).
##
## `get_configuration_warnings()` is editor-only and is not callable from a
## headless run, so these assert the condition behind the warning instead.
## `MeshInstance3D` raises "requires a Mesh to render anything" exactly when its
## `mesh` is null, so a non-null mesh is the same statement from this side.


func _root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _meshless(node: Node, out: Array) -> Array:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh == null:
		out.append(String(node.name))
	for child in node.get_children():
		_meshless(child, out)
	return out


func test_the_region_overlay_is_built_with_a_mesh() -> void:
	var root := _root()
	var overlay := root.generated_region_overlay
	assert_not_null(overlay, "the overlay node is built with the rest of the level")
	if overlay == null:
		return
	assert_not_null(
		overlay.mesh,
		"a MeshInstance3D with nothing to draw yet still needs a mesh resource to be quiet"
	)


func test_an_empty_overlay_mesh_draws_nothing() -> void:
	# Silencing the warning must not put geometry in the level. An ArrayMesh with
	# no surfaces satisfies the editor and renders nothing.
	var root := _root()
	var overlay := root.generated_region_overlay
	assert_not_null(overlay, "the overlay node is built with the rest of the level")
	if overlay == null or overlay.mesh == null:
		return
	assert_eq(
		overlay.mesh.get_surface_count(),
		0,
		"the placeholder mesh is empty, so a level with no region painted shows none"
	)


func test_a_new_level_has_no_meshless_mesh_instances_anywhere() -> void:
	# The general version, so a second always-on warning cannot appear elsewhere
	# in the tree without this failing.
	var root := _root()
	assert_eq(
		_meshless(root, []), [], "nothing in a freshly built level is asking the mapper to fix it"
	)
