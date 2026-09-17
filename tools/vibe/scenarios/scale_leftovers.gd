@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The numbers #625 did not reach.
##
## #625 moved the project onto Godot scale: the player is 1.6 units, the grid
## snaps at 0.5, a drawn brush is 2 units, the examples are rooms you can stand
## in. `world-scale` covers the defaults that were in that sweep and is clean.
##
## This one goes looking for the ones that were not: values elsewhere in the
## plugin that only make sense if a player is seventy-two units high. A leftover
## is not a style problem -- it is a control whose default puts geometry
## somewhere a mapper cannot use, on a surface that gives no clue why.
##
## Everything below is reported in player heights, the same unit `world-scale`
## uses, so the two read together.

const PLAYER_HEIGHT := 1.6
const PolygonTool = preload("res://addons/hammerforge/hf_polygon_tool.gd")


func id() -> String:
	return "scale-leftovers"


func summary() -> String:
	return "defaults elsewhere in the plugin that are still on the pre-#625 scale"


func run() -> void:
	await _the_default_spawn()
	await _the_polygon_tools_height()
	await _the_shipped_entity_properties()
	await _controls_whose_range_outlives_the_level()


func _players(value: float) -> String:
	return "%.2f units = %.2f player heights" % [value, value / PLAYER_HEIGHT]


## `create_default_spawn()` puts the spawn five units above the centroid of the
## level. Five units was a sensible nudge when a room was 256 units tall.
func _the_default_spawn() -> void:
	note("-- where a new level's player spawn goes --")
	var root: Node3D = await fresh_root()
	# Headless is not `Engine.is_editor_hint()`, so a fresh root treats itself as
	# the running game and deferred-starts a playtest. Its CharacterBody3D is
	# then in the physics space and the spawn validator's floor ray hits it, which
	# is the harness and not the level.
	root.auto_spawn_player = false
	for child in root.get_children():
		if child is CharacterBody3D:
			root.remove_child(child)
			child.queue_free()
	await frame()
	# A room at the scale the project settled on: 8x3x8, walls 0.25.
	var solid = box(root, Vector3(8, 3, 8), Vector3(0, 1.5, 0))
	await frame()
	root.hollow_brush_by_id(solid.brush_id, 0.25)
	await frame()
	var aabb: AABB = root._compute_level_aabb()
	note("the level's own AABB", aabb)
	note("its ceiling", _players(aabb.end.y))

	root.spawn_system.create_default_spawn()
	await frame()
	var spawn = root.spawn_system.get_active_spawn()
	note("spawn placed at", spawn.global_position)
	note("its height above the floor", _players(spawn.global_position.y))
	if spawn.global_position.y > aabb.end.y:
		flag(
			"the default player spawn is placed above the level's ceiling",
			(
				"`create_default_spawn()` takes the centroid of every pick node and adds "
				+ "a literal 5.0 to its y (hf_spawn_system.gd:203), with a hard-coded "
				+ "Vector3(0, 5, 0) for an empty level. The room here is %s units tall "
				+ "and the spawn is at %s. Five units was a small step up when the "
				+ "project was on Quake scale; on the scale #625 settled it is three "
				+ "rooms up"
			) % [aabb.size.y, spawn.global_position.y]
		)

	# Give the physics server frames to register the draft collision before
	# asking the validator anything, so a "no floor below" is the level's answer
	# and not the harness's.
	for _i in 8:
		await _tree.physics_frame
	var report: Dictionary = root.spawn_system.validate_spawn(spawn, root.draft_pick_layer_index)
	note("the spawn system's own verdict", report.get("issues", []))
	note("its severity", report.get("severity", "?"))
	note("what it would move the spawn to", report.get("suggested_position", "?"))
	# Recorded, not flagged on: a headless physics space is not the editor's, so
	# the verdict is corroboration for the arithmetic above rather than the
	# finding itself.
	var complained: bool = report.get("issues", []).size() > 0
	note("the validator agrees the spawn is unusable", complained)

	# And what the level-wide validator says about all that.
	var level_report: Dictionary = root.validate_level()
	note("validate_level()", level_report)
	var issues = level_report.get("issues", [])
	var mentions_spawn := false
	if issues is Array:
		for entry in issues:
			if str(entry).to_lower().find("spawn") >= 0:
				mentions_spawn = true
	note("validate_level mentions the spawn", mentions_spawn)
	var validation_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_validation_system.gd"
	)
	note("times hf_validation_system.gd says 'spawn'", validation_source.countn("spawn"))
	if spawn.global_position.y > aabb.end.y and not mentions_spawn:
		flag(
			"validate_level() passes a level whose spawn its own spawn validator rejects",
			(
				"the Validate button reports %s issues on a level whose only player "
				+ "spawn is outside the level. `hf_validation_system.gd` contains the "
				+ "word 'spawn' %s times: `validate_spawn()` is not among the twenty-odd "
				+ "checks `validate()` runs, so the surface a mapper presses before "
				+ "testing is the one that never looks at the thing testing starts from"
			) % [
				issues.size() if issues is Array else "?",
				validation_source.countn("spawn"),
			]
		)


