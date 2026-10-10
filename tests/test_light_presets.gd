extends GutTest

## Light presets, and a projector texture on lights (#990).
##
## Every lamp started white, energy 1, range 10, and a warm ceiling lamp was
## typed in by hand. A spot had no projector slot, so its beam was always a plain
## cone. Presets live in entities.json as property values per class, so a
## project's overlay file can add its own, and are applied from the Entity panel
## or placed straight from the palette.

const CollationTests = preload("res://tests/test_undo_collation.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFDockEntityHandler = preload("res://addons/hammerforge/dock_entity_handler.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")
const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
const DropHandler = preload("res://addons/hammerforge/plugin_drop_handler.gd")

const GRATE := "res://addons/hammerforge/projectors/grate.png"


class FakeEditor:
	extends RefCounted

	func get_selection():
		return null


class FakePlugin:
	extends RefCounted

	var active_root = null
	var last_3d_camera: Camera3D = null
	var last_3d_mouse_pos := Vector2.ZERO
	var hf_selection: Array = []

	func get_editor_interface():
		return FakeEditor.new()


var root: LevelRoot
var dock: Node


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


func after_each() -> void:
	root = null
	dock = null


func _definition(class_name_key: String) -> Dictionary:
	return HFEntityPropUtils.find_definition(dock.entity_defs, class_name_key)


func _light(class_name_key: String) -> Node3D:
	var light := root._create_entity_from_map({"classname": class_name_key, "origin": Vector3.ZERO})
	dock._selection_nodes = [light]
	return light


func _row(label: String) -> HBoxContainer:
	for row in dock._entity_props_controls:
		if row is HBoxContainer and (row.get_child(0) as Label).text == label:
			return row
	return null


func test_every_light_preset_sets_only_what_its_class_declares():
	for key in ["light_point", "light_spot", "light_directional"]:
		var definition := _definition(key)
		var names := HFEntityPropUtils.preset_names(definition)
		assert_false(names.is_empty(), "%s offers presets" % key)
		var declared := {}
		for prop in definition.get("properties", []):
			declared[str(prop.get("name", ""))] = true
		for preset_name in names:
			var raw: Dictionary = definition["presets"][preset_name]
			for prop_name in raw:
				assert_true(
					declared.has(prop_name), "%s %s sets %s" % [key, preset_name, prop_name]
				)
	assert_true("Sun" in HFEntityPropUtils.preset_names(_definition("light_directional")))


func test_a_preset_value_takes_its_propertys_type():
	var values := HFEntityPropUtils.preset_values(_definition("light_point"), "Warm Ceiling")
	assert_true(values.get("color") is Color, "a colour, not the text it was written as")
	assert_true(values.get("energy") is float)


func test_picking_a_preset_in_the_panel_sets_the_light():
	var lamp := _light("light_point")
	HFDockEntityHandler.rebuild_entity_props(dock, lamp)
	var row := _row("Preset:")
	assert_not_null(row, "a light's panel starts with its presets")
	if row == null:
		return
	var picker: OptionButton = row.get_child(1)
	var index := -1
	for i in picker.item_count:
		if picker.get_item_text(i) == "Practical":
			index = i
	assert_gt(index, 0, "Practical is offered")
	picker.select(index)
	picker.item_selected.emit(index)
	assert_almost_eq(float(lamp.entity_data.get("energy")), 0.5, 0.001, "the preset's energy")
	assert_almost_eq(float(lamp.entity_data.get("range")), 4.0, 0.001, "and range")
	assert_eq(lamp.entity_data.get("color"), Color("#ffc27a"), "and colour")


func test_a_preset_is_one_undo_step():
	# Registered the way the panel registers it, against the stand-in.
	var lamp := _light("light_point")
	lamp.entity_data["energy"] = 3.0
	var fake = CollationTests.FakeUndoRedo.new()
	var values := HFEntityPropUtils.preset_values(_definition("light_point"), "Warm Ceiling")
	var scope_paths := [root.get_path_to(lamp)]
	var before: Dictionary = root.capture_brush_scope([], scope_paths)
	HFUndoHelper.register_action(
		fake,
		root,
		"Preset Warm Ceiling",
		0,
		"set_entity_properties",
		[lamp, values],
		before,
		false,
		true,
		[],
		scope_paths
	)
	assert_eq(fake.entries.size(), 1, "one step for every value it set")
	assert_almost_eq(float(lamp.entity_data.get("energy")), 1.2, 0.001)
	fake.undo()
	assert_almost_eq(float(lamp.entity_data.get("energy")), 3.0, 0.001, "undo puts it back")


func test_the_palette_offers_each_preset_and_places_with_it():
	var preset_buttons: Array = []
	for button in dock.entity_palette_buttons:
		if button.entity_id == "light_spot" and not button.preset_values.is_empty():
			preset_buttons.append(button)
	assert_eq(preset_buttons.size(), 3, "one button per spot preset")
	if preset_buttons.is_empty():
		return
	var button = preset_buttons[0]
	var data: Dictionary = dock._make_entity_drag_data(
		button.entity_id, button.entity_def, null, button.preset_values
	)
	assert_true(data.has("properties"), "the drag carries the preset's values")

	# Dropped on a floor, the light is placed with those values.
	var floor_info := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": Vector3(8, 1, 8),
		"center": Vector3(0, -0.5, 0),
		"operation": CSGShape3D.OPERATION_UNION,
	}
	root.create_brush_from_info(floor_info)
	var camera := Camera3D.new()
	add_child_autoqfree(camera)
	camera.global_position = Vector3(0, 10, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	var plugin := FakePlugin.new()
	plugin.active_root = root
	plugin.last_3d_camera = camera
	DropHandler.handle_entity_drop(plugin, camera.unproject_position(Vector3.ZERO), data)
	assert_eq(plugin.hf_selection.size(), 1, "fixture: the drop placed a light")
	if plugin.hf_selection.is_empty():
		return
	var placed: Node3D = plugin.hf_selection[0]
	for prop_name in data["properties"]:
		assert_eq(placed.entity_data.get(prop_name), data["properties"][prop_name], prop_name)


func test_a_spot_with_a_projector_exports_with_it_and_casts_shadows():
	var spot := _light("light_spot")
	spot.entity_data["projector"] = GRATE
	var built: Node = root._playtest_node_for_entity(spot)
	assert_true(built is SpotLight3D, "fixture: a spot builds a SpotLight3D")
	if not (built is SpotLight3D):
		return
	var light := built as SpotLight3D
	assert_true(light.light_projector is Texture2D, "the projector is the texture")
	assert_true(light.shadow_enabled, "a projector needs shadows, so they are on")
	light.free()


func test_a_light_with_no_projector_keeps_its_shadow_setting():
	var spot := _light("light_spot")
	var built := root._playtest_node_for_entity(spot) as SpotLight3D
	assert_null(built.light_projector)
	assert_false(built.shadow_enabled, "off, as the class default says")
	built.free()


func test_the_projector_tooltip_names_the_compatibility_renderer():
	var spot := _light("light_spot")
	HFDockEntityHandler.rebuild_entity_props(dock, spot)
	var row := _row("Projector:")
	assert_not_null(row, "the projector is in the panel")
	if row == null:
		return
	var field: Control = row.get_child(1)
	assert_string_contains(field.tooltip_text, "Compatibility", "said up front")
	assert_eq(row.get_child(0).mouse_filter, Control.MOUSE_FILTER_PASS, "the label shows it too")
