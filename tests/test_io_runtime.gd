extends GutTest

const HFIORuntime = preload("res://addons/hammerforge/hf_io_runtime.gd")
const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")

var scene_root: Node3D
var dispatcher: HFIORuntime
var sys: HFEntitySystem


func before_each():
	scene_root = Node3D.new()
	scene_root.name = "TestScene"
	add_child_autoqfree(scene_root)
	# Set up a minimal root shim for entity system
	var root_shim := Node3D.new()
	root_shim.name = "RootShim"
	root_shim.set_script(_root_shim_script())
	scene_root.add_child(root_shim)
	var entities := Node3D.new()
	entities.name = "Entities"
	root_shim.add_child(entities)
	root_shim.entities_node = entities
	root_shim.draft_brushes_node = Node3D.new()
	root_shim.add_child(root_shim.draft_brushes_node)
	root_shim.entity_definitions = {}
	root_shim.entity_definitions_path = ""
	sys = HFEntitySystem.new(root_shim)


func after_each():
	dispatcher = null
	scene_root = null
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var entities_node: Node3D
var draft_brushes_node: Node3D
var entity_definitions: Dictionary = {}
var entity_definitions_path: String = ""
"""
	s.reload()
	return s


func _make_entity(parent: Node3D, entity_name: String) -> Node3D:
	var e := Node3D.new()
	e.name = entity_name
	parent.add_child(e)
	return e


func _make_target_entity(parent: Node3D, entity_name: String) -> Node:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var received_calls: Array = []

func Open(parameter: String = "") -> void:
	received_calls.append({"method": "Open", "parameter": parameter})

func turn_on(parameter: String = "") -> void:
	received_calls.append({"method": "turn_on", "parameter": parameter})

func _on_io_input(input_name: String, parameter: String) -> void:
	received_calls.append({"method": "_on_io_input", "input": input_name, "parameter": parameter})
"""
	s.reload()
	var e := Node3D.new()
	e.set_script(s)
	e.name = entity_name
	parent.add_child(e)
	return e


func _add_connection(
	entity: Node,
	output_name: String,
	target_name: String,
	input_name: String,
	parameter: String = "",
	delay: float = 0.0,
	fire_once: bool = false
) -> void:
	var outputs: Array = entity.get_meta("entity_io_outputs", [])
	(
		outputs
		. append(
			{
				"output_name": output_name,
				"target_name": target_name,
				"input_name": input_name,
				"parameter": parameter,
				"delay": delay,
				"fire_once": fire_once,
			}
		)
	)
	entity.set_meta("entity_io_outputs", outputs)


func _wire_dispatcher() -> HFIORuntime:
	dispatcher = HFIORuntime.new()
	dispatcher.name = "HFIODispatcher"
	scene_root.add_child(dispatcher)
	# wire() is called in _ready(), but since we add entities before adding
	# the dispatcher, we need to re-wire after adding entities
	dispatcher.wire()
	return dispatcher


# ===========================================================================
# Basic wiring
# ===========================================================================


func test_wire_discovers_connections():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	assert_eq(dispatcher._connections.size(), 1, "should have 1 source instance")
	# Connections keyed by instance ID
	var id: int = button.get_instance_id()
	assert_eq(dispatcher._connections[id].size(), 1, "should have 1 connection")


func test_wire_caches_entities():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	assert_true(dispatcher._entity_cache.has("Button1"))
	assert_true(dispatcher._entity_cache.has("Door1"))
	# Cache stores arrays
	assert_eq(dispatcher._entity_cache["Button1"].size(), 1)
	assert_eq(dispatcher._entity_cache["Door1"].size(), 1)


# ===========================================================================
# Direct method dispatch
# ===========================================================================


func test_fire_calls_target_method():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1)
	assert_eq(door.received_calls[0]["method"], "Open")


func test_fire_passes_parameter():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open", "fast")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls[0]["parameter"], "fast")


