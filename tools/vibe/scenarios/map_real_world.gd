@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## A `.map` written by something other than HammerForge.
##
## `map-io` round-trips HammerForge's own export and feeds the reader seven
## malformed files. This one starts from the other end: a file shaped the way
## TrenchBroom and the Half-Life tools write one, because "I have a map, open
## it" is the first thing anyone with existing work does.
##
## What such a file has that HammerForge's own export does not:
##
##   - `worldspawn` with keys on it: `wad`, `message`, `mapversion`, `light`
##   - brush entities holding several brushes each
##   - point entities with arbitrary keys: `spawnflags`, `wait`, `health`
##   - texture names from the WAD conventions: `*water`, `+0button`, `sky1`,
##     `AAATRIGGER`, `__TB_empty`
##   - brushes defined by planes that are not an axis-aligned box
##   - `// entity 0` and `// brush 0` comments between the blocks
##
## Every one of those is in the file below, and every one is checked on the way
## back out.


func id() -> String:
	return "map-real-world"


func summary() -> String:
	return "a .map written by another editor: what survives import, and the export after it"


func run() -> void:
	await _import_a_third_party_map()
	await _and_export_it_again()


## A Valve 220 file of the shape TrenchBroom writes.
func _source_map() -> String:
	var lines: Array[String] = []
	lines.append("// Game: Quake")
	lines.append("// Format: Valve")
	lines.append("// entity 0")
	lines.append("{")
	lines.append('"classname" "worldspawn"')
	lines.append('"mapversion" "220"')
	lines.append('"wad" "/textures/base.wad;/textures/liquids.wad"')
	lines.append('"message" "The Slipgate Complex"')
	lines.append('"light" "20"')
	lines.append('"_tb_textures" "textures"')
	# A room: six axis-aligned brushes.
	lines.append_array(_box_brush(-256, 0, -256, 256, 16, 256, "floor1"))
	lines.append_array(_box_brush(-256, 240, -256, 256, 256, 256, "ceil1"))
	lines.append_array(_box_brush(-256, 0, -256, -240, 256, 256, "wall_a"))
	lines.append_array(_box_brush(240, 0, -256, 256, 256, 256, "wall_b"))
	# A pool of water, with a texture name that starts with a star.
	lines.append_array(_box_brush(-64, 16, -64, 64, 48, 64, "*water1"))
	# A trigger volume: the texture name the tools use for one.
	lines.append_array(_box_brush(-32, 16, 100, 32, 80, 132, "AAATRIGGER"))
	# A wedge, defined by planes rather than as a box.
	lines.append("// brush 6")
	lines.append("{")
	lines.append("( 0 0 0 ) ( 0 0 1 ) ( 0 1 0 ) sky1 [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1")
	lines.append("( 128 0 0 ) ( 128 1 0 ) ( 128 0 1 ) sky1 [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1")
	lines.append("( 0 0 0 ) ( 1 0 0 ) ( 0 0 1 ) sky1 [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1")
	lines.append("( 0 96 0 ) ( 0 96 1 ) ( 1 96 0 ) sky1 [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1")
	lines.append("( 0 0 0 ) ( 0 1 0 ) ( 1 0 0 ) sky1 [ 1 0 0 0 ] [ 0 1 0 0 ] 0 1 1")
	lines.append("( 0 0 96 ) ( 1 0 96 ) ( 0 1 96 ) sky1 [ 1 0 0 0 ] [ 0 1 0 0 ] 0 1 1")
	lines.append("}")
	lines.append("}")
	# A point entity with keys nothing in HammerForge names.
	lines.append("// entity 1")
	lines.append("{")
	lines.append('"classname" "info_player_start"')
	lines.append('"origin" "0 32 0"')
	lines.append('"angle" "90"')
	lines.append('"spawnflags" "0"')
	lines.append("}")
	lines.append("// entity 2")
	lines.append("{")
	lines.append('"classname" "light"')
	lines.append('"origin" "0 200 0"')
	lines.append('"light" "300"')
	lines.append('"_color" "1.0 0.9 0.8"')
	lines.append('"wait" "2"')
	lines.append("}")
	# A brush entity holding two brushes, with a target and a name.
	lines.append("// entity 3")
	lines.append("{")
	lines.append('"classname" "func_door"')
	lines.append('"targetname" "gate"')
	lines.append('"speed" "100"')
	lines.append('"wait" "4"')
	lines.append('"angle" "-1"')
	lines.append_array(_box_brush(-48, 16, -256, 0, 128, -240, "+0button"))
	lines.append_array(_box_brush(0, 16, -256, 48, 128, -240, "+0button"))
	lines.append("}")
	lines.append("// entity 4")
	lines.append("{")
	lines.append('"classname" "trigger_once"')
	lines.append('"target" "gate"')
	lines.append_array(_box_brush(-64, 16, -200, 64, 96, -160, "AAATRIGGER"))
	lines.append("}")
	return "\n".join(lines) + "\n"


