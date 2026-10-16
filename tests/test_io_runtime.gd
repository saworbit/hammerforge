extends GutTest

const HFIORuntime = preload("res://addons/hammerforge/hf_io_runtime.gd")
const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")

var scene_root: Node3D
var level: LevelRoot
var dispatcher: HFIORuntime
var sys: HFEntitySystem


func before_each():
	scene_root = Node3D.new()
	scene_root.name = "TestScene"
	add_child_autoqfree(scene_root)
	# A level inside the scene, for the entity system's fire_output()
	level = LevelRoot.new()
	level.name = "Level"
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	scene_root.add_child(level)
	sys = level.entity_system


func after_each():
	Engine.time_scale = 1.0
	get_tree().paused = false
	dispatcher = null
	scene_root = null
	level = null
	sys = null


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


func test_dispatcher_joins_lookup_group():
	_wire_dispatcher()
	assert_true(
		dispatcher.is_in_group("hf_io_dispatcher"),
		"HFIORuntime should join hf_io_dispatcher for O(1) lookup",
	)


func test_find_dispatcher_uses_group_before_tree_walk():
	_wire_dispatcher()
	var found := HFIORuntime._find_dispatcher(scene_root)
	assert_eq(found, dispatcher, "Group lookup should return the live dispatcher")


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
	var button := _make_entity(level.entities_node, "Btn")
	var door := _make_target_entity(level.entities_node, "Dr")
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


# ===========================================================================
# Firing by authored entity name (#151)
# ===========================================================================


func test_fire_resolves_source_by_entity_name_meta():
	var button := _make_entity(scene_root, "Area3D_Baked_1")
	button.set_meta("entity_name", "secret_button")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()

	dispatcher.fire("secret_button", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "fire() should resolve the authored entity name")


func test_fire_still_resolves_source_by_node_name():
	var button := _make_entity(scene_root, "Area3D_Baked_1")
	button.set_meta("entity_name", "secret_button")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()

	dispatcher.fire("Area3D_Baked_1", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "Node name lookup must keep working")


func test_fire_by_both_names_does_not_double_dispatch():
	var button := _make_entity(scene_root, "Trigger_0")
	button.set_meta("entity_name", "secret_button")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()

	dispatcher.fire("secret_button", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "One alias fires the source exactly once")


func test_fire_ignores_empty_entity_name_meta():
	var button := _make_entity(scene_root, "Button1")
	button.set_meta("entity_name", "")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()

	dispatcher.fire("", "OnPressed")
	assert_eq(door.received_calls.size(), 0, "An empty alias must not become a lookup key")


# ===========================================================================
# Names that collide with the engine, and metadata that is not a list
# ===========================================================================


func test_an_input_named_after_an_engine_method_does_not_call_it():
	# `has_method()` answers for everything Node implements, and the snake_case
	# fallback turns ordinary PascalCase naming into a collision: an input called
	# QueueFree used to delete the target.
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnTrigger", "Door1", "QueueFree")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnTrigger")
	assert_true(is_instance_valid(door), "The target is still there")
	assert_false(door.is_queued_for_deletion(), "and is not on its way out")
	assert_eq(door.received_calls.size(), 1, "The input went to the generic handler instead")
	assert_eq(door.received_calls[0]["method"], "_on_io_input")
	assert_eq(door.received_calls[0]["input"], "QueueFree")


func test_an_input_named_hide_is_left_to_the_target_to_handle():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnTrigger", "Door1", "Hide")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnTrigger")
	assert_true(door.visible, "The engine method was not called behind the game's back")
	assert_eq(door.received_calls[0]["method"], "_on_io_input", "It went to the handler")


func test_an_input_the_target_script_defines_is_still_called():
	# The guard must not cost the ordinary case.
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1)
	assert_eq(door.received_calls[0]["method"], "Open", "A script method still answers")


func test_an_input_starting_with_an_underscore_is_not_called():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnTrigger", "Door1", "_ready")
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnTrigger")
	assert_eq(door.received_calls[0]["method"], "_on_io_input", "Engine callbacks are not inputs")