func test_fire_override_parameter():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open", "slow")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed", "fast")
	assert_eq(door.received_calls[0]["parameter"], "fast")


# ===========================================================================
# Snake-case fallback
# ===========================================================================


func test_fire_snake_case_fallback():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "TurnOn")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1)
	assert_eq(door.received_calls[0]["method"], "turn_on")


# ===========================================================================
# Generic _on_io_input fallback
# ===========================================================================


func test_fire_generic_handler_fallback():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "UnknownAction")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1)
	assert_eq(door.received_calls[0]["method"], "_on_io_input")
	assert_eq(door.received_calls[0]["input"], "UnknownAction")


# ===========================================================================
# Fire-once
# ===========================================================================


func test_fire_once():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open", "", 0.0, true)
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")
	dispatcher.fire("Button1", "OnPressed")
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "fire_once should only fire once")


func test_fire_without_fire_once():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open", "", 0.0, false)
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 2, "should fire multiple times")


# ===========================================================================
# User signals
# ===========================================================================


func test_creates_user_signals_on_source():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	assert_true(button.has_signal("io_OnPressed"), "user signal should be added")


func test_emit_user_signal_triggers_connection():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	button.emit_signal("io_OnPressed", "")
	assert_eq(door.received_calls.size(), 1)


# ===========================================================================
# Multiple connections / chain reactions
# ===========================================================================


func test_multiple_targets():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	var light := _make_target_entity(scene_root, "Light1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_add_connection(button, "OnPressed", "Light1", "TurnOn")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1)
	assert_eq(light.received_calls.size(), 1)


func test_chain_reaction():
	# Button -> Door -> Light (chain)
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	var light := _make_target_entity(scene_root, "Light1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_add_connection(door, "OnOpened", "Light1", "TurnOn")
	_wire_dispatcher()
	# Fire button — door receives Open
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1)
	# Now simulate door firing its own output
	dispatcher.fire("Door1", "OnOpened")
	assert_eq(light.received_calls.size(), 1)


# ===========================================================================
# Signal emissions for debugging
# ===========================================================================


func test_io_fired_signal():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	var fired_args: Array = []
	dispatcher.io_fired.connect(
		func(src, out, tgt, inp, param):
			fired_args.append({"src": src, "out": out, "tgt": tgt, "inp": inp, "param": param})
	)
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(fired_args.size(), 1)
	assert_eq(fired_args[0]["src"], "Button1")
	assert_eq(fired_args[0]["tgt"], "Door1")


# ===========================================================================
# Missing target
# ===========================================================================


func test_missing_target_does_not_crash():
	var button := _make_entity(scene_root, "Button1")
	_add_connection(button, "OnPressed", "NonExistent", "Open")
	_wire_dispatcher()
	# Should not crash
	dispatcher.fire("Button1", "OnPressed")
	pass_test("no crash on missing target")


# ===========================================================================
# Re-wire
# ===========================================================================


func test_rewire_clears_state():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	# Add a new entity and connection after initial wire
	var light := _make_target_entity(scene_root, "Light1")
	_add_connection(button, "OnPressed", "Light1", "TurnOn")
	dispatcher.wire()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1)
	assert_eq(light.received_calls.size(), 1)


# ===========================================================================
# Static fire_on helper
# ===========================================================================


func test_static_fire_on():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	HFIORuntime.fire_on(button, "OnPressed")
	assert_eq(door.received_calls.size(), 1)


# ===========================================================================
# Signal name helper
# ===========================================================================


func test_signal_name():
	assert_eq(HFIORuntime._signal_name("OnTrigger"), "io_OnTrigger")


func test_to_snake_case():
	assert_eq(HFIORuntime._to_snake_case("TurnOn"), "turn_on")
	assert_eq(HFIORuntime._to_snake_case("OnDamage"), "on_damage")
	assert_eq(HFIORuntime._to_snake_case("open"), "open")


