extends GutTest

## The Entity panel showed a tied brush's properties (#728) and refused every
## edit to them, since the dock counts a tied brush as a brush and the edit asked
## for an entity-only selection (#1784).

const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFDockEntityHandler = preload("res://addons/hammerforge/dock_entity_handler.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")

var root: LevelRoot
var dock: Node


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	if dock.entity_defs.is_empty():
		dock._load_entity_definitions()


func after_each() -> void:
	root = null
	dock = null


func _brush(brush_id: String, x: float) -> Node:
	return root.create_brush_from_info(
		{"brush_id": brush_id, "size": Vector3(2, 3, 0.2), "center": Vector3(x, 1.5, 0)}
	)


func _speed(node: Node) -> Variant:
	return HFEntityPropUtils.get_entity_data(node).get("speed")


func test_a_door_s_speed_typed_in_the_panel_lands_as_one_undo_step():
	var door := _brush("d1", 0.0)
	root.brush_system.tie_brushes_to_entity(["d1"], "func_door", "door_1")
	dock.set_selection_nodes([door])
	assert_true(dock._entity_props_section.visible, "the panel shows the door")
	var undo = UndoStandIn.new()
	dock.undo_redo = undo
	HFDockEntityHandler.on_entity_prop_changed(dock, 7.5, door, "speed")
	assert_almost_eq(float(_speed(door)), 7.5, 0.001, "the speed is written")
	assert_eq(undo.scene_history.get_current_action_name(), "Set speed", "as its own step")
	undo.scene_history.undo()
	# The undo rebuilds the brush from its record, so ask for it again.
	assert_ne(_speed(root.find_brush_by_id("d1")), 7.5, "and undo takes it back")
	dock.undo_redo = null
	undo.free_histories()


func test_both_leaves_of_a_door_take_the_speed():
	var left := _brush("l1", 0.0)
	var right := _brush("r1", 2.0)
	root.brush_system.tie_brushes_to_entity(["l1", "r1"], "func_door", "door_2")
	dock.set_selection_nodes([left])
	HFDockEntityHandler.on_entity_prop_changed(dock, 3.0, left, "speed")
	assert_almost_eq(float(_speed(right)), 3.0, 0.001, "the other leaf too")


func test_a_door_and_a_light_selected_together_can_be_edited():
	var door := _brush("d2", 0.0)
	root.brush_system.tie_brushes_to_entity(["d2"], "func_door", "door_3")
	var light: Node = root._create_entity_from_map(
		{"classname": "light_point", "origin": Vector3(4, 2, 0)}
	)
	dock.set_selection_nodes([door, light])
	HFDockEntityHandler.on_entity_prop_changed(dock, 5.0, door, "speed")
	assert_almost_eq(float(_speed(door)), 5.0, 0.001)


func test_a_plain_brush_in_the_selection_still_refuses():
	var door := _brush("d3", 0.0)
	root.brush_system.tie_brushes_to_entity(["d3"], "func_door", "door_4")
	var plain := _brush("p1", 6.0)
	dock.set_selection_nodes([door, plain])
	HFDockEntityHandler.on_entity_prop_changed(dock, 9.0, door, "speed")
	assert_ne(_speed(door), 9.0, "refused, not filtered down to the door")


func test_add_output_wires_a_trigger_brush():
	var trigger := _brush("t1", 0.0)
	root.brush_system.tie_brushes_to_entity(["t1"], "trigger_once", "trig_1")
	dock.set_selection_nodes([trigger])
	dock.io_output_name.text = "OnStartTouch"
	dock.io_target_name.text = "door_1"
	dock.io_input_name.text = "Open"
	HFDockEntityHandler.on_io_add(dock)
	var outputs: Array = root.get_entity_outputs(trigger)
	assert_eq(outputs.size(), 1, "wired")
	if outputs.size() == 1:
		assert_eq(str(outputs[0].get("output_name", "")), "OnStartTouch")
