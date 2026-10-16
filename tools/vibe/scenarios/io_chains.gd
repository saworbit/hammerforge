@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Wires at runtime: what a chain of them does in the game.
##
## `runtime-io` feeds the dispatcher malformed metadata and `runtime-entities`
## settles that one trigger opens one door. This one builds the graphs a mapper
## actually draws -- a button through a relay to a door (the reference map's own
## shape), a timer, triggers of both kinds, lights and a sound on the end of a
## wire, the built-in connection presets applied the way the panel applies them,
## loops, self-wires, delays, fire-once wires, a target that is not there, two
## targets with one name, and one level loaded twice -- and runs them the way a
## game does: baked, exported with `export_game_scene()`, the editing root taken
## out of the tree, the scene loaded back and instanced.
##
## What is measured is what the far end of each wire did, not what the
## dispatcher said it delivered. `io_received` is recorded too, so a wire that
## was delivered and ignored can be told from one that never went out.

const DoorRuntime = preload("res://addons/hammerforge/hf_door_runtime.gd")
const MapIOScript = preload("res://addons/hammerforge/map_io.gd")
const IORuntime = preload("res://addons/hammerforge/hf_io_runtime.gd")

const LEAF := Vector3(0.2, 2.2, 1.6)

var _written: Array[String] = []
var _scenes: Array[Node] = []
var _events: Array = []


func id() -> String:
	return "io-chains"


func summary() -> String:
	return "wires at runtime: loops, self-wires, delays, relays, timers, fire counts and Kill"


func run() -> void:
	await _what_the_library_promises()
	await _relay_chain()
	await _lights_and_sound()
	await _built_in_presets()
	await _timers()
	await _triggers_and_wires()
	await _loops_and_self_wires()
	await _one_level_loaded_twice()
	await _cleanup()


# ---------------------------------------------------------------------------
# Scaffolding
# ---------------------------------------------------------------------------


func _ship(root: Node3D, tag: String) -> Node3D:
	var path := await _export(root, tag)
	if path == "":
		return null
	return await _instance(path)


## Bake, export as a game scene, and take the editing root out of the tree.
func _export(root: Node3D, tag: String) -> String:
	await root.bake(false, false)
	await frame()
	var path := "user://io-chains_%s.tscn" % tag
	var ok: bool = root.export_game_scene(path)
	_written.append(path)
	await drop_root(root)
	if not ok:
		flag("export_game_scene refused the level for case '%s'" % tag)
		return ""
	return path


func _instance(path: String, offset: Vector3 = Vector3.ZERO) -> Node3D:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if not (packed is PackedScene):
		flag("the exported game scene %s did not load back" % path)
		return null
	var scene := (packed as PackedScene).instantiate() as Node3D
	scene.position = offset
	_tree.get_root().add_child(scene)
	_scenes.append(scene)
	await frame()
	await frame()
	return scene


func _unship(scene: Node) -> void:
	if is_instance_valid(scene):
		_scenes.erase(scene)
		var parent := scene.get_parent()
		if parent:
			parent.remove_child(scene)
		scene.queue_free()
	await frame()


func _find(node: Node, pred: Callable, out: Array) -> Array:
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		_find(c, pred, out)
	return out


## Every node answering to an authored name.
func _named(scene: Node, wanted: String) -> Array:
	return _find(
		scene, func(n: Node) -> bool: return str(n.get_meta("entity_name", "")) == wanted, []
	)


func _first_named(scene: Node, wanted: String, cls: String = "") -> Node:
	for n in _named(scene, wanted):
		if cls == "" or (n as Node).is_class(cls):
			return n
	return null


func _door_of(scene: Node, wanted: String) -> Node3D:
	for n in _named(scene, wanted):
		if n.get_script() == DoorRuntime:
			return n
	return null


func _point(
	root: Node3D, cls: String, entity_name: String, pos: Vector3, props: Dictionary, basis: Basis
) -> Node3D:
	return (
		root
		. _restore_entity_from_info(
			{
				"entity_type": cls,
				"transform": Transform3D(basis, pos),
				"properties": props.duplicate(),
				"name": entity_name,
				"entity_name": entity_name,
			}
		)
	)


func _brush_entity(
	root: Node3D, cls: String, entity_name: String, size: Vector3, centre: Vector3
) -> Node:
	var b = box(root, size, centre)
	await frame()
	root.tie_brushes_to_entity([str(b.brush_id)], cls, entity_name)
	return b


func _listen(scene: Node) -> Node:
	_events.clear()
	var dispatcher: Node = scene.get_node_or_null("HFIODispatcher") if scene else null
	if dispatcher == null:
		return null
	dispatcher.connect(
		"io_received",
		func(target: String, input: String, param: String) -> void:
			(
				_events
				. append(
					{
						"target": target,
						"input": input,
						"param": param,
						"ms": Time.get_ticks_msec(),
						"frame": Engine.get_process_frames(),
					}
				)
			)
	)
	return dispatcher


func _count(target: String, input: String = "", param: Variant = null) -> int:
	var n := 0
	for e in _events:
		if e["target"] != target:
			continue
		if input != "" and e["input"] != input:
			continue
		if param != null and e["param"] != str(param):
			continue
		n += 1
	return n


func _seconds(s: float) -> void:
	await _tree.create_timer(s).timeout


func _settle(door: Node, cap_seconds: float = 6.0) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(cap_seconds * 1000.0):
		var tween = door.get("_tween")
		if tween == null or not (tween as Tween).is_valid() or not (tween as Tween).is_running():
			break
		await frame()
	await frame()


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _wire_text(c: Dictionary) -> String:
	return "%s -> %s.%s" % [c["output_name"], c["target_name"], c["input_name"]]


func _light_state(light: Node) -> String:
	if light == null:
		return "missing"
	if not (light is Light3D):
		return "%s (not a Light3D)" % light.get_class()
	return (
		"%s visible=%s energy=%.2f"
		% [light.get_class(), (light as Light3D).visible, (light as Light3D).light_energy]
	)


func _body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	cs.shape = cap
	body.add_child(cs)
	_tree.get_root().add_child(body)
	_scenes.append(body)
	body.global_position = Vector3(0, 50, 0)
	return body


