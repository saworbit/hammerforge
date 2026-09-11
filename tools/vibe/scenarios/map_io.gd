@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## `.map` is the exchange format, so both directions face someone else's tool.
##
## Export has to produce something TrenchBroom or J.A.C.K. will read, and import
## has to survive whatever they -- or a hand edit, or a precision blow-up -- hand
## back. The malformed inputs below are the ones a real file actually arrives in.

## Face lines a Valve 220 reader will reject or render degenerate, because a
## texture axis parallel to the face normal projects nothing.
const AXIS_TOLERANCE := 0.99


func id() -> String:
	return "map-io"


func summary() -> String:
	return ".map export fidelity in both formats, and import against broken files"


func run() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 16, 64), Vector3.ZERO)
	(
		root
		. create_brush_from_info(
			{
				"shape": 0,
				"size": Vector3(32, 32, 32),
				"transform": Transform3D(Basis(Vector3.UP, deg_to_rad(37)), Vector3(100, 20, 0)),
			}
		)
	)
	root.create_brush_from_info(
		{"shape": 1, "size": Vector3(24, 48, 24), "center": Vector3(-100, 0, 0), "sides": 8}
	)

	note("--- export, both formats")
	for format in ["quake", "valve220"]:
		var path := "user://vibe_export_%s.map" % format
		var rc: int = root.export_map(path, format)
		note("export %s" % format, "rc=%d bytes=%d" % [rc, HFVibe.file_size(path)])
		if format == "valve220":
			_check_valve_axes(path)

		var reopened: Node3D = await fresh_root("Import_%s" % format)
		var import_rc: int = reopened.import_map(path)
		note(
			"  reimport %s" % format,
			"rc=%d brushes=%d" % [import_rc, reopened.brush_system.get_live_brush_count()]
		)
		if reopened.brush_system.get_live_brush_count() != 3:
			flag(
				"%s round trip changed the brush count" % format,
				"3 out, %d back" % reopened.brush_system.get_live_brush_count()
			)

	note("--- an unrecognised format name")
	var fallback := "user://vibe_export_bogus.map"
	root.export_map(fallback, "not-a-format")
	var quake_bytes := HFVibe.file_size("user://vibe_export_quake.map")
	if HFVibe.file_size(fallback) == quake_bytes:
		note("an unknown format silently falls back to classic Quake")

	note("--- import against malformed files")
	var cases := {
		"empty": "",
		"garbage": "this is not a map at all",
		"unclosed": '{\n"classname" "worldspawn"\n{\n( 0 0 0 ) ( 1 0 0 ) ( 0 1 0 ) t 0 0 0 1 1\n',
		"coincident_points":
		'{\n"classname" "worldspawn"\n{\n( 0 0 0 ) ( 0 0 0 ) ( 0 0 0 ) t 0 0 0 1 1\n}\n}\n',
		"huge_coords":
		'{\n"classname" "worldspawn"\n{\n( 1e30 1e30 1e30 ) ( 1 0 0 ) ( 0 1 0 ) t 0 0 0 1 1\n}\n}\n',
		"nan_coords":
		'{\n"classname" "worldspawn"\n{\n( nan nan nan ) ( 1 0 0 ) ( 0 1 0 ) t 0 0 0 1 1\n}\n}\n',
		"deep_nesting": "{".repeat(500),
	}
	for name in cases:
		var path := "user://vibe_bad/%s.map" % name
		HFVibe.write_text(path, cases[name])
		var target: Node3D = await fresh_root("Bad_%s" % name)
		var rc: int = target.import_map(path)
		var count: int = target.brush_system.get_live_brush_count()
		note("%-18s" % name, "rc=%d brushes=%d" % [rc, count])
		if rc == OK and count > 0 and name in ["nan_coords", "huge_coords"]:
			known(
				318,
				"%s imported as a brush and reported success" % name,
				"a brush with non-finite geometry is now in the level"
			)


## Every Valve 220 face line carries two texture axes that have to lie in the
## face plane. Read them back out and check them against the plane the same line
## defines.
func _check_valve_axes(path: String) -> void:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
	var degenerate := 0
	var checked := 0
	for line in text.split("\n"):
		if not ("[" in line and ")" in line):
			continue
		var points := _parse_points(line)
		if points.size() < 3:
			continue
		var normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
		var axes := _parse_axes(line)
		if axes.size() < 2:
			continue
		checked += 1
		for axis in axes:
			if absf(axis.normalized().dot(normal)) > AXIS_TOLERANCE:
				degenerate += 1
				break
	note("valve220 faces checked", "%d, degenerate axes on %d" % [checked, degenerate])
	if degenerate > 0:
		known(
			317,
			"valve220 texture axes are parallel to the face normal",
			"%d of %d faces" % [degenerate, checked]
		)


func _parse_points(line: String) -> Array:
	var points: Array = []
	var depth := 0
	var current := ""
	for c in line:
		if c == "(":
			depth += 1
			current = ""
		elif c == ")" and depth > 0:
			depth -= 1
			var parts := current.strip_edges().split(" ", false)
			if parts.size() == 3:
				points.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
			current = ""
		elif depth > 0:
			current += c
	return points


func _parse_axes(line: String) -> Array:
	var axes: Array = []
	var depth := 0
	var current := ""
	for c in line:
		if c == "[":
			depth += 1
			current = ""
		elif c == "]" and depth > 0:
			depth -= 1
			var parts := current.strip_edges().split(" ", false)
			if parts.size() >= 3:
				axes.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
			current = ""
		elif depth > 0:
			current += c
	return axes
