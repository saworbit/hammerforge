@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## A level the size of a real game map, timed at every step a mapper waits on.
##
## `level-scale` walks a level up in stages and records the curve. `cost` prices
## one brush of each shape. Neither one builds a map you would actually ship: a
## Quake or Half-Life level is 800 to 2000 brushes with a dozen materials, and
## the interesting numbers are the ones a mapper meets on a Friday afternoon --
## how long Ctrl+S takes, how long a full bake takes, how big the file is, and
## how many draw calls the result is.
##
## Everything here is a measurement, not a rule. A number only becomes a finding
## when it is out of proportion to the thing beside it.


func id() -> String:
	return "big-level"


func summary() -> String:
	return "a 900-brush map priced at every step: build, save, validate, bake, draw calls"


const BRUSHES := 900


func run() -> void:
	await _build_and_price()


## A map shaped like one: a grid of rooms with walls, floors, ceilings and
## clutter, not 900 copies of the same box in the same place.
func _build(root: Node3D) -> Dictionary:
	var made := 0
	var t0 := Time.get_ticks_msec()
	var cells := 12
	var pitch := 10.0
	for gx in cells:
		for gz in cells:
			var cx := gx * pitch
			var cz := gz * pitch
			box(root, Vector3(pitch, 0.2, pitch), Vector3(cx, -0.1, cz))
			box(root, Vector3(pitch, 0.2, pitch), Vector3(cx, 3.1, cz))
			box(root, Vector3(pitch, 3, 0.3), Vector3(cx, 1.5, cz - pitch * 0.5))
			box(root, Vector3(0.3, 3, pitch), Vector3(cx - pitch * 0.5, 1.5, cz))
			made += 4
			if made >= BRUSHES:
				break
			# Clutter: crates and a pillar, the things that make a room a room.
			box(root, Vector3(0.8, 0.8, 0.8), Vector3(cx - 2, 0.4, cz - 2))
			box(root, Vector3(0.8, 1.6, 0.8), Vector3(cx + 2, 0.8, cz + 2))
			box(root, Vector3(1.0, 3, 1.0), Vector3(cx, 1.5, cz))
			made += 3
			if made >= BRUSHES:
				break
		if made >= BRUSHES:
			break
	return {"brushes": made, "ms": Time.get_ticks_msec() - t0}


func _mesh_facts(node: Node, out: Dictionary) -> Dictionary:
	if node is MeshInstance3D and node.mesh:
		out["meshes"] = int(out.get("meshes", 0)) + 1
		var m: Mesh = node.mesh
		for s in m.get_surface_count():
			out["surfaces"] = int(out.get("surfaces", 0)) + 1
			var arrays: Array = m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			out["vertices"] = int(out.get("vertices", 0)) + verts.size()
			var idx = arrays[Mesh.ARRAY_INDEX]
			var tris: int = (idx.size() / 3) if idx != null else (verts.size() / 3)
			out["triangles"] = int(out.get("triangles", 0)) + tris
	if node is CollisionShape3D:
		out["collision_shapes"] = int(out.get("collision_shapes", 0)) + 1
	for c in node.get_children():
		_mesh_facts(c, out)
	return out