func _walk(body: CharacterBody3D, to: Vector3) -> void:
	body.global_position = to
	for _i in 4:
		await _tree.physics_frame


# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------


## Every class's description and declared I/O, against what the runtime can do
## with each: an input it can deliver to something that acts on it, and an
## output something raises. Static, from `entities.json` and the dispatcher's
## own tables; the cases below run the ones that matter.
func _what_the_library_promises() -> void:
	var f := FileAccess.open("res://addons/hammerforge/entities.json", FileAccess.READ)
	var defs: Variant = JSON.parse_string(f.get_as_text()) if f else null
	if f:
		f.close()
	if not (defs is Dictionary):
		flag("entities.json did not parse")
		return
	# What answers an input with no script on the node: the class's
	# `input_methods`, the brush entity branches in `_deliver_to_target()` (3b and
	# 3c), and the door script. What raises an output: CLASS_SIGNAL_OUTPUTS, the
	# class's `output_signals`, the door script and `press_button()`.
	var handled_in := {
		"trigger_once": ["Enable", "Disable"],
		"trigger_multiple": ["Enable", "Disable"],
		"func_wall": ["Enable", "Disable"],
		"func_button": ["Press", "Lock", "Unlock"],
		"func_door": ["Open", "Close", "Toggle", "Lock", "Unlock"],
	}
	var raised_out := {
		"trigger_once": ["OnStartTouch", "OnEndTouch"],
		"trigger_multiple": ["OnStartTouch", "OnEndTouch"],
		"func_door": ["OnOpen", "OnClose"],
		"func_button": ["OnPressed"],
	}
	var dead_in: Array = []
	var dead_out: Array = []
	var rows: Array = []
	for key in defs:
		var d: Dictionary = defs[key]
		var granted: Dictionary = d.get("input_methods", {})
		var signals: Dictionary = d.get("output_signals", {})
		for input_name in d.get("inputs", []):
			if granted.has(input_name) or str(input_name) in handled_in.get(key, []):
				continue
			dead_in.append("%s.%s" % [key, input_name])
		for output_name in d.get("outputs", []):
			if str(output_name) in raised_out.get(key, []) or signals.values().has(output_name):
				continue
			dead_out.append("%s.%s" % [key, output_name])
		rows.append("%s: %s" % [key, d.get("description", "(no description)")])
	note("every class's description", rows)
	note(
		"declared inputs nothing in the addon acts on (only the io_<Input> user signal goes out)",
		dead_in
	)
	note("declared outputs nothing in the addon raises", dead_out)
	note(
		"door_basic",
		(
			"a door_basic tied to brushes gets the door script (MOVER_CLASSES), so Open, Close, "
			+ "Toggle, Lock and Unlock work there; as a point entity it ships as its marker and "
			+ "none of them does (see door-motion). Its OnTrigger is raised by nothing either way."
		)
	)
	note(
		"player_start.OnSpawn",
		"raised by nothing; the guide leaves outputs that depend on the game to the game, and a spawn is the game's"
	)
	note(
		"info_target",
		(
			"'A named point for something else to aim at or move to.' Nothing shipped aims at or "
			+ "moves to anything -- func_door slides by angle -- so it is a name for game code to "
			+ "look up. It exports as its marker, a Node3D carrying entity_name, which is enough."
		)
	)
	# The times-to-fire field of a Source-style wire, as the .map reader takes it.
	var three: Dictionary = MapIOScript.parse_connection("OnTrigger", "door,Open,,0,3")
	var once: Dictionary = MapIOScript.parse_connection("OnTrigger", "door,Open,,0,1")
	var neg: Dictionary = MapIOScript.parse_connection("OnTrigger", "door,Open,,-2,-1")
	note(
		"a .map wire's fifth field (times to fire)",
		(
			(
				"'1' -> fire_once %s; '3' -> fire_once %s (unlimited); delay '-2' -> %s, which the "
				+ "dispatcher delivers at once (`delay > 0.0` is false). add_entity_output() refuses a "
				+ "negative or non-finite delay, so only an import or a hand edit gets one."
			)
			% [once.get("fire_once"), three.get("fire_once"), neg.get("delay")]
		)
	)