# ===========================================================================
# Entity system fire_output()
# ===========================================================================


func test_entity_system_fire_output_fallback():
	var root_shim: Node3D = scene_root.get_node("RootShim")
	var button := _make_entity(root_shim.entities_node, "Btn")
	var door := _make_target_entity(root_shim.entities_node, "Dr")
	sys.add_entity_output(button, "OnPress", "Dr", "Open")
	sys.fire_output(button, "OnPress")
	assert_eq(door.received_calls.size(), 1)
	assert_eq(door.received_calls[0]["method"], "Open")


# ===========================================================================
# Target signal fallback (no method, no _on_io_input)
# ===========================================================================


func test_target_signal_fallback():
	var button := _make_entity(scene_root, "Button1")
	# Plain Node3D with no methods — will get a user signal created
	var target := _make_entity(scene_root, "PlainTarget")
	_add_connection(button, "OnPressed", "PlainTarget", "CustomAction")
	_wire_dispatcher()
	var received: Array = []
	# Wire after dispatcher creates the signal
	dispatcher.fire("Button1", "OnPressed")
	# The target should now have the signal
	assert_true(target.has_signal("io_CustomAction"), "user signal created on target")


# ===========================================================================
# Duplicate target names (multi-target resolution)
# ===========================================================================


func test_duplicate_names_all_receive():
	var button := _make_entity(scene_root, "Button1")
	var door_a := _make_target_entity(scene_root, "Door")
	# Godot auto-renames duplicate siblings, so parent under different nodes
	var sub := Node3D.new()
	sub.name = "Sub"
	scene_root.add_child(sub)
	var door_b := _make_target_entity(sub, "Door")
	_add_connection(button, "OnPressed", "Door", "Open")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door_a.received_calls.size(), 1, "first Door should receive")
	assert_eq(door_b.received_calls.size(), 1, "second Door should receive")


func test_entity_name_meta_alias():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "DoorNode")
	door.set_meta("entity_name", "my_door")
	_add_connection(button, "OnPressed", "my_door", "Open")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1)


# ===========================================================================
# Extra scan roots (bake-path fix)
# ===========================================================================


func test_extra_scan_roots():
	# Simulate the bake scenario: dispatcher under baked_container,
	# entities under a sibling node.
	var baked_container := Node3D.new()
	baked_container.name = "BakedContainer"
	scene_root.add_child(baked_container)

	var entities_node := Node3D.new()
	entities_node.name = "Entities2"
	scene_root.add_child(entities_node)

	var button := _make_entity(entities_node, "Btn")
	var door := _make_target_entity(entities_node, "Dr")
	_add_connection(button, "OnPressed", "Dr", "Open")

	dispatcher = HFIORuntime.new()
	dispatcher.name = "HFIODispatcher"
	dispatcher.extra_scan_roots.append(entities_node)
	baked_container.add_child(dispatcher)
	dispatcher.wire()

	dispatcher.fire("Btn", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "dispatcher should find entities via extra_scan_roots")


func test_extra_scan_roots_empty_without():
	# Without extra_scan_roots, dispatcher under baked_container misses sibling entities
	var baked_container := Node3D.new()
	baked_container.name = "BakedContainer"
	scene_root.add_child(baked_container)

	var entities_node := Node3D.new()
	entities_node.name = "Entities2"
	scene_root.add_child(entities_node)

	var button := _make_entity(entities_node, "Btn")
	var door := _make_target_entity(entities_node, "Dr")
	_add_connection(button, "OnPressed", "Dr", "Open")

	dispatcher = HFIORuntime.new()
	dispatcher.name = "HFIODispatcher"
	baked_container.add_child(dispatcher)
	dispatcher.wire()

	assert_eq(dispatcher._connections.size(), 0, "should find 0 connections without extra roots")


# ===========================================================================
# Rewire signal duplication fix
# ===========================================================================


