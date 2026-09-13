@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Every dock spin that writes a level setting, turned to both ends of its own
## range, against what the level did with the number.
##
## `HFDockConnections.connect_settings()` wires each control straight to
## `level_root.set(property, value)`. The controls carry one range, declared
## where the tab is built; the properties carry another, declared as setters on
## `LevelRoot`. Nothing checks that the two agree, and when they do not the dock
## goes on showing a number the level does not hold.

const DockScene = preload("res://addons/hammerforge/dock.tscn")

## control name on the dock -> the level property it is bound to, from
## connect_settings()'s float_bindings and int_bindings.
const BINDINGS := [
	["bake_chunk_size_spin", "bake_chunk_size"],
	["bake_lightmap_texel", "bake_lightmap_texel_size"],
	["bake_navmesh_cell_size", "bake_navmesh_cell_size"],
	["bake_navmesh_cell_height", "bake_navmesh_cell_height"],
	["bake_navmesh_agent_height", "bake_navmesh_agent_height"],
	["bake_navmesh_agent_radius", "bake_navmesh_agent_radius"],
	["bake_connector_stair_height_spin", "bake_connector_stair_height"],
	["bake_occluder_min_area_spin", "bake_occluder_min_area"],
	["autosave_minutes", "hflevel_autosave_minutes"],
	["autosave_keep", "hflevel_autosave_keep"],
	["bake_connector_width_spin", "bake_connector_width"],
]


func id() -> String:
	return "dock-ranges"


func summary() -> String:
	return "whether each dock spin and the level property behind it agree about the legal range"


func run() -> void:
	await _both_ends_of_every_spin()


func _dock(root: Node3D) -> Node:
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	return dock


func _both_ends_of_every_spin() -> void:
	var root: Node3D = await fresh_root("RangeLevel")
	var dock = await _dock(root)
	await frame()
	var disagreements: Array = []
	for binding in BINDINGS:
		var control: SpinBox = dock.get(binding[0]) as SpinBox
		var property: String = binding[1]
		if control == null:
			note("no control for %s" % property, binding[0])
			continue
		note("%s spin range" % property, [control.min_value, control.max_value, control.step])
		for end in [control.min_value, control.max_value]:
			control.value = end
			control.value_changed.emit(control.value)
			await frame()
			var held = root.get(property)
			var shown: float = float(control.value)
			var kept: bool = is_equal_approx(float(held), shown)
			note(
				"%s: spin set to %s" % [property, shown],
				"level holds %s%s" % [held, "" if kept else "   <-- different"]
			)
			if not kept:
				disagreements.append(
					"%s: the spin allows %s, the level holds %s" % [property, shown, held]
				)
	note("bindings where the two ends disagree", disagreements.size())
	if not disagreements.is_empty():
		flag(
			"dock spins offer values the level refuses, and go on showing them",
			(
				(
					"each of these is a control whose declared range is wider than the setter"
					+ " behind it, so turning the spin to its own end leaves the dock reading one"
					+ " number and the bake using another, with nothing said either way: %s"
				)
				% str(disagreements)
			)
		)
	dock.queue_free()
	await frame()