## The reference map's chain, rebuilt: a button wired to a `logic_relay`, the
## relay wired to a door with a 0.25 s delay. `logic_relay` says it "Fans one
## input out to several outputs, so one wire can drive many": Trigger in,
## OnTrigger out.
func _relay_chain() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	var button = await _brush_entity(
		root, "func_button", "door_button", Vector3(0.3, 0.3, 0.3), Vector3(3, 1.15, 2)
	)
	var door = await _brush_entity(
		root, "func_door", "west_door", LEAF, Vector3(-3, LEAF.y * 0.5, 0)
	)
	root.set_entity_property(door, "wait", 0.0)
	var relay := _point(root, "logic_relay", "door_relay", Vector3(0, 1, 2), {}, Basis.IDENTITY)
	var relay_a := _point(root, "logic_relay", "relay_a", Vector3(1, 1, 2), {}, Basis.IDENTITY)
	var relay_b := _point(root, "logic_relay", "relay_b", Vector3(2, 1, 2), {}, Basis.IDENTITY)
	await frame()
	root.add_entity_output(button, "OnPressed", "door_relay", "Trigger", "", 0.0, false)
	root.add_entity_output(relay, "OnTrigger", "west_door", "Open", "", 0.25, false)
	# A to B to A, no delay.
	root.add_entity_output(relay_a, "OnTrigger", "relay_b", "Trigger", "", 0.0, false)
	root.add_entity_output(relay_b, "OnTrigger", "relay_a", "Trigger", "", 0.0, false)
	var scene := await _ship(root, "relay")
	var dispatcher := _listen(scene)
	if dispatcher == null:
		flag("the relay level shipped no dispatcher")
		await _unship(scene)
		return
	var relay_node: Node = _first_named(scene, "door_relay")
	note(
		"the shipped logic_relay",
		(
			"%s, script %s, has _on_io_input %s"
			% [
				relay_node.get_class() if relay_node else "missing",
				(
					relay_node.get_script().resource_path.get_file()
					if relay_node and relay_node.get_script()
					else "none"
				),
				relay_node.has_method("_on_io_input") if relay_node else false
			]
		)
	)
	var west: Node3D = _door_of(scene, "west_door")
	var origin: Vector3 = west.global_position if west else Vector3.ZERO
	var answering: Array = (dispatcher.get("_entity_cache") as Dictionary).get("west_door", [])
	note(
		"nodes the dispatcher delivers a west_door input to",
		(
			(
				"%s -- the holder acts on it; the collision body keeps the entity_name the bake gave "
				+ 'it (hf_bake_system.gd, `body.set_meta("entity_name", authored)`), which '
				+ "_make_it_a_door() moves off the mesh but not off the body, so every door input is "
				+ "delivered twice and io_received fires twice. Harmless to the door; a game counting "
				+ "io_received sees double. Not flagged."
			)
			% [answering.map(func(n: Node) -> String: return n.get_class())]
		)
	)
	var press_node: Node = _first_named(scene, "door_button")
	var pressed: bool = dispatcher.call("press_button", press_node) if press_node else false
	await _seconds(0.25 + 1.2)
	var moved_by_press := (west.global_position - origin).length() if west else -1.0
	var relay_got := _count("door_relay", "Trigger")
	var door_got_after_press := _count("west_door", "Open")
	note("press_button(door_button) returned", pressed)
	note(
		"inputs delivered after the press",
		_events.map(func(e) -> String: return "%s.%s" % [e["target"], e["input"]])
	)
	note("west_door moved after the press", "%.3f m" % moved_by_press)

	# The second half of the chain on its own: raise the relay's output by hand.
	dispatcher.call("fire", "door_relay", "OnTrigger", "")
	await _seconds(0.25 + 1.2)
	var moved_by_hand := (west.global_position - origin).length() if west else -1.0
	note("west_door moved after fire('door_relay', 'OnTrigger') by hand", "%.3f m" % moved_by_hand)

	# A to B to A with no delay.
	_events.clear()
	var frame_before := Engine.get_process_frames()
	dispatcher.call("fire", "relay_a", "OnTrigger", "")
	note(
		"relay_a -> relay_b -> relay_a, zero delay, one fire()",
		(
			"%d input(s) delivered, %d frame(s) passed"
			% [_events.size(), Engine.get_process_frames() - frame_before]
		)
	)

	# #1209: the relay passes Trigger on, so the press opens the door.
	if relay_got > 0 and door_got_after_press == 0 and moved_by_press < 0.01:
		flag(
			"a button wired through a logic_relay to a door does nothing in the game again (#1209)",
			(
				"press_button() returned %s, the relay received Trigger (%d), west_door moved %.3f m"
				% [pressed, relay_got, moved_by_press]
			)
		)
	await _unship(scene)


## Lights and a sound on the end of a wire, each fed the inputs its own class
## declares. `light_point`, `light_spot` and `light_directional` all declare
## TurnOn, TurnOff and Toggle; `ambient_sound` declares Play and Stop and grants
## them to the engine methods through `input_methods`.
func _lights_and_sound() -> void:
	var tone_path := "user://io-chains_tone.tres"
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	var pcm := PackedByteArray()
	pcm.resize(16000)
	wav.data = pcm
	ResourceSaver.save(wav, tone_path)
	_written.append(tone_path)

	var root: Node3D = await fresh_root()
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	var off_btn = await _brush_entity(
		root, "func_button", "lights_off", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 0)
	)
	var tog_btn = await _brush_entity(
		root, "func_button", "lights_toggle", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 1)
	)
	var on_btn = await _brush_entity(
		root, "func_button", "lights_on", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 2)
	)
	var snd_btn = await _brush_entity(
		root, "func_button", "radio_btn", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 3)
	)
	var aim := Basis(Vector3.RIGHT, deg_to_rad(-60.0)) * Basis(Vector3.UP, deg_to_rad(30.0))
	var marker_spot := _point(root, "light_spot", "spot", Vector3(0, 3, 0), {}, aim)
	_point(root, "light_point", "lamp", Vector3(-2, 2.5, 0), {"energy": 1.5}, Basis.IDENTITY)
	_point(
		root,
		"light_directional",
		"sun",
		Vector3(0, 10, 0),
		{},
		Basis(Vector3.RIGHT, deg_to_rad(-45.0))
	)
	_point(root, "light_point", "lamp_dark", Vector3(2, 2.5, 0), {"energy": 0.0}, Basis.IDENTITY)
	_point(root, "ambient_sound", "radio", Vector3(0, 1, -2), {"stream": tone_path}, Basis.IDENTITY)
	_point(
		root,
		"ambient_sound",
		"radio2",
		Vector3(0, 1, -3),
		{"stream": tone_path, "autoplay": false},
		Basis.IDENTITY
	)
	await frame()
	var spot_basis: Basis = marker_spot.global_transform.basis
	for target in ["lamp", "spot", "sun"]:
		root.add_entity_output(off_btn, "OnPressed", target, "TurnOff")
		root.add_entity_output(tog_btn, "OnPressed", target, "Toggle")
	root.add_entity_output(on_btn, "OnPressed", "lamp_dark", "TurnOn")
	root.add_entity_output(snd_btn, "OnPressed", "radio", "Stop")
	root.add_entity_output(snd_btn, "OnPressed", "radio2", "Play")
	var scene := await _ship(root, "lights")
	var dispatcher := _listen(scene)
	if dispatcher == null:
		flag("the lights level shipped no dispatcher")
		await _unship(scene)
		return
	var lamp: Node = _first_named(scene, "lamp")
	var spot: Node = _first_named(scene, "spot")
	var sun: Node = _first_named(scene, "sun")
	var dark: Node = _first_named(scene, "lamp_dark")
	var before := [_light_state(lamp), _light_state(spot), _light_state(sun), _light_state(dark)]
	if spot is Node3D:
		note(
			"light_spot aimed with the entity's rotation",
			(
				"shipped basis equals the marker's: %s"
				% (spot as Node3D).global_transform.basis.is_equal_approx(spot_basis)
			)
		)
	dispatcher.call("press_button", _first_named(scene, "lights_off"))
	await frame()
	var after_off := [_light_state(lamp), _light_state(spot), _light_state(sun)]
	dispatcher.call("press_button", _first_named(scene, "lights_toggle"))
	await frame()
	var after_toggle := [_light_state(lamp), _light_state(spot), _light_state(sun)]
	dispatcher.call("press_button", _first_named(scene, "lights_on"))
	await frame()
	var dark_after := _light_state(dark)
	note("lamp, spot, sun, lamp_dark as shipped", before)
	note("after TurnOff on lamp, spot and sun", after_off)
	note("after Toggle on lamp, spot and sun", after_toggle)
	note("lamp_dark (energy 0) after TurnOn", dark_after)
	note(
		"light inputs delivered",
		_events.map(func(e) -> String: return "%s.%s" % [e["target"], e["input"]])
	)
	var lights_ignored: bool = (
		before[0] == after_off[0]
		and before[1] == after_off[1]
		and before[2] == after_off[2]
		and after_off == after_toggle
		and before[3] == dark_after
		and _count("lamp", "TurnOff") > 0
	)

	var radio: Node = _first_named(scene, "radio")
	var radio2: Node = _first_named(scene, "radio2")
	var r_before := (
		"radio playing %s, radio2 playing %s"
		% [radio.get("playing") if radio else "?", radio2.get("playing") if radio2 else "?"]
	)
	dispatcher.call("press_button", _first_named(scene, "radio_btn"))
	await frame()
	var r_after := (
		"radio playing %s, radio2 playing %s"
		% [radio.get("playing") if radio else "?", radio2.get("playing") if radio2 else "?"]
	)
	note("ambient_sound: autoplay on (radio) and off (radio2), as shipped", r_before)
	note("after radio.Stop and radio2.Play", r_after)

	# #1209: the dispatcher switches a light on TurnOn, TurnOff and Toggle.
	if lights_ignored:
		flag(
			"TurnOn, TurnOff and Toggle do nothing to a light again (#1209)",
			"after TurnOff %s, after Toggle %s" % [after_off, after_toggle]
		)
	await _unship(scene)


