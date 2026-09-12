@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The numbers on `LevelRoot` itself: grid snap, rotate snap, and the bake
## settings.
##
## Most of these are edited through a dock SpinBox, and a SpinBox has a range.
## `apply_hflevel_settings()` does not -- it is a flat list of
## `root.x = float(settings.get("x", root.x))`, so every one of these comes back
## out of a `.hflevel` unchecked. #361 bounded the terrain settings for exactly
## this reason; this is the same list for the bake and grid side.
##
## What each case asks is narrow: does the value survive the assignment, does it
## survive a state round trip, and does anything downstream refuse it later.

const OUT_OF_RANGE: Array = [
	["grid_snap", NAN],
	["grid_snap", -16.0],
	["grid_plane_size", 0.0],
	["grid_plane_size", NAN],
	["rotate_snap_degrees", 0.0],
	["rotate_snap_degrees", NAN],
	["rotate_snap_degrees", 100000.0],
	["bake_chunk_size", NAN],
	["bake_chunk_size", -32.0],
	["bake_lightmap_texel_size", 0.0],
	["bake_lightmap_texel_size", -1.0],
	["bake_lightmap_texel_size", NAN],
	["bake_navmesh_cell_size", 0.0],
	["bake_navmesh_cell_size", NAN],
	["bake_navmesh_cell_height", -1.0],
	["bake_navmesh_agent_height", NAN],
	["bake_navmesh_agent_radius", -5.0],
	["bake_connector_stair_height", 0.0],
	["bake_connector_stair_height", NAN],
	["bake_connector_width", -4],
	["bake_convex_simplify", -1.0],
	["bake_convex_simplify", 5.0],
	["bake_convex_simplify", NAN],
	["bake_collision_mode", 99],
	["bake_connector_mode", -7],
]


func id() -> String:
	return "settings"


func summary() -> String:
	return "grid, rotate-snap and bake settings at their edges, and through a state round trip"


func run() -> void:
	await _assigning_out_of_range_values()
	await _through_a_state_round_trip()
	await _what_a_broken_snap_does_downstream()


func _assigning_out_of_range_values() -> void:
	var root: Node3D = await fresh_root()
	var accepted: Array = []
	for case in OUT_OF_RANGE:
		var key: String = case[0]
		var bad = case[1]
		var before = root.get(key)
		root.set(key, bad)
		var after = root.get(key)
		var kept: bool = HFVibe.canonical(after) == HFVibe.canonical(bad)
		note("%s = %s" % [key, bad], "reads back %s%s" % [after, "" if kept else "  (refused)"])
		if kept:
			accepted.append("%s = %s" % [key, bad])
		root.set(key, before)
	note("accepted out of %d" % OUT_OF_RANGE.size(), accepted.size())
	if not accepted.is_empty():
		known(
			480,
			(
				"LevelRoot takes %d of %d out-of-range settings without a word"
				% [accepted.size(), OUT_OF_RANGE.size()]
			),
			(
				(
					"#373 gave the numeric settings clamping setters; what is left is the two whose"
					+ " legal values are an enum -- bake_connector_mode has no setter at all and"
					+ " bake_collision_mode relies on @export_range, which is an inspector hint. %s"
				)
				% "; ".join(PackedStringArray(accepted))
			)
		)


## The file path. `apply_hflevel_settings()` is what a `.hflevel` load calls, and
## it is the one place a value arrives without a SpinBox in front of it.
func _through_a_state_round_trip() -> void:
	var root: Node3D = await fresh_root()
	var settings: Dictionary = root.state_system.capture_hflevel_settings()
	var poisoned: Dictionary = settings.duplicate(true)
	poisoned["grid_snap"] = NAN
	poisoned["bake_chunk_size"] = -1.0
	poisoned["bake_lightmap_texel_size"] = 0.0
	poisoned["bake_navmesh_cell_size"] = NAN
	poisoned["bake_convex_simplify"] = 9.0
	poisoned["bake_connector_width"] = -4
	poisoned["bake_collision_mode"] = 99

	root.state_system.apply_hflevel_settings(poisoned)
	await frame()

	var landed: Array = []
	for key in [
		"grid_snap",
		"bake_chunk_size",
		"bake_lightmap_texel_size",
		"bake_navmesh_cell_size",
		"bake_convex_simplify",
		"bake_connector_width",
		"bake_collision_mode",
	]:
		var got = root.get(key)
		note("after apply_hflevel_settings, %s" % key, got)
		if HFVibe.canonical(got) == HFVibe.canonical(poisoned[key]):
			landed.append("%s = %s" % [key, poisoned[key]])
	if not landed.is_empty():
		known(
			480,
			"apply_hflevel_settings writes a .hflevel's enum settings straight onto the property",
			(
				(
					"%d of 7 poisoned settings landed unchanged: %s -- the numeric ones are clamped"
					% [landed.size(), "; ".join(PackedStringArray(landed))]
				)
				+ " by their setters since #373; bake_collision_mode and bake_connector_mode"
				+ " have no setter to clamp them"
			)
		)


## A setting is only worth reporting when something reads it. `grid_snap` is
## read by the drag system, the clip preview and the brush system.
func _what_a_broken_snap_does_downstream() -> void:
	var root: Node3D = await fresh_root()
	root.grid_snap = NAN
	note("grid_snap after assigning NaN", root.grid_snap)
	note("is it finite", is_finite(root.grid_snap))
	# Every consumer is written `root.grid_snap if root.grid_snap > 0.0 else <fallback>`,
	# and `NAN > 0.0` is false -- so NaN reads as "snapping is off" rather than
	# as a bad value, everywhere, silently.
	note("does `grid_snap > 0.0` hold for it", root.grid_snap > 0.0)

	var b := box(root, Vector3(64, 64, 64))
	await frame()
	note("a brush still builds with a NaN snap", is_instance_valid(b))
	for problem in HFVibe.check_invariants(root):
		flag("with grid_snap = NaN: %s" % problem)

	root.grid_snap = 16.0
	root.rotate_snap_degrees = 0.0
	note("rotate_snap_degrees after assigning 0", root.rotate_snap_degrees)
	if root.rotate_snap_degrees == 0.0:
		note(
			"a zero rotate snap",
			"the rotate hotkeys step by this, so the rotate buttons become a no-op"
		)
