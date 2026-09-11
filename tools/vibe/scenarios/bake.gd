@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The bake: the editor's actual output.
##
## Everything else in the plugin is upstream of this. A defect anywhere in the
## draft is only a defect because of what it does to the baked result, and the
## baked result is what ships. So the questions here are the ones a mapper
## implicitly trusts: is what came out the shape that went in, does baking twice
## give the same thing, does the draft survive being baked, and do the flags that
## say "leave these out" actually leave them out.


func id() -> String:
	return "bake"


func summary() -> String:
	return "what a bake produces: geometry, idempotence, and the flags that exclude brushes"


func run() -> void:
	await _a_box_bakes_to_a_box()
	await _baking_twice()
	await _bake_visible_only()
	await _rebaking_after_a_bake_setting_changes()
	await _a_brush_with_no_faces_in_the_bake()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## Total triangle count and the summed volume of every mesh under a node, by the
## divergence theorem in world space. Independent of what the bake reports.
func _mesh_stats(node: Node) -> Dictionary:
	var tris := 0
	var volume := 0.0
	var meshes := 0
	for child in _walk(node):
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		meshes += 1
		var xf: Transform3D = mi.global_transform
		for s in range(mi.mesh.get_surface_count()):
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var raw_verts = arrays[Mesh.ARRAY_VERTEX]
			if not (raw_verts is PackedVector3Array):
				continue
			var verts: PackedVector3Array = raw_verts
			var raw_idx = arrays[Mesh.ARRAY_INDEX]
			var idx: PackedInt32Array = (
				raw_idx if raw_idx is PackedInt32Array else PackedInt32Array()
			)
			if idx.is_empty():
				var i := 0
				while i + 2 < verts.size():
					volume += _tet(xf * verts[i], xf * verts[i + 1], xf * verts[i + 2])
					tris += 1
					i += 3
			else:
				var j := 0
				while j + 2 < idx.size():
					volume += _tet(
						xf * verts[idx[j]], xf * verts[idx[j + 1]], xf * verts[idx[j + 2]]
					)
					tris += 1
					j += 3
	return {"tris": tris, "volume": absf(volume), "meshes": meshes}


func _tet(a: Vector3, b: Vector3, c: Vector3) -> float:
	return a.dot(b.cross(c)) / 6.0


