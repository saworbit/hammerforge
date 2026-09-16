@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## One number, asked of every part of the editor that has an opinion about it:
## how big is a thing.
##
## A level editor only works if the drawing tools, the generated content and the
## player agree on how many units a person is. Quake-family editors put a player
## at ~72 units; Godot puts one at ~1.8. HammerForge sits on Godot and is modelled
## on Hammer, so it is exactly the place where the two conventions can end up in
## one project without anyone noticing.


func id() -> String:
	return "world-scale"


func summary() -> String:
	return "whether the drawing defaults, the generators, the shipped examples and the player agree on how big a person is"


const PLAYER_HEIGHT := 1.6  # HFSpawnSystem.PLAYER_HEIGHT


func run() -> void:
	await _what_each_surface_thinks_a_metre_is()


func _schema_defaults(type_name: String) -> Dictionary:
	var out: Dictionary = {}
	var schema = HFGeneratorSystem.settings_schema(type_name)
	if not (schema is Array):
		return out
	for field in schema:
		if field is Dictionary and field.has("key"):
			out[str(field["key"])] = field.get("default", null)
	return out


func _example_extent() -> float:
	var path := "res://addons/hammerforge/data/example_levels.json"
	if not FileAccess.file_exists(path):
		return -1.0
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return -1.0
	var biggest := 0.0
	for example in parsed.get("examples", []):
		for b in example.get("brushes", []):
			var size = b.get("size", [0, 0, 0])
			if size is Array and size.size() >= 3:
				biggest = maxf(biggest, maxf(float(size[0]), float(size[2])))
	return biggest


func _what_each_surface_thinks_a_metre_is() -> void:
	var root: Node3D = await fresh_root()

	var rows: Array = []
	rows.append(["the playtest player's height", PLAYER_HEIGHT, "hf_spawn_system.gd:14"])
	rows.append(["the playtest player's radius", 0.35, "hf_spawn_system.gd:13"])
	rows.append(["grid snap, default", root.grid_snap, "level_root.gd:118"])
	rows.append(["a drawn brush, default", root.brush_size_default.x, "level_root.gd:124"])
	var drag: Dictionary = root.drag_system._compute_brush_info(
		Vector3.ZERO,
		Vector3.ZERO,
		root.grid_snap,
		0,
		root.brush_size_default,
		root.AxisLock.NONE,
		false,
		false
	)
	rows.append(["a click with no drag makes a brush", drag["size"].x, "hf_drag_system.gd"])
	for type_name in HFGeneratorSystem.known_types():
		var defaults := _schema_defaults(type_name)
		for key in ["radius", "width", "step_height", "step_depth", "wall_thickness"]:
			if defaults.has(key) and defaults[key] != null:
				rows.append(
					["%s default %s" % [type_name, key], float(defaults[key]), "generator schema"]
				)
	rows.append(["the widest shipped example brush", _example_extent(), "example_levels.json"])
	rows.append(
		["bake_connector_stair_height, default", root.bake_connector_stair_height, "level_root.gd"]
	)
	rows.append(["bake_occluder_min_area, default", root.bake_occluder_min_area, "level_root.gd"])

	for row in rows:
		note(
			"%-40s" % row[0],
			(
				"%.3f units = %.2f player heights   (%s)"
				% [row[1], float(row[1]) / PLAYER_HEIGHT, row[2]]
			)
		)

	var drawn: float = float(root.brush_size_default.x) / PLAYER_HEIGHT
	var example: float = _example_extent() / PLAYER_HEIGHT
	note("a default brush is %.1f players tall" % drawn)
	note("the widest shipped example brush is %.1f players wide" % example)
	if drawn > 5.0 and example < 20.0:
		known(
			625,
			"the drawing defaults and the player are on different scales",
			(
				(
					"a default brush is %.0f units, which is %.0f playtest players tall, while "
					+ "the widest brush in any shipped example is %.0f units (%.0f players) and "
					+ "the auto-connector's stair height runs 0.05..2.0. The drawing side -- "
					+ "grid snap %s, default brush %s, the generator schema defaults -- is "
					+ "authored at Quake-family scale where a player is about 72 units; the "
					+ "player, the examples, the stair connector and the occluder area default "
					+ "are authored at Godot scale where a player is 1.6. A mapper who draws "
					+ "with the defaults and presses Test Level is a %.0f-times-too-small "
					+ "person in a cathedral, and one who loads an example then draws beside it "
					+ "cannot put a brush inside a room a fraction of one grid square across"
				)
				% [
					root.brush_size_default.x,
					drawn,
					_example_extent(),
					example,
					root.grid_snap,
					root.brush_size_default,
					drawn,
				]
			)
		)