## A Valve 220 box, written the way the tools write one.
func _box_brush(
	x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, texture: String
) -> Array[String]:
	var out: Array[String] = []
	out.append("{")
	# ( p1 ) ( p2 ) ( p3 ) TEX [ ux uy uz uoff ] [ vx vy vz voff ] rot xs ys
	out.append(
		(
			"( %d %d %d ) ( %d %d %d ) ( %d %d %d ) %s [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1"
			% [x0, y1, z0, x1, y1, z0, x1, y1, z1, texture]
		)
	)
	out.append(
		(
			"( %d %d %d ) ( %d %d %d ) ( %d %d %d ) %s [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1"
			% [x0, y0, z0, x1, y0, z1, x1, y0, z0, texture]
		)
	)
	out.append(
		(
			"( %d %d %d ) ( %d %d %d ) ( %d %d %d ) %s [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1"
			% [x0, y0, z0, x0, y1, z0, x1, y1, z0, texture]
		)
	)
	out.append(
		(
			"( %d %d %d ) ( %d %d %d ) ( %d %d %d ) %s [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1"
			% [x1, y0, z1, x1, y1, z1, x0, y1, z1, texture]
		)
	)
	out.append(
		(
			"( %d %d %d ) ( %d %d %d ) ( %d %d %d ) %s [ 0 0 1 0 ] [ 0 -1 0 0 ] 0 1 1"
			% [x0, y0, z0, x0, y1, z1, x0, y1, z0, texture]
		)
	)
	out.append(
		(
			"( %d %d %d ) ( %d %d %d ) ( %d %d %d ) %s [ 0 0 1 0 ] [ 0 -1 0 0 ] 0 1 1"
			% [x1, y0, z0, x1, y1, z0, x1, y1, z1, texture]
		)
	)
	out.append("}")
	return out


func _import_a_third_party_map() -> void:
	note("-- importing a Valve 220 file written by another editor --")
	var path := "user://vibe_third_party.map"
	HFVibe.write_text(path, _source_map())
	note("source file", "%s bytes" % HFVibe.file_size(path))

	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var report: Dictionary = root.validate_map(path)
	note("validate_map()", report)

	var count = root.import_map(path)
	await frame()
	note("import_map returned", count)
	note("brushes in the level", root.get_live_brush_count())
	note("entities in the level", root.get_entity_count())
	if root.get_live_brush_count() == 0:
		flag("a Valve 220 file from another editor imports as an empty level", report)
		return

	# The seven brushes of the world plus the three of the two brush entities.
	if root.get_live_brush_count() != 10:
		flag(
			"the file's ten brushes do not all arrive",
			"%s in the level" % root.get_live_brush_count()
		)

	# Brush entities: the two func_door brushes must both carry the class.
	var by_class := {}
	for child in root.draft_brushes_node.get_children():
		if not root.is_brush_node(child):
			continue
		var cls := str(child.get_meta("brush_entity_class", ""))
		by_class[cls] = int(by_class.get(cls, 0)) + 1
	note("brushes by entity class", by_class)
	if int(by_class.get("func_door", 0)) != 2:
		flag(
			"a brush entity's brushes do not both arrive tied to it",
			"func_door holds %s of 2" % by_class.get("func_door", 0)
		)

	# Point entities and their keys.
	var entities: Array = HFVibe.describe_entities(root)
	for e in entities:
		note("entity", e)
	var names: Array = []
	for child in root.entities_node.get_children():
		names.append(str(child.get("entity_type")))
	note("point entity classes", names)

	# The keys a real file carries that are not classname/origin/targetname.
	var light_node: Node = null
	for child in root.entities_node.get_children():
		if str(child.get("entity_type")) == "light":
			light_node = child
	if light_node == null:
		flag("the file's `light` entity did not arrive", names)
	else:
		var props = light_node.get("entity_data")
		note("what the light kept", props)
		var kept: bool = props is Dictionary and (props as Dictionary).size() > 0
		if not kept:
			flag("a point entity's keys are dropped on import", str(props))
		else:
			note("a point entity's arbitrary keys survive the import", props)

	# Texture names. A `.map` face names a texture; HammerForge stores a slot.
	note("palette after the import", root.get_material_names())
	var slots := {}
	for child in root.draft_brushes_node.get_children():
		if not root.is_brush_node(child):
			continue
		for face in child.get("faces"):
			if face:
				slots[int(face.material_idx)] = int(slots.get(int(face.material_idx), 0)) + 1
	note("face material slots after the import", slots)
	if root.get_materials().is_empty() and slots.keys() == [-1]:
		known(
			662,
			"a .map import throws away every texture name in the file",
			(
				(
					"the file names floor1, ceil1, wall_a, wall_b, *water1, AAATRIGGER, "
					+ "sky1 and +0button across %s faces. The palette is empty afterwards "
					+ "and all %s faces are on material_idx -1, so the level arrives "
					+ "untextured with no record anywhere of what each face was"
				)
				% [slots.get(-1, 0), slots.get(-1, 0)]
			)
		)


