@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## How big a `.map` is, in the units the two sides of the exchange believe in.
##
## `map-io` checks the format is well formed. `map-real-world` checks a file
## written by another editor survives an import. `world-scale` checks the
## plugin's own defaults agree with each other about how big a person is.
## Nothing has checked the join: a `.map` carries bare numbers and no statement
## of what a unit is, so the two editors either agree or the level is the wrong
## size, and the way that shows up is not an error.
##
## HammerForge is on Godot's metric scale since #625 -- the playtest player is
## 1.6 units tall. Every Quake-family editor a `.map` comes from is on Quake
## units, where a player is 56 to 72.


func id() -> String:
	return "map-units"


func summary() -> String:
	return "whether a .map crossing between this editor and a Quake-family one keeps its size"


const PLAYER_HEIGHT := 1.6

## A doorway in Quake units. Every editor in that family uses roughly this: a
## player 56 tall, a door 64 wide by 112 high, a grid step of 16.
const QUAKE_DOOR := "\
{\n\
\"classname\" \"worldspawn\"\n\
{\n\
( -64 -16 0 ) ( -64 -15 0 ) ( -64 -16 1 ) WALL_A [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1\n\
( 64 -16 0 ) ( 64 -16 1 ) ( 64 -15 0 ) WALL_A [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1\n\
( -64 -16 0 ) ( -64 -16 1 ) ( -63 -16 0 ) WALL_A [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1\n\
( -64 16 0 ) ( -63 16 0 ) ( -64 16 1 ) WALL_A [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1\n\
( -64 -16 0 ) ( -63 -16 0 ) ( -64 -15 0 ) FLOOR1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1\n\
( -64 -16 112 ) ( -64 -15 112 ) ( -63 -16 112 ) CEIL1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1\n\
}\n\
}\n\
{\n\
\"classname\" \"info_player_start\"\n\
\"origin\" \"0 0 24\"\n\
}\n\
"


func run() -> void:
	await _what_an_imported_quake_map_is()
	await _what_an_exported_level_looks_like_to_them()


func _import(root: Node3D, text: String) -> int:
	var path := "user://vibe_map_units.map"
	HFVibe.write_text(path, text)
	var result = root.import_map(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result


func _what_an_imported_quake_map_is() -> void:
	var root: Node3D = await fresh_root()
	var result := _import(root, QUAKE_DOOR)
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
	note(
		"the largest imported brush, in player heights",
		"%.1f" % (biggest / PLAYER_HEIGHT)
	)
	var spawns: Array = []
	if root.entities_node:
		for c in root.entities_node.get_children():
			spawns.append("%s at %s" % [c.get_meta("entity_type", "?"), c.global_position])
	note("point entities and where they landed", spawns)

	# The source file says the room is 128 x 32 x 112, which in Quake units is a
	# corridor about two players wide and two high. The question is what those
	# numbers mean once they are here.
	note("what the source file says the room is", "128 x 32 x 112 (Quake units)")
	note(
		"what a Quake unit is",
		"a player is 56 units tall in that family, so the room is 2.0 players high"
	)
	note(
		"what those numbers are here",
		"%.1f players high, because nothing converts between the two scales" % (112.0 / PLAYER_HEIGHT)
	)
	if biggest / PLAYER_HEIGHT > 10.0:
		flag(
			"a .map from a Quake-family editor imports at %.0fx the size it was drawn"
			% (PLAYER_HEIGHT * 0.0 + 56.0 / PLAYER_HEIGHT),
			(
				(
					"`MapIO` copies coordinates through unchanged, and a `.map` file states no "
					+ "unit. Every editor that writes one -- Hammer, TrenchBroom, J.A.C.K., "
					+ "Radiant -- is on Quake units, where a player is 56 tall. HammerForge has "
					+ "been on Godot's metric scale since #625, where a player is %.1f. So a "
					+ "corridor drawn 112 units high arrives %.0f players high, an "
					+ "`info_player_start` at z 24 lands 24 units up, and the level is "
					+ "unusable without rescaling every brush by hand. The export has the same "
					+ "problem in reverse: a HammerForge room opened in TrenchBroom is smaller "
					+ "than that editor's smallest grid step.\n\n"
					+ "The data portability guide documents the UV conversion, the winding "
					+ "conversion and the weld tolerance in detail and says nothing about "
					+ "units, which is the conversion that decides whether the file is usable "
					+ "at all. An import/export scale -- offered in the dialog, defaulting to "
					+ "the Quake-family convention, and recorded in the level so a round trip "
					+ "is symmetric -- is what this needs."
				)
				% [PLAYER_HEIGHT, 112.0 / PLAYER_HEIGHT]
			)
		)


func _what_an_exported_level_looks_like_to_them() -> void:
	var root: Node3D = await fresh_root()
	# A room at this project's own scale: 12 x 3 x 12, a person 1.6 tall.
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	box(root, Vector3(12, 3, 0.3), Vector3(0, 1.5, -6))
	await frame()
	var path := "user://vibe_map_units_out.map"
	var ok = root.export_map(path, "valve220")
	note("export_map returned", ok)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		flag("export_map wrote nothing")
		return
	var text := f.get_as_text()
	f.close()
	var plane_lines: Array = []
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("("):
			plane_lines.append(s.substr(0, 60))
	note("the first plane lines the export writes", plane_lines.slice(0, 3))
	note(
		"what a Quake-family editor makes of those numbers",
		(
			"its default grid step is 16 and its smallest is 1, so a 12-unit room is "
			+ "smaller than one grid square and every vertex snaps onto the same point"
		)
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