## The six built-in connection presets, applied the way the wiring panel applies
## them (`HFIOPresets.apply_preset()` with the tags mapped to real entities), on
## the shipped class each one obviously means. The first is the one the panel
## opens on.
func _built_in_presets() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	var porch = await _brush_entity(
		root, "trigger_once", "porch", Vector3(2, 2, 2), Vector3(0, 1, 0)
	)
	var pdoor = await _brush_entity(
		root, "func_door", "porch_door", LEAF, Vector3(4, LEAF.y * 0.5, 0)
	)
	root.set_entity_property(pdoor, "wait", 0.0)
	_point(root, "light_point", "porch_lamp", Vector3(0, 2.5, 3), {}, Basis.IDENTITY)
	_point(
		root, "ambient_sound", "porch_radio", Vector3(0, 1, 4), {"autoplay": false}, Basis.IDENTITY
	)
	var blink := _point(
		root, "logic_timer", "blink", Vector3(0, 1, 5), {"wait": 0.2}, Basis.IDENTITY
	)
	_point(root, "light_point", "blink_lamp", Vector3(0, 2.5, 5), {}, Basis.IDENTITY)
	await frame()
	var presets: Array = root.io_presets.get_all_presets() if root.io_presets else []
	var builtin_names: Array = (
		presets
		. filter(func(p) -> bool: return bool(p.get("builtin", false)))
		. map(func(p) -> String: return str(p.get("name", "")))
	)
	note("built-in preset names", builtin_names)
	var door_preset: Dictionary = presets[0] if presets.size() > 0 else {}
	var unresolved: Array = []
	var made: int = root.io_presets.apply_preset(
		porch,
		door_preset,
		{"door": "porch_door", "light": "porch_lamp", "sound": "porch_radio"},
		unresolved
	)
	var cycle: Dictionary = {}
	for p in presets:
		if str(p.get("name", "")).begins_with("Timer"):
			cycle = p
	var made2: int = root.io_presets.apply_preset(blink, cycle, {"light": "blink_lamp"}, [])
	note(
		"'%s' applied to a trigger_once" % door_preset.get("name", "?"),
		"%d wire(s): %s" % [made, root.get_entity_outputs(porch).map(_wire_text)]
	)
	note("'%s' applied to a logic_timer" % cycle.get("name", "?"), "%d wire(s)" % made2)
	var scene := await _ship(root, "presets")
	var dispatcher := _listen(scene)
	if dispatcher == null:
		await _unship(scene)
		return
	var door: Node3D = _door_of(scene, "porch_door")
	var origin: Vector3 = door.global_position if door else Vector3.ZERO
	var lamp: Node = _first_named(scene, "porch_lamp")
	var radio: Node = _first_named(scene, "porch_radio")
	var blink_lamp: Node = _first_named(scene, "blink_lamp")
	var lamp0 := _light_state(lamp)
	var blink0 := _light_state(blink_lamp)
	var body := _body()
	await _walk(body, Vector3(0, 0.9, 0))
	await _seconds(1.2)
	var walked := {
		"door moved": "%.3f m" % ((door.global_position - origin).length() if door else -1.0),
		"lamp": _light_state(lamp),
		"radio playing": radio.get("playing") if radio else "?",
		"inputs delivered":
		(
			_events
			. map(func(e) -> String: return "%s.%s" % [e["target"], e["input"]])
			. filter(func(s: String) -> bool: return not s.begins_with("blink"))
		),
	}
	note("walking into the trigger the preset was applied to", walked)
	note(
		"'Timer -> Cycle Lights' after 1.2 s",
		(
			"%d Toggle input(s) delivered to blink_lamp; it was %s and is %s"
			% [_count("blink_lamp", "Toggle"), blink0, _light_state(blink_lamp)]
		)
	)
	var dead_door_preset: bool = (
		_count("porch_door") == 0 and _count("porch_lamp") == 0 and _count("porch_radio") == 0
	)
	await _walk(body, Vector3(0, 50, 0))
	# What the same three wires do if something did raise OnTrigger.
	_events.clear()
	dispatcher.call("fire", "porch", "OnTrigger", "")
	await _seconds(1.0)
	note(
		"the same three wires when OnTrigger is raised by hand",
		(
			"door moved %.3f m; lamp %s (was %s); radio playing %s; delivered %s"
			% [
				(door.global_position - origin).length() if door else -1.0,
				_light_state(lamp),
				lamp0,
				radio.get("playing") if radio else "?",
				_events.map(func(e) -> String: return "%s.%s" % [e["target"], e["input"]])
			]
		)
	)
	if dead_door_preset:
		known(
			1213,
			"the built-in I/O presets wire outputs and inputs the shipped classes never raise or answer, so applied as offered they do nothing in the game",
			(
				(
					"'Door Open -> Light + Sound', the first preset in the panel, applied to a "
					+ "trigger_once with door, light and sound mapped to a func_door, a light_point "
					+ "and an ambient_sound: walking into the trigger delivered nothing (%s). Its "
					+ "wires leave on OnTrigger, which trigger_once never raises (it raises "
					+ "OnStartTouch; hf_io_presets.gd:23-25 copies the preset's output name "
					+ "verbatim in apply_preset(), line 283). Raised by hand, the door opens but "
					+ "TurnOn leaves the light as it was and PlaySound reaches an ambient_sound "
					+ "that declares Play, not PlaySound, so it stays silent. 'Timer -> Cycle "
					+ "Lights' delivered %d Toggle inputs to a light in 1.2 s and the light never "
					+ "changed. Of the six built-ins only 'Button -> Door Toggle' works on shipped "
					+ "classes: 'Trigger -> Alarm Sequence' is OnTrigger/TurnOn/PlaySound again, "
					+ "and 'Pickup -> Effect + Remove' and 'Damage -> Break + Particles' use "
					+ "OnUse, OnDamage, OnBreak, PlayEffect, Kill, Break and Start, which no class "
					+ "raises or answers (Kill included -- nothing in the addon removes a node on "
					+ "an input). #613 and #704 aligned the vocabulary on paper; the runtime half "
					+ "was never checked."
				)
				% [walked["inputs delivered"], _count("blink_lamp", "Toggle")]
			)
		)
	await _unship(scene)


