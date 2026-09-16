@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether an incremental bake lands where a full bake would.
##
## `bake_dirty()` exists so a mapper does not pay for the whole level every time
## they nudge one brush, and it is the path the editor takes most often. A full
## bake is the reference: if the two ever disagree, the level a mapper is looking
## at is not the level that ships, and the difference only shows up on whatever
## triggers a full rebuild next -- a reopen, a clean bake, the exporter.


func id() -> String:
	return "bake-equivalence"


func summary() -> String:
	return "whether bake_dirty() produces the geometry a full bake would, after each kind of edit"


func run() -> void:
	await _after_each_kind_of_edit()
	await _repeated_dirty_bakes()


func _build(root: Node3D) -> Array:
	var made: Array = []
	made.append(box(root, Vector3(512, 16, 512), Vector3(0, -8, 0)))
	for i in 5:
		made.append(box(root, Vector3(64, 96, 64), Vector3(-128.0 + i * 64.0, 48, 0)))
	made.append(box(root, Vector3(256, 128, 16), Vector3(0, 64, -128)))
	return made


## Everything the baked container holds, in a form two bakes can be compared by.
func _fingerprint(root: Node3D) -> Dictionary:
	if root.baked_container == null:
		return {"container": "none"}
	var meshes := 0
	var surfaces := 0
	var verts := 0
	var tris := 0
	var bounds := AABB()
	var first := true
	var shapes := 0
	# Counts and bounds are dominated by the floor, so a brush moved inside the
	# level would not change either. Sum the world positions as well, which does.
	var centroid := Vector3.ZERO
	for node in _all(root.baked_container, []):
		if node is CollisionShape3D:
			shapes += 1
		if not (node is MeshInstance3D) or node.mesh == null:
			continue
		meshes += 1
		var m: Mesh = node.mesh
		surfaces += m.get_surface_count()
		for s in m.get_surface_count():
			var arrays: Array = m.surface_get_arrays(s)
			var v = arrays[Mesh.ARRAY_VERTEX]
			if v == null:
				continue
			verts += v.size()
			var idx = arrays[Mesh.ARRAY_INDEX]
			tris += (idx.size() / 3) if (idx != null and idx.size() > 0) else (v.size() / 3)
			for p in v:
				var world: Vector3 = (node as Node3D).global_transform * p
				centroid += world
				if first:
					bounds = AABB(world, Vector3.ZERO)
					first = false
				else:
					bounds = bounds.expand(world)
	return {
		"meshes": meshes,
		"surfaces": surfaces,
		"verts": verts,
		"tris": tris,
		"collision_shapes": shapes,
		"vertex_sum": (centroid / maxf(1.0, float(verts))).snapped(Vector3.ONE * 0.001),
		"bounds":
		(
			"%s .. %s"
			% [
				bounds.position.snapped(Vector3.ONE * 0.01),
				(bounds.position + bounds.size).snapped(Vector3.ONE * 0.01)
			]
		),
	}


func _all(node: Node, out: Array) -> Array:
	out.append(node)
	for c in node.get_children():
		_all(c, out)
	return out


## Apply an edit, bake incrementally, then compare against a level built the
## same way and baked from scratch.
##
## Every edit goes through a LevelRoot method that tags the brush dirty. Writing
## `global_position` straight onto the node does *not*: the tracker that notices
## a native gizmo drag (`HFBrushChangeTracker`) lives on the plugin, not on the
## root, so a bare headless root has nothing watching. Driving the edits through
## the API is what makes the two bakes comparable rather than measuring the
## harness.
func _after_each_kind_of_edit() -> void:
	var edits: Array = ["nudge", "resize", "delete", "add", "rotate", "material", "hide"]
	for edit in edits:
		var a: Node3D = await fresh_root("Dirty_%s" % edit)
		var made_a := _build(a)
		await frame()
		await a.bake()
		await frame()
		_edit(a, made_a, edit)
		await frame()
		await a.bake_dirty()
		await frame()
		var incremental := _fingerprint(a)

		var b: Node3D = await fresh_root("Full_%s" % edit)
		var made_b := _build(b)
		await frame()
		_edit(b, made_b, edit)
		await frame()
		await b.bake()
		await frame()
		var full := _fingerprint(b)

		note("%s: bake_dirty" % edit, incremental)
		note("%s: full bake" % edit, full)
		if HFVibe.canonical(incremental) != HFVibe.canonical(full):
			flag(
				"after a %s, an incremental bake does not match a full one" % edit,
				"dirty %s vs full %s" % [incremental, full]
			)


func _edit(root: Node3D, made: Array, edit: String) -> void:
	# made[4] sits off-centre in X, so a resize or a rotation of it moves the
	# baked centroid. made[2] is on the axis and would not.
	var target: Node3D = made[4] if made.size() > 4 else made[0]
	var tid := str(target.get_meta("brush_id", ""))
	match edit:
		"nudge":
			root.nudge_brushes_by_id([tid], Vector3(32, 0, 0))
		"resize":
			target.size = Vector3(96, 96, 96)
			root.tag_brush_dirty(tid)
		"delete":
			root.delete_brush(target)
		"add":
			box(root, Vector3(64, 64, 64), Vector3(0, 32, 192))
		"rotate":
			root.rotate_managed_nodes([tid], [], 1, 45.0, target.global_position)
		"material":
			if target.get("faces") is Array and not target.faces.is_empty():
				target.faces[0].material_idx = 0
				root.tag_brush_dirty(tid)
		"hide":
			target.visible = false
			root.bake_visible_only = true
			root.tag_brush_dirty(tid)


## Ten dirty bakes in a row against one full bake of the same end state.
func _repeated_dirty_bakes() -> void:
	var a: Node3D = await fresh_root("DirtyChain")
	var made := _build(a)
	await frame()
	await a.bake()
	for i in 10:
		a.nudge_brushes_by_id([str(made[1 + (i % 5)].get_meta("brush_id", ""))], Vector3(0, 8, 0))
		await frame()
		await a.bake_dirty()
	await frame()
	var chained := _fingerprint(a)

	var b: Node3D = await fresh_root("ChainReference")
	var made_b := _build(b)
	for i in 10:
		b.nudge_brushes_by_id([str(made_b[1 + (i % 5)].get_meta("brush_id", ""))], Vector3(0, 8, 0))
	await frame()
	await b.bake()
	await frame()
	var reference := _fingerprint(b)

	note("after ten incremental bakes", chained)
	note("one full bake of the same end state", reference)
	if HFVibe.canonical(chained) != HFVibe.canonical(reference):
		flag(
			"ten incremental bakes drift away from a full bake of the same level",
			"%s vs %s" % [chained, reference]
		)