func _the_polygon_tools_height() -> void:
	note("-- the height the Polygon tool extrudes to --")
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/hf_polygon_tool.gd")
	var root: Node3D = await fresh_root()
	var tool_instance = PolygonTool.new()
	var height := float(tool_instance.get("_height"))
	note("Polygon tool default height", _players(height))
	note("the level's grid snap", _players(root.grid_snap))
	note("a drawn brush's default size", root.brush_size_default)
	note("resets to the same number after each shape", source.count("_height = 32.0"))
	if height > root.brush_size_default.y * 4.0:
		flag(
			"the Polygon tool extrudes to a height nothing else on the project's scale uses",
			(
				"`_height` starts at %s units -- %.0f players -- against a default drawn "
				+ "brush of %s and a grid that snaps at %s. It is also reset to the "
				+ "literal 32.0 in two more places after each shape, so a mapper who "
				+ "drags it down to something usable gets it back on the next polygon"
			) % [height, height / PLAYER_HEIGHT, root.brush_size_default.y, root.grid_snap]
		)


## The three entity classes that ship, and what their property defaults assume.
func _the_shipped_entity_properties() -> void:
	note("-- the shipped entity definitions --")
	var root: Node3D = await fresh_root()
	var defs: Dictionary = root.get_entity_definitions()
	note("classes in entities.json", defs.keys())
	if defs.keys().size() <= 3:
		flag(
			"three entity classes ship with a level editor built around entity I/O",
			(
				"entities.json defines %s: no trigger volume, no spot or directional "
				+ "light, no static prop, no brush entity class. The I/O wiring panel, "
				+ "the connection visualiser, the runtime dispatcher and the .map entity "
				+ "export are all built and there is almost nothing to point them at, so "
				+ "the whole gameplay half of the tool is unreachable without the mapper "
				+ "hand-authoring JSON first"
			) % str(defs.keys())
		)
	for key in defs.keys():
		var entry: Dictionary = defs[key]
		var props = entry.get("properties", [])
		if not (props is Array):
			continue
		for prop in props:
			if not (prop is Dictionary):
				continue
			var type := str(prop.get("type", ""))
			if type != "float":
				continue
			var value := float(prop.get("default", 0.0))
			note("%s.%s" % [key, prop.get("name", "?")], _players(value))
			# A distance or a speed two orders of magnitude off the scale the
			# project settled on is the leftover shape.
			if value >= 100.0:
				flag(
					"a shipped entity's default is on the pre-#625 scale",
					(
						"%s.%s defaults to %s. The playtest player walks at 6.5 units a "
						+ "second and a room is 8 units across, so this is the Quake-scale "
						+ "number the rest of the project moved off"
					) % [key, prop.get("name", "?"), value]
				)


## Spin ranges that still run to sixty-four units on a level eight units across.
func _controls_whose_range_outlives_the_level() -> void:
	note("-- dock spin ranges against the size of a level --")
	var dock_source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var interesting := {
		"_disp_elevation_spin": "displacement elevation",
		"_disp_radius_spin": "displacement brush radius",
		"_bevel_radius_spin": "bevel radius",
		"_bevel_inset_dist_spin": "inset distance",
		"_bevel_inset_height_spin": "inset height",
	}
	for name in interesting:
		var idx := dock_source.find("%s.max_value = " % name)
		if idx < 0:
			continue
		var rest := dock_source.substr(idx + name.length() + 13, 20)
		var maximum := float(rest.split("\n")[0])
		note("%s max" % interesting[name], _players(maximum))
		if maximum >= 32.0:
			flag(
				"a dock control's range is four rooms wide",
				(
					"%s runs to %s units -- %.0f players -- on a project whose default "
					+ "brush is 2 units and whose shipped examples are 8 unit rooms. "
					+ "Every useful value is in the first 3%% of the slider"
				) % [interesting[name], maximum, maximum / PLAYER_HEIGHT]
			)