## logic_timer at its edges: an interval of 0.2, 0, -1 and one-shot; a timer
## that waits for Start, Start with a parameter, Stop, and a timer wired to stop
## itself. Every OnTimer is wired to an info_target `sink` with the timer's name
## as the parameter, so each one can be counted.
func _timers() -> void:
	var root: Node3D = await fresh_root()
	var sink := _point(root, "info_target", "sink", Vector3(0, 1, -3), {}, Basis.IDENTITY)
	var specs := {
		"t_fast": {"wait": 0.2},
		"t_zero": {"wait": 0.0},
		"t_neg": {"wait": -1.0},
		"t_once": {"wait": 0.2, "once": true},
		"t_idle": {"wait": 0.2, "start_on": false},
		"t_self": {"wait": 0.2},
	}
	var x := 0.0
	var timers := {}
	for tname in specs:
		timers[tname] = _point(
			root, "logic_timer", tname, Vector3(x, 1, 0), specs[tname], Basis.IDENTITY
		)
		x += 1.0
	var go = await _brush_entity(
		root, "func_button", "t_go", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 2)
	)
	var halt = await _brush_entity(
		root, "func_button", "t_halt", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 3)
	)
	await frame()
	for tname in timers:
		root.add_entity_output(timers[tname], "OnTimer", "sink", "Ping", tname)
	root.add_entity_output(timers["t_self"], "OnTimer", "t_self", "Stop")
	root.add_entity_output(go, "OnPressed", "t_idle", "Start", "0.1")
	root.add_entity_output(halt, "OnPressed", "t_fast", "Stop")
	var scene := await _ship(root, "timers")
	var dispatcher := _listen(scene)
	if dispatcher == null:
		await _unship(scene)
		return
	var shipped := {}
	for tname in specs:
		var t = _first_named(scene, tname)
		shipped[tname] = (
			(
				"%s wait_time=%.2f one_shot=%s autostart=%s"
				% [t.get_class(), t.wait_time, t.one_shot, t.autostart]
			)
			if t is Timer
			else "missing"
		)
	note("the timers as shipped (authored interval -> wait_time)", shipped)
	var t0 := Time.get_ticks_msec()
	await _seconds(1.1)
	var counts := {}
	for tname in specs:
		counts[tname] = _count("sink", "Ping", tname)
	note("OnTimer fires in the first 1.1 s", counts)
	_events.clear()
	dispatcher.call("press_button", _first_named(scene, "t_go"))
	dispatcher.call("press_button", _first_named(scene, "t_halt"))
	await _seconds(0.55)
	var idle = _first_named(scene, "t_idle")
	note(
		"after Start('0.1') on t_idle and Stop on t_fast, 0.55 s",
		(
			"t_idle fired %d (wait_time now %.2f), t_fast fired %d"
			% [
				_count("sink", "Ping", "t_idle"),
				idle.wait_time if idle is Timer else -1.0,
				_count("sink", "Ping", "t_fast")
			]
		)
	)
	note(
		"an Interval of 0 or below",
		(
			"Timer.wait_time refuses a value <= 0 with an engine error ('Time should be greater "
			+ "than zero') and keeps its 1.0 default, so t_zero and t_neg run once a second. The "
			+ "definition has no range; not flagged, a mapper typing 0 gets a log line."
		)
	)
	await _unship(scene)