func test_malformed_outputs_metadata_costs_only_that_entity():
	# The typed local used to make this a runtime error that unwound the whole
	# scan, including the recursion into the children, so everything nested under
	# the bad entity dropped out of the wiring.
	var broken := _make_entity(scene_root, "BrokenButton")
	broken.set_meta("entity_io_outputs", "not a list")
	var nested := _make_entity(broken, "NestedButton")
	var good := _make_entity(scene_root, "GoodButton")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(nested, "OnPressed", "Door1", "Open")
	_add_connection(good, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	assert_true(
		dispatcher._source_name_to_ids.has("NestedButton"),
		"The entity under the bad one is still wired"
	)
	assert_true(dispatcher._source_name_to_ids.has("GoodButton"), "and so is its sibling")
	assert_false(dispatcher._source_name_to_ids.has("BrokenButton"), "The bad one is skipped")
	dispatcher.fire("NestedButton", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "and the nested connection fires")


func test_malformed_outputs_metadata_does_not_stop_the_entity_cache():
	var broken := _make_entity(scene_root, "BrokenButton")
	broken.set_meta("entity_io_outputs", {"output_name": "OnPressed"})
	var nested := _make_entity(broken, "NestedDoor")
	_wire_dispatcher()
	assert_true(dispatcher._entity_cache.has("NestedDoor"), "Nested entities are still found")


# ===========================================================================
# The call shape comes from the handler, not from the parameter field (#497)
# ===========================================================================


## Every handler in the fixture above is declared with a default, so it accepts
## both call shapes and both branches passed whatever the code did. These targets
## declare one shape each.
func _make_arity_target(parent: Node3D, entity_name: String, declaration: String) -> Node:
	var s = GDScript.new()
	s.source_code = (
		"""
extends Node3D

var received_calls: Array = []

%s
	received_calls.append({"method": "Open"})

func _on_io_input(input_name: String, parameter: String) -> void:
	received_calls.append({"method": "_on_io_input", "input": input_name})
"""
		% declaration
	)
	s.reload()
	var e := Node3D.new()
	e.set_script(s)
	e.name = entity_name
	parent.add_child(e)
	return e


func test_a_handler_that_takes_nothing_is_called_without_the_parameter():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_arity_target(scene_root, "Door1", "func Open() -> void:")
	_add_connection(button, "OnPressed", "Door1", "Open", "fast")
	_wire_dispatcher()

	dispatcher.fire("Button1", "OnPressed")

	assert_eq(door.received_calls.size(), 1, "a parameter it cannot take must not stop the call")
	assert_eq(door.received_calls[0]["method"], "Open")


func test_a_handler_that_requires_one_is_called_with_the_empty_parameter():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_arity_target(scene_root, "Door1", "func Open(parameter: String) -> void:")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()

	dispatcher.fire("Button1", "OnPressed")

	assert_eq(door.received_calls.size(), 1, "no parameter typed is an empty one, not no call")
	assert_eq(door.received_calls[0]["method"], "Open")


func test_a_handler_with_a_default_still_takes_both_shapes():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_add_connection(button, "OnTwo", "Door1", "Open", "fast")
	_wire_dispatcher()

	dispatcher.fire("Button1", "OnPressed")
	dispatcher.fire("Button1", "OnTwo")

	assert_eq(door.received_calls.size(), 2)
	assert_eq(door.received_calls[0]["parameter"], "")
	assert_eq(door.received_calls[1]["parameter"], "fast")


## One parameter field cannot satisfy two required arguments, so the input goes
## down the fallback chain rather than raising an error that ends delivery.
func test_a_handler_needing_two_arguments_falls_through_to_the_generic_handler():
	var button := _make_entity(scene_root, "Button1")
	var door := _make_arity_target(scene_root, "Door1", "func Open(a: String, b: String) -> void:")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()

	dispatcher.fire("Button1", "OnPressed")

	assert_eq(door.received_calls.size(), 1, "the input still lands somewhere")
	assert_eq(door.received_calls[0]["method"], "_on_io_input")


# ===========================================================================
# A source raises its own output (#686, #714)
# ===========================================================================


func _make_trigger_volume(parent: Node3D, volume_name: String, entity_class: String) -> Area3D:
	var area := Area3D.new()
	area.name = volume_name
	area.monitoring = true
	area.set_meta("entity_name", volume_name)
	area.set_meta("brush_entity_class", entity_class)
	parent.add_child(area)
	return area


func test_a_trigger_volume_raises_its_output_when_a_body_enters():
	# Nothing in the addon called fire(), so every graph a mapper wired was inert
	# at runtime however correct it was.
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_multiple")
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	_wire_dispatcher()
	assert_gt(
		volume.get_signal_connection_list("body_entered").size(),
		0,
		"body_entered is what a trigger volume fires from"
	)
	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 1, "walking in should deliver the wired input")
	assert_eq(door.received_calls[0]["method"], "Open")


func test_a_trigger_volume_raises_its_end_output_when_a_body_leaves():
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_multiple")
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(volume, "OnEndTouch", "gate", "Open")
	_wire_dispatcher()
	volume.emit_signal("body_exited", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 1, "leaving should deliver the wired input")


func test_trigger_multiple_raises_its_output_every_time():
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_multiple")
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	_wire_dispatcher()
	for _i in 3:
		volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 3, "trigger_multiple fires every time")


func test_trigger_once_raises_its_output_only_the_first_time():
	# The class describes itself as firing the first time the player enters it,
	# which with trigger_multiple's wait is all that separates the two in the bake.
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_once")
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	_wire_dispatcher()
	for _i in 3:
		volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 1, "trigger_once fires the first time only")


func test_a_rewire_does_not_let_trigger_once_fire_again():
	# wire() is documented as safe to call again, and it cleared the fired state
	# with everything else, so the same live volume fired a second time (#825).
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_once")
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	_wire_dispatcher()
	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 1, "fixture: the first touch fires")

	dispatcher.wire()
	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 1, "the same volume stays fired across a rewire")


func test_a_volume_that_replaces_a_fired_one_fires_once_itself():
	var first := _make_trigger_volume(scene_root, "front_trigger", "trigger_once")
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(first, "OnStartTouch", "gate", "Open")
	_wire_dispatcher()
	first.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	scene_root.remove_child(first)
	first.free()
	var second := _make_trigger_volume(scene_root, "front_trigger", "trigger_once")
	_add_connection(second, "OnStartTouch", "gate", "Open")

	dispatcher.wire()
	second.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	second.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 2, "a new volume is a new once, and only once")


func test_a_rewire_does_not_let_a_fire_once_connection_fire_again():
	# The same promise made per connection rather than per class.
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "Door1", "Open", "", 0.0, true)
	_wire_dispatcher()
	dispatcher.fire("Button1", "OnPressed")

	dispatcher.wire()
	dispatcher.fire("Button1", "OnPressed")

	assert_eq(door.received_calls.size(), 1, "a fire once connection stays fired across a rewire")


func test_disable_stops_a_trigger_volume_detecting_bodies():
	# trigger_once and trigger_multiple declare Enable and Disable as well.
	var relay := _make_entity(scene_root, "relay")
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_once")
	_add_connection(relay, "OnTrigger", "front_trigger", "Disable")
	_add_connection(relay, "OnUser1", "front_trigger", "Enable")
	_wire_dispatcher()

	dispatcher.fire("relay", "OnTrigger")
	await wait_physics_frames(2)
	assert_false(volume.monitoring, "a disabled trigger stops detecting bodies")

	dispatcher.fire("relay", "OnUser1")
	await wait_physics_frames(2)
	assert_true(volume.monitoring, "and Enable turns it back on")


