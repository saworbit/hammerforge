@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Dropping things into the viewport, and the brush presets that are one of them.
##
## `HFPluginDropHandler` classifies drag data by a `type` string alone and then
## reads the payload separately. `can_drop_data()` is what the viewport asks
## before it shows the drop cursor, and `drop_data()` is what runs on release.
## When the first says yes and the second finds nothing to do, the mapper gets a
## cursor that promises a drop and a release that does nothing.
##
## The brush-preset half is here because a preset is one of the four drag
## sources, and because the Save Preset button names the file itself.

const DropHandler = preload("res://addons/hammerforge/plugin_drop_handler.gd")
const BrushPresetType = preload("res://addons/hammerforge/brush_preset.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")

## Every drag payload the viewport accepts, paired with the field its handler
## needs and a version of it that is missing that field.
const WHOLE := [
	{"type": "hammerforge_entity", "entity_id": "light"},
	{"type": "hammerforge_brush_preset", "preset_path": "res://nope.tres"},
	{"type": "hammerforge_prefab", "path": "res://nope.hfprefab"},
	{"type": "hammerforge_material", "index": 0},
]

const HOLLOW := [
	{"type": "hammerforge_entity"},
	{"type": "hammerforge_brush_preset"},
	{"type": "hammerforge_prefab"},
	{"type": "hammerforge_material"},
]


func id() -> String:
	return "viewport-drop"


func summary() -> String:
	return "what the viewport accepts as a drop, and how a saved brush preset is named"


func run() -> void:
	await _what_can_drop_data_accepts()
	await _what_a_preset_carries()
	await _how_presets_are_named()


## The gate the viewport uses before it shows a drop cursor.
func _what_can_drop_data_accepts() -> void:
	for payload in WHOLE:
		note("can_drop_data, whole %s" % payload["type"], DropHandler.can_drop_data(payload))
	var accepted_hollow: Array = []
	for payload in HOLLOW:
		var ok: bool = DropHandler.can_drop_data(payload)
		note("can_drop_data, %s with no payload" % payload["type"], ok)
		if ok:
			accepted_hollow.append(payload["type"])
	for junk in [null, "a string", 7, [], {}, {"type": "something_else"}]:
		note("can_drop_data, %s" % str(junk), DropHandler.can_drop_data(junk))
	if accepted_hollow.size() == HOLLOW.size():
		note(
			"every drag type is accepted on its type string alone",
			(
				"each handler re-reads the payload and returns early when it is missing,"
				+ " so the viewport shows a drop cursor for %s and the release does nothing"
				% str(accepted_hollow)
			)
		)

	# A material drop names the failure. The other three do not.
	note(
		"handle_material_drop tells the mapper when it finds no face",
		'shows the toast "No face under drop position"'
	)
	note(
		"handle_entity_drop / handle_brush_preset_drop / handle_prefab_drop on a bad payload",
		"return with no toast, no log line and no change"
	)


## What a preset records, against what placing a brush needs.
func _what_a_preset_carries() -> void:
	var preset = BrushPresetType.new()
	var fields: Array = []
	for property in preset.get_property_list():
		var usage := int(property.get("usage", 0))
		if usage & PROPERTY_USAGE_STORAGE and usage & PROPERTY_USAGE_EDITOR:
			var name := str(property.get("name", ""))
			if name != "" and not name.begins_with("script"):
				fields.append(name)
	note("fields a BrushPreset stores", fields)
	note(
		"what handle_brush_preset_drop adds on top",
		"the dock's currently selected material, not one the preset chose"
	)


## Save Preset writes the file and names it, with no dialog. The name it picks
## counts the buttons that are there.
func _how_presets_are_named() -> void:
	var root: Node3D = await fresh_root("PresetDock")
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	await frame()

	note("the dock's own presets directory", str(dock.get("presets_dir")))
	# Redirected, so the scenario never writes a .tres into the checkout.
	dock.presets_dir = "user://vibe_presets"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dock.presets_dir))
	dock._load_presets()
	await frame()
	var before: int = dock.preset_buttons.size()
	note("presets already there", before)

	var names: Array = []
	var paths: Array = []
	for i in range(3):
		dock._on_save_preset()
		await frame()
	for button in dock.preset_buttons:
		names.append(str(button.text))
		paths.append(str(button.get_meta("preset_path", "")))
	note("names after three saves", names)

	# Delete the middle one and save again: the suggested name counts buttons.
	if dock.preset_buttons.size() >= 3:
		var middle = dock.preset_buttons[1]
		dock._delete_preset(middle)
		await frame()
		note("names after deleting the middle one", _button_names(dock))
		dock._on_save_preset()
		await frame()
		var after := _button_names(dock)
		note("names after saving once more", after)
		var seen: Dictionary = {}
		var duplicates: Array = []
		for name in after:
			if seen.has(name):
				duplicates.append(name)
			seen[name] = true
		if not duplicates.is_empty():
			known(
				513,
				"two saved brush presets can end up with the same name in the list",
				(
					"_suggest_preset_name() is 'Preset N' counting the buttons on screen,"
					+ " so after deleting one from the middle the next save reuses a name that"
					+ " is still in use. _unique_preset_path() makes the *file* unique and"
					+ " leaves resource_name alone, and resource_name is what the button shows"
					+ " -- the list now reads %s with %s twice" % [str(after), str(duplicates)]
				)
			)

	# Clean up what the scenario wrote. _delete_preset() rebuilds the button list
	# through _load_presets(), so the buttons captured before the first delete are
	# freed by the second -- take the live head of the list each time round.
	while dock.preset_buttons.size() > before:
		var count_before: int = dock.preset_buttons.size()
		dock._delete_preset(dock.preset_buttons[0])
		await frame()
		if dock.preset_buttons.size() >= count_before:
			break
	note("presets left behind", dock.preset_buttons.size())
	dock.queue_free()


func _button_names(dock: Node) -> Array:
	var out: Array = []
	for button in dock.preset_buttons:
		out.append(str(button.text))
	return out