## Triggers of both kinds, Enable/Disable/Kill on one, fire-once and delayed
## wires, a missing target, a target freed at runtime, two targets with one
## name, and a parameter on a wire. One body walks the volumes in turn.
func _triggers_and_wires() -> void:
	var root: Node3D = await fresh_root()
	_point(root, "info_target", "sink", Vector3(0, 1, -3), {}, Basis.IDENTITY)
	var t1 = await _brush_entity(root, "trigger_once", "t1", Vector3(2, 2, 2), Vector3(0, 1, 0))
	var tm = await _brush_entity(root, "trigger_multiple", "tm", Vector3(2, 2, 2), Vector3(4, 1, 0))
	var tm0 = await _brush_entity(
		root, "trigger_multiple", "tm0", Vector3(2, 2, 2), Vector3(8, 1, 0)
	)
	var tmn = await _brush_entity(
		root, "trigger_multiple", "tmn", Vector3(2, 2, 2), Vector3(12, 1, 0)
	)
	var tf = await _brush_entity(
		root, "trigger_multiple", "tf", Vector3(2, 2, 2), Vector3(16, 1, 0)
	)
	var td = await _brush_entity(
		root, "trigger_multiple", "td", Vector3(2, 2, 2), Vector3(20, 1, 0)
	)
	root.set_entity_property(tm, "wait", 0.3)
	root.set_entity_property(tm0, "wait", 0.0)
	root.set_entity_property(tmn, "wait", -1.0)
	root.set_entity_property(tf, "wait", 0.0)
	root.set_entity_property(td, "wait", 0.0)
	var dis = await _brush_entity(
		root, "func_button", "dis", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 4)
	)
	var ena = await _brush_entity(
		root, "func_button", "ena", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 5)
	)
	var kill = await _brush_entity(
		root, "func_button", "kill", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 6)
	)
	var wires = await _brush_entity(
		root, "func_button", "wires", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 7)
	)
	root.set_entity_property(wires, "wait", 0.0)
	_point(root, "info_target", "victim", Vector3(0, 1, -5), {}, Basis.IDENTITY)
	_point(root, "info_target", "twin", Vector3(0, 1, -6), {}, Basis.IDENTITY)
	var twin2 := _point(root, "info_target", "twin", Vector3(0, 1, -7), {}, Basis.IDENTITY)
	await frame()
	note(
		"the second info_target asked to be 'twin'",
		"entity_name %s, node %s" % [twin2.get_meta("entity_name", ""), twin2.name]
	)
	for pair in [[t1, "t1"], [tm, "tm"], [tm0, "tm0"], [tmn, "tmn"], [td, "td"]]:
		root.add_entity_output(pair[0], "OnStartTouch", "sink", "Ping", pair[1])
	root.add_entity_output(tf, "OnStartTouch", "sink", "Ping", "tf", 0.0, true)
	root.add_entity_output(dis, "OnPressed", "td", "Disable")
	root.add_entity_output(ena, "OnPressed", "td", "Enable")
	root.add_entity_output(kill, "OnPressed", "td", "Kill")
	root.add_entity_output(wires, "OnPressed", "sink", "Ping", "d0", 0.0)
	root.add_entity_output(wires, "OnPressed", "sink", "Ping", "d03", 0.3)
	root.add_entity_output(wires, "OnPressed", "sink", "Ping", "dbig", 1000000.0)
	root.add_entity_output(wires, "OnPressed", "sink", "Ping", "fo", 0.3, true)
	root.add_entity_output(wires, "OnPressed", "nobody", "Ping", "ghost")
	root.add_entity_output(wires, "OnPressed", "victim", "Ping", "dead")
	root.add_entity_output(wires, "OnPressed", "twin", "Ping", "both")
	var scene := await _ship(root, "triggers")
	var dispatcher := _listen(scene)
	if dispatcher == null:
		await _unship(scene)
		return
	var body := _body()
	var spots := {"t1": 0.0, "tm": 4.0, "tm0": 8.0, "tmn": 12.0, "tf": 16.0}
	for _round in 3:
		for tname in spots:
			await _walk(body, Vector3(spots[tname], 0.9, 0))
			await _walk(body, Vector3(spots[tname], 50, 0))
		await _seconds(0.4)
	var fired := {}
	for tname in spots:
		fired[tname] = _count("sink", "Ping", tname)
	note("OnStartTouch -> sink.Ping over three walk-ins, 0.4 s apart", fired)
	note(
		"expected",
		"t1 1 (once), tm 3 (wait 0.3), tm0 3 (wait 0), tmn 1 (wait -1), tf 1 (fire-once wire)"
	)
	var expected := {"t1": 1, "tm": 3, "tm0": 3, "tmn": 1, "tf": 1}
	for tname in expected:
		if int(fired[tname]) != int(expected[tname]):
			flag(
				(
					"trigger '%s' fired %d time(s) over three walk-ins, expected %d"
					% [tname, fired[tname], expected[tname]]
				)
			)

	# Enable / Disable / Kill on td.
	var td_x := 20.0
	await _walk(body, Vector3(td_x, 0.9, 0))
	await _walk(body, Vector3(td_x, 50, 0))
	var first := _count("sink", "Ping", "td")
	dispatcher.call("press_button", _first_named(scene, "dis"))
	for _i in 3:
		await _tree.physics_frame
	await _walk(body, Vector3(td_x, 0.9, 0))
	await _walk(body, Vector3(td_x, 50, 0))
	var while_disabled := _count("sink", "Ping", "td") - first
	dispatcher.call("press_button", _first_named(scene, "ena"))
	for _i in 3:
		await _tree.physics_frame
	await _walk(body, Vector3(td_x, 0.9, 0))
	await _walk(body, Vector3(td_x, 50, 0))
	var after_enable := _count("sink", "Ping", "td") - first - while_disabled
	dispatcher.call("press_button", _first_named(scene, "kill"))
	await frame()
	var td_node: Node = _first_named(scene, "td", "Area3D")
	note(
		"td: walk-in, Disable, walk-in, Enable, walk-in",
		"%d, %d while disabled, %d after Enable" % [first, while_disabled, after_enable]
	)
	note(
		"td after a Kill input (no class declares Kill)",
		(
			"still in the tree %s, monitoring %s"
			% [
				is_instance_valid(td_node) and td_node.is_inside_tree(),
				td_node.get("monitoring") if td_node else "?"
			]
		)
	)
	if while_disabled != 0 or after_enable != 1:
		flag(
			"Enable/Disable on a trigger_multiple did not gate it",
			"%d while disabled, %d after Enable" % [while_disabled, after_enable]
		)

	# Delays, fire-once, missing, freed and doubled targets, and a parameter.
	var victim: Node = _first_named(scene, "victim")
	if victim:
		victim.get_parent().remove_child(victim)
		victim.free()
	_events.clear()
	var press_at := Time.get_ticks_msec()
	var wires_node: Node = _first_named(scene, "wires")
	dispatcher.call("press_button", wires_node)
	await frame()
	dispatcher.call("press_button", wires_node)
	await _seconds(0.7)
	var timing := {}
	for e in _events:
		timing["%s.%s(%s)" % [e["target"], e["input"], e["param"]]] = (
			str(timing.get("%s.%s(%s)" % [e["target"], e["input"], e["param"]], ""))
			+ " %d ms" % (int(e["ms"]) - press_at)
		)
	note("one button pressed twice, a frame apart, wait 0: every delivery and when", timing)
	note(
		"read as",
		(
			"d0 twice at once, d03 twice after 0.3 s, dbig never (1e6 s), fo once (a fire-once "
			+ "wire with a delay keeps only the first of two fires), nobody and the freed victim "
			+ "nothing and no error, twin twice (both nodes with the name)"
		)
	)
	if _count("sink", "Ping", "fo") != 1:
		flag(
			(
				"a fire-once wire with a delay delivered %d times for two fires inside its delay"
				% _count("sink", "Ping", "fo")
			)
		)
	if _count("twin", "Ping", "both") != 4:
		note(
			"deliveries to the two nodes named 'twin' for two presses",
			_count("twin", "Ping", "both")
		)
	# The game passing its own parameter beats the one on the wire.
	_events.clear()
	dispatcher.call("fire", "wires", "OnPressed", "from_game")
	await frame()
	note(
		"fire('wires', 'OnPressed', 'from_game') on wires carrying their own parameters",
		(
			"sink got %s"
			% [
				(
					_events
					. filter(func(e) -> bool: return e["target"] == "sink")
					. map(func(e) -> String: return str(e["param"]))
				)
			]
		)
	)
	_scenes.erase(body)
	body.queue_free()
	await _unship(scene)