func test_enable_on_a_plain_node_is_left_to_the_game():
	# Only a baked brush entity has an Enable of its own. Anything else still gets
	# the user signal and nothing more.
	var relay := _make_entity(scene_root, "relay")
	var target := _make_entity(scene_root, "lamp")
	_add_connection(relay, "OnTrigger", "lamp", "Disable")
	_wire_dispatcher()
	dispatcher.fire("relay", "OnTrigger")
	await wait_physics_frames(1)
	assert_true(target.visible, "a node with no brush entity class is not hidden")
	assert_true(target.has_signal("io_Disable"), "it got the user signal instead")


func test_a_brush_entity_with_no_class_signal_is_left_alone():
	# func_detail and func_wall have no event of their own, and connecting one to
	# a signal the class does not name would fire outputs nobody asked for.
	var volume := _make_trigger_volume(scene_root, "clutter", "func_detail")
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	_wire_dispatcher()
	assert_eq(volume.get_signal_connection_list("body_entered").size(), 0)


func test_rewiring_does_not_double_connect_a_class_signal():
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_multiple")
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	_wire_dispatcher()
	dispatcher.wire()
	dispatcher.wire()
	assert_eq(volume.get_signal_connection_list("body_entered").size(), 1)
	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 1, "one body entering is one delivery")


func test_an_input_the_class_grants_calls_the_engine_method():
	# logic_timer declares Start and Stop, its node class is Timer, and those are
	# exactly the two methods the engine-method guard exists to refuse.
	var relay := _make_entity(scene_root, "relay")
	var timer := Timer.new()
	timer.name = "spawner"
	timer.set_meta("entity_name", "spawner")
	timer.set_meta("entity_io_input_methods", {"Start": "start", "Stop": "stop"})
	timer.wait_time = 5.0
	scene_root.add_child(timer)
	_add_connection(relay, "OnTrigger", "spawner", "Start")
	_wire_dispatcher()
	assert_true(timer.is_stopped(), "the timer has not been started yet")
	dispatcher.fire("relay", "OnTrigger")
	assert_false(timer.is_stopped(), "Start should have called Timer.start()")


func test_a_class_can_name_the_engine_signal_an_output_comes_from():
	# A Timer raises `timeout`, and nothing turned that into the OnTimer a mapper
	# wires (#826). The class names the signal the way it names input methods.
	var door := _make_target_entity(scene_root, "door")
	var timer := Timer.new()
	timer.name = "tick"
	timer.set_meta("entity_name", "tick")
	timer.set_meta("entity_io_output_signals", {"timeout": "OnTimer"})
	scene_root.add_child(timer)
	_add_connection(timer, "OnTimer", "door", "Open")
	_wire_dispatcher()

	timer.timeout.emit()

	assert_eq(door.received_calls.size(), 1, "OnTimer reached the door")
	if door.received_calls.size() == 1:
		assert_eq(door.received_calls[0]["method"], "Open")


func test_a_rewire_does_not_raise_a_named_signal_output_twice():
	var door := _make_target_entity(scene_root, "door")
	var timer := Timer.new()
	timer.name = "tick"
	timer.set_meta("entity_name", "tick")
	timer.set_meta("entity_io_output_signals", {"timeout": "OnTimer"})
	scene_root.add_child(timer)
	_add_connection(timer, "OnTimer", "door", "Open")
	_wire_dispatcher()
	dispatcher.wire()

	timer.timeout.emit()

	assert_eq(door.received_calls.size(), 1, "one timeout, one Open")


func test_a_granted_method_takes_its_parameter_in_the_type_it_declares():
	# The parameter field is free text and an engine argument is typed, so handing
	# Timer.start() a String is an argument error that stops the delivery dead.
	var relay := _make_entity(scene_root, "relay")
	var timer := Timer.new()
	timer.name = "spawner"
	timer.set_meta("entity_name", "spawner")
	timer.set_meta("entity_io_input_methods", {"Start": "start", "Stop": "stop"})
	timer.wait_time = 60.0
	scene_root.add_child(timer)
	_add_connection(relay, "OnTrigger", "spawner", "Start", "2.5")
	_wire_dispatcher()
	dispatcher.fire("relay", "OnTrigger")
	assert_false(timer.is_stopped(), "Start should have called Timer.start()")
	assert_almost_eq(timer.time_left, 2.5, 0.25, "the parameter is the interval in seconds")


func test_an_engine_method_the_class_does_not_grant_is_still_refused():
	# The guard is what stops an input called QueueFree deleting its target, and a
	# grant is per class rather than a global allow-list for that reason.
	var relay := _make_entity(scene_root, "relay")
	var timer := Timer.new()
	timer.name = "spawner"
	timer.set_meta("entity_name", "spawner")
	timer.wait_time = 5.0
	scene_root.add_child(timer)
	_add_connection(relay, "OnTrigger", "spawner", "Start")
	_wire_dispatcher()
	dispatcher.fire("relay", "OnTrigger")
	assert_true(timer.is_stopped(), "an ungranted engine method is not called")


# ===========================================================================
# A trigger's and a button's wait and lock reach the game (#1121)
# ===========================================================================


## A dispatcher whose clock the test sets, so a wait is checked without sleeping.
class ClockedRuntime:
	extends HFIORuntime
	var now := 0.0

	func _now() -> float:
		return now


func _wire_clocked_dispatcher(parent: Node = null) -> ClockedRuntime:
	var clocked := ClockedRuntime.new()
	clocked.name = "HFIODispatcher"
	(parent if parent else scene_root).add_child(clocked)
	clocked.wire()
	dispatcher = clocked
	return clocked


## What the bake makes of a `func_button`: a mesh carrying the wiring, and a body
## beside it that the player's ray hits. Both answer to the button's name.
func _make_button(button_name: String, data: Dictionary, target_name: String) -> StaticBody3D:
	var mesh := MeshInstance3D.new()
	mesh.name = button_name
	mesh.set_meta("entity_name", button_name)
	mesh.set_meta("brush_entity_class", "func_button")
	mesh.set_meta("entity_data", data.duplicate())
	scene_root.add_child(mesh)
	_add_connection(mesh, "OnPressed", target_name, "Open")
	var body := StaticBody3D.new()
	body.name = "FuncDetailCollision_0"
	body.set_meta("entity_name", button_name)
	body.set_meta("brush_entity_class", "func_button")
	body.set_meta("entity_data", data.duplicate())
	scene_root.add_child(body)
	return body


