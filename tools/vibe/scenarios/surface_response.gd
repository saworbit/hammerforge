@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What the game can tell about the surface the player is standing on.
##
## Texturing a level is not only about how it looks. In a shipped game the
## material under the player's feet decides the footstep sound, the impact decal,
## the bullet spark, the friction of a slope and whether a grenade bounces. All
## of that is a question the running game asks of the collision it just hit, and
## it can only be answered if the bake put the answer there.
##
## `bake-materials` checks that per-face materials reach the baked *mesh*. This
## asks the other half: what reaches the baked *collision*, which is the thing a
## raycast and a `move_and_slide()` actually touch.


func id() -> String:
	return "surface-response"


func summary() -> String:
	return "what a raycast can learn about the material of the surface it hit"


func run() -> void:
	await _what_a_raycast_gets_back()
	await _what_the_collision_body_carries()
	await _each_collision_mode()


func _palette(root: Node3D) -> void:
	for pair in [
		["metal", Color(0.7, 0.7, 0.8)],
		["wood", Color(0.5, 0.3, 0.1)],
		["stone", Color(0.4, 0.4, 0.4)]
	]:
		var mat := StandardMaterial3D.new()
		mat.resource_name = str(pair[0])
		mat.albedo_color = pair[1]
		root.material_manager.materials.append(mat)


## Three floor slabs side by side, one material each: a metal walkway, a wooden
## floor and a stone floor. The thing every game wants to tell apart.
func _three_floors(root: Node3D) -> Array:
	var made: Array = []
	for i in 3:
		var b = box(root, Vector3(4, 0.4, 4), Vector3(i * 5.0, -0.2, 0))
		made.append(b)
	return made


func _bodies(node: Node, out: Array) -> Array:
	if node is StaticBody3D or node is Area3D:
		out.append(node)
	for c in node.get_children():
		_bodies(c, out)
	return out


func _what_a_raycast_gets_back() -> void:
	var root: Node3D = await fresh_root()
	_palette(root)
	var floors := _three_floors(root)
	await frame()
	for i in floors.size():
		for face in floors[i].faces:
			if face:
				face.material_idx = i
	await root.bake(false, false)
	await frame()
	# Drop the live brushes, or the ray finds the editor's picking collision.
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			root.draft_brushes_node.remove_child(child)
			child.queue_free()
	await frame()
	await frame()

	var space := root.get_world_3d().direct_space_state
	var rows: Array = []
	for i in 3:
		var q := PhysicsRayQueryParameters3D.new()
		q.from = Vector3(i * 5.0, 2, 0)
		q.to = Vector3(i * 5.0, -2, 0)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			rows.append({"slab": i, "hit": false})
			continue
		var collider: Object = hit.get("collider")
		var shape_index: int = int(hit.get("shape", -1))
		(
			rows
			. append(
				{
					"slab": i,
					"material_the_mapper_gave_it": ["metal", "wood", "stone"][i],
					"collider": collider.name if collider else "-",
					"collider_meta": collider.get_meta_list() if collider else [],
					"shape_index": shape_index,
				}
			)
		)
	note("what a raycast onto each slab returns", rows)
	var distinct: Dictionary = {}
	for r in rows:
		distinct[str(r.get("collider", "-"))] = true
	note("distinct colliders across three differently-textured floors", distinct.keys())
	if distinct.size() == 1:
		flag(
			"the baked collision carries nothing that names the material of the surface hit",
			(
				"Three floors, textured metal, wood and stone. The bake puts all of it in one "
				+ "StaticBody3D with no metadata, so a raycast comes back with the same "
				+ "collider, the same shape index range and nothing to distinguish them. Every "
				+ "footstep sound, impact decal, bullet spark and surface-specific reaction in "
				+ "a shipped game is decided by exactly this lookup, and per-face materials -- "
				+ "the one piece of information the mapper spent the evening authoring -- are "
				+ "the part that does not survive to runtime. The mesh keeps them; the "
				+ "collision does not."
			)
		)


func _what_the_collision_body_carries() -> void:
	var root: Node3D = await fresh_root()
	_palette(root)
	_three_floors(root)
	await frame()
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		return
	for b in _bodies(container, []):
		note(
			"body '%s'" % b.name,
			(
				"class=%s meta=%s physics_material=%s"
				% [
					b.get_class(),
					b.get_meta_list(),
					b.get("physics_material_override"),
				]
			)
		)
	note(
		"physics_material_override on a baked body",
		(
			"never set anywhere in the addon, so friction and bounce are Godot's defaults "
			+ "for every surface in every level -- no ice, no mud, no rubber"
		)
	)


## The three collision modes, because a per-brush convex mode would at least give
## a raycast one shape per brush to key off.
func _each_collision_mode() -> void:
	for mode in [0, 1, 2]:
		var root: Node3D = await fresh_root()
		_palette(root)
		var floors := _three_floors(root)
		await frame()
		for i in floors.size():
			for face in floors[i].faces:
				if face:
					face.material_idx = i
		root.bake_collision_mode = mode
		await root.bake(false, false)
		await frame()
		var container := root.get_node_or_null("BakedGeometry")
		var shapes := 0
		var stack: Array = [container] if container else []
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is CollisionShape3D:
				shapes += 1
			for c in n.get_children():
				stack.append(c)
		note(
			"bake_collision_mode = %d" % mode,
			"%d CollisionShape3D for 3 differently-textured floor brushes" % shapes
		)