## Zero-delay loops and self-wires through doors, the one shipped class that
## raises an output in answer to an input. Two doors that Toggle each other on
## OnOpen and OnClose make a loop that never settles. The dispatcher stops it
## after `HFIORuntime.MAX_CHAIN` nested wires (#1218); the scenario's own cut is
## far past that, so a regression shows as a FLAG rather than a stack overflow.
func _loops_and_self_wires() -> void:
	var root: Node3D = await fresh_root()
	var a = await _brush_entity(root, "func_door", "door_a", LEAF, Vector3(0, LEAF.y * 0.5, 0))
	var b = await _brush_entity(root, "func_door", "door_b", LEAF, Vector3(4, LEAF.y * 0.5, 0))
	var c = await _brush_entity(root, "func_door", "door_c", LEAF, Vector3(8, LEAF.y * 0.5, 0))
	var d = await _brush_entity(root, "func_door", "door_d", LEAF, Vector3(12, LEAF.y * 0.5, 0))
	var selfie = await _brush_entity(
		root, "func_door", "selfie", LEAF, Vector3(16, LEAF.y * 0.5, 0)
	)
	for door in [a, b, c, d, selfie]:
		root.set_entity_property(door, "wait", 0.0)
	root.add_entity_output(a, "OnOpen", "door_b", "Toggle")
	root.add_entity_output(a, "OnClose", "door_b", "Toggle")
	root.add_entity_output(b, "OnOpen", "door_a", "Toggle")
	root.add_entity_output(b, "OnClose", "door_a", "Toggle")
	# The linked pair a mapper would actually draw: open and close each other.
	root.add_entity_output(c, "OnOpen", "door_d", "Open")
	root.add_entity_output(c, "OnClose", "door_d", "Close")
	root.add_entity_output(d, "OnOpen", "door_c", "Open")
	root.add_entity_output(d, "OnClose", "door_c", "Close")
	root.add_entity_output(selfie, "OnOpen", "selfie", "Close")
	var scene := await _ship(root, "loops")
	var dispatcher := _listen(scene)
	if dispatcher == null:
		await _unship(scene)
		return
	const CUT_AT := 400
	var cut := [false]
	dispatcher.connect(
		"io_received",
		func(_t: String, _i: String, _p: String) -> void:
			if _events.size() >= CUT_AT and not cut[0]:
				cut[0] = true
				(dispatcher.get("_connections") as Dictionary).clear()
	)
	var frame0 := Engine.get_process_frames()
	var door_a: Node = _door_of(scene, "door_a")
	var door_b: Node = _door_of(scene, "door_b")
	var moves := [0]
	for door_node in [door_a, door_b]:
		door_node.connect("opened", func() -> void: moves[0] += 1)
		door_node.connect("closed", func() -> void: moves[0] += 1)
	door_a.call("open")
	note(
		"door_a Open with a Toggle loop to door_b on OnOpen and OnClose, zero delay",
		(
			"%d door opens and closes inside the one open() call, %d frame(s) passed, %d input(s) seen"
			% [moves[0], Engine.get_process_frames() - frame0, _events.size()]
		)
	)
	if cut[0]:
		flag(
			"a zero-delay loop between two doors runs on until the scenario cuts it again (#1218)",
			"cut at %d inputs, %d door moves" % [CUT_AT, moves[0]]
		)
	dispatcher.call("wire")
	_events.clear()
	var door_c: Node = _door_of(scene, "door_c")
	var door_d: Node = _door_of(scene, "door_d")
	door_c.call("open")
	await _settle(door_c)
	await _settle(door_d)
	note(
		"door_c and door_d wired to Open and Close each other, Open on door_c",
		(
			"%d input(s), c open %s, d open %s"
			% [_events.size(), door_c.call("is_open"), door_d.call("is_open")]
		)
	)
	door_d.call("close")
	await _settle(door_c)
	await _settle(door_d)
	note(
		"then Close on door_d",
		"c open %s, d open %s" % [door_c.call("is_open"), door_d.call("is_open")]
	)
	var selfie_node: Node3D = _door_of(scene, "selfie")
	var origin := selfie_node.global_position
	selfie_node.call("open")
	await _settle(selfie_node)
	note(
		"a door wired OnOpen -> its own Close",
		(
			"%.3f m out, is_open %s: it shuts in the same call, which is what the wire says"
			% [(selfie_node.global_position - origin).length(), selfie_node.call("is_open")]
		)
	)
	await _unship(scene)