func test_trigger_multiple_waits_its_wait_before_it_fires_again():
	# entities.json declares the wait and the Entity panel edits it, and nothing
	# past the bake read it, so every body entering fired.
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_multiple")
	volume.set_meta("entity_data", {"wait": 2.0})
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	var clocked := _wire_clocked_dispatcher()

	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	clocked.now = 1.0
	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 1, "a second entry a second later is inside the wait")

	clocked.now = 2.0
	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 2, "two seconds after it fired, it fires again")


func test_a_trigger_with_a_wait_below_zero_fires_once_and_never_again():
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_multiple")
	volume.set_meta("entity_data", {"wait": -1.0})
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	var clocked := _wire_clocked_dispatcher()

	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	clocked.now = 1000.0
	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 1, "a wait below zero is once")


func test_a_trigger_with_a_wait_of_zero_fires_every_time():
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_multiple")
	volume.set_meta("entity_data", {"wait": 0.0})
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	_wire_clocked_dispatcher()

	for _i in 3:
		volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 3, "zero is every time")


func test_the_wait_holds_back_entering_and_not_leaving():
	var volume := _make_trigger_volume(scene_root, "front_trigger", "trigger_multiple")
	volume.set_meta("entity_data", {"wait": 2.0})
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(volume, "OnEndTouch", "gate", "Open")
	_wire_clocked_dispatcher()

	for _i in 3:
		volume.emit_signal("body_exited", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 3, "every body leaving still fires OnEndTouch")


func test_volumes_tied_under_one_name_share_one_wait():
	# Each brush bakes to a volume of its own, and a trigger built from two brushes
	# is still one trigger.
	var first := _make_trigger_volume(scene_root, "hall_trigger", "trigger_multiple")
	var second := _make_trigger_volume(scene_root, "hall_trigger", "trigger_multiple")
	var door := _make_target_entity(scene_root, "gate")
	for volume in [first, second]:
		volume.set_meta("entity_data", {"wait": 2.0})
		_add_connection(volume, "OnStartTouch", "gate", "Open")
	var clocked := _wire_clocked_dispatcher()

	first.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	clocked.now = 1.0
	second.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 1, "the second brush is inside the same wait")


func test_a_locked_button_does_not_fire_until_it_is_unlocked():
	# The playtest player fired OnPressed by name on every use, locked or not.
	var body := _make_button("vault_button", {"locked": true, "wait": 0.0}, "gate")
	var door := _make_target_entity(scene_root, "gate")
	var relay := _make_entity(scene_root, "relay")
	_add_connection(relay, "OnTrigger", "vault_button", "Unlock")
	var clocked = _wire_clocked_dispatcher()

	assert_false(clocked.press_button(body), "a locked button refuses the press")
	assert_eq(door.received_calls.size(), 0, "so OnPressed does not fire")

	dispatcher.fire("relay", "OnTrigger")
	assert_true(clocked.press_button(body), "Unlock lets it be pressed")
	assert_eq(door.received_calls.size(), 1, "and OnPressed fires")


func test_lock_stops_a_button_being_pressed():
	var body := _make_button("vault_button", {"locked": false, "wait": 0.0}, "gate")
	var door := _make_target_entity(scene_root, "gate")
	var relay := _make_entity(scene_root, "relay")
	_add_connection(relay, "OnTrigger", "vault_button", "Lock")
	var clocked = _wire_clocked_dispatcher()

	clocked.press_button(body)
	dispatcher.fire("relay", "OnTrigger")
	clocked.press_button(body)

	assert_eq(door.received_calls.size(), 1, "the press after Lock is refused")


func test_a_button_pressed_twice_inside_its_wait_fires_once():
	var body := _make_button("vault_button", {"wait": 1.0}, "gate")
	var door := _make_target_entity(scene_root, "gate")
	var clocked = _wire_clocked_dispatcher()

	clocked.press_button(body)
	clocked.now = 0.5
	clocked.press_button(body)
	assert_eq(door.received_calls.size(), 1, "half a second is inside a one second wait")

	clocked.now = 1.0
	clocked.press_button(body)
	assert_eq(door.received_calls.size(), 2, "and a second after it fired, it fires again")


func test_a_wire_into_press_presses_the_button_once():
	# Press, Lock and Unlock fell through to a user signal nobody was connected to.
	# The button is a mesh and a body under one name and both receive the input,
	# which is still one press.
	var body := _make_button("vault_button", {"wait": 0.0}, "gate")
	var door := _make_target_entity(scene_root, "gate")
	var relay := _make_entity(scene_root, "relay")
	_add_connection(relay, "OnTrigger", "vault_button", "Press")
	_wire_clocked_dispatcher()

	dispatcher.fire("relay", "OnTrigger")

	assert_eq(door.received_calls.size(), 1, "one Press is one OnPressed")
	assert_true(body.has_signal("io_Press"), "and the user signal still goes out")


func test_a_wire_into_press_goes_through_the_lock():
	_make_button("vault_button", {"locked": true}, "gate")
	var door := _make_target_entity(scene_root, "gate")
	var relay := _make_entity(scene_root, "relay")
	_add_connection(relay, "OnTrigger", "vault_button", "Press")
	_wire_clocked_dispatcher()

	dispatcher.fire("relay", "OnTrigger")

	assert_eq(door.received_calls.size(), 0, "Press is refused by a lock the way Use is")


func test_a_button_reads_its_properties_as_a_map_import_wrote_them():
	# A `.map` import stores every value as the text it read.
	var body := _make_button("vault_button", {"locked": "1", "wait": "2"}, "gate")
	var door := _make_target_entity(scene_root, "gate")
	var relay := _make_entity(scene_root, "relay")
	_add_connection(relay, "OnTrigger", "vault_button", "Unlock")
	var clocked = _wire_clocked_dispatcher()

	assert_false(clocked.press_button(body), '"1" is locked')
	dispatcher.fire("relay", "OnTrigger")
	clocked.press_button(body)
	clocked.now = 1.0
	clocked.press_button(body)

	assert_eq(door.received_calls.size(), 1, 'and "2" is a two second wait')


