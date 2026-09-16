extends GutTest

## An entity class says what it fires and what it answers to.
##
## `entities.json` shipped three entries, none of which declared any I/O names,
## while the wiring system, the six built-in connection presets and the overlay's
## colour table all assumed strings like `OnTrigger`, `Open` and `TurnOn`. The
## form is free text, so a mapper had to know those strings from the presets
## rather than from the entity they were wiring, and nothing checked a typo
## against anything (#613).

const HFIOVisualizer = preload("res://addons/hammerforge/systems/hf_io_visualizer.gd")
const HFIOPresets = preload("res://addons/hammerforge/systems/hf_io_presets.gd")
const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")
const HFIOWiringPanel = preload("res://addons/hammerforge/ui/hf_io_wiring_panel.gd")
const HFEntityDefType = preload("res://addons/hammerforge/hf_entity_def.gd")

const PRESET_PATH := "user://test_entity_io_vocabulary_tmp.json"

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
	s.source_code = (
		"extends Node3D\n"
		+ "var entities_node: Node3D\n"
		+ "var draft_brushes_node: Node3D\n"
		+ "var entity_definitions: Dictionary = {}\n"
		+ 'var entity_definitions_path: String = ""\n'
		+ "var entity_system = null\n"
		+ "func _assign_owner(node: Node) -> void:\n"
		+ "\tpass\n"
	)
	s.reload()
	return s


func _defined_entity(entity_name: String, entity_class: String) -> Node3D:
	var e = Node3D.new()
	e.name = entity_name
	e.set_meta("is_entity", true)
	e.set_meta("brush_entity_class", entity_class)
	root.entities_node.add_child(e)
	return e


func _offered(picker: OptionButton) -> Array:
	var out: Array = []
	for i in range(1, picker.item_count):
		out.append(picker.get_item_text(i))
	return out


# ===========================================================================
# The form offers the names the definition declares
# ===========================================================================


func test_the_output_box_offers_the_names_the_source_class_declares():
	root.entity_definitions["button_x"] = {
		"classname": "button_x",
		"outputs": ["OnPressed", "OnTrigger"],
		"inputs": [],
	}
	panel.set_source_entity(_defined_entity("button_1", "button_x"))
	assert_eq(
		_offered(panel._wire_output_pick),
		["OnPressed", "OnTrigger"],
		"the preset vocabulary is discoverable from the entity now"
	)
	assert_false(panel._wire_output_pick.disabled)


func test_picking_an_output_name_fills_the_free_text_box():
	root.entity_definitions["button_x"] = {"classname": "button_x", "outputs": ["OnPressed"]}
	panel.set_source_entity(_defined_entity("button_1", "button_x"))
	panel._wire_output_pick.select(1)
	panel._on_output_name_picked(1)
	assert_eq(panel._wire_output.text, "OnPressed", "the form stays free text, it is just filled")
	assert_eq(panel._wire_output_pick.selected, 0, "and the picker resets so it reads as a picker")


func test_the_input_box_offers_the_names_the_target_class_declares():
	root.entity_definitions["button_x"] = {"classname": "button_x", "outputs": ["OnPressed"]}
	root.entity_definitions["door_x"] = {
		"classname": "door_x",
		"inputs": ["Open", "Close", "Toggle"],
	}
	var button := _defined_entity("button_1", "button_x")
	_defined_entity("door_1", "door_x")
	panel.set_source_entity(button)
	for i in panel._wire_target.item_count:
		if panel._wire_target.get_item_text(i).begins_with("door_1"):
			panel._wire_target.select(i)
			panel._on_wire_target_selected(i)
	assert_eq(
		_offered(panel._wire_input_pick),
		["Open", "Close", "Toggle"],
		"the inputs on offer belong to what is being wired to"
	)


func test_a_class_that_declares_nothing_leaves_the_picker_disabled():
	root.entity_definitions["plain_x"] = {"classname": "plain_x"}
	panel.set_source_entity(_defined_entity("plain_1", "plain_x"))
	assert_true(panel._wire_output_pick.disabled, "nothing declared, nothing to offer")
	assert_eq(panel._wire_output.text, "", "and the free text box is untouched")


# ===========================================================================
# The shipped definitions carry the vocabulary the presets use
# ===========================================================================


func _shipped() -> Dictionary:
	var out: Dictionary = {}
	for def in HFEntityDefType.load_definitions("res://addons/hammerforge/entities.json"):
		out[def.classname] = def
	return out


func test_the_door_answers_to_the_names_the_presets_fire_at_it():
	var defs := _shipped()
	assert_true(defs.has("door_basic"), "door_basic is still shipped")
	if defs.has("door_basic"):
		var door = defs["door_basic"]
		assert_true(door.inputs.has("Open"), "the Door Open preset fires Open at a door")
		assert_true(door.inputs.has("Toggle"), "and the Button preset fires Toggle")


func test_the_light_answers_to_the_preset_input_name():
	var defs := _shipped()
	assert_true(defs.has("light_point"))
	if defs.has("light_point"):
		assert_true(
			defs["light_point"].inputs.has("TurnOn"), "three presets fire TurnOn at a light"
		)


func test_declared_names_survive_the_definition_round_trip():
	var defs := _shipped()
	if defs.has("door_basic"):
		var round_tripped = HFEntityDefType.from_dict(defs["door_basic"].to_dict())
		assert_true(round_tripped.inputs.has("Open"), "to_dict has to write them back")
		assert_eq(round_tripped.outputs, defs["door_basic"].outputs)


func test_declared_names_are_stripped_and_deduplicated():
	var def = HFEntityDefType.from_dict({"id": "x", "outputs": [" OnUse ", "OnUse", "", "OnBreak"]})
	assert_eq(def.outputs, ["OnUse", "OnBreak"])


# ===========================================================================
# The door no longer previews as a light bulb
# ===========================================================================


func test_the_door_does_not_preview_with_the_light_bulb_mesh():
	var raw := FileAccess.get_file_as_string("res://addons/hammerforge/entities.json")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "entities.json must parse")
	if parsed is Dictionary:
		var door: Dictionary = parsed.get("door_basic", {})
		var preview: Dictionary = door.get("preview", {})
		assert_eq(str(preview.get("type", "")), "box", "a door proxy that needs no asset")
		assert_false(
			str(preview.get("path", "")).contains("light_bulb"),
			"the only mesh in the plugin is a bulb, and a door is not one"
		)


func test_the_draft_entity_preview_builder_knows_the_box_type():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/draft_entity.gd")
	assert_false(source.is_empty(), "draft_entity.gd must be readable")
	assert_true(source.contains('"box":'), "the box preview arm has to exist for the JSON to work")
	assert_true(source.contains("BoxMesh.new()"))
