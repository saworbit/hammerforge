@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## `HFIORuntime` -- the half of the entity I/O system that runs in the shipped
## game rather than in the editor.
##
## Everything it works from is authored data: `entity_io_outputs` metadata baked
## into the scene, target names typed into a dock field, input names that end up
## as method calls. None of it is validated between the editor and here, and a
## failure at runtime is a level that quietly does nothing rather than an error
## anyone sees. So: what does one bad entity do to the others, and what does an
## input name that happens to collide with a Godot method do to its target.

const IORuntime = preload("res://addons/hammerforge/hf_io_runtime.gd")


func id() -> String:
	return "runtime-io"


func summary() -> String:
	return "the runtime I/O dispatcher against malformed metadata and input names that collide with Node methods"


func run() -> void:
	await _one_bad_entity_among_good_ones()
	await _an_input_name_that_is_a_node_method()
	await _a_target_that_does_not_exist()


## A source, a dispatcher and a target under one parent.
func _stage() -> Node3D:
	var stage := Node3D.new()
	stage.name = "Stage"
	_tree.get_root().add_child(stage)
	await _tree.process_frame
	return stage


func _source(stage: Node3D, node_name: String, outputs: Variant) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.set_meta("entity_io_outputs", outputs)
	stage.add_child(node)
	return node


func _dispatcher(stage: Node3D) -> Node:
	var dispatcher = IORuntime.new()
	dispatcher.name = "HFIODispatcher"
	stage.add_child(dispatcher)
	return dispatcher


## `_collect_connections()` reads the metadata into a typed local:
##
##     var outputs: Array = node.get_meta("entity_io_outputs", [])
##
## A value of another type is a runtime error there, and GDScript unwinds the
## function -- including the recursion into the rest of the tree.
func _one_bad_entity_among_good_ones() -> void:
	var stage: Node3D = await _stage()
	# A sibling of the malformed entity, and a child of it. The recursion into
	# the rest of the tree happens at the end of _collect_connections(), after
	# the typed local that fails.
	var broken := _source(stage, "BrokenButton", "OnPressed")
	_source(
		stage,
		"GoodButton",
		[{"output_name": "OnPressed", "target_name": "Door", "input_name": "Open"}]
	)
	_source(
		broken,
		"NestedButton",
		[{"output_name": "OnPressed", "target_name": "Door", "input_name": "Open"}]
	)
	var door := Node3D.new()
	door.name = "Door"
	stage.add_child(door)
	var dispatcher := _dispatcher(stage)
	await frame()

	var wired: int = dispatcher._connections.size()
	var known_names: Array = dispatcher._source_name_to_ids.keys()
	note("sources wired with one malformed entity in the tree", wired)
	note("source names the dispatcher knows", known_names)
	if not known_names.has("NestedButton"):
		known(
			406,
			"an entity with malformed I/O metadata takes everything under it out of the wiring",
			(
				"a String where entity_io_outputs should be an Array is a runtime error in the"
				+ " typed local `var outputs: Array = node.get_meta(...)`, and GDScript unwinds"
				+ " _collect_connections() past the loop that recurses into the children."
				+ " NestedButton, one level down, is never scanned: %s. Siblings survive."
				% str(known_names)
			)
		)

	stage.queue_free()
	await frame()


## `_deliver_to_target()` calls the input name as a method on the target, and
## falls back to a snake_case spelling of it. Both are looked up with
## `has_method()` on the node itself, so anything `Node` implements is fair game.
func _an_input_name_that_is_a_node_method() -> void:
	var stage: Node3D = await _stage()
	var target := Node3D.new()
	target.name = "Door"
	stage.add_child(target)
	_source(
		stage,
		"Trap",
		[{"output_name": "OnTrigger", "target_name": "Door", "input_name": "QueueFree"}]
	)
	var dispatcher := _dispatcher(stage)
	await frame()

	dispatcher.fire("Trap", "OnTrigger")
	await frame()
	await frame()
	var alive := is_instance_valid(target) and not target.is_queued_for_deletion()
	note("target still alive after an input called QueueFree", alive)
	if not alive:
		known(
			407,
			"an I/O input name that matches a Node method calls the engine method",
			(
				"_deliver_to_target() tries target.call(input_name) and then the snake_case"
				+ " spelling, with no allowlist -- an input named QueueFree (or Free, Hide,"
				+ " SetScript, Replace_By) reaches Node's own method and deletes the target at"
				+ " runtime. Nothing in the editor warns when an input is named one of these."
			)
		)

	stage.queue_free()
	await frame()


## The ordinary authoring mistake: the target name is misspelt.
func _a_target_that_does_not_exist() -> void:
	var stage: Node3D = await _stage()
	_source(
		stage,
		"Button",
		[{"output_name": "OnPressed", "target_name": "Dorr", "input_name": "Open"}]
	)
	var door := Node3D.new()
	door.name = "Door"
	stage.add_child(door)
	var dispatcher := _dispatcher(stage)
	await frame()

	var received := []
	dispatcher.io_received.connect(func(t, i, p): received.append([t, i, p]))
	dispatcher.fire("Button", "OnPressed")
	await frame()
	note("deliveries to a misspelt target", received.size())
	note(
		"debug_logging is what gates the only warning",
		dispatcher.debug_logging
	)

	stage.queue_free()
	await frame()