func test_rewire_does_not_duplicate_signals():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()

	# Rewire multiple times
	dispatcher.wire()
	dispatcher.wire()

	# Emit the user signal — should only fire once per emit, not 3x
	button.emit_signal("io_OnPressed", "")
	assert_eq(door.received_calls.size(), 1, "rewire should not stack signal handlers")


func test_rewire_via_fire_no_duplication():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()

	dispatcher.wire()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "fire after rewire should deliver once")


# ===========================================================================
# Duplicate source names — per-instance isolation
# ===========================================================================


func test_duplicate_source_names_fire_from_isolates():
	# Two sources share the name "Button" but have different connections.
	# fire_from() should only run the connections of the specific instance.
	var sub_a := Node3D.new()
	sub_a.name = "SubA"
	scene_root.add_child(sub_a)
	var sub_b := Node3D.new()
	sub_b.name = "SubB"
	scene_root.add_child(sub_b)

	var btn_a := _make_entity(sub_a, "Button")
	var btn_b := _make_entity(sub_b, "Button")
	var door := _make_target_entity(scene_root, "Door1")
	var light := _make_target_entity(scene_root, "Light1")

	_add_connection(btn_a, "OnPressed", "Door1", "Open")
	_add_connection(btn_b, "OnPressed", "Light1", "TurnOn")
	_wire_dispatcher()

	# fire_from btn_a should only open door, not turn on light
	dispatcher.fire_from(btn_a, "OnPressed")
	assert_eq(door.received_calls.size(), 1, "Door should receive from btn_a")
	assert_eq(light.received_calls.size(), 0, "Light should NOT receive from btn_a")


func test_duplicate_source_names_fire_by_name_hits_both():
	# fire() by name runs connections of ALL sources sharing that name
	var sub_a := Node3D.new()
	sub_a.name = "SubA"
	scene_root.add_child(sub_a)
	var sub_b := Node3D.new()
	sub_b.name = "SubB"
	scene_root.add_child(sub_b)

	var btn_a := _make_entity(sub_a, "Button")
	var btn_b := _make_entity(sub_b, "Button")
	var door := _make_target_entity(scene_root, "Door1")
	var light := _make_target_entity(scene_root, "Light1")

	_add_connection(btn_a, "OnPressed", "Door1", "Open")
	_add_connection(btn_b, "OnPressed", "Light1", "TurnOn")
	_wire_dispatcher()

	dispatcher.fire("Button", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "Door should receive")
	assert_eq(light.received_calls.size(), 1, "Light should receive")


# ===========================================================================
# io_received emits per-target (fan-out accuracy)
# ===========================================================================


func test_io_received_emits_per_target():
	var button := _make_entity(scene_root, "Button1")
	# Two targets with the same name under different parents
	var sub := Node3D.new()
	sub.name = "Sub"
	scene_root.add_child(sub)
	var door_a := _make_target_entity(scene_root, "Door")
	var door_b := _make_target_entity(sub, "Door")
	_add_connection(button, "OnPressed", "Door", "Open")
	_wire_dispatcher()

	# Use array — GDScript lambdas capture ints by value, arrays by reference
	var counts: Array = [0]
	dispatcher.io_received.connect(func(_tgt, _inp, _param): counts[0] += 1)
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(counts[0], 2, "io_received should emit once per target delivery")


func test_io_fired_emits_per_target():
	var button := _make_entity(scene_root, "Button1")
	var sub := Node3D.new()
	sub.name = "Sub"
	scene_root.add_child(sub)
	var door_a := _make_target_entity(scene_root, "Door")
	var door_b := _make_target_entity(sub, "Door")
	_add_connection(button, "OnPressed", "Door", "Open")
	_wire_dispatcher()

	# Use array — GDScript lambdas capture ints by value, arrays by reference
	var counts: Array = [0]
	dispatcher.io_fired.connect(func(_src, _out, _tgt, _inp, _param): counts[0] += 1)
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(counts[0], 2, "io_fired should emit once per target delivery")