# -- From the bake --------------------------------------------------------------


## Bake the level's brush entities into a container beside it, with a dispatcher
## inside the container the way a bake attaches one.
func _bake_brush_entities() -> Node3D:
	var container := Node3D.new()
	container.name = "Baked"
	scene_root.add_child(container)
	level.bake_system._append_nonstructural_brushes(container)
	return container


func _brush(brush_id: String) -> Node3D:
	return (
		level.create_brush_from_info(
			{"shape": 0, "size": Vector3(2, 2, 2), "center": Vector3.ZERO, "brush_id": brush_id}
		)
		as Node3D
	)


func test_a_baked_trigger_multiple_waits_the_wait_its_brush_was_given():
	var brush := _brush("t1")
	level.tie_brushes_to_entity(["t1"], "trigger_multiple", "hall_trigger")
	HFEntityPropUtils.set_entity_property(brush, "wait", 2.0)
	level.add_entity_output(brush, "OnStartTouch", "gate", "Open")
	var container := _bake_brush_entities()
	var door := _make_target_entity(container, "gate")
	var clocked := _wire_clocked_dispatcher(container)
	var volume := container.get_node("Nonstructural/hall_trigger") as Area3D

	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	clocked.now = 1.0
	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 1, "inside the wait the Entity panel set")
	clocked.now = 2.0
	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 2, "and out of it")


func test_a_baked_button_stays_locked_until_it_is_unlocked():
	var brush := _brush("b1")
	level.tie_brushes_to_entity(["b1"], "func_button", "vault_button")
	HFEntityPropUtils.set_entity_property(brush, "locked", true)
	level.add_entity_output(brush, "OnPressed", "gate", "Open")
	var container := _bake_brush_entities()
	var door := _make_target_entity(container, "gate")
	var relay := _make_entity(container, "relay")
	_add_connection(relay, "OnTrigger", "vault_button", "Unlock")
	var clocked = _wire_clocked_dispatcher(container)
	var body: Node = null
	for child in container.get_node("Nonstructural").get_children():
		if child is StaticBody3D:
			body = child
	assert_not_null(body, "the button bakes a body for the player's ray to hit")

	clocked.press_button(body)
	assert_eq(door.received_calls.size(), 0, "the lock the Entity panel set holds")
	dispatcher.fire("relay", "OnTrigger")
	clocked.press_button(body)
	assert_eq(door.received_calls.size(), 1, "until Unlock")


# ===========================================================================
# A brush entity's wires are the entity's, not each brush's (#1129)
# ===========================================================================


func test_a_wire_on_one_brush_of_a_trigger_fires_from_every_brush():
	# Only a volume holding a wire was connected, and a level wired before the
	# Entity panel put wires on every brush holds it on one.
	var first := _make_trigger_volume(scene_root, "hall", "trigger_once")
	var second := _make_trigger_volume(scene_root, "hall", "trigger_once")
	var door := _make_target_entity(scene_root, "gate")
	_add_connection(first, "OnStartTouch", "gate", "Open")
	_wire_clocked_dispatcher()

	second.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 1, "the brush without the wire is the same trigger")


func test_a_trigger_once_of_two_brushes_fires_once_in_all():
	var first := _make_trigger_volume(scene_root, "hall", "trigger_once")
	var second := _make_trigger_volume(scene_root, "hall", "trigger_once")
	var door := _make_target_entity(scene_root, "gate")
	for volume in [first, second]:
		_add_connection(volume, "OnStartTouch", "gate", "Open")
	_wire_clocked_dispatcher()

	first.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	second.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 1, "once, not once per brush")


func test_a_trigger_once_of_two_brushes_stays_fired_through_a_rewire():
	var first := _make_trigger_volume(scene_root, "hall", "trigger_once")
	var second := _make_trigger_volume(scene_root, "hall", "trigger_once")
	var door := _make_target_entity(scene_root, "gate")
	for volume in [first, second]:
		_add_connection(volume, "OnStartTouch", "gate", "Open")
	var clocked := _wire_clocked_dispatcher()

	first.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	clocked.wire()
	second.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 1, "a name is not an instance that goes away")


func test_a_wire_every_brush_of_a_trigger_holds_is_delivered_once():
	var first := _make_trigger_volume(scene_root, "hall", "trigger_multiple")
	var second := _make_trigger_volume(scene_root, "hall", "trigger_multiple")
	var door := _make_target_entity(scene_root, "gate")
	for volume in [first, second]:
		volume.set_meta("entity_data", {"wait": 0.0})
		_add_connection(volume, "OnStartTouch", "gate", "Open")
	_wire_clocked_dispatcher()

	first.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 1, "one entry, one delivery")


func test_a_fire_once_wire_every_brush_holds_fires_once():
	var first := _make_trigger_volume(scene_root, "hall", "trigger_multiple")
	var second := _make_trigger_volume(scene_root, "hall", "trigger_multiple")
	var door := _make_target_entity(scene_root, "gate")
	for volume in [first, second]:
		volume.set_meta("entity_data", {"wait": 0.0})
		_add_connection(volume, "OnStartTouch", "gate", "Open", "", 0.0, true)
	_wire_clocked_dispatcher()

	first.emit_signal("body_entered", autofree(CharacterBody3D.new()))
	second.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 1, "the wire fires once, whichever brush")


func test_two_wires_alike_on_one_brush_are_still_two():
	var volume := _make_trigger_volume(scene_root, "hall", "trigger_multiple")
	var door := _make_target_entity(scene_root, "gate")
	volume.set_meta("entity_data", {"wait": 0.0})
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	_add_connection(volume, "OnStartTouch", "gate", "Open")
	_wire_clocked_dispatcher()

	volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 2, "as they always were")


