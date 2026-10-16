@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether an agent can get through a door on the navmesh the bake makes.
##
## `navmesh` checks the polygons are there and the agent settings reach them.
## A level with AI in it has doors in it, and a door is a brush entity the bake
## gives a `StaticBody3D` of its own (`_append_func_detail()`), while the navmesh
## is parsed from the container's static colliders. So the question is whether
## the navmesh treats a door as the doorway it stands in or as a wall, and the
## same for the other brush entities a corridor might have across it: a trigger,
## which a game walks through, and a `func_wall`, which a game switches off.
##
## Measured on the polygons, not on a path query: every polygon is joined to the
## polygons it shares an edge with, and the question is whether the polygon
## under one end of a corridor is joined to the polygon under the other end.

const CORRIDOR := Vector3(2.4, 3.0, 12.0)


func id() -> String:
	return "navmesh-doors"


func summary() -> String:
	return "whether a door, a trigger or a func_wall cuts the baked navmesh in two, and whether a prop is in it"


func run() -> void:
	var x := 0.0
	for what in [
		"nothing",
		"func_door",
		"func_door (open: wait -1)",
		"trigger_once",
		"func_wall",
		"func_detail"
	]:
		await _corridor(what, Vector3(x, 0, 0))
		x += 100.0
	await _a_prop_in_a_room(Vector3(x, 0, 0))


const CRATE_PATH := "user://navmesh_doors_crate.tscn"


## A 2 m crate placed with `prop_static`, the documented way to put a model in a
## level, in the middle of a room. An agent should walk round it.
func _a_prop_in_a_room(at: Vector3) -> void:
	var crate := Node3D.new()
	crate.name = "Crate"
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(2, 2, 2)
	shape.shape = box_shape
	shape.position = Vector3(0, 1, 0)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(2, 2, 2)
	mesh.mesh = box_mesh
	mesh.position = Vector3(0, 1, 0)
	crate.add_child(body)
	body.add_child(shape)
	crate.add_child(mesh)
	body.owner = crate
	shape.owner = crate
	mesh.owner = crate
	var packed := PackedScene.new()
	packed.pack(crate)
	ResourceSaver.save(packed, CRATE_PATH)
	crate.free()

	var root: Node3D = await fresh_root()
	box(root, Vector3(8, 0.2, 8), at + Vector3(0, -0.1, 0))
	(
		root
		. _restore_entity_from_info(
			{
				"entity_type": "prop_static",
				"entity_class": "prop_static",
				"transform": Transform3D(Basis.IDENTITY, at),
				"properties": {"scene": CRATE_PATH},
				"name": "crate_1",
				"entity_name": "crate_1",
			}
		)
	)
	await frame()
	root.bake_navmesh = true
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	var region := (
		container.get_node_or_null("BakedNavmesh") as NavigationRegion3D if container else null
	)
	var under_baked := -2
	if region and region.navigation_mesh:
		under_baked = _polygon_under(region.navigation_mesh, at)
	var scene_path := "user://navmesh_doors_playtest.tscn"
	root.export_playtest_scene(scene_path)
	var under_exported := -2
	var crate_bodies := 0
	var packed_level: PackedScene = load(scene_path) if ResourceLoader.exists(scene_path) else null
	if packed_level:
		var inst := packed_level.instantiate()
		for n in inst.find_children("*", "NavigationRegion3D", true, false):
			var nm: NavigationMesh = (n as NavigationRegion3D).navigation_mesh
			if nm:
				under_exported = _polygon_under(nm, at)
		crate_bodies = inst.find_children("Body", "StaticBody3D", true, false).size()
		inst.free()
	note(
		"a 2 m crate placed as a prop_static in the middle of an 8 m room",
		(
			(
				"navmesh polygon under the crate's centre: baked %d, exported playtest %d "
				+ "(-1 is a hole, as there should be); crate collision bodies in the export: %d"
			)
			% [under_baked, under_exported, crate_bodies]
		)
	)
	# Fixed by #1197: the bake parses each prop the export will build.
	if under_baked >= 0 or under_exported >= 0:
		flag(
			"the baked navmesh runs straight through a prop_static's model again",
			(
				(
					"a 2 m crate with its own StaticBody3D, placed as a prop_static in an 8 m room. "
					+ "The navmesh has a polygon under the crate's centre in the bake (%d) and in "
					+ "the exported playtest scene (%d), while the export does put the crate's "
					+ "collision in the level (%d body). Agents path through the crate."
				)
				% [under_baked, under_exported, crate_bodies]
			)
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scene_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CRATE_PATH))
	await drop_root(root)