func _walk(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for child in node.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func _collision_shapes(node: Node) -> int:
	var n := 0
	for child in _walk(node):
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			n += 1
	return n


## One 64-unit box. The baked mesh should enclose the same 262144 units of space
## the draft brush does.
func _a_box_bakes_to_a_box() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	await frame()

	var ok: bool = await root.bake_dirty()
	await frame()
	var stats := _mesh_stats(root.baked_container)
	note("bake_dirty returned", ok)
	note("last bake status", root.get_last_bake_status())
	note(
		"baked geometry",
		"%d mesh(es), %d triangles, volume %.0f" % [stats["meshes"], stats["tris"], stats["volume"]]
	)
	note("collision shapes", _collision_shapes(root.baked_container))

	if not ok:
		flag(
			"baking a level with one default box did not succeed",
			"status %s" % root.get_last_bake_status()
		)
		return
	if int(stats["meshes"]) == 0:
		flag("a bake that reported success produced no mesh")
		return
	if absf(float(stats["volume"]) - 262144.0) > 262144.0 * 0.02:
		flag(
			"the baked mesh does not enclose the volume of the brush it came from",
			"draft box is 64^3 = 262144; the baked mesh encloses %.0f" % stats["volume"]
		)

	# Baking must not consume the draft.
	note("draft brushes after the bake", root.brush_system.get_live_brush_count())
	if root.brush_system.get_live_brush_count() != 1:
		flag(
			"the bake changed the draft brush count",
			"1 before, %d after" % root.brush_system.get_live_brush_count()
		)
	for problem in HFVibe.check_invariants(root):
		flag("after a bake: %s" % problem)


## The same level baked twice. Nothing changed between them, so nothing about
## the result should differ -- and the second bake must not stack a second copy
## of the geometry on the first.
func _baking_twice() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	box(root, Vector3(32, 96, 32), Vector3(160, 0, 0))
	await frame()

	await root.bake_dirty()
	await frame()
	var first := _mesh_stats(root.baked_container)
	var first_shapes := _collision_shapes(root.baked_container)

	await root.bake_dirty()
	await frame()
	var second := _mesh_stats(root.baked_container)
	var second_shapes := _collision_shapes(root.baked_container)

	note("first bake", first)
	note("second bake", second)
	note("collision shapes", "%d -> %d" % [first_shapes, second_shapes])
	if HFVibe.canonical(first) != HFVibe.canonical(second):
		flag(
			"baking the same unchanged level twice gives a different result",
			"first %s, second %s" % [first, second]
		)
	if first_shapes != second_shapes:
		flag(
			"a second bake of an unchanged level changed the collision shape count",
			"%d -> %d" % [first_shapes, second_shapes]
		)


## `bake_visible_only` is the flag that says "leave the hidden brushes out". So
## with it off, a brush hidden by its visgroup should still be baked.
##
## Two separate roots, so a bake-dirty cache cannot explain the answer.
func _bake_visible_only() -> void:
	for visible_only in [true, false]:
		var root: Node3D = await fresh_root()
		box(root, Vector3(64, 64, 64))
		var hidden := box(root, Vector3(64, 64, 64), Vector3(256, 0, 0))
		root.create_visgroup("Hidden")
		root.add_selection_to_visgroup("Hidden", [hidden])
		root.set_visgroup_visible("Hidden", false)
		await frame()
		root.bake_visible_only = visible_only
		await root.bake_dirty()
		await frame()
		var stats := _mesh_stats(root.baked_container)
		note(
			"bake_visible_only = %s" % visible_only,
			(
				"the hidden brush is visible: %s; baked %d triangles, volume %.0f across %d mesh(es)"
				% [hidden.visible, stats["tris"], stats["volume"], stats["meshes"]]
			)
		)
		# Two 64 boxes are 524288 units of space. One is 262144.
		if not visible_only and absf(float(stats["volume"]) - 524288.0) > 1000.0:
			flag(
				"a brush hidden by its visgroup is left out of the bake even with bake_visible_only off",
				(
					"the level holds two 64-unit boxes, one of them in a hidden visgroup. With bake_visible_only = false the bake should contain both -- 524288 units of space -- and it encloses %.0f across %d triangles, which is one box. The flag that is meant to control this has no effect in either position."
					% [stats["volume"], stats["tris"]]
				)
			)
		note("draft brushes after the bake", root.brush_system.get_live_brush_count())
		for problem in HFVibe.check_invariants(root):
			flag("after baking with bake_visible_only = %s: %s" % [visible_only, problem])


## Flipping a bake setting and baking again. Nothing about the *brushes* changed,
## so nothing is dirty -- but the output should still change, because the setting
## that decides what goes into the output did.
func _rebaking_after_a_bake_setting_changes() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	var hidden := box(root, Vector3(64, 64, 64), Vector3(256, 0, 0))
	root.create_visgroup("Hidden")
	root.add_selection_to_visgroup("Hidden", [hidden])
	root.set_visgroup_visible("Hidden", false)
	await frame()

	root.bake_visible_only = true
	await root.bake_dirty()
	await frame()
	var excluded := _mesh_stats(root.baked_container)
	note("bake_dirty with bake_visible_only = true", excluded)

	# The mapper changes their mind and bakes again.
	root.bake_visible_only = false
	await root.bake_dirty()
	await frame()
	var after_flip := _mesh_stats(root.baked_container)
	note("bake_dirty again with bake_visible_only = false", after_flip)

	# And the full bake, for the comparison.
	await root.bake(false, false)
	await frame()
	var full := _mesh_stats(root.baked_container)
	note("a full bake() with the same setting", full)

	if (
		HFVibe.canonical(after_flip) == HFVibe.canonical(excluded)
		and HFVibe.canonical(full) != HFVibe.canonical(excluded)
	):
		known(
			376,
			"changing a bake setting does not dirty anything, so the next bake silently returns the old result",
			(
				"with bake_visible_only = true the bake holds %d triangles. Setting it to false and baking again gives the same %d -- the hidden brush is still missing. A full bake() with that setting gives %d, which is the right answer. Nothing between the setting and the dirty set connects them, so the mapper changes the flag, bakes, and sees no change."
				% [excluded["tris"], after_flip["tris"], full["tris"]]
			)
		)


## The brush `merge_vertices()` can leave behind (#366) is live, saved and
## exported. What the bake does with it is the last question about it.
func _a_brush_with_no_faces_in_the_bake() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	var broken := box(root, Vector3(64, 64, 64), Vector3(256, 0, 0))
	broken.faces.clear()
	await frame()

	var ok: bool = await root.bake_dirty()
	await frame()
	var stats := _mesh_stats(root.baked_container)
	note("baking a level that holds a faceless brush", "returned %s, %s" % [ok, stats])
	note("status", root.get_last_bake_status())
	if not ok:
		flag(
			"one faceless brush stops the whole level baking",
			(
				"the level holds one good box and one brush with no faces, and the bake returned %s (status %s) -- a brush the mapper cannot see takes the bake down with it"
				% [ok, root.get_last_bake_status()]
			)
		)
	for problem in HFVibe.check_invariants(root):
		flag("after baking with a faceless brush: %s" % problem)
