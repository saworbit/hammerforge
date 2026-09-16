@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The five shipped example levels, built and inspected.
##
## `examples` covers what loading one does to the level already in the scene.
## This covers the levels themselves: an example is the first thing a new user
## clicks, and it is the only geometry in the project that ships as content
## rather than as code, so nothing in the test suite is looking at it.

const DATA_PATH := "res://addons/hammerforge/data/example_levels.json"


func id() -> String:
	return "examples-integrity"


func summary() -> String:
	return "whether each shipped example builds a level that validates and holds its invariants"


func run() -> void:
	await _each_example()
	await _the_loader_itself()


func _examples() -> Array:
	if not FileAccess.file_exists(DATA_PATH):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (parsed is Dictionary):
		return []
	var list = parsed.get("examples", [])
	return list if list is Array else []


## Build an example the way `dock._apply_example_data()` does.
func _build(root: Node3D, example: Dictionary) -> int:
	var made := 0
	for brush_data in example.get("brushes", []):
		var pos_arr: Array = brush_data.get("position", [0, 0, 0])
		var size_arr: Array = brush_data.get("size", [4, 4, 4])
		(
			root
			. create_brush_from_info(
				{
					"center": Vector3(pos_arr[0], pos_arr[1], pos_arr[2]),
					"size": Vector3(size_arr[0], size_arr[1], size_arr[2]),
					"shape": int(brush_data.get("shape", 0)),
					"operation": int(brush_data.get("operation", 0)),
				}
			)
		)
		made += 1
	for entity_data in example.get("entities", []):
		var epos_arr: Array = entity_data.get("position", [0, 0, 0])
		(
			root
			. _restore_entity_from_info(
				{
					"entity_type": str(entity_data.get("type", "point_light")),
					"entity_class": str(entity_data.get("type", "point_light")),
					"transform":
					Transform3D(Basis.IDENTITY, Vector3(epos_arr[0], epos_arr[1], epos_arr[2])),
					"properties": {},
					"name": "DraftEntity",
				}
			)
		)
		made += 1
	return made


func _each_example() -> void:
	var examples := _examples()
	note("shipped examples", examples.size())
	if examples.is_empty():
		flag("no example levels could be read from %s" % DATA_PATH)
		return
	for example in examples:
		if not (example is Dictionary):
			continue
		var eid := str(example.get("id", "?"))
		var root: Node3D = await fresh_root("Example_%s" % eid)
		var made := _build(root, example)
		await frame()

		var report: Dictionary = root.validate_level()
		var issues: Array = report.get("issues", [])
		var problems: Array = HFVibe.check_invariants(root)
		var baked: bool = await root.bake()
		await frame()
		var tris := 0
		if root.baked_container:
			for node in _all(root.baked_container, []):
				if node is MeshInstance3D and node.mesh:
					for s in node.mesh.get_surface_count():
						var arrays: Array = node.mesh.surface_get_arrays(s)
						var idx = arrays[Mesh.ARRAY_INDEX]
						var v = arrays[Mesh.ARRAY_VERTEX]
						if idx != null and idx.size() > 0:
							tris += idx.size() / 3
						elif v != null:
							tris += v.size() / 3

		note(
			"%s (%s)" % [eid, example.get("title", "")],
			(
				(
					"%d objects, %d brush(es), %d entit(y/ies), validate %d issue(s), "
					+ "%d invariant problem(s), bake %s, %d triangle(s)"
				)
				% [
					made,
					example.get("brushes", []).size(),
					example.get("entities", []).size(),
					issues.size(),
					problems.size(),
					baked,
					tris,
				]
			)
		)
		if not issues.is_empty():
			flag("the shipped example '%s' does not validate" % eid, issues)
		for problem in problems:
			flag("the shipped example '%s' breaks an invariant" % eid, problem)
		if not baked:
			flag("the shipped example '%s' will not bake" % eid)


func _all(node: Node, out: Array) -> Array:
	out.append(node)
	for c in node.get_children():
		_all(c, out)
	return out


## Two things in the loader worth writing down.
func _the_loader_itself() -> void:
	var examples := _examples()
	var types: Dictionary = {}
	var untyped := 0
	for example in examples:
		for entity_data in example.get("entities", []):
			if not entity_data.has("type"):
				untyped += 1
			types[str(entity_data.get("type", ""))] = true
	note("entity types the examples use", types.keys())
	note("example entities with no 'type' key", untyped)
	note(
		"the loader's fallback type",
		(
			'dock.gd:5931 defaults to "point_light", and entities.json defines '
			+ '"light_point" -- reachable only by a hand-written example that omits the '
			+ "key, which none of the shipped five do"
		)
	)
	note(
		"the loader's entity naming",
		(
			'dock.gd:5936 names every entity "DraftEntity" and sets no entity_name, so '
			+ "Godot dedupes them to DraftEntity2, DraftEntity3 and none has the authored "
			+ "address an I/O output is aimed at. None of the shipped examples is wired, "
			+ "so nothing depends on it today"
		)
	)