# ===========================================================================
# Extra scan root paths (serialization)
# ===========================================================================


func test_extra_scan_root_paths():
	# Verify the NodePath-based extra roots work (simulating scene reload)
	var baked_container := Node3D.new()
	baked_container.name = "BakedContainer"
	scene_root.add_child(baked_container)

	var entities_node := Node3D.new()
	entities_node.name = "Entities2"
	scene_root.add_child(entities_node)

	var button := _make_entity(entities_node, "Btn")
	var door := _make_target_entity(entities_node, "Dr")
	_add_connection(button, "OnPressed", "Dr", "Open")

	dispatcher = HFIORuntime.new()
	dispatcher.name = "HFIODispatcher"
	baked_container.add_child(dispatcher)
	# Set NodePath instead of direct ref (simulates deserialized state)
	dispatcher.extra_scan_root_paths.append(dispatcher.get_path_to(entities_node))
	dispatcher.wire()

	dispatcher.fire("Btn", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "NodePath-based extra roots should work")


func test_overlapping_extra_roots_no_double_fire():
	# Simulates the bake path: both transient ref and NodePath point to the
	# same entities_node.  Connections must not be duplicated.
	var baked_container := Node3D.new()
	baked_container.name = "BakedContainer"
	scene_root.add_child(baked_container)

	var entities_node := Node3D.new()
	entities_node.name = "Entities2"
	scene_root.add_child(entities_node)

	var button := _make_entity(entities_node, "Btn")
	var door := _make_target_entity(entities_node, "Dr")
	_add_connection(button, "OnPressed", "Dr", "Open")

	dispatcher = HFIORuntime.new()
	dispatcher.name = "HFIODispatcher"
	# Set both — same node via transient ref AND serialized path
	dispatcher.extra_scan_roots.append(entities_node)
	baked_container.add_child(dispatcher)
	dispatcher.extra_scan_root_paths.append(dispatcher.get_path_to(entities_node))
	dispatcher.wire()

	dispatcher.fire("Btn", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "overlapping extra roots must not double-fire")


func test_descendant_extra_root_no_double_fire():
	# Extra root is a descendant of the primary scan root (parent).
	# The descendant subtree must not be scanned twice.
	var entities_node := Node3D.new()
	entities_node.name = "Entities3"
	scene_root.add_child(entities_node)

	var button := _make_entity(entities_node, "Btn")
	var door := _make_target_entity(entities_node, "Dr")
	_add_connection(button, "OnPressed", "Dr", "Open")

	dispatcher = HFIORuntime.new()
	dispatcher.name = "HFIODispatcher"
	# entities_node is a child of scene_root, and dispatcher's parent is
	# scene_root — so entities_node is a descendant of the primary scan root
	dispatcher.extra_scan_roots.append(entities_node)
	scene_root.add_child(dispatcher)
	dispatcher.wire()

	dispatcher.fire("Btn", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "descendant extra root must not cause double-fire")


func test_prune_overlapping_roots():
	var a := Node3D.new()
	a.name = "A"
	scene_root.add_child(a)
	var b := Node3D.new()
	b.name = "B"
	a.add_child(b)

	var roots: Array[Node] = [scene_root, a, b]
	var pruned: Array[Node] = HFIORuntime._prune_overlapping_roots(roots)
	assert_eq(pruned.size(), 1, "only the top-most ancestor should remain")
	assert_eq(pruned[0], scene_root)


func test_prune_overlapping_roots_disjoint():
	var a := Node3D.new()
	a.name = "A"
	scene_root.add_child(a)
	var b := Node3D.new()
	b.name = "B"
	scene_root.add_child(b)

	# a and b are siblings — neither is an ancestor of the other
	var roots: Array[Node] = [a, b]
	var pruned: Array[Node] = HFIORuntime._prune_overlapping_roots(roots)
	assert_eq(pruned.size(), 2, "disjoint roots should both survive")
