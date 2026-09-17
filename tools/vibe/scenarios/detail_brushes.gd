@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What tying a brush to `func_detail` costs.
##
## `func_detail` is the class a mapper reaches for constantly, because its own
## description tells them to: "Geometry the structural bake skips. For trim and
## clutter that should not cut the world." Trim and clutter is most of a
## finished map — pipes, crates, skirting, light fittings, railings — so on a
## real level this class is applied to hundreds of brushes, and it is applied
## *because* it is supposed to be the cheap option.
##
## This scenario builds the same room twice, once with the clutter left
## structural and once with it tied to `func_detail`, and compares what the bake
## makes of the two.


func id() -> String:
	return "detail-brushes"


func summary() -> String:
	return "what tying clutter to func_detail does to the node count and the draw calls"


const CLUTTER := 80


func _counts(node: Node, out: Dictionary) -> Dictionary:
	out[node.get_class()] = int(out.get(node.get_class(), 0)) + 1
	if node is MeshInstance3D and node.mesh:
		out["surfaces"] = int(out.get("surfaces", 0)) + node.mesh.get_surface_count()
	for c in node.get_children():
		_counts(c, out)
	return out


## A room with clutter in it. `detail` decides whether the clutter is tied.
func _room(root: Node3D, detail: bool) -> void:
	box(root, Vector3(20, 0.2, 20), Vector3(0, -0.1, 0))
	box(root, Vector3(20, 3, 0.3), Vector3(0, 1.5, -10))
	box(root, Vector3(20, 3, 0.3), Vector3(0, 1.5, 10))
	box(root, Vector3(0.3, 3, 20), Vector3(-10, 1.5, 0))
	box(root, Vector3(0.3, 3, 20), Vector3(10, 1.5, 0))
	var ids: Array = []
	for i in CLUTTER:
		var b = box(
			root,
			Vector3(0.5, 0.5, 0.5),
			Vector3(-9.0 + (i % 10) * 2.0, 0.25, -7.0 + (i / 10) * 2.0)
		)
		ids.append(str(b.brush_id))
	if detail:
		root.tie_brushes_to_entity(ids, "func_detail", "")


func run() -> void:
	await _structural_against_detail()
	await _what_a_map_sized_amount_of_detail_costs()


func _structural_against_detail() -> void:
	var results: Dictionary = {}
	for detail in [false, true]:
		var root: Node3D = await fresh_root()
		_room(root, detail)
		await frame()
		var t := Time.get_ticks_msec()
		await root.bake(false, false)
		await frame()
		var ms := Time.get_ticks_msec() - t
		var container := root.get_node_or_null("BakedGeometry")
		if container == null:
			flag("detail-brushes: nothing baked (detail=%s)" % detail)
			continue
		var counts := _counts(container, {})
		counts["bake_ms"] = ms
		results[detail] = counts
		note("clutter tied to func_detail = %s" % detail, counts)

	if not results.has(false) or not results.has(true):
		return
	var plain: Dictionary = results[false]
	var tied: Dictionary = results[true]
	for key in ["MeshInstance3D", "StaticBody3D", "CollisionShape3D", "surfaces"]:
		note("%s: structural %s -> detail %s" % [key, plain.get(key, 0), tied.get(key, 0)], "")
	var plain_meshes := int(plain.get("MeshInstance3D", 0))
	var tied_meshes := int(tied.get("MeshInstance3D", 0))
	if tied_meshes > plain_meshes + 4:
		flag(
			(
				"tying %d clutter brushes to func_detail turns %d baked mesh(es) into %d"
				% [CLUTTER, plain_meshes, tied_meshes]
			),
			(
				(
					"`func_detail`'s own description is 'Geometry the structural bake skips. For "
					+ "trim and clutter that should not cut the world', which is what a mapper "
					+ "applies to every crate, pipe and railing in a finished map -- and applies "
					+ "*because* it reads as the cheap option. `_append_nonstructural_brushes()` "
					+ "gives each one its own MeshInstance3D, its own StaticBody3D and its own "
					+ "CollisionShape3D, with no grouping by material and no merge, so the same "
					+ "%d boxes go from %d draw call(s) to %d. Detail brushes are the ones there "
					+ "are most of; they are the ones being merged least.\n\n"
					+ "The structural path already groups faces by material into one surface. "
					+ "Running the non-structural brushes through the same grouping -- one "
					+ "holder, grouped by material, with the per-brush split kept only for the "
					+ "ones that carry an entity name or I/O the runtime has to find -- is the "
					+ "same code applied twice."
				)
				% [CLUTTER, plain_meshes, tied_meshes]
			)
		)
	note("bake time, structural", "%d ms" % int(plain.get("bake_ms", 0)))
	note("bake time, detail", "%d ms" % int(tied.get("bake_ms", 0)))


## The curve, so the report says how this scales.
func _what_a_map_sized_amount_of_detail_costs() -> void:
	for n in [20, 80, 300]:
		var root: Node3D = await fresh_root()
		var ids: Array = []
		for i in n:
			var b = box(root, Vector3(0.4, 0.4, 0.4), Vector3((i % 20) * 1.0, 0.2, (i / 20) * 1.0))
			ids.append(str(b.brush_id))
		root.tie_brushes_to_entity(ids, "func_detail", "")
		await frame()
		var t := Time.get_ticks_msec()
		await root.bake(false, false)
		await frame()
		var ms := Time.get_ticks_msec() - t
		var counts := _counts(root.get_node_or_null("BakedGeometry"), {})
		note(
			"%d func_detail brushes" % n,
			(
				"%d MeshInstance3D, %d StaticBody3D, %d CollisionShape3D, bake %d ms"
				% [
					int(counts.get("MeshInstance3D", 0)),
					int(counts.get("StaticBody3D", 0)),
					int(counts.get("CollisionShape3D", 0)),
					ms,
				]
			)
		)
