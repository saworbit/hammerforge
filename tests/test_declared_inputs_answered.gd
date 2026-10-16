extends GutTest

## A class's inputs do something in a game.
##
## `logic_relay` declares Trigger and the three lights declare TurnOn, TurnOff and
## Toggle, and nothing in the addon answered any of them: the wire was delivered
## and only a user signal nobody listened for went out. The reference map's
## button reaches its door through a relay, so that door could not be opened in a
## game (#1209).

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")

## Classes left out of the every-input check, with the reason.
const NOT_ANSWERED := {
	# Placed from the palette it is a point entity, which ships as a marker with
	# no door to move. Tied to brushes it bakes into a door and is answered.
	"door_basic": "#1232",
}

var root: Node3D


func before_each():
	root = LevelRootScript.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.grid_snap = 1.0
	add_child(root)


func after_each():
	root.free()
	root = null


func _place(entity_class: String, entity_name: String, data: Dictionary = {}) -> DraftEntity:
	var entity: DraftEntity = root._create_entity_from_map(
		{"classname": entity_class, "origin": Vector3.ZERO}
	)
	entity.name = entity_name
	for key in data:
		entity.entity_data[key] = data[key]
	return entity


func _box(center: Vector3, entity_class: String, entity_name: String) -> Node:
	var brush = root.brush_system.create_brush_from_info(
		{"shape": 0, "size": Vector3(1, 2, 1), "center": center}
	)
	root.tie_brushes_to_entity([str(brush.brush_id)], entity_class, entity_name)
	return brush


func _game_scene(file_name: String) -> Node:
	assert_true(await root.bake(), "the bake succeeds")
	var path := "user://%s" % file_name
	assert_true(root.export_game_scene(path), "the export has to succeed")
	var packed: PackedScene = ResourceLoader.load(path)
	DirAccess.remove_absolute(path)
	var scene: Node = packed.instantiate()
	add_child_autoqfree(scene)
	return scene


func _dispatcher(scene: Node) -> HFIORuntime:
	var io := scene.get_node_or_null("HFIODispatcher") as HFIORuntime
	assert_not_null(io, "fixture: a wired level gets a dispatcher")
	return io


func _find(node: Node, pick: Callable) -> Array:
	var out: Array = []
	if pick.call(node):
		out.append(node)
	for child in node.get_children():
		out.append_array(_find(child, pick))
	return out


# ---------------------------------------------------------------------------
# logic_relay
# ---------------------------------------------------------------------------


func _relay_to_lamp(relay_data: Dictionary) -> Dictionary:
	var first := _place("logic_relay", "first")
	var relay := _place("logic_relay", "relay", relay_data)
	_place("light_point", "lamp")
	root.add_entity_output(first, "OnTrigger", "relay", "Trigger")
	root.add_entity_output(relay, "OnTrigger", "lamp", "Toggle")
	var scene: Node = await _game_scene("hf_test_relay_%d.tscn" % relay_data.size())
	return {"io": _dispatcher(scene), "lamp": scene.get_node_or_null("lamp")}


func test_a_relay_passes_trigger_on_as_its_on_trigger():
	var got: Dictionary = await _relay_to_lamp({})
	var lamp := got["lamp"] as Light3D
	assert_not_null(lamp, "fixture: the lamp exports as a light")
	if got["io"] == null or lamp == null:
		return
	(got["io"] as HFIORuntime).fire("first", "OnTrigger")
	assert_false(lamp.visible, "the relay should pass Trigger on, and the lamp toggle off")


func test_a_relay_passes_every_trigger_on():
	var got: Dictionary = await _relay_to_lamp({"once": false})
	var lamp := got["lamp"] as Light3D
	if got["io"] == null or lamp == null:
		return
	(got["io"] as HFIORuntime).fire("first", "OnTrigger")
	(got["io"] as HFIORuntime).fire("first", "OnTrigger")
	assert_true(lamp.visible, "two Triggers toggle the lamp off and on again")


func test_a_relay_set_to_fire_once_passes_the_first_trigger_and_no_other():
	var got: Dictionary = await _relay_to_lamp({"once": true})
	var lamp := got["lamp"] as Light3D
	if got["io"] == null or lamp == null:
		return
	var io := got["io"] as HFIORuntime
	io.fire("first", "OnTrigger")
	io.fire("first", "OnTrigger")
	assert_false(lamp.visible, "Fire Once passes the first Trigger only")
	io.wire()
	io.fire("first", "OnTrigger")
	assert_false(lamp.visible, "and stays fired when the dispatcher wires again")


