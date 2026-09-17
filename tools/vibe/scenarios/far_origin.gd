@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The same level built at the origin and built where a real map sits.
##
## Quake-lineage editors run a +/-16384 world and mappers use it: a map is laid
## out across the whole grid, not huddled at 0,0,0. Everything in HammerForge
## that compares two floats does it with an absolute epsilon -- `0.001`,
## `0.0001`, `is_equal_approx` -- and a 32-bit float's spacing at 16384 is
## 0.00195, at 65536 it is 0.0078. An epsilon smaller than the representable
## step is a comparison that cannot hold.
##
## So: build one brush, measure it; build the identical brush a long way out,
## measure it the same way, and report every answer that moved. Anything that
## changes is something a mapper working out there gets and a mapper working at
## the origin never sees.

const DISTANCES := [0.0, 1024.0, 8192.0, 16384.0, 32768.0]


func id() -> String:
	return "far-origin"


func summary() -> String:
	return "whether a brush built far from the origin is the brush built at it"


func run() -> void:
	await _one_box_at_each_distance()
	await _round_trips_out_there()
	await _operations_out_there()


## The measurements that should not care where the brush is.
func _measure(root: Node3D, brush) -> Dictionary:
	var extent: Vector3 = HFVibe.local_extent(brush)
	var volume := 0.0
	for face in brush.faces:
		var tri: Dictionary = face.triangulate()
		var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
		for t in range(verts.size() / 3):
			var i := t * 3
			volume += verts[i].dot(verts[i + 1].cross(verts[i + 2])) / 6.0
	return {
		"faces": brush.faces.size(),
		"extent": extent,
		"volume": absf(volume),
		"inward": HFVibe.inward_face_count(brush),
		"convex": root.vertex_system.validate_convexity(brush),
	}


func _one_box_at_each_distance() -> void:
	note("-- one 128-cube, moved out along every axis --")
	var root: Node3D = await fresh_root()
	var baseline := {}
	for d in DISTANCES:
		var centre := Vector3(d, d * 0.25, d)
		var brush = box(root, Vector3(128, 128, 128), centre)
		await frame()
		var m := _measure(root, brush)
		if d == 0.0:
			baseline = m
			note("at origin", m)
			continue
		var moved: Array[String] = []
		if m["faces"] != baseline["faces"]:
			moved.append("faces %s -> %s" % [baseline["faces"], m["faces"]])
		if not (m["extent"] as Vector3).is_equal_approx(baseline["extent"]):
			moved.append("extent %s -> %s" % [baseline["extent"], m["extent"]])
		if absf(m["volume"] - baseline["volume"]) > baseline["volume"] * 0.001:
			moved.append("volume %s -> %s" % [baseline["volume"], m["volume"]])
		if m["inward"] != baseline["inward"]:
			moved.append("inward faces %s -> %s" % [baseline["inward"], m["inward"]])
		if m["convex"] != baseline["convex"]:
			moved.append("convexity %s -> %s" % [baseline["convex"], m["convex"]])
		if moved.is_empty():
			note("at %s: identical" % d)
		else:
			flag("a 128-cube is not the same brush at %s units out" % d, ", ".join(moved))


## Save the level, load it back, and ask what the coordinates came back as.
func _round_trips_out_there() -> void:
	note("-- a .hflevel and a .map round trip, at 16384 --")
	var root: Node3D = await fresh_root()
	var far := Vector3(16384.0, 512.0, -16384.0)
	var brush = box(root, Vector3(256, 128, 256), far)
	await frame()
	var before: Vector3 = brush.global_position
	var path := "user://vibe_far.hflevel"
	root.hflevel_autosave_path = path
	root.save_hflevel(path)
	if not await HFVibe.settle_save(_tree, root):
		flag("the save never finished at 16384", "thread still running")
		return
	root.clear_brushes()
	await frame()
	root.load_hflevel(path)
	await frame()
	var loaded := root.get_children().filter(func(n): return root.is_brush_node(n))
	if loaded.is_empty():
		var all_brushes: Array = []
		_collect_brushes(root, root, all_brushes)
		loaded = all_brushes
	if loaded.is_empty():
		flag("nothing came back from a .hflevel saved at 16384")
	else:
		var after: Vector3 = (loaded[0] as Node3D).global_position
		var drift := (after - before).length()
		note(".hflevel drift at 16384", "%s units (%s -> %s)" % [drift, before, after])
		if drift > 0.01:
			flag(".hflevel moves a brush built at 16384", "%s units of drift" % drift)

	var map_path := "user://vibe_far.map"
	root.export_map(map_path, "valve220")
	await frame()
	var text := FileAccess.get_file_as_string(map_path)
	if text == "":
		flag(".map export at 16384 wrote nothing")
	else:
		note(".map size at 16384", "%s bytes" % text.length())
		root.clear_brushes()
		await frame()
		root.import_map(map_path)
		await frame()
		var back: Array = []
		_collect_brushes(root, root, back)
		if back.is_empty():
			flag(
				".map written at 16384 imports as an empty level",
				"export wrote %s bytes" % text.length()
			)
		else:
			var re: Vector3 = (back[0] as Node3D).global_position
			var map_drift := (re - before).length()
			note(".map drift at 16384", "%s units (%s -> %s)" % [map_drift, before, re])
			if map_drift > 1.0:
				flag(".map round trip moves a brush built at 16384", "%s units" % map_drift)
			var extent: Vector3 = HFVibe.local_extent(back[0])
			note(".map re-imported extent", extent)
			if not extent.is_equal_approx(Vector3(256, 128, 256)):
				flag(
					"a 256x128x256 brush at 16384 comes back a different size from .map",
					"extent %s" % extent
				)


func _collect_brushes(root: Node3D, node: Node, out: Array) -> void:
	for child in node.get_children():
		if root.is_brush_node(child):
			out.append(child)
		_collect_brushes(root, child, out)


## Editing operations, run at the origin and run at 16384, compared.
func _operations_out_there() -> void:
	note("-- clip, hollow and carve at the origin against 16384 --")
	for d in [0.0, 16384.0]:
		var root: Node3D = await fresh_root()
		var centre := Vector3(d, 0, d)

		var clip_target = box(root, Vector3(256, 256, 256), centre)
		await frame()
		var clip_ok = root.clip_brush_by_id(clip_target.brush_id, 0, centre.x)
		var clip_count := _brush_count(root)
		note("at %s: clip reported %s, level holds %s brushes" % [d, clip_ok.ok, clip_count])

		var root2: Node3D = await fresh_root()
		var hollow_target = box(root2, Vector3(512, 512, 512), centre)
		await frame()
		var hollow = root2.hollow_brush_by_id(hollow_target.brush_id, 16.0)
		var walls := _brush_count(root2)
		note("at %s: hollow reported %s, produced %s brushes" % [d, hollow.ok, walls])
		if d > 0.0 and walls != 6:
			flag("hollow at %s does not produce six walls" % d, "%s brushes" % walls)

		var root3: Node3D = await fresh_root()
		var solid = box(root3, Vector3(512, 256, 512), centre)
		await frame()
		var cutter = box(root3, Vector3(128, 512, 128), centre)
		await frame()
		var carve = root3.carve_with_brush(cutter.brush_id)
		note(
			"at %s: carve reported %s, level holds %s brushes" % [d, carve.ok, _brush_count(root3)]
		)
		if d > 0.0 and not carve.ok:
			flag("carve refuses at %s and works at the origin" % d, carve.user_text())
		var unused_ref = solid


func _brush_count(root: Node3D) -> int:
	var out: Array = []
	_collect_brushes(root, root, out)
	return out.size()
