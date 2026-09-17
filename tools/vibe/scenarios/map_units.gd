@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## How big a `.map` is, in the units the two sides of the exchange believe in.
##
## `map-io` checks the format is well formed. `map-real-world` checks a file
## written by another editor survives an import. `world-scale` checks the
## plugin's own defaults agree with each other about how big a person is.
## Nothing checked the join: a `.map` carries bare numbers and no statement of
## what a unit is, so the two editors either agree or the level is the wrong
## size, and the way that shows up is not an error.
##
## HammerForge is on Godot's metric scale since #625, where the playtest player
## is 1.6 units tall. Every Quake-family editor a `.map` comes from is on Quake
## units, where a player is 56 to 72. Since #713 the two sides are converted
## between, at 32 map units to one of ours.


func id() -> String:
	return "map-units"


func summary() -> String:
	return "whether a .map crossing between this editor and a Quake-family one keeps its size"


const PLAYER_HEIGHT := 1.6

## What the other editor's grid steps in, and the smallest step it offers.
const THEIR_GRID_STEP := 16.0
const THEIR_SMALLEST_STEP := 1.0


## A doorway in Quake units. Every editor in that family uses roughly this: a
## player 56 tall, a door 64 wide by 112 high, a grid step of 16.
func _quake_door() -> String:
	var lines: Array[String] = []
	lines.append("{")
	lines.append('"classname" "worldspawn"')
	lines.append("{")
	lines.append("( -64 -16 0 ) ( -64 -15 0 ) ( -64 -16 1 ) WALL_A [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1")
	lines.append("( 64 -16 0 ) ( 64 -16 1 ) ( 64 -15 0 ) WALL_A [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1")
	lines.append("( -64 -16 0 ) ( -64 -16 1 ) ( -63 -16 0 ) WALL_A [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1")
	lines.append("( -64 16 0 ) ( -63 16 0 ) ( -64 16 1 ) WALL_A [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1")
	lines.append("( -64 -16 0 ) ( -63 -16 0 ) ( -64 -15 0 ) FLOOR1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1")
	lines.append(
		"( -64 -16 112 ) ( -64 -15 112 ) ( -63 -16 112 ) CEIL1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1"
	)
	lines.append("}")
	lines.append("}")
	lines.append("{")
	lines.append('"classname" "info_player_start"')
	lines.append('"origin" "0 0 24"')
	lines.append("}")
	lines.append("")
	return "\n".join(lines)


func run() -> void:
	await _what_an_imported_quake_map_is()
	await _what_an_exported_level_looks_like_to_them()
	await _what_survives_a_round_trip()