func _build_and_price() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false

	var built := _build(root)
	await frame()
	note("brushes built", built["brushes"])
	note("time to build them", "%d ms" % built["ms"])
	note("live brush count the level agrees on", root.brush_system.get_live_brush_count())

	# Materials, because a map with one material is not a map.
	var palette := 12
	for i in palette:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(float(i) / palette, 0.5, 0.8)
		root.material_manager.materials.append(mat)
	var brushes: Array = root.draft_brushes_node.get_children()
	for i in brushes.size():
		var b = brushes[i]
		for face in b.faces:
			if face:
				face.material_idx = i % palette
	note("materials in the palette", palette)

	# Validate: the thing a mapper runs before a bake.
	var t := Time.get_ticks_msec()
	var report = root.validate_level()
	note("validate_level", "%d ms" % (Time.get_ticks_msec() - t))
	note("validate reported", report if report is Dictionary else str(report))

	# One undo step. `capture_state()` is the unit, and it is taken per action.
	t = Time.get_ticks_msec()
	var state = root.capture_state()
	var capture_ms := Time.get_ticks_msec() - t
	note("capture_state (one undo step)", "%d ms" % capture_ms)
	t = Time.get_ticks_msec()
	root.restore_state(state)
	await frame()
	note("restore_state", "%d ms" % (Time.get_ticks_msec() - t))
	if capture_ms > 250:
		flag(
			"one undo step on a 900-brush map costs %d ms" % capture_ms,
			(
				"capture_state() runs on every action, so this is the delay between a nudge "
				+ "and the brush moving. At this size the editor is unusable for the map sizes "
				+ "the format is designed for."
			)
		)

	# The bake, before anything touches the file, so the surface count is a
	# measurement of the level the mapper textured rather than of what a save
	# and a load left behind.
	var t_bake := Time.get_ticks_msec()
	await root.bake(false, false)
	await frame()
	note("full bake, freshly textured", "%d ms" % (Time.get_ticks_msec() - t_bake))
	var fresh := _mesh_facts(root.get_node_or_null("BakedGeometry"), {})
	note("baked geometry, freshly textured", fresh)
	note(
		"draw calls for %d materials" % palette,
		"%d surface(s) across %d MeshInstance3D" % [int(fresh.get("surfaces", 0)), int(fresh.get("meshes", 0))]
	)
	if int(fresh.get("surfaces", 0)) > palette * 2:
		flag(
			"a %d-material map bakes to %d surfaces" % [palette, int(fresh.get("surfaces", 0))],
			(
				"the face-material path groups by material, so the floor of the whole map "
				+ "should be one surface. More surfaces than materials means the grouping is "
				+ "not reaching across brushes and every draw call is paid per brush."
			)
		)

	# Ctrl+S.
	var path := "user://vibe_big_level.hflevel"
	t = Time.get_ticks_msec()
	root.save_hflevel(path)
	var settled: bool = await HFVibe.settle_save(_tree, root, 3000)
	var save_ms := Time.get_ticks_msec() - t
	note("save_hflevel settled", settled)
	note("save_hflevel", "%d ms" % save_ms)
	note("file size", "%d bytes (%.1f KB)" % [HFVibe.file_size(path), HFVibe.file_size(path) / 1024.0])

	t = Time.get_ticks_msec()
	root.load_hflevel(path)
	await frame()
	note("load_hflevel", "%d ms" % (Time.get_ticks_msec() - t))
	note("brushes after the load", root.brush_system.get_live_brush_count())

	# The bake again, on the level that came back off disk.
	t = Time.get_ticks_msec()
	await root.bake(false, false)
	await frame()
	note("full bake, after the save and the load", "%d ms" % (Time.get_ticks_msec() - t))
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		flag("a 900-brush level baked nothing")
		return
	var facts := _mesh_facts(container, {})
	note("baked geometry, after the round trip", facts)
	note("collision shapes", int(facts.get("collision_shapes", 0)))
	if int(facts.get("surfaces", 0)) < int(fresh.get("surfaces", 0)):
		note(
			"the round trip cost %d surface(s)" % (int(fresh.get("surfaces", 0)) - int(facts.get("surfaces", 0))),
			(
				"the palette is made of StandardMaterial3D built in memory, and HFLevelIO "
				+ "writes a resource with no path as an empty slot -- the documented behaviour "
				+ "the `material-persistence` scenario covers. Recorded here so the two bake "
				+ "numbers above are read as measuring different levels"
			)
		)

	# Bake again with nothing changed: the incremental path a mapper leans on.
	t = Time.get_ticks_msec()
	await root.bake_dirty()
	note("bake_dirty with nothing dirty", "%d ms" % (Time.get_ticks_msec() - t))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