func test_a_button_opens_a_door_through_a_relay():
	# The reference map's shape: the button triggers the relay, and the relay
	# opens the door after a short delay.
	var button = _box(Vector3(-4, 1, 0), "func_button", "door_button")
	_box(Vector3(4, 1, 0), "func_door", "west_door")
	var relay := _place("logic_relay", "door_relay")
	root.add_entity_output(button, "OnPressed", "door_relay", "Trigger", "", 0.0, false)
	root.add_entity_output(relay, "OnTrigger", "west_door", "Open", "", 0.05, false)
	var scene: Node = await _game_scene("hf_test_relay_door.tscn")
	var io := _dispatcher(scene)
	var buttons := _find(scene, func(n): return n.get_meta("entity_name", "") == "door_button")
	var doors := _find(scene, func(n): return n.has_method("is_open"))
	assert_false(buttons.is_empty(), "fixture: the button is baked")
	assert_eq(doors.size(), 1, "fixture: the door is baked into one mover")
	if io == null or buttons.is_empty() or doors.size() != 1:
		return
	assert_true(io.press_button(buttons[0]), "the press goes through")
	await wait_seconds(0.2)
	assert_true(doors[0].is_open(), "the relay should pass the press on and open the door")


# ---------------------------------------------------------------------------
# Lights
# ---------------------------------------------------------------------------


func test_each_light_class_turns_off_on_and_toggles():
	for entity_class in ["light_point", "light_spot", "light_directional"]:
		_place(entity_class, entity_class)
	# A level gets a dispatcher when something in it is wired.
	_place("logic_relay", "wired")
	root.add_entity_output(
		root.entities_node.get_node("wired"), "OnTrigger", "light_point", "TurnOn"
	)
	var scene: Node = await _game_scene("hf_test_light_inputs.tscn")
	var io := _dispatcher(scene)
	if io == null:
		return
	for entity_class in ["light_point", "light_spot", "light_directional"]:
		var light := scene.get_node_or_null(entity_class) as Light3D
		assert_not_null(light, "fixture: %s exports as a light" % entity_class)
		if light == null:
			continue
		io._deliver("test", "Out", entity_class, "TurnOff", "")
		assert_false(light.visible, "%s goes out on TurnOff" % entity_class)
		io._deliver("test", "Out", entity_class, "TurnOn", "")
		assert_true(light.visible, "%s comes on on TurnOn" % entity_class)
		io._deliver("test", "Out", entity_class, "Toggle", "")
		assert_false(light.visible, "%s toggles off" % entity_class)
		io._deliver("test", "Out", entity_class, "Toggle", "")
		assert_true(light.visible, "%s toggles on" % entity_class)


# ---------------------------------------------------------------------------
# Every class
# ---------------------------------------------------------------------------


func test_every_input_a_class_declares_is_answered_in_a_game():
	var definitions: Dictionary = root.get_entity_definitions()
	var classes: Array = []
	var x := 0.0
	for entity_class in definitions:
		var definition: Dictionary = definitions[entity_class]
		var inputs: Array = definition.get("inputs", [])
		if inputs.is_empty() or NOT_ANSWERED.has(entity_class):
			continue
		classes.append(entity_class)
		if str(definition.get("class", "")) == "":
			_box(Vector3(x, 1, 10), entity_class, "the_%s" % entity_class)
		else:
			_place(entity_class, "the_%s" % entity_class)
		x += 3.0
	assert_true(classes.size() >= 8, "fixture: the shipped classes with inputs are all here")
	# A level gets a dispatcher when something in it is wired.
	var wired := _place("logic_relay", "wired")
	root.add_entity_output(wired, "OnTrigger", "the_logic_relay", "Trigger")
	var scene: Node = await _game_scene("hf_test_declared_inputs.tscn")
	var io := _dispatcher(scene)
	if io == null:
		return
	for entity_class in classes:
		var address := "the_%s" % entity_class
		var nodes := _find(
			scene, func(n): return n.name == address or n.get_meta("entity_name", "") == address
		)
		assert_false(nodes.is_empty(), "fixture: %s is in the game" % entity_class)
		for input_name in definitions[entity_class].get("inputs", []):
			var answered := false
			for node in nodes:
				answered = io._deliver_to_target(node, str(input_name), "", {}) or answered
			assert_true(answered, "%s answers %s, which it declares" % [entity_class, input_name])