func test_a_button_of_two_brushes_with_the_wire_on_both_presses_once():
	var body := _make_button("vault_button", {"wait": 0.0}, "gate")
	_make_button("vault_button", {"wait": 0.0}, "gate")
	var door := _make_target_entity(scene_root, "gate")
	var clocked := _wire_clocked_dispatcher()

	clocked.press_button(body)

	assert_eq(door.received_calls.size(), 1, "one press, one delivery")


# ===========================================================================
# Brushes tied with no name are one entity too (#1133)
# ===========================================================================


## Tie fresh brushes with no name, and give every one of them `data`.
func _tie_unnamed(brush_ids: Array, entity_class: String, data: Dictionary = {}) -> Array:
	var brushes: Array = []
	for brush_id in brush_ids:
		brushes.append(_brush(brush_id))
	level.tie_brushes_to_entity(brush_ids, entity_class, "")
	for brush in brushes:
		for key in data:
			HFEntityPropUtils.set_entity_property(brush, key, data[key])
	return brushes


func _baked_of_type(container: Node3D, type_name: String) -> Array:
	return container.get_node("Nonstructural").get_children().filter(
		func(child): return child.is_class(type_name)
	)


func test_the_nodes_of_a_tie_with_no_name_carry_the_tie():
	# Each brush bakes answering to its own node name, so nothing else says the
	# volumes are one trigger.
	var brushes := _tie_unnamed(["u1", "u2"], "trigger_once")
	var group := str(brushes[0].get_meta("brush_entity_group", ""))
	var container := _bake_brush_entities()
	var volumes := _baked_of_type(container, "Area3D")
	assert_eq(volumes.size(), 2)
	for volume in volumes:
		assert_eq(str(volume.get_meta("brush_entity_group", "")), group, volume.name)


func test_a_named_tie_bakes_one_entity_by_its_name_alone():
	var first := _brush("n1")
	_brush("n2")
	level.tie_brushes_to_entity(["n1", "n2"], "trigger_once", "hall")
	assert_true(first.has_meta("brush_entity_group"), "the tie minted one")
	var container := _bake_brush_entities()
	for volume in _baked_of_type(container, "Area3D"):
		assert_false(volume.has_meta("brush_entity_group"), "the name already says it")


func test_an_unnamed_trigger_once_of_two_brushes_fires_once_in_all():
	var brushes := _tie_unnamed(["u1", "u2"], "trigger_once")
	level.add_entity_output(brushes[0], "OnStartTouch", "gate", "Open")
	var container := _bake_brush_entities()
	var door := _make_target_entity(container, "gate")
	_wire_clocked_dispatcher(container)

	for volume in _baked_of_type(container, "Area3D"):
		volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 1, "once, not once per brush")


func test_an_unnamed_trigger_multiple_delivers_once_per_entry():
	var brushes := _tie_unnamed(["u1", "u2"], "trigger_multiple", {"wait": 0.0})
	level.add_entity_output(brushes[0], "OnStartTouch", "gate", "Open")
	var container := _bake_brush_entities()
	var door := _make_target_entity(container, "gate")
	_wire_clocked_dispatcher(container)
	var volumes := _baked_of_type(container, "Area3D")

	volumes[1].emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 1, "the volume without the first copy still fires")
	volumes[0].emit_signal("body_entered", autofree(CharacterBody3D.new()))
	assert_eq(door.received_calls.size(), 2, "and each entry is one delivery")


func test_an_unnamed_trigger_multiple_waits_as_one_trigger():
	var brushes := _tie_unnamed(["u1", "u2"], "trigger_multiple", {"wait": 2.0})
	level.add_entity_output(brushes[0], "OnStartTouch", "gate", "Open")
	var container := _bake_brush_entities()
	var door := _make_target_entity(container, "gate")
	var clocked := _wire_clocked_dispatcher(container)
	var volumes := _baked_of_type(container, "Area3D")

	volumes[0].emit_signal("body_entered", autofree(CharacterBody3D.new()))
	clocked.now = 1.0
	volumes[1].emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 1, "the other brush is inside the same wait")


func test_two_unnamed_triggers_tied_separately_stay_two():
	var first := _tie_unnamed(["a1"], "trigger_once")
	var second := _tie_unnamed(["b1"], "trigger_once")
	level.add_entity_output(first[0], "OnStartTouch", "gate", "Open")
	level.add_entity_output(second[0], "OnStartTouch", "gate", "Open")
	var container := _bake_brush_entities()
	var door := _make_target_entity(container, "gate")
	_wire_clocked_dispatcher(container)

	for volume in _baked_of_type(container, "Area3D"):
		volume.emit_signal("body_entered", autofree(CharacterBody3D.new()))

	assert_eq(door.received_calls.size(), 2, "one each")


func test_an_unnamed_button_of_two_brushes_presses_as_one():
	var brushes := _tie_unnamed(["p1", "p2"], "func_button", {"wait": 1.0})
	level.add_entity_output(brushes[0], "OnPressed", "gate", "Open")
	var container := _bake_brush_entities()
	var door := _make_target_entity(container, "gate")
	var clocked := _wire_clocked_dispatcher(container)
	var bodies := _baked_of_type(container, "StaticBody3D")
	assert_eq(bodies.size(), 2)

	assert_true(clocked.press_button(bodies[1]), "the brush without the first copy")
	assert_eq(door.received_calls.size(), 1, "fires the wire once")
	clocked.now = 0.5
	assert_false(clocked.press_button(bodies[0]), "one button, one wait")
	clocked.now = 1.0
	clocked.press_button(bodies[0])
	assert_eq(door.received_calls.size(), 2)


# ===========================================================================
# A wait is measured in game time, as a door's is (#1136)
# ===========================================================================


func test_the_wait_clock_is_the_frame_time_the_dispatcher_is_handed():
	# It read the wall clock, while a door's wait is a `SceneTreeTimer`, which
	# `Engine.time_scale` slows down.
	_wire_dispatcher()
	dispatcher.set_process(false)
	var start := dispatcher._now()
	OS.delay_msec(50)
	assert_eq(dispatcher._now(), start, "no frame, no time")
	dispatcher._process(0.25)
	assert_almost_eq(dispatcher._now(), start + 0.25, 0.0001)


