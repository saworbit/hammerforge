extends GutTest

const DropHandler = preload("res://addons/hammerforge/plugin_drop_handler.gd")


## Enough of the plugin for `handle_material_drop()` to run. It reads the root,
## the camera and the undo manager off the plugin, and reports through the dock,
## which is left null so the toast path is skipped.
class FakePlugin:
	extends RefCounted

	var active_root: Node = null
	var last_3d_camera: Camera3D = null
	var last_3d_mouse_pos := Vector2.ZERO
	var dock = null

	func _get_level_root() -> Node:
		return active_root

	func _get_undo_redo():
		return null

	func _record_history(_action_name: String) -> void:
		pass


func test_drop_data_classification_accepts_only_supported_payloads() -> void:
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_entity"}))
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_brush_preset"}))
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_prefab"}))
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_material"}))
	assert_false(DropHandler.can_drop_data({"type": "files"}))
	assert_false(DropHandler.can_drop_data({}))
	assert_false(DropHandler.can_drop_data(null))


func test_plugin_drop_callbacks_are_thin_delegates() -> void:
	# Godot calls `_can_drop_data` and `_drop_data` on the plugin, and those two
	# are the whole of the viewport drop path it owns. `drop_data()` dispatches to
	# the four payload kinds itself, so plugin.gd had a second layer of wrappers
	# in front of that dispatch which nothing called (#609).
	#
	# The delegation is asserted on the two entry points that exist, and the
	# absence of the classification is asserted directly. Listing the wrappers was
	# the weaker check: it passed while plugin.gd held a duplicate of the payload
	# logic, which is the thing "thin delegate" is supposed to rule out.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for method_name in ["can_drop_data", "drop_data"]:
		assert_true(
			source.contains("HFPluginDropHandler.%s" % method_name),
			"plugin.gd hands %s straight to the drop handler" % method_name
		)
	for payload in [
		"hammerforge_entity",
		"hammerforge_brush_preset",
		"hammerforge_prefab",
		"hammerforge_material",
	]:
		assert_false(
			source.contains(payload),
			"plugin.gd does not classify %s itself; the drop handler does" % payload
		)


func test_drop_handler_keeps_placement_selection_and_undo_contracts() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_drop_handler.gd")
	assert_eq(source.count("root = plugin._create_level_root()"), 3)
	assert_true(source.contains("root.place_entity_at_screen"))
	assert_true(source.contains("plugin.hf_selection.append(entity)"))
	assert_true(source.contains("plugin._commit_brush_placement(root, info)"))
	assert_true(source.contains("prefab.instantiate(root.brush_system, root.entity_system"))
	assert_true(source.contains("root.prefab_system.register_instance"))
	assert_true(source.contains('undo_redo.create_action("Place Prefab:'))
	assert_true(source.contains("root.pick_face(camera, mouse_pos)"))
	assert_true(source.contains('"assign_material_to_faces_by_id"'))
	assert_true(source.contains('Callable(plugin, "_record_history")'))


## A material dropped on a brush that has never been captured into a level state.
##
## `brush_id` is minted lazily, so a brush placed and not yet recorded has none,
## and this path used to fall back to the instance id. Nothing resolves that:
## `assign_material_to_faces_by_id()` looks brushes up by id only, so the drop
## silently did nothing, and an instance id could not have survived an undo that
## rebuilt the brush anyway. The id is minted at the drop instead (#761).
func test_dropping_a_material_on_a_brush_with_no_id_still_paints_the_face() -> void:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var brush = (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(64, 64, 64),
				"transform": Transform3D(Basis.IDENTITY, Vector3.ZERO),
			}
		)
	)
	# The lazy id, taken back off the node so the drop meets the case it guards.
	brush.brush_id = ""
	if brush.has_meta("brush_id"):
		brush.remove_meta("brush_id")

	var camera := Camera3D.new()
	add_child_autoqfree(camera)
	camera.global_position = Vector3(0, 0, 256)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	var aim := camera.unproject_position(Vector3.ZERO)

	var plugin := FakePlugin.new()
	plugin.active_root = root
	plugin.last_3d_camera = camera

	var hit: Dictionary = root.pick_face(camera, aim)
	assert_false(hit.is_empty(), "the camera has to be looking at the brush")
	var face_idx: int = int(hit.get("face_idx", -1))

	DropHandler.handle_material_drop(plugin, aim, {"type": "hammerforge_material", "index": 1})
	assert_eq(
		brush.faces[face_idx].material_idx,
		1,
		"the face under the drop takes the material, so the key the drop built resolved"
	)
	assert_ne(brush.brush_id, "", "and the brush is left with an id an undo can replay")
