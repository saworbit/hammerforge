@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a `.map` coordinate means: how big it is, and which way up.
##
## `map-io` checks the format is well formed. `map-real-world` checks a file
## written by another editor survives an import. `world-scale` checks the
## plugin's own defaults agree with each other about how big a person is.
## Nothing checked the join: a `.map` carries bare numbers and says neither what
## a unit is nor which axis points up, so the two editors either agree or the
## level is the wrong size and on its side, and the way that shows up is not an
## error.
##
## HammerForge is on Godot's metric scale since #625, where the playtest player
## is 1.6 units tall, and Godot is Y-up. Every Quake-family editor a `.map` comes
## from is on Quake units, where a player is 56 to 72, and is Z-up. Since #713
## the sizes are converted between, at 32 map units to one of ours, and since
## #733 so are the axes.
##
## Both halves are worth checking the same way: not by reading the plugin's
## source, but by putting a shape through the crossing whose right answer is
## obvious. A corridor a person fits down, and a floor that is thin in the
## direction you stand up in.


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
	await _which_way_up_it_lands()
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


## Every plane point the export wrote.
##
## One place that knows how to read a face line, because the two readings below
## want the same numbers grouped differently and a second copy of this regex is
## a second chance to get its escaping wrong.
func _written_points(text: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\(([^\\)]+)\\)")
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if not stripped.begins_with("("):
			continue
		for m in re.search_all(stripped):
			var parts := m.get_string(1).strip_edges().split(" ", false)
			if parts.size() < 3:
				continue
			out.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	return out


## The largest coordinate written, in any direction.
func _largest_written(text: String) -> float:
	var largest := 0.0
	for p in _written_points(text):
		var point: Vector3 = p
		largest = maxf(largest, absf(point.x))
		largest = maxf(largest, absf(point.y))
		largest = maxf(largest, absf(point.z))
	return largest


## The size of the box the written plane points describe.
func _written_extent_of(text: String) -> Vector3:
	var points := _written_points(text)
	if points.is_empty():
		return Vector3.ZERO
	var lo: Vector3 = points[0]
	var hi: Vector3 = points[0]
	for p in points:
		var point: Vector3 = p
		lo = Vector3(minf(lo.x, point.x), minf(lo.y, point.y), minf(lo.z, point.z))
		hi = Vector3(maxf(hi.x, point.x), maxf(hi.y, point.y), maxf(hi.z, point.z))
	return hi - lo


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
		if absf((c as Node3D).global_position.y - spawn_height) > 0.01:
			flag(
				"a point entity does not take the same conversion as the geometry",
				(
					(
						"`origin` is a position in the same space as the plane points, so it takes "
						+ "the same divide and the same turn. This one is at %s and the file put "
						+ "it %.2f above the floor at %.0f units to one of ours, so the spawn is "
						+ "somewhere the level is not."
					)
					% [
						str((c as Node3D).global_position),
						spawn_height,
						MapIO.QUAKE_UNITS_PER_METRE
					]
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
	var largest := _largest_written(text)
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


## A floor slab as an editor in that family writes one: wide in x and y, thin in
## z, because z is their up.
func _quake_floor() -> String:
	var lines: Array[String] = []
	lines.append("{")
	lines.append('"classname" "worldspawn"')
	lines.append("{")
	lines.append(
		"( -64 -64 -8 ) ( -64 -63 -8 ) ( -63 -64 -8 ) FLOOR1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1"
	)
	lines.append("( -64 -64 0 ) ( -63 -64 0 ) ( -64 -63 0 ) FLOOR1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1")
	lines.append(
		"( -64 -64 -8 ) ( -64 -64 -7 ) ( -64 -63 -8 ) WALL_A [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1"
	)
	lines.append("( 64 -64 -8 ) ( 64 -63 -8 ) ( 64 -64 -7 ) WALL_A [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1")
	lines.append(
		"( -64 -64 -8 ) ( -63 -64 -8 ) ( -64 -64 -7 ) WALL_A [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1"
	)
	lines.append("( -64 64 -8 ) ( -64 64 -7 ) ( -63 64 -8 ) WALL_A [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1")
	lines.append("}")
	lines.append("}")
	lines.append("")
	return "\n".join(lines)


## Whether the file's up axis is this level's up axis, in both directions.
##
## A level the right size and on its side is harder to notice than one seventy
## players high, so this asks the question with a shape that has an obvious right
## answer: a floor is thin in the direction you stand up in.
func _which_way_up_it_lands() -> void:
	var root: Node3D = await fresh_root()
	_import(root, _quake_floor())
	await frame()
	var extent := Vector3.ZERO
	for b in root.draft_brushes_node.get_children():
		extent = HFVibe.local_extent(b)
		break
	note("a 128 x 128 x 8 slab, thin on the file's up axis, imports as", str(extent))
	var thinnest := "x"
	if extent.y <= extent.x and extent.y <= extent.z:
		thinnest = "y"
	elif extent.z <= extent.x and extent.z <= extent.y:
		thinnest = "z"
	note("the axis it is thinnest on", thinnest)
	note("the axis a floor should be thinnest on here", "y, which is up in Godot")
	if thinnest != "y":
		flag(
			"a floor imports as a wall",
			(
				(
					"`.map` is Z-up across the whole Quake family and this project is Y-up. A "
					+ "slab written 8 units thick on the file's up axis came in %s, thinnest on "
					+ "%s, so the level is on its side. It is hard to spot because the trip out "
					+ "and back is symmetric: only the crossing is wrong, and the crossing is "
					+ "what the format is for."
				)
				% [str(extent), thinnest]
			)
		)

	var out: Node3D = await fresh_root()
	box(out, Vector3(4, 0.25, 4), Vector3.ZERO)
	await frame()
	var text := _export_text(out)
	if text == "":
		return
	var written := _written_extent_of(text)
	note("and a floor drawn here exports as", str(written))
	note("the axis it should be thinnest on there", "z, which is up in a .map")
	if written.z > written.x or written.z > written.y:
		flag(
			"a floor exports as a wall",
			(
				(
					"A slab 0.25 thick on this project's up axis was written %s. A `.map` is "
					+ "Z-up, so a floor has to be the thin one on z or it opens upright in the "
					+ "editor it was written for."
				)
				% str(written)
			)
		)
	note(
		"what the file records it was written as",
		"%s = %s" % [MapIO.AXIS_PROPERTY, MapIO.AXES_QUAKE]
	)