func test_the_wait_clock_runs_at_the_time_scale():
	_wire_dispatcher()
	var start := dispatcher._now()
	var wall_start := Time.get_ticks_usec()
	Engine.time_scale = 0.5
	await get_tree().create_timer(0.4, true, false, true).timeout
	Engine.time_scale = 1.0
	var wall := (Time.get_ticks_usec() - wall_start) / 1000000.0
	assert_almost_eq((dispatcher._now() - start) / wall, 0.5, 0.15, "half the wall clock")


func test_a_delayed_wire_waits_out_a_pause():
	# A `SceneTreeTimer` runs through a pause unless told otherwise, so a delayed
	# wire was delivered behind a pause menu (#1140).
	var relay := _make_entity(scene_root, "relay")
	var lamp := _make_target_entity(scene_root, "lamp")
	_add_connection(relay, "OnTrigger", "lamp", "Open", "", 0.1)
	_wire_dispatcher()
	get_tree().paused = true
	dispatcher.fire("relay", "OnTrigger")
	await get_tree().create_timer(0.3, true).timeout
	var while_paused: int = lamp.received_calls.size()
	get_tree().paused = false
	assert_eq(while_paused, 0, "not while paused")
	await get_tree().create_timer(0.3).timeout
	assert_eq(lamp.received_calls.size(), 1, "once play resumes")


# ===========================================================================
# A door raises OnOpen and OnClose as one door (#1145)
# ===========================================================================


func _baked_doors(container: Node3D) -> Array:
	return container.get_node("Nonstructural").get_children().filter(
		func(child): return child.has_method("open")
	)


func test_an_unnamed_door_fires_on_open_whichever_leaf_opens():
	# A wire every leaf holds is given to one of them, and a leaf raised only its
	# own wires, so the other leaf opened the door and nothing heard it.
	var leaves := _tie_unnamed(["d1", "d2"], "func_door", {"wait": 0.0})
	level.add_entity_output(leaves[0], "OnOpen", "lamp", "TurnOn")
	var container := _bake_brush_entities()
	var lamp := _make_target_entity(container, "lamp")
	_wire_clocked_dispatcher(container)
	var doors := _baked_doors(container)
	assert_eq(doors.size(), 2)

	doors[1].open()
	assert_eq(lamp.received_calls.size(), 1, "the leaf without the wire")
	doors[0].open()
	assert_eq(lamp.received_calls.size(), 1, "the door was open already")


func test_a_named_door_fires_on_open_once_for_both_leaves():
	_brush("g1")
	_brush("g2")
	level.tie_brushes_to_entity(["g1", "g2"], "func_door", "gate")
	level.add_entity_output(level.find_brush_by_id("g1"), "OnOpen", "lamp", "TurnOn")
	var container := _bake_brush_entities()
	var lamp := _make_target_entity(container, "lamp")
	var relay := _make_entity(container, "relay")
	_add_connection(relay, "OnTrigger", "gate", "Open")
	var clocked := _wire_clocked_dispatcher(container)
	assert_eq(_baked_doors(container).size(), 2)

	clocked.fire("relay", "OnTrigger")
	assert_eq(lamp.received_calls.size(), 1, "both leaves open, and the door opened once")


func test_a_door_fires_on_close_as_its_last_leaf_shuts():
	var leaves := _tie_unnamed(["d1", "d2"], "func_door", {"wait": 0.0})
	level.add_entity_output(leaves[0], "OnClose", "lamp", "TurnOn")
	var container := _bake_brush_entities()
	var lamp := _make_target_entity(container, "lamp")
	_wire_clocked_dispatcher(container)
	var doors := _baked_doors(container)

	doors[1].open()
	doors[1].close()
	assert_eq(lamp.received_calls.size(), 1, "the leaf without the wire")
	doors[0].open()
	doors[1].open()
	doors[0].close()
	assert_eq(lamp.received_calls.size(), 1, "the other leaf is still open")
	doors[1].close()
	assert_eq(lamp.received_calls.size(), 2, "and now the door is shut")


# ===========================================================================
# An address reaches the whole brush entity (#1149, #1150)
# ===========================================================================


## A point entity that sends `input_name` to `target_name` when it fires `OnTrigger`.
func _relay_to(container: Node3D, target_name: String, input_name: String) -> Node3D:
	var relay := _make_entity(container, "relay")
	_add_connection(relay, "OnTrigger", target_name, input_name)
	return relay


func _open_doors(container: Node3D) -> int:
	return _baked_doors(container).filter(func(door): return door.is_open()).size()


func _monitoring_volumes(container: Node3D) -> int:
	return _baked_of_type(container, "Area3D").filter(func(area): return area.monitoring).size()


func test_open_aimed_at_a_brush_of_a_named_door_opens_the_door():
	# The editor takes a brush's node name as an address of its entity, and the
	# target dropdown offered nothing else. The bake names the door's nodes after
	# the door, so nothing in the game answered to the brush's name.
	var first := _brush("g1")
	_brush("g2")
	level.tie_brushes_to_entity(["g1", "g2"], "func_door", "gate")
	var container := _bake_brush_entities()
	_relay_to(container, str(first.name), "Open")
	var clocked := _wire_clocked_dispatcher(container)

	clocked.fire("relay", "OnTrigger")
	assert_eq(_open_doors(container), 2, "both leaves of the door")


func test_disable_aimed_at_a_brush_of_a_named_trigger_switches_it_off():
	var first := _brush("h1")
	_brush("h2")
	level.tie_brushes_to_entity(["h1", "h2"], "trigger_multiple", "hall")
	var container := _bake_brush_entities()
	_relay_to(container, str(first.name), "Disable")
	var clocked := _wire_clocked_dispatcher(container)

	clocked.fire("relay", "OnTrigger")
	await get_tree().process_frame
	assert_eq(_monitoring_volumes(container), 0, "every volume of the trigger")


