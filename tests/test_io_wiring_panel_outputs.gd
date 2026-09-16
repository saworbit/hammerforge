extends GutTest

## One list, and it is the one you can delete from.
##
## The Objects tab built two lists of the same entity's connections, one above the
## other, in two spellings — `[once]` on the plainer one and `[1x]` on the wiring
## panel. Only the plainer one had a Remove beside it, and the panel is the surface
## the user guide describes and a mapper works in. #616 moved the Remove onto the
## panel and deleted the duplicate.

const HFIOVisualizer = preload("res://addons/hammerforge/systems/hf_io_visualizer.gd")
const HFIOPresets = preload("res://addons/hammerforge/systems/hf_io_presets.gd")
const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")
const HFIOWiringPanel = preload("res://addons/hammerforge/ui/hf_io_wiring_panel.gd")

const PRESET_PATH := "user://test_wiring_panel_outputs_tmp.json"

var root: Node3D
var sys: HFEntitySystem
var viz: HFIOVisualizer
var presets: HFIOPresets
var panel: HFIOWiringPanel


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
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
	root.entity_system = sys
	viz = HFIOVisualizer.new(root)
	presets = HFIOPresets.new(root)
	presets.load_presets(PRESET_PATH)
	panel = HFIOWiringPanel.new()
	add_child_autoqfree(panel)
	panel.setup(sys, presets, viz)


func after_each():
	viz.cleanup()
	if FileAccess.file_exists(PRESET_PATH):
		DirAccess.remove_absolute(PRESET_PATH)
	root = null
	sys = null
	viz = null
	presets = null
	panel = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var entities_node: Node3D
var draft_brushes_node: Node3D
var entity_definitions: Dictionary = {}
var entity_definitions_path: String = ""
var entity_system = null

func _assign_owner(node: Node) -> void:
	pass
"""
	s.reload()
	return s


func _entity(entity_name: String) -> Node3D:
	var e = Node3D.new()
	e.name = entity_name
	e.set_meta("is_entity", true)
	root.entities_node.add_child(e)
	return e


func _wired_button() -> Node3D:
	var button := _entity("button_1")
	_entity("door_1")
	sys.add_entity_output(button, "OnPressed", "door_1", "Open")
	sys.add_entity_output(button, "OnPressed", "door_1", "Lock")
	panel.set_source_entity(button)
	return button


# ===========================================================================
# The list can be acted on
# ===========================================================================


func test_the_panels_output_list_has_a_remove_beside_it():
	_wired_button()
	assert_not_null(panel._outputs_remove, "the surface a mapper wires in needs the Remove")
	assert_eq(panel._outputs_list.item_count, 2)


func test_remove_is_disabled_until_a_connection_is_selected():
	_wired_button()
	assert_true(panel._outputs_remove.disabled, "nothing selected, nothing to remove")
	panel._outputs_list.select(0)
	panel._on_outputs_list_selected(0)
	assert_false(panel._outputs_remove.disabled)


func test_removing_the_selected_output_takes_that_one():
	var button := _wired_button()
	panel._outputs_list.select(0)
	panel._on_outputs_list_selected(0)
	panel._on_outputs_remove_pressed()
	var left = sys.get_entity_outputs(button)
	assert_eq(left.size(), 1, "one connection removed")
	assert_eq(str(left[0].get("input_name", "")), "Lock", "and it was the selected one")
	assert_eq(panel._outputs_list.item_count, 1, "the list redraws itself")


func test_removing_announces_the_change_so_the_dock_can_register_undo():
	var button := _wired_button()
	var opened: Array = []
	var removed: Array = []
	panel.will_change.connect(func(action): opened.append(action))
	panel.connection_removed.connect(func(source, index): removed.append([source, index]))
	panel._outputs_list.select(1)
	panel._on_outputs_list_selected(1)
	panel._on_outputs_remove_pressed()
	assert_eq(opened, ["Remove Entity Output"], "the dock takes the before state on this")
	assert_eq(removed.size(), 1, "and commits on this")
	if removed.size() == 1:
		assert_eq(removed[0][0], button)
		assert_eq(removed[0][1], 1)


func test_removing_with_nothing_selected_changes_nothing():
	var button := _wired_button()
	var opened: Array = []
	panel.will_change.connect(func(action): opened.append(action))
	panel._on_outputs_remove_pressed()
	assert_eq(sys.get_entity_outputs(button).size(), 2)
	assert_true(opened.is_empty(), "an undo step must not be opened and left open")


# ===========================================================================
# One label builder
# ===========================================================================


func test_a_fire_once_connection_is_spelled_one_way():
	var label := HFIOWiringPanel.connection_label(
		{
			"output_name": "OnPressed",
			"target_name": "door_1",
			"input_name": "Open",
			"fire_once": true
		}
	)
	assert_string_contains(label, "[once]")
	assert_false(label.contains("[1x]"), "the two spellings were the duplicated formatter")


func test_a_delayed_connection_carries_its_delay():
	var label := HFIOWiringPanel.connection_label(
		{"output_name": "OnPressed", "target_name": "door_1", "input_name": "Open", "delay": 1.5}
	)
	assert_string_contains(label, "(1.5s)")


func test_the_objects_tab_no_longer_builds_a_second_list():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/ui/entity_tab_builder.gd")
	assert_false(source.is_empty(), "entity_tab_builder.gd must be readable")
	assert_false(source.contains("dock.io_list"), "the duplicate list is gone")
	assert_false(source.contains("dock.io_remove_btn"), "and so is the Remove that served it")


func test_only_one_label_builder_is_left():
	var handler := FileAccess.get_file_as_string("res://addons/hammerforge/dock_entity_handler.gd")
	assert_false(handler.is_empty(), "dock_entity_handler.gd must be readable")
	assert_false(handler.contains("[once]"), "the second formatter is gone")
	assert_false(handler.contains("[1x]"))
