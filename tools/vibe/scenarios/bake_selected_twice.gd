@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What Bake Selected leaves behind of the brushes it bakes.
##
## Bake Selected bakes the selected brushes and adds the result to the baked
## container beside what is there (`_bake_selected_impl()`, "Merge into
## existing baked container rather than replacing it"). The guide says
## previously baked geometry is preserved, which is right for the brushes that
## were not selected. This asks about the ones that were: after a full bake, a
## wall is moved and Bake Selected is pressed on it, then pressed again. Where
## is there baked collision, and how many baked copies of the wall are there?


func id() -> String:
	return "bake-selected-twice"


func summary() -> String:
	return "what Bake Selected leaves of the selected brush's earlier bake, after a move and a second press"


func run() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	var wall = box(root, Vector3(4, 3, 0.3), Vector3(0, 1.5, 0))
	var wall_id := str(wall.get_meta("brush_id", ""))
	await root.bake(false, false)
	await frame()
	note("after a full bake", _report(root))

	root.nudge_brushes_by_id([wall_id], Vector3(0, 0, 3))
	await frame()
	await root.bake_selected([root.find_brush_by_id(wall_id)])
	await frame()
	var moved := _report(root)
	note("wall moved 3 along z, then Bake Selected on it", moved)

	await root.bake_selected([root.find_brush_by_id(wall_id)])
	await frame()
	var twice := _report(root)
	note("Bake Selected on it again, nothing changed", twice)

	# Drafts carry their own picking collision; take them out so a ray meets
	# only what a game would have.
	for child in root.draft_brushes_node.get_children():
		root.draft_brushes_node.remove_child(child)
		child.queue_free()
	await frame()
	await frame()
	var old_spot := _ray(root, Vector3(0, 1.5, -2), Vector3(0, 1.5, 2))
	note("a ray across the wall's old place (z 0) hits", old_spot)
	if old_spot.has("position") and absf((old_spot["position"] as Vector3).z) < 0.5:
		flag(
			"Bake Selected leaves the selected brush's old baked wall where the brush used to be",
			(
				(
					"a wall baked in full at z 0, moved to z 3, then Bake Selected on it. The baked "
					+ "level now has walls at both places: a ray across z 0 hits %s."
				)
				% old_spot
			)
		)
	else:
		note("  nothing is baked where the wall used to be")
	if moved != twice:
		flag(
			"a second Bake Selected with nothing changed changes the bake",
			(
				(
					"wall-sized meshes after one Bake Selected %d, after a second with nothing changed "
					+ "%d; collision bodies %d then %d"
				)
				% [
					int(moved["wall-sized meshes"]),
					int(twice["wall-sized meshes"]),
					int(moved["bodies"]),
					int(twice["bodies"]),
				]
			)
		)
	else:
		note("  a second press leaves the bake as the first did")
	await drop_root(root)
	await _a_brush_drawn_after_the_bake()


## A brush the full bake never held is baked beside it, and a second press after
## a move replaces that selection rather than adding to it.
func _a_brush_drawn_after_the_bake() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	await root.bake(false, false)
	await frame()
	var pillar = box(root, Vector3(1, 3, 1), Vector3(4, 1.5, 0))
	var pillar_id := str(pillar.get_meta("brush_id", ""))
	await root.bake_selected([pillar])
	await frame()
	var first := _report(root)
	note("a pillar drawn after the full bake, then Bake Selected on it", first)
	root.nudge_brushes_by_id([pillar_id], Vector3(0, 0, 3))
	await root.bake_selected([root.find_brush_by_id(pillar_id)])
	await frame()
	var again := _report(root)
	note("the pillar moved 3 along z, then Bake Selected on it again", again)
	if int(again["selection nodes"]) != 1 or again != first:
		flag(
			"Bake Selected on a brush it baked before adds to the bake instead of replacing it",
			"after the first press %s, after the second %s" % [first, again]
		)
	else:
		note("  the second press replaced the first selection")
	await drop_root(root)


func _report(root: Node3D) -> Dictionary:
	var container := root.get_node_or_null("BakedGeometry")
	var walls := 0
	var bodies := 0
	var selections := 0
	if container:
		for n in container.find_children("*", "", true, false):
			if str(n.name).begins_with("BakedSelection_"):
				selections += 1
			if n is StaticBody3D:
				bodies += 1
			if n is MeshInstance3D and (n as MeshInstance3D).mesh:
				var box_size: Vector3 = (n as MeshInstance3D).mesh.get_aabb().size
				# The wall is 4 x 3 x 0.3; the floor is 12 wide.
				if box_size.x < 6.0 and box_size.y > 2.0:
					walls += 1
	return {"wall-sized meshes": walls, "bodies": bodies, "selection nodes": selections}


func _ray(root: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return space.intersect_ray(q)
