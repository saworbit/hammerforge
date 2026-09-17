extends GutTest

## What Godot's own Ctrl+S keeps of a level, beyond the brushes (#664, #665).
##
## `PackedScene.pack()` writes nodes. Visgroups, groups, arrays, hollows,
## generators and prefab instances are not nodes -- they live on `RefCounted`
## subsystems -- so the scene used to come back as loose geometry with nothing
## that could still edit it, and a visgroup hidden at save time came back with
## its brushes invisible and no entry in the dock to show them.
##
## These pack a real `LevelRoot` and open the copy, because that is the path the
## `.hflevel` tests do not take and the one the defect lived on.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const GeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	# `_get_editor_owner()` reads `edited_scene_root`, which is null headless, and
	# falls back to `get_owner()`. Without one, `pack()` writes an empty scene and
	# every assertion below passes for the wrong reason.
	root.owner = self
	return root


func _box(root: LevelRoot, at := Vector3.ZERO, size := Vector3(2, 2, 2)) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


## The owners the editor assigns as it goes. Headless there is no edited scene,
## so anything created before `root.owner` was set has none.
func _own(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


func _reopen(root: LevelRoot) -> LevelRoot:
	_own(root)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	var copy := packed.instantiate() as LevelRoot
	add_child_autoqfree(copy)
	return copy


# ===========================================================================
# The registries
# ===========================================================================


func test_a_hollow_record_survives_the_scene_save():
	var root := _fresh_root()
	var solid := _box(root, Vector3.ZERO, Vector3(8, 3, 8))
	root.hollow_brush_by_id(solid.brush_id, 0.25)
	var before: int = root.state_system.capture_registries()["hollows"].size()
	assert_eq(before, 1, "the level has a hollow to lose")

	var copy := _reopen(root)
	assert_eq(
		copy.state_system.capture_registries()["hollows"].size(),
		before,
		"the record that lets update_hollow() re-shell the walls comes back with them"
	)


func test_a_generator_record_survives_the_scene_save():
	var root := _fresh_root()
	var settings: Dictionary = GeneratorSystemScript.default_settings("stairs")
	settings["steps"] = 4
	assert_true(
		root.create_generator("stairs", settings, Transform3D.IDENTITY).ok, "the stairs are built"
	)
	assert_eq(root.generator_count(), 1, "the level has a generator to lose")

	var copy := _reopen(root)
	assert_eq(
		copy.generator_count(), 1, "the structure is still editable after the scene is reopened"
	)


func test_a_visgroup_survives_the_scene_save_with_its_visibility():
	var root := _fresh_root()
	var brush := _box(root)
	root.create_visgroup("detail")
	root.add_selection_to_visgroup("detail", [brush])
	root.set_visgroup_visible("detail", false)

	var copy := _reopen(root)
	assert_has(
		Array(copy.get_visgroup_names()),
		"detail",
		"the visgroup the brushes belong to is in the list"
	)
	assert_false(
		copy.visgroup_system.is_visgroup_visible("detail"),
		"and it is still hidden, which is why it is reachable"
	)


# ===========================================================================
# The repair pass, for scenes saved before any of the above existed
# ===========================================================================


func test_a_visgroup_is_recovered_from_the_members_that_still_name_it():
	var root := _fresh_root()
	var brush := _box(root)
	root.create_visgroup("detail")
	root.add_selection_to_visgroup("detail", [brush])
	# What an older scene is: the membership meta on the node, and no registry.
	root.visgroup_system.visgroups.clear()
	assert_eq(root.get_visgroup_names().size(), 0, "the list is gone the way an old scene lost it")

	assert_eq(root.visgroup_system.reconcile_visgroups_from_members(), 1, "one visgroup recovered")
	assert_has(
		Array(root.get_visgroup_names()),
		"detail",
		"the brush that claims 'detail' puts 'detail' back in the dock"
	)
	assert_true(
		root.visgroup_system.is_visgroup_visible("detail"),
		(
			"a recovered visgroup is visible: the flag cannot be recovered and this is the direction"
			+ " that does not leave geometry the mapper cannot reach"
		)
	)


# ===========================================================================
# Paint
# ===========================================================================


func test_paint_layers_come_back_once_rather_than_twice():
	var root := _fresh_root()
	root.paint_layers.create_layer(&"second", 1.0)
	var before: Array = root.get_paint_layer_names()
	assert_eq(before.size(), 2, "the level has two paint layers")

	var copy := _reopen(root)
	assert_eq(
		copy.get_paint_layer_names().size(),
		2,
		"the index is rebuilt from the layer nodes rather than a third layer_0 added on top"
	)


func test_a_painted_face_comes_back_painted():
	var root := _fresh_root()
	var brush := _box(root)
	var face: FaceData = brush.get("faces")[0]
	var layer := FaceData.PaintLayer.new()
	layer.opacity = 0.42
	layer.ensure_weight_image(Vector2i(8, 8))
	face.paint_layers.append(layer)

	var copy := _reopen(root)
	var reopened_face: FaceData = null
	for child in copy.draft_brushes_node.get_children():
		if copy.is_brush_node(child):
			reopened_face = child.get("faces")[0]
			break
	assert_not_null(reopened_face, "the brush came back")
	assert_eq(
		reopened_face.paint_layers.size(),
		1,
		"a face paint layer is a Resource with a type the scene can name, so it loads back"
	)
	assert_almost_eq(reopened_face.paint_layers[0].opacity, 0.42, 0.0001, "with its settings")
