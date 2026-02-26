extends GutTest

const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")

var root: Node3D
var sys: HFEntitySystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child(root)
	var entities = Node3D.new()
	entities.name = "Entities"
	root.add_child(entities)
	root.entities_node = entities
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	root.entity_definitions = {}
	root.entity_definitions_path = ""
	sys = HFEntitySystem.new(root)


func after_each():
	root.queue_free()
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var entities_node: Node3D
var draft_brushes_node: Node3D
var entity_definitions: Dictionary = {}
var entity_definitions_path: String = ""

func _assign_owner(node: Node) -> void:
	pass
"""
	s.reload()
	return s


func _make_entity(entity_name: String = "TestEntity") -> Node3D:
	var e = Node3D.new()
	e.name = entity_name
	e.set_meta("is_entity", true)
	root.entities_node.add_child(e)
	return e


# ===========================================================================
# Add / Get outputs
# ===========================================================================


func test_add_output_creates_connection():
	var e = _make_entity("light_1")
	sys.add_entity_output(e, "OnTrigger", "door_1", "Open")
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs.size(), 1, "Should have 1 output")
	assert_eq(outputs[0]["output_name"], "OnTrigger")
	assert_eq(outputs[0]["target_name"], "door_1")
	assert_eq(outputs[0]["input_name"], "Open")


func test_add_output_with_parameters():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnPress", "relay_1", "Trigger", "some_param", 1.5, true)
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs.size(), 1)
	assert_eq(outputs[0]["parameter"], "some_param")
	assert_almost_eq(outputs[0]["delay"], 1.5, 0.001)
	assert_true(outputs[0]["fire_once"])


func test_add_multiple_outputs():
	var e = _make_entity("button_1")
	sys.add_entity_output(e, "OnPressed", "door_1", "Open")
	sys.add_entity_output(e, "OnPressed", "light_1", "TurnOn")
	sys.add_entity_output(e, "OnReset", "door_1", "Close")
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs.size(), 3, "Should have 3 outputs")


func test_get_outputs_empty_by_default():
	var e = _make_entity("entity_1")
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs.size(), 0, "New entity should have no outputs")


func test_get_outputs_null_entity():
	var outputs = sys.get_entity_outputs(null)
	assert_eq(outputs.size(), 0, "Null entity should return empty array")


func test_add_output_null_entity_noop():
	# Should not crash
	sys.add_entity_output(null, "OnTrigger", "target", "Input")
	assert_true(true, "Adding output to null entity should not crash")


# ===========================================================================
# Remove outputs
# ===========================================================================


func test_remove_output_by_index():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnPress", "door_1", "Open")
	sys.add_entity_output(e, "OnPress", "light_1", "TurnOn")
	sys.remove_entity_output(e, 0)
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs.size(), 1, "Should have 1 output after removal")
	assert_eq(outputs[0]["target_name"], "light_1", "Remaining output should be the second one")


func test_remove_output_invalid_index_noop():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnPress", "door_1", "Open")
	sys.remove_entity_output(e, 5)  # Out of bounds
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs.size(), 1, "Invalid index should not remove anything")


func test_remove_output_negative_index_noop():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnPress", "door_1", "Open")
	sys.remove_entity_output(e, -1)
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs.size(), 1, "Negative index should not remove anything")


func test_remove_output_null_entity_noop():
	# Should not crash
	sys.remove_entity_output(null, 0)
	assert_true(true, "Removing output from null entity should not crash")


func test_remove_all_outputs():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnPress", "door_1", "Open")
	sys.add_entity_output(e, "OnReset", "door_1", "Close")
	sys.remove_entity_output(e, 1)
	sys.remove_entity_output(e, 0)
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs.size(), 0, "All outputs should be removed")


# ===========================================================================
# Find entities by name
# ===========================================================================


func test_find_entities_by_name():
	var e1 = _make_entity("door_1")
	var e2 = _make_entity("light_1")
	var found = sys.find_entities_by_name("door_1")
	assert_eq(found.size(), 1, "Should find 1 entity named door_1")
	assert_eq(found[0], e1)


func test_find_entities_no_match():
	_make_entity("door_1")
	var found = sys.find_entities_by_name("nonexistent")
	assert_eq(found.size(), 0, "Should find 0 entities for non-matching name")


func test_find_entities_empty_name():
	_make_entity("door_1")
	var found = sys.find_entities_by_name("")
	assert_eq(found.size(), 0, "Empty name should return empty array")


func test_find_entities_by_meta_name():
	var e = _make_entity("entity_node")
	e.set_meta("entity_name", "custom_name")
	var found = sys.find_entities_by_name("custom_name")
	assert_eq(found.size(), 1, "Should find entity by meta entity_name")


# ===========================================================================
# Get all connections
# ===========================================================================


func test_get_all_connections():
	var e1 = _make_entity("trigger_1")
	var e2 = _make_entity("button_1")
	sys.add_entity_output(e1, "OnTrigger", "door_1", "Open")
	sys.add_entity_output(e2, "OnPress", "light_1", "TurnOn")
	var conns = sys.get_all_connections()
	assert_eq(conns.size(), 2, "Should have 2 total connections")


func test_get_all_connections_empty():
	_make_entity("trigger_1")
	var conns = sys.get_all_connections()
	assert_eq(conns.size(), 0, "No connections should return empty array")


func test_get_all_connections_includes_source_info():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnTrigger", "door_1", "Open", "param", 2.0, true)
	var conns = sys.get_all_connections()
	assert_eq(conns.size(), 1)
	var conn = conns[0]
	assert_eq(conn["source"], e)
	assert_eq(conn["source_name"], "trigger_1")
	assert_eq(conn["output_name"], "OnTrigger")
	assert_eq(conn["target_name"], "door_1")
	assert_eq(conn["input_name"], "Open")
	assert_eq(conn["parameter"], "param")
	assert_almost_eq(conn["delay"], 2.0, 0.001)
	assert_true(conn["fire_once"])


# ===========================================================================
# Serialization round-trip
# ===========================================================================


func test_capture_entity_preserves_io_outputs():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnTrigger", "door_1", "Open", "param1", 0.5, false)
	sys.add_entity_output(e, "OnReset", "door_1", "Close", "", 0.0, true)
	var outputs = sys.get_entity_outputs(e)
	# Verify outputs are in meta
	var stored = e.get_meta("entity_io_outputs", [])
	assert_eq(stored.size(), 2, "Meta should have 2 outputs stored")
	assert_eq(stored[0]["output_name"], "OnTrigger")
	assert_eq(stored[1]["output_name"], "OnReset")


func test_io_outputs_survive_meta_round_trip():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnTrigger", "door_1", "Open", "p", 1.0, true)
	# Read back from meta
	var stored: Array = e.get_meta("entity_io_outputs", [])
	var conn = stored[0]
	assert_eq(conn["output_name"], "OnTrigger")
	assert_eq(conn["target_name"], "door_1")
	assert_eq(conn["input_name"], "Open")
	assert_eq(conn["parameter"], "p")
	assert_almost_eq(float(conn["delay"]), 1.0, 0.001)
	assert_true(bool(conn["fire_once"]))


func test_default_parameter_values():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnTrigger", "door_1", "Open")
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs[0]["parameter"], "", "Default parameter should be empty")
	assert_almost_eq(outputs[0]["delay"], 0.0, 0.001, "Default delay should be 0")
	assert_false(outputs[0]["fire_once"], "Default fire_once should be false")
