extends GutTest

## The Entity panel for a class read from an FGD (#1721): choices by their labels,
## flags as a box each, and a tick that sets its bit.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFDockEntityHandler = preload("res://addons/hammerforge/dock_entity_handler.gd")

const FGD := "user://test_fgd_entity_panel.fgd"
const TEXT := """
@PointClass size(-8 -8 -8, 8 8 8) = light_bulb : "A small light"
[
	style(choices) : "Style" : 10 =
	[
		0 : "Normal"
		10 : "Fluorescent flicker"
	]
	spawnflags(flags) =
	[
		1 : "Initially dark" : 0
		2 : "Toggle" : 1
	]
	input TurnOn(void)
	output OnTurnedOn(void)
]
"""

var root: LevelRoot
var dock: Node
var bulb: Node3D


func before_each() -> void:
	var file := FileAccess.open(FGD, FileAccess.WRITE)
	file.store_string(TEXT)
	file.close()
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	root.entity_definitions_path = FGD
	add_child_autoqfree(root)
	root.entity_system.load_entity_definitions()
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	dock._load_entity_definitions()
	bulb = root._create_entity_from_map({"classname": "light_bulb", "origin": Vector3.ZERO})
	dock._selection_nodes = [bulb]
	HFDockEntityHandler.rebuild_entity_props(dock, bulb)


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FGD))
	root = null
	dock = null
	bulb = null


func _row(label: String) -> HBoxContainer:
	for row in dock._entity_props_controls:
		if row is HBoxContainer and (row.get_child(0) as Label).text == label:
			return row
	return null


func test_choices_show_their_labels_and_pick_their_value():
	var row := _row("Style:")
	assert_not_null(row, "a Style row")
	if row == null:
		return
	var picker := row.get_child(1) as OptionButton
	assert_not_null(picker)
	if picker:
		assert_eq(picker.get_item_text(0), "Normal")
		assert_eq(picker.get_item_text(1), "Fluorescent flicker")
		assert_eq(picker.selected, 1, "the default, 10, is picked")


func test_each_flag_is_a_box_and_a_tick_sets_its_bit():
	var row := _row("spawnflags:")
	assert_not_null(row, "a spawnflags row")
	if row == null:
		return
	var boxes: Array = row.find_children("*", "CheckBox", true, false)
	assert_eq(boxes.size(), 2)
	if boxes.size() != 2:
		return
	assert_eq(boxes[0].text, "Initially dark")
	assert_false(boxes[0].button_pressed)
	assert_true(boxes[1].button_pressed, "Toggle is on by default")
	boxes[0].toggled.emit(true)
	var data := HFEntityPropUtils.get_entity_data(bulb)
	assert_eq(int(data.get("spawnflags", -1)), 3, "both bits now")
	HFDockEntityHandler.rebuild_entity_props(dock, bulb)
	boxes = _row("spawnflags:").find_children("*", "CheckBox", true, false)
	boxes[1].toggled.emit(false)
	assert_eq(int(HFEntityPropUtils.get_entity_data(bulb).get("spawnflags", -1)), 1)


func test_the_wiring_panel_offers_the_class_inputs_and_outputs():
	var definition: Dictionary = root.get_entity_definition("light_bulb")
	assert_eq(definition.get("inputs", []), ["TurnOn"])
	assert_eq(definition.get("outputs", []), ["OnTurnedOn"])