func _import(root: Node3D, text: String) -> int:
	var path := "user://vibe_map_units.map"
	HFVibe.write_text(path, text)
	var result = root.import_map(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result


func _export_text(root: Node3D) -> String:
	var path := "user://vibe_map_units_out.map"
	var ok = root.export_map(path, "valve220")
	note("export_map returned", ok)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return text


## Every plane coordinate the export wrote.
func _written_numbers(text: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\(([^\\)]+)\\)")
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if not stripped.begins_with("("):
			continue
		for m in re.search_all(stripped):
			for part in m.get_string(1).strip_edges().split(" ", false):
				if part.is_valid_float():
					out.append(float(part))
	return out


func _what_an_imported_quake_map_is() -> void:
	var root: Node3D = await fresh_root()
	var result := _import(root, _quake_door())
	await frame()
	note("import_map returned", result)
	note("brushes imported", root.brush_system.get_live_brush_count())
	var sizes: Array = []
	var biggest := 0.0
	for b in root.draft_brushes_node.get_children():
		var extent: Vector3 = HFVibe.local_extent(b)
		sizes.append(str(extent))
		biggest = maxf(biggest, extent.length())
	note("imported brush extents, in HammerForge units", sizes)
	note("the playtest player's height, for scale", PLAYER_HEIGHT)
	note("the largest imported brush, in player heights", "%.1f" % (biggest / PLAYER_HEIGHT))
	var spawns: Array = []
	if root.entities_node:
		for c in root.entities_node.get_children():
			spawns.append("%s at %s" % [c.get_meta("entity_type", "?"), c.global_position])
	note("point entities and where they landed", spawns)

	# The source file says the room is 128 x 32 x 112, which in Quake units is a
	# corridor about two players wide and two high.
	note("what the source file says the room is", "128 x 32 x 112 (Quake units)")
	note(
		"what a Quake unit is",
		"a player is 56 units tall in that family, so the room is 2.0 players high"
	)
	var ceiling := 112.0 / MapIO.QUAKE_UNITS_PER_METRE
	note(
		"what those numbers are here",
		(
			"%.1f players high, at %.0f map units to one of ours"
			% [ceiling / PLAYER_HEIGHT, MapIO.QUAKE_UNITS_PER_METRE]
		)
	)
	if biggest / PLAYER_HEIGHT > 10.0:
		flag(
			"a .map from a Quake-family editor imports at many times the size it was drawn",
			(
				(
					"The largest brush is %.0f player heights. A corridor drawn two players high "
					+ "should arrive about two players high. The unit conversion added in #713 is "
					+ "not being applied on this path."
				)
				% (biggest / PLAYER_HEIGHT)
			)
		)
	var spawn_height := 24.0 / MapIO.QUAKE_UNITS_PER_METRE
	for c in root.entities_node.get_children() if root.entities_node else []:
		if absf((c as Node3D).global_position.z - spawn_height) > 0.01:
			flag(
				"a point entity does not take the same conversion as the geometry",
				(
					(
						"`origin` is a position in the same space as the plane points. This one "
						+ "is at %s and the geometry around it was divided by %.0f, so the spawn "
						+ "is somewhere the level is not."
					)
					% [str((c as Node3D).global_position), MapIO.QUAKE_UNITS_PER_METRE]
				)
			)


func _what_an_exported_level_looks_like_to_them() -> void:
	var root: Node3D = await fresh_root()
	# A room at this project's own scale: 12 x 3 x 12, a person 1.6 tall.
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	box(root, Vector3(12, 3, 0.3), Vector3(0, 1.5, -6))
	await frame()
	var text := _export_text(root)
	if text == "":
		flag("export_map wrote nothing")
		return
	var plane_lines: Array = []
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("("):
			plane_lines.append(s.substr(0, 60))
	note("the first plane lines the export writes", plane_lines.slice(0, 3))
	var numbers := _written_numbers(text)
	var largest := 0.0
	for n in numbers:
		largest = maxf(largest, absf(float(n)))
	note("the largest coordinate written", largest)
	note(
		"what a Quake-family editor makes of those numbers",
		(
			"its default grid step is %.0f and its smallest is %.0f"
			% [THEIR_GRID_STEP, THEIR_SMALLEST_STEP]
		)
	)
	note("the room, in their grid squares", "%.1f" % (largest / THEIR_GRID_STEP))
	if largest < THEIR_GRID_STEP:
		flag(
			"an exported room is smaller than one of the other editor's grid squares",
			(
				(
					"The largest coordinate written is %.2f and their grid steps in %.0f with a "
					+ "smallest step of %.0f, so every vertex of this room snaps onto the same "
					+ "point. The export is writing this project's own units rather than the "
					+ "file's."
				)
				% [largest, THEIR_GRID_STEP, THEIR_SMALLEST_STEP]
			)
		)
	# The texture scale divides in a `.map` and multiplies here, so a conversion
	# applied to the points and not to the scale tiles the texture that many
	# times more often. The room would be the right size and covered in dust.
	var scales: Array = []
	for line in text.split("\n"):
		var s := line.strip_edges()
		if not s.begins_with("("):
			continue
		var tokens := s.split(" ", false)
		if tokens.size() >= 2:
			scales.append(float(tokens[tokens.size() - 2]))
	note("the texture scales written", scales.slice(0, 3))
	for value in scales:
		if absf(float(value) - MapIO.QUAKE_UNITS_PER_METRE) > 0.01:
			flag(
				"the texture scale did not take the conversion the geometry took",
				(
					(
						"A `.map` reader computes `axis . point / scale`. A face drawn at scale 1 "
						+ "here should be written as %.0f, and this one is %s, so the texture "
						+ "repeats at the wrong size on a room that is otherwise right."
					)
					% [MapIO.QUAKE_UNITS_PER_METRE, str(value)]
				)
			)
			break


func _what_survives_a_round_trip() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(4, 1, 3.5), Vector3.ZERO)
	await frame()
	var text := _export_text(root)
	if text == "":
		return
	var back: Node3D = await fresh_root()
	var path := "user://vibe_map_units_trip.map"
	HFVibe.write_text(path, text)
	back.import_map(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await frame()
	var sizes: Array = []
	var worst := 0.0
	for b in back.draft_brushes_node.get_children():
		var extent: Vector3 = HFVibe.local_extent(b)
		sizes.append(str(extent))
		worst = maxf(worst, (extent - Vector3(4, 1, 3.5)).length())
	note("a 4 x 1 x 3.5 room, out to .map and back", sizes)
	note("how far it drifted", "%.4f" % worst)
	note(
		"what the file records it was written at",
		"%s = %s" % [MapIO.SCALE_PROPERTY, str(MapIO.QUAKE_UNITS_PER_METRE)]
	)
	if worst > 0.01:
		flag(
			"a level does not survive its own .map round trip at its own size",
			(
				(
					"Exported and imported again, the room came back %.3f out. The file records "
					+ "what it was written with, so the two directions should cancel."
				)
				% worst
			)
		)
