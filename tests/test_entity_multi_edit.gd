extends GutTest

## Editing a property on several entities at once, and class defaults (#1729).

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFDockEntityHandler = preload("res://addons/hammerforge/dock_entity_handler.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")
const HFEntityMultiEdit = preload("res://addons/hammerforge/ui/hf_entity_multi_edit.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")

var root: LevelRoot
var dock: Node
var undo


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
	undo = UndoStandIn.new()
	dock.undo_redo = undo


func after_each() -> void:
	dock.undo_redo = null
	undo.free_histories()
	root = null
	dock = null


func _light(entity_class: String, x: float) -> Node:
	return root._create_entity_from_map({"classname": entity_class, "origin": Vector3(x, 2, 0)})


func _energy(node: Node) -> float:
	return float(HFEntityPropUtils.get_entity_data(node).get("energy", 1.0))


func _row(prop_name: String) -> HBoxContainer:
	for control in dock._entity_props_controls:
		if is_instance_valid(control) and str(control.name) == "Multi_%s" % prop_name:
			return control
	return null


func _label(row: HBoxContainer) -> Label:
	return row.get_child(0) as Label if row else null


func test_twelve_lights_take_one_energy_in_one_undo_step():
	var lights: Array = []
	for i in 12:
		lights.append(_light("light_point", i * 2.0))
	dock.set_selection_nodes(lights)
	var row := _row("energy")
	assert_not_null(row, "the panel shows the lights together")
	if row == null:
		return
	var spin := row.get_child(1) as SpinBox
	var steps: int = undo.scene_history.get_version()
	spin.value = 3.5
	for light in lights:
		assert_almost_eq(_energy(light), 3.5, 0.001)
	assert_eq(undo.scene_history.get_version(), steps + 1, "one step for all twelve")
	undo.scene_history.undo()
	for light in lights:
		assert_almost_eq(_energy(light), 1.0, 0.001, "and one undo takes all twelve back")


func test_differing_values_show_a_dash_and_a_partial_property_its_count():
	var lights: Array = []
	for i in 9:
		lights.append(_light("light_point", i * 2.0))
	for i in 3:
		lights.append(_light("light_spot", 30.0 + i * 2.0))
	HFEntityPropUtils.set_entity_property(lights[0], "energy", 2.0)
	dock.set_selection_nodes(lights)
	var energy := _row("energy")
	assert_eq((energy.get_child(1) as SpinBox).get_line_edit().text, "-", "values differ")
	var angle := _row("angle")
	assert_not_null(angle, "the spots' angle is in the union")
	assert_string_contains(_label(angle).text, "(3 of 12)")
	(angle.get_child(1) as SpinBox).value = 30.0
	assert_almost_eq(
		float(HFEntityPropUtils.get_entity_data(lights[11]).get("angle", 0.0)), 30.0, 0.001
	)
	assert_false(
		HFEntityPropUtils.get_entity_data(lights[0]).has("angle"), "not given to a point light"
	)


func test_a_default_reads_lighter_and_reset_to_default_puts_it_back():
	var lights := [_light("light_point", 0.0), _light("light_point", 2.0)]
	dock.set_selection_nodes(lights)
	var range_label := _label(_row("range"))
	assert_lt(range_label.modulate.a, 1.0, "the default reads lighter")
	assert_null(_row("range").get_node_or_null("Reset_range"), "and has nothing to reset")
	HFDockEntityHandler.on_entities_prop_changed(dock, 25.0, lights, "range")
	dock.set_selection_nodes(lights)
	assert_almost_eq(_label(_row("range")).modulate.a, 1.0, 0.001, "a set value reads plainly")
	var reset := _row("range").get_node_or_null("Reset_range") as Button
	assert_not_null(reset, "with a Reset beside it")
	if reset:
		reset.pressed.emit()
	for light in lights:
		assert_almost_eq(
			float(HFEntityPropUtils.get_entity_data(light).get("range", -1.0)), 10.0, 0.001
		)
	HFEntityPropUtils.set_entity_property(lights[0], "energy", 4.0)
	HFDockEntityHandler.reset_to_default(dock, lights, [])
	assert_almost_eq(_energy(lights[0]), 1.0, 0.001, "Reset to Default puts every one back")


func test_write_defaults_adds_what_is_missing_and_leaves_set_values_alone():
	var light := _light("light_point", 0.0)
	var data := HFEntityPropUtils.get_entity_data(light)
	data.erase("range")
	data.erase("shadows")
	data["energy"] = 5.0
	light.entity_data = data
	dock.set_selection_nodes([light])
	HFDockEntityHandler.write_defaults(dock, [light])
	var after := HFEntityPropUtils.get_entity_data(light)
	assert_almost_eq(float(after.get("range", -1.0)), 10.0, 0.001, "range added")
	assert_eq(after.get("shadows"), false, "shadows added")
	assert_almost_eq(float(after.get("energy", -1.0)), 5.0, 0.001, "energy left as it was")


func test_a_door_and_a_light_together_each_take_only_their_own():
	var door: Node = root.create_brush_from_info(
		{"brush_id": "d1", "size": Vector3(2, 3, 0.2), "center": Vector3(0, 1.5, 0)}
	)
	root.brush_system.tie_brushes_to_entity(["d1"], "func_door", "door_1")
	var light := _light("light_point", 5.0)
	dock.set_selection_nodes([door, light])
	var speed := _row("speed")
	assert_not_null(speed)
	assert_string_contains(_label(speed).text, "(1 of 2)")
	(speed.get_child(1) as SpinBox).value = 6.0
	assert_almost_eq(float(HFEntityPropUtils.get_entity_data(door).get("speed", 0.0)), 6.0, 0.001)
	assert_false(HFEntityPropUtils.get_entity_data(light).has("speed"))
	assert_not_null(_row("energy"), "and the light's own properties too")


func test_the_model_counts_holders_and_sees_sameness():
	var a := _light("light_point", 0.0)
	var b := _light("light_spot", 2.0)
	var rows := HFEntityMultiEdit.rows(dock.entity_defs, [a, b])
	var by_name: Dictionary = {}
	for row in rows:
		by_name[row["name"]] = row
	assert_eq(by_name["energy"]["holders"].size(), 2)
	assert_true(by_name["energy"]["same"])
	assert_true(by_name["energy"]["at_default"])
	assert_eq(by_name["angle"]["holders"], [b])
