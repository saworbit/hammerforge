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


## The five `@export_range` properties on `LevelRoot`. The annotation constrains
## the Inspector widget and nothing else: a value set from a script, a `.hflevel`
## or an undo replay goes straight to the setter, or straight onto the field when
## there is no setter.
const RANGED := [
	["bake_collision_layer_index", 1, 32],
	["hflevel_autosave_minutes", 1, 60],
	["hflevel_autosave_keep", 1, 50],
	["draft_pick_layer_index", 1, 32],
	["grid_major_line_frequency", 1, 16],
]


func _export_ranges_are_only_the_inspectors() -> void:
	var root: Node3D = await fresh_root()
	var leaky: Array = []
	for entry in RANGED:
		var prop: String = entry[0]
		var lo = entry[1]
		var hi = entry[2]
		var kept: Array = []
		for candidate in [lo - 1, -5, 0, hi + 1, 100000]:
			root.set(prop, candidate)
			var got = root.get(prop)
			if got == candidate and (candidate < lo or candidate > hi):
				kept.append(candidate)
		note("%s (@export_range %s..%s)" % [prop, lo, hi], "kept out of range: %s" % str(kept))
		if not kept.is_empty():
			leaky.append("%s kept %s" % [prop, str(kept)])
	if not leaky.is_empty():
		flag(
			"%d @export_range properties hold values outside their own range" % leaky.size(),
			(
				("%s. " % str(leaky))
				+ "@export_range constrains the Inspector spinner; it is not a runtime "
				+ "clamp. Three of these have no setter at all, so the value lands on the "
				+ "field, is written back out by capture_hflevel_settings(), and comes back "
				+ "on the next load. The consumers defend themselves to different degrees: "
				+ "_layer_from_index() clamps to 1..32 at use, the grid shader does "
				+ "max(major_line_frequency, 1.0), and _set_hflevel_autosave_minutes() "
				+ "clamps the bottom with max(1, value) and not the top -- so an autosave "
				+ "interval of 100000 minutes is accepted and silently means never"
			)
		)


func run() -> void:
	await _export_ranges_are_only_the_inspectors()
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
