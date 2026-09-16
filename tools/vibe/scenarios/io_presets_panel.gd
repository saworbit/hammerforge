@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The I/O wiring panel's preset row: Apply, Save, and what the list looks like
## after a session of using them.
##
## An I/O preset is a named bundle of connections. The panel offers two buttons
## for them and the store behind it offers three operations, so what is worth
## measuring is the third one -- whether anything a mapper puts into that list
## can be taken back out, and whether the list stays readable while they do.

const PanelType = preload("res://addons/hammerforge/ui/hf_io_wiring_panel.gd")
const PresetsType = preload("res://addons/hammerforge/systems/hf_io_presets.gd")


func id() -> String:
	return "io-presets-panel"


func summary() -> String:
	return "what the wiring panel's Save preset button adds to the preset list, and how it comes out"


func run() -> void:
	await _saving_the_same_entity_twice()
	await _applying_a_preset_twice()


func _entity(root: Node3D, name_str: String) -> Node:
	return (
		root
		. _restore_entity_from_info(
			{
				"entity_type": "func_button",
				"entity_class": "func_button",
				"transform": Transform3D(Basis.IDENTITY, Vector3.ZERO),
				"properties": {},
				"name": name_str,
				"entity_name": name_str,
			}
		)
	)


func _panel(root: Node3D, presets, entity: Node) -> Control:
	var panel = PanelType.new()
	_tree.get_root().add_child(panel)
	await frame()
	panel.setup(root.entity_system, presets, root.io_visualizer)
	panel.set_source_entity(entity)
	await frame()
	return panel


func _saving_the_same_entity_twice() -> void:
	var root: Node3D = await fresh_root("PresetLevel")
	var presets = PresetsType.new(root)
	presets.load_presets("user://vibe_io_presets_a.json")
	var door = _entity(root, "Door_A")
	var light = _entity(root, "Light_A")
	await frame()
	root.entity_system.add_entity_output(door, "OnOpen", "Light_A", "TurnOn", "", 0.0, false)
	await frame()
	var panel = await _panel(root, presets, door)

	var builtin_count: int = PresetsType.BUILTIN_PRESETS.size()
	note("built-in presets", builtin_count)
	panel._on_preset_save()
	await frame()
	panel._on_preset_save()
	await frame()
	panel._on_preset_save()
	await frame()
	var all: Array = presets.get_all_presets()
	var names: Array = []
	for p in all:
		names.append(str(p.get("name", "")))
	note("presets after pressing Save three times on one entity", names.slice(builtin_count))
	var seen: Dictionary = {}
	var dupes: Array = []
	for n in names:
		if seen.has(n):
			if not dupes.has(n):
				dupes.append(n)
		seen[n] = true
	note("names appearing more than once in the list", dupes)
	if not dupes.is_empty():
		known(
			557,
			"pressing Save preset twice on one entity makes two presets with the same name",
			(
				(
					"`_on_preset_save()` always names the preset 'From <entity>' and"
					+ " `add_user_preset()` checks only that the name is not empty, so the"
					+ " dropdown ends up reading %s and nothing distinguishes the entries:"
					+ " Apply picks by position in the list"
				)
				% str(names.slice(builtin_count))
			)
		)

	# And what a mapper does about an entry they did not want.
	var has_remove_ui := false
	for child in _walk(panel):
		if child is Button and str(child.text).to_lower().contains("delete"):
			has_remove_ui = true
	note("a Delete/Remove button anywhere on the panel", has_remove_ui)
	note("preset row buttons", _button_labels(panel))
	if not has_remove_ui:
		known(
			558,
			"nothing in the editor can remove a user I/O preset",
			(
				"`HFIOPresets.remove_user_preset()` exists and is covered by"
				+ " tests/test_io_presets.gd, and has no caller in the plugin. The panel offers"
				+ " Apply and Save only, so the list is append-only and the only way to take an"
				+ " entry out is to hand-edit the JSON under user://"
			)
		)
	panel.queue_free()
	await frame()


func _applying_a_preset_twice() -> void:
	var root: Node3D = await fresh_root("ApplyLevel")
	var presets = PresetsType.new(root)
	presets.load_presets("user://vibe_io_presets_b.json")
	var button = _entity(root, "Button_A")
	var door = _entity(root, "Door_A")
	await frame()
	var preset: Dictionary = PresetsType.BUILTIN_PRESETS[1]
	note("preset", preset.get("name", ""))
	var first: int = presets.apply_preset(button, preset, {"door": "Door_A"})
	await frame()
	var after_first: int = root.entity_system.get_entity_outputs(button).size()
	var second: int = presets.apply_preset(button, preset, {"door": "Door_A"})
	await frame()
	var after_second: int = root.entity_system.get_entity_outputs(button).size()
	note("applied once", "%d reported, %d outputs on the entity" % [first, after_first])
	note("applied again", "%d reported, %d outputs on the entity" % [second, after_second])
	if after_second > after_first:
		note(
			"applying the same preset twice doubles the connections",
			(
				"add_entity_output() does not look for an identical connection, so the"
				+ " entity now fires the same input twice"
			)
		)
	# An unmapped tag falls through to the tag itself as a target name.
	var loose: int = presets.apply_preset(door, preset, {})
	await frame()
	var outs: Array = root.entity_system.get_entity_outputs(door)
	var targets: Array = []
	for o in outs:
		targets.append(str(o.get("target_name", "")))
	note("applying with no target map wired to", targets)
	var index: Dictionary = root.entity_system.build_name_index()
	var dangling: Array = []
	for t in targets:
		if not index.has(t):
			dangling.append(t)
	note("of those, targets no entity answers to", dangling)
	if not dangling.is_empty():
		note(
			"an unmapped preset tag becomes a literal target name",
			(
				"apply_preset() does `target_map.get(tag, tag)`, so leaving the map blank"
				+ (
					" wires to an entity literally called %s and reports it as a success"
					% str(dangling)
				)
			)
		)


func _walk(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func _button_labels(panel: Control) -> Array:
	var out: Array = []
	for child in _walk(panel):
		if child is Button and not (child is CheckBox) and not (child is OptionButton):
			out.append(str(child.text))
	return out