func test_open_aimed_at_one_leaf_of_an_unnamed_door_opens_both():
	var leaves := _tie_unnamed(["d1", "d2"], "func_door", {"wait": 0.0})
	var container := _bake_brush_entities()
	_relay_to(container, str(leaves[1].name), "Open")
	var clocked := _wire_clocked_dispatcher(container)

	clocked.fire("relay", "OnTrigger")
	assert_eq(_open_doors(container), 2, "one door, not one leaf of it")


func test_disable_aimed_at_one_brush_of_an_unnamed_trigger_switches_off_every_volume():
	var brushes := _tie_unnamed(["u1", "u2"], "trigger_multiple")
	var container := _bake_brush_entities()
	_relay_to(container, str(brushes[0].name), "Disable")
	var clocked := _wire_clocked_dispatcher(container)

	clocked.fire("relay", "OnTrigger")
	await get_tree().process_frame
	assert_eq(_monitoring_volumes(container), 0, "the whole trigger")


func test_press_aimed_at_one_brush_of_an_unnamed_button_presses_it_once():
	var brushes := _tie_unnamed(["p1", "p2"], "func_button", {"wait": 0.0})
	level.add_entity_output(brushes[0], "OnPressed", "gate", "Open")
	var container := _bake_brush_entities()
	var door := _make_target_entity(container, "gate")
	_relay_to(container, str(brushes[1].name), "Press")
	var clocked := _wire_clocked_dispatcher(container)

	clocked.fire("relay", "OnTrigger")
	assert_eq(door.received_calls.size(), 1, "one press, though four nodes make the button")


# ===========================================================================
# A zero-delay loop stops (#1218)
# ===========================================================================


## A target that raises its own output as its input arrives, the way a relay or
## a door does, so two of them wired to each other with no delay make a loop.
func _make_passing_entity(parent: Node3D, entity_name: String) -> Node:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var received := 0

func Trigger() -> void:
	received += 1
	HFIORuntime.fire_on(self, "OnTrigger")
"""
	s.reload()
	var e := Node3D.new()
	e.set_script(s)
	e.name = entity_name
	parent.add_child(e)
	return e


func test_two_entities_wired_to_each_other_with_no_delay_stop():
	var a := _make_passing_entity(scene_root, "A")
	var b := _make_passing_entity(scene_root, "B")
	_add_connection(a, "OnTrigger", "B", "Trigger")
	_add_connection(b, "OnTrigger", "A", "Trigger")
	_wire_dispatcher()
	dispatcher.fire("A", "OnTrigger")
	var hops: int = a.received + b.received
	assert_between(
		hops, 2, HFIORuntime.MAX_CHAIN, "the loop is stopped, not run until the stack is out"
	)
	assert_eq(dispatcher._loops_reported.size(), 1, "the loop is named")
	var named: String = dispatcher._loops_reported.keys()[0]
	assert_string_contains(named, "A.OnTrigger -> B.Trigger")
	assert_string_contains(named, "B.OnTrigger -> A.Trigger")
	dispatcher.fire("A", "OnTrigger")
	assert_eq(dispatcher._loops_reported.size(), 1, "and named once, however often it runs")
	assert_eq(a.received + b.received, 2 * hops, "each fire stops at the same place")


func test_a_loop_that_fans_out_stops_as_soon():
	var a := _make_passing_entity(scene_root, "A")
	var b := _make_passing_entity(scene_root, "B")
	var c := _make_passing_entity(scene_root, "C")
	_add_connection(a, "OnTrigger", "B", "Trigger")
	_add_connection(a, "OnTrigger", "C", "Trigger")
	_add_connection(b, "OnTrigger", "A", "Trigger")
	_add_connection(c, "OnTrigger", "A", "Trigger")
	_wire_dispatcher()
	dispatcher.fire("A", "OnTrigger")
	# Each A doubles what follows it, so stopping only the deepest wire would
	# still be two to the sixty-fourth deliveries. One stopped chain for each of
	# the two wires the fire started is all that runs.
	assert_lte(a.received + b.received + c.received, 2 * HFIORuntime.MAX_CHAIN)


func test_wires_after_a_stopped_loop_are_delivered():
	var a := _make_passing_entity(scene_root, "A")
	var b := _make_passing_entity(scene_root, "B")
	var button := _make_entity(scene_root, "Button1")
	var door := _make_target_entity(scene_root, "Door1")
	_add_connection(a, "OnTrigger", "B", "Trigger")
	_add_connection(b, "OnTrigger", "A", "Trigger")
	_add_connection(button, "OnPressed", "Door1", "Open")
	_wire_dispatcher()
	dispatcher.fire("A", "OnTrigger")
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(door.received_calls.size(), 1, "a stopped loop leaves the next fire alone")


func test_a_chain_of_zero_delay_wires_still_runs_in_one_frame_in_order():
	var button := _make_entity(scene_root, "Button1")
	var first := _make_passing_entity(scene_root, "R1")
	var second := _make_passing_entity(scene_root, "R2")
	_make_target_entity(scene_root, "Door1")
	_add_connection(button, "OnPressed", "R1", "Trigger")
	_add_connection(button, "OnPressed", "Door1", "Open", "last")
	_add_connection(first, "OnTrigger", "R2", "Trigger")
	_add_connection(second, "OnTrigger", "Door1", "Open", "chained")
	_wire_dispatcher()
	var order: Array = []
	dispatcher.io_received.connect(
		func(target: String, input: String, parameter: String):
			order.append("%s.%s(%s)" % [target, input, parameter])
	)
	var frame := Engine.get_process_frames()
	dispatcher.fire("Button1", "OnPressed")
	assert_eq(Engine.get_process_frames(), frame, "all in the frame the button fired in")
	assert_eq(
		order,
		["R1.Trigger()", "R2.Trigger()", "Door1.Open(chained)", "Door1.Open(last)"],
		"each wire's chain runs before the next wire"
	)
	assert_eq(dispatcher._loops_reported.size(), 0, "a chain is not a loop")