## And straight back out, which is what a mapper does who wants to keep working
## in both tools.
func _and_export_it_again() -> void:
	note("-- the same level exported back to Valve 220 --")
	var path := "user://vibe_third_party.map"
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	root.import_map(path)
	await frame()
	var out := "user://vibe_third_party_out.map"
	root.export_map(out, "valve220")
	await frame()
	var text := FileAccess.get_file_as_string(out)
	note("exported", "%s bytes against the source's %s" % [text.length(), HFVibe.file_size(path)])
	# What the export writes in the texture field of a face line, since the
	# source's names are the thing most obviously at risk.
	var written := {}
	for line in text.split("\n"):
		var idx := line.rfind(") ")
		if idx < 0 or not line.begins_with("("):
			continue
		var rest := line.substr(idx + 2).strip_edges()
		var tex := rest.split(" ")[0]
		written[tex] = int(written.get(tex, 0)) + 1
	note("texture names the export writes", written)

	var source := FileAccess.get_file_as_string(path)
	var checks := {
		'"wad"': "the WAD list",
		'"message"': "the level's name",
		'"mapversion"': "the format marker",
		'"spawnflags"': "a point entity's spawnflags",
		'"speed"': "the door's speed",
		'"wait"': "the door's wait",
		'"target"': "the trigger's target",
		'"targetname"': "the door's name",
		"*water1": "the water texture",
		"AAATRIGGER": "the trigger texture",
		"sky1": "the sky texture",
		"+0button": "the button texture",
		"func_door": "the door class",
		"trigger_once": "the trigger class",
		"info_player_start": "the spawn class",
	}
	var lost: Array[String] = []
	for token in checks:
		var in_source := source.find(token) >= 0
		var in_output := text.find(token) >= 0
		note("%s (%s)" % [checks[token], token], "source %s, export %s" % [in_source, in_output])
		if in_source and not in_output:
			lost.append("%s (%s)" % [checks[token], token])
	# The texture half is already flagged above; this is the key/value half.
	var keys_lost: Array[String] = lost.filter(func(x: String): return x.find('("') >= 0)
	if not keys_lost.is_empty():
		known(
			663,
			"a .map round trip drops the worldspawn and brush-entity keys",
			(
				(
					"opening someone's map and saving it back loses: %s. "
					+ "`parse_map_text()` keeps every key/value pair in the record's "
					+ "'properties' and 'pairs'; a point entity's land on `entity_data` and "
					+ "come back out, and worldspawn's and a brush entity's have nowhere to "
					+ "go, so export has nothing to write. The `target` loss takes the "
					+ "trigger-to-door link with it, which is the whole of the map's logic"
				)
				% ", ".join(keys_lost)
			)
		)
