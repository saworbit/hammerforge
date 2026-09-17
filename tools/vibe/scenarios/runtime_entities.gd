@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The entity classes a game is built out of, driven the way the game drives them.
##
## `entities` covers naming and wiring in the editor. `brush-entities` covers
## what a brush tied to an entity class saves and exports. Neither one presses
## the button. This scenario bakes a level with a trigger volume, a button and a
## door wired together, then does what the player does: walk into the volume,
## fire the button, open the door. Every one of those is a promise the shipped
## `entities.json` makes in its own `description` field.


func id() -> String:
	return "runtime-entities"


func summary() -> String:
	return "whether a trigger, a button and a door do at runtime what their definitions promise"


func run() -> void:
	await _what_the_definitions_promise()
	await _does_a_trigger_volume_fire()
	await _does_a_door_move()
	await _what_a_light_entity_is_in_the_level()


func _defs() -> Dictionary:
	var f := FileAccess.open("res://addons/hammerforge/entities.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


## Every shipped class whose description tells the mapper it does something by
## itself, against whether anything in the addon implements it.
func _what_the_definitions_promise() -> void:
	var defs := _defs()
	var promising: Array = []
	for key in defs:
		var desc := str(defs[key].get("description", ""))
		var low := desc.to_lower()
		if (
			low.contains("fires")
			or low.contains("moves")
			or low.contains("presses")
			or low.contains("player")
		):
			promising.append("%s: %s" % [key, desc])
	note("classes whose description promises runtime behaviour", promising)
	# The only script in the addon that runs inside a built game.
	var src := FileAccess.open("res://addons/hammerforge/hf_io_runtime.gd", FileAccess.READ)
	var text := src.get_as_text() if src else ""
	if src:
		src.close()
	var hooks: Dictionary = {}
	for hook in ["body_entered", "area_entered", "input_event", "_physics_process", "mouse_entered"]:
		hooks[hook] = text.contains(hook)
	note("physics or input hooks HFIORuntime mentions", hooks)


func _build_wired_level(root: Node3D) -> void:
	root.auto_spawn_player = false
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	var trigger = box(root, Vector3(2, 2, 2), Vector3(-3, 1, 0))
	var button = box(root, Vector3(0.4, 0.4, 0.2), Vector3(3, 1.2, 0))
	var door = box(root, Vector3(0.2, 2.2, 1.6), Vector3(0, 1.1, 4))
	await frame()
	root.tie_brushes_to_entity([str(trigger.brush_id)], "trigger_once", "front_trigger")
	root.tie_brushes_to_entity([str(button.brush_id)], "func_button", "gate_button")
	root.tie_brushes_to_entity([str(door.brush_id)], "func_door", "gate")
	await frame()
	# Wire them the way the I/O panel would.
	root.add_entity_output(trigger, "OnStartTouch", "gate", "Open")
	root.add_entity_output(button, "OnPressed", "gate", "Open")
	root.bake_wire_io = true


func _find(node: Node, pred: Callable, out: Array) -> Array:
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		_find(c, pred, out)
	return out


func _does_a_trigger_volume_fire() -> void:
	var root: Node3D = await fresh_root()
	await _build_wired_level(root)
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	if container == null:
		flag("runtime-entities: nothing baked")
		return
	var areas: Array = _find(container, func(n: Node) -> bool: return n is Area3D, [])
	note("Area3D volumes in the baked container", areas.map(func(a: Node) -> String: return a.name))
	if areas.is_empty():
		flag("a trigger_once brush baked no Area3D", "nothing the player can walk into")
		return
	var area: Area3D = areas[0]
	note("trigger monitoring", area.monitoring)
	var connected: int = area.get_signal_connection_list("body_entered").size()
	note("things connected to the trigger's body_entered", connected)
	var dispatcher: Node = container.get_node_or_null("HFIODispatcher")
	note("dispatcher attached", dispatcher != null)
	if dispatcher == null:
		flag("bake_wire_io on produced no HFIODispatcher")
		return

	# Walk in. A CharacterBody3D is what the plugin's own playtest spawns.
	var body := CharacterBody3D.new()
	var body_shape := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(0.7, 1.6, 0.7)
	body_shape.shape = s
	body.add_child(body_shape)
	root.add_child(body)
	body.global_position = area.global_position
	for _i in 6:
		await frame()
	note("bodies overlapping the trigger after walking in", area.get_overlapping_bodies().size())
	if connected == 0:
		flag(
			"nothing connects a baked trigger volume to its own output",
			(
				"trigger_once says 'A volume that fires the first time the player enters it'. "
				+ "The bake makes a monitoring Area3D carrying entity_io_outputs, and "
				+ "HFIORuntime wires OnStartTouch -> gate.Open, but nothing ever calls fire(). "
				+ "No body_entered handler exists anywhere in the addon, so walking in does "
				+ "nothing and the whole I/O graph a mapper builds in the panel is inert."
			)
		)
	body.queue_free()
	await frame()


func _does_a_door_move() -> void:
	var root: Node3D = await fresh_root()
	await _build_wired_level(root)
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	if container == null:
		return
	var gates: Array = _find(
		container, func(n: Node) -> bool: return str(n.name).begins_with("gate"), []
	)
	note(
		"nodes the runtime can find under the name 'gate'",
		gates.map(func(n: Node) -> String: return "%s (%s)" % [n.name, n.get_class()])
	)
	var dispatcher: Node = container.get_node_or_null("HFIODispatcher")
	if dispatcher == null:
		return
	var door: Node3D = null
	for g in gates:
		if g is Node3D:
			door = g
			break
	if door == null:
		flag("the func_door baked no node at all")
		return
	var before: Transform3D = door.global_transform
	dispatcher.call("fire", "front_trigger", "OnStartTouch", "")
	for _i in 10:
		await frame()
	var after: Transform3D = door.global_transform
	note("door transform before Open", before)
	note("door transform after Open", after)
	if before.is_equal_approx(after):
		flag(
			"firing Open on a func_door moves nothing",
			(
				"func_door's own description is 'Geometry that moves when opened.' and it "
				+ "ships speed, wait and angle properties. HFIORuntime's _deliver_to_target "
				+ "falls through to emit_signal on a MeshInstance3D with no script, so the "
				+ "three properties are authored, saved, exported and read by nothing."
			)
		)


func _what_a_light_entity_is_in_the_level() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	var info := {
		"entity_type": "light_point",
		"entity_class": "light_point",
		"transform": Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)),
		"properties": {},
		"name": "lamp",
		"entity_name": "lamp",
	}
	var lamp = root._restore_entity_from_info(info)
	if lamp == null:
		note("could not place a light_point", true)
		return
	note("light_point in the edited level", "%s (%s)" % [lamp.name, lamp.get_class()])
	var lights: Array = _find(root, func(n: Node) -> bool: return n is Light3D, [])
	note("Light3D nodes anywhere in the edited level", lights.size())
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	var baked_lights: Array = (
		_find(container, func(n: Node) -> bool: return n is Light3D, []) if container else []
	)
	note("Light3D nodes in the baked container", baked_lights.size())
	if lights.is_empty() and baked_lights.is_empty():
		note(
			"a light entity is a Node3D everywhere except the playtest export",
			(
				"export_playtest_scene() is the only path that turns light_point into an "
				+ "OmniLight3D, so a level used directly as a game scene, or a level baked "
				+ "and shipped, is unlit"
			)
		)
