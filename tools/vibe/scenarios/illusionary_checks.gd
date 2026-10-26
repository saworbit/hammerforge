@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What the spawn check makes of a func_illusionary brush, which bakes no collision.
##
## `func_illusionary` (#1914) bakes its mesh and no collision: cloth, a bead
## curtain, a light shaft, a fake floor over a pit. The spawn check reads the
## brushes as well as the baked collision (`_brush_floor_under()`), so it can
## approve a spawn before the first bake, and it leaves out triggers, which have
## no collision either. This asks two things of it: a spawn standing on an
## illusionary platform over a real floor, which the player falls through; and a
## spawn standing on the real floor inside an illusionary light shaft, where the
## player stands fine. The verdict that counts is the one with the drafts in the
## scene, as the editor has them; the one with them taken out is noted beside it.

const PLATFORM_TOP := 2.1


func id() -> String:
	return "illusionary-checks"


func summary() -> String:
	return "what the spawn check makes of a func_illusionary brush, which bakes no collision"


func expected_issues() -> Array[int]:
	return [1962]


func run() -> void:
	await _case("fake floor", Vector3(0, 0, 0))
	await _case("light shaft", Vector3(60, 0, 0))


func _case(kind: String, at: Vector3) -> void:
	var root: Node3D = await fresh_root("IllusionaryLevel")
	box(root, Vector3(10, 0.2, 10), at + Vector3(0, -0.1, 0))
	var feet := 0.0
	var b
	if kind == "fake floor":
		b = box(root, Vector3(3, 0.2, 3), at + Vector3(0, PLATFORM_TOP - 0.1, 0))
		feet = PLATFORM_TOP
	else:
		b = box(root, Vector3(2, 4, 2), at + Vector3(0, 2, 0))
	root.tie_brushes_to_entity([str(b.get_meta("brush_id", ""))], "func_illusionary", "illusion")
	var spawn: Node3D = root.spawn_system.create_default_spawn()
	spawn.global_position = at + Vector3(0, feet + 0.1, 0)
	await root.bake(true, false, 0)
	await frame()
	await physics_frame()
	await physics_frame()
	var with_drafts: Dictionary = root.spawn_system.validate_spawn(spawn, 0)
	for child in root.draft_brushes_node.get_children():
		root.draft_brushes_node.remove_child(child)
		child.queue_free()
	await frame()
	await physics_frame()
	await physics_frame()
	var game_only: Dictionary = root.spawn_system.validate_spawn(spawn, 0)
	var ray := _ray_down(root, at + Vector3(0, feet + 1.0, 0))
	note("%s, drafts in the scene" % kind, _said(with_drafts))
	note("%s, drafts taken out" % kind, _said(game_only))
	note("%s: what the baked collision has under the spawn" % kind, ray)
	if kind == "fake floor":
		if bool(with_drafts.get("valid", false)) and (with_drafts["issues"] as Array).is_empty():
			known(
				1962,
				"the spawn check approves a spawn standing on a func_illusionary platform",
				(
					"a spawn at y %.1f on a 3 x 3 func_illusionary platform over a floor at y 0 validates clean (%s), and the baked collision under it is %s. The player falls %.1f to the floor, or into the pit a fake floor is built over."
					% [feet + 0.1, _said(with_drafts), ray, feet]
				)
			)
	else:
		if not bool(with_drafts.get("valid", true)):
			known(
				1962,
				"the spawn check refuses a spawn inside a func_illusionary light shaft",
				(
					"a spawn standing on the floor inside a 2 x 4 x 2 func_illusionary brush says %s. It bakes no collision, and the player stands there fine."
					% _said(with_drafts)
				)
			)
	await drop_root(root)


func physics_frame() -> void:
	await _tree.physics_frame


func _said(validation: Dictionary) -> String:
	return "valid %s, issues %s" % [validation.get("valid"), Array(validation.get("issues", []))]


func _ray_down(root: Node3D, from: Vector3) -> String:
	var space := root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 10.0)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return "nothing"
	return "a hit at y %.2f" % (hit["position"] as Vector3).y
