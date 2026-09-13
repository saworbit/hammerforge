@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What an entity property is after it has been through the file.
##
## `entities.json` gives a property a type, the Objects tab builds a control for
## that type, and the control writes the value straight into `entity_data`. A
## colour picker writes a `Color`, a vector row writes a `Vector3`. The level is
## then saved as JSON, and JSON has neither.
##
## The property panel reads the values back the next time the entity is
## selected, and the `.map` exporter writes them into the file a compiler reads,
## so both ends of this matter.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")


func id() -> String:
	return "entity-props"


func summary() -> String:
	return "what a colour or vector entity property is after a save and a load"


func run() -> void:
	await _through_the_hflevel()
	await _into_the_map_file()


func _entity(root: Node3D, type_id: String) -> Node3D:
	var entity = DraftEntity.new()
	entity.name = "Probe_%s" % type_id
	entity.entity_type = type_id
	entity.entity_class = type_id
	entity.set_meta("is_entity", true)
	root.add_entity(entity)
	return entity


func _through_the_hflevel() -> void:
	var root: Node3D = await fresh_root("EntityPropLevel")
	var light := _entity(root, "light_point")
	await frame()

	# Exactly what the colour picker and the vector row in the Objects tab write.
	HFEntityPropUtils.set_entity_property(light, "color", Color(0.2, 0.4, 0.8, 1.0))
	HFEntityPropUtils.set_entity_vec3_axis(light, "offset", 0, 16.0)
	HFEntityPropUtils.set_entity_vec3_axis(light, "offset", 1, 32.0)
	HFEntityPropUtils.set_entity_property(light, "energy", 2.5)
	HFEntityPropUtils.set_entity_property(light, "targetname", "lamp_1")
	await frame()
	note("colour as the picker left it", light.entity_data.get("color", null))
	note("vector as the row left it", light.entity_data.get("offset", null))

	var path := "user://vibe_entity_props.hflevel"
	root.save_hflevel(path, true)
	var settled: bool = await HFVibe.settle_save(_tree, root)
	if not settled:
		flag("the save never finished", path)
		return
	var other: Node3D = await fresh_root("EntityPropLevelB")
	other.load_hflevel(path)
	await frame()
	var loaded: Node3D = null
	for child in other.entities_node.get_children():
		if child is DraftEntity:
			loaded = child
	if loaded == null:
		flag("the entity did not survive the round trip at all", path)
		return

	var colour_back = loaded.entity_data.get("color", null)
	var vector_back = loaded.entity_data.get("offset", null)
	var energy_back = loaded.entity_data.get("energy", null)
	var name_back = loaded.entity_data.get("targetname", null)
	note("colour after load", "%s  (%s)" % [colour_back, type_string(typeof(colour_back))])
	note("vector after load", "%s  (%s)" % [vector_back, type_string(typeof(vector_back))])
	note("float after load", "%s  (%s)" % [energy_back, type_string(typeof(energy_back))])
	note("string after load", "%s  (%s)" % [name_back, type_string(typeof(name_back))])

	if typeof(colour_back) != TYPE_COLOR or typeof(vector_back) != TYPE_VECTOR3:
		flag(
			"colour and vector entity properties do not survive a .hflevel save",
			(
				(
					"the Objects tab writes a Color from the colour picker and a Vector3 from the"
					+ " vector row into entity_data, capture_entity_info() duplicates the dictionary"
					+ " as it is, and hflevel_io writes it with JSON.stringify, which has no type"
					+ " for either. They come back as %s and %s. The property panel then feeds that"
					+ " to ColorPickerButton.color / the vector spins, and the .map exporter writes"
					+ " the stringified form into the file a compiler reads."
				)
				% [type_string(typeof(colour_back)), type_string(typeof(vector_back))]
			)
		)

	# What the panel does with whatever came back, which is the path a mapper
	# actually walks: select the entity again and look at the controls.
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = other
	dock.set_selection_nodes([loaded])
	dock._rebuild_entity_props(loaded)
	await frame()
	var picker: ColorPickerButton = null
	for control in dock._entity_props_controls:
		for child in control.get_children():
			if child is ColorPickerButton:
				picker = child
	if picker != null:
		note("what the colour control shows after the round trip", picker.color)
		if picker.color != Color(0.2, 0.4, 0.8, 1.0):
			flag(
				"the colour control comes back a different colour",
				(
					(
						"rebuild_entity_props() branches on `current_val is Color` and then"
						+ " `is String`, so a value that is neither lands on Color.WHITE, and a"
						+ " string Godot cannot read as a colour is black. The picker shows %s"
						+ " where the mapper left %s."
					)
					% [picker.color, Color(0.2, 0.4, 0.8, 1.0)]
				)
			)
	dock.queue_free()
	await frame()


func _into_the_map_file() -> void:
	var root: Node3D = await fresh_root("EntityMapLevel")
	var light := _entity(root, "light_point")
	box(root, Vector3(64, 64, 64))
	await frame()
	HFEntityPropUtils.set_entity_property(light, "color", Color(0.2, 0.4, 0.8, 1.0))
	HFEntityPropUtils.set_entity_property(light, "targetname", "lamp_1")
	await frame()
	var path := "user://vibe_entity_props.map"
	var err: int = int(root.export_map(path, "valve220"))
	note("export_map returned", err)
	var text := FileAccess.get_file_as_string(path)
	var colour_line := ""
	for line in text.split("\n"):
		if line.contains("color") or line.contains("targetname"):
			note("map file line", line.strip_edges())
		if line.contains('"color"'):
			colour_line = line.strip_edges()
	if colour_line.contains("(") or colour_line.contains(","):
		flag(
			"a colour entity property is written into the .map file in Godot's own notation",
			(
				(
					"HFMapAdapter.format_entity_properties() writes str(value) for every property,"
					+ " so the Color the Objects tab stored comes out as %s. A .map file exists to"
					+ " be read by something else, and no Quake-family compiler or editor parses"
					+ " that: the value they expect is numbers. The same text comes back through"
					+ " import_map() as a plain String, so the type is gone on a round trip through"
					+ " HammerForge's own importer as well."
				)
				% colour_line
			)
		)

	# What HammerForge's own importer makes of what it just wrote.
	var back: Node3D = await fresh_root("EntityMapLevelB")
	back.import_map(path)
	await frame()
	for child in back.entities_node.get_children():
		if child is DraftEntity and child.entity_data.has("color"):
			var value = child.entity_data["color"]
			note("colour after a .map round trip", "%s  (%s)" % [value, type_string(typeof(value))])
