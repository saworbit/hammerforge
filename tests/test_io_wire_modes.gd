extends GutTest

## Which wires to draw: all, the chain the selection is in, the selection's own,
## or none (#1730).

const Visualizer = preload("res://addons/hammerforge/systems/hf_io_visualizer.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFUserPrefsScript = preload("res://addons/hammerforge/hf_user_prefs.gd")

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	root = null


func _entity(entity_name: String, at: Vector3) -> Node:
	var entity: Node = root._create_entity_from_map({"classname": "func_button", "origin": at})
	entity.set_meta("entity_name", entity_name)
	return entity


## trigger fires relay, relay fires door, door fires light; and apart from them,
## button_2 fires lamp_2.
func _wire_level() -> Dictionary:
	var made := {}
	for i in ["trigger", "relay", "door", "light", "button_2", "lamp_2"].size():
		var entity_name: String = ["trigger", "relay", "door", "light", "button_2", "lamp_2"][i]
		made[entity_name] = _entity(entity_name, Vector3(i * 3, 1, 0))
	root.add_entity_output(made["trigger"], "OnTrigger", "relay", "Trigger")
	root.add_entity_output(made["relay"], "OnTrigger", "door", "Open")
	root.add_entity_output(made["door"], "OnFullyOpen", "light", "TurnOn")
	root.add_entity_output(made["button_2"], "OnPressed", "lamp_2", "Toggle")
	return made


func _wires(mode: int, selected: Array) -> Dictionary:
	var names := {}
	for node in selected:
		names[str(node.get_meta("entity_name"))] = true
		names[str(node.name)] = true
	var connections: Array = root.entity_system.get_all_connections()
	var hops := Visualizer.wire_hops(
		connections, root.entity_system.build_name_index(), names, mode
	)
	var out := {}
	for index in hops:
		var conn: Dictionary = connections[index]
		out["%s>%s" % [conn["source_name"], conn["target_name"]]] = hops[index]
	return out


func test_the_chain_from_a_trigger_is_its_sequence_and_nothing_else():
	var made := _wire_level()
	assert_eq(
		_wires(Visualizer.WireMode.CHAIN, [made["trigger"]]),
		{"trigger>relay": 0, "relay>door": 1, "door>light": 2}
	)


func test_the_chain_follows_inputs_back_to_their_sources():
	var made := _wire_level()
	assert_eq(
		_wires(Visualizer.WireMode.CHAIN, [made["door"]]),
		{"relay>door": 0, "door>light": 0, "trigger>relay": 1}
	)


func test_selection_only_is_the_selected_entity_s_own_wires():
	var made := _wire_level()
	assert_eq(
		_wires(Visualizer.WireMode.SELECTION, [made["relay"]]),
		{"trigger>relay": 0, "relay>door": 0}
	)


func test_all_is_every_wire():
	var made := _wire_level()
	assert_eq(_wires(Visualizer.WireMode.ALL, [made["relay"]]).size(), 4)


func test_a_cycle_is_walked_once():
	var a := _entity("a", Vector3.ZERO)
	var b := _entity("b", Vector3(3, 0, 0))
	root.add_entity_output(a, "OnTrigger", "b", "Trigger")
	root.add_entity_output(b, "OnTrigger", "a", "Trigger")
	assert_eq(_wires(Visualizer.WireMode.CHAIN, [a]), {"a>b": 0, "b>a": 0})


func test_chain_wires_fade_with_the_hop():
	assert_eq(Visualizer.chain_color(0), Visualizer.CHAIN_NEAR_COLOR)
	assert_ne(Visualizer.chain_color(2), Visualizer.chain_color(0))
	assert_true(Visualizer.chain_color(50).is_equal_approx(Visualizer.CHAIN_FAR_COLOR))


func test_the_mode_is_kept_per_user_and_reaches_the_level():
	# The run's own preferences file, which gut_pre_run.gd points the prefs at.
	var prefs := HFUserPrefsScript.load_prefs()
	prefs.set_pref("io_wire_mode", 1)
	prefs.save()
	var again := HFUserPrefsScript.load_prefs()
	assert_eq(int(again.get_pref("io_wire_mode", 0)), 1, "the mode survives a restart")
	var dock: Node = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock.set_user_prefs(again)
	assert_eq(dock.io_wire_mode_opt.selected, 1)
	assert_eq(root.io_visualizer.wire_mode, Visualizer.WireMode.CHAIN, "and the level draws it")
	again.set_pref("io_wire_mode", 0)
	again.save()


func test_cycling_steps_through_none_all_chain_and_selection():
	var dock: Node = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._show_io_lines.set_pressed_no_signal(false)
	var seen: Array = []
	for _i in 4:
		dock.cycle_io_wires()
		var on: bool = root.io_visualizer.enabled
		seen.append(root.io_visualizer.wire_mode if on else -1)
	assert_eq(seen, [0, 1, 2, -1])
