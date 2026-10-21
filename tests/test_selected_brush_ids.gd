extends GutTest
## Every command turns the selection into brush ids through one function, with
## one rule for a brush that has no id yet (#1455).
##
## `brush_id` is minted lazily, so a brush added to the level other than through
## HammerForge has none until something asks for it. The dock's material commands
## filed such a brush under its instance id. That found the brush once, but the
## undo step kept the instance id, and a brush rebuilt by undo has a new one, so
## the redo found nothing and the material did not come back. Selecting in the
## editor hid it only because the dock's Array section asks for the ids on every
## selection change, and that mints them.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginEditActionsScript = preload("res://addons/hammerforge/plugin_edit_actions.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


## A brush with no id, as one added other than through HammerForge arrives: made
## the usual way, then with its id taken off, the property and the meta both.
func _brush_with_no_id(level: Node, center: Vector3) -> DraftBrush:
	var brush: DraftBrush = level.create_brush_from_info(
		{"size": Vector3(4, 4, 4), "center": center}
	)
	brush.brush_id = ""
	if brush.has_meta("brush_id"):
		brush.remove_meta("brush_id")
	return brush


## Whether every face of the level's one brush uses `material_index`. Read off
## the container rather than a held node, since an undo rebuilds the brush.
func _all_faces_use(level: Node, material_index: int) -> bool:
	var brush: DraftBrush = level.draft_brushes_node.get_child(0)
	if brush.faces.is_empty():
		return false
	for face in brush.faces:
		if face.material_idx != material_index:
			return false
	return true


func test_the_dock_and_the_plugin_give_a_brush_with_no_id_the_same_id():
	assert_not_null(rig.plugin, rig.error())
	var level = await rig.make_level()
	var brush := _brush_with_no_id(level, Vector3.ZERO)
	# Onto the dock's list directly, and the dock asked first. Selecting through
	# the editor refreshes the dock's sections, and the plugin's answer writes an
	# id onto the brush, so either would hide what the dock does with a brush that
	# has none.
	rig.plugin.dock._selection_nodes = [brush]
	var from_dock: Array = rig.plugin.dock._get_selected_brush_ids()
	rig.select([brush])
	var from_plugin: Array = (
		HFPluginEditActionsScript.collect_managed_targets(rig.plugin, level)["brush_ids"]
	)
	assert_eq(from_dock, from_plugin, "one selection, one answer")
	assert_eq(from_dock.size(), 1)
	if from_dock.size() == 1:
		assert_same(
			level.find_brush_by_id(str(from_dock[0])),
			brush,
			"and an id the level finds the brush by"
		)
	await rig.leave_level(level)


func test_brush_material_on_a_brush_with_no_id_comes_back_on_redo():
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var brush := _brush_with_no_id(level, Vector3.ZERO)
	var dock = rig.plugin.dock
	dock._selection_nodes = [brush]
	dock._selected_material_index = 1
	dock._apply_material_to_whole_brush()
	assert_true(_all_faces_use(level, 1), "Apply Brush Material put it on")
	rig.undo().press_undo()
	assert_false(_all_faces_use(level, 1), "undo took it off")
	rig.undo().press_redo()
	assert_true(_all_faces_use(level, 1), "and redo puts it back")
	await rig.leave_level(level)


func test_brush_ids_of_reads_the_id_then_the_meta_then_mints_one():
	var level = await rig.make_level()
	var named = rig.box(level, "named", Vector3.ZERO)
	var meta_only := _brush_with_no_id(level, Vector3(8, 0, 0))
	meta_only.set_meta("brush_id", "kept_in_meta")
	var bare := _brush_with_no_id(level, Vector3(16, 0, 0))
	var entity = DraftEntityScript.new()
	entity.entity_type = "light_point"
	level.add_entity(entity)
	var gone := Node3D.new()
	gone.free()
	var ids: PackedStringArray = level.brush_system.brush_ids_of(
		[named, meta_only, bare, entity, rig.native_node(), gone, level]
	)
	assert_eq(ids.size(), 3, "an id for each brush, and none for anything else")
	if ids.size() == 3:
		assert_eq(ids[0], "named")
		assert_eq(ids[1], "kept_in_meta")
		assert_ne(ids[2], "", "a brush with no id is given one")
		assert_ne(ids[2], str(bare.get_instance_id()), "and not its instance id")
		assert_eq(bare.brush_id, ids[2], "written onto the brush")
		assert_eq(str(bare.get_meta("brush_id", "")), ids[2], "and its meta")
		assert_eq(
			level.get_brush_info_from_node(bare)["brush_id"], ids[2], "the id its record carries"
		)
		assert_same(level.find_brush_by_id(ids[1]), meta_only)
		assert_same(level.find_brush_by_id(ids[2]), bare)
	await rig.leave_level(level)