func _corridor(across: String, at: Vector3) -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(CORRIDOR.x, 0.2, CORRIDOR.z), at + Vector3(0, -0.1, 0))
	box(root, Vector3(0.3, CORRIDOR.y, CORRIDOR.z), at + Vector3(-CORRIDOR.x * 0.5 - 0.15, 1.5, 0))
	box(root, Vector3(0.3, CORRIDOR.y, CORRIDOR.z), at + Vector3(CORRIDOR.x * 0.5 + 0.15, 1.5, 0))
	if across != "nothing":
		var b = box(root, Vector3(CORRIDOR.x, 2.4, 0.2), at + Vector3(0, 1.2, 0))
		var cls := across.split(" ")[0]
		root.tie_brushes_to_entity([str(b.get_meta("brush_id", ""))], cls, "thing")
		if across.contains("wait -1"):
			root.set_entity_property(b, "wait", -1.0)
	root.bake_navmesh = true
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	var region := (
		container.get_node_or_null("BakedNavmesh") as NavigationRegion3D if container else null
	)
	if region == null or region.navigation_mesh == null:
		flag("no navmesh baked for the corridor with %s across it" % across)
		await drop_root(root)
		return
	var nav: NavigationMesh = region.navigation_mesh
	var a := _polygon_under(nav, at + Vector3(0, 0, -CORRIDOR.z * 0.4))
	var b := _polygon_under(nav, at + Vector3(0, 0, CORRIDOR.z * 0.4))
	var joined := a >= 0 and b >= 0 and _component(nav, a) == _component(nav, b)
	note(
		"corridor with %s across it" % across,
		(
			"%d polygons; polygon under the near end %d, far end %d; joined: %s"
			% [nav.get_polygon_count(), a, b, joined]
		)
	)
	if across == "nothing" and not joined:
		flag("the scenario's own control corridor is not joined end to end", "fix the harness")
	# Fixed by #1196: what moves is left out of the parse, and only that.
	if across.begins_with("func_door") and not joined:
		flag(
			"the baked navmesh treats a door as a wall again: %s" % across,
			(
				"a 2.4 m corridor with a func_door across the middle bakes to a navmesh in "
				+ "two pieces, so no agent can plan a path through the doorway, open or shut."
			)
		)
	if (across == "func_wall" or across == "func_detail") and joined:
		flag("a %s across a corridor no longer cuts the baked navmesh" % across)
	if across == "trigger_once" and not joined:
		flag("a trigger volume cuts the baked navmesh in two")
	await drop_root(root)


## The polygon at the height of `p` whose outline contains it from above, or -1.
## The height counts, because the top of a crate is walkable too.
func _polygon_under(nav: NavigationMesh, p: Vector3) -> int:
	var verts := nav.get_vertices()
	for i in nav.get_polygon_count():
		var poly := PackedVector2Array()
		var level := true
		for idx in nav.get_polygon(i):
			poly.append(Vector2(verts[idx].x, verts[idx].z))
			level = level and absf(verts[idx].y - p.y) < 1.0
		if level and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly):
			return i
	return -1


## Which connected piece polygon `start` is in, as the lowest polygon index in it.
func _component(nav: NavigationMesh, start: int) -> int:
	var verts := nav.get_vertices()
	# Edges keyed by their two end points, rounded, so two polygons that share an
	# edge by position (not only by index) are joined.
	var by_edge := {}
	for i in nav.get_polygon_count():
		var poly: PackedInt32Array = nav.get_polygon(i)
		for k in poly.size():
			var p := _key(verts[poly[k]])
			var q := _key(verts[poly[(k + 1) % poly.size()]])
			var e := p + "|" + q if p < q else q + "|" + p
			if not by_edge.has(e):
				by_edge[e] = []
			by_edge[e].append(i)
	var seen := {start: true}
	var queue: Array = [start]
	var lowest := start
	while not queue.is_empty():
		var i: int = queue.pop_back()
		lowest = mini(lowest, i)
		var poly: PackedInt32Array = nav.get_polygon(i)
		for k in poly.size():
			var p := _key(verts[poly[k]])
			var q := _key(verts[poly[(k + 1) % poly.size()]])
			var e := p + "|" + q if p < q else q + "|" + p
			for j in by_edge.get(e, []):
				if not seen.has(j):
					seen[j] = true
					queue.append(j)
	return lowest


func _key(v: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [v.x, v.y, v.z]