## One level instanced twice, and two different levels loaded together, each
## with its own dispatcher. A door raises OnOpen through the static
## `HFIORuntime.fire_door_on()`, which finds its dispatcher with
## `get_first_node_in_group()` -- the first dispatcher in the whole tree, not
## the one in the door's own level.
func _one_level_loaded_twice() -> void:
	var root: Node3D = await fresh_root()
	var gate = await _brush_entity(root, "func_door", "gate", LEAF, Vector3(0, LEAF.y * 0.5, 0))
	root.set_entity_property(gate, "wait", 0.0)
	_point(
		root,
		"logic_timer",
		"clock",
		Vector3(2, 1, 0),
		{"wait": 5.0, "start_on": false},
		Basis.IDENTITY
	)
	var ring = await _brush_entity(
		root, "func_button", "ring", Vector3(0.3, 0.3, 0.3), Vector3(3, 1, 2)
	)
	_point(
		root,
		"logic_timer",
		"chime",
		Vector3(4, 1, 0),
		{"wait": 5.0, "start_on": false},
		Basis.IDENTITY
	)
	await frame()
	root.add_entity_output(gate, "OnOpen", "clock", "Start")
	root.add_entity_output(ring, "OnPressed", "chime", "Start")
	var path_d := await _export(root, "level_d")

	var root2: Node3D = await fresh_root()
	var hatch = await _brush_entity(root2, "func_door", "hatch", LEAF, Vector3(0, LEAF.y * 0.5, 0))
	root2.set_entity_property(hatch, "wait", 0.0)
	_point(
		root2,
		"logic_timer",
		"beacon",
		Vector3(2, 1, 0),
		{"wait": 5.0, "start_on": false},
		Basis.IDENTITY
	)
	await frame()
	root2.add_entity_output(hatch, "OnOpen", "beacon", "Start")
	var path_e := await _export(root2, "level_e")
	if path_d == "" or path_e == "":
		return

	# Control: level E alone.
	var alone := await _instance(path_e)
	_door_of(alone, "hatch").call("open")
	await frame()
	var beacon_alone := not (_first_named(alone, "beacon") as Timer).is_stopped()
	note("level E alone: hatch opens, beacon started", beacon_alone)
	await _unship(alone)

	# The same level twice.
	var first := await _instance(path_d, Vector3(0, 0, 0))
	var second := await _instance(path_d, Vector3(40, 0, 0))
	_door_of(second, "gate").call("open")
	await frame()
	var clock_first := not (_first_named(first, "clock") as Timer).is_stopped()
	var clock_second := not (_first_named(second, "clock") as Timer).is_stopped()
	note(
		"level D instanced twice, the second copy's gate opened",
		(
			"first copy's clock started %s, second copy's clock started %s"
			% [clock_first, clock_second]
		)
	)
	# The playtest player's Use key, as playtest_fps.gd:268 does it: the first
	# dispatcher in the group, handed the button the ray hit -- here, the second
	# copy's.
	var used: Node = _tree.get_first_node_in_group(IORuntime.DISPATCHER_GROUP)
	var ring_second: Node = _first_named(second, "ring")
	var used_ok: bool = used.call("press_button", ring_second) if used and ring_second else false
	await frame()
	var chime_first := not (_first_named(first, "chime") as Timer).is_stopped()
	var chime_second := not (_first_named(second, "chime") as Timer).is_stopped()
	note(
		"the second copy's button pressed the way the playtest player's Use key presses it",
		(
			"press_button returned %s; first copy's chime started %s, second copy's %s"
			% [used_ok, chime_first, chime_second]
		)
	)
	await _unship(second)
	await _unship(first)

	# Two different levels: D loaded first, E second.
	var level_d := await _instance(path_d, Vector3(0, 0, 0))
	var level_e := await _instance(path_e, Vector3(40, 0, 0))
	_door_of(level_e, "hatch").call("open")
	await frame()
	var beacon_with_d := not (_first_named(level_e, "beacon") as Timer).is_stopped()
	note("level D then level E loaded, E's hatch opened", "beacon started %s" % beacon_with_d)
	await _unship(level_e)
	await _unship(level_d)

	if beacon_alone and (clock_first or not clock_second or not beacon_with_d):
		known(
			1211,
			"a door raises OnOpen through whichever dispatcher entered the tree first, so with two levels loaded it fires the other level's wires or none",
			(
				(
					"Each exported level carries its own HFIODispatcher. Level E alone: its hatch's "
					+ "OnOpen -> beacon.Start works (%s). The same level D instanced twice and the "
					+ "second copy's gate opened: first copy's clock started %s, second copy's %s. "
					+ "Level D then a different level E loaded, E's hatch opened: E's beacon started "
					+ "%s. HFDoorRuntime.open() calls the static HFIORuntime.fire_door_on() "
					+ "(hf_door_runtime.gd:127), which takes `_find_dispatcher(door)` "
					+ "(hf_io_runtime.gd:1031) = `tree.get_first_node_in_group(DISPATCHER_GROUP)`, "
					+ "the first dispatcher anywhere in the tree. That dispatcher looks the door up "
					+ "by name in its own level: a copy of the same level finds its own 'gate' and "
					+ "fires that copy's wires, and a different level finds nothing and the event "
					+ "is lost. The doc comment above _find_dispatcher says it 'Tries current_scene "
					+ "first', which the code does not do. HFIORuntime.fire_on(), the API the guide "
					+ "gives game scripts, has the same lookup, and so does the playtest player's Use "
					+ "key (playtest_fps.gd:268), which the guide tells a game to copy: the second "
					+ "copy's button pressed that way started the first copy's chime (%s) and not "
					+ "its own (%s). Any game that keeps two levels in "
					+ "the tree -- a hub and a sub-level, streamed sections, a level piece instanced "
					+ "twice, or the old level for one frame while the next comes in -- gets "
					+ "doors whose OnOpen/OnClose drive the wrong level or nothing."
				)
				% [
					beacon_alone,
					clock_first,
					clock_second,
					beacon_with_d,
					chime_first,
					chime_second
				]
			)
		)


func _cleanup() -> void:
	for s in _scenes.duplicate():
		if is_instance_valid(s):
			await _unship(s)
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	note("files written and removed", _written.size())
